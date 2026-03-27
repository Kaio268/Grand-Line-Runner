local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))
local ProtectionRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("ProtectionRuntime"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GAMEPLAY_MODAL_OPEN_ATTRIBUTE = "GameplayModalOpen"

local GOMU_AIM_RAY_DISTANCE = 500
local GOMU_HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 176, 120)
local GOMU_HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 243, 231)
local GOMU_AUTO_LATCH_MAX_ALIGNMENT = math.cos(math.rad(18))
local GOMU_AUTO_LATCH_BASE_RADIUS = 4
local GOMU_AUTO_LATCH_RADIUS_FACTOR = 0.14
local PHOENIX_FRUIT_NAME = "Tori Tori no Mi"
local PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local PHOENIX_EFFECT_COLOR = Color3.fromRGB(108, 255, 214)
local PHOENIX_EFFECT_ACCENT_COLOR = Color3.fromRGB(255, 188, 113)
local HAZARD_SUPPRESSION_INTERVAL = 0.05
local PHOENIX_SHIELD_PADDING = 2.5
local PHOENIX_VERTICAL_DEADZONE = 0.12
local MIN_DIRECTION_MAGNITUDE = 0.01
local HIE_AIM_DEBUG = RunService:IsStudio()
local HIE_VFX_DEBUG = RunService:IsStudio()
local HIE_VFX_VERBOSE = false
local HIE_DEFAULT_AIM_RAY_DISTANCE = 700
local HIE_AIM_PLANE_HEIGHT_OFFSET = 1.2
local HIE_MAX_AIM_FILTER_PASSES = 12
local HIE_AIM_HELPER_NAMES = {
	HitBox = true,
	ExtractionZone = true,
	RunHub = true,
	DecreaseSpeed = true,
}

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
local activePhoenixShields = {}
local activeHieFreezeShots = {}
local pendingHieFreezeShotResolutions = {}
local hazardSuppressionLoopRunning = false
local spaceHeld = false
local flightInputState = {
	Forward = false,
	Backward = false,
	Left = false,
	Right = false,
}
local resolveFreezeShotVisual
local playOptionalEffect
local getFruitFolder
local getEquippedFruit
local gomuAimState = {
	Highlight = nil,
	TargetPlayer = nil,
}
local phoenixFlightState = {
	Active = false,
	EndTime = 0,
	TakeoffEndTime = 0,
	TakeoffVelocity = 0,
	ActivationHeight = 0,
	InitialLiftTarget = 0,
	MaxHeight = 0,
	FlightSpeed = 0,
	VerticalSpeed = 0,
	MaxDescendSpeed = 0,
	HorizontalResponsiveness = 0,
}
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

local function formatHieVfxVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function describeFreezeShotPayload(payload)
	payload = payload or {}

	return string.format(
		"phase=%s projectileId=%s start=%s impact=%s speed=%s baseSpeed=%s velocity=%s inherited=%s radius=%s maxDistance=%s startedAt=%s resolvedAt=%s hitKind=%s hitLabel=%s resolveReason=%s",
		tostring(payload.Phase),
		tostring(payload.ProjectileId),
		formatHieVfxVector3(payload.StartPosition),
		formatHieVfxVector3(payload.ImpactPosition),
		tostring(payload.ProjectileSpeed),
		tostring(payload.BaseProjectileSpeed),
		formatHieVfxVector3(payload.ProjectileVelocity),
		formatHieVfxVector3(payload.InheritedVelocity),
		tostring(payload.ProjectileRadius),
		tostring(payload.MaxDistance or payload.Range),
		tostring(payload.StartedAt),
		tostring(payload.ResolvedAt),
		tostring(payload.HitKind),
		tostring(payload.HitLabel),
		tostring(payload.ResolveReason)
	)
end

local function logHieVfx(tag, message, ...)
	if not HIE_VFX_DEBUG then
		return
	end

	local prefix = "[HIE][VFX]"
	if typeof(tag) == "string" and tag ~= "" then
		prefix ..= string.format("[%s]", tag)
	end

	print(string.format(prefix .. " " .. message, ...))
end

local function logHieVfxVerbose(message, ...)
	if not (HIE_VFX_DEBUG and HIE_VFX_VERBOSE) then
		return
	end

	print(string.format("[HIE][VFX][STEP] " .. message, ...))
end

local function logHieVfxError(message, ...)
	warn(string.format("[HIE][VFX][ERROR] " .. message, ...))
end

local function logHieAimClient(tag, message, ...)
	if not HIE_AIM_DEBUG then
		return
	end

	local prefix = "[HIE][AIM][CLIENT]"
	if typeof(tag) == "string" and tag ~= "" then
		prefix = string.format("[HIE][AIM][%s]", tag)
	end

	print(string.format(prefix .. " " .. message, ...))
end

local function hasTruthyInstanceAttribute(instance, attributeName)
	if typeof(instance) ~= "Instance" then
		return false
	end

	local value = instance:GetAttribute(attributeName)
	if value == true then
		return true
	end

	if typeof(value) == "string" then
		local lowered = string.lower(value)
		return lowered == "true" or lowered == "1" or lowered == "yes"
	end

	return false
end

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

local function isCooldownBypassEnabled()
	return player:GetAttribute("DevilFruitCooldownBypass") == true
end

local function getPlayerGui()
	return playerGui
end

local function isGameplayModalOpen()
	return playerGui:GetAttribute(GAMEPLAY_MODAL_OPEN_ATTRIBUTE) == true
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
	local shouldShow = isVisible and not isGameplayModalOpen()
	cooldownHud.Gui.Enabled = shouldShow
	cooldownHud.Panel.Visible = shouldShow
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
		local readyAt = isCooldownBypassEnabled() and 0 or (localCooldowns[abilityName] or 0)
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
	if isCooldownBypassEnabled() then
		return true
	end

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

local function getHumanoid()
	local character = getCharacter()
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getCurrentCamera()
	return Workspace.CurrentCamera
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getCurrentLookVector(rootPart)
	local camera = getCurrentCamera()
	local lookVector = camera and camera.CFrame.LookVector or (rootPart and rootPart.CFrame.LookVector)
	if typeof(lookVector) ~= "Vector3" or lookVector.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return Vector3.new(0, 0, -1)
	end

	return lookVector.Unit
end

local function getInitialLiftVelocity(initialLift)
	local gravity = math.max(Workspace.Gravity, 0.01)
	return math.sqrt(2 * gravity * math.max(initialLift, 0))
end

local function setFlightInputKeyState(keyCode, isPressed)
	if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
		flightInputState.Forward = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
		flightInputState.Backward = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
		flightInputState.Left = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
		flightInputState.Right = isPressed
		return true
	end

	return false
end

local function getFlightInputAxes()
	local forwardAxis = 0
	local rightAxis = 0

	if flightInputState.Forward then
		forwardAxis += 1
	end
	if flightInputState.Backward then
		forwardAxis -= 1
	end
	if flightInputState.Right then
		rightAxis += 1
	end
	if flightInputState.Left then
		rightAxis -= 1
	end

	return forwardAxis, rightAxis
end

local function getCameraRelativeFlightDirection(rootPart)
	local forwardAxis, rightAxis = getFlightInputAxes()
	if forwardAxis == 0 and rightAxis == 0 then
		return Vector3.zero
	end

	local camera = getCurrentCamera()
	local lookVector = camera and camera.CFrame.LookVector or getCurrentLookVector(rootPart)
	local rightVector = camera and camera.CFrame.RightVector or (rootPart and rootPart.CFrame.RightVector) or Vector3.xAxis
	local direction = (lookVector * forwardAxis) + (rightVector * rightAxis)
	local magnitude = direction.Magnitude
	if magnitude <= MIN_DIRECTION_MAGNITUDE then
		return Vector3.zero
	end

	return direction.Unit * math.min(math.sqrt((forwardAxis * forwardAxis) + (rightAxis * rightAxis)), 1)
end

local function faceCharacterTowards(direction)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return
	end

	local character = getCharacter()
	local rootPart = getRootPart()
	if not character or not rootPart then
		return
	end

	local planarDirection = getPlanarVector(direction)
	if planarDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return
	end

	local rootPosition = rootPart.Position
	local targetCFrame = CFrame.lookAt(rootPosition, rootPosition + planarDirection.Unit, Vector3.yAxis)
	character:PivotTo(targetCFrame)
