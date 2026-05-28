local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewSlotAssignmentReconciler = require(ServerScriptService.Modules:WaitForChild("CrewSlotAssignmentReconciler"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local IncomeClaimMath = require(ServerScriptService.Modules:WaitForChild("IncomeClaimMath"))
local QuestSignals = require(ServerScriptService.Modules:WaitForChild("GrandLineRushQuestSignals"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))
local RebirthConfig = require(Configs:WaitForChild("Rebirths"))
local StandUpgradeMults = require(ServerScriptService.Modules:WaitForChild("StandsMultiply"))

local CaptainSlotRuntime = {}

local CAPTAIN_SLOT_KEY = CrewSlotAssignmentReconciler.CaptainSlotKey or ShipSlotService.CaptainSlotKey or "Captain"
local CAPTAIN_SLOT_DATA_PATH = "Ship.CaptainSlot"
local CAPTAIN_INCOME_FIELD = "IncomeToCollect"
local CAPTAIN_INCOME_PATH = CAPTAIN_SLOT_DATA_PATH .. "." .. CAPTAIN_INCOME_FIELD
local PLACEMENT_PICKUP_GUARD_SECONDS = 1.25
local CLAIM_TOUCH_DEBOUNCE_SECONDS = 0.35
local INCOME_TICK_SECONDS = 1
local LOCKED_LABEL = "LOCKED"
local EMPTY_LABEL = "CAPTAIN"

local runtimeByPlayer = setmetatable({}, { __mode = "k" })
local placementPickupGuardUntil = setmetatable({}, { __mode = "k" })
local claimTouchDebounce = setmetatable({}, { __mode = "k" })
local callbacks = {}
local dataManagerModule = nil
local incomeLoopStarted = false

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
		local dataManager = getDataManager()
		if typeof(dataManager.TryGetValue) == "function" then
			return dataManager:TryGetValue(player, path)
		end
		return dataManager:GetValue(player, path)
	end)

	return if ok then value else nil
end

local function dmSet(player, path, value)
	local ok, result = pcall(function()
		local dataManager = getDataManager()
		if typeof(dataManager.TrySetValue) == "function" then
			return dataManager:TrySetValue(player, path, value)
		end
		return dataManager:SetValue(player, path, value)
	end)

	return ok and result ~= false
end

local function dmAdd(player, path, amount)
	local ok, result = pcall(function()
		local dataManager = getDataManager()
		if typeof(dataManager.TryAddValue) == "function" then
			return dataManager:TryAddValue(player, path, amount)
		end
		return dataManager:AddValue(player, path, amount)
	end)

	return ok and result ~= false
end

local function getRuntimeDataReadiness(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		return false, "cleanup"
	end

	local dataManager = getDataManager()
	if typeof(dataManager.IsHardResetPending) == "function" and dataManager:IsHardResetPending(player.UserId) then
		return false, "cleanup"
	end
	if typeof(dataManager.IsReady) == "function" and not dataManager:IsReady(player) then
		return false, "not_ready"
	end

	return true, nil
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

local function getCaptainIncomeToCollect(player, captainSlot)
	captainSlot = if typeof(captainSlot) == "table" then captainSlot else dmGet(player, CAPTAIN_SLOT_DATA_PATH)
	if typeof(captainSlot) ~= "table" then
		return 0
	end

	return math.max(0, tonumber(captainSlot[CAPTAIN_INCOME_FIELD]) or 0)
end

local function setCaptainIncomeToCollect(player, amount)
	return dmSet(player, CAPTAIN_INCOME_PATH, math.max(0, tonumber(amount) or 0))
end

local function getBaseIncome(player, crewMemberName, instanceId)
	if typeof(callbacks.GetBaseIncome) == "function" then
		return math.max(0, tonumber(callbacks.GetBaseIncome(player, crewMemberName, instanceId)) or 0)
	end

	return 0
end

local function getBeliBoostMultiplier(player)
	if typeof(callbacks.GetBeliBoostMultiplier) == "function" then
		return math.max(0, tonumber(callbacks.GetBeliBoostMultiplier(player)) or 1)
	end

	return 1
end

local function getCrewMemberLevel(player, crewMemberName, instanceId)
	local target = if tostring(instanceId or "") ~= "" then tostring(instanceId) else tostring(crewMemberName or "")
	if target ~= "" and typeof(callbacks.GetCrewMemberLevel) == "function" then
		return math.max(1, math.floor(tonumber(callbacks.GetCrewMemberLevel(player, target)) or 1))
	end

	return 1
end

local function getCrewLevelMultiplier(player, crewMemberName, instanceId)
	local level = getCrewMemberLevel(player, crewMemberName, instanceId)
	local multiplier = tonumber(StandUpgradeMults[tostring(level)]) or 1
	if multiplier <= 0 then
		return 1
	end

	return multiplier
end

local function getCaptainBonusMultiplierForAssignment(player, instanceId)
	instanceId = tostring(instanceId or "")
	if instanceId == "" then
		return 1
	end

	local assignment = getSavedCaptainAssignment(player)
	local _, assignedInstanceId = getCaptainAssignmentCrewName(player, assignment)
	if assignedInstanceId == "" or assignedInstanceId ~= instanceId then
		return 1
	end

	local _, instanceData = CrewInstanceService.GetInstance(player, instanceId)
	if typeof(instanceData) ~= "table" or tostring(instanceData.AssignedStand or "") ~= CAPTAIN_SLOT_KEY then
		return 1
	end

	return PlotUpgradeConfig.GetCaptainBonusMultiplier(getPlayerShipUpgradeLevel(player), getPlayerRebirthCount(player))
end

local function getCaptainCollectMultiplier(player, crewMemberName, instanceId)
	return getCrewLevelMultiplier(player, crewMemberName, instanceId)
		* RebirthConfig.GetShipIncomeMultiplier(getPlayerRebirthCount(player))
		* getCaptainBonusMultiplierForAssignment(player, instanceId)
end

local function getCaptainBankAmountPerTick(player, crewMemberName, instanceId)
	return getBaseIncome(player, crewMemberName, instanceId) * getBeliBoostMultiplier(player)
end

local function getCaptainDisplayIncome(player, crewMemberName, instanceId)
	local assignment = getSavedCaptainAssignment(player)
	local pending = getCaptainIncomeToCollect(player, assignment)
	return IncomeClaimMath.GetWholeClaimableAmount(
		pending,
		getCaptainCollectMultiplier(player, crewMemberName, instanceId)
	)
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

local function refreshRuntimeSlotRefs(runtime)
	if not runtime or not runtime.CaptainSpot or not runtime.CaptainSpot.Parent then
		return
	end

	runtime.ClaimHitBox = ShipSlotService.GetClaimHitBox(runtime.CaptainSpot)
	runtime.MoneyLabel = ShipSlotService.GetClaimMoneyLabel(runtime.CaptainSpot)
end

local function setMoneyLabelText(runtime, text)
	if not runtime or not runtime.MoneyLabel or not runtime.MoneyLabel.Parent then
		return
	end

	text = tostring(text or "")
	if runtime.LastMoneyText == text and runtime.MoneyLabel.Text == text then
		return
	end

	runtime.MoneyLabel.TextWrapped = true
	runtime.MoneyLabel.Text = text
	runtime.LastMoneyText = text
end

local function updateCaptainMoneyText(player, runtime, assignment)
	if not runtime or not runtime.CaptainSpot or not runtime.CaptainSpot.Parent then
		return
	end
	if not runtime.MoneyLabel or not runtime.MoneyLabel.Parent then
		refreshRuntimeSlotRefs(runtime)
	end
	if not runtime.MoneyLabel or not runtime.MoneyLabel.Parent then
		return
	end

	local state = runtime.State or getCaptainSlotState(player)
	if not state.Unlocked then
		setMoneyLabelText(runtime, LOCKED_LABEL)
		return
	end

	assignment = if typeof(assignment) == "table" then assignment else getSavedCaptainAssignment(player)
	local crewMemberName, instanceId = getCaptainAssignmentCrewName(player, assignment)
	if crewMemberName == "" then
		if state.BonusPercent > 0 then
			setMoneyLabelText(runtime, string.format("%s +%d%%", EMPTY_LABEL, state.BonusPercent))
		else
			setMoneyLabelText(runtime, EMPTY_LABEL)
		end
		return
	end

	local displayIncome = getCaptainDisplayIncome(player, crewMemberName, instanceId)
	setMoneyLabelText(runtime, CurrencyUtil.formatIncomeCompactAmount(displayIncome))
end

local function updateCaptainLevelUpUI(player, runtime, assignment, forceRefresh)
	if not runtime or not runtime.CaptainSpot or not runtime.CaptainSpot.Parent then
		return
	end
	if typeof(callbacks.UpdateCaptainLevelUpUI) ~= "function" then
		return
	end

	local state = runtime.State or getCaptainSlotState(player)
	assignment = if typeof(assignment) == "table" then assignment else getSavedCaptainAssignment(player)
	local crewMemberName, instanceId = getCaptainAssignmentCrewName(player, assignment)
	callbacks.UpdateCaptainLevelUpUI(
		player,
		runtime.CaptainSpot,
		{
			Visible = true,
			Usable = state.Unlocked == true,
		},
		crewMemberName,
		instanceId,
		forceRefresh == true
	)
end

local function setClaimTouchEnabled(runtime, enabled)
	if runtime and runtime.ClaimHitBox and runtime.ClaimHitBox.Parent then
		runtime.ClaimHitBox.CanTouch = enabled == true
	end
end

local function refreshNormalIncomeDisplays(player)
	if typeof(callbacks.RefreshNormalIncomeDisplays) == "function" then
		callbacks.RefreshNormalIncomeDisplays(player)
	end
end

local function setRuntimeHasCaptain(player, hasCaptain)
	local runtime = runtimeByPlayer[player]
	if runtime then
		local nextHasCaptain = hasCaptain == true
		local changed = runtime.HasCaptain ~= nextHasCaptain
		runtime.HasCaptain = nextHasCaptain
		if changed then
			refreshNormalIncomeDisplays(player)
		end
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
		local getEquippedCrewMemberToolInfo = callbacks.GetEquippedCrewMemberToolInfo
		local equippedInfo = if typeof(getEquippedCrewMemberToolInfo) == "function"
			then getEquippedCrewMemberToolInfo(player)
			else nil
		prompt.ActionText = if equippedInfo and equippedInfo.Name ~= "" then "Switch Captain" else "Remove Captain"
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
		setClaimTouchEnabled(runtime, false)
		updateCaptainMoneyText(player, runtime)
		updateCaptainLevelUpUI(player, runtime, nil, true)
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
		setClaimTouchEnabled(runtime, true)
		updateCaptainMoneyText(player, runtime, assignment)
		updateCaptainLevelUpUI(player, runtime, assignment, true)
		return
	end

	local spawnCrewMember = callbacks.SpawnCrewMember
	if typeof(spawnCrewMember) ~= "function" then
		logCrewSwitchFailure(player, "captain_visual_refresh_failed", "missing_spawn_callback")
		updatePromptText(player, runtime)
		updateCaptainMoneyText(player, runtime, assignment)
		updateCaptainLevelUpUI(player, runtime, assignment, true)
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
	setClaimTouchEnabled(runtime, true)
	updateCaptainMoneyText(player, runtime, assignment)
	updateCaptainLevelUpUI(player, runtime, assignment, true)
end

local function getCaptainPlacementCandidate(player, equippedInfo, options)
	options = if typeof(options) == "table" then options else {}
	if not equippedInfo or equippedInfo.Name == "" then
		return nil, nil, false, "no_equipped_crewmate"
	end

	local tutorialInstanceId, tutorialInstance
	if options.AllowTutorialFallback ~= false and typeof(callbacks.FindAvailableTutorialPlacementReward) == "function" then
		tutorialInstanceId, tutorialInstance = callbacks.FindAvailableTutorialPlacementReward(player, equippedInfo.Name)
	end
	if tutorialInstance then
		return tostring(tutorialInstanceId or ""), tutorialInstance, true, nil
	end

	if
		options.SkipInventoryPreflight ~= true
		and typeof(callbacks.GetInventoryQuantity) == "function"
		and callbacks.GetInventoryQuantity(player, equippedInfo.Name) < 1
	then
		return nil, nil, false, "no_inventory"
	end

	if options.SkipInventoryPreflight ~= true and typeof(callbacks.CanEquipCrewMember) == "function" then
		local quickSlotUnlocked = callbacks.CanEquipCrewMember(player, equippedInfo.Name)
		if not quickSlotUnlocked then
			if typeof(callbacks.PromptUnlockForCrewMember) == "function" then
				callbacks.PromptUnlockForCrewMember(player, equippedInfo.Name)
			end
			return nil, nil, false, "quick_slot_locked"
		end
	end

	if equippedInfo.InstanceId == "" then
		return nil, nil, false, "incoming_instance_missing"
	end

	return equippedInfo.InstanceId, nil, false, nil
end

local function assignEquippedCaptain(player, runtime)
	local getEquippedCrewMemberToolInfo = callbacks.GetEquippedCrewMemberToolInfo
	local equippedInfo = if typeof(getEquippedCrewMemberToolInfo) == "function"
		then getEquippedCrewMemberToolInfo(player)
		else nil
	local candidateInstanceId, _, isTutorialPlacement, candidateReason = getCaptainPlacementCandidate(player, equippedInfo)
	if not candidateInstanceId then
		logCrewSwitchFailure(player, tostring(candidateReason or "captain_place_rejected"), "captain_place_rejected")
		updatePromptText(player, runtime)
		updateCaptainMoneyText(player, runtime)
		updateCaptainLevelUpUI(player, runtime, nil, true)
		return
	end

	local placedInstanceId, placedInstance, placeReason = CrewSlotAssignmentReconciler.AssignCaptain(
		player,
		candidateInstanceId,
		{
			ExpectedIncomingStorageName = equippedInfo.Name,
			ClearTutorialMetadataAfterAssign = isTutorialPlacement == true,
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
		callbacks.GetCrewMemberLevel(player, placedInstanceId)
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
		TutorialPlacement = isTutorialPlacement == true,
		TutorialRewardConverted = isTutorialPlacement == true,
	})
	setRuntimeHasCaptain(player, true)
	updatePromptText(player, runtime)
	updateCaptainMoneyText(player, runtime)
	updateCaptainLevelUpUI(player, runtime, nil, true)
end

local function switchEquippedCaptain(player, runtime, equippedInfo)
	local candidateInstanceId, _, isTutorialPlacement, candidateReason = getCaptainPlacementCandidate(player, equippedInfo, {
		AllowTutorialFallback = false,
		SkipInventoryPreflight = true,
	})
	if not candidateInstanceId then
		logCrewSwitchFailure(player, tostring(candidateReason or "captain_switch_rejected"), "captain_switch_rejected")
		updatePromptText(player, runtime)
		updateCaptainMoneyText(player, runtime)
		updateCaptainLevelUpUI(player, runtime, nil, true)
		return
	end

	local incomingInstanceId, incomingInstance, outgoingInstanceId, outgoingInstance, switchReason =
		CrewSlotAssignmentReconciler.SwapCaptain(player, candidateInstanceId, {
			ExpectedIncomingStorageName = equippedInfo.Name,
			ClearIncomingTutorialMetadataAfterAssign = isTutorialPlacement == true,
			Source = "captain_prompt_switch",
			SourcePath = "captain_prompt_switch",
		})
	if not incomingInstance then
		logCrewSwitchFailure(player, tostring(switchReason or "captain_switch_failed"))
		updatePromptText(player, runtime)
		updateCaptainMoneyText(player, runtime)
		updateCaptainLevelUpUI(player, runtime, nil, true)
		return
	end

	if typeof(callbacks.ClearCrewRecordCache) == "function" then
		callbacks.ClearCrewRecordCache(player)
	end
	if typeof(callbacks.GetCrewMemberLevel) == "function" then
		callbacks.GetCrewMemberLevel(player, incomingInstanceId)
	end
	setPlacementPickupGuard(player)

	local spawnCrewMember = callbacks.SpawnCrewMember
	if typeof(spawnCrewMember) == "function" then
		local placedModel, visualReason = spawnCrewMember(player, runtime.CaptainSpot, runtime.Handle, incomingInstance.StorageName)
		if not placedModel then
			logCrewSwitchFailure(
				player,
				"captain_visual_refresh_failed",
				string.format("incomingInstanceId=%s reason=%s", tostring(incomingInstanceId), tostring(visualReason or "unknown"))
			)
		end
	end

	if typeof(callbacks.EquipCrewMemberToolByInstanceId) == "function" then
		callbacks.EquipCrewMemberToolByInstanceId(player, outgoingInstanceId, outgoingInstance and outgoingInstance.StorageName or "")
	end

	QuestSignals.Record(player, "PlaceOnStand", 1, {
		Source = "CaptainPlacement",
		StandName = CAPTAIN_SLOT_KEY,
		CrewMemberName = tostring(incomingInstance.StorageName or equippedInfo.Name),
		CrewMemberInstanceId = tostring(incomingInstanceId),
		SwitchPlacement = true,
		TutorialPlacement = isTutorialPlacement == true,
		TutorialRewardConverted = isTutorialPlacement == true,
	})
	setRuntimeHasCaptain(player, true)
	updatePromptText(player, runtime)
	updateCaptainMoneyText(player, runtime)
	updateCaptainLevelUpUI(player, runtime, nil, true)
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
		updateCaptainMoneyText(player, runtime)
		updateCaptainLevelUpUI(player, runtime, nil, true)
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
	updateCaptainMoneyText(player, runtime)
	updateCaptainLevelUpUI(player, runtime, nil, true)
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

			local getEquippedCrewMemberToolInfo = callbacks.GetEquippedCrewMemberToolInfo
			local equippedInfo = if typeof(getEquippedCrewMemberToolInfo) == "function"
				then getEquippedCrewMemberToolInfo(player)
				else nil
			if CaptainSlotRuntime.HasAssignedCaptain(player) then
				if equippedInfo and equippedInfo.Name ~= "" then
					switchEquippedCaptain(player, runtime, equippedInfo)
				else
					releaseAssignedCaptain(player, runtime)
				end
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

local function fireMoneyCollected(player, captainSpot, collected, crewMemberName)
	if typeof(callbacks.FireMoneyCollected) ~= "function" then
		return
	end

	local payload = nil
	if typeof(callbacks.BuildIncomeToastDisplayPayload) == "function" then
		payload = callbacks.BuildIncomeToastDisplayPayload(player, crewMemberName)
	end

	callbacks.FireMoneyCollected(player, captainSpot, collected, payload)
end

local function collectCaptainIncome(player, activeShip, runtime)
	if not runtime or not runtime.CaptainSpot or not runtime.CaptainSpot.Parent then
		return
	end

	runtime.State = getCaptainSlotState(player)
	if not runtime.State.Unlocked then
		updatePromptText(player, runtime)
		setClaimTouchEnabled(runtime, false)
		updateCaptainMoneyText(player, runtime)
		return
	end

	if activeShip:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end

	local assignment = getSavedCaptainAssignment(player)
	local crewMemberName, instanceId = getCaptainAssignmentCrewName(player, assignment)
	if crewMemberName == "" then
		updateCaptainMoneyText(player, runtime, assignment)
		return
	end

	local baseToCollect = getCaptainIncomeToCollect(player, assignment)
	if baseToCollect <= 0 then
		updateCaptainMoneyText(player, runtime, assignment)
		return
	end

	local collectMultiplier = getCaptainCollectMultiplier(player, crewMemberName, instanceId)
	local collected = IncomeClaimMath.GetWholeClaimableAmount(baseToCollect, collectMultiplier)
	if collected <= 0 then
		updateCaptainMoneyText(player, runtime, assignment)
		return
	end

	local remainingRawIncome = IncomeClaimMath.GetRawRemainderAfterClaim(baseToCollect, collectMultiplier, collected)
	if not setCaptainIncomeToCollect(player, remainingRawIncome) then
		return
	end

	dmAdd(player, CurrencyUtil.getPrimaryPath(), collected)
	dmAdd(player, CurrencyUtil.getTotalPath(), collected)
	QuestSignals.Record(player, "EarnBeli", collected, {
		Source = "CaptainIncome",
		StandName = CAPTAIN_SLOT_KEY,
	})
	fireMoneyCollected(player, runtime.CaptainSpot, collected, crewMemberName)
	updateCaptainMoneyText(player, runtime)
end

local function bindClaimHitBox(player, activeShip, runtime)
	if not runtime or not runtime.ClaimHitBox then
		return
	end

	local zone = runtime.ClaimHitBox
	if runtime.Connections.ClaimTouched and runtime.Connections.ClaimTouched.Connected and runtime.BoundClaimHitBox == zone then
		return
	end

	if runtime.Connections.ClaimTouched and runtime.Connections.ClaimTouched.Connected then
		runtime.Connections.ClaimTouched:Disconnect()
	end

	runtime.BoundClaimHitBox = zone
	runtime.Connections.ClaimTouched = zone.Touched:Connect(function(hit)
		if not hit or hit.Name ~= "HumanoidRootPart" then
			return
		end

		local character = hit.Parent
		if not character then
			return
		end

		local touchingPlayer = Players:GetPlayerFromCharacter(character)
		if touchingPlayer ~= player then
			return
		end

		claimTouchDebounce[player] = claimTouchDebounce[player] or {}
		local now = os.clock()
		local last = claimTouchDebounce[player][zone]
		if last and (now - last) < CLAIM_TOUCH_DEBOUNCE_SECONDS then
			return
		end
		claimTouchDebounce[player][zone] = now

		collectCaptainIncome(player, activeShip, runtime)
	end)
end

local function syncCaptainOverhead(player, runtime, crewMemberName)
	if not runtime or not runtime.CaptainSpot or not runtime.CaptainSpot.Parent then
		return
	end
	if typeof(callbacks.SyncPlacedOverheadMetadata) ~= "function" then
		return
	end

	local placedModel = runtime.CaptainSpot:FindFirstChild("PlacedCrewMember")
	if placedModel and placedModel:IsA("Model") then
		callbacks.SyncPlacedOverheadMetadata(player, runtime.CaptainSpot, crewMemberName, placedModel)
	end
end

local function bankCaptainIncome(player, runtime)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent == nil then
		CaptainSlotRuntime.CleanupPlayer(player)
		return
	end
	local ready, readinessReason = getRuntimeDataReadiness(player)
	if not ready then
		if readinessReason == "cleanup" then
			CaptainSlotRuntime.CleanupPlayer(player)
		end
		return
	end
	if not runtime or not runtime.CaptainSpot or not runtime.CaptainSpot.Parent then
		CaptainSlotRuntime.CleanupPlayer(player)
		return
	end
	if not runtime.ActiveShip or runtime.ActiveShip.Parent == nil or runtime.ActiveShip:GetAttribute("OwnerUserId") ~= player.UserId then
		CaptainSlotRuntime.CleanupPlayer(player)
		return
	end

	runtime.State = getCaptainSlotState(player)
	if not runtime.State.Unlocked then
		setClaimTouchEnabled(runtime, false)
		clearVisual(runtime)
		setRuntimeHasCaptain(player, false)
		updatePromptText(player, runtime)
		updateCaptainMoneyText(player, runtime)
		updateCaptainLevelUpUI(player, runtime, nil, false)
		return
	end

	setClaimTouchEnabled(runtime, true)

	local assignment = getSavedCaptainAssignment(player)
	local crewMemberName, instanceId = getCaptainAssignmentCrewName(player, assignment)
	if crewMemberName == "" then
		setRuntimeHasCaptain(player, false)
		updatePromptText(player, runtime)
		updateCaptainMoneyText(player, runtime, assignment)
		updateCaptainLevelUpUI(player, runtime, assignment, false)
		return
	end

	setRuntimeHasCaptain(player, true)
	local incomeDelta = getCaptainBankAmountPerTick(player, crewMemberName, instanceId)
	if incomeDelta > 0 then
		local nextIncome = getCaptainIncomeToCollect(player, assignment) + incomeDelta
		setCaptainIncomeToCollect(player, nextIncome)
	end

	syncCaptainOverhead(player, runtime, crewMemberName)
	updatePromptText(player, runtime)
	updateCaptainMoneyText(player, runtime)
	updateCaptainLevelUpUI(player, runtime, assignment, false)
end

local function ensureIncomeLoopStarted()
	if incomeLoopStarted then
		return
	end
	incomeLoopStarted = true

	task.spawn(function()
		while true do
			task.wait(INCOME_TICK_SECONDS)

			for player, runtime in pairs(runtimeByPlayer) do
				local ok, err = xpcall(function()
					bankCaptainIncome(player, runtime)
				end, debug.traceback)
				if not ok then
					warn(("[CaptainSlotRuntime] Captain income tick failed for %s: %s"):format(
						player and player.Name or "unknown",
						tostring(err)
					))
				end
			end
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

function CaptainSlotRuntime.GetCaptainIncomePerSecond(player)
	local assignment = getSavedCaptainAssignment(player)
	local crewMemberName, instanceId = getCaptainAssignmentCrewName(player, assignment)
	if crewMemberName == "" then
		return 0
	end

	return getCaptainBankAmountPerTick(player, crewMemberName, instanceId)
		* getCaptainCollectMultiplier(player, crewMemberName, instanceId)
end

function CaptainSlotRuntime.GetCaptainCollectMultiplier(player)
	local assignment = getSavedCaptainAssignment(player)
	local crewMemberName, instanceId = getCaptainAssignmentCrewName(player, assignment)
	if crewMemberName == "" then
		return 1
	end

	return getCaptainCollectMultiplier(player, crewMemberName, instanceId)
end

function CaptainSlotRuntime.GetCaptainIncomeToCollect(player)
	local assignment = getSavedCaptainAssignment(player)
	if not assignment then
		return 0
	end

	local crewMemberName, instanceId = getCaptainAssignmentCrewName(player, assignment)
	if crewMemberName == "" then
		return 0
	end

	return getCaptainIncomeToCollect(player, assignment)
		* getCaptainCollectMultiplier(player, crewMemberName, instanceId)
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
			ClaimHitBox = nil,
			MoneyLabel = nil,
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
	refreshRuntimeSlotRefs(runtime)

	if not handle then
		if state.Unlocked then
			warn(("[CaptainSlotRuntime] Unlocked Captain's Spot is missing Handle for %s: %s"):format(
				player.Name,
				captainSpot:GetFullName()
			))
		end
		setClaimTouchEnabled(runtime, false)
		updateCaptainMoneyText(player, runtime)
		updateCaptainLevelUpUI(player, runtime, nil, true)
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
		setClaimTouchEnabled(runtime, state.Unlocked)
		updateCaptainMoneyText(player, runtime)
		updateCaptainLevelUpUI(player, runtime, nil, true)
		return false, "captain_prompt_missing"
	end

	prompt.Enabled = state.Unlocked
	setClaimTouchEnabled(runtime, state.Unlocked)
	bindClaimHitBox(player, activeShip, runtime)
	bindPrompt(player, activeShip, runtime)
	renderAssignedCaptain(player, runtime)
	refreshNormalIncomeDisplays(player)
	ensureIncomeLoopStarted()
	return true
end

function CaptainSlotRuntime.CleanupPlayer(player)
	local runtime = runtimeByPlayer[player]
	if not runtime then
		placementPickupGuardUntil[player] = nil
		claimTouchDebounce[player] = nil
		return
	end

	disconnectRuntime(runtime)
	clearVisual(runtime)
	runtimeByPlayer[player] = nil
	placementPickupGuardUntil[player] = nil
	claimTouchDebounce[player] = nil
end

return CaptainSlotRuntime
