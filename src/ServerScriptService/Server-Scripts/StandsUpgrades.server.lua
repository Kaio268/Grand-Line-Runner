local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local CREW_MEMBER_STAND_UPGRADE_REMOTE_NAME = "CrewMemberStandUpgradeRemote"
local CREW_MEMBER_STAND_UPGRADE_PREVIEW_REMOTE_NAME = "CrewMemberStandUpgradePreviewRemote"
local CREW_MEMBER_STAND_UPGRADE_RESULT_REMOTE_NAME = "CrewMemberStandUpgradeStepResultRemote"

local function getOrCreateRemote(remoteName, className)
	local remote = remotes:FindFirstChild(remoteName)
	if remote and not remote:IsA(className) then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new(className)
		remote.Name = remoteName
		remote.Parent = remotes
	end
	return remote
end

local crewMemberRemote = getOrCreateRemote(CREW_MEMBER_STAND_UPGRADE_REMOTE_NAME, "RemoteEvent")
local crewMemberPreviewRemote = getOrCreateRemote(CREW_MEMBER_STAND_UPGRADE_PREVIEW_REMOTE_NAME, "RemoteFunction")
local crewMemberResultRemote = getOrCreateRemote(CREW_MEMBER_STAND_UPGRADE_RESULT_REMOTE_NAME, "RemoteEvent")

