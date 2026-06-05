local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CrewIncomeBalance = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewIncomeBalance")
)
local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(ServerScriptService.Modules:WaitForChild("CrewQuickSlotService"))
local CrewStandIncomeAuthority = require(ServerScriptService.Modules:WaitForChild("CrewStandIncomeAuthority"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))

local CrewSlotAssignmentReconciler = {}

local CREW_MEMBER_INCOME_PATH = "CrewMemberIncome"
local SHIP_SLOTS_PATH = "Ship.Slots"
local SHIP_CAPTAIN_SLOT_PATH = "Ship.CaptainSlot"
local CAPTAIN_SLOT_KEY = "Captain"
local RESET_IN_PROGRESS_ATTRIBUTE = "CrewSlotResetInProgress"
local RESET_EPOCH_ATTRIBUTE = "CrewSlotResetEpoch"

local resetStateByPlayer = setmetatable({}, { __mode = "k" })
local resetCompletedEventsByPlayer = setmetatable({}, { __mode = "k" })

local function normalizeSlotKey(value)
	local numeric = tonumber(value)
	if not numeric or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return nil
	end

	numeric = math.floor(numeric)
	if numeric < 1 then
		return nil
	end

	return tostring(numeric)
end

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local value = tostring(select(index, ...) or "")
		if value ~= "" then
			return value
		end
	end
	return ""
end

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneValue(child)
	end
	return copy
end

local function hasStandAssignment(row)
	if typeof(row) ~= "table" then
		return false
	end

	return firstNonEmpty(
		row.CrewMemberName,
		row.CrewMemberId,
		row.StorageName,
		row.LegacyStorageName,
		row.CrewMemberInstanceId,
		row.InstanceId,
		row.CrewInstanceId
	) ~= ""
end

local function getInstanceCrewKey(instanceData)
	if typeof(instanceData) ~= "table" then
		return ""
	end

	return firstNonEmpty(
		instanceData.StorageName,
		instanceData.CrewMemberId,
		instanceData.LegacyStorageName,
		instanceData.Name
	)
end

local function hasCaptainAssignment(row)
	if typeof(row) ~= "table" then
		return false
	end

	return firstNonEmpty(
		row.CrewMemberInstanceId,
		row.InstanceId,
		row.CrewInstanceId,
		row.CrewMemberName,
		row.CrewMemberId,
		row.StorageName,
		row.LegacyStorageName
	) ~= ""
end

local function hasCaptainIncome(row)
	return typeof(row) == "table" and math.max(0, tonumber(row.IncomeToCollect) or 0) > 0
end

local function isCaptainAssignableStandMarker(assignedStand)
	local marker = tostring(assignedStand or "")
	return marker == "" or marker == CAPTAIN_SLOT_KEY
end

local function clearTutorialMetadata(instanceData)
	if typeof(instanceData) ~= "table" then
		return
	end

	instanceData.TutorialReward = false
	instanceData.TutorialToken = ""
	instanceData.TutorialOwnerUserId = nil
	instanceData.TutorialCrewMember = nil
	instanceData.TutorialRewardName = nil
end

local function makeCaptainSlotDataFromInstance(instanceId, instanceData, existingRow)
	local crewMemberName = getInstanceCrewKey(instanceData)
	if crewMemberName == "" then
		return nil
	end

	existingRow = if typeof(existingRow) == "table" then existingRow else {}
	local level = CrewIncomeBalance.NormalizeLevel(instanceData.Level or existingRow.Level)
	return {
		CrewMemberName = crewMemberName,
		CrewMemberId = tostring(instanceData.CrewMemberId or crewMemberName),
		LegacyStorageName = tostring(instanceData.LegacyStorageName or existingRow.LegacyStorageName or ""),
		CrewMemberInstanceId = tostring(instanceId),
		AssignedAt = math.max(0, math.floor(tonumber(existingRow.AssignedAt) or os.time())),
		IncomeToCollect = math.max(0, tonumber(existingRow.IncomeToCollect) or 0),
		LastAccruedAtUnix = math.max(0, math.floor(tonumber(existingRow.LastAccruedAtUnix) or os.time())),
		Level = level,
		CurrentXP = math.max(0, math.floor(tonumber(instanceData.CurrentXP) or tonumber(existingRow.CurrentXP) or 0)),
	}
end

local function makeStandRowFromInstance(instanceId, instanceData, existingRow)
	local crewMemberName = getInstanceCrewKey(instanceData)
	if crewMemberName == "" then
		return nil
	end

	existingRow = if typeof(existingRow) == "table" then existingRow else {}
	return {
		CrewMemberName = crewMemberName,
		LegacyStorageName = tostring(instanceData.LegacyStorageName or existingRow.LegacyStorageName or ""),
		CrewMemberInstanceId = tostring(instanceId),
		IncomeToCollect = tonumber(existingRow.IncomeToCollect) or 0,
		LastAccruedAtUnix = math.max(0, math.floor(tonumber(existingRow.LastAccruedAtUnix) or os.time())),
		StandLevel = CrewIncomeBalance.NormalizeLevel(instanceData.Level or existingRow.StandLevel),
	}
