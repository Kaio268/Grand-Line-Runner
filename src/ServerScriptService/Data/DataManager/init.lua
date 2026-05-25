--// Main
local DataManager = {}
DataManager.__index = DataManager
local self = setmetatable({}, DataManager)

local RunService = game:GetService("RunService")

--// Other 
local keyAttribute = script:GetAttribute("Data_Key")
local Key: string
if typeof(keyAttribute) == "string" and keyAttribute ~= "" and keyAttribute ~= "DefaultKey_123" then
	Key = keyAttribute
elseif RunService:IsStudio() then
	warn("[DataManager]: Data_Key attribute is missing or default; Studio is using an isolated fallback key. Set Data_Key before publishing.")
	Key = "StudioMissingDataKey"
else
	error("[DataManager]: Data_Key attribute must be set to a non-default value outside Studio.")
end
if script:GetAttribute("Custom_Studio_Data") then
	Key = "S__"..Key..tostring(script:GetAttribute("Studio_Version"))
end

local ATTRIBUTE_STORE_KEY = "__Attributes"

local __Debug : boolean = script:GetAttribute("Debug")
local __Debugging : "Data" | "Profile" = "Data"

--// Requires
local ProfileStore = require(game.ServerScriptService.Framework.ProfileStore)
local GlobalStore = require(game.ServerScriptService.Framework.GlobalStore)
local Replica = require(game.ServerScriptService.Framework.ReplicaServer)
local GetTemplate = require(script.GetTemplate)
local ProfileMigrations = require(script.ProfileMigrations)
local MessageFunctions = require(script.MessageFunctions)
local ProductFunctions = require(script.ProductFunctions)
local Settings = require(script.Settings)
local Premades = require(script.Premades)
local EconomyConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local MonetizationConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Monetization"))
local PaidRandomItemPolicy = require(game.ServerScriptService.Modules.PaidRandomItemPolicy)
local RemoteGuard = require(game.ServerScriptService.Modules.RemoteGuard)
local ValidationChecks = require(game.ServerScriptService.Modules.ValidationChecks)
  
--// ProfileStore
local PlayerStore = ProfileStore.New(Key, GetTemplate)
local Profiles: {[Player]: typeof(PlayerStore:StartSessionAsync())} = {}
local Replicas: {[Player]: typeof(Replica)} = {}
local ActiveBoostRoutines = {}  
local PendingReplicaReadyConnections: {[Player]: any} = {}
local PendingHardResetByUserId: {[number]: boolean} = {}
local SuppressSessionEndKickByUserId: {[number]: boolean} = {}
local DataManagerInitialized = false
local HardResetStartingEvent = Instance.new("BindableEvent")
DataManager.HardResetStarting = HardResetStartingEvent.Event

--// GlobalStore
local GlobalDataTemplate = {Players = {}}
local globalDataOk, globalDataResult = pcall(function()
	return GlobalStore.New("__GlobalData", GlobalDataTemplate)
end)

local function cloneGlobalValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, childValue in pairs(value) do
		copy[key] = cloneGlobalValue(childValue)
	end
	return copy
end

local GlobalData = if globalDataOk then globalDataResult else (function()
	local memoryData = cloneGlobalValue(GlobalDataTemplate)
	warn("[DataManager]: GlobalStore unavailable; using in-memory global data for this server: ", globalDataResult)
	return {
		Get = function(_, key)
			return cloneGlobalValue(memoryData[key])
		end,
		Set = function(_, key, value)
			memoryData[key] = cloneGlobalValue(value)
			return true
		end,
	}
end)()

--// Services 
local Players = game:GetService("Players")
local MarketPlaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
--// Variables
local PURCHASE_ID_CACHE_SIZE = 100
local PASTEBIN = "https://pastebin.com/raw/JT4wrgrq"
local SCRIPT_VERSION = script:GetTags()[1]
local HARD_RESET_KICK_MESSAGE = "Your data was reset. Rejoin for a fresh start."
local HARD_RESET_FAILURE_KICK_MESSAGE = "Your data reset could not be completed cleanly. Rejoin to restore your session."
local HARD_RESET_PROGRESS_KICK_MESSAGE = "A data reset is still being applied to your account. Rejoin in a moment."
local HARD_RESET_SAVE_TIMEOUT = 30
local PLAYER_DATA_READY_ATTRIBUTE = "PlayerDataReady"
local PLAYER_DATA_READY_AT_ATTRIBUTE = "PlayerDataReadyAt"
local REPLICA_READY_TIMEOUT_SECONDS = 10
local DATA_READY_DEBUG = true
local CREW_LEGACY_DEPRECATION_AUDIT_PATH = "CrewMemberLegacyDeprecationAudit"
local MAX_LEGACY_DEPRECATION_RECENT_EVENTS = 20

--[[
	Primary message functions to DataManager:MessageAsync() function
]]

local PathAliasLookup = {}
local PrimaryCurrencyConfig = EconomyConfig.Currency and EconomyConfig.Currency.Primary or {}

for canonicalPath, aliases in pairs(EconomyConfig.PathAliases or {}) do
	for _, alias in ipairs(aliases) do
		PathAliasLookup[alias] = canonicalPath
	end
end

local function NormalizeDataPath(path: string): string
	if typeof(path) ~= "string" then
		return path
	end

	return PathAliasLookup[path] or path
end

local function SyncCurrencyCompatibilityMirror(player: Player, pathTable: {string}, value: any)
	local profile = Profiles[player]
	if profile == nil or typeof(profile.Data) ~= "table" then
		return
	end

	local legacy = profile.Data.CurrencyLegacy
	if typeof(legacy) ~= "table" then
		legacy = {}
		profile.Data.CurrencyLegacy = legacy
	end

	if pathTable[1] == "leaderstats" and pathTable[2] == PrimaryCurrencyConfig.Key then
		legacy.CurrentBeli = value
		-- Mirrored legacy names are kept out of leaderstats so players only see Beli.
		legacy.Doubloons = value
		legacy.Money = value
		legacy.Moeny = value
	elseif pathTable[1] == "TotalStats" and pathTable[2] == PrimaryCurrencyConfig.TotalKey then
		legacy.CurrentTotalBeli = value
		legacy.TotalDoubloons = value
		legacy.TotalMoney = value
	end
end

