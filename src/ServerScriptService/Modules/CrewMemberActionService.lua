local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewIncomeBalance = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewIncomeBalance"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local CrewInventoryDerivedCache = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInventoryDerivedCache"))
local CrewInstanceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewQuickSlotService"))

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))

local CrewMemberActionService = {}

local ACTION_REMOTE_NAME = "CrewMemberActionRequest"
local CHANGED_REMOTE_NAME = "CrewMemberInventoryChanged"
local SELL_TIME_SECONDS = 15

local initialized = false
local sliceServiceCache = nil
local baseAreaServiceCache = nil

local function getOrCreateRemote(parent, remoteName, className)
	local remote = parent:FindFirstChild(remoteName)
	if remote and not remote:IsA(className) then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new(className)
		remote.Name = remoteName
		remote.Parent = parent
	end
	return remote
end

local actionRemote = getOrCreateRemote(ReplicatedStorage, ACTION_REMOTE_NAME, "RemoteFunction")
local changedRemote = getOrCreateRemote(ReplicatedStorage, CHANGED_REMOTE_NAME, "RemoteEvent")

local function getSliceService()
	if sliceServiceCache ~= nil then
		return sliceServiceCache
	end

	local ok, service = pcall(function()
		return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
	end)
	sliceServiceCache = if ok then service else false
	return if sliceServiceCache == false then nil else sliceServiceCache
end

local function getBaseAreaService()
	if baseAreaServiceCache ~= nil then
		return baseAreaServiceCache
	end

	local ok, service = pcall(function()
		return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("BaseAreaService"))
	end)
	baseAreaServiceCache = if ok then service else false
	return if baseAreaServiceCache == false then nil else baseAreaServiceCache
end