end

local function getGlideConfig()
	local fruitName = getEquippedFruit()
	if fruitName ~= PHOENIX_FRUIT_NAME then
		return nil
	end

	local fruit = DevilFruitConfig.GetFruit(fruitName)
	return fruit and fruit.Passives and fruit.Passives.PhoenixGlide or nil
end

local function isPhoenixFlightActive(now)
	now = now or os.clock()
	return phoenixFlightState.Active and now < phoenixFlightState.EndTime
end

local function stopPhoenixFlight()
	if not phoenixFlightState.Active then
		return
	end

	phoenixFlightState.Active = false
	phoenixFlightState.EndTime = 0
	phoenixFlightState.TakeoffEndTime = 0
	phoenixFlightState.TakeoffVelocity = 0
	phoenixFlightState.ActivationHeight = 0
	phoenixFlightState.InitialLiftTarget = 0
	phoenixFlightState.MaxHeight = 0
	phoenixFlightState.FlightSpeed = 0
	phoenixFlightState.VerticalSpeed = 0
	phoenixFlightState.MaxDescendSpeed = 0
	phoenixFlightState.HorizontalResponsiveness = 0

	local humanoid = getHumanoid()
	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function startPhoenixFlight(payload)
	local rootPart = getRootPart()
	local humanoid = getHumanoid()
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	stopPhoenixFlight()

	local duration = math.max(0.1, tonumber(payload.Duration) or 0)
	local takeoffDuration = math.max(0.1, tonumber(payload.TakeoffDuration) or 0.4)
	local initialLift = math.max(0, tonumber(payload.InitialLift) or 10)
	local maxRiseHeight = math.max(initialLift, tonumber(payload.MaxRiseHeight) or initialLift)
	local liftVelocity = getInitialLiftVelocity(initialLift)

	phoenixFlightState.Active = true
	phoenixFlightState.EndTime = os.clock() + duration
	phoenixFlightState.TakeoffEndTime = os.clock() + takeoffDuration
	phoenixFlightState.TakeoffVelocity = liftVelocity
	phoenixFlightState.ActivationHeight = rootPart.Position.Y
	phoenixFlightState.InitialLiftTarget = rootPart.Position.Y + initialLift
	phoenixFlightState.MaxHeight = rootPart.Position.Y + maxRiseHeight
	phoenixFlightState.FlightSpeed = math.max(0, tonumber(payload.FlightSpeed) or 78)
	phoenixFlightState.VerticalSpeed = math.max(0, tonumber(payload.VerticalSpeed) or 52)
	phoenixFlightState.MaxDescendSpeed = math.max(0, tonumber(payload.MaxDescendSpeed) or 58)
	phoenixFlightState.HorizontalResponsiveness = math.max(1, tonumber(payload.HorizontalResponsiveness) or 10)

	humanoid.AutoRotate = false
	humanoid.Jump = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		math.max(currentVelocity.Y, liftVelocity),
		currentVelocity.Z
	)
end

local function updatePhoenixFlight(dt)
	local now = os.clock()
	if getEquippedFruit() ~= PHOENIX_FRUIT_NAME then
		stopPhoenixFlight()
		return
	end

	if not isPhoenixFlightActive(now) then
		if phoenixFlightState.Active then
			stopPhoenixFlight()
		end
		return
	end

	local rootPart = getRootPart()
	local humanoid = getHumanoid()
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		stopPhoenixFlight()
		return
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	local desiredFlightDirection = getCameraRelativeFlightDirection(rootPart)
	local desiredVelocity = desiredFlightDirection * phoenixFlightState.FlightSpeed
	local currentHeight = rootPart.Position.Y
	local inTakeoffPhase = now < phoenixFlightState.TakeoffEndTime and currentHeight < phoenixFlightState.InitialLiftTarget
	if desiredVelocity.Y > 0 and math.abs(desiredVelocity.Y) < (phoenixFlightState.VerticalSpeed * PHOENIX_VERTICAL_DEADZONE) then
		desiredVelocity = Vector3.new(desiredVelocity.X, 0, desiredVelocity.Z)
	end
	if inTakeoffPhase then
		desiredVelocity = Vector3.new(
			desiredVelocity.X,
			math.max(desiredVelocity.Y, phoenixFlightState.TakeoffVelocity),
			desiredVelocity.Z
		)
	end
	if currentHeight >= phoenixFlightState.MaxHeight and desiredVelocity.Y > 0 then
		desiredVelocity = Vector3.new(desiredVelocity.X, 0, desiredVelocity.Z)
	end

	local currentVelocity = rootPart.AssemblyLinearVelocity
	local response = math.clamp(phoenixFlightState.HorizontalResponsiveness * dt, 0, 1)
	local nextVelocity
	if inTakeoffPhase then
		nextVelocity = Vector3.new(
			currentVelocity.X + ((desiredVelocity.X - currentVelocity.X) * response),
			math.max(currentVelocity.Y, desiredVelocity.Y),
			currentVelocity.Z + ((desiredVelocity.Z - currentVelocity.Z) * response)
		)
	else
		nextVelocity = currentVelocity:Lerp(desiredVelocity, response)
	end
	if desiredVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		nextVelocity = Vector3.zero
	end
	if currentHeight > (phoenixFlightState.MaxHeight + 0.5) then
		nextVelocity = Vector3.new(nextVelocity.X, math.min(nextVelocity.Y, -14), nextVelocity.Z)
	end

	rootPart.AssemblyLinearVelocity = nextVelocity

	local desiredPlanarDirection = getPlanarVector(desiredVelocity)
	local nextPlanarDirection = getPlanarVector(nextVelocity)
	if desiredPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE or nextPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		local facingDirection = desiredPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE and desiredPlanarDirection or nextPlanarDirection
		faceCharacterTowards(facingDirection)
	end
end

local function updatePhoenixGlide(dt)
	local glideConfig = getGlideConfig()
	if not glideConfig or not spaceHeld or isPhoenixFlightActive() then
		return
	end

	local rootPart = getRootPart()
	local humanoid = getHumanoid()
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local humanoidState = humanoid:GetState()
	if humanoidState ~= Enum.HumanoidStateType.Freefall and humanoidState ~= Enum.HumanoidStateType.Jumping then
		return
	end

	local currentVelocity = rootPart.AssemblyLinearVelocity
	local activationThreshold = tonumber(glideConfig.ActivateMaxVerticalSpeed) or 6
	if currentVelocity.Y > activationThreshold then
		return
	end

	local desiredDirection = getPlanarVector(getCurrentLookVector(rootPart))
	if desiredDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		desiredDirection = getPlanarVector(humanoid.MoveDirection)
	end
	if desiredDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		desiredDirection = getPlanarVector(rootPart.CFrame.LookVector)
	end
	if desiredDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return
	end

	local forwardSpeed = math.max(0, tonumber(glideConfig.ForwardSpeed) or 28)
	local fallSpeed = math.max(0, tonumber(glideConfig.FallSpeed) or 18)
	local response = math.clamp((tonumber(glideConfig.Responsiveness) or 8) * dt, 0, 1)
	local desiredPlanarVelocity = desiredDirection.Unit * forwardSpeed
	local nextPlanarVelocity = getPlanarVector(currentVelocity):Lerp(desiredPlanarVelocity, response)
	local nextVerticalVelocity = currentVelocity.Y

	if currentVelocity.Y <= 0 then
		local desiredVerticalVelocity = -fallSpeed
		nextVerticalVelocity = currentVelocity.Y + ((desiredVerticalVelocity - currentVelocity.Y) * response)
	end

	rootPart.AssemblyLinearVelocity = Vector3.new(nextPlanarVelocity.X, nextVerticalVelocity, nextPlanarVelocity.Z)
end

local function getPlanarDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function getPlayerFromDescendant(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local targetPlayer = Players:GetPlayerFromCharacter(current)
			if targetPlayer then
				return targetPlayer
			end
		end

		current = current.Parent
	end

	return nil
end

local function getLookAimRay()
	local camera = getCurrentCamera()
	if not camera then
		return nil
	end

	local viewportSize = camera.ViewportSize
	return camera:ViewportPointToRay(viewportSize.X * 0.5, viewportSize.Y * 0.5)
end

local function getLookAimRaycast()
	local unitRay = getLookAimRay()
	if not unitRay then
		return nil, nil, nil, nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}
	params.IgnoreWater = true

	local rayVector = unitRay.Direction * GOMU_AIM_RAY_DISTANCE
	local result = Workspace:Raycast(unitRay.Origin, rayVector, params)
	return result, (result and result.Position) or (unitRay.Origin + rayVector), unitRay.Origin, unitRay.Direction.Unit
