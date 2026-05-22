local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewSlotAssignmentReconciler = require(ServerScriptService.Modules:WaitForChild("CrewSlotAssignmentReconciler"))
local QuestSignals = require(ServerScriptService.Modules:WaitForChild("GrandLineRushQuestSignals"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))

local CaptainSlotRuntime = {}

local CAPTAIN_SLOT_KEY = CrewSlotAssignmentReconciler.CaptainSlotKey or ShipSlotService.CaptainSlotKey or "Captain"
local CAPTAIN_SLOT_DATA_PATH = "Ship.CaptainSlot"
local PLACEMENT_PICKUP_GUARD_SECONDS = 1.25

local runtimeByPlayer = setmetatable({}, { __mode = "k" })
local placementPickupGuardUntil = setmetatable({}, { __mode = "k" })
local callbacks = {}
local dataManagerModule = nil

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local value = tostring(select(index, ...) or "")
		if value ~= "" then
			return value
		end
	end

	return ""
end

local function getDataManager()
	if dataManagerModule == nil then
		dataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerModule
end

local function dmGet(player, path)
	local ok, value = pcall(function()
		return getDataManager():GetValue(player, path)
	end)

	return if ok then value else nil
end

local function getPlayerShipUpgradeLevel(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 0
	end

	local hiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")
	if hiddenLeaderstats then
		local plotUpgradeValue = hiddenLeaderstats:FindFirstChild("PlotUpgrade")
		if plotUpgradeValue and plotUpgradeValue:IsA("NumberValue") then
			return PlotUpgradeConfig.ClampLevel(plotUpgradeValue.Value)
		end
	end

	local storedUpgrade = dmGet(player, "HiddenLeaderstats.PlotUpgrade")
	if typeof(storedUpgrade) == "number" then
		return PlotUpgradeConfig.ClampLevel(storedUpgrade)
	end

	return 0
end

local function getPlayerRebirthCount(player)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	local rebirthValue = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if rebirthValue and rebirthValue:IsA("ValueBase") then
		return math.max(0, math.floor(tonumber(rebirthValue.Value) or 0))
	end

	local storedRebirths = dmGet(player, "leaderstats.Rebirths")
	if typeof(storedRebirths) == "number" then
		return math.max(0, math.floor(storedRebirths))
	end

	return 0
end

local function getCaptainSlotState(player)
	local upgradeLevel = getPlayerShipUpgradeLevel(player)
	local rebirthCount = getPlayerRebirthCount(player)
	local info = PlotUpgradeConfig.GetCaptainSlotInfo(upgradeLevel, rebirthCount)

	return {
		Level = upgradeLevel,
		Rebirths = rebirthCount,
		Unlocked = info and info.Unlocked == true,
		State = info and tostring(info.State or "inactive") or "inactive",
		BonusPercent = math.max(0, tonumber(info and info.BonusPercent) or 0),
		BonusLabel = info and tostring(info.BonusLabel or "") or "",
	}
end

local function getSavedCaptainAssignment(player)
	local captainSlot = dmGet(player, CAPTAIN_SLOT_DATA_PATH)
	if typeof(captainSlot) ~= "table" then
		return nil
	end

	local crewMemberName = firstNonEmpty(
		captainSlot.CrewMemberName,
		captainSlot.CrewMemberId,
		captainSlot.StorageName,
		captainSlot.LegacyStorageName
	)
	local instanceId = firstNonEmpty(captainSlot.CrewMemberInstanceId, captainSlot.InstanceId, captainSlot.CrewInstanceId)
	if crewMemberName == "" and instanceId == "" then
		return nil
	end

	return captainSlot
end

local function getCaptainAssignmentCrewName(player, assignment)
	assignment = if typeof(assignment) == "table" then assignment else getSavedCaptainAssignment(player)
	if typeof(assignment) ~= "table" then
		return "", ""
	end

	local crewMemberName = firstNonEmpty(
		assignment.CrewMemberName,
		assignment.CrewMemberId,
		assignment.StorageName,
		assignment.LegacyStorageName
	)
	local instanceId = firstNonEmpty(assignment.CrewMemberInstanceId, assignment.InstanceId, assignment.CrewInstanceId)
	if crewMemberName == "" and instanceId ~= "" then
		local _, instanceData = CrewInstanceService.GetInstance(player, instanceId)
		crewMemberName = if typeof(instanceData) == "table"
			then firstNonEmpty(instanceData.StorageName, instanceData.CrewMemberId, instanceData.LegacyStorageName)
			else ""
	end

	return crewMemberName, instanceId
end

local function setPlacementPickupGuard(player)
	placementPickupGuardUntil[player] = os.clock() + PLACEMENT_PICKUP_GUARD_SECONDS
end

local function getPlacementPickupGuardRemaining(player)
	local expiresAt = tonumber(placementPickupGuardUntil[player]) or 0
	local remaining = expiresAt - os.clock()
	if remaining <= 0 then
		placementPickupGuardUntil[player] = nil
		return 0
	end

	return remaining
end

local function disconnectRuntime(runtime)
	if not runtime or typeof(runtime.Connections) ~= "table" then
		return
	end

	for _, connection in pairs(runtime.Connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(runtime.Connections)
end

local function clearVisual(runtime)
	local clearVisualCallback = callbacks.ClearVisual
	if runtime and runtime.CaptainSpot and runtime.CaptainSpot.Parent and typeof(clearVisualCallback) == "function" then
		clearVisualCallback(runtime.CaptainSpot)
	end
end

local function setRuntimeHasCaptain(player, hasCaptain)
	local runtime = runtimeByPlayer[player]
	if runtime then
		runtime.HasCaptain = hasCaptain == true
	end
end

local function logCrewSwitchFailure(player, reason, detail)
	if typeof(callbacks.LogCrewSwitchFailure) == "function" then
		callbacks.LogCrewSwitchFailure(player, CAPTAIN_SLOT_KEY, reason, detail)
	end
end

local function resolveDisplayName(player, crewMemberName)
	if typeof(callbacks.ResolveDisplayName) == "function" then
		local displayName = callbacks.ResolveDisplayName(player, crewMemberName)
		if tostring(displayName or "") ~= "" then
			return displayName
		end
	end

	return tostring(crewMemberName or "")
end

local function updatePromptText(player, runtime)
	if not runtime or not runtime.Prompt or not runtime.Prompt.Parent then
		return
	end

	local state = runtime.State or getCaptainSlotState(player)
	local prompt = runtime.Prompt
	if not state.Unlocked then
		prompt.Enabled = false
		prompt.ObjectText = "Captain's Spot"
		prompt.ActionText = "Upgrade Ship"
		return
	end

	prompt.Enabled = true
	local assignment = getSavedCaptainAssignment(player)
	local crewMemberName = getCaptainAssignmentCrewName(player, assignment)
	if crewMemberName ~= "" then
		prompt.ObjectText = resolveDisplayName(player, crewMemberName)
		prompt.ActionText = "Remove Captain"
	else
		prompt.ObjectText = if state.BonusPercent > 0
			then string.format("Captain's Spot (+%d%%)", state.BonusPercent)
			else "Captain's Spot"
		prompt.ActionText = "Assign Captain"
	end
end

local function renderAssignedCaptain(player, runtime)
	if not runtime or not runtime.CaptainSpot or not runtime.CaptainSpot.Parent then
		return
	end

	local state = runtime.State or getCaptainSlotState(player)
	if not state.Unlocked then
		clearVisual(runtime)
		updatePromptText(player, runtime)
		return
	end

	local ok, reason = CrewSlotAssignmentReconciler.ReconcileCaptain(player, {
		Source = "captain_render",
		ActiveShip = runtime.ActiveShip,
	})
	if ok == false and reason ~= "reset_in_progress" then
		warn(("[CaptainSlotRuntime] Captain assignment reconciliation failed for %s: %s"):format(
			player.Name,
			tostring(reason)
		))
	end

	local assignment = getSavedCaptainAssignment(player)
	local crewMemberName = getCaptainAssignmentCrewName(player, assignment)
	local hasCaptain = crewMemberName ~= ""
	setRuntimeHasCaptain(player, hasCaptain)
	if not hasCaptain then
		clearVisual(runtime)
		updatePromptText(player, runtime)
		return
	end

	local spawnCrewMember = callbacks.SpawnCrewMember
	if typeof(spawnCrewMember) ~= "function" then
		logCrewSwitchFailure(player, "captain_visual_refresh_failed", "missing_spawn_callback")
		updatePromptText(player, runtime)
		return
	end

	local placedModel, visualReason = spawnCrewMember(player, runtime.CaptainSpot, runtime.Handle, crewMemberName)
	if not placedModel then
		logCrewSwitchFailure(
			player,
			"captain_visual_refresh_failed",
			string.format("reason=%s", tostring(visualReason or "unknown"))
		)
	end
	updatePromptText(player, runtime)
end

local function assignEquippedCaptain(player, runtime)
	local getEquippedCrewMemberToolInfo = callbacks.GetEquippedCrewMemberToolInfo
	local equippedInfo = if typeof(getEquippedCrewMemberToolInfo) == "function"
		then getEquippedCrewMemberToolInfo(player)
		else nil
	if not equippedInfo or equippedInfo.Name == "" then
		logCrewSwitchFailure(player, "no_equipped_crewmate", "captain_place_rejected")
		return
	end

	if equippedInfo.InstanceId == "" then
		logCrewSwitchFailure(player, "incoming_instance_missing", "captain_tool_missing_instance_id")
		return
	end

	local placedInstanceId, placedInstance, placeReason = CrewSlotAssignmentReconciler.AssignCaptain(
		player,
		equippedInfo.InstanceId,
		{
			ExpectedIncomingStorageName = equippedInfo.Name,
			Source = "captain_prompt_assign",
			SourcePath = "captain_prompt_assign",
		}
	)
	if not placedInstance then
		logCrewSwitchFailure(player, tostring(placeReason or "captain_assign_failed"))
		updatePromptText(player, runtime)
		return
	end

	if typeof(callbacks.ClearCrewRecordCache) == "function" then
		callbacks.ClearCrewRecordCache(player)
	end
	if typeof(callbacks.GetCrewMemberLevel) == "function" then
		callbacks.GetCrewMemberLevel(player, placedInstance.StorageName or equippedInfo.Name)
	end
	setPlacementPickupGuard(player)

	local spawnCrewMember = callbacks.SpawnCrewMember
	if typeof(spawnCrewMember) == "function" then
		local placedModel, visualReason = spawnCrewMember(player, runtime.CaptainSpot, runtime.Handle, placedInstance.StorageName)
		if not placedModel then
			logCrewSwitchFailure(
				player,
				"captain_visual_refresh_failed",
				string.format("placedInstanceId=%s reason=%s", tostring(placedInstanceId), tostring(visualReason or "unknown"))
			)
		end
	end

	QuestSignals.Record(player, "PlaceOnStand", 1, {
		Source = "CaptainPlacement",
		StandName = CAPTAIN_SLOT_KEY,
		CrewMemberName = tostring(placedInstance.StorageName or equippedInfo.Name),
		CrewMemberInstanceId = tostring(placedInstanceId),
	})
	setRuntimeHasCaptain(player, true)
	updatePromptText(player, runtime)
end

local function releaseAssignedCaptain(player, runtime)
	if getPlacementPickupGuardRemaining(player) > 0 then
		return
	end

	local releasedInstanceId, releasedInstance, releaseReason = CrewSlotAssignmentReconciler.ClearCaptainAssignment(
		player,
		{
			Source = "captain_prompt_release",
			SourcePath = "captain_prompt_release",
		}
	)
	if not releasedInstance then
		logCrewSwitchFailure(player, tostring(releaseReason or "captain_release_failed"))
		clearVisual(runtime)
		setRuntimeHasCaptain(player, false)
		updatePromptText(player, runtime)
		return
	end

	if typeof(callbacks.ClearCrewRecordCache) == "function" then
		callbacks.ClearCrewRecordCache(player)
	end
	clearVisual(runtime)
	setRuntimeHasCaptain(player, false)
	if typeof(callbacks.EquipCrewMemberToolByInstanceId) == "function" then
		callbacks.EquipCrewMemberToolByInstanceId(player, releasedInstanceId, releasedInstance.StorageName)
	end
	updatePromptText(player, runtime)
end

local function bindPrompt(player, activeShip, runtime)
	if not runtime.Prompt then
		return
	end

	if runtime.Connections.PromptTriggered and runtime.Connections.PromptTriggered.Connected then
		return
	end

	runtime.Connections.PromptTriggered = runtime.Prompt.Triggered:Connect(function(plr)
		local ok, err = xpcall(function()
			if plr ~= player then
				local getEquippedCrewMemberToolInfo = callbacks.GetEquippedCrewMemberToolInfo
				if plr and plr:IsA("Player") and typeof(getEquippedCrewMemberToolInfo) == "function" and getEquippedCrewMemberToolInfo(plr) then
					logCrewSwitchFailure(plr, "captain_slot_not_owned")
				end
				return
			end

			if activeShip:GetAttribute("OwnerUserId") ~= player.UserId then
				logCrewSwitchFailure(player, "owner_mismatch")
				return
			end

			runtime.State = getCaptainSlotState(player)
			if not runtime.State.Unlocked then
				logCrewSwitchFailure(player, "captain_slot_locked")
				updatePromptText(player, runtime)
				return
			end

			if CaptainSlotRuntime.HasAssignedCaptain(player) then
				releaseAssignedCaptain(player, runtime)
			else
				assignEquippedCaptain(player, runtime)
			end
		end, debug.traceback)

		if not ok then
			warn(("[CaptainSlotRuntime] Captain prompt handler errored for %s: %s"):format(
				player.Name,
				tostring(err)
			))
		end
	end)
end

function CaptainSlotRuntime.Configure(nextCallbacks)
	if typeof(nextCallbacks) ~= "table" then
		return
	end

	for key, value in pairs(nextCallbacks) do
		callbacks[key] = value
	end
end

function CaptainSlotRuntime.GetAssignment(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	return getSavedCaptainAssignment(player)
end

function CaptainSlotRuntime.HasAssignedCaptain(player)
	local runtime = runtimeByPlayer[player]
	if runtime and runtime.HasCaptain ~= nil then
		return runtime.HasCaptain == true
	end

	return getSavedCaptainAssignment(player) ~= nil
end

function CaptainSlotRuntime.GetCaptainBonusMultiplier(player, upgradeLevel, rebirthCount)
	if not CaptainSlotRuntime.HasAssignedCaptain(player) then
		return 1
	end

	return PlotUpgradeConfig.GetCaptainBonusMultiplier(upgradeLevel, rebirthCount)
end

function CaptainSlotRuntime.RefreshPlayer(player, activeShip)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end
	if typeof(activeShip) ~= "Instance" or not activeShip:IsA("Model") then
		CaptainSlotRuntime.CleanupPlayer(player)
		return false, "invalid_active_ship"
	end

	local existingRuntime = runtimeByPlayer[player]
	if existingRuntime and existingRuntime.ActiveShip ~= activeShip then
		CaptainSlotRuntime.CleanupPlayer(player)
	end

	local state = getCaptainSlotState(player)
	local captainSpot, handle, prompt = ShipSlotService.GetCaptainSlotPrompt(activeShip)
	if not captainSpot then
		if state.Unlocked then
			warn(("[CaptainSlotRuntime] Active ship is missing Captain's Spot for %s: %s"):format(
				player.Name,
				activeShip:GetFullName()
			))
		end
		return false, "captain_slot_missing"
	end

	local runtime = runtimeByPlayer[player]
	if not runtime or runtime.CaptainSpot ~= captainSpot then
		CaptainSlotRuntime.CleanupPlayer(player)
		runtime = {
			Player = player,
			ActiveShip = activeShip,
			CaptainSpot = captainSpot,
			Handle = handle,
			Prompt = prompt,
			Connections = {},
			State = state,
			HasCaptain = getSavedCaptainAssignment(player) ~= nil,
		}
		runtimeByPlayer[player] = runtime
	else
		runtime.ActiveShip = activeShip
		runtime.Handle = handle
		runtime.Prompt = prompt
		runtime.State = state
	end

	if not handle then
		if state.Unlocked then
			warn(("[CaptainSlotRuntime] Unlocked Captain's Spot is missing Handle for %s: %s"):format(
				player.Name,
				captainSpot:GetFullName()
			))
		end
		return false, "captain_handle_missing"
	end

	if not prompt then
		if state.Unlocked then
			warn(("[CaptainSlotRuntime] Unlocked Captain's Spot is missing ProximityPrompt for %s: %s"):format(
				player.Name,
				captainSpot:GetFullName()
			))
		end
		clearVisual(runtime)
		return false, "captain_prompt_missing"
	end

	prompt.Enabled = state.Unlocked
	bindPrompt(player, activeShip, runtime)
	renderAssignedCaptain(player, runtime)
	return true
end

function CaptainSlotRuntime.CleanupPlayer(player)
	local runtime = runtimeByPlayer[player]
	if not runtime then
		placementPickupGuardUntil[player] = nil
		return
	end

	disconnectRuntime(runtime)
	clearVisual(runtime)
	runtimeByPlayer[player] = nil
	placementPickupGuardUntil[player] = nil
end

return CaptainSlotRuntime
