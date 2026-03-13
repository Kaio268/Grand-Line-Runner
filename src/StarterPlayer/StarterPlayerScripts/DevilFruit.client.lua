local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local HazardUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))
local HazardRuntime = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))

local player = Players.LocalPlayer

local function waitForChildSafe(parent, childName, timeout)
	local deadline = os.clock() + (timeout or 15)
	local child = parent:FindFirstChild(childName)

	while not child and os.clock() < deadline do
		task.wait(0.1)
		child = parent:FindFirstChild(childName)
	end

	if child then
		return child
	end

	error(string.format("[DevilFruit] Timed out waiting for %s.%s", parent:GetFullName(), childName))
end

local remotes = waitForChildSafe(ReplicatedStorage, "Remotes", 15)
local requestRemote = waitForChildSafe(remotes, "DevilFruitAbilityRequest", 15)
local stateRemote = waitForChildSafe(remotes, "DevilFruitAbilityState", 15)
local effectRemote = waitForChildSafe(remotes, "DevilFruitAbilityEffect", 15)

local localCooldowns = {}
local suppressedParts = {}
local activeFireBursts = {}
local getFruitFolder
local getEquippedFruit
local cooldownHud = {
	CurrentFruit = nil,
	Gui = nil,
	Panel = nil,
	FruitLabel = nil,
	List = nil,
	Rows = {},
}
local clearCooldownRows

local HUD_REFRESH_INTERVAL = 0.05
local nextHudRefreshAt = 0

local function formatAbilityName(abilityName)
	return tostring(abilityName):gsub("(%l)(%u)", "%1 %2")
end

local function formatCooldownTime(seconds)
	local remaining = math.max(0, tonumber(seconds) or 0)
	if remaining >= 10 then
		return string.format("%.0fs", math.ceil(remaining))
	end

	return string.format("%.1fs", math.ceil(remaining * 10) / 10)
end

local function getPlayerGui()
	return waitForChildSafe(player, "PlayerGui", 15)
end

local function ensureStroke(instance, color, transparency, thickness)
	local stroke = instance:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = instance
	end

	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	return stroke
end

local function ensureCorner(instance, radius)
	local corner = instance:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = instance
	end

	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function getOrderedAbilities(fruitName)
	local fruit = DevilFruitConfig.GetFruit(fruitName)
	if not fruit or not fruit.Abilities then
		return {}
	end

	local orderedAbilities = {}
	for abilityName, abilityConfig in pairs(fruit.Abilities) do
		table.insert(orderedAbilities, {
			Name = abilityName,
			Config = abilityConfig,
		})
	end

	table.sort(orderedAbilities, function(a, b)
		local aCooldown = tonumber(a.Config.Cooldown) or math.huge
		local bCooldown = tonumber(b.Config.Cooldown) or math.huge
		if aCooldown == bCooldown then
			return a.Name < b.Name
		end

		return aCooldown < bCooldown
	end)

	return orderedAbilities
end

local function shouldShowCooldownHud(fruitName)
	return DevilFruitConfig.GetFruit(fruitName) ~= nil
end