end

local function getCursorAimRay()
	local camera = getCurrentCamera()
	if not camera then
		return nil, nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y), mouseLocation
end

local function getCursorAimRaycast(maxDistance)
	local unitRay, mouseLocation = getCursorAimRay()
	if not unitRay then
		return nil, nil, nil, nil, mouseLocation
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}
	params.IgnoreWater = true

	local rayDistance = math.max(1, tonumber(maxDistance) or HIE_DEFAULT_AIM_RAY_DISTANCE)
	local rayVector = unitRay.Direction * rayDistance
	local result = Workspace:Raycast(unitRay.Origin, rayVector, params)
	return result, (result and result.Position) or (unitRay.Origin + rayVector), unitRay.Origin, unitRay.Direction.Unit, mouseLocation
end

local function projectPointToHorizontalPlane(point, planeY)
	if typeof(point) ~= "Vector3" then
		return nil
	end

	return Vector3.new(point.X, planeY, point.Z)
end

local function getHorizontalRayPlaneIntersection(rayOrigin, rayDirection, planeY, maxDistance)
	if typeof(rayOrigin) ~= "Vector3" or typeof(rayDirection) ~= "Vector3" then
		return nil
	end

	if math.abs(rayDirection.Y) <= 0.0001 then
		return nil
	end

	local distance = (planeY - rayOrigin.Y) / rayDirection.Y
	if distance <= 0 then
		return nil
	end

	local maxAllowedDistance = math.max(1, tonumber(maxDistance) or HIE_DEFAULT_AIM_RAY_DISTANCE)
	if distance > maxAllowedDistance then
		return nil
	end

	return rayOrigin + (rayDirection * distance)
end

local function isCharacterDescendant(instance)
	return getPlayerFromDescendant(instance) ~= nil
end

local function getHieAimExclusion(instance)
	if typeof(instance) ~= "Instance" then
		return false, nil, nil
	end

	if instance == Workspace.Terrain then
		return false, nil, nil
	end

	if isCharacterDescendant(instance) then
		return false, nil, nil
	end

	local hazardRoot = HazardUtils.GetHazardInfo(instance)
	if hazardRoot then
		return false, nil, nil
	end

	local current = instance
	while current and current ~= Workspace do
		if hasTruthyInstanceAttribute(current, "IgnoreAim")
			or hasTruthyInstanceAttribute(current, "AimIgnore")
			or hasTruthyInstanceAttribute(current, "IgnoreProjectiles")
			or hasTruthyInstanceAttribute(current, "ProjectileIgnore") then
			return true, current, "ConfiguredIgnore"
		end

		local loweredName = string.lower(current.Name)
		if HIE_AIM_HELPER_NAMES[current.Name]
			or loweredName:find("hitbox", 1, true)
			or loweredName:find("trigger", 1, true)
			or loweredName:find("boundary", 1, true)
			or loweredName == "decreasespeed"
			or (current:IsA("BasePart") and current.CanCollide ~= true and loweredName:find("zone", 1, true)) then
			return true, current, current.Name
		end

		current = current.Parent
	end

	if instance:IsA("BasePart") and instance.CanCollide ~= true then
		return true, instance, "NonCollidable"
	end

	return false, nil, nil
end

