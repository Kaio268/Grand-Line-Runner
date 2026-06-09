local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local BiomeAreas = require(Modules:WaitForChild("Configs"):WaitForChild("BiomeAreas"))
local Economy = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local UiModalState = require(Modules:WaitForChild("UiModalState"))
local HudLayout = require(UiFolder:WaitForChild("HudLayout"))
local BottomRightHudCoordinator = require(UiFolder:WaitForChild("Hud"):WaitForChild("BottomRightHudCoordinator"))
local Responsive = require(UiFolder:WaitForChild("Responsive"))
local BaseHeldCrewPanel = require(UiFolder:WaitForChild("Crew"):WaitForChild("BaseHeldCrewPanel"))

local verticalSliceConfig = Economy.VerticalSlice
if verticalSliceConfig.Enabled ~= true then
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local stateRemote = remotesFolder:WaitForChild(verticalSliceConfig.Remotes.StateEventName)
local crewActionRemote = ReplicatedStorage:WaitForChild("CrewMemberActionRequest", 15)
if crewActionRemote and not crewActionRemote:IsA("RemoteFunction") then
	crewActionRemote = nil
end
local crewActionEvent = ReplicatedStorage:WaitForChild("CrewMemberActionSubmit", 2)
if crewActionEvent and not crewActionEvent:IsA("RemoteEvent") then
	crewActionEvent = nil
end
local crewActionResultEvent = ReplicatedStorage:WaitForChild("CrewMemberActionResult", 2)
if crewActionResultEvent and not crewActionResultEvent:IsA("RemoteEvent") then
	crewActionResultEvent = nil
end

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactBaseHeldCrewRoot"
rootContainer.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)
local modalOpenAttribute = UiModalState.GetAttributeName()
local hudHost = nil

local currentState = nil
local pending = false
local renderQueued = false
local destroyed = false
local connections = {}
local characterConnections = {}
local toolAttributeConnections = {}
local viewportConnection
local cameraConnection
local coordinatorConnection
local crewActionRequestSequence = 0
local pendingCrewActionRequestId = nil

local ACTIVE_AREA_ATTRIBUTE = BiomeAreas.ActiveAreaAttribute
local STARTING_AREA_KEY = BiomeAreas.StartingAreaKey
local RESERVATION_KEY = "BaseHeldCrew"
local DEVIL_FRUIT_RESERVATION_KEY = "DevilFruit"
local HUD_HOST_NAME = "BaseHeldCrewHUDHost"
local HUD_DISPLAY_ORDER = 119
local BASE_AREA_NAMES = {
	"StartingArea",
	"Starting Area",
	"StartArea",
	"BaseArea",
	"Lobby",
}
local TOOL_ATTRIBUTE_NAMES = {
	"CrewMemberInstanceId",
	"CrewInstanceId",
	"CrewMemberDisplayName",
	"DisplayName",
	"CrewMemberId",
	"InventoryItemName",
	"CrewMemberRarity",
	"Variant",
	"CrewMemberVariantTag",
	"CrewMemberVariantDisplayName",
	"CrewMemberShowVariantTag",
	"CrewMemberBaseDisplayName",
	"BaseName",
	"ModelName",
	"RealCharacterName",
	"CrewMemberIncome",
	"CrewMemberLevel",
}
local startingAreaCache = nil

local function ensureHudHost()
	if hudHost and hudHost.Parent == playerGui then
		return hudHost
	end

	local existing = playerGui:FindFirstChild(HUD_HOST_NAME)
	if existing and not existing:IsA("ScreenGui") then
		existing:Destroy()
		existing = nil
	end

	if existing then
		hudHost = existing
	else
		hudHost = Instance.new("ScreenGui")
		hudHost.Name = HUD_HOST_NAME
		hudHost.Parent = playerGui
	end

	hudHost.DisplayOrder = HUD_DISPLAY_ORDER
	hudHost.Enabled = true
	hudHost.IgnoreGuiInset = true
	hudHost.ResetOnSpawn = false
	hudHost.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return hudHost
