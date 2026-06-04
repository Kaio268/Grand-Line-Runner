local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local TutorialConfigs = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Tutorials"))
local TutorialTargetResolvers = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TutorialTargetResolvers"))

local TutorialService = {}

local REMOTES_FOLDER_NAME = "Remotes"
local FIRST_TIME_TUTORIAL_ACTIVE_ATTRIBUTE = "FirstTimeTutorialActive"
local TRIGGER_COOLDOWN_SECONDS = 1
local CONTEXT_MAX_KEYS = 16
local CONTEXT_MAX_STRING_LENGTH = 160

local sessions = {}
local lastTriggerAtByPlayer = {}
local queueTimersByPlayer = {}
local started = false
local requestRemote = nil
local stateRemote = nil
local baseAreaService = nil
local verticalSliceService = nil
local warnedLazyRequires = {}

local tryProcessQueue

local function warnOnce(key, message)
	if warnedLazyRequires[key] then
		return
	end
	warnedLazyRequires[key] = true
	warn(message)
end

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

local function lazyRequireModule(moduleName, cacheName)
	local cached
	if cacheName == "baseArea" then
		cached = baseAreaService
	elseif cacheName == "verticalSlice" then
		cached = verticalSliceService
	end
	if cached ~= nil then
		return cached
	end

	local modules = ServerScriptService:FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild(moduleName)
	if module == nil then
		warnOnce(cacheName .. "_missing", string.format("[TutorialService] %s is unavailable.", moduleName))
		return nil
	end

	local ok, service = pcall(require, module)
	if not ok then
		warnOnce(
			cacheName .. "_require_failed",
			string.format("[TutorialService] Failed to require %s: %s", moduleName, tostring(service))
		)
		return nil
	end

	if cacheName == "baseArea" then
		baseAreaService = service
	elseif cacheName == "verticalSlice" then
		verticalSliceService = service
	end
	return service
end

local function getBaseAreaService()
	return lazyRequireModule("BaseAreaService", "baseArea")
end

local function getVerticalSliceService()
	return lazyRequireModule("GrandLineRushVerticalSliceService", "verticalSlice")
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

local function sanitizeContext(context)
	if typeof(context) ~= "table" then
		return {}
	end

	local sanitized = {}
	local count = 0
	for key, value in pairs(context) do
		local keyText = tostring(key or "")
		if keyText ~= "" and #keyText <= 64 and count < CONTEXT_MAX_KEYS then
			local valueType = typeof(value)
			if valueType == "string" then
				sanitized[keyText] = string.sub(value, 1, CONTEXT_MAX_STRING_LENGTH)
				count += 1
			elseif valueType == "number" then
				if value == value and value ~= math.huge and value ~= -math.huge then
					sanitized[keyText] = value
					count += 1
				end
			elseif valueType == "boolean" then
				sanitized[keyText] = value
				count += 1
			end
		end
	end

	return sanitized
end

local function normalizeQueue(queue)
	local normalized = {}
	if typeof(queue) ~= "table" then
		return normalized
	end

	for _, entry in ipairs(queue) do
		if typeof(entry) == "table" then
			local tutorialId = tostring(entry.Id or entry.TutorialId or "")
			local definition = TutorialConfigs.GetDefinition(tutorialId)
			if tutorialId ~= "" and definition ~= nil and definition.Enabled == true then
				local enqueuedAt = math.max(0, math.floor(tonumber(entry.EnqueuedAtUnix) or os.time()))
				local eligibleAt = math.max(0, math.floor(tonumber(entry.EligibleAtUnix) or enqueuedAt))
				table.insert(normalized, {
					Id = tutorialId,
					EnqueuedAtUnix = enqueuedAt,
					EligibleAtUnix = eligibleAt,
					Context = sanitizeContext(entry.Context),
				})
			end
		end
	end

	return normalized
end

local function readQueue(player)
	local queue, reason = DataManager:TryGetValue(player, TutorialConfigs.GetQueuePath())
	if reason ~= nil then
		return nil, reason
	end

	return normalizeQueue(queue), nil
end

local function writeQueue(player, queue)
	local success, reason = DataManager:TrySetValue(player, TutorialConfigs.GetQueuePath(), normalizeQueue(queue))
	return success == true, reason
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

	local modularFirstRunComplete, modularReason = isTutorialCompleted(player, "FirstRun")
	if modularReason ~= nil then
		return false, modularReason
	end
	if modularFirstRunComplete == true then
		return true, nil
	end

	return markTutorialCompleted(player, "FirstRun")