local function getHieFreezeAimRaycast(maxDistance)
	local unitRay, mouseLocation = getCursorAimRay()
	if not unitRay then
		return nil, nil, nil, nil, mouseLocation
	end

	local rayDistance = math.max(1, tonumber(maxDistance) or HIE_DEFAULT_AIM_RAY_DISTANCE)
	local rayVector = unitRay.Direction * rayDistance
	local ignoredInstances = player.Character and { player.Character } or {}

	for _ = 1, HIE_MAX_AIM_FILTER_PASSES do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoredInstances
		params.IgnoreWater = true

		local result = Workspace:Raycast(unitRay.Origin, rayVector, params)
		if not result then
			return nil, nil, unitRay.Origin, unitRay.Direction.Unit, mouseLocation
		end

		local shouldExclude, excludeInstance, excludeReason = getHieAimExclusion(result.Instance)
		logHieAimClient(
			"FILTER",
			"hit=%s excluded=%s reason=%s hitPosition=%s",
			result.Instance:GetFullName(),
			tostring(shouldExclude),
			tostring(excludeReason or "Accepted"),
			formatHieVfxVector3(result.Position)
		)

		if not shouldExclude then
			return result, result.Position, unitRay.Origin, unitRay.Direction.Unit, mouseLocation
		end

		ignoredInstances[#ignoredInstances + 1] = excludeInstance or result.Instance
	end

	logHieAimClient(
		"FILTER",
		"raycast exhausted filterPasses=%d fallback=true rayOrigin=%s rayDirection=%s",
		HIE_MAX_AIM_FILTER_PASSES,
		formatHieVfxVector3(unitRay.Origin),
		formatHieVfxVector3(unitRay.Direction.Unit)
	)

	return nil, nil, unitRay.Origin, unitRay.Direction.Unit, mouseLocation
end

local function resolveHiePlanarAimPoint(rootPart, candidatePosition, abilityConfig)
	if not rootPart or typeof(candidatePosition) ~= "Vector3" then
		return nil, "InvalidCandidate", nil
	end

	local aimOrigin = rootPart.Position + Vector3.new(0, HIE_AIM_PLANE_HEIGHT_OFFSET, 0)
	local projectedPosition = projectPointToHorizontalPlane(candidatePosition, aimOrigin.Y)
	local planarOffset = projectedPosition - aimOrigin
	local planarMagnitude = planarOffset.Magnitude
	local minDistance = math.max(0.5, tonumber(abilityConfig and abilityConfig.MinimumAimDistance) or 6)
	if planarMagnitude < minDistance then
		return nil, "TooClose", nil
	end

	local forwardPlanar = getPlanarVector(rootPart.CFrame.LookVector)
	if forwardPlanar.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		forwardPlanar = Vector3.new(0, 0, -1)
	end

	local forwardDot = forwardPlanar.Unit:Dot(planarOffset.Unit)
	local maxDistance = math.max(minDistance, tonumber(abilityConfig and abilityConfig.Range) or 0)
	local clampedDistance = math.clamp(planarMagnitude, minDistance, maxDistance)
	return aimOrigin + (planarOffset.Unit * clampedDistance), nil, forwardDot
end

local function getHieFallbackAimPoint(rootPart, rayOrigin, rayDirection, abilityConfig)
	if not rootPart then
		return nil, "MissingRoot"
	end

	local aimOrigin = rootPart.Position + Vector3.new(0, HIE_AIM_PLANE_HEIGHT_OFFSET, 0)
	local aimRayDistance = math.max(1, tonumber(abilityConfig and abilityConfig.AimRayDistance) or HIE_DEFAULT_AIM_RAY_DISTANCE)
	local planePoint = getHorizontalRayPlaneIntersection(rayOrigin, rayDirection, aimOrigin.Y, aimRayDistance)
	if planePoint then
		local resolvedPoint, rejectReason, forwardDot = resolveHiePlanarAimPoint(rootPart, planePoint, abilityConfig)
		if resolvedPoint then
			logHieAimClient(
				"FALLBACK",
				"mode=plane resolved=true aimPoint=%s origin=%s forwardDot=%.2f",
				formatHieVfxVector3(resolvedPoint),
				formatHieVfxVector3(aimOrigin),
				forwardDot or 0
			)
			return resolvedPoint
		end

		logHieAimClient(
			"FALLBACK",
			"mode=plane resolved=false reason=%s planePoint=%s origin=%s",
			tostring(rejectReason),
			formatHieVfxVector3(planePoint),
			formatHieVfxVector3(aimOrigin)
		)
	end

	local forwardPlanar = getPlanarVector(rootPart.CFrame.LookVector)
	if forwardPlanar.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		forwardPlanar = Vector3.new(0, 0, -1)
	end

	local fallbackDistance = math.max(
		math.max(tonumber(abilityConfig and abilityConfig.MinimumAimDistance) or 6, 18),
		math.min(tonumber(abilityConfig and abilityConfig.Range) or 45, aimRayDistance)
	)
	local fallbackPoint = aimOrigin + (forwardPlanar.Unit * fallbackDistance)
	logHieAimClient(
		"FALLBACK",
		"mode=forward aimPoint=%s origin=%s direction=%s",
		formatHieVfxVector3(fallbackPoint),
		formatHieVfxVector3(aimOrigin),
		formatHieVfxVector3(forwardPlanar.Unit)
	)
	return fallbackPoint
end

local function getDistanceFromRay(rayOrigin, rayDirection, point)
	local toPoint = point - rayOrigin
	local projectedDistance = math.max(0, toPoint:Dot(rayDirection))
	local closestPoint = rayOrigin + (rayDirection * projectedDistance)
	return (point - closestPoint).Magnitude, projectedDistance
end

local function findGomuAutoLatchPlayer(launchDistance, rayOrigin, rayDirection)
	local localRootPart = getRootPart()
	if not localRootPart or not rayOrigin or not rayDirection then
		return nil
	end

	local bestTargetPlayer
	local bestScore = -math.huge

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player and isGomuTargetInRange(targetPlayer, launchDistance) then
			local targetRootPart = getPlayerRootPart(targetPlayer)
			if targetRootPart then
				local targetPosition = targetRootPart.Position + Vector3.new(0, 1.5, 0)
				local toTarget = targetPosition - rayOrigin
				local toTargetUnit = toTarget.Magnitude > 0.01 and toTarget.Unit or nil
				local alignment = toTargetUnit and rayDirection:Dot(toTargetUnit) or -1
				if alignment >= GOMU_AUTO_LATCH_MAX_ALIGNMENT then
					local lateralDistance, projectedDistance = getDistanceFromRay(rayOrigin, rayDirection, targetPosition)
					local allowedRadius = math.max(GOMU_AUTO_LATCH_BASE_RADIUS, projectedDistance * GOMU_AUTO_LATCH_RADIUS_FACTOR)
					if lateralDistance <= allowedRadius then
						local planarDistance = getPlanarDistance(localRootPart.Position, targetRootPart.Position)
						local score = (alignment * 100) - (lateralDistance * 2) - (planarDistance * 0.1)
						if score > bestScore then
							bestScore = score
							bestTargetPlayer = targetPlayer
						end
					end
				end
			end
		end
	end

	return bestTargetPlayer
end

local function ensureGomuHighlight()
	local highlight = gomuAimState.Highlight
	if highlight and highlight.Parent then
		return highlight
	end

	highlight = Instance.new("Highlight")
	highlight.Name = "GomuAimHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = GOMU_HIGHLIGHT_FILL_COLOR
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = GOMU_HIGHLIGHT_OUTLINE_COLOR
	highlight.OutlineTransparency = 0.05
	highlight.Enabled = false
	highlight.Parent = Workspace

	gomuAimState.Highlight = highlight
	return highlight
end

local function clearGomuHighlight()
	local highlight = gomuAimState.Highlight
	if highlight then
		highlight.Enabled = false
		highlight.Adornee = nil
	end

	gomuAimState.TargetPlayer = nil
end

local function isGomuTargetInRange(targetPlayer, maxDistance)
	local localRootPart = getRootPart()
	local targetRootPart = getPlayerRootPart(targetPlayer)
	if not localRootPart or not targetRootPart then
		return false
	end

	return getPlanarDistance(localRootPart.Position, targetRootPart.Position) <= (maxDistance + 0.5)
end

local function getGomuLaunchTarget(abilityConfig)
	local result, fallbackPosition, rayOrigin, rayDirection = getLookAimRaycast()
	local aimPosition = fallbackPosition
	local launchDistance = math.max(0, tonumber(abilityConfig and abilityConfig.LaunchDistance) or 0)
	local targetPlayer = findGomuAutoLatchPlayer(launchDistance, rayOrigin, rayDirection)

	if not targetPlayer and result then
		targetPlayer = getPlayerFromDescendant(result.Instance)
		if targetPlayer == player or not isGomuTargetInRange(targetPlayer, launchDistance) then
			targetPlayer = nil
		end
	end

	if targetPlayer then
		local targetRootPart = getPlayerRootPart(targetPlayer)
		if targetRootPart then
			aimPosition = targetRootPart.Position
		end
	end

	if not aimPosition then
		local rootPart = getRootPart()
		if rootPart then
			local fallbackDirection = rayDirection or rootPart.CFrame.LookVector
			aimPosition = rootPart.Position + (fallbackDirection * GOMU_AIM_RAY_DISTANCE)
		end
	end

	return aimPosition, targetPlayer
end

local function getHieFreezeShotAimPosition(abilityConfig)
	local aimRayDistance = math.max(1, tonumber(abilityConfig and abilityConfig.AimRayDistance) or HIE_DEFAULT_AIM_RAY_DISTANCE)
	local rootPart = getRootPart()
	local result, hitPosition, rayOrigin, rayDirection, mouseLocation = getHieFreezeAimRaycast(aimRayDistance)
	if rootPart and hitPosition then
		local chosenAimPosition, rejectReason, forwardDot = resolveHiePlanarAimPoint(rootPart, hitPosition, abilityConfig)
		if chosenAimPosition then
			local flattenedY = math.abs(hitPosition.Y - chosenAimPosition.Y) > 0.01
			logHieAimClient(
				"CLIENT",
				"captured=true mouse=%s hit=%s chosenAim=%s rayOrigin=%s rayDirection=%s flattenedY=%s forwardDot=%.2f",
				tostring(mouseLocation),
				result and result.Instance and result.Instance:GetFullName() or "<none>",
				formatHieVfxVector3(chosenAimPosition),
				formatHieVfxVector3(rayOrigin),
				formatHieVfxVector3(rayDirection),
				tostring(flattenedY),
				forwardDot or 0
			)
			return chosenAimPosition
		end

		logHieAimClient(
			"FALLBACK",
			"capturedHitRejected=true reason=%s mouse=%s hit=%s hitPosition=%s",
			tostring(rejectReason),
			tostring(mouseLocation),
			result and result.Instance and result.Instance:GetFullName() or "<none>",
			formatHieVfxVector3(hitPosition)
		)
	end

	if rootPart then
		return getHieFallbackAimPoint(rootPart, rayOrigin, rayDirection, abilityConfig)
	end

	logHieAimClient("FALLBACK", "captured=false reason=no_cursor_ray_and_no_root")
	return nil
end

local function buildAbilityRequestPayload(fruitName, abilityName)
	if fruitName == "Hie Hie no Mi" and abilityName == "FreezeShot" then
		local abilityConfig = DevilFruitConfig.GetAbility(fruitName, abilityName)
		local aimPosition = getHieFreezeShotAimPosition(abilityConfig)
		return aimPosition and {
			AimPosition = aimPosition,
		} or nil
	end

	if fruitName == "Gomu Gomu no Mi" and abilityName == "RubberLaunch" then
		local abilityConfig = DevilFruitConfig.GetAbility(fruitName, abilityName)
		local aimPosition, targetPlayer = getGomuLaunchTarget(abilityConfig)

		return {
			AimPosition = aimPosition,
			TargetPlayerUserId = targetPlayer and targetPlayer.UserId or nil,
		}
	end

	return nil
end

local function updateGomuAimAssist()
	local fruitName = getEquippedFruit()
	if fruitName ~= "Gomu Gomu no Mi" then
		clearGomuHighlight()
		return
	end

	local abilityConfig = DevilFruitConfig.GetAbility(fruitName, "RubberLaunch")
	if not abilityConfig then
		clearGomuHighlight()
		return
	end

	local _, targetPlayer = getGomuLaunchTarget(abilityConfig)
	if not targetPlayer or not targetPlayer.Character then
		clearGomuHighlight()
		return
	end

	local highlight = ensureGomuHighlight()
	highlight.Adornee = targetPlayer.Character
	highlight.Enabled = true
	gomuAimState.TargetPlayer = targetPlayer
end

local function isDescendantOfClientWave(instance)
	local clientWavesFolder = MapResolver.GetRefs().ClientWaves
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
		OriginalCanCollide = part.CanCollide,
		UntilTime = untilTime,
	}

	part.CanTouch = false
	part.CanCollide = false
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
			part.CanCollide = state.OriginalCanCollide
			suppressedParts[part] = nil
		end
	end
