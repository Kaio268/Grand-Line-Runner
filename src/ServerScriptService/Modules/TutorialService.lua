local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(game:GetService("ServerScriptService"):WaitForChild("Data"):WaitForChild("DataManager"))
local TutorialConfigs = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Tutorials"))

local TutorialService = {}

local REMOTES_FOLDER_NAME = "Remotes"
local FIRST_TIME_TUTORIAL_ACTIVE_ATTRIBUTE = "FirstTimeTutorialActive"
local TRIGGER_COOLDOWN_SECONDS = 1

local sessions = {}
local lastTriggerAtByPlayer = {}
local started = false
local requestRemote = nil
local stateRemote = nil

local function ensureRemotes()
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = REMOTES_FOLDER_NAME
		remotesFolder.Parent = ReplicatedStorage
	end

	local requestName = TutorialConfigs.Remotes.RequestName
	local existingRequest = remotesFolder:FindFirstChild(requestName)
	if existingRequest and existingRequest:IsA("RemoteFunction") then
		requestRemote = existingRequest
	elseif not existingRequest then
		requestRemote = Instance.new("RemoteFunction")
		requestRemote.Name = requestName
		requestRemote.Parent = remotesFolder
	else
		warn(string.format("[TutorialService] %s exists but is not a RemoteFunction.", requestName))
	end

	local stateName = TutorialConfigs.Remotes.StateName
	local existingState = remotesFolder:FindFirstChild(stateName)
	if existingState and existingState:IsA("RemoteEvent") then
		stateRemote = existingState
	elseif not existingState then
		stateRemote = Instance.new("RemoteEvent")
		stateRemote.Name = stateName
		stateRemote.Parent = remotesFolder
	else
		warn(string.format("[TutorialService] %s exists but is not a RemoteEvent.", stateName))
	end
end

local function normalizeStep(step)
	if typeof(step) ~= "table" then
		return nil
	end

	return {
		id = tostring(step.Id or step.id or ""),
		title = tostring(step.Title or step.title or "Tutorial"),
		body = tostring(step.Body or step.body or ""),
		instruction = tostring(step.Instruction or step.instruction or ""),
		actionText = tostring(step.ActionText or step.actionText or ""),
		waitText = tostring(step.WaitText or step.waitText or ""),
		completionMode = tostring(step.CompletionMode or step.completionMode or ""),
	}
end

local function isFirstRunComplete(player)
	local completed, reason = DataManager:TryGetValue(player, TutorialConfigs.LegacyFirstRunCompletionPath)
	if reason ~= nil then
		return false, reason
	end
	return completed == true, nil
end

local function isTutorialCompleted(player, tutorialId)
	local path = TutorialConfigs.GetCompletionPath(tutorialId)
	if path == nil then
		return false, "invalid_tutorial"
	end

	local completed, reason = DataManager:TryGetValue(player, path)
	if reason ~= nil then
		return false, reason
	end
	return completed == true, nil
end

local function markTutorialCompleted(player, tutorialId)
	local path = TutorialConfigs.GetCompletionPath(tutorialId)
	if path == nil then
		return false, "invalid_tutorial"
	end

	local success, reason = DataManager:TrySetValue(player, path, true)
	return success == true, reason
end

local function syncFirstRunCompletion(player)
	local firstRunComplete, reason = isFirstRunComplete(player)
	if firstRunComplete ~= true then
		return false, reason
	end

	local modularFirstRunComplete = isTutorialCompleted(player, "FirstRun")
	if modularFirstRunComplete == true then
		return true, nil
	end

	return markTutorialCompleted(player, "FirstRun")
end

local function buildState(player)
	local session = sessions[player]
	if not session then
		return {
			active = false,
			completed = false,
		}
	end

	local definition = TutorialConfigs.GetDefinition(session.tutorialId)
	local step = TutorialConfigs.GetStep(session.tutorialId, session.stepIndex)
	if not definition or not step then
		return {
			active = false,
			completed = false,
		}
	end

	local stepCount = math.max(1, TutorialConfigs.GetStepCount(session.tutorialId))
	local normalizedStep = normalizeStep(step)

	return {
		active = true,
		completed = false,
		tutorialId = session.tutorialId,
		title = tostring(definition.Title or definition.Id or session.tutorialId),
		step = normalizedStep,
		stepIndex = session.stepIndex,
		totalSteps = stepCount,
		progress = if normalizedStep and normalizedStep.completionMode == "Acknowledge" then 1 else 0,
		canAdvance = normalizedStep ~= nil and normalizedStep.completionMode == "Acknowledge",
		target = nil,
	}
end

local function pushState(player)
	if stateRemote and player.Parent == Players then
		stateRemote:FireClient(player, buildState(player))
	end
