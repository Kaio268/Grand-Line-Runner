local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local PlotUpgradeConfig = require(Modules:WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ShipVisuals = require(Modules:WaitForChild("Configs"):WaitForChild("ShipVisuals"))
local Shorten = require(Modules:WaitForChild("Shorten"))
local ShipUpgradeWorldPrompt = require(UiFolder:WaitForChild("ShipUpgrade"):WaitForChild("ShipUpgradeWorldPrompt"))

local plotUpgradeRemote = Remotes:WaitForChild("PlotUpgradeRemote")
local shipUpgradeResultRemote = Remotes:WaitForChild("ShipUpgradeResultRemote", 15)

local ATTR = ShipVisuals.Attributes
local RUNTIME_POINTS = ShipVisuals.RuntimePoints or {}
local RUNTIME_POINTS_FOLDER_NAME = tostring(RUNTIME_POINTS.FolderName or "ShipRuntimePoints")
local UPGRADE_POINT_CONFIG = RUNTIME_POINTS.Upgrade or {}
local WORLD_ADORNEE_NAME = "ShipUpgradeReactAdornee"
local BASE_WORLD_ADORNEE_SIZE = if typeof(UPGRADE_POINT_CONFIG.PromptWorldSize) == "Vector3"
	then UPGRADE_POINT_CONFIG.PromptWorldSize
	else Vector3.new(4.8, 2.7, 0.2)
local PROMPT_WORLD_SCALE = math.clamp(tonumber(UPGRADE_POINT_CONFIG.PromptWorldScale) or 1, 0.25, 3)
local WORLD_ADORNEE_SIZE = Vector3.new(
	BASE_WORLD_ADORNEE_SIZE.X * PROMPT_WORLD_SCALE,
	BASE_WORLD_ADORNEE_SIZE.Y * PROMPT_WORLD_SCALE,
	BASE_WORLD_ADORNEE_SIZE.Z
)
local SURFACE_CANVAS_SIZE = if typeof(UPGRADE_POINT_CONFIG.PromptCanvasSize) == "Vector2"
	then UPGRADE_POINT_CONFIG.PromptCanvasSize
	else Vector2.new(720, 430)
local SURFACE_MAX_DISTANCE = math.max(1, tonumber(UPGRADE_POINT_CONFIG.PromptMaxDistance) or 46)
local SURFACE_ALWAYS_ON_TOP = UPGRADE_POINT_CONFIG.PromptAlwaysOnTop == true
local PROMPT_INPUT_CAN_QUERY = UPGRADE_POINT_CONFIG.PromptInputCanQuery ~= false
local SURFACE_LIGHT_INFLUENCE = math.clamp(tonumber(UPGRADE_POINT_CONFIG.PromptLightInfluence) or 0.15, 0, 1)
local PROMPT_WORLD_OFFSET = if typeof(UPGRADE_POINT_CONFIG.PromptWorldOffset) == "Vector3"
	then UPGRADE_POINT_CONFIG.PromptWorldOffset
	else Vector3.new()
local PROMPT_LOCAL_OFFSET = if typeof(UPGRADE_POINT_CONFIG.PromptLocalOffset) == "Vector3"
	then UPGRADE_POINT_CONFIG.PromptLocalOffset
	else Vector3.new()
local PROMPT_YAW_OFFSET_RADIANS = math.rad(tonumber(UPGRADE_POINT_CONFIG.PromptYawOffsetDegrees) or 0)

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactShipUpgradeWorldRoot"

local surfaceGui = Instance.new("SurfaceGui")
surfaceGui.Name = "ShipUpgradeWorldSurfaceGui"
surfaceGui.AlwaysOnTop = SURFACE_ALWAYS_ON_TOP
surfaceGui.CanvasSize = SURFACE_CANVAS_SIZE
surfaceGui.ClipsDescendants = true
surfaceGui.Enabled = false
surfaceGui.Face = Enum.NormalId.Front
surfaceGui.LightInfluence = SURFACE_LIGHT_INFLUENCE
surfaceGui.ResetOnSpawn = false
surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
	surfaceGui.MaxDistance = SURFACE_MAX_DISTANCE
end)
surfaceGui.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)
local activeShipsFolder = nil
local activeShip = nil
local upgradeMarker = nil
local fallbackCFrame = nil
local worldAdornee = nil
local pendingPurchase = false
local destroyed = false
local renderQueued = false
local dataRootWatcherBound = false
local warnedKeys = {}
local cleanupConnections = {}
local dataConnections = {}
local activeShipConnections = {}

