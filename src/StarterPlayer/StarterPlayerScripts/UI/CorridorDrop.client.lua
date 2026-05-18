local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local BiomeAreas = require(Modules:WaitForChild("Configs"):WaitForChild("BiomeAreas"))
local ChestUtils = require(Modules:WaitForChild("GrandLineRushChestUtils"))
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local Economy = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local UiModalState = require(Modules:WaitForChild("UiModalState"))
local DropAction = require(UiFolder:WaitForChild("Corridor"):WaitForChild("DropAction"))

local verticalSliceConfig = Economy.VerticalSlice
if verticalSliceConfig.Enabled ~= true then
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote = remotesFolder:WaitForChild(verticalSliceConfig.Remotes.RequestName)
local stateRemote = remotesFolder:WaitForChild(verticalSliceConfig.Remotes.StateEventName)

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactCorridorDropRoot"
rootContainer.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)
local modalOpenAttribute = UiModalState.GetAttributeName()

local currentState = nil
local dropPending = false
local renderQueued = false
local destroyed = false
local cleanupConnections = {}
local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local ACTIVE_AREA_ATTRIBUTE = BiomeAreas.ActiveAreaAttribute
local STARTING_AREA_KEY = BiomeAreas.StartingAreaKey
local MAX_CARRY_SLOTS = math.clamp(math.floor(tonumber((verticalSliceConfig.CarrySlots or {}).MaxSlots) or 3), 1, 3)

local function trackConnection(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(cleanupConnections, connection)
	return connection
end

local function getStringAttribute(attributeName)
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function getCarriedCrewMember()
	local carriedName = getStringAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE)
	if not carriedName then
		return nil
	end

	local canonicalCrewMemberId, crewInfo = CrewCatalog.ResolveCanonicalCrewMemberId(carriedName)
	local modelName = if crewInfo then tostring(crewInfo.ModelName or "") else ""
	local modelPreview = if modelName ~= ""
		then {
			ModelName = modelName,
			UsedCanonical = true,
			IsPreviewOnly = true,
			Source = "CrewCatalog",
		}
		else nil

	return {
		ItemType = "Crewmate",
		CrewMemberId = if crewInfo then canonicalCrewMemberId else carriedName,
		DisplayName = if crewInfo then crewInfo.DisplayName else carriedName,
		ModelName = if modelName ~= "" then modelName else nil,
		ModelPreview = modelPreview,
		PreviewKind = "CrewMember",
		RewardType = "Crewmate",
		Rarity = if crewInfo then tostring(crewInfo.Rarity or "Common") else nil,
		CanonicalRarity = if crewInfo then tostring(crewInfo.Rarity or "Common") else nil,
	}
end

local function getRewardType(reward)
	if typeof(reward) ~= "table" then
		return ""
	end

	local rewardType = reward.RewardType or reward.Type or reward.Kind
	if typeof(rewardType) == "string" then
		return rewardType
	end

	return ""
end

local function getRewardDisplayName(reward)
	if typeof(reward) ~= "table" then
		return ""
	end

	local displayName = reward.DisplayName or reward.displayName or reward.Name or reward.name
	if typeof(displayName) == "string" then
		return displayName
	end

	return ""
end

local function parseChestDisplayName(displayName)
	local name = tostring(displayName or "")
	local inventoryName = string.match(name, "^(.-)%s+Chest$")
	if typeof(inventoryName) == "string" and inventoryName ~= "" then
		return ChestUtils.ParseInventoryName(inventoryName)
	end

	return ChestUtils.ParseInventoryName(name)
end

local function hasChestSignal(reward)
	if typeof(reward) ~= "table" then
		return false
	end

	local rewardType = getRewardType(reward)
	if rewardType == "Chest" or reward.Tier ~= nil or reward.ChestKind ~= nil or reward.FruitRarity ~= nil then
		return true
	end
	if rewardType ~= "" then
		return false
	end

	local displayName = string.lower(getRewardDisplayName(reward))
	return string.find(displayName, "chest", 1, true) ~= nil