end

local function removeQueuedTutorial(player, tutorialId)
	local queue, reason = readQueue(player)
	if queue == nil then
		return false, reason
	end

	local changed = false
	for index = #queue, 1, -1 do
		if tostring(queue[index].Id or "") == tutorialId then
			table.remove(queue, index)
			changed = true
		end
	end

	if not changed then
		return true, nil
	end

	return writeQueue(player, queue)
end

local function isTutorialQueued(queue, tutorialId)
	for _, entry in ipairs(queue or {}) do
		if tostring(entry.Id or "") == tutorialId then
			return true
		end
	end
	return false
end

local function hasOccupiedCarrySlot(run)
	local carrySlots = run and run.CarrySlots
	if typeof(carrySlots) ~= "table" then
		return false
	end

	for _, slot in ipairs(carrySlots) do
		if
			typeof(slot) == "table"
			and (slot.Occupied == true or tostring(slot.CarryId or "") ~= "" or typeof(slot.Data) == "table")
		then
			return true
		end
	end

	return false
end

local function isPlayerRunSafe(player)
	local service = getVerticalSliceService()
	if typeof(service) ~= "table" or typeof(service.GetState) ~= "function" then
		return false, "run_state_unavailable"
	end

	local ok, state = pcall(service.GetState, player)
	if not ok then
		return false, "run_state_failed"
	end

	local run = state and state.Run
	if typeof(run) ~= "table" then
		return true, nil
	end

	if run.InRun == true then
		return false, "in_run"
	end
	if run.SpawnedReward ~= nil then
		return false, "spawned_reward_active"
	end
	if run.CarriedReward ~= nil then
		return false, "carried_reward_active"
	end
	if hasOccupiedCarrySlot(run) then
		return false, "carry_slots_active"
	end

	return true, nil
end

local function isPlayerInBaseArea(player)
	local service = getBaseAreaService()
	if typeof(service) ~= "table" or typeof(service.IsPlayerInBaseArea) ~= "function" then
		return false, "base_area_unavailable"
	end

	local ok, inBase = pcall(service.IsPlayerInBaseArea, player)
	if not ok then
		return false, "base_area_failed"
	end
	return inBase == true, if inBase == true then nil else "not_in_base"
end

local function buildTarget(player, definition, session)
	local resolverKey = tostring(definition and definition.TargetResolver or "")
	if resolverKey == "" then
		return nil
	end

	local ok, target = pcall(TutorialTargetResolvers.Resolve, resolverKey, player, {
		definition = definition,
		session = session,
	})
	if not ok then
		warnOnce(
			"target_resolver_" .. resolverKey,
			string.format("[TutorialService] Target resolver %s failed: %s", resolverKey, tostring(target))
		)
		return nil
	end

	return if typeof(target) == "table" then target else nil
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
		target = buildTarget(player, definition, session),
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

local function scheduleQueueEntry(player, entry)
	if typeof(entry) ~= "table" then
		return
	end

	local tutorialId = tostring(entry.Id or "")
	if tutorialId == "" then
		return
	end

	queueTimersByPlayer[player] = queueTimersByPlayer[player] or {}
	if queueTimersByPlayer[player][tutorialId] == true then
		return
	end

	local delaySeconds = math.max(0, math.floor(tonumber(entry.EligibleAtUnix) or 0) - os.time())
	if delaySeconds <= 0 then
		return
	end

	queueTimersByPlayer[player][tutorialId] = true
	task.delay(delaySeconds, function()
		local timers = queueTimersByPlayer[player]
		if timers then
			timers[tutorialId] = nil
		end
		if player.Parent == Players then
			tryProcessQueue(player, "eligible_timer")
		end
	end)
end

local function canStartDirectTutorial(player, tutorialId, triggerContext)
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

local function canStartQueuedTutorial(player, entry)
	local tutorialId = tostring(entry and entry.Id or "")
	if tutorialId == "" then
		return false, "invalid_tutorial"
	end

	if sessions[player] then
		return false, "tutorial_active"
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

	local eligibleAt = math.floor(tonumber(entry.EligibleAtUnix) or 0)
	if eligibleAt > os.time() then
		return false, "not_eligible"
	end

	local inBase, baseReason = isPlayerInBaseArea(player)
	if inBase ~= true then
		return false, baseReason or "not_in_base"
	end

	local runSafe, runReason = isPlayerRunSafe(player)
	if runSafe ~= true then
		return false, runReason or "run_not_safe"
	end

	return true, nil
