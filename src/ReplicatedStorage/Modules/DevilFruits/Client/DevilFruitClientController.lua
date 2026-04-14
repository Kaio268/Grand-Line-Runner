local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DevilFruitClientController = {}
local started = false

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local SharedFolder = DevilFruits:WaitForChild("Shared")
local Registry = require(SharedFolder:WaitForChild("Registry"))
local DevilFruitLogger = require(SharedFolder:WaitForChild("DevilFruitLogger"))
local DevilFruitRemotes = require(SharedFolder:WaitForChild("DevilFruitRemotes"))
local ClientEffectVisuals = require(Modules:WaitForChild("DevilFruits"):WaitForChild("ClientEffectVisuals"))
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))
local ProtectionRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("ProtectionRuntime"))
local FruitModuleLoader = require(SharedFolder:WaitForChild("FruitModuleLoader"))
local DevilFruitInputController = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitInputController"))
local DevilFruitEffectRouter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitEffectRouter"))
local DevilFruitUiController = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitUiController"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GAMEPLAY_MODAL_OPEN_ATTRIBUTE = "GameplayModalOpen"

local GOMU_AIM_RAY_DISTANCE = 500
local GOMU_HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 176, 120)
local GOMU_HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 243, 231)
local GOMU_AUTO_LATCH_MAX_ALIGNMENT = math.cos(math.rad(18))
local GOMU_AUTO_LATCH_BASE_RADIUS = 4
local GOMU_AUTO_LATCH_RADIUS_FACTOR = 0.14
local MOGU_FRUIT_NAME = "Mogu Mogu no Mi"
local MOGU_BURROW_ABILITY = "Burrow"
local PHOENIX_FRUIT_NAME = "Tori Tori no Mi"
local PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local HAZARD_SUPPRESSION_INTERVAL = 0.05
local PHOENIX_SHIELD_PADDING = 2.5
local PHOENIX_VERTICAL_DEADZONE = 0.12
local MIN_DIRECTION_MAGNITUDE = 0.01
local MERA_AUDIT_MARKER = "MERA_AUDIT_2026_03_30_V4"
local DEFAULT_MOGU_HAZARD_PROTECTION_RADIUS = 12

local RemoteBundle = DevilFruitRemotes.GetBundle()
local requestRemote = RemoteBundle.Request
local stateRemote = RemoteBundle.State
local effectRemote = RemoteBundle.Effect

local localCooldowns = {}
local suppressedParts = {}
local activeFireBursts = {}
local activePhoenixShields = {}
local activeMoguBurrow = nil
local hazardSuppressionLoopRunning = false
local spaceHeld = false
local flightInputState = {
	Forward = false,
	Backward = false,
	Left = false,
	Right = false,
}
local playOptionalEffect
local getFruitFolder
local getEquippedFruit
local fruitModuleLoader
local inputController
local effectRouter
local syncDevilFruitClientState
local lastSyncedFruitName = DevilFruitConfig.None
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

local function logDevilFruitClient(message, ...)
	print(string.format("[DEVILFRUIT CLIENT] " .. message, ...))
end

local function logDevilFruitRequest(message, ...)
	if not RunService:IsStudio() then
		return
	end

	DevilFruitLogger.Info("REQUEST", message, ...)
end

local function countPayloadKeys(payload)
	if typeof(payload) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(payload) do
		count += 1
	end

	return count
end

local function describeRemote(instance)
	return DevilFruitRemotes.DescribeInstance(instance)
end