local function ensureCooldownHud()
	if cooldownHud.Panel and cooldownHud.Panel.Parent then
		return cooldownHud
	end

	local playerGui = getPlayerGui()
	local screenGui = playerGui:FindFirstChild("DevilFruitHUD")
	if screenGui and not screenGui:IsA("ScreenGui") then
		screenGui:Destroy()
		screenGui = nil
	end

	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "DevilFruitHUD"
		screenGui.Parent = playerGui
	end

	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 25
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = screenGui:FindFirstChild("CooldownPanel")
	if panel and not panel:IsA("Frame") then
		panel:Destroy()
		panel = nil
	end

	if not panel then
		panel = Instance.new("Frame")
		panel.Name = "CooldownPanel"
		panel.AnchorPoint = Vector2.new(1, 1)
		panel.Position = UDim2.new(1, -24, 1, -24)
		panel.Size = UDim2.fromOffset(270, 0)
		panel.AutomaticSize = Enum.AutomaticSize.Y
		panel.BackgroundColor3 = Color3.fromRGB(22, 18, 15)
		panel.BackgroundTransparency = 0.18
		panel.BorderSizePixel = 0
		panel.Visible = false
		panel.Parent = screenGui

		ensureCorner(panel, 14)
		ensureStroke(panel, Color3.fromRGB(255, 151, 53), 0.15, 1.5)

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = panel

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = panel

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0, 16)
		title.Font = Enum.Font.GothamBold
		title.Text = "DEVIL FRUIT"
		title.TextColor3 = Color3.fromRGB(255, 205, 160)
		title.TextSize = 12
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.LayoutOrder = 1
		title.Parent = panel

		local fruitLabel = Instance.new("TextLabel")
		fruitLabel.Name = "FruitName"
		fruitLabel.BackgroundTransparency = 1
		fruitLabel.Size = UDim2.new(1, 0, 0, 22)
		fruitLabel.Font = Enum.Font.GothamBold
		fruitLabel.Text = ""
		fruitLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		fruitLabel.TextSize = 18
		fruitLabel.TextWrapped = true
		fruitLabel.TextXAlignment = Enum.TextXAlignment.Left
		fruitLabel.LayoutOrder = 2
		fruitLabel.Parent = panel

		local list = Instance.new("Frame")
		list.Name = "AbilityList"
		list.BackgroundTransparency = 1
		list.Size = UDim2.new(1, 0, 0, 0)
		list.AutomaticSize = Enum.AutomaticSize.Y
		list.LayoutOrder = 3
		list.Parent = panel

		local listLayout = Instance.new("UIListLayout")
		listLayout.Padding = UDim.new(0, 6)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = list

	end

	local fruitLabel = panel and panel:FindFirstChild("FruitName")
	local list = panel and panel:FindFirstChild("AbilityList")
	if not fruitLabel or not fruitLabel:IsA("TextLabel") or not list or not list:IsA("Frame") then
		panel:Destroy()
		cooldownHud.Panel = nil
		return ensureCooldownHud()
	end

	cooldownHud.Gui = screenGui
	cooldownHud.Panel = panel
	cooldownHud.FruitLabel = fruitLabel
	cooldownHud.List = list
	cooldownHud.Rows = cooldownHud.Rows or {}

	return cooldownHud
end

local function setCooldownHudVisible(isVisible)
	ensureCooldownHud()
	cooldownHud.Gui.Enabled = isVisible
	cooldownHud.Panel.Visible = isVisible
end

local function hideCooldownHud()
	setCooldownHudVisible(false)
	cooldownHud.CurrentFruit = nil
	clearCooldownRows()

	if cooldownHud.FruitLabel then
		cooldownHud.FruitLabel.Text = ""
	end
end

clearCooldownRows = function()
	for _, row in pairs(cooldownHud.Rows) do
		if row.Container and row.Container.Parent then
			row.Container:Destroy()
		end
	end

	cooldownHud.Rows = {}
end