local function result(ok, reason, extra)
	local defaultReason = if ok then "ok" else "unknown"
	local payload = {
		Ok = ok == true,
		Reason = tostring(reason or defaultReason),
	}
	if typeof(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end
	return payload
end

local function notifyChanged(player, reason)
	CrewInventoryDerivedCache.MarkDirty(player, reason)
	changedRemote:FireClient(player, {
		Reason = tostring(reason or "crew_action"),
		UpdatedAt = os.clock(),
	})
end

local function sendError(player, message)
	PopUpModule:Server_SendPopUp(
		player,
		message,
		Color3.fromRGB(255, 86, 86),
		Color3.fromRGB(0, 0, 0),
		3,
		true
	)
end

local function getSellPrice(instanceData)
	if typeof(instanceData) ~= "table" then
		return 0
	end

	local crewMemberId = tostring(instanceData.CrewMemberId or instanceData.StorageName or "")
	local canonicalId, info = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	if not info then
		return 0
	end

	if info.SellPrice ~= nil then
		return math.max(0, math.floor(tonumber(info.SellPrice) or 0))
	end

	local income = tonumber(instanceData.Income or info.Income)
	local baseIncomeRoll = tonumber(instanceData.BaseIncomeRoll)
	if baseIncomeRoll ~= nil and baseIncomeRoll > 0 then
		income = CrewIncomeBalance.ComputeIncome(
			baseIncomeRoll,
			instanceData.Variant,
			instanceData.Level,
			instanceData.Rarity or info.Rarity
		)
	end
	if income == nil then
		return 0
	end
	_ = canonicalId
	return math.max(0, math.floor(income * SELL_TIME_SECONDS))
end

local function getHumanoid(player)
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end
	return nil
end

local function getToolCrewInstanceId(tool)
	if not tool or not tool:IsA("Tool") then
		return ""
	end
	return tostring(tool:GetAttribute("CrewMemberInstanceId") or tool:GetAttribute("CrewInstanceId") or "")
end

local function findExactCrewTool(container, instanceId)
	if not container then
		return nil
	end

	local normalizedInstanceId = tostring(instanceId or "")
	if normalizedInstanceId == "" then
		return nil
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and getToolCrewInstanceId(child) == normalizedInstanceId then
			return child
		end
	end
	return nil
end

local function getInstanceMetadata(instanceId, instanceData, slotIndex, toolEquipped, action)
	instanceData = if typeof(instanceData) == "table" then instanceData else {}
	local crewMemberId = tostring(instanceData.CrewMemberId or instanceData.StorageName or "")
	local canonicalId, info = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	local displayInfo = CrewCatalog.GetDisplayInfo(canonicalId ~= "" and canonicalId or crewMemberId, instanceData)
	local displayName = tostring(displayInfo.DisplayName or (info and (info.DisplayName or info.Name)) or canonicalId or crewMemberId or "Crewmate")
	local rarity = tostring(instanceData.Rarity or (info and info.Rarity) or "")
	local variant = tostring(displayInfo.Variant or instanceData.Variant or instanceData.VariantKey or "")
	local income = tonumber(instanceData.Income or (info and info.Income))
	local baseIncomeRoll = tonumber(instanceData.BaseIncomeRoll)
	if baseIncomeRoll ~= nil and baseIncomeRoll > 0 then
		income = CrewIncomeBalance.ComputeIncome(baseIncomeRoll, variant, instanceData.Level, rarity)
	end

	return {
		Action = tostring(action or "HoldEquipped"),
		InstanceId = tostring(instanceId),
		SlotIndex = slotIndex,
		DisplayName = displayName,
		BaseDisplayName = displayInfo.BaseDisplayName,
		CrewMemberId = tostring(canonicalId or crewMemberId),
		Rarity = if rarity ~= "" then rarity else nil,
		Variant = if variant ~= "" then variant else nil,
		VariantTag = displayInfo.VariantTag,
		VariantDisplayName = displayInfo.VariantDisplayName,
		ShowVariantTag = displayInfo.ShowVariantTag == true,
		Income = income,
		Level = tonumber(instanceData.Level),
		ToolEquipped = toolEquipped == true,
	}
end

local function normalizePayload(payload)
	if typeof(payload) ~= "table" then
		return {}
	end
	return payload
end

local function equip(player, payload)
	local instanceId = tostring(payload.InstanceId or payload.CrewMemberInstanceId or "")
	if instanceId == "" then
		return result(false, "invalid_instance_id")
	end

	local state, _, _, inventory = CrewInstanceService.GetInstanceState(player, instanceId)
	if state ~= "Stored" then
		return result(false, "equip_requires_stored", {
			State = state,
		})
	end

	local ok, assignResult = CrewQuickSlotService.AssignInstanceToSlot(player, instanceId, payload.SlotIndex)
	if ok ~= true then
		sendError(player, "Could not equip that crewmate.")
		return result(false, assignResult and assignResult.Reason or "quick_slot_assign_failed", assignResult)
	end

	notifyChanged(player, "crew_equip")
	return result(true, "ok", {
		Action = "Equip",
		InstanceId = instanceId,
		SlotIndex = assignResult and assignResult.SlotIndex,
		StoredCount = CrewInstanceService.CountStoredInstances(player, inventory),
	})
end

local function unequip(player, payload)
	local instanceId = tostring(payload.InstanceId or payload.CrewMemberInstanceId or "")
	if instanceId == "" then
		return result(false, "invalid_instance_id")
	end

	local state, _, _, inventory = CrewInstanceService.GetInstanceState(player, instanceId)
	if state == "Stored" then
		return result(true, "already_stored", {
			Action = "Unequip",
			InstanceId = instanceId,
		})
	end
	if state ~= "Equipped" then
		return result(false, "unequip_requires_equipped", {
			State = state,
		})
	end

	local canStore, occupied, storageSlots = CrewInstanceService.CanStoreInstances(player, inventory, 1)
	if canStore ~= true then
		sendError(player, "Crewmate inventory full. Free a slot before unequipping.")
		return result(false, "crew_inventory_full", {
			StoredCount = occupied,
			StorageSlots = storageSlots,
		})
	end

	local ok, clearResult = CrewQuickSlotService.ClearAssignmentsForInstance(player, instanceId)
	if ok ~= true then
		return result(false, clearResult and clearResult.Reason or "quick_slot_clear_failed", clearResult)
	end

	notifyChanged(player, "crew_unequip")
	return result(true, "ok", {
		Action = "Unequip",
		InstanceId = instanceId,
	})
end

local function holdEquipped(player, payload)
	local instanceId = tostring(payload.InstanceId or payload.CrewMemberInstanceId or "")
	if instanceId == "" then
		return result(false, "invalid_instance_id")
	end

	local state, resolvedInstanceId, instanceData, _, slotIndex = CrewInstanceService.GetInstanceState(player, instanceId)
	if state ~= "Equipped" then
		return result(false, "hold_requires_equipped", {
			State = state,
		})
	end

	local humanoid = getHumanoid(player)
	if not humanoid then
		return result(false, "missing_humanoid")
	end

	local character = player.Character
	local heldTool = findExactCrewTool(character, resolvedInstanceId)
	if heldTool then
		return result(true, "ok", getInstanceMetadata(resolvedInstanceId, instanceData, slotIndex, true))
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack")
	local tool = findExactCrewTool(backpack, resolvedInstanceId)
	if not tool then
		return result(false, "tool_not_found")
	end

	humanoid:UnequipTools()
	humanoid:EquipTool(tool)

	return result(true, "ok", getInstanceMetadata(resolvedInstanceId, instanceData, slotIndex, true))
end

local function toggleHoldEquipped(player, payload)
	local instanceId = tostring(payload.InstanceId or payload.CrewMemberInstanceId or "")
	if instanceId == "" then
		return result(false, "invalid_instance_id")
	end

	local state, resolvedInstanceId, instanceData, _, slotIndex = CrewInstanceService.GetInstanceState(player, instanceId)
	if state ~= "Equipped" then
		return result(false, "toggle_hold_requires_equipped", {
			State = state,
		})
	end

	local humanoid = getHumanoid(player)
	if not humanoid then
		return result(false, "missing_humanoid")
	end

	local character = player.Character
	local heldTool = findExactCrewTool(character, resolvedInstanceId)
	if heldTool then
		humanoid:UnequipTools()
		return result(
			true,
			"ok",
			getInstanceMetadata(resolvedInstanceId, instanceData, slotIndex, false, "ToggleHoldEquipped")
		)
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack")
	local tool = findExactCrewTool(backpack, resolvedInstanceId)
	if not tool then
		return result(false, "tool_not_found")
	end

	humanoid:UnequipTools()
	humanoid:EquipTool(tool)

	return result(
		true,
		"ok",
		getInstanceMetadata(resolvedInstanceId, instanceData, slotIndex, true, "ToggleHoldEquipped")
	)
end

local function sell(player, payload)
	local instanceId = tostring(payload.InstanceId or payload.CrewMemberInstanceId or "")
	if instanceId == "" then
		return result(false, "invalid_instance_id")
	end

	local state, _, instanceData = CrewInstanceService.GetInstanceState(player, instanceId)
	if state ~= "Stored" then
		return result(false, "sell_requires_stored", {
			State = state,
		})
	end

	local price = getSellPrice(instanceData)
	if price <= 0 then
		return result(false, "sell_price_unavailable")
	end

	local removedId, removedInstance, removeReason = CrewInstanceService.RemoveStoredInstanceById(player, instanceId, {
		SourcePath = "crew_action_sell",
	})
	if not removedInstance then
		return result(false, tostring(removeReason or "sell_remove_failed"))
	end

	DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), price, { ApplyTitleBuff = false })
	notifyChanged(player, "crew_sell")
	return result(true, "ok", {
		Action = "Sell",
		InstanceId = tostring(removedId),
		Amount = price,
	})