end

local function buildCarriedChestItem(reward)
	if not hasChestSignal(reward) then
		return nil
	end

	local displayName = getRewardDisplayName(reward)
	local chestSource = reward
	if reward.Tier == nil and displayName ~= "" then
		chestSource = parseChestDisplayName(displayName)
	end

	local chestData = ChestUtils.BuildChestData(chestSource)
	return {
		ItemType = "Chest",
		RewardType = "Chest",
		ChestKind = chestData.ChestKind,
		Tier = chestData.Tier,
		FruitRarity = chestData.FruitRarity,
		RewardProfile = chestData.RewardProfile,
		DisplayName = ChestUtils.GetDisplayName(chestData),
		PreviewKind = "Chest",
		PreviewName = ChestUtils.GetVisualStyleName(chestData),
		RarityLabel = ChestUtils.GetRarityLabel(chestData),
	}
end

local function getCarriedInHandItem(carriedReward, carriedCrewMember)
	local chestItem = buildCarriedChestItem(carriedReward)
	if chestItem ~= nil then
		return chestItem
	end

	if typeof(carriedReward) == "table" then
		local rewardType = getRewardType(carriedReward)
		if rewardType == "Crewmate" or rewardType == "CrewMember" then
			local item = table.clone(carriedReward)
			item.ItemType = item.ItemType or "Crewmate"
			item.PreviewKind = item.PreviewKind or "CrewMember"
			if item.Rarity == nil then
				local crewId = item.CrewMemberId or item.CrewStorageName or item.CrewName or item.DisplayName or item.Name
				local _, crewInfo = CrewCatalog.ResolveCanonicalCrewMemberId(crewId)
				if crewInfo then
					item.Rarity = tostring(crewInfo.Rarity or "Common")
					item.CanonicalRarity = tostring(crewInfo.Rarity or "Common")
				end
			end
			return item
		end
	end

	return carriedCrewMember
end

local getRunState

local function buildCrewItemFromCarrySlot(slot)
	if typeof(slot) ~= "table" then
		return nil
	end

	local data = if typeof(slot.Data) == "table" then slot.Data else {}
	local rawCrewId = data.CrewMemberId or data.CrewStorageName or data.CrewName or slot.DisplayName
	local crewId = if typeof(rawCrewId) == "string" then rawCrewId else ""
	local canonicalCrewMemberId, crewInfo = CrewCatalog.ResolveCanonicalCrewMemberId(crewId)
	local modelName = if crewInfo then tostring(crewInfo.ModelName or "") else tostring(data.ModelName or "")
	local rarity = data.Rarity or data.CanonicalRarity or slot.Rarity or slot.CanonicalRarity
	if rarity == nil and crewInfo then
		rarity = tostring(crewInfo.Rarity or "Common")
	end
	local modelPreview = if modelName ~= ""
		then {
			ModelName = modelName,
			UsedCanonical = crewInfo ~= nil,
			IsPreviewOnly = true,
			Source = if crewInfo then "CrewCatalog" else "CarrySlots",
		}
		else nil

	return {
		ItemType = "Crewmate",
		CrewMemberId = if crewInfo then canonicalCrewMemberId else crewId,
		DisplayName = if typeof(slot.DisplayName) == "string" and slot.DisplayName ~= ""
			then slot.DisplayName
			elseif crewInfo
				then crewInfo.DisplayName
				else tostring(data.CrewDisplayName or data.DisplayName or data.CrewName or crewId or "Crewmate"),
		ModelName = if modelName ~= "" then modelName else nil,
		ModelPreview = modelPreview,
		PreviewKind = "CrewMember",
		RewardType = "Crewmate",
		Rarity = rarity,
		CanonicalRarity = rarity,
		Image = data.Image,
	}
end