local function createCooldownRow(layoutOrder, abilityName, abilityConfig)
	local row = Instance.new("Frame")
	row.Name = abilityName
	row.Size = UDim2.new(1, 0, 0, 54)
	row.BackgroundColor3 = Color3.fromRGB(35, 28, 24)
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.Parent = cooldownHud.List

	ensureCorner(row, 12)
	ensureStroke(row, Color3.fromRGB(255, 164, 82), 0.45, 1)

	local keyBadge = Instance.new("TextLabel")
	keyBadge.Name = "Key"
	keyBadge.AnchorPoint = Vector2.new(0, 0.5)
	keyBadge.Position = UDim2.new(0, 10, 0.5, -6)
	keyBadge.Size = UDim2.fromOffset(34, 24)
	keyBadge.BackgroundColor3 = Color3.fromRGB(255, 124, 32)
	keyBadge.BorderSizePixel = 0
	keyBadge.Font = Enum.Font.GothamBold
	keyBadge.Text = abilityConfig.KeyCode.Name
	keyBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
	keyBadge.TextSize = 14
	keyBadge.Parent = row

	ensureCorner(keyBadge, 8)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 56, 0, 8)
	nameLabel.Size = UDim2.new(1, -136, 0, 18)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = formatAbilityName(abilityName)
	nameLabel.TextColor3 = Color3.fromRGB(255, 243, 231)
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.AnchorPoint = Vector2.new(1, 0)
	statusLabel.Position = UDim2.new(1, -10, 0, 8)
	statusLabel.Size = UDim2.new(0, 72, 0, 18)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Text = "READY"
	statusLabel.TextColor3 = Color3.fromRGB(116, 255, 161)
	statusLabel.TextSize = 13
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.Parent = row

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.BackgroundTransparency = 1
	detailLabel.Position = UDim2.new(0, 56, 0, 27)
	detailLabel.Size = UDim2.new(1, -68, 0, 12)
	detailLabel.Font = Enum.Font.Gotham
	detailLabel.Text = string.format("Cooldown %.1fs", tonumber(abilityConfig.Cooldown) or 0)
	detailLabel.TextColor3 = Color3.fromRGB(204, 186, 175)
	detailLabel.TextSize = 11
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.Parent = row

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 10, 1, -8)
	bar.Size = UDim2.new(1, -20, 0, 6)
	bar.BackgroundColor3 = Color3.fromRGB(64, 50, 44)
	bar.BorderSizePixel = 0
	bar.Parent = row

	ensureCorner(bar, 999)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(116, 255, 161)
	fill.BorderSizePixel = 0
	fill.Parent = bar

	ensureCorner(fill, 999)

	return {
		Container = row,
		Status = statusLabel,
		Fill = fill,
		Detail = detailLabel,
		Cooldown = tonumber(abilityConfig.Cooldown) or 0,
	}
end

local function rebuildCooldownHud(fruitName)
	ensureCooldownHud()
	clearCooldownRows()

	cooldownHud.CurrentFruit = fruitName
	local fruit = DevilFruitConfig.GetFruit(fruitName)
	if not fruit then
		hideCooldownHud()
		return
	end

	setCooldownHudVisible(true)
	cooldownHud.FruitLabel.Text = fruit.DisplayName or fruitName

	local orderedAbilities = getOrderedAbilities(fruitName)
	for index, entry in ipairs(orderedAbilities) do
		cooldownHud.Rows[entry.Name] = createCooldownRow(index, entry.Name, entry.Config)
	end
end

local function updateCooldownHud(forceRebuild)
	ensureCooldownHud()

	local fruitName = getEquippedFruit()
	if forceRebuild or fruitName ~= cooldownHud.CurrentFruit then
		rebuildCooldownHud(fruitName)
	end

	if not shouldShowCooldownHud(fruitName) then
		hideCooldownHud()
		return
	end

	setCooldownHudVisible(true)

	for abilityName, row in pairs(cooldownHud.Rows) do
		local readyAt = localCooldowns[abilityName] or 0
		local remaining = math.max(0, readyAt - os.clock())
		local total = math.max(row.Cooldown, 0.001)
		local progress = math.clamp(1 - (remaining / total), 0, 1)
		local isReady = remaining <= 0

		row.Status.Text = isReady and "READY" or ("CD " .. formatCooldownTime(remaining))
		row.Status.TextColor3 = isReady and Color3.fromRGB(116, 255, 161) or Color3.fromRGB(255, 190, 116)
		row.Detail.Text = isReady and "Move ready" or ("On cooldown for " .. formatCooldownTime(remaining))
		row.Fill.Size = UDim2.new(progress, 0, 1, 0)
		row.Fill.BackgroundColor3 = isReady and Color3.fromRGB(116, 255, 161) or Color3.fromRGB(255, 133, 44)
	end