local CaptainSlotRuntime = require(game.ServerScriptService.Modules:WaitForChild("CaptainSlotRuntime"))
local CrewFoodProgression = require(game.ServerScriptService.Modules:WaitForChild("CrewFoodProgression"))
local CrewIncomeRuntime = require(game.ServerScriptService.Modules:WaitForChild("CrewIncomeRuntime"))
local CrewInstanceService = require(game.ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewMemberCanonicalReadGate = require(game.ServerScriptService.Modules:WaitForChild("CrewMemberCanonicalReadGate"))
local CrewStandIncomeAuthority = require(game.ServerScriptService.Modules:WaitForChild("CrewStandIncomeAuthority"))
local GrandLineRushVerticalSliceService = require(game.ServerScriptService.Modules:WaitForChild("GrandLineRushVerticalSliceService"))
local ServerRestartService = require(game.ServerScriptService.Modules:WaitForChild("ServerRestartService"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local ShipSlotLevelPanelState = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("ShipSlotLevelPanelState"))
local ShipRuntimeService = require(game.ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
local ShipSlotGuiIdentity = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ShipSlotGuiIdentity"))
local ShipSlotService = require(game.ServerScriptService.Modules:WaitForChild("ShipSlotService"))

local SUCCESS_COLOR = Color3.fromRGB(92, 230, 126)
local INFO_COLOR = Color3.fromRGB(111, 188, 255)
local ERROR_COLOR = Color3.fromRGB(255, 94, 94)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local CAPTAIN_SLOT_KEY = ShipSlotService.CaptainSlotKey or "Captain"
local CAPTAIN_RUNTIME_GUI_ATTRIBUTE = "ShipCaptainSlotRuntimeGui"
local CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE = "ShipCaptainSlotKey"
local CAPTAIN_RUNTIME_GUI_NAME = "ShipCaptainSlotLevelUp"
local FOOD_STATUS_CANARY_ATTRIBUTE = "CrewMemberFoodStatusCanaryHotPathEnabled"
local FOOD_STATUS_CANARY_SAMPLE_RATE = 0.01
local FOOD_STATUS_CANARY_SAMPLE_THROTTLE_SECONDS = 60
local MAX_UPGRADE_QUEUE_DEPTH = 8
local PERF_THRESHOLD_SECONDS = 0.025
local tutorialService = nil
local foodStatusCanaryLastSampleByUserId = {}
local upgradeQueues = {}
local upgradeWorkers = {}

local function logPerf(player, phase, target, durationSeconds, result, extra, always)
	extra = if typeof(extra) == "table" then extra else {}
	if always ~= true and game:GetAttribute("GTRPerformanceDebug") ~= true and durationSeconds < PERF_THRESHOLD_SECONDS then
		return
	end

	print(string.format(
		"[GTR_PERF] phase=%s player=%s userId=%s target=%s durationMs=%.3f replicaWriteCount=%s result=%s reason=%s",
		tostring(phase or ""),
		player and player.Name or "unknown",
		tostring(player and player.UserId or 0),
		tostring(target or ""),
		durationSeconds * 1000,
		tostring(extra.ReplicaWriteCount or ""),
		tostring(result or "ok"),
		tostring(extra.Reason or "none")
	))
end

local function shouldRunFoodStatusCanary(player)
	if RunService:IsStudio() or game:GetAttribute(FOOD_STATUS_CANARY_ATTRIBUTE) == true then
		return true
	end
	if math.random() > FOOD_STATUS_CANARY_SAMPLE_RATE then
		return false
	end

	local userId = player and player.UserId or 0
	local now = os.clock()
	local lastSampleAt = tonumber(foodStatusCanaryLastSampleByUserId[userId]) or 0
	if now - lastSampleAt < FOOD_STATUS_CANARY_SAMPLE_THROTTLE_SECONDS then
		return false
	end
	foodStatusCanaryLastSampleByUserId[userId] = now
	return true
end

local function pushResourceState(player)
	if GrandLineRushVerticalSliceService and typeof(GrandLineRushVerticalSliceService.PushState) == "function" then
		GrandLineRushVerticalSliceService.PushState(player)
	end
end

local function getTutorialService()
	if tutorialService ~= nil then
		return tutorialService
	end

	local module = game.ServerScriptService.Modules:FindFirstChild("TutorialService")
	if not module then
		return nil
	end

	local ok, service = pcall(require, module)
	if ok then
		tutorialService = service
	end
	return tutorialService
end

local function completeContextualTutorial(player, tutorialId, context)
	local service = getTutorialService()
	if typeof(service) ~= "table" or typeof(service.Complete) ~= "function" then
		return false, "tutorial_service_unavailable"
	end

	local ok, success, reason = pcall(service.Complete, player, tutorialId, context)
	if not ok then
		return false, "tutorial_complete_failed"
	end
	return success == true, reason
end

local function sendPopup(player, text, color, isError)
	PopUpModule:Server_SendPopUp(player, text, color or INFO_COLOR, STROKE_COLOR, 3, isError == true)
end

local function getStandName(payload)
	local rawStandName = ""

	if typeof(payload) == "table" then
		rawStandName = tostring(payload.StandName or "")
	elseif typeof(payload) == "string" then
		rawStandName = payload
	end

	if rawStandName == CAPTAIN_SLOT_KEY then
		return CAPTAIN_SLOT_KEY
	end

	return ShipSlotGuiIdentity.NormalizeSlotKey(rawStandName) or ""
end

local function buildFailurePayload(standName, errorCode, message, progress, step)
	return {
		Ok = false,
		StandName = standName,
		Error = errorCode,
		Message = message,
		Progress = progress,
		Step = step,
	}
end

local function getFailureMessage(errorCode)
	if errorCode == "crew_member_max_level" then
		return "This Crewmate is already max level."
	end
	if errorCode == "not_enough_food" then
		return "Not enough food to upgrade this Crewmate."
	end
	if errorCode == "step_changed" then
		return "The next food changed. Please confirm the new step."
	end
	if errorCode == "missing_crew_member" then
		return "Crewmate progress could not be loaded."
	end
	return "Unable to use food on this Crewmate right now."
end

local function getKnownFoodStatusDisplayNameForPopup(context, progress)
	local crewMemberId = tostring(
		(context and context.CrewMemberId)
			or (progress and progress.StorageName)
			or (progress and progress.CrewMemberId)
			or ""
	)
	if crewMemberId == "" then
		return nil
	end

	local _, info = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	if typeof(info) == "table" then
		local displayName = tostring(info.DisplayName or info.CrewMemberName or info.Name or "")
		if displayName ~= "" then
			return displayName
		end
	end
	return crewMemberId
end

local function getCanonicalFoodStatusDisplayNameForPopup(player, context)
	local crewMemberId = tostring(context and context.CrewMemberId or "")
	if crewMemberId == "" then
		return nil
	end

	local _, result = CrewMemberCanonicalReadGate.ResolveFoodStatusDisplayName(player, crewMemberId, {
		Player = player,
	})
	if typeof(result) ~= "table" then
		return nil
	end
	if result.UsedCanonical ~= true or result.IsAuthoritative == true then
		return nil
	end
	if tostring(result.Path or "") ~= CrewMemberCanonicalReadGate.Paths.GameplayHelperFoodStatusDisplayName then
		return nil
	end

	local displayName = tostring(result.Value or "")
	if displayName == "" then
		return nil
	end
	return displayName
end

local function getFoodStatusReadAuthorityDisplayNameForPopup(player, context, progress, appliedStep)
	local crewMemberId = tostring(context and context.CrewMemberId or "")
	if crewMemberId == "" then
		return nil
	end

	local _, result = CrewMemberCanonicalReadGate.ResolveFoodStatusReadAuthority(player, {
		StandName = tostring(context and context.StandName or ""),
		LegacyIdentity = crewMemberId,
		InstanceId = tostring(context and context.CrewMemberInstanceId or ""),
		Progress = progress,
		AppliedStep = appliedStep,
	}, {
		Player = player,
	})
	if typeof(result) ~= "table" then
		return nil
	end
	if result.UsedCanonical ~= true or result.IsMutationAuthority == true then
		return nil
	end
	if tostring(result.Path or "") ~= CrewMemberCanonicalReadGate.Paths.ReadAuthorityFoodStatus then
		return nil
	end

	local displayName = tostring(result.DisplayName or "")
	if displayName == "" then
		return nil
	end
	return displayName
end

local function getPlayerUpgradeLevel(player)
	local hiddenLeaderstats = player and player:FindFirstChild("HiddenLeaderstats")
	local valueObject = hiddenLeaderstats and hiddenLeaderstats:FindFirstChild(PlotUpgradeConfig.InternalStatName or "PlotUpgrade")
	if valueObject and valueObject:IsA("ValueBase") then
		return PlotUpgradeConfig.ClampLevel(valueObject.Value)
	end

	return 0
end

local function getPlayerRebirthCount(player)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	local valueObject = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if valueObject and valueObject:IsA("ValueBase") then
		return math.max(0, math.floor(tonumber(valueObject.Value) or 0))
	end

	return 0
end

local function findSlotGui(playerGui, standName)
	if standName == CAPTAIN_SLOT_KEY then
		local direct = playerGui:FindFirstChild(CAPTAIN_RUNTIME_GUI_NAME)
		if
			direct
			and direct:IsA("SurfaceGui")
			and direct:GetAttribute(CAPTAIN_RUNTIME_GUI_ATTRIBUTE) == true
			and tostring(direct:GetAttribute(CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE) or CAPTAIN_SLOT_KEY) == CAPTAIN_SLOT_KEY
		then
			return direct
		end

		for _, gui in ipairs(playerGui:GetChildren()) do
			if
				gui:IsA("SurfaceGui")
				and gui:GetAttribute(CAPTAIN_RUNTIME_GUI_ATTRIBUTE) == true
				and tostring(gui:GetAttribute(CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE) or CAPTAIN_SLOT_KEY) == CAPTAIN_SLOT_KEY
			then
				return gui
			end
		end

		return nil
	end

	local slotKey = ShipSlotGuiIdentity.NormalizeSlotKey(standName)
	if not slotKey then
		return nil
	end

	local legacyGui = playerGui:FindFirstChild(slotKey)
	if legacyGui and legacyGui:IsA("SurfaceGui") and ShipSlotGuiIdentity.GetSlotKeyFromGui(legacyGui) == slotKey then
		return legacyGui
	end

	local runtimeGuiName = ShipSlotGuiIdentity.GetRuntimeGuiName(slotKey)
	local runtimeGui = runtimeGuiName and playerGui:FindFirstChild(runtimeGuiName)
	if runtimeGui and runtimeGui:IsA("SurfaceGui") and ShipSlotGuiIdentity.GetSlotKeyFromGui(runtimeGui) == slotKey then
		return runtimeGui
	end

	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("SurfaceGui") and ShipSlotGuiIdentity.GetSlotKeyFromGui(gui) == slotKey then
			return gui
		end
	end

	return nil
end

local function validateOwnedShipSlot(player, standName)
	local slotKey = ShipSlotGuiIdentity.NormalizeSlotKey(standName)
	if not slotKey then
		return false, "invalid_stand", "Stand could not be identified."
	end

	local activeShip = ShipRuntimeService.GetActiveShip(player)
	if not activeShip then
		return false, "active_ship_not_found", "Your ship is not ready yet."
	end

	if activeShip:GetAttribute("OwnerUserId") ~= player.UserId then
		return false, "ship_owner_mismatch", "This ship slot does not belong to you."
	end

	local slotModel = ShipSlotService.GetSlot(activeShip, slotKey)
	if not slotModel or not slotModel:IsA("Model") then
		return false, "slot_not_found", "This crew slot is not available on your current ship."
	end

	local upgradeLevel = getPlayerUpgradeLevel(player)
	local rebirthCount = getPlayerRebirthCount(player)
	if not PlotUpgradeConfig.IsStandUsable(upgradeLevel, slotKey, rebirthCount) then
		return false, "slot_locked", PlotUpgradeConfig.GetLockedSlotDescription(upgradeLevel, slotKey, rebirthCount)
			or "This crew slot is locked."
	end

	if slotModel:GetAttribute("ShipSlotUsable") == false then
		return false, "slot_locked", "This crew slot is locked."
	end

	return true
end

local function validateOwnedCaptainSlot(player)
	local activeShip = ShipRuntimeService.GetActiveShip(player)
	if not activeShip then
		return false, "active_ship_not_found", "Your ship is not ready yet."
	end

	if activeShip:GetAttribute("OwnerUserId") ~= player.UserId then
		return false, "ship_owner_mismatch", "This ship slot does not belong to you."
	end

	local captainSpot = ShipSlotService.GetCaptainSlot(activeShip)
	if not captainSpot or not captainSpot:IsA("Model") then
		return false, "slot_not_found", "Captain's Spot is not available on your current ship."
	end

	local upgradeLevel = getPlayerUpgradeLevel(player)
	local rebirthCount = getPlayerRebirthCount(player)
	if not PlotUpgradeConfig.IsCaptainSlotUnlocked(upgradeLevel, rebirthCount) then
		return false, "slot_locked", "Captain's Spot is locked."
	end

	if captainSpot:GetAttribute("ShipSlotUsable") == false then
		return false, "slot_locked", "Captain's Spot is locked."
	end

	return true
end

local function getPanelUpgradeCostText(player, progress, hasFood)
	if not hasFood or not progress or (tonumber(progress.Level) or 1) >= (tonumber(progress.MaxLevel) or 1) then
		return ""
	end

	local progressTarget = tostring(progress.InstanceId or progress.StorageName or "")
	if progressTarget == "" or typeof(CrewFoodProgression.GetNextAutoFeedStep) ~= "function" then
		return ""
	end

	local previewOk, preview = CrewFoodProgression.GetNextAutoFeedStep(player, progressTarget)
	local step = previewOk and preview and preview.Step
	if typeof(step) ~= "table" then
		return ""
	end

	local amountUsed = math.max(0, math.floor(tonumber(step.AmountUsed) or 0))
	local foodName = tostring(step.FoodDisplayName or step.FoodKey or "")
	if amountUsed <= 0 or foodName == "" then
		return ""
	end

	return string.format("%dx %s", amountUsed, foodName)
end

local function updateStandGui(player, standName, progress)
	if not progress then
		return
	end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local standGui = findSlotGui(playerGui, standName)
	if not standGui then
		return
	end

	local foodCount = CrewFoodProgression.GetTotalFoodCount(player)
	local hasFood = foodCount > 0
	local panelState = ShipSlotLevelPanelState.Publish(standGui, {
		CurrentLevel = progress.Level,
		CurrentXP = progress.CurrentXP,
		FoodCount = foodCount,
		HasFood = hasFood,
		IsMaxLevel = progress.Level >= progress.MaxLevel,
		MaxLevel = progress.MaxLevel,
		NextLevelXP = progress.NextLevelXP,
		UpgradeCostText = getPanelUpgradeCostText(player, progress, hasFood),
	})

	local levelText = ShipSlotLevelPanelState.FormatLevelText(panelState)
	local progressText = ShipSlotLevelPanelState.FormatProgressText(panelState)
	if not standGui:FindFirstChild("LevelUp") or not standGui.LevelUp:FindFirstChild("Main") then
		return
	end

	local main = standGui.LevelUp.Main
	local price = main:FindFirstChild("Price", true)
	local upgrade = main:FindFirstChild("Upgarde", true) or main:FindFirstChild("Upgrade", true)

	if upgrade and (upgrade:IsA("TextLabel") or upgrade:IsA("TextButton") or upgrade:IsA("TextBox")) then
		upgrade.Text = levelText
	end

	if price and (price:IsA("TextLabel") or price:IsA("TextButton") or price:IsA("TextBox")) then
		price.Text = progressText
	end
end

local function resolveUpgradeContext(player, standName)
	if standName == "" then
		return false, buildFailurePayload("", "invalid_stand", "Stand could not be identified.")
	end

	if standName == CAPTAIN_SLOT_KEY then
		local slotOk, slotError, slotMessage = validateOwnedCaptainSlot(player)
		if not slotOk then
			return false, buildFailurePayload(standName, slotError, slotMessage or "Captain's Spot is not available.")
		end

		local assignment = CaptainSlotRuntime.GetAssignment(player)
		if typeof(assignment) ~= "table" then
			return false, buildFailurePayload(standName, "missing_crew_member", "Assign a captain first.")
		end

		local crewMemberInstanceId = tostring(
			assignment.CrewMemberInstanceId or assignment.InstanceId or assignment.CrewInstanceId or ""
		)
		local crewMemberId = tostring(
			assignment.CrewMemberName
				or assignment.CrewMemberId
				or assignment.StorageName
				or assignment.LegacyStorageName
				or ""
		)
		if crewMemberInstanceId == "" and crewMemberId == "" then
			return false, buildFailurePayload(standName, "missing_crew_member", "Assign a captain first.")
		end

		local instanceData = nil
		if crewMemberInstanceId ~= "" then
			local _, resolvedInstance = CrewInstanceService.GetInstance(player, crewMemberInstanceId)
			instanceData = resolvedInstance
		end
		if not instanceData then
			local crewMemberInventory = CrewInstanceService.GetCrewInventory(player)
			if typeof(crewMemberInventory) == "table" and typeof(crewMemberInventory.ById) == "table" then
				for candidateInstanceId, candidate in pairs(crewMemberInventory.ById) do
					if
						typeof(candidate) == "table"
						and tostring(candidate.AssignedStand or "") == CAPTAIN_SLOT_KEY
						and (
							crewMemberId == ""
							or tostring(candidate.StorageName or candidate.CrewMemberId or candidate.LegacyStorageName or "") == crewMemberId
						)
					then
						crewMemberInstanceId = tostring(candidateInstanceId)
						instanceData = candidate
						break
					end
				end
			end
		end
		if not instanceData or tostring(instanceData.AssignedStand or "") ~= CAPTAIN_SLOT_KEY then
			return false, buildFailurePayload(standName, "missing_crew_member", "Captain assignment could not be loaded.")
		end

		crewMemberId = tostring(instanceData.StorageName or instanceData.CrewMemberId or crewMemberId)
		local progressTarget = crewMemberInstanceId ~= "" and crewMemberInstanceId or crewMemberId
		local progress = CrewFoodProgression.GetProgress(player, progressTarget)
		if not progress then
			return false, buildFailurePayload(standName, "missing_crew_member", "Captain progress could not be loaded.")
		end

		return true, {
			StandName = standName,
			CrewMemberId = crewMemberId,
			CrewMemberInstanceId = crewMemberInstanceId,
			ProgressTarget = progressTarget,
			Progress = progress,
		}
	end

	local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
	local crewMemberId = standData and standData.CrewMemberName
	if typeof(crewMemberId) ~= "string" or crewMemberId == "" then
		return false, buildFailurePayload(standName, "missing_crew_member", "Place a Crewmate on this stand first.")
	end

	local slotOk, slotError, slotMessage = validateOwnedShipSlot(player, standName)
	if not slotOk then
		return false, buildFailurePayload(standName, slotError, slotMessage or "This crew slot is not available.")
	end

	local crewMemberInstanceId = CrewInstanceService.GetStandInstanceId(player, standName)
	if crewMemberInstanceId == "" then
		crewMemberInstanceId = CrewInstanceService.EnsureStandInstance(player, standName, crewMemberId) or ""
	end

	local progressTarget = crewMemberInstanceId ~= "" and crewMemberInstanceId or crewMemberId
	local progress = CrewFoodProgression.GetProgress(player, progressTarget)
	if not progress then
		return false, buildFailurePayload(standName, "missing_crew_member", "Crewmate progress could not be loaded.")
	end

	return true, {
		StandName = standName,
		CrewMemberId = crewMemberId,
		CrewMemberInstanceId = crewMemberInstanceId,
		ProgressTarget = progressTarget,
		Progress = progress,
	}
end

local function syncStandStateForProgress(player, fallbackStandName, progress)
	local startedAt = os.clock()
	local standName = tostring(fallbackStandName or "")
	updateStandGui(player, standName, progress)
	if standName ~= CAPTAIN_SLOT_KEY and CrewIncomeRuntime and typeof(CrewIncomeRuntime.RefreshStand) == "function" then
		CrewIncomeRuntime.RefreshStand(player, standName, "stand_upgrade_progress_sync")
	end
	logPerf(player, "StandUpdate", standName, os.clock() - startedAt, "ok")
end

local function fireStepResult(player, payload)
	crewMemberResultRemote:FireClient(player, payload)
end

local function buildUpgradePreview(player, standNameInput)
	local standName = getStandName(standNameInput)
	local ok, context = resolveUpgradeContext(player, standName)
	if not ok then
		return context
	end

	local previewOk, preview = CrewFoodProgression.GetNextAutoFeedStep(player, context.ProgressTarget)
	if not previewOk then
		local progress = preview and preview.Progress or context.Progress
		return buildFailurePayload(
			standName,
			preview and preview.Error or "preview_failed",
			getFailureMessage(preview and preview.Error or nil),
			progress,
			preview and preview.Step or nil
		)
	end

	return {
		Ok = true,
		StandName = standName,
		Progress = preview.Progress,
		Step = preview.Step,
	}
end

crewMemberPreviewRemote.OnServerInvoke = function(player, standNameInput)
	return buildUpgradePreview(player, standNameInput)
end

local function handleUpgradeRequest(player, payload)
	local upgradeStartedAt = os.clock()
	local standName = getStandName(payload)
	local function finishUpgrade(result, reason, replicaWriteCount)
		logPerf(player, "UpgradeComplete", standName, os.clock() - upgradeStartedAt, result, {
			Reason = tostring(reason or "none"),
			ReplicaWriteCount = replicaWriteCount or 0,
		}, true)
	end

	if standName == "" then
		finishUpgrade("failed", "invalid_stand")
		return
	end

	local restartBlocked, restartMessage = ServerRestartService.RejectIfFinalMinuteLocked(player, "feeding crewmates")
	if restartBlocked then
		fireStepResult(player, buildFailurePayload(
			standName,
			"server_restart_final_minute",
			restartMessage or "Server restart is in its final minute."
		))
		finishUpgrade("failed", "server_restart_final_minute")
		return
	end

	local expectedFoodKey = ""
	if typeof(payload) == "table" then
		expectedFoodKey = tostring(payload.ExpectedFoodKey or "")
	end

	local ok, context = resolveUpgradeContext(player, standName)
	if not ok then
		if context.Message then
			sendPopup(player, context.Message, ERROR_COLOR, true)
		end
		fireStepResult(player, context)
		finishUpgrade("failed", context.Error or "context_failed")
		return
	end

	local success, result = CrewFoodProgression.ApplyAutoFeedStep(
		player,
		context.ProgressTarget,
		expectedFoodKey ~= "" and expectedFoodKey or nil,
		{
			DeferShadowRefresh = true,
			StandName = standName,
		}
	)

	local progress = success and result and result.Progress or CrewFoodProgression.GetProgress(player, context.ProgressTarget)
	if not progress then
		finishUpgrade("failed", "progress_missing_after_apply", result and result.BatchInfo and result.BatchInfo.ReplicaWriteCount or 0)
		return
	end

	if not success then
		pushResourceState(player)

		local failurePayload = buildFailurePayload(
			standName,
			result and result.Error or "upgrade_failed",
			getFailureMessage(result and result.Error or nil),
			progress,
			result and result.Step or nil
		)

		sendPopup(player, failurePayload.Message, ERROR_COLOR, true)
		updateStandGui(player, standName, progress)
		fireStepResult(player, failurePayload)
		finishUpgrade("failed", failurePayload.Error or "upgrade_failed", result and result.BatchInfo and result.BatchInfo.ReplicaWriteCount or 0)
		return
	end

	local appliedStep = result.AppliedStep
	local appliedFoodName = tostring(appliedStep.FoodDisplayName or CrewFoodProgression.GetFoodDisplayName(appliedStep.FoodKey))

	pushResourceState(player)
	syncStandStateForProgress(player, standName, progress)
	CrewFoodProgression.RefreshProgressionShadow(player, "food_progression")
	completeContextualTutorial(player, "FeedCrewmates", {
		Source = "stand_auto_feed",
		StandName = standName,
		CrewInstanceId = tostring(progress.InstanceId or context.ProgressTarget or ""),
		FoodKey = tostring(appliedStep.FoodKey or ""),
		Level = tonumber(progress.Level) or 0,
		LevelUps = tonumber(result.LevelUps) or 0,
	})

	local foodStatusDisplayName = getKnownFoodStatusDisplayNameForPopup(context, progress)
	if shouldRunFoodStatusCanary(player) then
		foodStatusDisplayName = getFoodStatusReadAuthorityDisplayNameForPopup(player, context, progress, appliedStep)
			or getCanonicalFoodStatusDisplayNameForPopup(player, context)
			or foodStatusDisplayName
	end
	local foodUsedMessage = if foodStatusDisplayName ~= nil
		then string.format(
			"Used %dx %s on %s (+%d XP).",
			appliedStep.AmountUsed,
			appliedFoodName,
			foodStatusDisplayName,
			appliedStep.XPGained
		)
		else string.format("Used %dx %s (+%d XP).", appliedStep.AmountUsed, appliedFoodName, appliedStep.XPGained)
	sendPopup(player, foodUsedMessage, SUCCESS_COLOR, false)

	local continuePreview = nil
	if progress.Level < progress.MaxLevel then
		local nextPreviewOk, nextPreview = CrewFoodProgression.GetNextAutoFeedStep(player, context.ProgressTarget)
		if nextPreviewOk then
			continuePreview = nextPreview.Step
			if continuePreview and tostring(continuePreview.FoodKey) ~= tostring(appliedStep.FoodKey) then
				sendPopup(
					player,
					string.format("%s used up. Switching to %s.", appliedFoodName, tostring(continuePreview.FoodDisplayName or continuePreview.FoodKey)),
					INFO_COLOR,
					false
				)
			end
		end
	end

	if result.LevelUps > 0 then
		sendPopup(
			player,
			string.format("Upgrade complete. Current Level: %d (+%d level).", progress.Level, result.LevelUps),
			SUCCESS_COLOR,
			false
		)
	else
		sendPopup(
			player,
			string.format("Current XP: %d / %d.", progress.CurrentXP, progress.NextLevelXP),
			INFO_COLOR,
			false
		)

		if not continuePreview and progress.Level < progress.MaxLevel then
			sendPopup(
				player,
				string.format("Out of food. Current XP: %d / %d.", progress.CurrentXP, progress.NextLevelXP),
				INFO_COLOR,
				false
			)
		end
	end

	fireStepResult(player, {
		Ok = true,
		StandName = standName,
		AppliedStep = appliedStep,
		Progress = progress,
		LevelUps = result.LevelUps,
		ContinuePreview = continuePreview,
	})
	finishUpgrade("ok", "none", result.BatchInfo and result.BatchInfo.ReplicaWriteCount or 0)
end

local function startUpgradeWorker(player)
	if upgradeWorkers[player] == true then
		return
	end
	upgradeWorkers[player] = true

	task.spawn(function()
		while player.Parent == Players do
			local queue = upgradeQueues[player]
			local job = queue and table.remove(queue, 1)
			if job == nil then
				break
			end

			local ok, err = xpcall(handleUpgradeRequest, debug.traceback, player, job.Payload)
			if not ok then
				local standName = getStandName(job.Payload)
				warn(string.format(
					"[StandsUpgrades] upgrade handler failed player=%s userId=%s stand=%s error=%s",
					player and player.Name or "unknown",
					tostring(player and player.UserId or 0),
					tostring(standName),
					tostring(err)
				))
				fireStepResult(player, buildFailurePayload(
					standName,
					"upgrade_failed",
					"Unable to use food on this Crewmate right now."
				))
				logPerf(player, "UpgradeComplete", standName, os.clock() - (job.EnqueuedAt or os.clock()), "failed", {
					Reason = "handler_error",
					ReplicaWriteCount = 0,
				}, true)
			end

			task.wait()
		end

		upgradeWorkers[player] = nil
		local queue = upgradeQueues[player]
		if player.Parent == Players and queue ~= nil and #queue > 0 then
			startUpgradeWorker(player)
		end
	end)
end

local function enqueueUpgradeRequest(player, payload)
	if player.Parent ~= Players then
		return
	end

	local queue = upgradeQueues[player]
	if queue == nil then
		queue = {}
		upgradeQueues[player] = queue
	end

	if #queue >= MAX_UPGRADE_QUEUE_DEPTH then
		local standName = getStandName(payload)
		local failurePayload = buildFailurePayload(
			standName,
			"upgrade_queue_full",
			"Upgrades are still processing. Please try again in a moment."
		)
		fireStepResult(player, failurePayload)
		sendPopup(player, failurePayload.Message, ERROR_COLOR, true)
		logPerf(player, "UpgradeComplete", standName, 0, "failed", {
			Reason = "queue_full",
			ReplicaWriteCount = 0,
		}, true)
		return
	end

	queue[#queue + 1] = {
		Payload = payload,
		EnqueuedAt = os.clock(),
	}
	startUpgradeWorker(player)
end

Players.PlayerRemoving:Connect(function(player)
	upgradeQueues[player] = nil
	upgradeWorkers[player] = nil
	foodStatusCanaryLastSampleByUserId[player.UserId] = nil
end)

crewMemberRemote.OnServerEvent:Connect(function(player, payload)
	enqueueUpgradeRequest(player, payload)
end)
