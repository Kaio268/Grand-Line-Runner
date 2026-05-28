local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TitleService = {}

local HYDRATE_READY_TIMEOUT = 30
local PERSIST_READY_TIMEOUT = 10
local EQUIP_REMOTE_NAME = "TitleEquipRequest"
local EQUIPPED_TITLE_ATTRIBUTE = "EquippedTitleId"
local EQUIPPED_TITLE_DISPLAY_ATTRIBUTE = "EquippedTitleDisplay"
local NONE_EQUIPPED = ""
local DATA_MANAGER_UNAVAILABLE_REASON = "data_manager_unavailable"

local AdminConfig = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AdminConfig"))
local TitlesConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Titles"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local started = false
local pendingUnlocksByPlayer = {}
local pendingEquippedByPlayer = {}
local hydrationTasksByPlayer = {}
local validationConnectionsByPlayer = {}
local cachedDataManager = nil
local dataManagerWarningPrinted = false

local function warnDataManagerUnavailable(reason)
	if dataManagerWarningPrinted then
		return
	end

	dataManagerWarningPrinted = true
	warn("[TitleService] DataManager unavailable; runtime titles will still hydrate, persistence skipped: " .. tostring(reason))
end

local function getDataManager()
	if cachedDataManager ~= nil then
		return cachedDataManager, nil
	end

	local dataFolder = ServerScriptService:FindFirstChild("Data")
	if not dataFolder then
		return nil, DATA_MANAGER_UNAVAILABLE_REASON
	end

	local dataManagerModule = dataFolder:FindFirstChild("DataManager")
	if not (dataManagerModule and dataManagerModule:IsA("ModuleScript")) then
		return nil, DATA_MANAGER_UNAVAILABLE_REASON
	end

	local requireOk, dataManagerOrError = pcall(require, dataManagerModule)
	if not requireOk or typeof(dataManagerOrError) ~= "table" then
		warnDataManagerUnavailable(dataManagerOrError)
		return nil, DATA_MANAGER_UNAVAILABLE_REASON
	end

	if dataManagerOrError._initialized ~= true and typeof(dataManagerOrError.init) == "function" then
		local initOk, initError = pcall(function()
			dataManagerOrError.init()
		end)
		if not initOk then
			warnDataManagerUnavailable(initError)
			return nil, DATA_MANAGER_UNAVAILABLE_REASON
		end
	end

	cachedDataManager = dataManagerOrError
	return cachedDataManager, nil
end

local function getOrCreateRemotesFolder()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	return remotesFolder
end