local function formatVector3ForLog(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function describePayloadForAudit(payload)
	if typeof(payload) ~= "table" then
		return string.format("type=%s value=%s", typeof(payload), formatVector3ForLog(payload))
	end

	local keys = {}
	for key in pairs(payload) do
		keys[#keys + 1] = key
	end

	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)

	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = string.format("%s=%s", tostring(key), formatVector3ForLog(payload[key]))
	end

	return string.format("type=table keys=%d payload={%s}", #keys, table.concat(parts, ", "))
end

local function shouldTraceAbilityInput(keyCode)
	return keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.E
end

local function normalizeEquippedFruitName(fruitIdentifier)
	if typeof(fruitIdentifier) ~= "string" then
		return DevilFruitConfig.None
	end

	if fruitIdentifier == DevilFruitConfig.None or fruitIdentifier == "None" then
		return DevilFruitConfig.None
	end

	return Registry.ResolveFruitName(fruitIdentifier) or fruitIdentifier
end

local function formatAbilityName(abilityName)
	return DevilFruitUiController.FormatAbilityName(abilityName)
end

local function formatCooldownTime(seconds)
	return DevilFruitUiController.FormatCooldownTime(seconds)
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
	return DevilFruitUiController.GetOrderedAbilities(fruitName)
end

local function shouldShowCooldownHud(fruitName)
	return DevilFruitUiController.ShouldShowCooldownHud(fruitName)
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
	local fruitFolder = getFruitFolder()
	if fruitFolder then
		local equipped = fruitFolder:FindFirstChild("Equipped")
		if equipped and equipped:IsA("StringValue") then
			return normalizeEquippedFruitName(equipped.Value)
		end
	end

	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		return normalizeEquippedFruitName(fruitAttribute)
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
		if typeof(syncDevilFruitClientState) == "function" then
			task.defer(syncDevilFruitClientState)
			return
		end

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
	if inputController then
		local resolvedFruitName, abilityName, abilityEntry = inputController:GetAbilityForKeyCode(fruitName, keyCode)
		if resolvedFruitName and abilityName then
			return resolvedFruitName, abilityName, abilityEntry
		end
	end

	local fruit = DevilFruitConfig.GetFruit(fruitName)
	if not fruit or not fruit.Abilities then
		return nil, nil, nil
	end

	for abilityName, abilityConfig in pairs(fruit.Abilities) do
		if abilityConfig.KeyCode == keyCode then
			return fruitName, abilityName, Registry.GetAbility(fruitName, abilityName)
		end
	end

	return nil, nil, nil
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

local clientEffectVisuals = ClientEffectVisuals.new({
	GetLocalRootPart = getRootPart,
	GetPlayerRootPart = getPlayerRootPart,
	MinDirectionMagnitude = MIN_DIRECTION_MAGNITUDE,
	PhoenixFruitName = PHOENIX_FRUIT_NAME,
	PhoenixFlightAbility = PHOENIX_FLIGHT_ABILITY,
	PhoenixShieldAbility = PHOENIX_SHIELD_ABILITY,
})

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

local function getDistanceFromRay(rayOrigin, rayDirection, point)
	local toPoint = point - rayOrigin
	local projectedDistance = math.max(0, toPoint:Dot(rayDirection))
	local closestPoint = rayOrigin + (rayDirection * projectedDistance)
	return (point - closestPoint).Magnitude, projectedDistance
end

local isGomuTargetInRange

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

isGomuTargetInRange = function(targetPlayer, maxDistance)
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

local function buildDefaultAbilityRequestPayload(fruitName, abilityName)
	return nil
end

local function buildAbilityRequestPayload(fruitName, abilityName)
	local abilityEntry = Registry.GetAbility(fruitName, abilityName)
	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") or nil
	local moveDirection = humanoid and humanoid.MoveDirection or nil
	logDevilFruitRequest(
		"client build begin fruit=%s ability=%s abilityEntry=%s character=%s humanoid=%s root=%s moveDir=%s lookDir=%s",
		tostring(fruitName),
		tostring(abilityName),
		tostring(abilityEntry ~= nil),
		tostring(character ~= nil),
		tostring(humanoid ~= nil),
		tostring(rootPart ~= nil),
		formatVector3ForLog(moveDirection),
		formatVector3ForLog(rootPart and rootPart.CFrame.LookVector or nil)
	)
	if inputController then
		local payload = inputController:BuildRequestPayload(fruitName, abilityName, abilityEntry, function()
			return buildDefaultAbilityRequestPayload(fruitName, abilityName)
		end)
		logDevilFruitRequest(
			"client build end fruit=%s ability=%s payloadKeys=%d",
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(payload)
		)
		return payload
	end

	local fallbackPayload = buildDefaultAbilityRequestPayload(fruitName, abilityName)
	logDevilFruitRequest(
		"client build end fruit=%s ability=%s payloadKeys=%d source=default_builder_only",
		tostring(fruitName),
		tostring(abilityName),
		countPayloadKeys(fallbackPayload)
	)
	return fallbackPayload
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

local function getMoguHazardProtectionRadius()
	local abilityConfig = DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}
	return math.max(0, tonumber(abilityConfig.HazardProtectionRadius) or DEFAULT_MOGU_HAZARD_PROTECTION_RADIUS)
end

local function isLocalPlayerBurrowProtected(now)
	if type(activeMoguBurrow) ~= "table" then
		return false
	end

	if now >= (activeMoguBurrow.EndTime or 0) then
		activeMoguBurrow = nil
		return false
	end

	return true
end

ProtectionRuntime.Register("MoguBurrowProtection", function(targetPlayer, position)
	if targetPlayer ~= player then
		return false
	end

	return isLocalPlayerBurrowProtected(os.clock())
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

	if isLocalPlayerBurrowProtected(now) then
		return true
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

	if isLocalPlayerBurrowProtected(now) then
		if rootPart then
			suppressHazardsNearPosition(rootPart.Position, activeMoguBurrow.Radius, activeMoguBurrow.EndTime)
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

local function startMoguBurrow(targetPlayer, payload)
	if targetPlayer ~= player then
		return
	end

	local resolvedPayload = payload or {}
	local duration = math.max(0, tonumber(resolvedPayload.Duration) or 0)
	if duration <= 0 then
		duration = math.max(0.5, tonumber((DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}).BurrowDuration) or 5)
	end

	activeMoguBurrow = {
		EndTime = os.clock() + duration,
		Radius = math.max(0, tonumber(resolvedPayload.HazardProtectionRadius) or getMoguHazardProtectionRadius()),
	}

	ensureHazardSuppressionLoop()
end

local function stopMoguBurrow(targetPlayer)
	if targetPlayer ~= player then
		return
	end

	activeMoguBurrow = nil
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

fruitModuleLoader = FruitModuleLoader.new({
	player = player,
	clientEffectVisuals = clientEffectVisuals,
	GetCharacter = getCharacter,
	GetCurrentCamera = getCurrentCamera,
	GetEquippedFruit = getEquippedFruit,
	GetHumanoid = getHumanoid,
	GetLocalRootPart = getRootPart,
	GetPlayerRootPart = getPlayerRootPart,
	PlayOptionalEffect = playOptionalEffect,
	RequestAbility = function(abilityName, payload)
		requestRemote:FireServer(abilityName, payload)
	end,
	CreateEffectVisual = function(startPosition, endPosition, direction, isPredicted)
		clientEffectVisuals:CreateMeraFlameDashEffectVisual(startPosition, endPosition, direction, isPredicted)
	end,
})
inputController = DevilFruitInputController.new({
	player = player,
	loader = fruitModuleLoader,
})
effectRouter = DevilFruitEffectRouter.new({
	player = player,
	loader = fruitModuleLoader,
	playOptionalEffect = playOptionalEffect,
	clientEffectVisuals = clientEffectVisuals,
})

local function initializeDevilFruitClient()
	logDevilFruitClient("init begin")
	local requestIdentity = describeRemote(requestRemote)
	logDevilFruitClient(
		"remote bundle resolved request=%s path=%s runtimeId=%s debugId=%s object=%s state=%s effect=%s folder=%s",
		tostring(requestIdentity.Name),
		tostring(requestIdentity.Path),
		tostring(requestIdentity.RuntimeId),
		tostring(requestIdentity.DebugId),
		tostring(requestIdentity.Object),
		tostring(describeRemote(stateRemote).Path),
		tostring(describeRemote(effectRemote).Path),
		tostring(RemoteBundle.Folder:GetFullName())
	)

	syncDevilFruitClientState = function()
		local currentFruitName = getEquippedFruit()
		local previousFruitName = lastSyncedFruitName
		if currentFruitName ~= lastSyncedFruitName then
			fruitModuleLoader:CallControllerMethod(previousFruitName, "HandleUnequipped", currentFruitName)
			logDevilFruitClient(
				"fruit changed previous=%s current=%s",
				tostring(lastSyncedFruitName),
				tostring(currentFruitName)
			)
			lastSyncedFruitName = currentFruitName
		end

		local warmedController = fruitModuleLoader:GetController(currentFruitName)
		if warmedController and currentFruitName ~= previousFruitName then
			fruitModuleLoader:CallControllerMethod(currentFruitName, "HandleEquipped", previousFruitName)
		end

		hookFruitFolderSignals()
		updateCooldownHud(true)
		local fruitFolder = getFruitFolder()
		local equippedValue = fruitFolder and fruitFolder:FindFirstChild("Equipped")
		local equippedValueText = equippedValue and equippedValue:IsA("StringValue") and equippedValue.Value or "<nil>"
		logDevilFruitClient(
			"fruit state synced equipped=%s attr=%s value=%s",
			tostring(currentFruitName),
			tostring(player:GetAttribute("EquippedDevilFruit")),
			tostring(equippedValueText)
		)
	end

	ensureCooldownHud()
	logDevilFruitClient("UI bind success")

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local traceAbilityInput = shouldTraceAbilityInput(input.KeyCode)
		local equippedFruitName = traceAbilityInput and getEquippedFruit() or nil
		local focusedTextBox = UserInputService:GetFocusedTextBox()
		if traceAbilityInput then
			logDevilFruitClient(
				"bind raw key=%s processed=%s focused=%s modal=%s equipped=%s",
				tostring(input.KeyCode.Name),
				tostring(gameProcessed),
				tostring(focusedTextBox ~= nil),
				tostring(isGameplayModalOpen()),
				tostring(equippedFruitName)
			)
		end

		if gameProcessed then
			if traceAbilityInput then
				logDevilFruitClient(
					"bind blocked key=%s reason=game_processed equipped=%s",
					tostring(input.KeyCode.Name),
					tostring(equippedFruitName)
				)
			end
			return
		end

		if focusedTextBox then
			if traceAbilityInput then
				logDevilFruitClient(
					"bind blocked key=%s reason=textbox_focus textbox=%s equipped=%s",
					tostring(input.KeyCode.Name),
					tostring(focusedTextBox:GetFullName()),
					tostring(equippedFruitName)
				)
			end
			return
		end

		local handledByCurrentFruit, shouldConsumeInput = fruitModuleLoader:CallControllerMethod(
			equippedFruitName or getEquippedFruit(),
			"HandleInputBegan",
			input,
			gameProcessed
		)
		if handledByCurrentFruit and shouldConsumeInput then
			return
		end

		local fruitName, abilityName, abilityEntry = getAbilityForKeyCode(input.KeyCode)
		if traceAbilityInput then
			logDevilFruitClient(
				"bind lookup key=%s equipped=%s resolvedFruit=%s ability=%s hasEntry=%s",
				tostring(input.KeyCode.Name),
				tostring(equippedFruitName),
				tostring(fruitName),
				tostring(abilityName),
				tostring(abilityEntry ~= nil)
			)
		end
		if not abilityName then
			if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
				logDevilFruitClient(
					"bind ignored key=%s equipped=%s reason=no_ability",
					tostring(input.KeyCode.Name),
					tostring(fruitName or getEquippedFruit())
				)
			end
			return
		end

		if not isLocallyReady(abilityName) then
			local _, canActivateOnLocalCooldown = fruitModuleLoader:CallControllerMethod(
				fruitName,
				"CanActivateOnLocalCooldown",
				abilityName,
				abilityEntry,
				input
			)
			if canActivateOnLocalCooldown == true then
				logDevilFruitClient(
					"bind bypass local cooldown key=%s fruit=%s ability=%s",
					tostring(input.KeyCode.Name),
					tostring(fruitName),
					tostring(abilityName)
				)
			else
				logDevilFruitClient(
					"bind ignored key=%s fruit=%s ability=%s reason=local_cooldown",
					tostring(input.KeyCode.Name),
					tostring(fruitName),
					tostring(abilityName)
				)
				return
			end
		end

		local requestStartedAt = os.clock()
		local requestIdentity = describeRemote(requestRemote)
		logDevilFruitRequest(
			"client dispatch begin key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(requestIdentity.Name),
			tostring(requestIdentity.Path),
			tostring(requestIdentity.RuntimeId),
			tostring(requestIdentity.DebugId),
			tostring(requestIdentity.Object)
		)
		local requestPayload = inputController:BuildPredictedRequest(fruitName, abilityName, function()
			return buildAbilityRequestPayload(fruitName, abilityName)
		end)
		logDevilFruitClient(
			"bind dispatch key=%s fruit=%s ability=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(requestPayload)
		)
		logDevilFruitClient(
			"remote fire begin key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(requestIdentity.Name),
			tostring(requestIdentity.Path),
			tostring(requestIdentity.RuntimeId),
			tostring(requestIdentity.DebugId),
			tostring(requestIdentity.Object),
			countPayloadKeys(requestPayload)
		)
		if fruitName == "Mera Mera no Mi" then
			logDevilFruitRequest(
				"[%s] Mera FireServer begin ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payload=%s",
				MERA_AUDIT_MARKER,
				tostring(abilityName),
				tostring(requestIdentity.Name),
				tostring(requestIdentity.Path),
				tostring(requestIdentity.RuntimeId),
				tostring(requestIdentity.DebugId),
				tostring(requestIdentity.Object),
				describePayloadForAudit(requestPayload)
			)
		end

		requestRemote:FireServer(abilityName, requestPayload)
		if fruitName == "Mera Mera no Mi" then
			logDevilFruitRequest(
				"[%s] Mera FireServer end ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payload=%s",
				MERA_AUDIT_MARKER,
				tostring(abilityName),
				tostring(requestIdentity.Name),
				tostring(requestIdentity.Path),
				tostring(requestIdentity.RuntimeId),
				tostring(requestIdentity.DebugId),
				tostring(requestIdentity.Object),
				describePayloadForAudit(requestPayload)
			)
		end
		logDevilFruitClient(
			"remote fire end key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(requestIdentity.Name),
			tostring(requestIdentity.Path),
			tostring(requestIdentity.RuntimeId),
			tostring(requestIdentity.DebugId),
			tostring(requestIdentity.Object),
			countPayloadKeys(requestPayload)
		)
		logDevilFruitRequest(
			"client dispatch end key=%s fruit=%s ability=%s payloadKeys=%d elapsedMs=%.2f",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(requestPayload),
			(os.clock() - requestStartedAt) * 1000
		)
		if traceAbilityInput then
			logDevilFruitClient(
				"bind remote fired key=%s fruit=%s ability=%s",
				tostring(input.KeyCode.Name),
				tostring(fruitName),
				tostring(abilityName)
			)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		fruitModuleLoader:CallControllerMethod(getEquippedFruit(), "HandleInputEnded", input)
	end)
	logDevilFruitClient("keybind connect success")

	stateRemote.OnClientEvent:Connect(function(eventName, fruitName, abilityName, value, payload)
		if eventName == "Activated" then
			local readyAt = tonumber(value) or 0
			localCooldowns[abilityName] = readyAt
			updateCooldownHud()

			fruitModuleLoader:CallControllerMethod(fruitName, "HandleStateEvent", eventName, abilityName, value, payload)

			if fruitName == "Mera Mera no Mi" and abilityName == "FireBurst" then
				startFireBurst(payload or {})
			end
			return
		end

		fruitModuleLoader:CallControllerMethod(fruitName, "HandleStateEvent", eventName, abilityName, value, payload)

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

		if fruitName == MOGU_FRUIT_NAME and abilityName == MOGU_BURROW_ABILITY then
			local phase = payload and payload.Phase
			if phase == "Start" then
				startMoguBurrow(targetPlayer, payload)
			elseif phase == "Resolve" then
				stopMoguBurrow(targetPlayer)
			end
		end

		effectRouter:HandleEffect(targetPlayer, fruitName, abilityName, payload)
	end)

	RunService.Heartbeat:Connect(function(dt)
		fruitModuleLoader:ForEachLoadedController("Update", dt)
	end)

	player.CharacterRemoving:Connect(function()
		activeFireBursts = {}
		activeMoguBurrow = nil
		fruitModuleLoader:ForEachLoadedController("HandleCharacterRemoving")
		hazardSuppressionLoopRunning = false
		restoreSuppressedParts(math.huge)
	end)

	Players.PlayerRemoving:Connect(function(leavingPlayer)
		fruitModuleLoader:ForEachLoadedController("HandlePlayerRemoving", leavingPlayer)
	end)

	player.CharacterAdded:Connect(function()
		if hasActiveHazardProtection(os.clock()) then
			ensureHazardSuppressionLoop()
		end
	end)

	player:GetAttributeChangedSignal("EquippedDevilFruit"):Connect(function()
		syncDevilFruitClientState()
	end)

	player:GetAttributeChangedSignal("DevilFruitCooldownBypass"):Connect(function()
		updateCooldownHud(false)
	end)

	playerGui:GetAttributeChangedSignal(GAMEPLAY_MODAL_OPEN_ATTRIBUTE):Connect(function()
		updateCooldownHud(false)
	end)

	player.ChildAdded:Connect(function(child)
		if child.Name == "DevilFruit" then
			syncDevilFruitClientState()
		end
	end)

	RunService.RenderStepped:Connect(function()
		fruitModuleLoader:ForEachLoadedController("RenderUpdate")

		local now = os.clock()
		if now < nextHudRefreshAt then
			return
		end

		nextHudRefreshAt = now + HUD_REFRESH_INTERVAL
		updateCooldownHud(false)
	end)

	task.defer(function()
		local ok, err = xpcall(syncDevilFruitClientState, debug.traceback)
		if not ok then
			warn(string.format("[DEVILFRUIT CLIENT][ERROR] startup failed: %s", tostring(err)))
		end
	end)

	logDevilFruitClient("init success")
end

function DevilFruitClientController.Start()
	if started then
		return DevilFruitClientController
	end

	started = true

	local initOk, initError = xpcall(initializeDevilFruitClient, debug.traceback)
	if not initOk then
		warn(string.format("[DEVILFRUIT CLIENT][ERROR] startup failed: %s", tostring(initError)))
		error(initError)
	end

	return DevilFruitClientController
end

return DevilFruitClientController