end

getFruitFolder = function()
	return player:FindFirstChild("DevilFruit")
end

getEquippedFruit = function()
	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		return fruitAttribute
	end

	local fruitFolder = getFruitFolder()
	if fruitFolder then
		local equipped = fruitFolder:FindFirstChild("Equipped")
		if equipped and equipped:IsA("StringValue") then
			return equipped.Value
		end
	end

	return DevilFruitConfig.None
end

local function hookEquippedFruitValue(equippedValue)
	if not equippedValue or not equippedValue:IsA("StringValue") then
		return
	end

	if equippedValue:GetAttribute("__DevilFruitHudHooked") == true then
		return
	end

	equippedValue:SetAttribute("__DevilFruitHudHooked", true)
	equippedValue:GetPropertyChangedSignal("Value"):Connect(function()
		updateCooldownHud(true)
	end)
end

local function hookFruitFolderSignals()
	local fruitFolder = getFruitFolder()
	if not fruitFolder then
		return
	end

	local equippedValue = fruitFolder:FindFirstChild("Equipped")
	if equippedValue then
		hookEquippedFruitValue(equippedValue)
	end

	if fruitFolder:GetAttribute("__DevilFruitHudFolderHooked") == true then
		return
	end

	fruitFolder:SetAttribute("__DevilFruitHudFolderHooked", true)
	fruitFolder.ChildAdded:Connect(function(child)
		if child.Name == "Equipped" then
			hookEquippedFruitValue(child)
			updateCooldownHud(true)
		end
	end)
end

local function getAbilityForKeyCode(keyCode)
	local fruitName = getEquippedFruit()
	local fruit = DevilFruitConfig.GetFruit(fruitName)
	if not fruit or not fruit.Abilities then
		return nil, nil
	end

	for abilityName, abilityConfig in pairs(fruit.Abilities) do
		if abilityConfig.KeyCode == keyCode then
			return fruitName, abilityName
		end
	end

	return nil, nil
end

local function isLocallyReady(abilityName)
	local readyAt = localCooldowns[abilityName]
	if not readyAt then
		return true
	end

	return os.clock() >= readyAt
end

local function getCharacter()
	return player.Character
end

local function getRootPart()
	local character = getCharacter()
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getPlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function isDescendantOfClientWave(instance)
	local map = Workspace:FindFirstChild("Map")
	local waveFolder = map and map:FindFirstChild("WaveFolder")
	local clientWavesFolder = waveFolder and waveFolder:FindFirstChild("ClientWaves")
	if not clientWavesFolder then
		return false
	end

	return instance:IsDescendantOf(clientWavesFolder)
end

local function getWaveTemplate(instance)
	local current = instance
	while current and current.Parent and current.Parent.Name ~= "ClientWaves" do
		current = current.Parent
	end

	if not current then
		return nil
	end

	local wavesFolder = ReplicatedStorage:FindFirstChild("Waves")
	if not wavesFolder then
		return nil
	end

	return wavesFolder:FindFirstChild(current.Name)
end

local function getHazardContainer(instance)
	local root, hazardClass, hazardType, canFreeze, freezeBehavior = HazardUtils.GetHazardInfo(instance)
	if root then
		return root, hazardClass, hazardType, canFreeze, freezeBehavior
	end

	if isDescendantOfClientWave(instance) then
		local template = getWaveTemplate(instance)
		if template then
			local _, templateClass, templateType, templateCanFreeze, templateFreezeBehavior = HazardUtils.GetHazardInfo(template)
			if templateClass or templateType or templateCanFreeze or templateFreezeBehavior then
				local current = instance
				while current and current.Parent and current.Parent.Name ~= "ClientWaves" do
					current = current.Parent
				end

				return current or instance, templateClass, templateType, templateCanFreeze, templateFreezeBehavior
			end
		end
	end

	return nil, nil, nil, false, nil