local function DeepCopyTable(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, childValue in pairs(value) do
		copy[key] = DeepCopyTable(childValue)
	end

	return copy
end

local function getCrewShadowFlags()
	local ok, flags = pcall(function()
		local CrewStorage = require(game.ServerScriptService.Modules.CrewStorage)
		return CrewStorage.GetShadowFlags()
	end)
	if ok == true and typeof(flags) == "table" then
		return flags
	end
	return {
		CrewMemberLegacyUsageTelemetryEnabled = true,
		CrewMemberLegacyWriteFreezeEnabled = false,
	}
end

local function getPathRootAndSegments(path: string)
	local normalizedPath = NormalizeDataPath(path)
	local segments = if typeof(normalizedPath) == "string" then normalizedPath:split(".") else {}
	if segments[1] == "Data" then
		table.remove(segments, 1)
	end
	return segments[1], segments
end

local function classifyLegacyPath(path: string)
	local root, segments = getPathRootAndSegments(path)
	local leaf = segments[#segments]
	if root == "Inventory" and #segments >= 3 then
		local storageName = tostring(segments[2] or "")
		if storageName ~= "Feed" and storageName ~= "DevilFruits" and storageName ~= "Potions" then
			if leaf == "Quantity" then
				return "Inventory.*.Quantity", "legacy_inventory_quantity"
			end
			if leaf == "Level" or leaf == "CurrentXP" then
				return "Inventory.*." .. tostring(leaf), "legacy_progression_mirror"
			end
		end
	end
	return nil, nil
end

local APPROVED_LEGACY_WRITE_SOURCES = {
	CrewInstanceService = true,
	CrewQuickSlotService = true,
	CrewStandIncomeAuthority = true,
	CrewFoodProgression = true,
	CrewIncomeRuntime = true,
	["CrewIncome.ClaimRuntime"] = true,
	["CrewIncome.StandState"] = true,
	CrewMemberShadowWriter = true,
	CrewMigrationPlanner = true,
	IndexCollectionService = true,
	ShipResetService = true,
}

local WRAPPER_LEGACY_USAGE_SOURCES = {
	FirstTimeTutorialService = true,
	DevilFruitDevCommands = true,
	Index = true,
}

local function getLegacyWriteClassification(stack)
	local safeStack = tostring(stack or "")
	for sourceName in pairs(APPROVED_LEGACY_WRITE_SOURCES) do
		if string.find(safeStack, sourceName, 1, true) ~= nil then
			return "approved_mirror_write", sourceName
		end
	end
	for sourceName in pairs(WRAPPER_LEGACY_USAGE_SOURCES) do
		if string.find(safeStack, sourceName, 1, true) ~= nil then
			return "wrapper_write", sourceName
		end
	end
	return "unexpected_direct_write", "unknown"
end

local function getLegacyDeprecationAudit(profile)
	if typeof(profile.Data[CREW_LEGACY_DEPRECATION_AUDIT_PATH]) ~= "table" then
		profile.Data[CREW_LEGACY_DEPRECATION_AUDIT_PATH] = {}
	end
	return profile.Data[CREW_LEGACY_DEPRECATION_AUDIT_PATH]
end

local function incrementAuditCounter(audit, key)
	audit[key] = math.max(0, math.floor(tonumber(audit[key]) or 0)) + 1
end

local function recordLegacyDeprecationEvent(_player, profile, event)
	if typeof(profile) ~= "table" or typeof(profile.Data) ~= "table" or typeof(event) ~= "table" then
		return nil
	end

	local audit = getLegacyDeprecationAudit(profile)
	incrementAuditCounter(audit, "TotalEventCount")
	if event.Kind == "legacy_write" then
		incrementAuditCounter(audit, "DirectLegacyWriteCount")
		if event.Classification == "approved_mirror_write" then
			incrementAuditCounter(audit, "ApprovedMirrorWriteCount")
		elseif event.Classification == "wrapper_write" then
			incrementAuditCounter(audit, "WrapperUsageCount")
		elseif event.Classification == "unexpected_direct_write" then
			incrementAuditCounter(audit, "UnexpectedDirectWriteCount")
			audit.LastOffendingSource = event.Source
			audit.LastOffendingPath = event.Path
			audit.LastOffendingRoot = event.Root
		end
	elseif event.Kind == "legacy_wrapper_usage" then
		incrementAuditCounter(audit, "WrapperUsageCount")
	elseif event.Kind == "legacy_fallback" then
		incrementAuditCounter(audit, "FallbackCount")
	end

	audit.LastEvent = event
	audit.UpdatedAt = os.time()
	local recent = if typeof(audit.RecentEvents) == "table" then audit.RecentEvents else {}
	recent[#recent + 1] = event
	while #recent > MAX_LEGACY_DEPRECATION_RECENT_EVENTS do
		table.remove(recent, 1)
	end
	audit.RecentEvents = recent
	return audit
end

local function inspectLegacyWrite(player, profile, path: string, operation: string)
	local root, category = classifyLegacyPath(path)
	if root == nil then
		return true, nil
	end

	local flags = getCrewShadowFlags()
	if flags.CrewMemberLegacyUsageTelemetryEnabled ~= true and flags.CrewMemberLegacyWriteFreezeEnabled ~= true then
		return true, nil
	end

	local stack = debug.traceback("", 3)
	local classification, source = getLegacyWriteClassification(stack)
	local event = {
		Kind = "legacy_write",
		Operation = tostring(operation or ""),
		Path = tostring(path or ""),
		Root = root,
		Category = category,
		Classification = classification,
		Source = source,
		Player = player and player.Name or "",
		UserId = player and player.UserId or 0,
		RecordedAt = os.time(),
		Stack = tostring(stack):sub(1, 1600),
		FailClosed = flags.CrewMemberLegacyWriteFreezeEnabled == true and classification == "unexpected_direct_write",
	}
	recordLegacyDeprecationEvent(player, profile, event)
	if event.FailClosed == true then
		warn(string.format(
			"[CrewLegacyDeprecation] blocked unexpected legacy write player=%s path=%s operation=%s root=%s source=%s",
			player and player.Name or "unknown",
			tostring(path),
			tostring(operation),
			tostring(root),
			tostring(source)
		))
		return false, "legacy_write_frozen"
	end

	return true, nil
end

local function CreateProfileFromTemplate()
	return DeepCopyTable(GetTemplate)
end

local function dataResetLog(...)
	print("[DATA][RESET]", ...)
end

local function dataResetSuccess(...)
	print("[DATA][RESET][SUCCESS]", ...)
end

local function dataResetError(...)
	warn("[DATA][RESET][ERROR]", ...)
end

local function dataReadyLog(...)
	if DATA_READY_DEBUG then
		print("[DATA][READY]", ...)
	end
end

local function GetPathTable(path: string): {string}
	local normalizedPath = NormalizeDataPath(path)
	local pathTable = normalizedPath:split(".")

	if pathTable[1] == "Data" then
		table.remove(pathTable, 1)
	end

	return pathTable
end

local function ResolveDataPath(profile, path: string, createMissing: boolean?, defaultLeafValue: any?)
	local pathTable = GetPathTable(path)
	if #pathTable == 0 then
		return nil, nil, pathTable, nil, "[DataManager]: Empty data path!"
	end

	local pointer = profile.Data
	for index = 1, #pathTable - 1 do
		local key = pathTable[index]
		local nextPointer = pointer[key]

		if nextPointer == nil then
			if not createMissing then
				return nil, nil, pathTable, nil, nil
			end

			nextPointer = {}
			pointer[key] = nextPointer
		elseif typeof(nextPointer) ~= "table" then
			return nil, nil, pathTable, nil, string.format(
				"[DataManager]: Can't traverse path '%s' because '%s' is %s, not table",
				path,
				tostring(key),
				typeof(nextPointer)
			)
		end

		pointer = nextPointer
	end

	local leafKey = pathTable[#pathTable]
	local currentValue = pointer[leafKey]
	if currentValue == nil and createMissing then
		pointer[leafKey] = defaultLeafValue
		currentValue = pointer[leafKey]
	end

	return pointer, leafKey, pathTable, currentValue, nil
end

local function GetRootDataKey(pathTable: {string}): string?
	return pathTable[1]
end

local SyncPathToInstances

local function SyncDataMutation(player: Player, replica, pathTable: {string}, value: any)
	SyncCurrencyCompatibilityMirror(player, pathTable, value)
	replica:Set(pathTable, value)

	if GetRootDataKey(pathTable) == "leaderstats" and not Settings.Experimental.CreateFolders then
		DataManager:Leaderstats(player)
	elseif Settings.Experimental.CreateFolders then
		SyncPathToInstances(player, pathTable, value)
	else
		DataManager:UpdateData(player)
	end

	Debug(player)
end


local function SanitizeAttributeValue(raw)
	local t = typeof(raw)
	if t == "table" then
		-- tabela ➜ serializujemy do JSON (string)
		return game:GetService("HttpService"):JSONEncode(raw), true
	elseif t == "Instance" then
		-- instancji nie zapisujemy jako atrybut
		return nil, false
	else
		-- string, number, boolean, Enum, Color3, …
		return raw, true
	end
end

local function GetInstanceFromPath(player: Player, path: string): Instance?
	path = NormalizeDataPath(path)
	local obj: Instance = player
	for _, part in ipairs(path:split(".")) do
		obj = obj:FindFirstChild(part)
		if not obj then return nil end
	end
	return obj
end


local MessagesFunctions = {
	["ResetData"] = function(player, profile, ...)
		local profile : typeof(Profiles[player]) = self:GetProfile(player)
		local replica: typeof(Replicas[player]) = self:GetReplica(player)
		if profile ~= nil and replica ~= nil then
			local freshData = CreateProfileFromTemplate()
			profile.Data = freshData
			replica.Data = freshData

			if Settings.Experimental.CreateFolders then
				self:UpdateData(player)
			else
				self:Leaderstats(player)
			end


			Debug(player)

			player:Kick("Your data got reseted, rejoin please.")
		end
	end,

	["BackupedJoined"] = function(player : Player, profile, ...)
		warn(`[DataManager]: Player {player.Name} joined with backuped data.`)
	end,
}

--[[
	Get access to player profile variables
	[player]: which player you want to get profile from
]]
function DataManager:GetProfile(player: Player) : typeof(PlayerStore:StartSessionAsync())?
	local PlayerProfile = Profiles[player]

	while PlayerProfile == nil do
		PlayerProfile = Profiles[player]
		if PlayerProfile then break end
		task.wait()
	end

	if PlayerProfile ~= nil then
		return PlayerProfile
	else
		warn(`[DataManager]: Couldn't get {player.Name} profile`)
		return
	end 
end

--[[
	Get access to player replica variables (need some knowledge)
	[player]: which player you want to get replica from
]]
function DataManager:GetReplica(player: Player) : typeof(Replica)?
	local PlayerReplica = Replicas[player]

	while PlayerReplica == nil do
		PlayerReplica = Replicas[player]
		if PlayerReplica then break end
		task.wait()
	end

	if PlayerReplica ~= nil then
		return PlayerReplica
	else
		warn(`[DataManager]: Couldn't get {player.Name} replica`)
		return
	end
end

--[[
	Get access to player data variables
	[player]: which player you want to get data from
]]
function DataManager:GetData(player : Player) : typeof(PlayerStore:StartSessionAsync().Data)?
	local profile = DataManager:GetProfile(player)
	return profile.Data
end

function DataManager:TryGetProfile(player: Player)
	return Profiles[player]
end

function DataManager:TryGetReplica(player: Player)
	return Replicas[player]
end

function DataManager:RecordLegacyDeprecationUsage(player: Player, kind: string, details: {[string]: any}?)
	local profile = self:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return nil, "no_profile"
	end

	local event = DeepCopyTable(details or {})
	event.Kind = tostring(kind or "legacy_wrapper_usage")
	event.Player = player and player.Name or ""
	event.UserId = player and player.UserId or 0
	event.RecordedAt = os.time()
	return recordLegacyDeprecationEvent(player, profile, event), nil
end

local function ReadValueFromProfile(profile, path: string)
	local _, _, _, value = ResolveDataPath(profile, path, false)
	return value
end

local function GetReadyProfileReplica(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil, "invalid_player"
	end

	if PendingHardResetByUserId[player.UserId] == true then
		return nil, nil, "hard_reset_pending"
	end

	local profile = Profiles[player]
	local replica = Replicas[player]
	if profile == nil or replica == nil then
		return nil, nil, "not_ready"
	end

	return profile, replica, nil
end

local function SetValueWithProfileReplica(player: Player, profile, replica, path: string, newValue: any)
	local legacyWriteAllowed, legacyWriteReason = inspectLegacyWrite(player, profile, path, "SetValue")
	if legacyWriteAllowed ~= true then
		return false, legacyWriteReason
	end

	local defaultValue = if newValue == nil then true else DeepCopyTable(newValue)
	local parent, leafKey, pathTable, currentValue, err = ResolveDataPath(profile, path, true, defaultValue)

	if err then
		warn(err)
		return false, "invalid_path"
	end

	if currentValue == nil then
		currentValue = parent[leafKey]
		SyncDataMutation(player, replica, pathTable, currentValue)
		return true, nil
	end

	local valueToStore = newValue
	if valueToStore ~= nil then
		if typeof(currentValue) ~= typeof(valueToStore) then
			warn(`[DataManager]: Given value ({valueToStore} : {typeof(valueToStore)}) must be the same type as (Data.{path} : {typeof(currentValue)})!`)
			return false, "type_mismatch"
		end

		valueToStore = DeepCopyTable(valueToStore)
	else
		if typeof(currentValue) ~= "boolean" then
			warn(`[DataManager]: Can't toggle non-boolean value at Data.{path}!`)
			return false, "invalid_toggle"
		end

		valueToStore = not currentValue
	end

	parent[leafKey] = valueToStore
	SyncDataMutation(player, replica, pathTable, valueToStore)
	return true, nil
end

local function AddValueWithProfileReplica(player: Player, profile, replica, path: string, addValue: any)
	local legacyWriteAllowed, legacyWriteReason = inspectLegacyWrite(player, profile, path, "AddValue")
	if legacyWriteAllowed ~= true then
		return false, legacyWriteReason
	end

	local defaultValue = if typeof(addValue) == "number" then 0 else {}
	local parent, leafKey, pathTable, currentValue, err = ResolveDataPath(profile, path, true, defaultValue)

	if err then
		warn(err)
		return false, "invalid_path"
	end

	if typeof(addValue) == "table" and typeof(currentValue) == "table" then
		local didChange = false
		for k, v in pairs(addValue) do
			if currentValue[k] ~= nil then
				warn("[DataManager]: value names are repeating!")
			else
				currentValue[k] = DeepCopyTable(v)
				didChange = true
			end
		end

		if didChange then
			SyncDataMutation(player, replica, pathTable, currentValue)
		end

		return true, nil
	end

	if typeof(currentValue) == "number" and typeof(addValue) == "number" then
		local final = currentValue + addValue
		parent[leafKey] = final
		SyncDataMutation(player, replica, pathTable, final)
		return true, nil
	end

	warn("[DataManager]: You can add only numbers!")
	return false, "invalid_add"
end

function DataManager:IsReady(player: Player): boolean
	local profile, replica = GetReadyProfileReplica(player)
	return profile ~= nil and replica ~= nil
end

function DataManager:WaitUntilReady(player: Player, timeoutSeconds: number?): boolean
	if self:IsReady(player) then
		return true
	end

	local timeout = tonumber(timeoutSeconds) or 30
	local deadline = os.clock() + timeout
	while player.Parent == Players and os.clock() < deadline do
		if self:IsReady(player) then
			return true
		end
		task.wait(0.1)
	end

	return player.Parent == Players and self:IsReady(player)
end

function DataManager:TryGetValue(player: Player, path: string)
	local profile, _, reason = GetReadyProfileReplica(player)
	if profile == nil then
		return nil, reason
	end

	return ReadValueFromProfile(profile, path), nil
end

function DataManager:TrySetValue(player: Player, path: string, newValue)
	local profile, replica, readyReason = GetReadyProfileReplica(player)
	if profile == nil or replica == nil then
		return false, readyReason
	end

	return SetValueWithProfileReplica(player, profile, replica, path, newValue)
end

function DataManager:TryAddValue(player: Player, path: string, addValue)
	local profile, replica, readyReason = GetReadyProfileReplica(player)
	if profile == nil or replica == nil then
		return false, readyReason
	end

	return AddValueWithProfileReplica(player, profile, replica, path, addValue)
end

--[[
	Function used to shorten code (isn't usable from the outside)
]]
function GetPointer(path : string, profile : typeof(PlayerStore:StartSessionAsync())) : ({any?}?, {any?}?)
	local _, _, pathTable, currentValue = ResolveDataPath(profile, path, false)
	return currentValue, pathTable
end

--[[
	Get value from a path
	[player]: player you want to get value from
	[path]: path to the value (e.g. "leaderstats.Beli")
]]
function DataManager:GetValue(player : Player, path: string) : (number | string | boolean)?
	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
		local pointer = GetPointer(path, profile)
		return pointer
	else
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return
	end
end



--[[
	Sets variable value
	[player]: which player you want to change the date
	[path]: path to variable (e.g. leaderstats.Beli)
	[newValue]: to which value it should be set 
]]
function DataManager:SetValue(player: Player, path: string, newValue : (string | number | boolean | {any?})?)
	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
		local legacyWriteAllowed, legacyWriteReason = inspectLegacyWrite(player, profile, path, "SetValue")
		if legacyWriteAllowed ~= true then
			return false, legacyWriteReason
		end

		local defaultValue = if newValue == nil then true else DeepCopyTable(newValue)
		local parent, leafKey, pathTable, currentValue, err = ResolveDataPath(profile, path, true, defaultValue)

		if err then
			warn(err)
			return false, "invalid_path"
		end

		if currentValue == nil then
			currentValue = parent[leafKey]
			SyncDataMutation(player, replica, pathTable, currentValue)
			return true
		end

		local valueToStore = newValue
		if valueToStore ~= nil then
			if typeof(currentValue) ~= typeof(valueToStore) then
				warn(`[DataManager]: Given value ({valueToStore} : {typeof(valueToStore)}) must be the same type as (Data.{path} : {typeof(currentValue)})!`)
				return false, "type_mismatch"
			end

			valueToStore = DeepCopyTable(valueToStore)
		else
			if typeof(currentValue) ~= "boolean" then
				warn(`[DataManager]: Can't toggle non-boolean value at Data.{path}!`)
				return false, "invalid_toggle"
			end

			valueToStore = not currentValue
		end

		parent[leafKey] = valueToStore
		SyncDataMutation(player, replica, pathTable, valueToStore)
		return true
	else
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return false, "missing_state"
	end
end


function DataManager:AddAttribute(player: Player, path: string, attributes: { [string]: any })
	assert(typeof(attributes) == "table",
		"[DataManager]: trzeci argument AddAttribute musi być tabelą")

	local profile = self:GetProfile(player)
	local replica = self:GetReplica(player)
	if not (profile and replica) then
		warn("[DataManager]: brak profilu lub repliki – przerwano AddAttribute")
		return
	end

	-- 1️⃣  Sekcja w profilu (trzymamy oryginalne wartości)
	profile.Data[ATTRIBUTE_STORE_KEY] = profile.Data[ATTRIBUTE_STORE_KEY] or {}
	local store = profile.Data[ATTRIBUTE_STORE_KEY]
	store[path] = store[path] or {}

	-- 2️⃣  Instancja w drzewie gracza – jeżeli istnieje
	local inst = GetInstanceFromPath(player, path)

	for name, value in pairs(attributes) do
		-- zapis do profilu
		store[path][name] = value

		-- sanitizacja i ewentualny zapis do instancji
		if inst then
			local sanitized, ok = SanitizeAttributeValue(value)
			if ok then
				inst:SetAttribute(name, sanitized)
			else
				warn(`[DataManager]: Attribute "{name}" pominięty – nieobsługiwany typ`)
			end
		end
	end

	-- 3️⃣  Zaktualizuj replikę (wystarczy jeden set całego store)
	replica:Set({ ATTRIBUTE_STORE_KEY }, store)

	Debug(player)
end


--[[
	Adds variable value
	[player]: which player you want to change the date
	[path]: path to variable (e.g. leaderstats.Beli)
	[addValue]: to which value it should be set 
]]
function DataManager:AddValue(player, path, addValue)
	local profile = self:GetProfile(player)
	local replica = self:GetReplica(player)
	if not (profile and replica) then
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return false, "missing_state"
	end

	local legacyWriteAllowed, legacyWriteReason = inspectLegacyWrite(player, profile, path, "AddValue")
	if legacyWriteAllowed ~= true then
		return false, legacyWriteReason
	end

	local defaultValue = if typeof(addValue) == "number" then 0 else {}
	local parent, leafKey, pathTable, currentValue, err = ResolveDataPath(profile, path, true, defaultValue)

	-- ⬇️ nowość: zainicjuj brakującą ścieżkę
	if err then
		warn(err)
		return false, "invalid_path"
	end

	if typeof(addValue) == "table" and typeof(currentValue) == "table" then
		local didChange = false
		for k, v in pairs(addValue) do
			if currentValue[k] ~= nil then
				warn("[DataManager]: value names are repeating!")
			else
				currentValue[k] = DeepCopyTable(v)
				didChange = true
			end
		end

		if didChange then
			SyncDataMutation(player, replica, pathTable, currentValue)
		end

		return true
	end

	if typeof(currentValue) == "number" and typeof(addValue) == "number" then
		local final = currentValue + addValue
		-- (nie ma sensu robić `pointer = pointer + final`; wystarczy Set do repliki)
		parent[leafKey] = final
		SyncDataMutation(player, replica, pathTable, final)
		return true
	end

	warn("[DataManager]: You can add only numbers!")
	return false, "invalid_add"
end


--[[
	Substracts variable value
	[player]: which player you want to change the date
	[path]: path to variable (e.g. leaderstats.Beli)
	[subValue]: to which value it should be set 
]]
function DataManager:SubValue(player : Player, path : string, subValue : (number | {any?}))
	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
		local legacyWriteAllowed, legacyWriteReason = inspectLegacyWrite(player, profile, path, "SubValue")
		if legacyWriteAllowed ~= true then
			return false, legacyWriteReason
		end

		local parent, leafKey, pathTable, currentValue, err = ResolveDataPath(profile, path, false)
		if err then
			warn(err)
			return false, "invalid_path"
		end

		if typeof(subValue) == "table" and typeof(currentValue) == "table" then
			local didChange = false
			for Index, Value in pairs(subValue) do
				if currentValue[Value] == nil then
					warn("[DataManager]: Couldn't find value!")
					continue
				end

				currentValue[Value] = nil
				didChange = true
			end

			if didChange then
				SyncDataMutation(player, replica, pathTable, currentValue)
			end

			return true
		else
			if typeof(currentValue) == typeof(subValue) and typeof(currentValue) == "number" then
				local targetNumber = currentValue - subValue
				parent[leafKey] = targetNumber
				SyncDataMutation(player, replica, pathTable, targetNumber)
				return true
			else
				warn("[DataManager]: You can substract only numbers!")
				return false, "invalid_subtract"
			end
		end
	else
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return false, "missing_state"
	end
end

function DataManager:Clear(player : Player, path : string)
	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
		local legacyWriteAllowed, legacyWriteReason = inspectLegacyWrite(player, profile, path, "Clear")
		if legacyWriteAllowed ~= true then
			return false, legacyWriteReason
		end

		local parent, leafKey, pathTable, currentValue, err = ResolveDataPath(profile, path, false)
		if err then
			warn(err)
			return false, "invalid_path"
		end

		if typeof(currentValue) == "table" then
			parent[leafKey] = {}
			SyncDataMutation(player, replica, pathTable, parent[leafKey])
		elseif typeof(currentValue) ~= "table" then
			warn("[DataManager]: You can clear only tables (folders)!")
			return false, "invalid_clear"
		end

		return true
	else
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return false, "missing_state"
	end
end

--[[
	Reset player data
	[userId]: player user id
]]
function DataManager:ResetData(userId : number) : boolean
	return DataManager:MessageAsync(userId, {Key = "ResetData"})
end

local function getProfileKeyForUserId(userId: number): string
	return `Player_{userId}`
end

local function waitForFinalProfileSave(profile, timeoutSeconds: number): (boolean, string?)
	if profile == nil then
		return true, nil
	end

	local saveCompleted = false
	local saveConnection = profile.OnAfterSave:Connect(function()
		saveCompleted = true
	end)

	profile:EndSession()

	local deadline = os.clock() + math.max(1, timeoutSeconds)
	while saveCompleted ~= true and os.clock() < deadline do
		task.wait(0.1)
	end

	saveConnection:Disconnect()

	if saveCompleted == true then
		return true, nil
	end

	return false, "save_timeout"
end

local function acquireResetControlProfile(profileKey: string, userId: number)
	local profile = PlayerStore:StartSessionAsync(profileKey, {
		Steal = true,
		Cancel = function()
			return ProfileStore.IsClosing == true or PendingHardResetByUserId[userId] ~= true
		end,
	})

	if profile == nil then
		return nil, "control_session_failed"
	end

	return profile, nil
end

function DataManager:IsHardResetPending(userId: number): boolean
	return PendingHardResetByUserId[userId] == true
end

function DataManager:HardResetData(userId: number, kickMessage: string?): (boolean, string?)
	if typeof(userId) ~= "number" or userId % 1 ~= 0 or userId <= 0 then
		dataResetError("Rejected hard reset with invalid userId", tostring(userId))
		return false, "invalid_user_id"
	end

	local profileKey = getProfileKeyForUserId(userId)
	local finalKickMessage = tostring(kickMessage or HARD_RESET_KICK_MESSAGE)
	local targetPlayer = Players:GetPlayerByUserId(userId)

	if PendingHardResetByUserId[userId] == true then
		dataResetError("Hard reset already in progress", "userId", userId, "profileKey", profileKey)
		return false, "reset_in_progress"
	end

	PendingHardResetByUserId[userId] = true
	if targetPlayer ~= nil then
		HardResetStartingEvent:Fire(targetPlayer, userId, profileKey)
	end
	dataResetLog("begin", "userId", userId, "profileKey", profileKey, "online", targetPlayer ~= nil)

	local function finish(success: boolean, reason: string?)
		PendingHardResetByUserId[userId] = nil
		SuppressSessionEndKickByUserId[userId] = nil

		if success then
			dataResetSuccess("wipe_complete", "userId", userId, "profileKey", profileKey, "online", targetPlayer ~= nil)
			return true, nil
		end

		dataResetError("wipe_failed", "userId", userId, "profileKey", profileKey, "reason", tostring(reason))
		return false, reason
	end

	if targetPlayer ~= nil then
		SuppressSessionEndKickByUserId[userId] = true

		local profile = self:TryGetProfile(targetPlayer)
		if profile ~= nil then
			local saved, saveReason = waitForFinalProfileSave(profile, HARD_RESET_SAVE_TIMEOUT)
			if not saved then
				if targetPlayer.Parent == Players then
					targetPlayer:Kick(HARD_RESET_FAILURE_KICK_MESSAGE)
				end
				return finish(false, saveReason)
			end
		elseif targetPlayer.Parent == Players then
			targetPlayer:Kick(finalKickMessage)
		end

		Profiles[targetPlayer] = nil
		ActiveBoostRoutines[targetPlayer] = nil
		ReplicaPlayerRemoving(targetPlayer)

		if profile == nil then
			local controlProfile, controlReason = acquireResetControlProfile(profileKey, userId)
			if controlProfile == nil then
				return finish(false, controlReason)
			end

			local saved, saveReason = waitForFinalProfileSave(controlProfile, HARD_RESET_SAVE_TIMEOUT)
			if not saved then
				return finish(false, saveReason)
			end
		end
	else
		local controlProfile, controlReason = acquireResetControlProfile(profileKey, userId)
		if controlProfile == nil then
			return finish(false, controlReason)
		end

		local saved, saveReason = waitForFinalProfileSave(controlProfile, HARD_RESET_SAVE_TIMEOUT)
		if not saved then
			return finish(false, saveReason)
		end
	end

	local removed = PlayerStore:RemoveAsync(profileKey)
	if removed ~= true then
		if targetPlayer and targetPlayer.Parent == Players then
			targetPlayer:Kick(HARD_RESET_FAILURE_KICK_MESSAGE)
		end
		return finish(false, "remove_failed")
	end

	if targetPlayer and targetPlayer.Parent == Players then
		targetPlayer:Kick(finalKickMessage)
	end

	return finish(true, nil)
end

--[[
	Update or create player leaderstats
	[player]: player you want to create/update leaderstats
]]
local SyncLeaderstatsFolder

function DataManager:Leaderstats(player : Player)
	local playerProfile = DataManager:GetProfile(player)

	if playerProfile == nil then
		return
	end

	if playerProfile.Data and playerProfile.Data.leaderstats then
		SyncLeaderstatsFolder(player, playerProfile.Data.leaderstats)
	end
end

function ConvertType(TypeOf)
	if TypeOf == "string" then
		return "StringValue"
	elseif TypeOf == "number" then
		return "NumberValue"
	elseif TypeOf == "boolean" then
		return "BoolValue"
	elseif TypeOf == "table" then
		return "Folder"
	end

	return nil
end

local function appendLeaderstatName(order: {string}, seen: {[string]: boolean}, statName: any)
	if typeof(statName) ~= "string" or statName == "" or seen[statName] then
		return
	end

	seen[statName] = true
	order[#order + 1] = statName
end

local function GetLeaderstatDisplayOrder(leaderstatsData: {[string]: any}?): {string}
	local order = {}
	local seen = {}
	local configuredOrder = EconomyConfig.Leaderstats and EconomyConfig.Leaderstats.DisplayOrder

	if typeof(configuredOrder) == "table" then
		for _, statName in ipairs(configuredOrder) do
			appendLeaderstatName(order, seen, statName)
		end
	end

	appendLeaderstatName(order, seen, PrimaryCurrencyConfig.Key)

	if typeof(leaderstatsData) == "table" then
		local extraNames = {}
		for statName, value in pairs(leaderstatsData) do
			if typeof(statName) == "string" and seen[statName] ~= true and typeof(value) ~= "table" then
				extraNames[#extraNames + 1] = statName
			end
		end

		table.sort(extraNames)
		for _, statName in ipairs(extraNames) do
			appendLeaderstatName(order, seen, statName)
		end
	end

	return order
end

local function ReorderLeaderstatsChildren(folder: Folder, orderedChildren: {Instance})
	local currentChildren = folder:GetChildren()
	if #currentChildren == #orderedChildren then
		local alreadyOrdered = true
		for index, child in ipairs(orderedChildren) do
			if currentChildren[index] ~= child then
				alreadyOrdered = false
				break
			end
		end

		if alreadyOrdered then
			return
		end
	end

	for _, child in ipairs(orderedChildren) do
		child.Parent = nil
	end

	for _, child in ipairs(orderedChildren) do
		child.Parent = folder
	end
end

SyncLeaderstatsFolder = function(player: Player, leaderstatsData: {[string]: any}?)
	if typeof(leaderstatsData) ~= "table" then
		return
	end

	local folder = player:FindFirstChild("leaderstats")
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end

	local expectedObjects = {}
	local orderedChildren = {}

	for _, statName in ipairs(GetLeaderstatDisplayOrder(leaderstatsData)) do
		local value = leaderstatsData[statName]
		local className = ConvertType(typeof(value))
		if value ~= nil and typeof(value) ~= "table" and className ~= nil then
			local valueObject = folder:FindFirstChild(statName)
			if valueObject and valueObject.ClassName ~= className then
				valueObject:Destroy()
				valueObject = nil
			end

			if not valueObject then
				valueObject = Instance.new(className)
				valueObject.Name = statName
				valueObject.Parent = folder
			end

			valueObject.Value = value
			expectedObjects[valueObject] = true
			orderedChildren[#orderedChildren + 1] = valueObject
		end
	end

	for _, child in ipairs(folder:GetChildren()) do
		if expectedObjects[child] ~= true then
			child:Destroy()
		end
	end

	ReorderLeaderstatsChildren(folder, orderedChildren)
end

local function RecursiveUpdate(folder, data)
	for k, v in pairs(data) do
		if folder ~= nil and folder:IsA("Player") and k == "leaderstats" and typeof(v) == "table" then
			SyncLeaderstatsFolder(folder, v)
			continue
		end

		if folder == nil then
			local NewInstance = Instance.new(ConvertType(typeof(v)))
			NewInstance.Name = k
			NewInstance.Parent = folder
			RecursiveUpdate(NewInstance, v)
		end
		if folder ~= nil and not folder:FindFirstChild(k) then
			if typeof(v) ~= "table" then
				local NewInstance = Instance.new(ConvertType(typeof(v)))
				NewInstance.Name = k
				NewInstance.Value = v
				NewInstance.Parent = folder
			else
				local NewInstance = Instance.new(ConvertType(typeof(v)))
				NewInstance.Name = k
				NewInstance.Parent = folder
				RecursiveUpdate(NewInstance, v)
			end
		elseif folder ~= nil and folder:FindFirstChild(k) and typeof(folder[k]) == "Instance" then
			if folder[k].ClassName ~= "Folder" then
				folder[k].Value = v
			else
				RecursiveUpdate(folder[k], v)
			end
		end
	end
end

local function RecursiveRemove(data, folder : Folder)
	for k, v in pairs(folder:GetChildren()) do
		if not (v:IsA("Folder") or v:IsA("NumberValue") or v:IsA("StringValue") or v:IsA("IntValue") or v:IsA("BoolValue")) then
			continue
		end

		if not v:IsA("Folder") then
			if data[v.Name] == nil then
				v:Destroy()
			end
		else
			if data[v.Name] ~= nil then
				RecursiveRemove(data[v.Name], v)
			else
				v:Destroy()
			end
		end
	end
end

SyncPathToInstances = function(player: Player, pathTable: {string}, value: any)
	if #pathTable == 0 then
		return
	end

	if pathTable[1] == "leaderstats" then
		local profile = Profiles[player]
		local leaderstatsData = if profile and profile.Data then profile.Data.leaderstats else value
		if typeof(leaderstatsData) == "table" then
			SyncLeaderstatsFolder(player, leaderstatsData)
			return
		end
	end

	local parent: Instance = player
	for index = 1, #pathTable - 1 do
		local segment = pathTable[index]
		local child = parent:FindFirstChild(segment)
		if child and not child:IsA("Folder") then
			child:Destroy()
			child = nil
		end

		if not child then
			child = Instance.new("Folder")
			child.Name = segment
			child.Parent = parent
		end

		parent = child
	end

	local leafName = pathTable[#pathTable]
	if typeof(value) == "table" then
		local folder = parent:FindFirstChild(leafName)
		if folder and not folder:IsA("Folder") then
			folder:Destroy()
			folder = nil
		end

		if not folder then
			folder = Instance.new("Folder")
			folder.Name = leafName
			folder.Parent = parent
		end

		RecursiveUpdate(folder, value)
		RecursiveRemove(value, folder)
		return
	end

	local className = ConvertType(typeof(value))
	if className == nil then
		return
	end

	local valueObject = parent:FindFirstChild(leafName)
	if valueObject and valueObject.ClassName ~= className then
		valueObject:Destroy()
		valueObject = nil
	end

	if not valueObject then
		valueObject = Instance.new(className)
		valueObject.Name = leafName
		valueObject.Parent = parent
	end

	valueObject.Value = value
end

function DataManager:UpdateData(player : Player)
	if Settings.Experimental.CreateFolders == false then return end

	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
		SyncLeaderstatsFolder(player, profile.Data.leaderstats)
		RecursiveUpdate(player, profile.Data)
		RecursiveRemove(profile.Data, player)
		local attrStore = profile.Data[ATTRIBUTE_STORE_KEY]
		if attrStore then
			for pathStr, attrs in pairs(attrStore) do
				local inst = GetInstanceFromPath(player, pathStr)
				if inst then
					for name, value in pairs(attrs) do
						local sanitized, ok = SanitizeAttributeValue(value)
						if ok then
							inst:SetAttribute(name, sanitized)
						end
					end
				end
			end
		end
	end
end

--[[
	Get player backup data
	[player]: Player you want to get backup data from
	[sort_direction]: Enum.SortDirection
	[min_date]: minimum date you want to search for backup from
	[max_date]: maximum date you want to search for backup from
]]
function DataManager:GetBackup(userId : number, sort_direction : Enum.SortDirection?, min_date : DateTime?, max_date : DateTime?): typeof(PlayerStore:VersionQuery():NextAsync())?
	local query = PlayerStore:VersionQuery(
		`Player_{userId}`,
		sort_direction or Enum.SortDirection.Ascending,
		min_date or nil,
		max_date or nil
	)

	local profile = query:NextAsync()

	if profile ~= nil then
		return profile
	end

	warn("[DataManager]: Couldn't get data backup")
	return false
end

--[[
	Load player backup data
	[profile]: backup data to load (use DataManager:GetBackup to get this backup data)
]]
function DataManager:LoadBackup(profile : typeof(PlayerStore:VersionQuery():NextAsync())) : boolean
	local UserId = tonumber(profile["Key"]:split("_")[2])
	profile:SetAsync()
	profile:EndSession()

	DataManager:MessageAsync(UserId, {Key = "BackupedJoined"})
	return true
end

--[[
	Send information to other player across other servers (works on offline players too)
	[userId]: user id of player you want to send information to
	[message]: table containing all of the information you want to send
]]
function DataManager:MessageAsync(userId : number, message : {any?}) : boolean
	return PlayerStore:MessageAsync(`Player_{userId}`, message)
end

function ListenToMessages(player : Player)
	local profile = self:GetProfile(player)

	if profile then
		profile:MessageHandler(function(message, processed)
			if MessagesFunctions[message["Key"]] then
				MessagesFunctions[message["Key"]](player, profile, message)
			end
			processed() 
		end)
	end
end

--[[
	Debugging function, prints player data everytime it updates if __Debug is true
]]
function Debug(player : Player, debugging : ("Data" | "Profile")?)
	if not debugging then debugging = __Debugging end

	if __Debug then
		local profile = self:GetProfile(player)
		if profile ~= nil then
			if debugging == "Data" then
				warn(`[DataManager]: DEBUGGING {(player.Name):upper()} DATA: `, profile.Data)
			else
				warn(`[DataManager]: DEBUGGING {(player.Name):upper()} PROFILE: `, profile)
			end

		end
	end
end

--[[
	Returns table of all players that ever joined your game
	returns table of players user ids and thier os.time() join time
]]
function DataManager:GetAllPlayers() : {typeof(os.time())}
	return GlobalData:Get("Players")
end

local function AddNewGlobalPlayer(player : Player) 
	local AllPlayers = GlobalData:Get("Players")
	if AllPlayers[player.UserId] ~= nil then return end

	local FixedPlayers = AllPlayers
	FixedPlayers[player.UserId] = os.time()

	GlobalData:Set("Players", FixedPlayers)
end

local function countPositiveQuantityFolders(root: Instance?): number
	if not root then
		return 0
	end

	local count = 0
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Folder") then
			local quantity = child:FindFirstChild("Quantity")
			if quantity and quantity:IsA("NumberValue") and quantity.Value > 0 then
				count += 1
			end
		end
	end
	return count
end

local function markPlayerDataReady(player: Player, startedAt: number)
	local inventory = player:FindFirstChild("Inventory")
	local inventoryFolderCount = countPositiveQuantityFolders(inventory)
	local crewMemberInventory = player:FindFirstChild("CrewMemberInventory")
	local crewById = crewMemberInventory and crewMemberInventory:FindFirstChild("ById")
	local crewCount = crewById and #crewById:GetChildren() or 0
	local elapsed = os.clock() - startedAt

	player:SetAttribute(PLAYER_DATA_READY_ATTRIBUTE, true)
	player:SetAttribute(PLAYER_DATA_READY_AT_ATTRIBUTE, os.clock())
	dataReadyLog(
		"player",
		player.Name,
		"userId",
		player.UserId,
		"elapsed",
		string.format("%.2f", elapsed),
		"profile",
		tostring(Profiles[player] ~= nil),
		"replica",
		tostring(Replicas[player] ~= nil),
		"inventoryFolders",
		inventoryFolderCount,
		"crew",
		crewCount
	)
end

local function runCrewMemberShadowWriteOnProfileReady(player: Player, profile)
	local ok, result = pcall(function()
		local CrewStorage = require(game.ServerScriptService.Modules.CrewStorage)
		local flags = CrewStorage.GetShadowFlags()
		if flags.CrewMemberShadowWriteEnabled ~= true then
			return {
				DidWrite = false,
				SkippedReason = "shadow_write_disabled",
			}
		end

		local CrewMemberShadowWriter = require(game.ServerScriptService.Modules.CrewMemberShadowWriter)
		return CrewMemberShadowWriter.RunProfileReadyProjection(profile.Data, {
			Player = player,
			Flags = flags,
		})
	end)

	if not ok then
		warn(string.format(
			"[DataManager]: CrewMember shadow-write hook failed for %s: %s",
			player.Name,
			tostring(result)
		))
	end

	return if ok then result else nil
end

local function disconnectPendingReplicaReadyConnection(player: Player)
	local connection = PendingReplicaReadyConnections[player]
	if connection then
		connection:Disconnect()
		PendingReplicaReadyConnections[player] = nil
	end
end

local function subscribeReplicaPlayer(player: Player, replica): boolean
	if player.Parent ~= Players then
		return false
	end

	if Replica.ReadyPlayers[player] == nil then
		return false
	end

	local ok, err = pcall(function()
		replica:Subscribe(player)
	end)

	if not ok then
		warn(string.format(
			"[DataManager]: Failed to subscribe player data replica for %s(%d): %s",
			player.Name,
			player.UserId,
			tostring(err)
		))
		return false
	end

	return true
end

local function waitForReplicaReady(player: Player, timeoutSeconds: number): (boolean, number)
	local startedAt = os.clock()
	local deadline = startedAt + math.max(0, timeoutSeconds)

	while player.Parent == Players and Replica.ReadyPlayers[player] == nil and os.clock() < deadline do
		task.wait(0.1)
	end

	return Replica.ReadyPlayers[player] ~= nil, os.clock() - startedAt
end

local function subscribeReplicaPlayerWhenReady(player: Player, startedAt: number)
	disconnectPendingReplicaReadyConnection(player)

	PendingReplicaReadyConnections[player] = Replica.NewReadyPlayer:Connect(function(readyPlayer: Player)
		if readyPlayer ~= player then
			return
		end

		disconnectPendingReplicaReadyConnection(player)

		local replica = Replicas[player]
		if replica == nil then
			return
		end

		if subscribeReplicaPlayer(player, replica) then
			dataReadyLog(
				"late_replica_subscribe",
				"player",
				player.Name,
				"userId",
				player.UserId,
				"elapsed",
				string.format("%.2f", os.clock() - startedAt)
			)
		end
	end)
end

function PlayerAdded(player: Player)
	local dataReadyStartedAt = os.clock()
	player:SetAttribute(PLAYER_DATA_READY_ATTRIBUTE, false)
	player:SetAttribute(PLAYER_DATA_READY_AT_ATTRIBUTE, nil)

	if PendingHardResetByUserId[player.UserId] == true then
		dataResetLog("reject_join_during_wipe", "player", player.Name, "userId", player.UserId)
		player:Kick(HARD_RESET_PROGRESS_KICK_MESSAGE)
		return
	end
	-- Natychmiastowe tworzenie folderów z szablonu
	if Settings.Experimental.CreateFolders == true then
		local templateRoot = script:FindFirstChild("Data")
		if templateRoot then
			for _, templateFolder in pairs(templateRoot:GetChildren()) do
				if not player:FindFirstChild(templateFolder.Name) then
					templateFolder:Clone().Parent = player
				end
			end
		else
			warn(string.format("[DataManager]: Missing Data template folder under %s; skipping template clone for %s", script:GetFullName(), player.Name))
			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then
				leaderstats = Instance.new("Folder")
				leaderstats.Name = "leaderstats"
				leaderstats.Parent = player
			end
		end
	else
		-- Jeśli CreateFolders jest false, od razu tworzymy leaderstats
		local folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end

	SyncLeaderstatsFolder(player, GetTemplate.leaderstats)

	-- Ładowanie profilu
	local profile = PlayerStore:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()
		ProfileMigrations.Apply(profile.Data)
		runCrewMemberShadowWriteOnProfileReady(player, profile)
		ValidationChecks.WarnProfileData(player, profile.Data)

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			ActiveBoostRoutines[player] = nil
			disconnectPendingReplicaReadyConnection(player)
			ReplicaPlayerRemoving(player)

			if SuppressSessionEndKickByUserId[player.UserId] == true then
				dataResetLog("session_end_suppressed", "player", player.Name, "userId", player.UserId)
				return
			end

			player:Kick("Profile session end - Please rejoin!")
		end)

		if player.Parent == Players then
			Profiles[player] = profile
		else
			profile:EndSession()
			return
		end

		local replicaReady, replicaWaitElapsed = waitForReplicaReady(player, REPLICA_READY_TIMEOUT_SECONDS)
		local replica = NewReplicaPlayer(player, replicaReady)
		if replica == nil then
			return
		end

		if not replicaReady and player.Parent == Players then
			warn(string.format(
				"[DataManager]: Replica readiness timed out for %s(%d) after %.2fs; continuing data startup and will attempt a late subscription when the client is ready.",
				player.Name,
				player.UserId,
				replicaWaitElapsed
			))
			if not subscribeReplicaPlayer(player, replica) then
				subscribeReplicaPlayerWhenReady(player, dataReadyStartedAt)
			end
		end

		AddNewGlobalPlayer(player)
		ListenToMessages(player)

		-- Aktualizacja danych po załadowaniu profilu
		if Settings.Experimental.CreateFolders == true then
			self:UpdateData(player)
		else
			self:Leaderstats(player)
		end
		markPlayerDataReady(player, dataReadyStartedAt)
		DataManager:SetupBoostListeners(player)
	else
		player:Kick("Profile load fail - Please rejoin!")
	end
end

local PlayerDataStoreToken = Replica.Token("PlayerDataStore")

function NewReplicaPlayer(player: Player, subscribeImmediately: boolean?)
	local profile = Profiles[player]
	if not profile then
		player:Kick("Replica – profile load fail – Please rejoin!")
		return
	end

	-- używamy wcześniej stworzonego tokena, nie tworzymy nowego
	local replica = Replica.New({
		Token = PlayerDataStoreToken,
		Data  = profile.Data,
		Tags  = { UserId = player.UserId },
	})

	if player.Parent == Players then
		Replicas[player] = replica
		if subscribeImmediately ~= false then
			subscribeReplicaPlayer(player, replica)
		end
	else
		replica:Unsubscribe()
		Replicas[player] = nil
	end

	return replica
end

function PlayerRemoving(player: Player)
	disconnectPendingReplicaReadyConnection(player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:EndSession()
		Profiles[player] = nil
		ActiveBoostRoutines[player] = nil
		ReplicaPlayerRemoving(player)
	end
end

function ReplicaPlayerRemoving(player : Player)
	local replica = Replicas[player]
	if replica ~= nil then
		replica:Unsubscribe()
		Replicas[player] = nil
	end
end

function FillMessageFunctions()
	for Index, Value in pairs(MessageFunctions) do
		MessagesFunctions[Index] = Value
	end
end

-- PRODUCT MANAGER SECTION
function DataManager:PromptProductPurchase(player : Player, productId : number)
	productId = tonumber(productId)
	if productId == nil then
		warn("[DataManager]: Refused product prompt with invalid product id")
		return false, "invalid_product_id"
	end

	if not MonetizationConfig.CanPromptDeveloperProduct(productId) then
		local status, metadata = MonetizationConfig.GetDeveloperProductStatus(productId)
		warn(string.format(
			"[DataManager]: Blocked disabled/non-GTR product prompt player=%s productId=%s status=%s reason=%s",
			player and player.Name or "<unknown>",
			tostring(productId),
			tostring(status),
			tostring(metadata and metadata.Reason or "not_active_chefs_product")
		))
		return false, "product_not_available"
	end

	if MonetizationConfig.DeveloperProductRequiresPaidRandomItemPolicy(productId) then
		local allowed, policyState = PaidRandomItemPolicy.CanUsePaidRandomItems(player)
		if allowed ~= true then
			warn(string.format(
				"[DataManager]: Blocked paid random product prompt player=%s productId=%s policyStatus=%s reason=%s",
				player and player.Name or "<unknown>",
				tostring(productId),
				tostring(policyState and policyState.Status or "unknown"),
				tostring(policyState and policyState.Reason or "policy_unknown")
			))
			return false, tostring(policyState and policyState.Reason or "policy_unknown"), policyState
		end
	end

	if ProductFunctions[productId] == nil then
		warn("[DataManager]: No product function under id: ".. productId)
		return false, "missing_product_function"
	end

	MarketPlaceService:PromptProductPurchase(player, productId)
	return true, nil
end

function PurchaseIdCheckAsync(profile : typeof(PlayerStore:StartSessionAsync()), purchase_id, grant_purchase): Enum.ProductPurchaseDecision
	if profile:IsActive() then
		local purchase_id_cache = profile.Data.PurchaseIdCache

		if purchase_id_cache == nil then
			purchase_id_cache = {}
			profile.Data.PurchaseIdCache = purchase_id_cache
		end

		if table.find(purchase_id_cache, purchase_id) == nil then
			local success, result = pcall(grant_purchase)
			if success ~= true then
				warn("[DataManager]: Failed to process receipt:" .. profile.Key, purchase_id, result)
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			while #purchase_id_cache >= PURCHASE_ID_CACHE_SIZE do
				table.remove(purchase_id_cache, 1)
			end

			table.insert(purchase_id_cache, purchase_id)
		end

		local function is_purchase_saved()
			local saved_cache = profile.LastSavedData.PurchaseIdCache
			return if saved_cache ~= nil then table.find(saved_cache, purchase_id) ~= nil else false
		end

		if is_purchase_saved() == true then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		while profile:IsActive() == true do
			local last_saved_data = profile.LastSavedData
			profile:Save()

			if profile.LastSavedData == last_saved_data then
				profile.OnAfterSave:Wait()
			end

			if is_purchase_saved() == true then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end

			if profile:IsActive() == true then
				task.wait(10)
			end
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function DataManager.RunProductReceiptIdempotencyCanary(dataManager, player: Player, receiptInfo, grant_purchase)
	if RunService:IsStudio() ~= true then
		return nil, "studio_required"
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, "player_required"
	end
	if typeof(receiptInfo) ~= "table" then
		return nil, "receipt_info_required"
	end
	if typeof(grant_purchase) ~= "function" then
		return nil, "grant_purchase_required"
	end

	local purchaseId = tostring(receiptInfo.PurchaseId or "")
	if purchaseId == "" then
		return nil, "purchase_id_required"
	end
	if tonumber(receiptInfo.PlayerId) ~= player.UserId then
		return nil, "receipt_player_mismatch"
	end

	local profile = dataManager:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return nil, "profile_or_replica_unavailable"
	end

	return PurchaseIdCheckAsync(profile, purchaseId, grant_purchase), nil
end
local MessagingService = game:GetService("MessagingService") -- <--- DODANE
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ANNOUNCE_TOPIC = "DM_DevProductAnnouncements" -- nazwa tematu w MessagingService
local ANNOUNCE_EVENT_NAME = "DevProductAnnouncement" -- nazwa RemoteEventu

-- RemoteEvent do ogłoszeń
local AnnouncementEvent = ReplicatedStorage:FindFirstChild(ANNOUNCE_EVENT_NAME)
if not AnnouncementEvent then
	AnnouncementEvent = Instance.new("RemoteEvent")
	AnnouncementEvent.Name = ANNOUNCE_EVENT_NAME
	AnnouncementEvent.Parent = ReplicatedStorage
end

-- prosta kolejka wiadomości do MessagingService
local PurchaseQueue = {}
local IsProcessingPurchaseQueue = false


-- Zwraca: priceInRobux, productName
local function GetProductPrice(productId: number): (number, string)
	-- Bezpiecznie pobieramy info o produkcie
	local ok, info = pcall(function()
		return MarketPlaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)

	if ok and info and typeof(info) == "table" then
		local price = info.PriceInRobux or 0
		local name = info.Name or ("Product " .. tostring(productId))
		return price, name
	else
		-- fallback, gdy API padnie
		return 0, ("Product " .. tostring(productId))
	end
end


local function ProcessPurchaseQueue()
	while #PurchaseQueue > 0 do
		local data = PurchaseQueue[1]

		local ok, err = pcall(function()
			MessagingService:PublishAsync(ANNOUNCE_TOPIC, data)
		end)

		if ok then
			table.remove(PurchaseQueue, 1)
		else
			warn("[DataManager]: MessagingService PublishAsync failed: ", err)
			-- jeśli throttling / błąd, poczekaj chwilę i spróbuj ponownie
			task.wait(3)
		end
	end

	IsProcessingPurchaseQueue = false
end

-- Dodaje wiadomość do kolejki
local function EnqueuePurchaseAnnouncement(player: Player, productId: number, productName: string, price: number)
	if RunService:IsStudio() then
		return
	end

	local payload = {
		UserId = player.UserId,
		Username = player.Name,
		ProductId = productId,
		ProductName = productName,
		PriceInRobux = price,
		Time = os.time(),
	}

	table.insert(PurchaseQueue, payload)

	if not IsProcessingPurchaseQueue then
		IsProcessingPurchaseQueue = true
		task.spawn(ProcessPurchaseQueue)
	end
end

local function ProcessReceipt(recieptInfo)
	local player = Players:GetPlayerByUserId(recieptInfo.PlayerId)
	if player ~= nil then
		local profile = self:GetProfile(player)

		while profile == nil and player.Parent == Players do
			profile = Profiles[player]
			if profile ~= nil then
				break
			end
			task.wait()
		end

		if profile ~= nil then
			local productId = tonumber(recieptInfo.ProductId)
			if productId == nil then
				warn("[DataManager]: No product found under id: " .. tostring(recieptInfo.ProductId))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			if MonetizationConfig.DeveloperProductRequiresPaidRandomItemPolicy(productId) then
				local allowed, policyState = PaidRandomItemPolicy.CanUsePaidRandomItems(player)
				if allowed ~= true then
					return PurchaseIdCheckAsync(
						profile,
						recieptInfo.PurchaseId,
						function()
							local marker, created = PaidRandomItemPolicy.RecordBlockedReceiptFallback(
								profile,
								player,
								recieptInfo,
								policyState
							)
							warn(string.format(
								"[DataManager]: Blocked paid random receipt and recorded support marker player=%s productId=%s purchaseId=%s markerCreated=%s policyStatus=%s reason=%s fallbackMode=%s",
								player.Name,
								tostring(productId),
								tostring(recieptInfo.PurchaseId),
								tostring(created == true),
								tostring(policyState and policyState.Status or "unknown"),
								tostring(policyState and policyState.Reason or "policy_unknown"),
								tostring(marker and marker.FallbackMode or "SupportMarker")
							))
						end
					)
				end
			end

			if ProductFunctions[productId] == nil then
				warn("[DataManager]: No product found under id: " .. tostring(recieptInfo.ProductId))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			return PurchaseIdCheckAsync(
				profile,
				recieptInfo.PurchaseId,
				function()
					---------------------------------------------------------------
					--  ➤  ID-check + doładowanie RobuxSpent
					---------------------------------------------------------------
					if recieptInfo.PlayerId ~= player.UserId then
						-- to nie powinno się zdarzyć, ale jeśli jednak – nie ryzykuj
						warn("[DataManager]: PlayerId z receiptInfo nie zgadza się z player.UserId!")
						return Enum.ProductPurchaseDecision.NotProcessedYet
					end

					local productStatus, productMetadata = MonetizationConfig.GetDeveloperProductStatus(productId)
					local shouldRecordPurchase = productStatus == MonetizationConfig.Status.Active
					local price = 0
					local productName = "Product " .. tostring(productId)
					if shouldRecordPurchase then
						price, productName = GetProductPrice(productId)
						if price > 0 then
							DataManager:AddValue(player, "TotalStats.RobuxSpent", price)
						end
					else
						warn(string.format(
							"[DataManager]: Processing disabled/non-GTR product receipt without grant accounting player=%s productId=%s status=%s reason=%s",
							player.Name,
							tostring(productId),
							tostring(productStatus),
							tostring(productMetadata and productMetadata.Reason or "not_active_chefs_product")
						))
					end

					---------------------------------------------------------------
					--  ➤  oryginalna logika produktu
					---------------------------------------------------------------
					ProductFunctions[productId](recieptInfo, player, profile, DataManager)

					---------------------------------------------------------------
					--  ➤  wrzuć ogłoszenie do kolejki MessagingService
					---------------------------------------------------------------
					if shouldRecordPurchase then
						EnqueuePurchaseAnnouncement(player, productId, productName, price)
					end
				end
			)
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end


local function _num(x)
	return (typeof(x) == "number") and x or 0
end

function DataManager:UnequipAnimal(player: Player, animalName: string)
	if typeof(animalName) ~= "string" then return false end

	local profile = self:GetProfile(player)
	if not profile or not profile.Data then return false end

	profile.Data.Animals = profile.Data.Animals or {}
	local animals = profile.Data.Animals
	local info = animals[animalName]
	local eq = _num(info and info.Equipped)

	if eq <= 0 then
		return false
	end

	self:AdjustValue(player, "Animals." .. animalName .. ".Equipped", -1)
	self:AdjustValue(player, "Animals." .. animalName .. ".Quantity", 1)
	return true
end

function DataManager:EquipAnimal(player: Player, animalName: string)
	if typeof(animalName) ~= "string" then return false end

	local profile = self:GetProfile(player)
	if not profile or not profile.Data then return false end

	profile.Data.Animals = profile.Data.Animals or {}
	local animals = profile.Data.Animals
	local info = animals[animalName]
	local qty = _num(info and info.Quantity)

	if qty <= 0 then
		return false
	end

	self:AdjustValue(player, "Animals." .. animalName .. ".Quantity", -1)
	self:AdjustValue(player, "Animals." .. animalName .. ".Equipped", 1)
	return true
end


function DataManager:AdjustValue(player: Player, path: string, delta: number)
	local profile = self:GetProfile(player)
	local replica = self:GetReplica(player)
	if not profile or not replica then return end

	local legacyWriteAllowed, legacyWriteReason = inspectLegacyWrite(player, profile, path, "AdjustValue")
	if legacyWriteAllowed ~= true then
		return nil, legacyWriteReason
	end

	-- upewnij się, że ścieżka istnieje i ma początkowo 0
	local parent, leafKey, pathTable, current, err = ResolveDataPath(profile, path, true, 0)

	-- znajdź rodzica i klucz końcowy, żeby zapisać do profile.Data
	if err then
		warn(err)
		return nil
	end

	if typeof(current) ~= "number" then
		warn(string.format("[DataManager]: Can't adjust non-number at '%s' (type: %s)", path, typeof(current)))
		return
	end
	if typeof(delta) ~= "number" then
		warn(string.format("[DataManager]: AdjustValue expects number delta, got %s", typeof(delta)))
		return
	end

	local final = current + delta
	parent[leafKey] = final               -- <— ZAPIS do profile.Data
	SyncDataMutation(player, replica, pathTable, final)

	return final
end

local function waitForChild(parent, childName)
	local inst = parent:FindFirstChild(childName)
	while not inst do
		parent.ChildAdded:Wait()
		inst = parent:FindFirstChild(childName)
	end
	return inst
end

DataManager._activeBoosts = DataManager._activeBoosts or {}

-- Pomocnik: znajdź NumberValue o podanej nazwie w Inventory.Potions (przeszukuje całe drzewo)
function DataManager:_findPotionNumberValue(player: Player, valueName: string): NumberValue?
	-- próbujemy nieblokująco, a potem z krótkim waitem (na wypadek, gdyby Inventory/Potions dopiero się tworzyły)
	local Potions = player:FindFirstChild("Potions") or player:WaitForChild("Potions", 5)
	if not Potions then return nil end



	for _, inst in ipairs(Potions:GetDescendants()) do
		if inst:IsA("NumberValue") and inst.Name == valueName then
			return inst
		end
	end

	return nil
end

function DataManager:_findPathInData(player: Player, predicate: (string, any) -> boolean): string?
	local profile = self:GetProfile(player)
	if not profile then return nil end

	local function dfs(tbl, parts)
		for k, v in pairs(tbl) do
			local newParts = {}
			for i = 1, #parts do newParts[i] = parts[i] end
			newParts[#newParts + 1] = k

			if predicate(k, v) then
				return table.concat(newParts, ".") -- np. "Inventory.Potions.Gems.Gem Potion ITime"
			end
			if typeof(v) == "table" then
				local p = dfs(v, newParts)
				if p then return p end
			end
		end
		return nil
	end

	return dfs(profile.Data, {})
end

function DataManager:_resolveBoostPaths(player: Player, boostName: string): (string?, string?)
	local potions = player:FindFirstChild("Potions")
	if not potions then
		return nil, nil
	end

	local timeKey = boostName .. "Time"

	local timeInst: NumberValue? = nil
	local countInst: NumberValue? = nil

	-- 🔎 SZUKAMY TYLKO W Potions
	for _, inst in ipairs(potions:GetDescendants()) do
		if inst:IsA("NumberValue") then
			if inst.Name == timeKey then
				timeInst = inst
			elseif inst.Name == boostName then
				countInst = inst
			end

			if timeInst and countInst then
				break
			end
		end
	end

	-- ❌ NIE MA Time w Potions → NIE MA BOOSTA
	if not timeInst then
		return nil, nil
	end

	-- składanie ścieżki bez helperów
	local function buildPath(inst: Instance): string
		local parts = {}
		local cur: Instance? = inst
		while cur and cur ~= player do
			table.insert(parts, 1, cur.Name)
			cur = cur.Parent
		end
		return table.concat(parts, ".")
	end

	local timePath = buildPath(timeInst)
	local countPath = countInst and buildPath(countInst) or nil

	return countPath, timePath
end

-- ResumeBoost – odliczanie czasu przez SubValue
function DataManager:ResumeBoost(player: Player, boostName: string)
	local _, timePath = self:_resolveBoostPaths(player, boostName)
	if not timePath then
		warn(("[Boost] Nie znaleziono *Time dla '%s' u %s"):format(boostName, player.Name))
		return
	end

	local key = tostring(player.UserId) .. "_" .. boostName
	if self._activeBoosts[key] then return end  -- już działa

	-- aktualna wartość czasu
	local remaining: number? = self:GetValue(player, timePath)
	if not remaining or remaining <= 0 then return end

	self._activeBoosts[key] = true
	task.spawn(function()
		while player.Parent == Players do
			task.wait(1)
			local cur = self:GetValue(player, timePath)
			if not cur or cur <= 0 then
				break
			end
			-- odejmujemy 1 sekundę bezpośrednio w danych (bez instancji)
			self:AdjustValue(player, timePath, -1)
		end
		self._activeBoosts[key] = nil
		print(("[Boost] %s zakończył się dla %s"):format(boostName, player.Name))
	end)
end

function DataManager:StartBoost(player: Player, boostName: string, timePerUnit: number, amountUsed: number)
	local countPath, timePath = self:_resolveBoostPaths(player, boostName)

	if not timePath then
		return
	end

	if countPath and amountUsed and amountUsed > 0 then
		self:AdjustValue(player, countPath, -amountUsed)
	end

	local totalTime = (timePerUnit or 0) * (amountUsed or 1)
	if totalTime > 0 then
		self:AdjustValue(player, timePath, totalTime)
	end

	print(("[Boost] Start %s dla %s (+%d s)"):format(boostName, player.Name, totalTime))
	self:ResumeBoost(player, boostName)
end

-- SetupBoostListeners – bez zmian, tylko dopasowany do AddValue/SubValue/ResumeBoost
function DataManager:SetupBoostListeners(player: Player)
	task.spawn(function()
		local function scanAndResumeAllTimes()
			local profile = self:GetProfile(player)
			if not profile then return end

			local potions = profile.Data.Potions
			if typeof(potions) ~= "table" then
				return
			end

			for key, value in pairs(potions) do
				if typeof(value) == "number" and type(key) == "string" and key:sub(-4) == "Time" and value > 0 then
					local boostName = key:sub(1, #key - 4)
					DataManager:ResumeBoost(player, boostName)
				end
			end
		end

		-- Pierwszy skan po załadowaniu profilu
		scanAndResumeAllTimes()

		-- Lekki polling (2s) – łapie późniejsze zwiększenia czasu bez instancji
		while player.Parent == Players do
			task.wait(2)
			scanAndResumeAllTimes()
		end
	end)
end


-- VERSION SECTION

function DataManager:Version()
	local CurrentVersion = GetVersion(SCRIPT_VERSION)
	if CurrentVersion == nil then warn("[DataManager]: Couldn't get current version") return end

	local split = CurrentVersion.date:split("-")
	local date, time, timezone = split[1], split[2], split[3]
	local date_split = date:split(".")
	local day, month, year = date_split[1], date_split[2], date_split[3]

	return print(
		`\n`..
			`									📈 Data Manager - Version \n \n`..
			`									🗂️ Version: {CurrentVersion.version} \n` ..
			`									🛠️ Status: {CurrentVersion.status} \n` ..
			`									📅 Release Date: {table.concat({day, month, year}, ".")} \n` ..
			`									📝 Description: {CurrentVersion.description} \n` ..
			`									👨‍💻 Author: {CurrentVersion.author} \n`
	)
end

function CheckVersion()
	workspace:SetAttribute("DataManager_Version", SCRIPT_VERSION)
	-- Security: external version polling is diagnostic-only and must not run in production servers.
	if not RunService:IsStudio() then
		return
	end

	local AllVersions = GetVersion()
	if typeof(AllVersions) == "table" then
		if AllVersions[1].version ~= SCRIPT_VERSION then
			warn(`⚠️ [DataManager]: New latest {AllVersions[1].status} version available ({AllVersions[1].version})! Currently running on version ({SCRIPT_VERSION}).`)
		else
			local status = GetVersion(SCRIPT_VERSION).status
			if status == "stable" then
				print(`✅ [DataManager]: You are running on latest stable version ({SCRIPT_VERSION}).`)
			elseif status == "unstable" then
				print(`❗ [DataManager]: You are running on latest unstable version ({SCRIPT_VERSION}).`)
			else
				warn(`⚠️ [DataManager]: You are running on latest {status} version ({SCRIPT_VERSION}).`)
			end

		end
	else
		warn(`❌ [DataManager]: Something failed during checking script version!`)
	end
end

function GetVersion(version : string?)
	local success, result = pcall(function()
		return HttpService:GetAsync(PASTEBIN)
	end)

	if success then
		local __success, __result = pcall(function() 
			return HttpService:JSONDecode(result)
		end)

		if __success then
			if version ~= nil then
				for Index, Value in pairs(__result) do
					if Value.version == version then
						return Value
					end
				end
			else
				return __result
			end
		else
			warn("[DataManager]: Something went wrong during decoding version")
			return __result
		end
	else
		warn("[DataManager]: Something went wrong during getting version")
		return result
	end

end

local function SetupAnnouncementSubscription()
	if RunService:IsStudio() then
		return
	end

	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(ANNOUNCE_TOPIC, function(message)
			local data = message.Data
			if typeof(data) ~= "table" then return end

			-- Prosty sanity check
			if not (data.Username and data.ProductName and data.PriceInRobux ~= nil) then
				return
			end

			-- Wysyłamy do wszystkich klientów na tym serwerze
			AnnouncementEvent:FireAllClients(data)
		end)
	end)

	if not ok then
		warn("[DataManager]: Failed to subscribe to MessagingService: ", err)
	end
end

local function SetupPaidRandomItemPolicyRemotes()
	local remotesConfig = MonetizationConfig.PaidRandomItemPolicy
		and MonetizationConfig.PaidRandomItemPolicy.Remotes
		or {}
	local promptRemoteName = tostring(remotesConfig.ProductPromptRequestName or "PaidRandomProductPromptRequest")

	PaidRandomItemPolicy.SetupRemotes({
		PromptProductPurchase = function(player: Player, productId: number)
			if not RemoteGuard.Check(player, promptRemoteName, { productId }, {
				Cooldown = 0.35,
				Args = {
					{ Type = "finiteNumber", Integer = true, Min = 1 },
				},
			}) then
				return {
					ok = false,
					error = "remote_guard_rejected",
				}
			end

			productId = tonumber(productId)
			if productId == nil or not MonetizationConfig.DeveloperProductRequiresPaidRandomItemPolicy(productId) then
				warn(string.format(
					"[DataManager]: Rejected paid random prompt remote for non-paid-random product player=%s productId=%s",
					player and player.Name or "<unknown>",
					tostring(productId)
				))
				return {
					ok = false,
					error = "not_paid_random_product",
				}
			end

			local prompted, reason = DataManager:PromptProductPurchase(player, productId)
			return {
				ok = prompted == true,
				error = if prompted == true then nil else tostring(reason or "prompt_rejected"),
				policy = PaidRandomItemPolicy.GetClientState(player),
			}
		end,
	})
end


DataManager.init = function()
	if DataManagerInitialized then
		return
	end

	DataManagerInitialized = true
	DataManager._initialized = true
	workspace:SetAttribute("DataManager_RuntimeSignature", "src-path-sync-2026-03-17")
	workspace:SetAttribute("DataManager_TargetedSync", true)
	workspace:SetAttribute(
		"DataManager_SyncMode",
		if Settings.Experimental.CreateFolders then "targeted_path_sync" else "legacy_update_data"
	)

	FillMessageFunctions()
	DataManager.Premades = Premades
	SetupPaidRandomItemPolicyRemotes()

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerAdded, player)
	end
	Players.PlayerAdded:Connect(PlayerAdded)
	Players.PlayerRemoving:Connect(PlayerRemoving)

	task.spawn(function()
		local ok, err = pcall(CheckVersion)
		if not ok then
			warn("[DataManager]: Version check failed during init: ", err)
		end
	end)

	task.spawn(function()
		local ok, err = pcall(SetupAnnouncementSubscription)
		if not ok then
			warn("[DataManager]: Announcement subscription failed during init: ", err)
		end
	end)

	task.spawn(function()
		local ok, err = pcall(ValidationChecks.WarnMissingDependencies)
		if not ok then
			warn("[DataManager]: Validation checks failed during init: ", err)
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(PlayerRemoving, player)
		end
	end)
end


MarketPlaceService.ProcessReceipt = ProcessReceipt

return DataManager