end

local function isLocalPlayerInsidePhoenixShield(position)
	local checkPosition = position
	if typeof(checkPosition) ~= "Vector3" then
		local rootPart = getRootPart()
		checkPosition = rootPart and rootPart.Position or nil
	end
	if not checkPosition then
		return false
	end

	local now = os.clock()
	for shieldOwner, shield in pairs(activePhoenixShields) do
		if now >= shield.EndTime then
			activePhoenixShields[shieldOwner] = nil
		else
			local ownerRootPart = getPlayerRootPart(shieldOwner)
			if ownerRootPart and getPlanarDistance(ownerRootPart.Position, checkPosition) <= (shield.Radius + PHOENIX_SHIELD_PADDING) then
				return true
			end
		end
	end

	return false
end

ProtectionRuntime.Register("PhoenixProtection", function(targetPlayer, position)
	if targetPlayer ~= player then
		return false
	end

	return isLocalPlayerInsidePhoenixShield(position)
end)

local function buildLocalHazardOverlapParams()
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = player.Character and { player.Character } or {}
	return overlapParams
end

local function suppressHazardsNearPosition(centerPosition, radius, untilTime, shouldSuppress)
	if typeof(centerPosition) ~= "Vector3" or radius <= 0 then
		return
	end

	local nearbyParts = Workspace:GetPartBoundsInRadius(centerPosition, radius, buildLocalHazardOverlapParams())
	for _, part in ipairs(nearbyParts) do
		local container, hazardClass, hazardType = getHazardContainer(part)
		if container and (shouldSuppress == nil or shouldSuppress(container, hazardClass, hazardType)) then
			suppressHazard(container, untilTime)
		end
	end
end

local function hasActiveHazardProtection(now)
	if #activeFireBursts > 0 then
		return true
	end

	for _, shield in pairs(activePhoenixShields) do
		if now < shield.EndTime then
			return true
		end
	end

	return false
end

local function updateHazardSuppression()
	local now = os.clock()
	local rootPart = getRootPart()

	for i = #activeFireBursts, 1, -1 do
		local burst = activeFireBursts[i]
		if now >= burst.EndTime or not rootPart then
			table.remove(activeFireBursts, i)
		else
			-- Corridor hazards are client-created in this project, so Fire Burst
			-- suppresses nearby minor hazards locally after the server authorizes it.
			suppressHazardsNearPosition(rootPart.Position, burst.Radius, burst.EndTime, function(_, hazardClass)
				return hazardClass == "minor"
			end)
		end
	end

	for shieldOwner, shield in pairs(activePhoenixShields) do
		if now >= shield.EndTime then
			activePhoenixShields[shieldOwner] = nil
		else
			local ownerRootPart = getPlayerRootPart(shieldOwner)
			if not ownerRootPart then
				if shieldOwner.Parent == nil then
					activePhoenixShields[shieldOwner] = nil
				end
			elseif rootPart and getPlanarDistance(ownerRootPart.Position, rootPart.Position) <= (shield.Radius + PHOENIX_SHIELD_PADDING) then
				suppressHazardsNearPosition(ownerRootPart.Position, shield.Radius, shield.EndTime)
			end
		end
	end

	restoreSuppressedParts(now)

	if hasActiveHazardProtection(now) then
		task.delay(HAZARD_SUPPRESSION_INTERVAL, updateHazardSuppression)
	else
		hazardSuppressionLoopRunning = false
	end
end

local function ensureHazardSuppressionLoop()
	if hazardSuppressionLoopRunning then
		return
	end

	hazardSuppressionLoopRunning = true
	updateHazardSuppression()
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

	ensureHazardSuppressionLoop()
end