end

local function makeStandRowFromLegacySlot(row)
	if typeof(row) ~= "table" then
		return nil
	end

	local crewMemberName = firstNonEmpty(
		row.CrewMemberName,
		row.CrewMemberId,
		row.StorageName,
		row.Name,
		row.LegacyStorageName,
		row.BrainrotName,
		row.Brainrot,
		row.ItemName
	)
	local instanceId = firstNonEmpty(row.CrewMemberInstanceId, row.InstanceId, row.CrewInstanceId)
	if crewMemberName == "" and instanceId == "" then
		return nil
	end

	return {
		CrewMemberName = crewMemberName,
		LegacyStorageName = firstNonEmpty(row.LegacyStorageName, row.StorageName, row.Name, row.BrainrotName),
		CrewMemberInstanceId = instanceId,
		IncomeToCollect = tonumber(row.IncomeToCollect or row.Income or row.Money or row.Cash) or 0,
		LastAccruedAtUnix = math.max(0, math.floor(tonumber(row.LastAccruedAtUnix) or os.time())),
		StandLevel = CrewIncomeBalance.NormalizeLevel(row.StandLevel or row.Level),
	}
end

local function addSlotKey(slotKeys, value)
	local slotKey = normalizeSlotKey(value)
	if not slotKey then
		return
	end

	slotKeys[slotKey] = true
end

local function collectActiveShipSlotKeys(slotKeys, activeShip)
	if typeof(activeShip) ~= "Instance" or not activeShip:IsA("Model") then
		return
	end

	for _, slotKey in ipairs(ShipSlotService.GetAvailableSlotNumbers(activeShip)) do
		addSlotKey(slotKeys, slotKey)
	end
end

local function collectIncomeSlotKeys(slotKeys, player)
	for standName, standData in pairs(CrewStandIncomeAuthority.GetAllStandData(player)) do
		if hasStandAssignment(standData) then
			addSlotKey(slotKeys, standName)
		end
	end
end

local function collectInventorySlotKeys(slotKeys, crewMemberInventory)
	if typeof(crewMemberInventory) ~= "table" or typeof(crewMemberInventory.ById) ~= "table" then
		return
	end

	for _, instanceData in pairs(crewMemberInventory.ById) do
		if typeof(instanceData) == "table" then
			addSlotKey(slotKeys, instanceData.AssignedStand)
		end
	end
end

local function collectShipSlotMirrorKeys(slotKeys, shipSlots)
	if typeof(shipSlots) ~= "table" then
		return
	end

	for slotName, slotData in pairs(shipSlots) do
		if hasStandAssignment(slotData) then
			addSlotKey(slotKeys, slotName)
		end
	end
end