end

local function suppressPart(part, untilTime)
	if not part or not part:IsA("BasePart") then
		return
	end

	local state = suppressedParts[part]
	if state then
		if untilTime > state.UntilTime then
			state.UntilTime = untilTime
		end
		return
	end

	suppressedParts[part] = {
		OriginalCanTouch = part.CanTouch,
		UntilTime = untilTime,
	}

	part.CanTouch = false
end

local function suppressHazard(container, untilTime)
	if not container then
		return
	end

	if container:IsA("BasePart") then
		suppressPart(container, untilTime)
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			suppressPart(descendant, untilTime)
		end
	end
end

local function restoreSuppressedParts(now)
	for part, state in pairs(suppressedParts) do
		if not part or not part.Parent then
			suppressedParts[part] = nil
		elseif now >= state.UntilTime then
			part.CanTouch = state.OriginalCanTouch
			suppressedParts[part] = nil
		end
	end
end

local function updateFireBursts()
	local now = os.clock()
	local rootPart = getRootPart()

	for i = #activeFireBursts, 1, -1 do
		local burst = activeFireBursts[i]
		if now >= burst.EndTime or not rootPart then
			table.remove(activeFireBursts, i)
		else
			-- Corridor hazards are client-created in this project, so Fire Burst
			-- suppresses nearby minor hazards locally after the server authorizes it.
			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			overlapParams.FilterDescendantsInstances = { player.Character }

			local nearbyParts = Workspace:GetPartBoundsInRadius(rootPart.Position, burst.Radius, overlapParams)
			for _, part in ipairs(nearbyParts) do
				local container, hazardClass = getHazardContainer(part)
				if container and hazardClass == "minor" then
					suppressHazard(container, burst.EndTime)
				end
			end
		end
	end

	restoreSuppressedParts(now)

	if #activeFireBursts > 0 then
		task.delay(0.05, updateFireBursts)
	end
end

local function startFireBurst(payload)
	local duration = tonumber(payload.Duration) or 0
	local radius = tonumber(payload.Radius) or 0
	if duration <= 0 or radius <= 0 then
		return
	end

	table.insert(activeFireBursts, {
		Radius = radius,
		EndTime = os.clock() + duration,
	})

	if #activeFireBursts == 1 then
		updateFireBursts()
	end
end

local function getProjectileDirection(direction, rootPart)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.01 then
		if not rootPart then
			return Vector3.new(0, 0, -1)
		end

		direction = rootPart.CFrame.LookVector
	end

	local planarDirection = Vector3.new(direction.X, 0, direction.Z)
	if planarDirection.Magnitude > 0.01 then
		return planarDirection.Unit
	end

	if direction.Magnitude > 0.01 then
		return direction.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function createIceImpactEffect(position)
	local burst = Instance.new("Part")
	burst.Name = "HieFreezeImpact"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Material = Enum.Material.Neon
	burst.Color = Color3.fromRGB(175, 240, 255)
	burst.Transparency = 0.15
	burst.Size = Vector3.new(1.6, 1.6, 1.6)
	burst.CFrame = CFrame.new(position)
	burst.Parent = Workspace

	local tween = TweenService:Create(burst, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(5.5, 5.5, 5.5),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if burst.Parent then
			burst:Destroy()
		end
	end)
end

local function createIceBoostEffect(targetPlayer, _payload)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	local ring = Instance.new("Part")
	ring.Name = "HieIceBoostRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(152, 232, 255)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.2, 5, 5)
	ring.CFrame = CFrame.new(rootPart.Position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace

	local tween = TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, 8, 8),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