local function startPhoenixShield(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	local duration = tonumber(payload.Duration) or 0
	local radius = tonumber(payload.Radius) or 0
	if duration <= 0 or radius <= 0 then
		return
	end

	local shieldState = activePhoenixShields[targetPlayer]
	local shieldEndTime = os.clock() + duration
	if shieldState then
		shieldState.EndTime = math.max(shieldState.EndTime, shieldEndTime)
		shieldState.Radius = math.max(shieldState.Radius, radius)
	else
		activePhoenixShields[targetPlayer] = {
			EndTime = shieldEndTime,
			Radius = radius,
		}
	end

	ensureHazardSuppressionLoop()
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

local function getFreezeShotVelocity(payload, direction, speed)
	if typeof(payload.ProjectileVelocity) == "Vector3" and payload.ProjectileVelocity.Magnitude > 0.01 then
		return payload.ProjectileVelocity
	end

	return direction * math.max(1, speed)
end

local function setFreezeShotVisualTransform(part, position, velocity, fallbackDirection)
	if not part then
		return
	end

	local facing = typeof(velocity) == "Vector3" and velocity.Magnitude > 0.01 and velocity.Unit or fallbackDirection
	if typeof(facing) ~= "Vector3" or facing.Magnitude <= 0.01 then
		facing = Vector3.new(0, 0, -1)
	end

	part.CFrame = CFrame.lookAt(position, position + facing)
end

local function getFreezeShotTravelSnapshot(startPosition, velocity, maxDistance, startedAt, queryTime, resolutionPayload)
	local speed = typeof(velocity) == "Vector3" and velocity.Magnitude or 0
	local elapsed = math.max(0, queryTime - startedAt)
	local maxTravelTime = speed > 0.01 and (maxDistance / speed) or 0
	local effectiveTravelTime = math.min(elapsed, maxTravelTime)
	local distance = math.min(speed * effectiveTravelTime, maxDistance)
	local position = startPosition + (velocity * effectiveTravelTime)
	local clamped = effectiveTravelTime < elapsed
	local clampReason = clamped and "max_distance" or "none"

	if type(resolutionPayload) == "table" then
		local resolvedAt = tonumber(resolutionPayload.ResolvedAt)
		local impactPosition = typeof(resolutionPayload.ImpactPosition) == "Vector3" and resolutionPayload.ImpactPosition or nil
		if resolvedAt and impactPosition and queryTime >= resolvedAt then
			position = impactPosition
			distance = math.min((impactPosition - startPosition).Magnitude, maxDistance)
			clamped = true
			clampReason = "resolved"
		end
	end

	return {
		Position = position,
		Elapsed = elapsed,
		Distance = distance,
		Speed = speed,
		Clamped = clamped,
		ClampReason = clampReason,
		EffectiveTravelTime = effectiveTravelTime,
	}
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

local function destroyFreezeShotPart(projectileState)
	if projectileState and projectileState.Part and projectileState.Part.Parent then
		projectileState.Part:Destroy()
	end
end

local function cleanupFreezeShot(projectileId)
	local projectileState = activeHieFreezeShots[projectileId]
	if not projectileState then
		return
	end

	activeHieFreezeShots[projectileId] = nil
	destroyFreezeShotPart(projectileState)
	logHieVfx("CLEANUP", "projectileId=%s cleanedUp=true", tostring(projectileId))
end

-- Temporary primitive projectile, isolated so it can be swapped for final Hie VFX later.
local function createTemporaryFreezeShotVisual(radius, startPosition, initialVelocity)
	local ok, projectile = pcall(function()
		local part = Instance.new("Part")
		part.Name = "HieFreezeShotTemp"
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(173, 244, 255)
		part.Transparency = 0.08
		part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		setFreezeShotVisualTransform(part, startPosition, initialVelocity, nil)

		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = Color3.fromRGB(196, 248, 255)
		light.Brightness = 1.8
		light.Range = math.max(6, radius * 8)
		light.Parent = part

		local attachment0 = Instance.new("Attachment")
		attachment0.Name = "TrailStart"
		attachment0.Position = Vector3.new(0, 0, -radius * 0.55)
		attachment0.Parent = part

		local attachment1 = Instance.new("Attachment")
		attachment1.Name = "TrailEnd"
		attachment1.Position = Vector3.new(0, 0, radius * 0.55)
		attachment1.Parent = part

		local trail = Instance.new("Trail")
		trail.Name = "Trail"
		trail.Attachment0 = attachment0
		trail.Attachment1 = attachment1
		trail.Color = ColorSequence.new(
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(153, 234, 255)
		)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.LightEmission = 1
		trail.Lifetime = 0.09
		trail.MinLength = 0.02
		trail.Enabled = true
		trail.Parent = part

		part.Parent = Workspace
		return part
	end)

	if not ok then
		logHieVfxError("temporary projectile creation failed detail=%s", tostring(projectile))
		return nil
	end

	logHieVfx(
		"PROJECTILE",
		"temporary projectile created success=true radius=%.2f start=%s",
		radius,
		formatHieVfxVector3(startPosition)
	)

	return projectile
end

local function registerFreezeShotLaunch(targetPlayer, payload)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		logHieVfxError("launch ignored missingRoot player=%s payload={%s}", targetPlayer.Name, describeFreezeShotPayload(payload))
		return false
	end

	local projectileId = tostring(payload.ProjectileId or "")
	if projectileId == "" then
		logHieVfxError("launch ignored missingProjectileId player=%s payload={%s}", targetPlayer.Name, describeFreezeShotPayload(payload))
		return false
	end

	logHieVfx("INIT", "launch received player=%s payload={%s}", targetPlayer.Name, describeFreezeShotPayload(payload))

	cleanupFreezeShot(projectileId)

	local receiptTime = Workspace:GetServerTimeNow()
	local pendingResolution = pendingHieFreezeShotResolutions[projectileId]
	local direction = getProjectileDirection(payload.Direction, rootPart)
	local speed = math.max(1, tonumber(payload.ProjectileSpeed) or 0)
	local radius = math.max(0.25, tonumber(payload.ProjectileRadius) or 0.8)
	local maxDistance = math.max(1, tonumber(payload.MaxDistance) or tonumber(payload.Range) or 0)
	local lifetime = math.max(0.05, tonumber(payload.Lifetime) or (maxDistance / speed))
	local startedAt = tonumber(payload.StartedAt) or Workspace:GetServerTimeNow()
	local startPosition = typeof(payload.StartPosition) == "Vector3"
		and payload.StartPosition
		or (rootPart.Position + Vector3.new(0, 1.2, 0) + direction * 3)
	local projectileVelocity = getFreezeShotVelocity(payload, direction, speed)
	speed = math.max(1, projectileVelocity.Magnitude)
	direction = projectileVelocity.Magnitude > 0.01 and projectileVelocity.Unit or direction
	local spawnSnapshot = getFreezeShotTravelSnapshot(
		startPosition,
		projectileVelocity,
		maxDistance,
		startedAt,
		receiptTime,
		pendingResolution and pendingResolution.Payload or nil
	)
	local visualStartPosition = spawnSnapshot.Position
	local fastForwardDistance = (visualStartPosition - startPosition).Magnitude

	if fastForwardDistance > 0.05 then
		logHieVfx(
			"DESYNC",
			"projectileId=%s receipt=%.3f startedAt=%.3f elapsed=%.3f rawStart=%s visualStart=%s offset=%.2f velocity=%s",
			projectileId,
			receiptTime,
			startedAt,
			spawnSnapshot.Elapsed,
			formatHieVfxVector3(startPosition),
			formatHieVfxVector3(visualStartPosition),
			fastForwardDistance,
			formatHieVfxVector3(projectileVelocity)
		)
	end

	logHieVfx(
		"FASTFORWARD",
		"projectileId=%s receipt=%.3f startedAt=%.3f elapsed=%.3f rawStart=%s visualStart=%s velocity=%s maxDistance=%.2f clamped=%s reason=%s",
		projectileId,
		receiptTime,
		startedAt,
		spawnSnapshot.Elapsed,
		formatHieVfxVector3(startPosition),
		formatHieVfxVector3(visualStartPosition),
		formatHieVfxVector3(projectileVelocity),
		maxDistance,
		tostring(spawnSnapshot.Clamped),
		spawnSnapshot.ClampReason
	)

	local projectile = createTemporaryFreezeShotVisual(radius, visualStartPosition, projectileVelocity)
	if not projectile then
		logHieVfxError("launch failed visualCreation=false projectileId=%s player=%s", projectileId, targetPlayer.Name)
		return false
	end

	activeHieFreezeShots[projectileId] = {
		Id = projectileId,
		Part = projectile,
		Direction = direction,
		Velocity = projectileVelocity,
		Speed = speed,
		Radius = radius,
		MaxDistance = maxDistance,
		Lifetime = lifetime,
		StartedAt = startedAt,
		StartPosition = startPosition,
		ResolvedAt = nil,
		ImpactPosition = nil,
		ImpactEffectPlayed = false,
		ShouldCreateImpact = false,
	}

	logHieVfx(
		"SPAWN",
		"projectile initialized player=%s projectileId=%s receipt=%.3f startedAt=%.3f speed=%.2f velocity=%s rawStart=%s visualStart=%s maxDistance=%.2f radius=%.2f lifetime=%.2f",
		targetPlayer.Name,
		projectileId,
		receiptTime,
		startedAt,
		speed,
		formatHieVfxVector3(projectileVelocity),
		formatHieVfxVector3(startPosition),
		formatHieVfxVector3(visualStartPosition),
		maxDistance,
		radius,
		lifetime
	)

	if pendingResolution then
		pendingHieFreezeShotResolutions[projectileId] = nil
		logHieVfx(
			"PROJECTILE",
			"applying queued resolution projectileId=%s createImpact=%s",
			projectileId,
			tostring(pendingResolution.ShouldCreateImpact)
		)
		resolveFreezeShotVisual(pendingResolution.Payload, pendingResolution.ShouldCreateImpact)
	end

	return true
end

resolveFreezeShotVisual = function(payload, shouldCreateImpact)
	local projectileId = tostring(payload.ProjectileId or "")
	if projectileId == "" then
		logHieVfxError("resolution ignored missingProjectileId payload={%s}", describeFreezeShotPayload(payload))
		return false
	end

	logHieVfx(
		"PROJECTILE",
		"resolution received projectileId=%s createImpact=%s payload={%s}",
		projectileId,
		tostring(shouldCreateImpact),
		describeFreezeShotPayload(payload)
	)

	local projectileState = activeHieFreezeShots[projectileId]
	if not projectileState then
		pendingHieFreezeShotResolutions[projectileId] = {
			Payload = payload,
			ShouldCreateImpact = shouldCreateImpact,
		}
		logHieVfx(
			"PROJECTILE",
			"resolution queued waitingForLaunch projectileId=%s createImpact=%s",
			projectileId,
			tostring(shouldCreateImpact)
		)
		return false
	end

	projectileState.ResolvedAt = tonumber(payload.ResolvedAt) or Workspace:GetServerTimeNow()
	projectileState.ImpactPosition = typeof(payload.ImpactPosition) == "Vector3" and payload.ImpactPosition or projectileState.Part.Position
	projectileState.ShouldCreateImpact = shouldCreateImpact
	return true
end

local function tryPlayFreezeShotOptionalEffect(targetPlayer)
	if typeof(playOptionalEffect) ~= "function" then
		logHieVfx("PROJECTILE", "optional effect helper unavailable, using temporary projectile fallback only")
		return
	end

	local ok, err = pcall(playOptionalEffect, targetPlayer, "Hie Hie no Mi", "FreezeShot")
	if not ok then
		logHieVfxError("optional effect helper failed player=%s detail=%s", targetPlayer.Name, tostring(err))
		return false
	end

	logHieVfx("PROJECTILE", "optional effect helper succeeded player=%s", targetPlayer.Name)
	return true
end

local function updateFreezeShots()
	local serverNow = Workspace:GetServerTimeNow()
	local cleanupIds = {}

	for projectileId, projectileState in pairs(activeHieFreezeShots) do
		if not projectileState.Part or not projectileState.Part.Parent then
			logHieVfxError("projectile visual missing projectileId=%s cleanedUp=true", projectileId)
			cleanupIds[#cleanupIds + 1] = projectileId
			continue
		end

		local elapsed = math.max(0, serverNow - projectileState.StartedAt)
		local maxTravelTime = projectileState.Speed > 0 and (projectileState.MaxDistance / projectileState.Speed) or 0
		local effectiveTravelTime = math.min(elapsed, maxTravelTime)
		local traveledDistance = math.min(projectileState.Speed * effectiveTravelTime, projectileState.MaxDistance)
		local currentPosition = projectileState.StartPosition + (projectileState.Velocity * effectiveTravelTime)

		if HIE_VFX_VERBOSE then
			logHieVfxVerbose(
				"projectileId=%s elapsed=%.2f distance=%.2f current=%s velocity=%s",
				projectileId,
				elapsed,
				traveledDistance,
				formatHieVfxVector3(currentPosition),
				formatHieVfxVector3(projectileState.Velocity)
			)
		end

		if projectileState.ResolvedAt ~= nil then
			local resolvedPosition = projectileState.ImpactPosition or currentPosition
			if serverNow >= projectileState.ResolvedAt then
				setFreezeShotVisualTransform(
					projectileState.Part,
					resolvedPosition,
					projectileState.Velocity,
					projectileState.Direction
				)

				if projectileState.ShouldCreateImpact and not projectileState.ImpactEffectPlayed then
					projectileState.ImpactEffectPlayed = true
					logHieVfx(
						"IMPACT",
						"rendering impact projectileId=%s position=%s",
						projectileId,
						formatHieVfxVector3(resolvedPosition)
					)
					local impactOk, impactError = pcall(createIceImpactEffect, resolvedPosition)
					if not impactOk then
						logHieVfxError("impact effect failed projectileId=%s detail=%s", projectileId, tostring(impactError))
					end
				end

				cleanupIds[#cleanupIds + 1] = projectileId
				continue
			end
		end

		setFreezeShotVisualTransform(
			projectileState.Part,
			currentPosition,
			projectileState.Velocity,
			projectileState.Direction
		)

		if elapsed >= (projectileState.Lifetime + 0.2) then
			logHieVfx("PROJECTILE", "forcing cleanup expiredVisual=true projectileId=%s", projectileId)
			cleanupIds[#cleanupIds + 1] = projectileId
		end
	end

	for _, projectileId in ipairs(cleanupIds) do
		cleanupFreezeShot(projectileId)
	end
end

local function handleFreezeShotEffect(targetPlayer, payload)
	local resolvedPayload = payload or {}
	local phase = typeof(resolvedPayload.Phase) == "string" and resolvedPayload.Phase or "Launch"

	logHieVfx(
		"INIT",
		"effect received player=%s phase=%s payload={%s}",
		targetPlayer.Name,
		phase,
		describeFreezeShotPayload(resolvedPayload)
	)

	local ok, err = pcall(function()
		if phase == "Launch" then
			tryPlayFreezeShotOptionalEffect(targetPlayer)
			registerFreezeShotLaunch(targetPlayer, resolvedPayload)
			return
		end

		if phase == "Impact" then
			resolveFreezeShotVisual(resolvedPayload, true)
			return
		end

		if phase == "Expire" then
			logHieVfx("PROJECTILE", "impactless expiry received projectileId=%s", tostring(resolvedPayload.ProjectileId))
			resolveFreezeShotVisual(resolvedPayload, false)
			return
		end

		logHieVfxError("unknown phase=%s player=%s payload={%s}", tostring(phase), targetPlayer.Name, describeFreezeShotPayload(resolvedPayload))
	end)

	if not ok then
		logHieVfxError(
			"handler failed player=%s phase=%s detail=%s payload={%s}",
			targetPlayer.Name,
			tostring(phase),
			tostring(err),
			describeFreezeShotPayload(resolvedPayload)
		)
	end
end

local function addUniqueFolderName(folderNames, seenNames, folderName)
	if typeof(folderName) ~= "string" or folderName == "" or seenNames[folderName] then
		return
	end

	seenNames[folderName] = true
	table.insert(folderNames, folderName)
end

local function getFruitEffectFolderNames(fruitName)
	local fruit = DevilFruitConfig.GetFruit(fruitName)
	local compactFruitName = typeof(fruitName) == "string" and (fruitName:gsub("[%W_]+", "")) or nil
	local folderNames = {}
	local seenNames = {}

	addUniqueFolderName(folderNames, seenNames, fruit and fruit.Id)
	addUniqueFolderName(folderNames, seenNames, fruit and fruit.AssetFolder)
	addUniqueFolderName(folderNames, seenNames, fruit and fruit.AbilityModule)
	addUniqueFolderName(folderNames, seenNames, fruit and fruit.FruitKey)
	addUniqueFolderName(folderNames, seenNames, compactFruitName)

	return folderNames
end

local function findFruitEffectFolder(rootFolder, fruitName)
	if not rootFolder then
		return nil
	end

	for _, folderName in ipairs(getFruitEffectFolderNames(fruitName)) do
		local folder = rootFolder:FindFirstChild(folderName)
		if folder then
			return folder
		end
	end

	return nil
end

playOptionalEffect = function(targetPlayer, fruitName, abilityName)
	local character = targetPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local particlesFolder = ReplicatedStorage:FindFirstChild("Particles")
	local devilFruitFolder = particlesFolder and particlesFolder:FindFirstChild("DevilFruits")
	local fruitFolder = findFruitEffectFolder(devilFruitFolder, fruitName)
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
	local soundFruitFolder = findFruitEffectFolder(soundDevilFruitFolder, fruitName)
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

local function createGomuPulse(name, position, color, initialSize, finalSize, duration)
	local pulse = Instance.new("Part")
	pulse.Name = name
	pulse.Shape = Enum.PartType.Ball
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanTouch = false
	pulse.CanQuery = false
	pulse.Material = Enum.Material.Neon
	pulse.Color = color
	pulse.Transparency = 0.18
	pulse.Size = Vector3.new(initialSize, initialSize, initialSize)
	pulse.CFrame = CFrame.new(position)
	pulse.Parent = Workspace

	local tween = TweenService:Create(pulse, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(finalSize, finalSize, finalSize),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if pulse.Parent then
			pulse:Destroy()
		end
	end)
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

local function getEffectOriginPosition(targetPlayer, payload)
	if typeof(payload) == "table" and typeof(payload.OriginPosition) == "Vector3" then
		return payload.OriginPosition
	end

	local rootPart = getPlayerRootPart(targetPlayer)
	return rootPart and rootPart.Position or nil
end

local function createBomuDetonationEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= "Bomu Bomu no Mi" then
		return
	end

	if abilityName ~= "LandMine" then
		return
	end

	if payload and payload.Action ~= "Detonated" then
		return
	end

	local originPosition = getEffectOriginPosition(targetPlayer, payload)
	if not originPosition then
		return
	end

	local radius = math.max(1, tonumber(payload and payload.Radius) or 8)

	local flash = Instance.new("Part")
	flash.Name = "BomuDetonationFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 225, 153)
	flash.Transparency = 0.12
	flash.Size = Vector3.new(2, 2, 2)
	flash.CFrame = CFrame.new(originPosition)
	flash.Parent = Workspace

	local ring = Instance.new("Part")
	ring.Name = "BomuDetonationRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 171, 82)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.25, radius * 0.8, radius * 0.8)
	ring.CFrame = CFrame.new(originPosition) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace

	local flashTween = TweenService:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(radius * 2.2, radius * 2.2, radius * 2.2),
	})

	local ringTween = TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.25, radius * 2.35, radius * 2.35),
	})

	flashTween:Play()
	ringTween:Play()

	flashTween.Completed:Connect(function()
		if flash.Parent then
			flash:Destroy()
		end
	end)

	ringTween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