end

local function trackConnection(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function disconnectCharacter()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	table.clear(toolAttributeConnections)
end

local function findStartingArea()
	if startingAreaCache and startingAreaCache.Parent ~= nil then
		return startingAreaCache
	end

	for _, areaName in ipairs(BASE_AREA_NAMES) do
		local found = Workspace:FindFirstChild(areaName, true)
		if found and (found:IsA("BasePart") or found:IsA("Model")) then
			startingAreaCache = found
			return found
		end
	end

	return nil
end

local function isPointInsidePart(part, position, padding)
	local relative = part.CFrame:PointToObjectSpace(position)
	local halfSize = (part.Size * 0.5) + Vector3.new(padding, padding, padding)
	return math.abs(relative.X) <= halfSize.X
		and math.abs(relative.Y) <= halfSize.Y
		and math.abs(relative.Z) <= halfSize.Z
end

local function isPointInsideModel(model, position, padding)
	local cframe, size = model:GetBoundingBox()
	local relative = cframe:PointToObjectSpace(position)
	local halfSize = (size * 0.5) + Vector3.new(padding, padding, padding)
	return math.abs(relative.X) <= halfSize.X
		and math.abs(relative.Y) <= halfSize.Y
		and math.abs(relative.Z) <= halfSize.Z
end

local function isCharacterInsideStartingArea()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return false
	end

	local area = findStartingArea()
	if area == nil then
		return nil
	end

	local padding = 24
	if area:IsA("BasePart") then
		return isPointInsidePart(area, rootPart.Position, padding)
	elseif area:IsA("Model") then
		return isPointInsideModel(area, rootPart.Position, padding)
	end

	return false
end

local function isInBaseArea()
	local activeArea = Lighting:GetAttribute(ACTIVE_AREA_ATTRIBUTE)
	if typeof(activeArea) == "string" and activeArea ~= "" then
		return activeArea == STARTING_AREA_KEY
	end

	local insideStartingArea = isCharacterInsideStartingArea()
	if insideStartingArea ~= nil then
		return insideStartingArea
	end

	return true
end

local function getRunState()
	return currentState and currentState.Run or nil
end

local function isRunActive()
	local runState = getRunState()
	return typeof(runState) == "table" and runState.InRun == true
end

local function isCrewCarrySlot(slot)
	if typeof(slot) ~= "table" then
		return false
	end

	local itemType = tostring(slot.ItemType or slot.itemType or "")
	local item = if typeof(slot.Item) == "table" then slot.Item else slot.Data
	local rewardType = if typeof(item) == "table" then tostring(item.RewardType or item.Type or item.Kind or "") else ""
	return itemType == "CrewMember" or rewardType == "Crew" or rewardType == "CrewMember" or rewardType == "Crewmate"
end

local function getDisplayName(slot)
	local item = if typeof(slot.Item) == "table" then slot.Item else slot.Data
	if typeof(item) == "table" then
		local displayName = tostring(item.DisplayName or item.CrewDisplayName or item.Name or item.CrewName or "")
		if displayName ~= "" then
			return displayName
		end
	end
	return tostring(slot.DisplayName or "Crewmate")
end

local function getToolCrewInstanceId(tool)
	if not tool or not tool:IsA("Tool") then
		return ""
	end
	return tostring(tool:GetAttribute("CrewMemberInstanceId") or tool:GetAttribute("CrewInstanceId") or "")
end

local function getEquippedHotbarCrew()
	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local instanceId = getToolCrewInstanceId(child)
			if instanceId ~= "" then
				local displayName = tostring(
					child:GetAttribute("CrewMemberDisplayName")
						or child:GetAttribute("DisplayName")
						or child.ToolTip
						or child.Name
				)
				local crewMemberId = tostring(child:GetAttribute("CrewMemberId") or child:GetAttribute("InventoryItemName") or "")
				local rarity = tostring(child:GetAttribute("CrewMemberRarity") or "")
				local variant = tostring(child:GetAttribute("Variant") or "")
				local baseName = tostring(child:GetAttribute("BaseName") or "")
				local displayInfo = CrewCatalog.GetDisplayInfo(if crewMemberId ~= "" then crewMemberId else child.Name, {
					DisplayName = displayName,
					Variant = variant,
					BaseName = baseName,
				})
				displayName = tostring(displayInfo.DisplayName or displayName)
				variant = tostring(displayInfo.Variant or variant)
				local modelName = tostring(child:GetAttribute("ModelName") or baseName)
				local realCharacterName = tostring(child:GetAttribute("RealCharacterName") or "")
				local previewName = modelName
				if previewName == "" then
					previewName = if crewMemberId ~= "" then crewMemberId else displayName
				end

				return {
					SourceKind = "HotbarCrew",
					InstanceId = instanceId,
					DisplayName = if displayName ~= "" then displayName else "Crewmate",
					BaseDisplayName = displayInfo.BaseDisplayName,
					CrewMemberId = crewMemberId,
					Rarity = if rarity ~= "" then rarity else nil,
					CanonicalRarity = if rarity ~= "" then rarity else nil,
					Variant = if variant ~= "" then variant else nil,
					VariantTag = displayInfo.VariantTag,
					VariantDisplayName = displayInfo.VariantDisplayName,
					ShowVariantTag = displayInfo.ShowVariantTag == true,
					BaseName = if baseName ~= "" then baseName else nil,
					ModelName = if modelName ~= "" then modelName else nil,
					PreviewKind = "CrewMember",
					PreviewName = previewName,
					RealCharacterName = if realCharacterName ~= "" then realCharacterName else nil,
					Income = tonumber(child:GetAttribute("CrewMemberIncome")),
					Level = tonumber(child:GetAttribute("CrewMemberLevel")),
				}
			end
		end
	end
	return nil
end

local function getHeldCrewSlot()
	local runState = getRunState()
	local carrySlots = runState and runState.CarrySlots or nil
	if typeof(carrySlots) ~= "table" then
		return nil
	end

	for slotIndex, slot in ipairs(carrySlots) do
		if typeof(slot) == "table" and tostring(slot.CarryId or "") ~= "" and isCrewCarrySlot(slot) then
			return {
				SourceKind = "CarrySlot",
				CarryId = tostring(slot.CarryId),
				SlotIndex = tonumber(slot.SlotIndex) or slotIndex,
				DisplayName = getDisplayName(slot),
			}
		end
	end
	return nil
end

local function setBaseHeldReservation(isVisible, layoutMode, devilFruitRect)
	if isVisible ~= true then
		BottomRightHudCoordinator.ClearReservation(RESERVATION_KEY)
		return
	end

	local layout = HudLayout.getBaseHeldCrewLayout(layoutMode, {
		devilFruitRect = devilFruitRect,
	})
	BottomRightHudCoordinator.SetReservation(RESERVATION_KEY, {
		Padding = layout.reservationPadding,
		Priority = layout.priority,
		Rect = layout.rect,
		Source = RESERVATION_KEY,
		Visible = true,
	})
end

local function render()
	local modalOpen = playerGui:GetAttribute(modalOpenAttribute) == true
	local equippedCrew = getEquippedHotbarCrew()
	local heldItem = equippedCrew or getHeldCrewSlot()
	local visible = equippedCrew ~= nil and isInBaseArea() and modalOpen ~= true and not isRunActive()
	local layoutMode = HudLayout.getMode()
	local devilFruitReservation = BottomRightHudCoordinator.GetReservation(DEVIL_FRUIT_RESERVATION_KEY)
	local devilFruitRect = devilFruitReservation and devilFruitReservation.Rect or nil

	setBaseHeldReservation(visible, layoutMode, devilFruitRect)

	root:render(ReactRoblox.createPortal(React.createElement(BaseHeldCrewPanel, {
		visible = visible,
		pending = pending,
		item = heldItem,
		compact = Responsive.isCompact(),
		devilFruitRect = devilFruitRect,
		layoutMode = layoutMode,
		onStore = function(item)
			if pending or (not crewActionRemote and not crewActionEvent) then
				return
			end

			pending = true
			render()
			local payload
			if item and item.SourceKind == "HotbarCrew" then
				payload = {
					Action = "Unequip",
					InstanceId = item.InstanceId,
				}
			else
				payload = {
					Action = "StoreHeld",
					CarryId = item and item.CarryId,
					SlotIndex = item and item.SlotIndex,
				}
			end
			if crewActionEvent then
				crewActionRequestSequence += 1
				pendingCrewActionRequestId = string.format("%d:%.3f", crewActionRequestSequence, os.clock())
				payload.RequestId = pendingCrewActionRequestId
				crewActionEvent:FireServer(payload)
				local requestId = pendingCrewActionRequestId
				task.delay(8, function()
					if pendingCrewActionRequestId == requestId then
						pendingCrewActionRequestId = nil
						pending = false
						if not destroyed then
							render()
						end
					end
				end)
				return
			end

			task.spawn(function()
				pcall(function()
					return crewActionRemote:InvokeServer(payload)
				end)
				pending = false
				if not destroyed then
					render()
				end
			end)
		end,
	}), ensureHudHost()))
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

local function bindViewportUpdates()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(scheduleRender)
	end

	if not cameraConnection then
		cameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindViewportUpdates()
			scheduleRender()
		end)
	end