end

local function storeHeld(player, payload)
	local baseAreaService = getBaseAreaService()
	if baseAreaService == nil or baseAreaService.IsPlayerInBaseArea(player) ~= true then
		return result(false, "base_area_required")
	end

	local sliceService = getSliceService()
	if sliceService == nil or typeof(sliceService.StoreHeldCrewMember) ~= "function" then
		return result(false, "store_held_unavailable")
	end

	local ok, storeResult = sliceService.StoreHeldCrewMember(player, payload)
	if ok ~= true then
		return result(false, storeResult and storeResult.Reason or "store_held_failed", storeResult)
	end

	notifyChanged(player, "crew_store_held")
	return result(true, "ok", storeResult)
end

function CrewMemberActionService.HandleAction(player, payload)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return result(false, "invalid_player")
	end

	payload = normalizePayload(payload)
	local action = tostring(payload.Action or payload.Type or "")
	if action == "Equip" then
		return equip(player, payload)
	elseif action == "Unequip" then
		return unequip(player, payload)
	elseif action == "HoldEquipped" then
		return holdEquipped(player, payload)
	elseif action == "ToggleHoldEquipped" then
		return toggleHoldEquipped(player, payload)
	elseif action == "Sell" then
		return sell(player, payload)
	elseif action == "StoreHeld" then
		return storeHeld(player, payload)
	end

	return result(false, "unknown_action")
end

function CrewMemberActionService.Start()
	if initialized then
		return
	end
	initialized = true

	actionRemote.OnServerInvoke = function(player, payload)
		return CrewMemberActionService.HandleAction(player, payload)
	end
end

return CrewMemberActionService