local function createPhoenixFlightEffect(targetPlayer, fruitName, abilityName, _payload)
	if fruitName ~= PHOENIX_FRUIT_NAME or abilityName ~= PHOENIX_FLIGHT_ABILITY then
		return
	end

	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	local burst = Instance.new("Part")
	burst.Name = "PhoenixFlightBurst"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Material = Enum.Material.Neon
	burst.Color = PHOENIX_EFFECT_COLOR
	burst.Transparency = 0.18
	burst.Size = Vector3.new(2.25, 2.25, 2.25)
	burst.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 1.5, 0))
	burst.Parent = Workspace

	local ring = Instance.new("Part")
	ring.Name = "PhoenixFlightRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = PHOENIX_EFFECT_ACCENT_COLOR
	ring.Transparency = 0.28
	ring.Size = Vector3.new(0.22, 4.8, 4.8)
	ring.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace

	local burstTween = TweenService:Create(burst, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(7, 7, 7),
	})
	local ringTween = TweenService:Create(ring, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.22, 9, 9),
	})

	burstTween:Play()
	ringTween:Play()

	burstTween.Completed:Connect(function()
		if burst.Parent then
			burst:Destroy()
		end
	end)

	ringTween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

local function createPhoenixShieldEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= PHOENIX_FRUIT_NAME or abilityName ~= PHOENIX_SHIELD_ABILITY then
		return
	end

	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	local radius = math.max(1, tonumber(payload.Radius) or 13)
	local duration = math.max(0.1, tonumber(payload.Duration) or 2.75)
	local endTime = os.clock() + duration

	local ring = Instance.new("Part")
	ring.Name = "PhoenixShieldRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = PHOENIX_EFFECT_COLOR
	ring.Transparency = 0.32
	ring.Size = Vector3.new(0.24, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(rootPart.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace

	local aura = Instance.new("Part")
	aura.Name = "PhoenixShieldAura"
	aura.Shape = Enum.PartType.Ball
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanTouch = false
	aura.CanQuery = false
	aura.Material = Enum.Material.ForceField
	aura.Color = PHOENIX_EFFECT_ACCENT_COLOR
	aura.Transparency = 0.72
	aura.Size = Vector3.new(4.5, 4.5, 4.5)
	aura.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 1.5, 0))
	aura.Parent = Workspace

	local ringTween = TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
		Transparency = 0.82,
	})
	local auraTween = TweenService:Create(aura, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
		Transparency = 1,
	})

	ringTween:Play()
	auraTween:Play()

	task.spawn(function()
		while ring.Parent and aura.Parent and os.clock() < endTime do
			local currentRootPart = getPlayerRootPart(targetPlayer)
			if not currentRootPart then
				break
			end

			ring.CFrame = CFrame.new(currentRootPart.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
			aura.CFrame = CFrame.new(currentRootPart.Position + Vector3.new(0, 1.5, 0))
			RunService.Heartbeat:Wait()
		end

		if ring.Parent then
			ring:Destroy()
		end
		if aura.Parent then
			aura:Destroy()
		end
	end)
end

local function createRubberLaunchEffect(_targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= "Gomu Gomu no Mi" or abilityName ~= "RubberLaunch" then
		return
	end

	local direction = typeof(payload.Direction) == "Vector3" and payload.Direction or Vector3.new(0, 0, -1)
	local distance = math.max(0, tonumber(payload.Distance) or 0)
	local startPosition = typeof(payload.StartPosition) == "Vector3" and payload.StartPosition or nil
	local endPosition = typeof(payload.EndPosition) == "Vector3" and payload.EndPosition or nil

	if not startPosition then
		local rootPart = getRootPart()
		startPosition = rootPart and rootPart.Position or Vector3.zero
	end

	if not endPosition then
		endPosition = startPosition + (direction * distance)
	end

	startPosition += Vector3.new(0, 1.15, 0)
	endPosition += Vector3.new(0, 1.15, 0)

	local segment = endPosition - startPosition
	local segmentLength = segment.Magnitude
	local color = Color3.fromRGB(255, 190, 132)

	if segmentLength > 0.2 then
		local band = Instance.new("Part")
		band.Name = "GomuRubberBand"
		band.Anchored = true
		band.CanCollide = false
		band.CanTouch = false
		band.CanQuery = false
		band.Material = Enum.Material.Neon
		band.Color = color
		band.Transparency = 0.18
		band.Size = Vector3.new(0.38, 0.38, segmentLength)
		band.CFrame = CFrame.lookAt(startPosition:Lerp(endPosition, 0.5), endPosition)
		band.Parent = Workspace

		local tween = TweenService:Create(band, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.08, 0.08, segmentLength * 1.06),
		})

		tween:Play()
		tween.Completed:Connect(function()
			if band.Parent then
				band:Destroy()
			end
		end)
	end

	createGomuPulse("GomuLaunchStart", startPosition, color, 1.25, 3.4, 0.22)
	createGomuPulse("GomuLaunchEnd", endPosition, Color3.fromRGB(255, 232, 198), 0.95, 2.6, 0.2)

	for sampleIndex = 1, 3 do
		local alpha = sampleIndex / 4
		local samplePosition = startPosition:Lerp(endPosition, alpha)
		task.delay((sampleIndex - 1) * 0.03, function()
			createGomuPulse("GomuLaunchTrail", samplePosition, color, 0.5, 1.4, 0.14)
		end)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.Space then
		spaceHeld = true
	end
	setFlightInputKeyState(input.KeyCode, true)

	local fruitName, abilityName = getAbilityForKeyCode(input.KeyCode)
	if fruitName == PHOENIX_FRUIT_NAME and abilityName == PHOENIX_FLIGHT_ABILITY and isPhoenixFlightActive() then
		stopPhoenixFlight()
		return
	end

	if not abilityName or not isLocallyReady(abilityName) then
		return
	end

	requestRemote:FireServer(abilityName, buildAbilityRequestPayload(fruitName, abilityName))
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		spaceHeld = false
	end

	setFlightInputKeyState(input.KeyCode, false)
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

	local resolvedPayload = payload or {}

	if fruitName == "Hie Hie no Mi" and abilityName == "FreezeShot" then
		handleFreezeShotEffect(targetPlayer, resolvedPayload)
		return
	end

	playOptionalEffect(targetPlayer, fruitName, abilityName)
	createFallbackBurstEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	createBomuDetonationEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	createPhoenixFlightEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	createPhoenixShieldEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	createRubberLaunchEffect(targetPlayer, fruitName, abilityName, resolvedPayload)

	if fruitName == PHOENIX_FRUIT_NAME and abilityName == PHOENIX_FLIGHT_ABILITY then
		if targetPlayer == player then
			startPhoenixFlight(resolvedPayload)
		end
		return
	end

	if fruitName == PHOENIX_FRUIT_NAME and abilityName == PHOENIX_SHIELD_ABILITY then
		startPhoenixShield(targetPlayer, resolvedPayload)
		return
	end

	if fruitName == "Hie Hie no Mi" and abilityName == "IceBoost" then
		createIceBoostEffect(targetPlayer, resolvedPayload)
	end