local function findFreezableHazardNearPosition(centerPosition, searchRadius, overlapParams)
	local nearbyParts = Workspace:GetPartBoundsInRadius(centerPosition, searchRadius, overlapParams)
	local closestContainer
	local closestDistance = math.huge

	for _, part in ipairs(nearbyParts) do
		local container, _, _, canFreeze = getHazardContainer(part)
		if container and canFreeze then
			local distance = (part.Position - centerPosition).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestContainer = container
			end
		end
	end

	return closestContainer
end

local function findFreezableHazardAlongSegment(startPosition, endPosition, searchRadius, overlapParams)
	local delta = endPosition - startPosition
	local distance = delta.Magnitude
	if distance <= 0.001 then
		local container = findFreezableHazardNearPosition(startPosition, searchRadius, overlapParams)
		return container, startPosition
	end

	local sampleSpacing = math.max(searchRadius * 0.55, 0.5)
	local sampleCount = math.max(1, math.ceil(distance / sampleSpacing))

	for sampleIndex = 0, sampleCount do
		local alpha = sampleIndex / sampleCount
		local samplePosition = startPosition:Lerp(endPosition, alpha)
		local container = findFreezableHazardNearPosition(samplePosition, searchRadius, overlapParams)
		if container then
			return container, samplePosition
		end
	end

	return nil, nil
end

local function launchFreezeShot(targetPlayer, payload, shouldResolveHit)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	local direction = getProjectileDirection(payload.Direction, rootPart)
	local range = math.max(1, tonumber(payload.Range) or 0)
	local speed = math.max(1, tonumber(payload.ProjectileSpeed) or 0)
	local radius = math.max(0.25, tonumber(payload.ProjectileRadius) or 0.8)
	local freezeDuration = math.max(0, tonumber(payload.FreezeDuration) or 0)
	local startPosition = rootPart.Position + Vector3.new(0, 1.2, 0) + direction * 3

	local projectile = Instance.new("Part")
	projectile.Name = "HieFreezeShot"
	projectile.Shape = Enum.PartType.Ball
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
	projectile.Material = Enum.Material.Neon
	projectile.Color = Color3.fromRGB(173, 244, 255)
	projectile.Transparency = 0.1
	projectile.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	projectile.CFrame = CFrame.new(startPosition)
	projectile.Parent = Workspace

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { projectile, targetPlayer.Character }

	task.spawn(function()
		local traveledDistance = 0
		local lastPosition = startPosition
		local hasResolvedFreeze = false

		while projectile.Parent and traveledDistance < range do
			local dt = RunService.Heartbeat:Wait()
			local stepDistance = math.min(speed * dt, range - traveledDistance)
			if stepDistance <= 0 then
				break
			end

			local nextPosition = lastPosition + direction * stepDistance
			if shouldResolveHit and not hasResolvedFreeze and freezeDuration > 0 then
				local overlapRadius = math.max(radius * 1.15, 1)
				local hitContainer, impactPosition = findFreezableHazardAlongSegment(lastPosition, nextPosition, overlapRadius, overlapParams)
				if hitContainer then
					hasResolvedFreeze = true
					local freezeApplied = HazardRuntime.Freeze(hitContainer, freezeDuration)
					if not freezeApplied then
						suppressHazard(hitContainer, os.clock() + freezeDuration)
					end
					createIceImpactEffect(impactPosition)
					projectile.Position = impactPosition
					break
				end
			end

			projectile.Position = nextPosition
			lastPosition = nextPosition
			traveledDistance += stepDistance
		end

		if projectile.Parent then
			projectile:Destroy()
		end
	end)
end