end

local function scheduleToolRender()
	scheduleRender()
	task.defer(scheduleRender)
	task.delay(0.15, scheduleRender)
end

local function bindTool(tool)
	if not tool:IsA("Tool") then
		return
	end

	if toolAttributeConnections[tool] == true then
		scheduleToolRender()
		return
	end
	toolAttributeConnections[tool] = true

	for _, attributeName in ipairs(TOOL_ATTRIBUTE_NAMES) do
		table.insert(characterConnections, tool:GetAttributeChangedSignal(attributeName):Connect(scheduleToolRender))
	end
	scheduleToolRender()
end

trackConnection(stateRemote.OnClientEvent, function(payload)
	currentState = payload
	scheduleRender()
end)

if crewActionResultEvent then
	trackConnection(crewActionResultEvent.OnClientEvent, function(response)
		if pendingCrewActionRequestId ~= nil
			and typeof(response) == "table"
			and tostring(response.RequestId or "") ~= pendingCrewActionRequestId
		then
			return
		end

		pendingCrewActionRequestId = nil
		pending = false
		scheduleRender()
	end)
end

local function bindCharacter(character)
	disconnectCharacter()
	if not character then
		scheduleRender()
		return
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end

	table.insert(characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindTool(child)
		end
	end))
	table.insert(characterConnections, character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			scheduleToolRender()
		end
	end))
	scheduleToolRender()
end

trackConnection(player.CharacterAdded, bindCharacter)
bindCharacter(player.Character)
trackConnection(Lighting:GetAttributeChangedSignal(ACTIVE_AREA_ATTRIBUTE), scheduleRender)
trackConnection(playerGui:GetAttributeChangedSignal(modalOpenAttribute), scheduleRender)
bindViewportUpdates()
coordinatorConnection = BottomRightHudCoordinator.Subscribe(function()
	scheduleRender()
end)

script.Destroying:Connect(function()
	destroyed = true
	BottomRightHudCoordinator.ClearReservation(RESERVATION_KEY)
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	if coordinatorConnection then
		coordinatorConnection:Disconnect()
		coordinatorConnection = nil
	end
	disconnectAll()
	disconnectCharacter()
	root:unmount()
end)

scheduleRender()