local MATERIAL_ALIASES = {
	Timber = { "CommonShipMaterial" },
	Iron = { "RareShipMaterial" },
}

local function warnOnce(key, message, ...)
	if warnedKeys[key] then
		return
	end

	warnedKeys[key] = true
	warn(string.format(message, ...))
end

local function track(connection, bucket)
	if connection then
		bucket[#bucket + 1] = connection
	end
	return connection
end

local function disconnectAll(bucket)
	for _, connection in ipairs(bucket) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(bucket)
end

local function resolveWorkspacePath(pathSegments)
	local current = Workspace
	for _, segment in ipairs(pathSegments or {}) do
		current = current and current:WaitForChild(segment, 30)
		if not current then
			return nil
		end
	end
	return current
end

local function getInstanceCFrame(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	if instance:IsA("Attachment") then
		return instance.WorldCFrame
	end

	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	return nil
end

local function isRuntimePointDescendant(instance)
	local folder = activeShip and activeShip:FindFirstChild(RUNTIME_POINTS_FOLDER_NAME)
	return folder ~= nil and instance ~= nil and instance:IsDescendantOf(folder)
end

local function findMarkerByName(markerName)
	if not activeShip then
		return nil
	end

	local directMarker = activeShip:FindFirstChild(markerName, true)
	if directMarker and not isRuntimePointDescendant(directMarker) then
		return directMarker
	end

	for _, descendant in ipairs(activeShip:GetDescendants()) do
		if descendant.Name == markerName and not isRuntimePointDescendant(descendant) then
			return descendant
		end
	end

	return nil
end

local function findUpgradeMarker()
	for _, markerName in ipairs(UPGRADE_POINT_CONFIG.MarkerNames or { "ShipUpgradePoint" }) do
		local marker = findMarkerByName(tostring(markerName))
		if getInstanceCFrame(marker) then
			return marker
		end
	end

	return nil
end

local function getConfigVector3(value, fallback)
	return if typeof(value) == "Vector3" then value else fallback
end

local function getFlatLookVector(sourceCFrame)
	local lookVector = sourceCFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude > 0.001 then
		return flatLook.Unit
	end

	local rightVector = sourceCFrame.RightVector
	local flatRight = Vector3.new(rightVector.X, 0, rightVector.Z)
	if flatRight.Magnitude > 0.001 then
		local flatRightUnit = flatRight.Unit
		return Vector3.new(flatRightUnit.Z, 0, -flatRightUnit.X).Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getShipFacingCFrameAt(position)
	local shipPivot = activeShip and activeShip:GetPivot()
	local flatLook = shipPivot and getFlatLookVector(shipPivot) or Vector3.new(0, 0, -1)
	local uprightCFrame = CFrame.lookAt(position, position + flatLook, Vector3.yAxis)
		* CFrame.Angles(0, PROMPT_YAW_OFFSET_RADIANS, 0)
	local adjustedPosition = uprightCFrame.Position
		+ PROMPT_WORLD_OFFSET
		+ uprightCFrame:VectorToWorldSpace(PROMPT_LOCAL_OFFSET)

	return CFrame.lookAt(adjustedPosition, adjustedPosition + uprightCFrame.LookVector, Vector3.yAxis)
end

local function getUpgradeFallbackCFrame()
	if not activeShip then
		return nil
	end

	local fallback = UPGRADE_POINT_CONFIG.Fallback
	if typeof(fallback) ~= "table" then
		return activeShip:GetPivot()
	end

	local boxCFrame, boxSize = activeShip:GetBoundingBox()
	local positionScale = getConfigVector3(fallback.PositionScale, Vector3.new(0.6, 0.2, 0))
	local localOffset = getConfigVector3(fallback.LocalOffset, Vector3.new())
	local worldOffset = getConfigVector3(fallback.WorldOffset, Vector3.new())
	local scaledOffset = Vector3.new(
		boxSize.X * positionScale.X,
		boxSize.Y * positionScale.Y,
		boxSize.Z * positionScale.Z
	)
	local position = boxCFrame:PointToWorldSpace(scaledOffset + localOffset) + worldOffset
	return CFrame.new(position)
end

local function getUpgradeTargetCFrame()
	local markerCFrame = getInstanceCFrame(upgradeMarker)
	if markerCFrame then
		return getShipFacingCFrameAt(markerCFrame.Position)
	end

	return fallbackCFrame and getShipFacingCFrameAt(fallbackCFrame.Position) or nil
end

local function destroyWorldAdornee()
	if worldAdornee then
		worldAdornee:Destroy()
		worldAdornee = nil
	end

	surfaceGui.Adornee = nil
	surfaceGui.Enabled = false
end

local function getRuntimePointsFolder()
	if not activeShip then
		return nil
	end

	local folder = activeShip:FindFirstChild(RUNTIME_POINTS_FOLDER_NAME)
	if folder and not folder:IsA("Folder") then
		return nil
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = RUNTIME_POINTS_FOLDER_NAME
		folder.Parent = activeShip
	end

	return folder
end

local function getOrCreateWorldAdornee()
	if worldAdornee and worldAdornee.Parent then
		return worldAdornee
	end

	local folder = getRuntimePointsFolder()
	if not folder then
		return nil
	end

	local part = folder:FindFirstChild(WORLD_ADORNEE_NAME)
	if part and not part:IsA("BasePart") then
		part:Destroy()
		part = nil
	end

	if not part then
		part = Instance.new("Part")
		part.Name = WORLD_ADORNEE_NAME
		part.Parent = folder
	end

	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = PROMPT_INPUT_CAN_QUERY
	part.CanTouch = false
	part.CastShadow = false
	part.Size = WORLD_ADORNEE_SIZE
	part.Transparency = 1
	worldAdornee = part

	return part
end

local function updateWorldPromptAdornee()
	local targetCFrame = getUpgradeTargetCFrame()
	if not activeShip or not targetCFrame then
		destroyWorldAdornee()
		return
	end

	local part = getOrCreateWorldAdornee()
	if not part then
		destroyWorldAdornee()
		return
	end

	part.Size = WORLD_ADORNEE_SIZE
	part.CFrame = targetCFrame
	surfaceGui.Adornee = part
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.Enabled = true
end

local function isOwnedShip(ship)
	return ship
		and ship:IsA("Model")
		and ship:GetAttribute(ATTR.OwnerUserId) == player.UserId
end

local function refreshUpgradeMarker()
	upgradeMarker = findUpgradeMarker()
	if upgradeMarker then
		fallbackCFrame = nil
		updateWorldPromptAdornee()
		return
	end

	fallbackCFrame = getUpgradeFallbackCFrame()
	local shipName = activeShip and tostring(activeShip:GetAttribute(ATTR.ActiveModelName) or activeShip.Name) or "<none>"
	warnOnce(
		"missing_upgrade_marker_" .. shipName,
		"[ShipUpgradeWorld] %s is missing ShipUpgradePoint; using bounding-box fallback for the React upgrade prompt.",
		shipName
	)
	updateWorldPromptAdornee()
end

local refreshActiveShip

local function setActiveShip(nextShip)
	if activeShip == nextShip then
		refreshUpgradeMarker()
		return
	end

	disconnectAll(activeShipConnections)
	destroyWorldAdornee()
	activeShip = nextShip
	upgradeMarker = nil
	fallbackCFrame = nil

	if not activeShip then
		return
	end

	local observedShip = activeShip

	track(observedShip.AncestryChanged:Connect(function(_, parent)
		if parent == nil and activeShip == observedShip then
			task.defer(refreshActiveShip)
		end
	end), activeShipConnections)

	track(observedShip.DescendantAdded:Connect(function(descendant)
		if activeShip == observedShip and table.find(UPGRADE_POINT_CONFIG.MarkerNames or {}, descendant.Name) then
			refreshUpgradeMarker()
		end
	end), activeShipConnections)

	track(observedShip.DescendantRemoving:Connect(function(descendant)
		if activeShip == observedShip
			and (descendant == upgradeMarker or table.find(UPGRADE_POINT_CONFIG.MarkerNames or {}, descendant.Name))
		then
			task.defer(refreshUpgradeMarker)
		end
	end), activeShipConnections)

	refreshUpgradeMarker()
end

function refreshActiveShip()
	if not activeShipsFolder then
		setActiveShip(nil)
		return
	end

	for _, ship in ipairs(activeShipsFolder:GetChildren()) do
		if isOwnedShip(ship) then
			setActiveShip(ship)
			return
		end
	end

	setActiveShip(nil)
end

local function getValueObject(folderName, valueName)
	local folder = player:FindFirstChild(folderName)
	local valueObject = folder and folder:FindFirstChild(valueName)
	if valueObject and valueObject:IsA("ValueBase") then
		return valueObject
	end

	return nil
end

local function readNumericValue(folderName, valueName, fallback)
	local valueObject = getValueObject(folderName, valueName)
	if valueObject and typeof(valueObject.Value) == "number" then
		return valueObject.Value
	end

	return fallback or 0
end

local function getUpgradeLevel()
	return PlotUpgradeConfig.ClampLevel(readNumericValue(
		"HiddenLeaderstats",
		PlotUpgradeConfig.InternalStatName or "PlotUpgrade",
		0
	))
end

local function getRebirthCount()
	return math.max(0, math.floor(readNumericValue("leaderstats", "Rebirths", 0)))
end

local function getBeli()
	local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
	return math.max(0, tonumber(moneyValue and moneyValue.Value) or 0)
end

local function getMaterialAmount(materialKey)
	local materials = player:FindFirstChild("Materials")
	local function consider(name)
		local valueObject = materials and materials:FindFirstChild(name)
		return math.max(0, tonumber(valueObject and valueObject.Value) or 0)
	end

	local best = consider(materialKey)
	for _, alias in ipairs(MATERIAL_ALIASES[materialKey] or {}) do
		best = math.max(best, consider(alias))
	end

	return best
end

local function getMaterialDisplayName(materialKey)
	return tostring(PlotUpgradeConfig.MaterialDisplayNames[materialKey] or materialKey)
end

local function formatCostNumber(amount)
	return Shorten.roundNumber(math.max(0, tonumber(amount) or 0))
end

local function formatBonus(percent)
	return string.format("+%d%%", math.max(0, math.floor(tonumber(percent) or 0)))
end

local function formatCostRatio(currentAmount, requiredAmount)
	return string.format("%s / %s", formatCostNumber(currentAmount), formatCostNumber(requiredAmount))
end

local function buildViewModel()
	local currentLevel = getUpgradeLevel()
	local currentInfo = ShipVisuals.GetUpgradeLevelInfo(currentLevel)
	local currentCaptain = ShipVisuals.GetCaptainSlotInfoForUpgradeLevel(currentLevel)
	local isMaxLevel = PlotUpgradeConfig.IsMaxLevel(currentLevel)
	local nextLevel = PlotUpgradeConfig.GetNextLevel(currentLevel)
	local nextInfo = nextLevel and ShipVisuals.GetUpgradeLevelInfo(nextLevel) or currentInfo
	local nextCaptain = nextLevel and ShipVisuals.GetCaptainSlotInfoForUpgradeLevel(nextLevel) or currentCaptain
	local requirement = PlotUpgradeConfig.GetRequirementForLevel(currentLevel)
	local rebirths = getRebirthCount()
	local requirements = {}
	local canBuy = not isMaxLevel and typeof(requirement) == "table"

	local function pushRequirement(entry)
		requirements[#requirements + 1] = entry
		if entry.Ok == false then
			canBuy = false
		end
	end

	if isMaxLevel then
		pushRequirement({
			Kind = "Max",
			Label = "Complete",
			Ok = true,
			Owned = 1,
			Required = 1,
			Text = "Ship fully upgraded",
		})
	else
		local beliRequired = math.max(0, tonumber(requirement and requirement.Beli) or 0)
		local beliCurrent = getBeli()
		pushRequirement({
			Kind = "Beli",
			Label = CurrencyUtil.getDisplayName(),
			Ok = beliCurrent >= beliRequired,
			Owned = beliCurrent,
			Required = beliRequired,
			Text = formatCostRatio(beliCurrent, beliRequired),
		})

		for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder or {}) do
			local requiredAmount = PlotUpgradeConfig.GetMaterialCost(requirement, materialKey)
			if requiredAmount > 0 then
				local currentAmount = getMaterialAmount(materialKey)
				pushRequirement({
					Kind = materialKey,
					Label = getMaterialDisplayName(materialKey),
					Ok = currentAmount >= requiredAmount,
					Owned = currentAmount,
					Required = requiredAmount,
					Text = formatCostRatio(currentAmount, requiredAmount),
				})
			end
		end

		local requiredRebirths = math.max(0, math.floor(tonumber(requirement and requirement.Rebirths) or 0))
		if requiredRebirths > 0 then
			pushRequirement({
				Kind = "Rebirth",
				Label = "Rebirth",
				Ok = rebirths >= requiredRebirths,
				Owned = rebirths,
				Required = requiredRebirths,
				Text = string.format("%d / %d", rebirths, requiredRebirths),
			})
		end
	end

	local currentSlots = tonumber(currentInfo and currentInfo.NormalCrewSlots) or 0
	local nextSlots = tonumber(nextInfo and nextInfo.NormalCrewSlots) or currentSlots
	local currentBonus = tonumber(currentCaptain and currentCaptain.BonusPercent) or 0
	local nextBonus = tonumber(nextCaptain and nextCaptain.BonusPercent) or currentBonus
	local buttonText = "Upgrade Ship"
	if isMaxLevel then
		buttonText = "Max"
	elseif pendingPurchase then
		buttonText = "Buying"
	elseif not canBuy then
		buttonText = "Not Enough Resources"
	end

	local currentShipLabel = string.format("Lv %d Ship", currentLevel)
	local nextShipLabel = string.format("Lv %d Ship", nextLevel or currentLevel)
	local description = if isMaxLevel
		then "Your ship progression is fully maxed."
		else string.format(
			"%s -> %s | %s",
			currentShipLabel,
			nextShipLabel,
			PlotUpgradeConfig.GetNextUnlockDescription(currentLevel)
		)

	return {
		ButtonText = buttonText,
		CanBuy = canBuy and not isMaxLevel,
		CaptainText = if nextBonus ~= currentBonus
			then string.format("%s -> %s", formatBonus(currentBonus), formatBonus(nextBonus))
			else formatBonus(currentBonus),
		CostLines = requirements,
		Requirements = requirements,
		Description = description,
		LevelText = if isMaxLevel
			then string.format("Lv %d / %d", currentLevel, PlotUpgradeConfig.MaxLevel)
			else string.format("Lv %d -> %d", currentLevel, nextLevel or currentLevel),
		Pending = pendingPurchase,
		SlotText = if nextSlots ~= currentSlots
			then string.format("%d -> %d", currentSlots, nextSlots)
			else tostring(currentSlots),
		Title = "Ship Upgrade",
	}
end

local function render()
	root:render(ReactRoblox.createPortal(React.createElement(ShipUpgradeWorldPrompt, {
		Compact = false,
		OnBuy = function()
			if pendingPurchase then
				return
			end

			local viewModel = buildViewModel()
			if viewModel.CanBuy ~= true then
				return
			end

			pendingPurchase = true
			plotUpgradeRemote:FireServer()
			render()
		end,
		View = buildViewModel(),
	}), surfaceGui))
end

local function scheduleRender()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			render()
		end
	end)
end

local function bindDataTracking()
	disconnectAll(dataConnections)

	local watchedRoots = {
		HiddenLeaderstats = true,
		leaderstats = true,
		Materials = true,
	}

	local function watchRoot(rootName)
		local rootFolder = player:FindFirstChild(rootName)
		if not rootFolder then
			return
		end

		local function handleChanged()
			if rootName == "HiddenLeaderstats" then
				pendingPurchase = false
			end
			scheduleRender()
		end

		for _, descendant in ipairs(rootFolder:GetDescendants()) do
			if descendant:IsA("ValueBase") then
				track(descendant:GetPropertyChangedSignal("Value"):Connect(handleChanged), dataConnections)
			end
		end

		track(rootFolder.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("ValueBase") then
				track(descendant:GetPropertyChangedSignal("Value"):Connect(handleChanged), dataConnections)
			end
			handleChanged()
		end), dataConnections)
		track(rootFolder.DescendantRemoving:Connect(handleChanged), dataConnections)
	end

	for rootName in pairs(watchedRoots) do
		watchRoot(rootName)
	end

	if not dataRootWatcherBound then
		dataRootWatcherBound = true
		track(player.ChildAdded:Connect(function(child)
			if watchedRoots[child.Name] then
				bindDataTracking()
				scheduleRender()
			end
		end), cleanupConnections)
		track(player.ChildRemoved:Connect(function(child)
			if watchedRoots[child.Name] then
				bindDataTracking()
				scheduleRender()
			end
		end), cleanupConnections)
	end