end

local function clearSession(player)
	sessions[player] = nil
	pushState(player)
end

local function completeTutorial(player, tutorialId)
	local success, reason = markTutorialCompleted(player, tutorialId)
	if success ~= true then
		return false, reason or "save_failed"
	end

	sessions[player] = nil
	pushState(player)
	return true, nil
end

local function canStartTutorial(player, tutorialId, triggerContext)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local definition = TutorialConfigs.GetDefinition(tutorialId)
	if not definition or definition.Enabled ~= true then
		return false, "unknown_tutorial"
	end

	if DataManager:IsReady(player) ~= true then
		return false, "data_not_ready"
	end

	if player:GetAttribute(FIRST_TIME_TUTORIAL_ACTIVE_ATTRIBUTE) == true then
		return false, "first_run_active"
	end

	local firstRunComplete, firstRunReason = isFirstRunComplete(player)
	if firstRunComplete ~= true then
		return false, firstRunReason or "first_run_incomplete"
	end
	syncFirstRunCompletion(player)

	local completed, completedReason = isTutorialCompleted(player, tutorialId)
	if completedReason ~= nil then
		return false, completedReason
	end
	if completed == true then
		return false, "already_completed"
	end

	if definition.Trigger then
		if typeof(triggerContext) ~= "table" then
			return false, "trigger_required"
		end

		local expectedType = tostring(definition.Trigger.Type or "")
		local expectedModalName = tostring(definition.Trigger.ModalName or "")
		if expectedType ~= "" and tostring(triggerContext.Type or "") ~= expectedType then
			return false, "trigger_mismatch"
		end
		if expectedModalName ~= "" and tostring(triggerContext.ModalName or "") ~= expectedModalName then
			return false, "trigger_mismatch"
		end
	end

	return true, nil
end

local function startTutorial(player, tutorialId, triggerContext)
	local now = os.clock()
	local lastTriggerAt = lastTriggerAtByPlayer[player] or 0
	if now - lastTriggerAt < TRIGGER_COOLDOWN_SECONDS then
		return false, "cooldown"
	end
	lastTriggerAtByPlayer[player] = now

	if sessions[player] then
		return true, nil
	end

	local canStart, reason = canStartTutorial(player, tutorialId, triggerContext)
	if canStart ~= true then
		return false, reason
	end

	sessions[player] = {
		tutorialId = tutorialId,
		stepIndex = 1,
		startedAt = os.clock(),
	}
	pushState(player)
	return true, nil
end

local function advanceTutorial(player)
	local session = sessions[player]
	if not session then
		return false, "not_active"
	end

	local step = TutorialConfigs.GetStep(session.tutorialId, session.stepIndex)
	if not step then
		clearSession(player)
		return false, "missing_step"
	end

	if tostring(step.CompletionMode or step.completionMode or "") ~= "Acknowledge" then
		return false, "step_not_manual"
	end

	local stepCount = TutorialConfigs.GetStepCount(session.tutorialId)
	if session.stepIndex >= stepCount then
		return completeTutorial(player, session.tutorialId)
	end

	session.stepIndex += 1
	pushState(player)
	return true, nil
end

local function skipTutorial(player)
	local session = sessions[player]
	if not session then
		return false, "not_active"
	end

	local definition = TutorialConfigs.GetDefinition(session.tutorialId)
	if definition and definition.SkipCompletes == true then
		return completeTutorial(player, session.tutorialId)
	end

	clearSession(player)
	return true, nil
end

local function handleRequest(player, action, payload)
	action = tostring(action or "")

	if action == "GetState" then
		return {
			success = true,
			state = buildState(player),
		}
	elseif action == "Trigger" then
		local tutorialId = if typeof(payload) == "table" then tostring(payload.TutorialId or "") else tostring(payload or "")
		local triggerContext = if typeof(payload) == "table" then payload.TriggerContext else nil
		local success, reason = startTutorial(player, tutorialId, triggerContext)
		return {
			success = success == true,
			message = reason,
			state = buildState(player),
		}
	elseif action == "Advance" then
		local success, reason = advanceTutorial(player)
		return {
			success = success == true,
			message = reason,
			state = buildState(player),
		}
	elseif action == "Skip" then
		local success, reason = skipTutorial(player)
		return {
			success = success == true,
			message = reason,
			state = buildState(player),
		}
	end

	return {
		success = false,
		message = "unknown_action",
		state = buildState(player),
	}
end

function TutorialService.Start()
	if started then
		return
	end
	started = true

	ensureRemotes()
	if requestRemote then
		requestRemote.OnServerInvoke = handleRequest
	end

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		lastTriggerAtByPlayer[player] = nil
	end)
end

return TutorialService