end

local function canClientDisplayQueuedEntry(entry, payload)
	payload = if typeof(payload) == "table" then payload else {}

	local definition = TutorialConfigs.GetDefinition(tostring(entry and entry.Id or ""))
	local presentation = definition and definition.Presentation
	if typeof(presentation) ~= "table" or tostring(presentation.Type or "") ~= "ScreenGui" then
		return false, "unsupported_presentation"
	end

	local guiName = tostring(presentation.GuiName or "")
	if guiName == "" then
		return false, "missing_screen_gui_config"
	end

	local availableScreenGuis = payload.ScreenGuis
	if typeof(availableScreenGuis) ~= "table" then
		return false, "client_missing_screen_gui"
	end
	if availableScreenGuis[guiName] ~= true then
		return false, "client_missing_screen_gui"
	end

	return true, nil
end

local function startDirectTutorial(player, tutorialId, triggerContext)
	local now = os.clock()
	local lastTriggerAt = lastTriggerAtByPlayer[player] or 0
	if now - lastTriggerAt < TRIGGER_COOLDOWN_SECONDS then
		return false, "cooldown"
	end
	lastTriggerAtByPlayer[player] = now

	if sessions[player] then
		return true, nil
	end

	local canStart, reason = canStartDirectTutorial(player, tutorialId, triggerContext)
	if canStart ~= true then
		return false, reason
	end

	sessions[player] = {
		tutorialId = tutorialId,
		stepIndex = 1,
		startedAt = os.clock(),
		context = sanitizeContext(triggerContext),
		queued = false,
	}
	pushState(player)
	return true, nil
end

local function startQueuedTutorial(player, entry)
	local tutorialId = tostring(entry.Id or "")
	sessions[player] = {
		tutorialId = tutorialId,
		stepIndex = 1,
		startedAt = os.clock(),
		context = sanitizeContext(entry.Context),
		queued = true,
	}
	pushState(player)
	return true, nil
end

tryProcessQueue = function(player, _reason, clientReady, clientPayload)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "invalid_player"
	end
	if sessions[player] then
		return false, "tutorial_active"
	end
	if DataManager:IsReady(player) ~= true then
		return false, "data_not_ready"
	end

	local queue, queueReason = readQueue(player)
	if queue == nil then
		return false, queueReason or "queue_unavailable"
	end

	local queueChanged = false
	local index = 1
	while index <= #queue do
		local entry = queue[index]
		local tutorialId = tostring(entry.Id or "")
		local completed = isTutorialCompleted(player, tutorialId)
		if completed == true then
			table.remove(queue, index)
			queueChanged = true
		else
			local canStart, reason = canStartQueuedTutorial(player, entry)
			if canStart == true then
				if queueChanged then
					writeQueue(player, queue)
				end
				if clientReady ~= true then
					pushState(player)
					return false, "client_not_ready"
				end
				local canDisplay, displayReason = canClientDisplayQueuedEntry(entry, clientPayload)
				if canDisplay ~= true then
					return false, displayReason
				end
				return startQueuedTutorial(player, entry)
			end

			if reason == "not_eligible" then
				scheduleQueueEntry(player, entry)
			end
			if queueChanged then
				writeQueue(player, queue)
			end
			return false, reason
		end
	end

	if queueChanged then
		writeQueue(player, queue)
	end
	return false, "queue_empty"
end

local function completeTutorial(player, tutorialId, _context)
	local alreadyCompleted, completedReason = isTutorialCompleted(player, tutorialId)
	if completedReason ~= nil then
		return false, completedReason
	end
	if alreadyCompleted == true then
		removeQueuedTutorial(player, tutorialId)
		if sessions[player] and sessions[player].tutorialId == tutorialId then
			sessions[player] = nil
			pushState(player)
		end
		return true, nil
	end

	local success, reason = markTutorialCompleted(player, tutorialId)
	if success ~= true then
		return false, reason or "save_failed"
	end

	removeQueuedTutorial(player, tutorialId)
	if sessions[player] and sessions[player].tutorialId == tutorialId then
		sessions[player] = nil
	end
	pushState(player)
	task.defer(function()
		if player.Parent == Players then
			tryProcessQueue(player, "tutorial_completed")
		end
	end)
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
		local success, reason = startDirectTutorial(player, tutorialId, triggerContext)
		return {
			success = success == true,
			message = reason,
			state = buildState(player),
		}
	elseif action == "TryStartQueued" or action == "StartQueued" then
		if typeof(payload) ~= "table" or payload.ClientReady ~= true then
			return {
				success = false,
				message = "client_not_ready",
				state = buildState(player),
			}
		end

		local success, reason = tryProcessQueue(player, "client_ready", true, payload)
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