local function sortedSlotKeys(slotKeys)
	local result = {}
	for slotKey in pairs(slotKeys) do
		result[#result + 1] = slotKey
	end

	table.sort(result, function(left, right)
		local leftNumber = tonumber(left)
		local rightNumber = tonumber(right)
		if leftNumber and rightNumber then
			return leftNumber < rightNumber
		end
		return left < right
	end)

	return result
end

local function findAssignedInventoryInstance(crewMemberInventory, slotKey)
	if typeof(crewMemberInventory) ~= "table" or typeof(crewMemberInventory.ById) ~= "table" then
		return nil, nil
	end

	for _, orderedInstanceId in ipairs(if typeof(crewMemberInventory.Order) == "table" then crewMemberInventory.Order else {}) do
		local instanceId = tostring(orderedInstanceId)
		local instanceData = crewMemberInventory.ById[instanceId]
		if typeof(instanceData) == "table" and normalizeSlotKey(instanceData.AssignedStand) == slotKey then
			return instanceId, instanceData
		end
	end

	for instanceId, instanceData in pairs(crewMemberInventory.ById) do
		if typeof(instanceData) == "table" and normalizeSlotKey(instanceData.AssignedStand) == slotKey then
			return tostring(instanceId), instanceData
		end
	end

	return nil, nil
end

local function getShipSlots(player)
	local shipSlots = DataManager:GetValue(player, SHIP_SLOTS_PATH)
	if typeof(shipSlots) == "table" then
		return shipSlots
	end

	return {}
end

local function getCaptainSlotData(player)
	local captainSlot = DataManager:GetValue(player, SHIP_CAPTAIN_SLOT_PATH)
	if typeof(captainSlot) == "table" then
		return captainSlot
	end

	return {}
end

local function setCaptainSlotData(player, captainSlot)
	return DataManager:SetValue(player, SHIP_CAPTAIN_SLOT_PATH, if typeof(captainSlot) == "table" then captainSlot else {})
end

local function findCaptainInventoryInstance(crewMemberInventory, preferredInstanceId, player)
	if typeof(crewMemberInventory) ~= "table" or typeof(crewMemberInventory.ById) ~= "table" then
		return nil, nil
	end

	preferredInstanceId = tostring(preferredInstanceId or "")
	if preferredInstanceId ~= "" then
		local preferred = crewMemberInventory.ById[preferredInstanceId]
		if typeof(preferred) == "table" then
			local assignedStand = tostring(preferred.AssignedStand or "")
			if isCaptainAssignableStandMarker(assignedStand) then
				return preferredInstanceId, preferred
			end

			warn(("[CrewSlotAssignmentReconciler] Preserving numeric crew assignment for %s: Ship.CaptainSlot points at instance %s assigned to %s. Clearing stale captain data instead."):format(
				player and player.Name or "unknown",
				preferredInstanceId,
				assignedStand
			))
		end
	end

	for _, orderedInstanceId in ipairs(if typeof(crewMemberInventory.Order) == "table" then crewMemberInventory.Order else {}) do
		local instanceId = tostring(orderedInstanceId)
		local instanceData = crewMemberInventory.ById[instanceId]
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") == CAPTAIN_SLOT_KEY then
			return instanceId, instanceData
		end
	end

	for instanceId, instanceData in pairs(crewMemberInventory.ById) do
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") == CAPTAIN_SLOT_KEY then
			return tostring(instanceId), instanceData
		end
	end

	return nil, nil
end

local function syncCaptainInventoryAssignments(crewMemberInventory, selectedInstanceId)
	if typeof(crewMemberInventory) ~= "table" or typeof(crewMemberInventory.ById) ~= "table" then
		return false
	end

	selectedInstanceId = tostring(selectedInstanceId or "")
	local changed = false
	for instanceId, instanceData in pairs(crewMemberInventory.ById) do
		if typeof(instanceData) ~= "table" then
			continue
		end

		local currentAssignment = tostring(instanceData.AssignedStand or "")
		if tostring(instanceId) == selectedInstanceId then
			if currentAssignment ~= CAPTAIN_SLOT_KEY then
				instanceData.AssignedStand = CAPTAIN_SLOT_KEY
				changed = true
			end
		elseif currentAssignment == CAPTAIN_SLOT_KEY then
			instanceData.AssignedStand = ""
			instanceData.LastReleasedAt = os.time()
			changed = true
		end
	end

	return changed
end

local function getResetState(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local state = resetStateByPlayer[player]
	if not state then
		state = {
			Depth = 0,
			Epoch = 0,
			Source = "",
			StartedAt = 0,
			CompletedAt = 0,
		}
		resetStateByPlayer[player] = state
	end

	return state
end

local function getResetCompletedEvent(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local event = resetCompletedEventsByPlayer[player]
	if not event then
		event = Instance.new("BindableEvent")
		resetCompletedEventsByPlayer[player] = event
	end

	return event
end

local function clearAssignmentTables(player)
	if DataManager:Clear(player, CREW_MEMBER_INCOME_PATH) == false then
		return false, "failed_to_clear_crew_member_income"
	end

	if DataManager:SetValue(player, SHIP_SLOTS_PATH, {}) == false then
		return false, "failed_to_clear_ship_slots"
	end

	if DataManager:SetValue(player, SHIP_CAPTAIN_SLOT_PATH, {}) == false then
		return false, "failed_to_clear_captain_slot"
	end

	return true
end

local function migrateShipSlotMirror(player, slotKeys)
	local shipSlots = getShipSlots(player)
	local migrated = 0

	for slotName, slotData in pairs(shipSlots) do
		local slotKey = normalizeSlotKey(slotName)
		if not slotKey then
			continue
		end

		local currentStandData = CrewStandIncomeAuthority.GetStandData(player, slotKey)
		if hasStandAssignment(currentStandData) then
			continue
		end

		local legacyRow = makeStandRowFromLegacySlot(slotData)
		if legacyRow then
			local ok, reason = CrewStandIncomeAuthority.SetStandData(
				player,
				slotKey,
				legacyRow,
				"ship_slot_mirror_migration"
			)
			if ok then
				migrated += 1
				addSlotKey(slotKeys, slotKey)
			else
				warn(("[CrewSlotAssignmentReconciler] Failed to migrate Ship.Slots[%s] for %s: %s"):format(
					slotKey,
					player.Name,
					tostring(reason)
				))
			end
		end
	end

	return migrated
end

local function rebuildMissingIncomeRowsFromInventory(player, slotKeys, crewMemberInventory)
	local rebuilt = 0

	for _, slotKey in ipairs(sortedSlotKeys(slotKeys)) do
		local standData = CrewStandIncomeAuthority.GetStandData(player, slotKey)
		if hasStandAssignment(standData) then
			continue
		end

		local instanceId, instanceData = findAssignedInventoryInstance(crewMemberInventory, slotKey)
		local row = makeStandRowFromInstance(instanceId, instanceData, standData)
		if row then
			local ok, reason = CrewStandIncomeAuthority.SetStandData(
				player,
				slotKey,
				row,
				"assigned_inventory_rehydrate"
			)
			if ok then
				rebuilt += 1
			else
				warn(("[CrewSlotAssignmentReconciler] Failed to rebuild CrewMemberIncome[%s] for %s: %s"):format(
					slotKey,
					player.Name,
					tostring(reason)
				))
			end
		end
	end

	return rebuilt
end

local function syncShipSlotsMirror(player, slotKeys)
	local shipSlots = getShipSlots(player)
	local changed = false

	for _, slotKey in ipairs(sortedSlotKeys(slotKeys)) do
		local standData = CrewStandIncomeAuthority.GetStandData(player, slotKey)
		if hasStandAssignment(standData) then
			local nextSlotData = {
				CrewMemberName = tostring(standData.CrewMemberName or ""),
				CrewMemberInstanceId = tostring(standData.CrewMemberInstanceId or ""),
				IncomeToCollect = tonumber(standData.IncomeToCollect) or 0,
				StandLevel = CrewIncomeBalance.NormalizeLevel(standData.StandLevel),
				LegacyStorageName = tostring(standData.LegacyStorageName or ""),
			}

			local current = shipSlots[slotKey]
			if
				typeof(current) ~= "table"
				or tostring(current.CrewMemberName or "") ~= nextSlotData.CrewMemberName
				or tostring(current.CrewMemberInstanceId or "") ~= nextSlotData.CrewMemberInstanceId
				or tonumber(current.IncomeToCollect) ~= nextSlotData.IncomeToCollect
				or CrewIncomeBalance.NormalizeLevel(current.StandLevel) ~= nextSlotData.StandLevel
			then
				shipSlots[slotKey] = nextSlotData
				changed = true
			end
		elseif shipSlots[slotKey] ~= nil then
			shipSlots[slotKey] = nil
			changed = true
		end
	end

	if changed then
		DataManager:SetValue(player, SHIP_SLOTS_PATH, shipSlots)
	end

	return changed
end

function CrewSlotAssignmentReconciler.GetCaptainSlotKey()
	return CAPTAIN_SLOT_KEY
end

CrewSlotAssignmentReconciler.CaptainSlotKey = CAPTAIN_SLOT_KEY

function CrewSlotAssignmentReconciler.NormalizeSlotKey(value)
	return normalizeSlotKey(value)
end

function CrewSlotAssignmentReconciler.GetCaptainAssignment(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local captainSlot = getCaptainSlotData(player)
	return if hasCaptainAssignment(captainSlot) then captainSlot else nil
end

function CrewSlotAssignmentReconciler.HasCaptainAssignment(player)
	return CrewSlotAssignmentReconciler.GetCaptainAssignment(player) ~= nil
end

function CrewSlotAssignmentReconciler.ReconcileCaptain(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}
	if CrewSlotAssignmentReconciler.IsResetInProgress(player) and options.AllowDuringReset ~= true then
		return false, "reset_in_progress", {
			Source = tostring(options.Source or "captain_reconcile"),
		}
	end

	local crewMemberInventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(crewMemberInventory) ~= "table" or typeof(crewMemberInventory.ById) ~= "table" then
		return false, "missing_crew_inventory"
	end

	local captainSlot = getCaptainSlotData(player)
	local preferredInstanceId = firstNonEmpty(captainSlot.CrewMemberInstanceId, captainSlot.InstanceId, captainSlot.CrewInstanceId)
	local selectedInstanceId, selectedInstanceData = findCaptainInventoryInstance(crewMemberInventory, preferredInstanceId, player)
	local changedInventory = false
	local changedCaptainSlot = false

	if selectedInstanceData then
		changedInventory = syncCaptainInventoryAssignments(crewMemberInventory, selectedInstanceId)
		local nextCaptainSlot = makeCaptainSlotDataFromInstance(selectedInstanceId, selectedInstanceData, captainSlot)
		if not nextCaptainSlot then
			selectedInstanceData.AssignedStand = ""
			changedInventory = true
			selectedInstanceId = nil
			selectedInstanceData = nil
			nextCaptainSlot = {}
		end

		if
			typeof(nextCaptainSlot) ~= "table"
			or tostring(captainSlot.CrewMemberInstanceId or "") ~= tostring(nextCaptainSlot.CrewMemberInstanceId or "")
			or tostring(captainSlot.CrewMemberName or "") ~= tostring(nextCaptainSlot.CrewMemberName or "")
			or tostring(captainSlot.LegacyStorageName or "") ~= tostring(nextCaptainSlot.LegacyStorageName or "")
			or tonumber(captainSlot.Level) ~= tonumber(nextCaptainSlot.Level)
			or tonumber(captainSlot.CurrentXP) ~= tonumber(nextCaptainSlot.CurrentXP)
		then
			if setCaptainSlotData(player, nextCaptainSlot) == false then
				return false, "failed_to_write_captain_slot"
			end
			changedCaptainSlot = true
		end
	elseif hasCaptainAssignment(captainSlot) or hasCaptainIncome(captainSlot) then
		if setCaptainSlotData(player, {}) == false then
			return false, "failed_to_clear_stale_captain_slot"
		end
		changedCaptainSlot = true
	end

	if changedInventory then
		local saved, saveReason = CrewInstanceService.SaveCrewInventory(player, crewMemberInventory, {
			SourcePath = tostring(options.SourcePath or options.Source or "captain_assignment_reconcile"),
		})
		if saved == false then
			return false, tostring(saveReason or "failed_to_save_captain_inventory")
		end
		CrewInstanceService.SyncCrewAvailableCounts(player)
	end

	return true, "ok", {
		Source = tostring(options.Source or "captain_reconcile"),
		HasCaptain = selectedInstanceData ~= nil,
		CaptainInstanceId = tostring(selectedInstanceId or ""),
		InventoryChanged = changedInventory,
		CaptainSlotChanged = changedCaptainSlot,
	}
end

function CrewSlotAssignmentReconciler.AssignCaptain(player, instanceRef, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}
	local reconcileOk, reconcileReason = CrewSlotAssignmentReconciler.ReconcileCaptain(player, {
		Source = tostring(options.Source or "captain_assign_preflight"),
	})
	if reconcileOk == false then
		return nil, nil, tostring(reconcileReason or "captain_reconcile_failed")
	end

	if CrewSlotAssignmentReconciler.HasCaptainAssignment(player) then
		return nil, nil, "captain_occupied"
	end

	local instanceId, instanceData, crewMemberInventory = CrewInstanceService.GetInstance(player, instanceRef)
	if not instanceData then
		return nil, nil, "incoming_instance_missing"
	end

	local expectedStorageName = tostring(options.ExpectedIncomingStorageName or options.StorageName or "")
	if expectedStorageName ~= "" and getInstanceCrewKey(instanceData) ~= expectedStorageName then
		return nil, nil, "ownership_mismatch"
	end

	if tostring(instanceData.AssignedStand or "") ~= "" then
		return nil, nil, "incoming_already_assigned"
	end
	if instanceData.Overflow == true then
		return nil, nil, "incoming_instance_overflow"
	end

	local previousQuickSlot = CrewQuickSlotService.GetInstanceSlot(player, instanceId)
	if previousQuickSlot ~= nil then
		local clearOk, clearResult = CrewQuickSlotService.ClearAssignmentsForInstance(player, instanceId)
		if clearOk ~= true then
			return nil, nil, tostring(clearResult and clearResult.Reason or "quick_slot_clear_failed")
		end
	end
	local function restoreQuickSlot()
		if previousQuickSlot ~= nil then
			CrewQuickSlotService.AssignInstanceToSlot(player, instanceId, previousQuickSlot)
		end
	end

	local originalInstanceData = table.clone(instanceData)
	instanceData.AssignedStand = CAPTAIN_SLOT_KEY
	if options.ClearTutorialMetadataAfterAssign == true then
		clearTutorialMetadata(instanceData)
	end
	crewMemberInventory.ById[tostring(instanceId)] = instanceData

	local saved, saveReason = CrewInstanceService.SaveCrewInventory(player, crewMemberInventory, {
		SourcePath = tostring(options.SourcePath or "captain_slot_assign"),
	})
	if saved == false then
		crewMemberInventory.ById[tostring(instanceId)] = originalInstanceData
		restoreQuickSlot()
		return nil, nil, tostring(saveReason or "captain_assignment_save_failed")
	end

	local captainSlot = makeCaptainSlotDataFromInstance(instanceId, instanceData, {
		AssignedAt = os.time(),
	})
	if setCaptainSlotData(player, captainSlot) == false then
		instanceData.AssignedStand = ""
		crewMemberInventory.ById[tostring(instanceId)] = instanceData
		CrewInstanceService.SaveCrewInventory(player, crewMemberInventory, {
			SourcePath = "captain_slot_assign_rollback",
		})
		restoreQuickSlot()
		return nil, nil, "captain_slot_write_failed"
	end

	CrewInstanceService.SyncCrewAvailableCounts(player)

	return tostring(instanceId), instanceData, "ok"
end

function CrewSlotAssignmentReconciler.SwapCaptain(player, incomingInstanceRef, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil, nil, nil, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}
	local reconcileOk, reconcileReason = CrewSlotAssignmentReconciler.ReconcileCaptain(player, {
		Source = tostring(options.Source or "captain_swap_preflight"),
	})
	if reconcileOk == false then
		return nil, nil, nil, nil, tostring(reconcileReason or "captain_reconcile_failed")
	end

	local crewMemberInventory = CrewInstanceService.GetCrewInventory(player)
	local captainSlot = getCaptainSlotData(player)
	local preferredInstanceId = firstNonEmpty(captainSlot.CrewMemberInstanceId, captainSlot.InstanceId, captainSlot.CrewInstanceId)
	local outgoingInstanceId, outgoingInstanceData = findCaptainInventoryInstance(crewMemberInventory, preferredInstanceId, player)
	if not outgoingInstanceData then
		return nil, nil, nil, nil, "no_captain_assigned"
	end

	local incomingInstanceId, incomingInstanceData = CrewInstanceService.GetInstance(player, incomingInstanceRef)
	if not incomingInstanceData then
		return nil, nil, nil, nil, "incoming_instance_missing"
	end

	incomingInstanceId = tostring(incomingInstanceId)
	outgoingInstanceId = tostring(outgoingInstanceId)
	if incomingInstanceId == outgoingInstanceId then
		return nil, nil, nil, nil, "incoming_already_assigned"
	end

	local expectedStorageName = tostring(options.ExpectedIncomingStorageName or options.StorageName or "")
	if expectedStorageName ~= "" and getInstanceCrewKey(incomingInstanceData) ~= expectedStorageName then
		return nil, nil, nil, nil, "ownership_mismatch"
	end

	if tostring(incomingInstanceData.AssignedStand or "") ~= "" then
		return nil, nil, nil, nil, "incoming_already_assigned"
	end
	if incomingInstanceData.Overflow == true then
		return nil, nil, nil, nil, "incoming_instance_overflow"
	end

	local previousQuickSlot = CrewQuickSlotService.GetInstanceSlot(player, incomingInstanceId)
	if previousQuickSlot ~= nil then
		local clearOk, clearResult = CrewQuickSlotService.ClearAssignmentsForInstance(player, incomingInstanceId)
		if clearOk ~= true then
			return nil, nil, nil, nil, tostring(clearResult and clearResult.Reason or "quick_slot_clear_failed")
		end
	end
	local function restoreIncomingQuickSlot()
		if previousQuickSlot ~= nil then
			CrewQuickSlotService.AssignInstanceToSlot(player, incomingInstanceId, previousQuickSlot)
		end
	end

	local finalInventory = cloneValue(crewMemberInventory)
	local finalIncoming = cloneValue(incomingInstanceData)
	local finalOutgoing = cloneValue(outgoingInstanceData)
	finalIncoming.AssignedStand = CAPTAIN_SLOT_KEY
	if options.ClearIncomingTutorialMetadataAfterAssign == true then
		clearTutorialMetadata(finalIncoming)
	end
	finalOutgoing.AssignedStand = ""
	finalOutgoing.LastReleasedAt = os.time()
	finalInventory.ById[incomingInstanceId] = finalIncoming
	finalInventory.ById[outgoingInstanceId] = finalOutgoing

	local capacityOk, _, _, _, capacityReason = CrewQuickSlotService.CanInventoryFitOrNotify(
		player,
		finalInventory,
		"CaptainSlotSwap"
	)
	if capacityOk ~= true then
		restoreIncomingQuickSlot()
		return nil, nil, nil, nil, tostring(capacityReason or "quick_slot_capacity")
	end

	local saved, saveReason = CrewInstanceService.SaveCrewInventory(player, finalInventory, {
		SourcePath = tostring(options.SourcePath or "captain_slot_swap"),
	})
	if saved == false then
		restoreIncomingQuickSlot()
		return nil, nil, nil, nil, tostring(saveReason or "captain_swap_save_failed")
	end

	local captainSlotRow = makeCaptainSlotDataFromInstance(incomingInstanceId, finalIncoming, {
		AssignedAt = os.time(),
		IncomeToCollect = 0,
	})
	if setCaptainSlotData(player, captainSlotRow) == false then
		CrewInstanceService.SaveCrewInventory(player, crewMemberInventory, {
			SourcePath = "captain_slot_swap_rollback",
		})
		restoreIncomingQuickSlot()
		return nil, nil, nil, nil, "captain_slot_write_failed"
	end

	CrewInstanceService.SyncCrewAvailableCounts(player)

	return incomingInstanceId, finalIncoming, outgoingInstanceId, finalOutgoing, "ok"
end

function CrewSlotAssignmentReconciler.ClearCaptainAssignment(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}
	local crewMemberInventory = CrewInstanceService.GetCrewInventory(player)
	local captainSlot = getCaptainSlotData(player)
	local preferredInstanceId = firstNonEmpty(captainSlot.CrewMemberInstanceId, captainSlot.InstanceId, captainSlot.CrewInstanceId)
	local instanceId, instanceData = findCaptainInventoryInstance(crewMemberInventory, preferredInstanceId, player)

	if not instanceData then
		if hasCaptainAssignment(captainSlot) or hasCaptainIncome(captainSlot) then
			setCaptainSlotData(player, {})
		end
		return nil, nil, "no_captain_assigned"
	end

	local releaseInventory = cloneValue(crewMemberInventory)
	local releasedInstanceData = cloneValue(instanceData)
	releasedInstanceData.AssignedStand = ""
	releasedInstanceData.LastReleasedAt = os.time()
	releaseInventory.ById[tostring(instanceId)] = releasedInstanceData

	local capacityOk, _, _, _, capacityReason = CrewQuickSlotService.CanInventoryFitOrNotify(
		player,
		releaseInventory,
		"CaptainSlotRelease"
	)
	if capacityOk ~= true then
		return nil, nil, tostring(capacityReason or "quick_slot_capacity")
	end

	local saved, saveReason = CrewInstanceService.SaveCrewInventory(player, releaseInventory, {
		SourcePath = tostring(options.SourcePath or "captain_slot_release"),
	})
	if saved == false then
		return nil, nil, tostring(saveReason or "captain_release_save_failed")
	end

	if setCaptainSlotData(player, {}) == false then
		CrewInstanceService.SaveCrewInventory(player, crewMemberInventory, {
			SourcePath = "captain_slot_release_rollback",
		})
		return nil, nil, "captain_slot_clear_failed"
	end

	CrewInstanceService.SyncCrewAvailableCounts(player)

	return tostring(instanceId), releasedInstanceData, "ok"
end

function CrewSlotAssignmentReconciler.BeginReset(player, source)
	local state = getResetState(player)
	if not state then
		return nil
	end

	state.Depth += 1
	state.Epoch += 1
	state.Source = tostring(source or "ship_slot_reset")
	state.StartedAt = os.clock()

	player:SetAttribute(RESET_IN_PROGRESS_ATTRIBUTE, true)
	player:SetAttribute(RESET_EPOCH_ATTRIBUTE, state.Epoch)

	return state.Epoch
end

function CrewSlotAssignmentReconciler.EndReset(player, epoch)
	local state = resetStateByPlayer[player]
	if not state then
		return
	end

	local numericEpoch = tonumber(epoch)
	if numericEpoch ~= nil and numericEpoch > state.Epoch then
		return
	end

	state.Depth = math.max(0, state.Depth - 1)
	if state.Depth > 0 then
		return
	end

	state.CompletedAt = os.clock()
	local completedSource = state.Source
	state.Source = ""
	player:SetAttribute(RESET_IN_PROGRESS_ATTRIBUTE, nil)

	local completedEvent = resetCompletedEventsByPlayer[player]
	if completedEvent then
		completedEvent:Fire(state.Epoch, completedSource)
	end
end

function CrewSlotAssignmentReconciler.IsResetInProgress(player)
	local state = resetStateByPlayer[player]
	return state ~= nil and state.Depth > 0
end

function CrewSlotAssignmentReconciler.WaitForResetToComplete(player, timeoutSeconds)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	if not CrewSlotAssignmentReconciler.IsResetInProgress(player) then
		return true, "not_in_progress"
	end

	local completedEvent = getResetCompletedEvent(player)
	if not completedEvent then
		return false, "missing_reset_event"
	end

	local done = Instance.new("BindableEvent")
	local settled = false
	local function settle(ok, reason)
		if settled then
			return
		end

		settled = true
		done:Fire(ok, reason)
	end

	local connection = completedEvent.Event:Connect(function()
		settle(true, "completed")
	end)

	local timeout = math.max(0.1, tonumber(timeoutSeconds) or 8)
	task.delay(timeout, function()
		settle(false, "timeout")
	end)

	if not CrewSlotAssignmentReconciler.IsResetInProgress(player) then
		settle(true, "completed")
	end

	local ok, reason = done.Event:Wait()

	if connection.Connected then
		connection:Disconnect()
	end
	done:Destroy()

	return ok, reason
end

function CrewSlotAssignmentReconciler.ResetAssignmentsForRebirth(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}

	local crewMemberInventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(crewMemberInventory) ~= "table" or typeof(crewMemberInventory.ById) ~= "table" then
		return false, "missing_crew_inventory"
	end

	local now = os.time()
	local unassigned = 0
	local storedAfterDisplacement = CrewQuickSlotService.CountStoredInstances(player, crewMemberInventory)
	local storageSlots = CrewQuickSlotService.GetInventoryStorageSlots(player)
	local movedToStorage = 0
	local movedToOverflow = 0
	local displacedSource = tostring(options.Source or "rebirth_slot_reset")
	for instanceId, instanceData in pairs(crewMemberInventory.ById) do
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") ~= "" then
			instanceData.AssignedStand = ""
			instanceData.LastReleasedAt = now
			CrewQuickSlotService.ClearAssignmentsForInstance(player, tostring(instanceId))
			if storedAfterDisplacement < storageSlots then
				instanceData.Overflow = false
				instanceData.OverflowSource = ""
				instanceData.OverflowedAt = 0
				storedAfterDisplacement += 1
				movedToStorage += 1
			else
				instanceData.Overflow = true
				instanceData.OverflowSource = displacedSource
				instanceData.OverflowedAt = now
				movedToOverflow += 1
			end
			unassigned += 1
		end
	end

	local ok, reason = clearAssignmentTables(player)
	if not ok then
		return false, reason
	end

	if unassigned > 0 then
		local saved, saveReason = CrewInstanceService.SaveCrewInventory(player, crewMemberInventory, {
			SourcePath = tostring(options.SourcePath or "rebirth_slot_reset_release_assigned"),
		})
		if saved == false then
			return false, tostring(saveReason or "failed_to_release_assigned_units")
		end
	end

	ok, reason = clearAssignmentTables(player)
	if not ok then
		return false, reason
	end

	CrewInstanceService.SyncCrewAvailableCounts(player)

	return true, "ok", {
		Source = tostring(options.Source or "rebirth_slot_reset"),
		UnassignedCount = unassigned,
		MovedToStorageCount = movedToStorage,
		MovedToOverflowCount = movedToOverflow,
		ClearedCrewMemberIncome = true,
		ClearedShipSlots = true,
		ClearedCaptainSlot = true,
	}
end

function CrewSlotAssignmentReconciler.ReconcilePlayer(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}
	if CrewSlotAssignmentReconciler.IsResetInProgress(player) and options.AllowDuringReset ~= true then
		return false, "reset_in_progress", {
			Source = tostring(options.Source or "unspecified"),
		}
	end

	local slotKeys = {}
	if typeof(options.SlotKeys) == "table" then
		for _, slotKey in ipairs(options.SlotKeys) do
			addSlotKey(slotKeys, slotKey)
		end
	end

	collectActiveShipSlotKeys(slotKeys, options.ActiveShip)
	collectIncomeSlotKeys(slotKeys, player)

	local crewMemberInventory = CrewInstanceService.GetCrewInventory(player)
	collectInventorySlotKeys(slotKeys, crewMemberInventory)
	collectShipSlotMirrorKeys(slotKeys, DataManager:GetValue(player, SHIP_SLOTS_PATH))

	local migrated = migrateShipSlotMirror(player, slotKeys)
	local rebuilt = rebuildMissingIncomeRowsFromInventory(player, slotKeys, crewMemberInventory)
	local repaired = 0
	local failed = {}

	for _, slotKey in ipairs(sortedSlotKeys(slotKeys)) do
		local ok, reason = CrewInstanceService.ReconcileStandAssignment(player, slotKey)
		if ok then
			repaired += 1
		else
			failed[#failed + 1] = string.format("%s:%s", slotKey, tostring(reason))
		end
	end

	local mirrorChanged = syncShipSlotsMirror(player, slotKeys)
	local summary = {
		Source = tostring(options.Source or "unspecified"),
		SlotCount = #sortedSlotKeys(slotKeys),
		MigratedShipSlots = migrated,
		RebuiltIncomeRows = rebuilt,
		ReconciledSlots = repaired,
		MirrorChanged = mirrorChanged,
		Failures = failed,
	}

	if #failed > 0 then
		return false, "slot_reconcile_failed", summary
	end

	return true, "ok", summary
end

function CrewSlotAssignmentReconciler.ReconcileSlot(player, slotKey, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	options.SlotKeys = { slotKey }
	return CrewSlotAssignmentReconciler.ReconcilePlayer(player, options)
end

return CrewSlotAssignmentReconciler