local function buildCarrySlotItem(slot)
	if typeof(slot) ~= "table" or slot.Occupied ~= true then
		return nil
	end

	local data = if typeof(slot.Data) == "table" then table.clone(slot.Data) else {}
	data.DisplayName = slot.DisplayName or data.DisplayName
	data.RewardType = data.RewardType or slot.ItemType
	local chestItem = buildCarriedChestItem(data)
	if chestItem ~= nil or slot.ItemType == "Chest" then
		chestItem = chestItem or buildCarriedChestItem({
			DisplayName = slot.DisplayName,
			RewardType = "Chest",
		})
		if chestItem then
			return chestItem
		end
	end

	return buildCrewItemFromCarrySlot(slot)
end

local function normalizeCarrySlot(rawSlot, slotIndex)
	local slot = if typeof(rawSlot) == "table" then rawSlot else {}
	local locked = slot.Locked == true
	local occupied = slot.Occupied == true
	local normalized = {
		SlotIndex = tonumber(slot.SlotIndex) or slotIndex,
		CarryId = slot.CarryId,
		Locked = locked,
		Unlocked = slot.Unlocked == true or locked ~= true,
		Occupied = occupied,
	}

	if occupied then
		normalized.Item = buildCarrySlotItem(slot)
		normalized.DisplayName = slot.DisplayName
		normalized.ItemType = slot.ItemType
	end

	return normalized
end

local function getCarrySlots()
	local runState = getRunState()
	local carrySlots = runState and runState.CarrySlots or nil
	if typeof(carrySlots) ~= "table" then
		return nil
	end

	local slots = {}
	for slotIndex = 1, MAX_CARRY_SLOTS do
		slots[slotIndex] = normalizeCarrySlot(carrySlots[slotIndex], slotIndex)
	end

	return slots
end

local function hasOccupiedCarrySlot(slots)
	if typeof(slots) ~= "table" then
		return false
	end

	for _, slot in ipairs(slots) do
		if typeof(slot) == "table" and slot.Occupied == true and typeof(slot.Item) == "table" then
			return true
		end
	end

	return false
end

local function getFirstOccupiedCarrySlot(slots)
	if typeof(slots) ~= "table" then
		return nil
	end

	for _, slot in ipairs(slots) do
		if typeof(slot) == "table" and slot.Occupied == true and typeof(slot.Item) == "table" then
			return slot
		end
	end

	return nil
end

local function isInCorridorArea()
	local activeArea = Lighting:GetAttribute(ACTIVE_AREA_ATTRIBUTE)
	return typeof(activeArea) == "string" and activeArea ~= "" and activeArea ~= STARTING_AREA_KEY
end

function getRunState()
	return currentState and currentState.Run or nil
end

local function getCarriedReward()
	local runState = getRunState()
	local carriedReward = runState and runState.CarriedReward or nil
	if carriedReward ~= nil then
		return carriedReward
	end

	local carriedDisplayName = player:GetAttribute("CarriedMajorRewardDisplayName")
	local carriedType = player:GetAttribute("CarriedMajorRewardType")
	if typeof(carriedDisplayName) == "string" and carriedDisplayName ~= "" then
		return {
			DisplayName = carriedDisplayName,
			RewardType = if typeof(carriedType) == "string" then carriedType else nil,
		}
	end

	local carriedCrewMember = getCarriedCrewMember()
	if carriedCrewMember ~= nil then
		return carriedCrewMember
	end

	return nil
end

local function showPopup(text, isError)
	local color = if isError then Color3.fromRGB(255, 104, 126) else Color3.fromRGB(113, 255, 184)
	local stroke = Color3.fromRGB(10, 8, 12)

	task.spawn(function()
		pcall(function()
			PopUpModule:Local_SendPopUp(tostring(text), color, stroke, 2, isError == true)
		end)
	end)
end