local function getOrCreateRemote(parent, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local EquipRemote = getOrCreateRemote(getOrCreateRemotesFolder(), EQUIP_REMOTE_NAME)

local function waitForDataReady(player, timeoutSeconds)
	local dataManager = getDataManager()
	if dataManager == nil then
		return false, DATA_MANAGER_UNAVAILABLE_REASON
	end

	local deadline = os.clock() + (timeoutSeconds or PERSIST_READY_TIMEOUT)

	while player.Parent == Players and os.clock() <= deadline do
		if dataManager:IsReady(player) then
			return true, nil
		end

		task.wait(0.1)
	end

	local ready = dataManager:IsReady(player)
	return ready, if ready then nil else "data_not_ready"
end

local function normalizeTitleId(titleId)
	if typeof(titleId) ~= "string" then
		return NONE_EQUIPPED
	end

	titleId = string.gsub(titleId, "^%s+", "")
	titleId = string.gsub(titleId, "%s+$", "")
	if titleId == "" then
		return NONE_EQUIPPED
	end

	return titleId
end

local function getPublicTesterTitleId()
	if typeof(AdminConfig) ~= "table" then
		return "Tester"
	end

	local titleId = normalizeTitleId(AdminConfig.PublicTesterTitleId)
	return titleId ~= NONE_EQUIPPED and titleId or "Tester"
end

local function isPublicTesterTitleEnabled()
	return typeof(AdminConfig) == "table" and AdminConfig.EnablePublicTesterTitle == true
end

local function isPublicTesterTitle(titleId)
	return normalizeTitleId(titleId) == getPublicTesterTitleId()
end

local function ensureTitlesFolder(player)
	local titlesFolder = player:FindFirstChild("Titles")
	if titlesFolder and not titlesFolder:IsA("Folder") then
		titlesFolder:Destroy()
		titlesFolder = nil
	end

	if not titlesFolder then
		titlesFolder = Instance.new("Folder")
		titlesFolder.Name = "Titles"
		titlesFolder.Parent = player
	end

	local unlockedFolder = titlesFolder:FindFirstChild("Unlocked")
	if unlockedFolder and not unlockedFolder:IsA("Folder") then
		unlockedFolder:Destroy()
		unlockedFolder = nil
	end

	if not unlockedFolder then
		unlockedFolder = Instance.new("Folder")
		unlockedFolder.Name = "Unlocked"
		unlockedFolder.Parent = titlesFolder
	end

	local runtimeUnlockedFolder = titlesFolder:FindFirstChild("RuntimeUnlocked")
	if runtimeUnlockedFolder and not runtimeUnlockedFolder:IsA("Folder") then
		runtimeUnlockedFolder:Destroy()
		runtimeUnlockedFolder = nil
	end

	if not runtimeUnlockedFolder then
		runtimeUnlockedFolder = Instance.new("Folder")
		runtimeUnlockedFolder.Name = "RuntimeUnlocked"
		runtimeUnlockedFolder.Parent = titlesFolder
	end

	local equippedValue = titlesFolder:FindFirstChild("Equipped")
	if equippedValue and not equippedValue:IsA("StringValue") then
		equippedValue:Destroy()
		equippedValue = nil
	end

	if not equippedValue then
		equippedValue = Instance.new("StringValue")
		equippedValue.Name = "Equipped"
		equippedValue.Value = NONE_EQUIPPED
		equippedValue.Parent = titlesFolder
	end

	return titlesFolder, unlockedFolder, equippedValue, runtimeUnlockedFolder
end

local function getRuntimeUnlockValue(player, titleId)
	local _, unlockedFolder = ensureTitlesFolder(player)
	local valueObject = unlockedFolder:FindFirstChild(titleId)
	if valueObject and not valueObject:IsA("BoolValue") then
		valueObject:Destroy()
		valueObject = nil
	end

	return unlockedFolder, valueObject
end

local function getRuntimeOnlyUnlockValue(player, titleId)
	local _, _, _, runtimeUnlockedFolder = ensureTitlesFolder(player)
	local valueObject = runtimeUnlockedFolder:FindFirstChild(titleId)
	if valueObject and not valueObject:IsA("BoolValue") then
		valueObject:Destroy()
		valueObject = nil
	end

	return runtimeUnlockedFolder, valueObject
end

local function getRuntimeEquippedValue(player)
	local _, _, equippedValue = ensureTitlesFolder(player)
	return equippedValue
end

local function setRuntimeTitleUnlocked(player, titleId, isUnlocked)
	local unlockedFolder, valueObject = getRuntimeUnlockValue(player, titleId)
	if not valueObject then
		valueObject = Instance.new("BoolValue")
		valueObject.Name = titleId
		valueObject.Value = isUnlocked == true
		valueObject.Parent = unlockedFolder
		return valueObject
	end

	valueObject.Value = isUnlocked == true
	return valueObject
end

local function setRuntimeOnlyTitleUnlocked(player, titleId, isUnlocked)
	local runtimeUnlockedFolder, valueObject = getRuntimeOnlyUnlockValue(player, titleId)
	if not valueObject then
		valueObject = Instance.new("BoolValue")
		valueObject.Name = titleId
		valueObject.Value = isUnlocked == true
		valueObject.Parent = runtimeUnlockedFolder
		return valueObject
	end

	valueObject.Value = isUnlocked == true
	return valueObject
end

local function syncPublicTesterTitleUnlock(player)
	local testerTitleId = getPublicTesterTitleId()
	if TitlesConfig.Get(testerTitleId) then
		setRuntimeOnlyTitleUnlocked(player, testerTitleId, isPublicTesterTitleEnabled())
	end
end

local function isRuntimeTitleUnlocked(player, titleId)
	local _, valueObject = getRuntimeUnlockValue(player, titleId)
	return valueObject ~= nil and valueObject.Value == true
end

local function isRuntimeOnlyTitleUnlocked(player, titleId)
	local _, valueObject = getRuntimeOnlyUnlockValue(player, titleId)
	return valueObject ~= nil and valueObject.Value == true
end

local function getRuntimeEquippedTitle(player)
	local equippedValue = getRuntimeEquippedValue(player)
	return normalizeTitleId(equippedValue and equippedValue.Value)
end

local function publishEquippedTitle(player, titleId)
	local normalizedTitleId = normalizeTitleId(titleId)
	local equippedValue = getRuntimeEquippedValue(player)
	if equippedValue.Value ~= normalizedTitleId then
		equippedValue.Value = normalizedTitleId
	end

	local titleDefinition = TitlesConfig.Get(normalizedTitleId)
	player:SetAttribute(EQUIPPED_TITLE_ATTRIBUTE, normalizedTitleId ~= NONE_EQUIPPED and normalizedTitleId or nil)
	player:SetAttribute(
		EQUIPPED_TITLE_DISPLAY_ATTRIBUTE,
		titleDefinition and tostring(titleDefinition.DisplayName or normalizedTitleId) or nil
	)

	return normalizedTitleId
end

local function disconnectValidationHooks(player)
	local connections = validationConnectionsByPlayer[player]
	if typeof(connections) ~= "table" then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	validationConnectionsByPlayer[player] = nil
end

local function persistTitleUnlock(player, titleId)
	local dataManager, unavailableReason = getDataManager()
	if dataManager == nil then
		return false, unavailableReason or DATA_MANAGER_UNAVAILABLE_REASON
	end

	local success, reason = dataManager:TrySetValue(player, "Titles.Unlocked." .. titleId, true)
	if success then
		return true, nil
	end

	return false, reason
end

local function persistEquippedTitle(player, titleId)
	local dataManager, unavailableReason = getDataManager()
	if dataManager == nil then
		return false, unavailableReason or DATA_MANAGER_UNAVAILABLE_REASON
	end

	local success, reason = dataManager:TrySetValue(player, "Titles.Equipped", normalizeTitleId(titleId))
	if success then
		return true, nil
	end

	return false, reason
end

local function flushPendingUnlocks(player)
	local pending = pendingUnlocksByPlayer[player]
	if typeof(pending) ~= "table" or next(pending) == nil then
		pendingUnlocksByPlayer[player] = nil
		return
	end

	if not waitForDataReady(player, PERSIST_READY_TIMEOUT) then
		return
	end

	for titleId in pairs(pending) do
		local success = persistTitleUnlock(player, titleId)
		if success then
			pending[titleId] = nil
		end
	end

	if next(pending) == nil then
		pendingUnlocksByPlayer[player] = nil
	end
end

local function queuePendingUnlock(player, titleId)
	local pending = pendingUnlocksByPlayer[player]
	if typeof(pending) ~= "table" then
		pending = {}
		pendingUnlocksByPlayer[player] = pending
	end

	pending[titleId] = true
	task.spawn(function()
		flushPendingUnlocks(player)
	end)
end

local function flushPendingEquippedTitle(player)
	local pendingTitleId = pendingEquippedByPlayer[player]
	if pendingTitleId == nil then
		return
	end

	if not waitForDataReady(player, PERSIST_READY_TIMEOUT) then
		return
	end

	local success = persistEquippedTitle(player, pendingTitleId)
	if success then
		pendingEquippedByPlayer[player] = nil
	end
end

local function queuePendingEquippedTitle(player, titleId)
	pendingEquippedByPlayer[player] = normalizeTitleId(titleId)
	task.spawn(function()
		flushPendingEquippedTitle(player)
	end)
end

local function getTitleDefinition(titleId)
	local normalizedTitleId = normalizeTitleId(titleId)
	if normalizedTitleId == NONE_EQUIPPED then
		return nil, "no_title"
	end

	local titleDefinition = TitlesConfig.Get(normalizedTitleId)
	if typeof(titleDefinition) ~= "table" then
		return nil, "unknown_title"
	end

	return titleDefinition, nil
end

local function ensurePersistentTitle(titleId)
	local titleDefinition, validationError = getTitleDefinition(titleId)
	if validationError ~= nil then
		return nil, validationError
	end

	if titleDefinition.UnlockType ~= "Persistent" then
		return nil, "non_persistent_title"
	end

	return titleDefinition, nil
end

local function isDynamicTitleUnlocked(player, titleDefinition, allowPending)
	local rankAttribute = titleDefinition and titleDefinition.RankAttribute
	if typeof(rankAttribute) ~= "string" or rankAttribute == "" then
		return false, "missing_rank_attribute"
	end

	local requiredRank = math.max(1, math.floor(tonumber(titleDefinition.RequiredRank) or 1))
	local currentRank = tonumber(player:GetAttribute(rankAttribute))
	if currentRank ~= nil and currentRank >= 1 then
		if currentRank <= requiredRank then
			return true, "dynamic_unlocked"
		end

		return false, "dynamic_rank_miss"
	end

	local boardReady = player:GetAttribute(rankAttribute .. "_Ready") == true
	if allowPending == true and not boardReady then
		return true, "dynamic_pending"
	end

	return false, boardReady and "dynamic_outside_board" or "dynamic_unresolved"
end

local function isTitleEquippable(player, titleId, allowPendingDynamic)
	local titleDefinition, validationError = getTitleDefinition(titleId)
	if validationError ~= nil then
		return false, validationError
	end

	if titleDefinition.UnlockType == "Persistent" then
		local publicTesterAllowed = isPublicTesterTitle(titleDefinition.Id) and isPublicTesterTitleEnabled()
		local persistentUnlocked = isRuntimeTitleUnlocked(player, titleDefinition.Id)
		local runtimeUnlocked = isRuntimeOnlyTitleUnlocked(player, titleDefinition.Id)

		if publicTesterAllowed then
			return true, "public_tester_title"
		end

		if persistentUnlocked or runtimeUnlocked then
			return true, "persistent_unlocked"
		end

		return false, "title_locked"
	end

	if titleDefinition.UnlockType == "DynamicRank" then
		return isDynamicTitleUnlocked(player, titleDefinition, allowPendingDynamic)
	end

	return false, "unsupported_unlock_type"
end

local function setEquippedTitleInternal(player, titleId, allowPendingDynamic)
	local normalizedTitleId = normalizeTitleId(titleId)

	if normalizedTitleId == NONE_EQUIPPED then
		publishEquippedTitle(player, NONE_EQUIPPED)
		local success, reason = persistEquippedTitle(player, NONE_EQUIPPED)
		if not success then
			queuePendingEquippedTitle(player, NONE_EQUIPPED)
			return true, reason or "queued_clear"
		end

		pendingEquippedByPlayer[player] = nil
		return true, "cleared"
	end

	local allowed, reason = isTitleEquippable(player, normalizedTitleId, allowPendingDynamic)
	if not allowed then
		return false, reason
	end

	publishEquippedTitle(player, normalizedTitleId)
	local success, persistReason = persistEquippedTitle(player, normalizedTitleId)
	if not success then
		queuePendingEquippedTitle(player, normalizedTitleId)
		return true, persistReason or "queued"
	end

	pendingEquippedByPlayer[player] = nil
	return true, reason or "equipped"
end

local function validateEquippedTitle(player)
	local equippedTitleId = getRuntimeEquippedTitle(player)
	if equippedTitleId == NONE_EQUIPPED then
		return true
	end

	local isValid = isTitleEquippable(player, equippedTitleId, true)
	if isValid then
		return true
	end

	setEquippedTitleInternal(player, NONE_EQUIPPED, false)
	return false
end

local function hookValidationSignals(player)
	disconnectValidationHooks(player)

	local connections = {}
	local watchedSignals = {}

	local function connectAttribute(attributeName)
		if watchedSignals[attributeName] == true then
			return
		end

		watchedSignals[attributeName] = true
		connections[#connections + 1] = player:GetAttributeChangedSignal(attributeName):Connect(function()
			validateEquippedTitle(player)
		end)
	end

	for _, titleDefinition in ipairs(TitlesConfig.GetAll()) do
		local rankAttribute = titleDefinition.RankAttribute
		if typeof(rankAttribute) == "string" and rankAttribute ~= "" then
			connectAttribute(rankAttribute)
			connectAttribute(rankAttribute .. "_Ready")
		end
	end

	validationConnectionsByPlayer[player] = connections
end

local function hydrateRuntimeTitles(player)
	if hydrationTasksByPlayer[player] then
		return
	end

	hydrationTasksByPlayer[player] = task.spawn(function()
		ensureTitlesFolder(player)
		publishEquippedTitle(player, NONE_EQUIPPED)
		syncPublicTesterTitleUnlock(player)
		hookValidationSignals(player)

		local dataReady = waitForDataReady(player, HYDRATE_READY_TIMEOUT)
		if not dataReady then
			hydrationTasksByPlayer[player] = nil
			return
		end

		local dataManager = getDataManager()
		if dataManager == nil then
			hydrationTasksByPlayer[player] = nil
			return
		end

		local persistedTitles = dataManager:TryGetValue(player, "Titles.Unlocked")
		if typeof(persistedTitles) == "table" then
			for titleId, unlocked in pairs(persistedTitles) do
				if unlocked == true and not isPublicTesterTitle(titleId) then
					setRuntimeTitleUnlocked(player, tostring(titleId), true)
				end
			end
		end
		syncPublicTesterTitleUnlock(player)

		local equippedFruit = dataManager:TryGetValue(player, "DevilFruit.Equipped")
		if typeof(equippedFruit) == "string" and equippedFruit ~= DevilFruitConfig.None then
			TitleService.UnlockTitle(player, "EnemyOfTheSea")
		end

		local persistedEquippedTitle = normalizeTitleId(dataManager:TryGetValue(player, "Titles.Equipped"))
		if persistedEquippedTitle ~= NONE_EQUIPPED then
			local equipped = setEquippedTitleInternal(player, persistedEquippedTitle, true)
			if not equipped then
				setEquippedTitleInternal(player, NONE_EQUIPPED, false)
			end
		end

		validateEquippedTitle(player)
		flushPendingUnlocks(player)
		flushPendingEquippedTitle(player)
		hydrationTasksByPlayer[player] = nil
	end)
end

local function cleanupPlayer(player)
	pendingUnlocksByPlayer[player] = nil
	pendingEquippedByPlayer[player] = nil
	hydrationTasksByPlayer[player] = nil
	disconnectValidationHooks(player)
end

function TitleService.Start()
	if started then
		return
	end

	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		hydrateRuntimeTitles(player)
	end

	Players.PlayerAdded:Connect(hydrateRuntimeTitles)
	Players.PlayerRemoving:Connect(cleanupPlayer)
	EquipRemote.OnServerEvent:Connect(function(player, titleId)
		if typeof(titleId) ~= "string" then
			return
		end

		if normalizeTitleId(titleId) == NONE_EQUIPPED then
			TitleService.UnequipTitle(player)
		else
			TitleService.EquipTitle(player, titleId)
		end
	end)
end

function TitleService.UnlockTitle(player, titleId)
	TitleService.Start()

	if not player or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local _, validationError = ensurePersistentTitle(titleId)
	if validationError ~= nil then
		return false, validationError
	end

	if isPublicTesterTitle(titleId) then
		if isPublicTesterTitleEnabled() then
			setRuntimeOnlyTitleUnlocked(player, titleId, true)
			return true, "public_runtime_unlocked"
		end

		return false, "public_tester_title_disabled"
	end

	if isRuntimeTitleUnlocked(player, titleId) then
		return true, "already_unlocked"
	end

	setRuntimeTitleUnlocked(player, titleId, true)

	local success, reason = persistTitleUnlock(player, titleId)
	if not success then
		queuePendingUnlock(player, titleId)
		return true, reason or "queued"
	end

	return true, "persisted"
end

function TitleService.EquipTitle(player, titleId)
	TitleService.Start()

	if not player or not player:IsA("Player") then
		return false, "invalid_player"
	end

	return setEquippedTitleInternal(player, titleId, false)
end

function TitleService.UnequipTitle(player)
	TitleService.Start()

	if not player or not player:IsA("Player") then
		return false, "invalid_player"
	end

	return setEquippedTitleInternal(player, NONE_EQUIPPED, false)
end

function TitleService.IsTitleUnlocked(player, titleId)
	local isUnlocked = isTitleEquippable(player, titleId, false)
	return isUnlocked == true
end

function TitleService.IsTitleOwned(player, titleId)
	local titleDefinition = TitlesConfig.Get(titleId)
	if typeof(titleDefinition) ~= "table" then
		return false
	end

	if titleDefinition.UnlockType == "Persistent" then
		if isPublicTesterTitle(titleId) and isPublicTesterTitleEnabled() then
			return true
		end

		return isRuntimeTitleUnlocked(player, titleId) or isRuntimeOnlyTitleUnlocked(player, titleId)
	end

	if titleDefinition.UnlockType == "DynamicRank" then
		return isDynamicTitleUnlocked(player, titleDefinition, false)
	end

	return false
end

function TitleService.GetEquippedTitle(player)
	return getRuntimeEquippedTitle(player)
end

task.defer(function()
	local ok, err = pcall(TitleService.Start)
	if not ok then
		warn("[TitleService] Deferred auto-start failed: " .. tostring(err))
	end
end)

return TitleService