end

bindDataTracking()
render()

task.spawn(function()
	local shipSystem = resolveWorkspacePath(ShipVisuals.ShipSystemPath)
	activeShipsFolder = shipSystem and shipSystem:WaitForChild(ShipVisuals.ActiveShipsName, 30)
	if not activeShipsFolder then
		warnOnce("missing_active_ships", "[ShipUpgradeWorld] Missing active ships folder; upgrade prompt will stay hidden.")
		return
	end

	track(activeShipsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			track(child:GetAttributeChangedSignal(ATTR.OwnerUserId):Connect(function()
				task.defer(refreshActiveShip)
			end), cleanupConnections)
		end
		task.defer(refreshActiveShip)
	end), cleanupConnections)
	track(activeShipsFolder.ChildRemoved:Connect(function()
		task.defer(refreshActiveShip)
	end), cleanupConnections)

	for _, child in ipairs(activeShipsFolder:GetChildren()) do
		if child:IsA("Model") then
			track(child:GetAttributeChangedSignal(ATTR.OwnerUserId):Connect(function()
				task.defer(refreshActiveShip)
			end), cleanupConnections)
		end
	end

	refreshActiveShip()
end)

if shipUpgradeResultRemote and shipUpgradeResultRemote:IsA("RemoteEvent") then
	track(shipUpgradeResultRemote.OnClientEvent:Connect(function()
		pendingPurchase = false
		scheduleRender()
	end), cleanupConnections)
end

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll(cleanupConnections)
	disconnectAll(dataConnections)
	disconnectAll(activeShipConnections)
	destroyWorldAdornee()
	root:unmount()
	surfaceGui:Destroy()
end)