local function getFallbackError(response)
	local errorCode = response and response.error
	if
		errorCode == "no_carried_reward"
		or errorCode == "no_held_crew_member"
		or errorCode == "no_carried_item"
	then
		return "No carried item to drop."
	elseif errorCode == "missing_drop_position" then
		return "Move a little before dropping that."
	elseif errorCode == "missing_context" or errorCode == "missing_state" then
		return "That item is not ready to drop yet."
	elseif errorCode == "profile_not_ready" then
		return "Your run data is still loading."
	end

	return "Could not drop item."
end

local function render()
	local modalOpen = playerGui:GetAttribute(modalOpenAttribute) == true
	local carriedCrewMember = getCarriedCrewMember()
	local carriedReward = getCarriedReward()
	local carriedItem = getCarriedInHandItem(carriedReward, carriedCrewMember)
	local carriedSlots = getCarrySlots()
	if carriedSlots == nil and carriedItem ~= nil then
		carriedSlots = {
			{
				SlotIndex = 1,
				Occupied = true,
				Unlocked = true,
				Locked = false,
				Item = carriedItem,
			},
			{
				SlotIndex = 2,
				Occupied = false,
				Unlocked = false,
				Locked = true,
			},
			{
				SlotIndex = 3,
				Occupied = false,
				Unlocked = false,
				Locked = true,
			},
		}
	end
	local firstOccupiedSlot = getFirstOccupiedCarrySlot(carriedSlots)
	local visible = (carriedReward ~= nil or firstOccupiedSlot ~= nil) and modalOpen ~= true
	local showInHandHud = hasOccupiedCarrySlot(carriedSlots) and isInCorridorArea() and modalOpen ~= true

	root:render(ReactRoblox.createPortal(React.createElement(DropAction, {
		visible = visible,
		isPending = dropPending,
		reward = carriedReward or (firstOccupiedSlot and firstOccupiedSlot.Item),
		carriedItem = carriedItem,
		carriedSlots = carriedSlots,
		carriedCrewMember = carriedCrewMember,
		showInHandHud = showInHandHud,
		onDrop = function(slot)
			local dropSlot = if typeof(slot) == "table" and slot.Occupied == true then slot else getFirstOccupiedCarrySlot(getCarrySlots())
			if dropPending or (getCarriedReward() == nil and dropSlot == nil) then
				return
			end

			dropPending = true
			render()

			task.spawn(function()
				local ok, response = pcall(function()
					if dropSlot ~= nil then
						return requestRemote:InvokeServer("DropCarriedReward", {
							SlotIndex = dropSlot.SlotIndex,
							CarryId = dropSlot.CarryId,
						})
					end

					return requestRemote:InvokeServer("DropCarriedReward")
				end)

				dropPending = false

				if ok and typeof(response) == "table" then
					currentState = response.state or currentState
					if response.ok == true then
						if response.message then
							showPopup(response.message, false)
						end
					else
						showPopup(response.message or getFallbackError(response), true)
					end
				else
					showPopup("Could not drop item.", true)
				end

				if not destroyed then
					render()
				end
			end)
		end,
	}), playerGui))
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

trackConnection(stateRemote.OnClientEvent, function(nextState)
	if typeof(nextState) ~= "table" then
		return
	end

	currentState = nextState
	scheduleRender()
end)

trackConnection(playerGui:GetAttributeChangedSignal(modalOpenAttribute), scheduleRender)
trackConnection(player:GetAttributeChangedSignal("CarriedMajorRewardDisplayName"), scheduleRender)
trackConnection(player:GetAttributeChangedSignal("CarriedMajorRewardType"), scheduleRender)
trackConnection(player:GetAttributeChangedSignal(CARRIED_CREW_MEMBER_ATTRIBUTE), scheduleRender)
trackConnection(Lighting:GetAttributeChangedSignal(ACTIVE_AREA_ATTRIBUTE), scheduleRender)

task.spawn(function()
	local ok, response = pcall(function()
		return requestRemote:InvokeServer("GetState")
	end)

	if ok and typeof(response) == "table" then
		currentState = response.state or currentState
	end

	scheduleRender()
end)

render()

script.Destroying:Connect(function()
	destroyed = true
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)
	root:unmount()
end)