local function playOptionalEffect(targetPlayer, fruitName, abilityName)
	if fruitName ~= "Mera Mera no Mi" then
		return
	end

	local character = targetPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local particlesFolder = ReplicatedStorage:FindFirstChild("Particles")
	local devilFruitFolder = particlesFolder and particlesFolder:FindFirstChild("DevilFruits")
	local fruitFolder = devilFruitFolder and devilFruitFolder:FindFirstChild("MeraMeraNoMi")
	local template = fruitFolder and fruitFolder:FindFirstChild(abilityName)
	if template then
		local clone = template:Clone()
		clone.Parent = rootPart

		if clone:IsA("ParticleEmitter") then
			clone:Emit(clone:GetAttribute("EmitCount") or 20)
			task.delay(2, function()
				if clone then
					clone:Destroy()
				end
			end)
			return
		end

		if clone:IsA("Attachment") then
			for _, descendant in ipairs(clone:GetDescendants()) do
				if descendant:IsA("ParticleEmitter") then
					descendant:Emit(descendant:GetAttribute("EmitCount") or 20)
				end
			end
			task.delay(2, function()
				if clone then
					clone:Destroy()
				end
			end)
		end
	end

	local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
	local soundDevilFruitFolder = soundsFolder and soundsFolder:FindFirstChild("DevilFruits")
	local soundFruitFolder = soundDevilFruitFolder and soundDevilFruitFolder:FindFirstChild("MeraMeraNoMi")
	local soundTemplate = soundFruitFolder and soundFruitFolder:FindFirstChild(abilityName)
	if soundTemplate and soundTemplate:IsA("Sound") then
		local soundClone = soundTemplate:Clone()
		soundClone.Parent = rootPart
		soundClone:Play()

		soundClone.Ended:Connect(function()
			if soundClone.Parent then
				soundClone:Destroy()
			end
		end)
	end
end

local function createFallbackBurstEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= "Mera Mera no Mi" or abilityName ~= "FireBurst" then
		return
	end

	local character = targetPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local radius = tonumber(payload.Radius) or 10

	local ring = Instance.new("Part")
	ring.Name = "MeraFireBurstRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 136, 32)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace

	local tween = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, radius * 2.6, radius * 2.6),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	local _, abilityName = getAbilityForKeyCode(input.KeyCode)
	if not abilityName or not isLocallyReady(abilityName) then
		return
	end

	requestRemote:FireServer(abilityName)
end)

stateRemote.OnClientEvent:Connect(function(eventName, fruitName, abilityName, value, payload)
	if eventName == "Activated" then
		local readyAt = tonumber(value) or 0
		localCooldowns[abilityName] = readyAt
		updateCooldownHud()

		if fruitName == "Mera Mera no Mi" and abilityName == "FireBurst" then
			startFireBurst(payload or {})
		end
		return
	end

	if eventName == "Denied" and value == "Cooldown" then
		local readyAt = tonumber(payload) or 0
		if readyAt > 0 then
			localCooldowns[abilityName] = readyAt
			updateCooldownHud()
		end
	end
end)

effectRemote.OnClientEvent:Connect(function(targetPlayer, fruitName, abilityName, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	playOptionalEffect(targetPlayer, fruitName, abilityName)
	createFallbackBurstEffect(targetPlayer, fruitName, abilityName, payload or {})

	if fruitName == "Hie Hie no Mi" and abilityName == "FreezeShot" then
		launchFreezeShot(targetPlayer, payload or {}, targetPlayer == player)
		return
	end

	if fruitName == "Hie Hie no Mi" and abilityName == "IceBoost" then
		createIceBoostEffect(targetPlayer, payload or {})
	end
end)

player.CharacterRemoving:Connect(function()
	activeFireBursts = {}
	restoreSuppressedParts(math.huge)
end)

player:GetAttributeChangedSignal("EquippedDevilFruit"):Connect(function()
	hookFruitFolderSignals()
	updateCooldownHud(true)
end)

player.ChildAdded:Connect(function(child)
	if child.Name == "DevilFruit" then
		hookFruitFolderSignals()
		updateCooldownHud(true)
	end
end)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	if now < nextHudRefreshAt then
		return
	end

	nextHudRefreshAt = now + HUD_REFRESH_INTERVAL
	updateCooldownHud(false)
end)

task.defer(function()
	hookFruitFolderSignals()
	updateCooldownHud(true)
end)