function TutorialService.Enqueue(player, tutorialId, context, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	tutorialId = tostring(tutorialId or "")
	local definition = TutorialConfigs.GetDefinition(tutorialId)
	if tutorialId == "" or not definition or definition.Enabled ~= true then
		return false, "unknown_tutorial"
	end

	if DataManager:IsReady(player) ~= true then
		task.spawn(function()
			if DataManager:WaitUntilReady(player, 10) and player.Parent == Players then
				TutorialService.Enqueue(player, tutorialId, context, options)
			end
		end)
		return false, "data_not_ready"
	end

	local completed, completedReason = isTutorialCompleted(player, tutorialId)
	if completedReason ~= nil then
		return false, completedReason
	end
	if completed == true then
		return false, "already_completed"
	end

	if sessions[player] and sessions[player].tutorialId == tutorialId then
		return true, "already_active"
	end

	local queue, queueReason = readQueue(player)
	if queue == nil then
		return false, queueReason or "queue_unavailable"
	end
	if isTutorialQueued(queue, tutorialId) then
		return true, "already_queued"
	end

	options = if typeof(options) == "table" then options else {}
	local nowUnix = os.time()
	local delaySeconds = math.max(
		0,
		math.floor(tonumber(options.EligibleDelaySeconds) or tonumber(definition.EligibleDelaySeconds) or 0)
	)
	local eligibleAt = math.max(nowUnix, math.floor(tonumber(options.EligibleAtUnix) or (nowUnix + delaySeconds)))
	local entry = {
		Id = tutorialId,
		EnqueuedAtUnix = nowUnix,
		EligibleAtUnix = eligibleAt,
		Context = sanitizeContext(context),
	}

	table.insert(queue, entry)
	local saved, saveReason = writeQueue(player, queue)
	if saved ~= true then
		return false, saveReason or "queue_save_failed"
	end

	scheduleQueueEntry(player, entry)
	task.defer(function()
		if player.Parent == Players then
			tryProcessQueue(player, "enqueue")
		end
	end)

	return true, nil
end

function TutorialService.Complete(player, tutorialId, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	tutorialId = tostring(tutorialId or "")
	local definition = TutorialConfigs.GetDefinition(tutorialId)
	if tutorialId == "" or not definition or definition.Enabled ~= true then
		return false, "unknown_tutorial"
	end

	if DataManager:IsReady(player) ~= true then
		task.spawn(function()
			if DataManager:WaitUntilReady(player, 10) and player.Parent == Players then
				TutorialService.Complete(player, tutorialId, context)
			end
		end)
		return false, "data_not_ready"
	end

	return completeTutorial(player, tutorialId, context)
end

function TutorialService.TryProcessQueue(player, reason)
	return tryProcessQueue(player, reason)
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

	local service = getBaseAreaService()
	if typeof(service) == "table" and typeof(service.PlayerEnteredBaseArea) == "RBXScriptSignal" then
		service.PlayerEnteredBaseArea:Connect(function(player)
			tryProcessQueue(player, "base_entered")
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			if DataManager:WaitUntilReady(player, 30) then
				local queue = readQueue(player)
				if typeof(queue) == "table" then
					for _, entry in ipairs(queue) do
						scheduleQueueEntry(player, entry)
					end
				end
				tryProcessQueue(player, "player_added")
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		lastTriggerAtByPlayer[player] = nil
		queueTimersByPlayer[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			if DataManager:WaitUntilReady(player, 30) then
				local queue = readQueue(player)
				if typeof(queue) == "table" then
					for _, entry in ipairs(queue) do
						scheduleQueueEntry(player, entry)
					end
				end
				tryProcessQueue(player, "start_existing_player")
			end
		end)
	end
end

return TutorialService