end)

RunService.Heartbeat:Connect(updateFreezeShots)

player.CharacterRemoving:Connect(function()
	activeFireBursts = {}
	local projectileIds = {}
	for projectileId in pairs(activeHieFreezeShots) do
		projectileIds[#projectileIds + 1] = projectileId
	end
	for _, projectileId in ipairs(projectileIds) do
		cleanupFreezeShot(projectileId)
	end
	pendingHieFreezeShotResolutions = {}
	stopPhoenixFlight()
	spaceHeld = false
	flightInputState.Forward = false
	flightInputState.Backward = false
	flightInputState.Left = false
	flightInputState.Right = false
	hazardSuppressionLoopRunning = false
	restoreSuppressedParts(math.huge)
	clearGomuHighlight()
end)

player.CharacterAdded:Connect(function()
	if hasActiveHazardProtection(os.clock()) then
		ensureHazardSuppressionLoop()
	end
end)

player:GetAttributeChangedSignal("EquippedDevilFruit"):Connect(function()
	hookFruitFolderSignals()
	updateCooldownHud(true)
	updateGomuAimAssist()
	if getEquippedFruit() ~= PHOENIX_FRUIT_NAME then
		stopPhoenixFlight()
	end
end)

player:GetAttributeChangedSignal("DevilFruitCooldownBypass"):Connect(function()
	updateCooldownHud(false)
end)

playerGui:GetAttributeChangedSignal(GAMEPLAY_MODAL_OPEN_ATTRIBUTE):Connect(function()
	updateCooldownHud(false)
end)

player.ChildAdded:Connect(function(child)
	if child.Name == "DevilFruit" then
		hookFruitFolderSignals()
		updateCooldownHud(true)
		updateGomuAimAssist()
		if getEquippedFruit() ~= PHOENIX_FRUIT_NAME then
			stopPhoenixFlight()
		end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	updatePhoenixFlight(dt)
	updatePhoenixGlide(dt)
end)

RunService.RenderStepped:Connect(function()
	updateGomuAimAssist()

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
	updateGomuAimAssist()
end)
