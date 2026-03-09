--// Main
local DataManager = {}
DataManager.__index = DataManager; self = setmetatable({}, DataManager)

--// Other 
local Key: string = script:GetAttribute("Data_Key") or "DefaultKey_123"
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
local MessageFunctions = require(script.MessageFunctions)
local ProductFunctions = require(script.ProductFunctions)
local Settings = require(script.Settings)
local Premades = require(script.Premades)
  
--// ProfileStore
local PlayerStore = ProfileStore.New(Key, GetTemplate)
local Profiles: {[Player]: typeof(PlayerStore:StartSessionAsync())} = {}
local Replicas: {[Player]: typeof(Replica)} = {}
local ActiveBoostRoutines = {}  

--// GlobalStore
local GlobalData = GlobalStore.New("__GlobalData", {Players = {}})

--// Services 
local Players = game:GetService("Players")
local MarketPlaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService(`RunService`)
--// Variables
local CLASS_NAMES = {["string"] = "StringValue", ["number"] = "NumberValue", ["boolean"] = "BoolValue"}
local PURCHASE_ID_CACHE_SIZE = 100
local PASTEBIN = "https://pastebin.com/raw/JT4wrgrq"
local SCRIPT_VERSION = script:GetTags()[1]

--[[
	Primary message functions to DataManager:MessageAsync() function
]]


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
			profile.Data = GetTemplate
			replica.Data = GetTemplate

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

--[[
	Function used to shorten code (isn't usable from the outside)
]]
function GetPointer(path : string, profile : typeof(PlayerStore:StartSessionAsync())) : ({any?}?, {any?}?)
	local pathTable = path:split(".")
	local pointer = profile

	if pathTable[1] ~= "Data" then 
		pointer = pointer.Data
	end

	for i = 1, #pathTable - 1 do
		if pointer[pathTable[i]] == nil then break end
		pointer = pointer[pathTable[i]]
	end

	if pointer[pathTable[#pathTable]] == nil then
		return nil, pathTable
	end

	return pointer[pathTable[#pathTable]], pathTable
end

--[[
	Get value from a path
	[player]: player you want to get value from
	[path]: path to the value (e.g. "leaderstats.Coins")
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



local function ReconstructPath(Player: Player, Path: string, EndValue: any?)
	local PathTable = string.split(Path, ".")
	local Pointer = self:GetData(Player)
	for Index, PathPoint in ipairs(PathTable) do
		if Pointer[PathPoint] == nil then
			Pointer[PathPoint] = {}
			if Index == #PathTable then
				Pointer[PathPoint] = EndValue or {}
			end
		end
		if Pointer[PathPoint] ~= nil and typeof(Pointer[PathPoint]) ~= "table" and Index ~= #PathTable then
			warn(string.format("[DataManager]: Can't reconstruct - found type %s at path step %s", typeof(Pointer[PathPoint]), PathPoint))
			return
		end
		Pointer = Pointer[PathPoint]
	end
end

--[[
	Sets variable value
	[player]: which player you want to change the date
	[path]: path to variable (e.g. leaderstats.Coins)
	[newValue]: to which value it should be set 
]]
function DataManager:SetValue(player: Player, path: string, newValue : (string | number | boolean | {any?})?)
	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
		local pointer, pathTable = GetPointer(path, profile)

		if pointer == nil then
			local currentPointer = profile

			for i, e in pairs(pathTable) do
				if i < #pathTable then
					if currentPointer[e] ~= nil then
						currentPointer = currentPointer[e]
					else
						currentPointer[e] = {}
						currentPointer = currentPointer[e]
					end
				else
					if currentPointer[e] ~= nil then
						currentPointer = currentPointer[e]
					else
						currentPointer[e] = newValue == nil and true or newValue
						currentPointer = currentPointer[e]
					end
				end
			end

			DataManager:UpdateData(player)
		else
			if newValue ~= nil then
				if typeof(pointer) == typeof(newValue) then
					pointer = newValue
					replica:Set(pathTable, newValue)
					if pathTable[2] == "leaderstats" and not Settings.Experimental.CreateFolders then
						DataManager:Leaderstats(player)
					else
						DataManager:UpdateData(player)
					end

					Debug(player)
				else
					warn(`[DataManager]: Given value ({newValue} : {typeof(newValue)}) must be the same type as (Data.{path} : {typeof(pointer)})!`)
					return
				end
			else
				if typeof(pointer) == "boolean" then
					local newValue = not pointer
					pointer = newValue
					replica:Set(pathTable, newValue)
					if pathTable[2] == "leaderstats" and not Settings.Experimental.CreateFolders then
						DataManager:Leaderstats(player)
					else
						DataManager:UpdateData(player)
					end

					Debug(player)
				end
			end
		end
	else
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return
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
	[path]: path to variable (e.g. leaderstats.Coins)
	[addValue]: to which value it should be set 
]]
function DataManager:AddValue(player, path, addValue)
	local profile = self:GetProfile(player)
	local replica = self:GetReplica(player)
	if not (profile and replica) then
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return
	end

	local pointer, pathTable = GetPointer(path, profile)

	-- ⬇️ nowość: zainicjuj brakującą ścieżkę
	if pointer == nil then
		local default = (typeof(addValue) == "number") and 0 or {}
		ReconstructPath(player, path, default)
		pointer, pathTable = GetPointer(path, profile)
	end

	if typeof(addValue) == "table" and typeof(pointer) == "table" then
		for k, v in pairs(addValue) do
			if pointer[k] then warn("[DataManager]: value names are repeating!") else
				pointer[k] = v
				local _, childPath = GetPointer(path.."."..k, profile)
				replica:Set(childPath, v)
			end
		end
		DataManager:UpdateData(player)
		Debug(player)
		return
	end

	if typeof(pointer) == "number" and typeof(addValue) == "number" then
		local final = pointer + addValue
		-- (nie ma sensu robić `pointer = pointer + final`; wystarczy Set do repliki)
		replica:Set(pathTable, final)
		if pathTable[2] == "leaderstats" and not Settings.Experimental.CreateFolders then
			DataManager:Leaderstats(player)
		else
			DataManager:UpdateData(player)
		end
		Debug(player)
	else
		warn("[DataManager]: You can add only numbers!")
	end
end


--[[
	Substracts variable value
	[player]: which player you want to change the date
	[path]: path to variable (e.g. leaderstats.Coins)
	[subValue]: to which value it should be set 
]]
function DataManager:SubValue(player : Player, path : string, subValue : (number | {any?}))
	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
		local pointer, pathTable = GetPointer(path, profile)

		if typeof(subValue) == "table" and typeof(pointer) == "table" then
			for Index, Value in pairs(subValue) do
				if pointer[Value] == nil then
					warn("[DataManager]: Couldn't find value!")
					continue
				end

				local newPointer, newPathTable = GetPointer(path.."."..Value, profile)
				replica:Set(newPathTable, nil)
				pointer[Value] = nil
			end
			DataManager:UpdateData(player)
			Debug(player)
		else
			if typeof(pointer) == typeof(subValue) and typeof(pointer) == "number" then
				local targetNumber = pointer - subValue
				replica:Set(pathTable, targetNumber)
				pointer = targetNumber
				if pathTable[2] == "leaderstats" and not Settings.Experimental.CreateFolders then
					DataManager:Leaderstats(player)
				else
					DataManager:UpdateData(player)
				end

				Debug(player)
			else
				warn("[DataManager]: You can substract only numbers!")
			end
		end
	else
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return
	end
end

function DataManager:Clear(player : Player, path : string)
	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
		local pointer, pathTable = GetPointer(path, profile)
		if typeof(pointer) == "table" then
			pointer = {}
			replica:Set(pathTable, {})
		elseif typeof(pointer) ~= "table" then
			warn("[DataManager]: You can clear only tables (folders)!")
			return
		end
		DataManager:UpdateData(player)
		Debug(player)
	else
		warn("[DataManager]: Couldn't find profile or (/and) replica!")
		return
	end
end

--[[
	Reset player data
	[userId]: player user id
]]
function DataManager:ResetData(userId : number) : boolean
	return DataManager:MessageAsync(userId, {Key = "ResetData"})
end

--[[
	Update or create player leaderstats
	[player]: player you want to create/update leaderstats
]]
function DataManager:Leaderstats(player : Player)
	local playerProfile = DataManager:GetProfile(player)

	if playerProfile == nil then
		return
	end

	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder", player)
		folder.Name = "leaderstats"
	end

	if playerProfile.Data and playerProfile.Data.leaderstats then
		for index, value in pairs(playerProfile.Data.leaderstats) do
			local element = folder:FindFirstChild(index)
			if not element then
				element = Instance.new(CLASS_NAMES[typeof(value)], folder)
				element.Name = index
			end
			element.Value = value
		end
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

local function RecursiveUpdate(folder, data)
	for k, v in pairs(data) do
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
		if not v:IsA("Folder") or not v:IsA("NumberValue") or not v:IsA("StringValue") or not v:IsA("IntValue") or not v:IsA("BoolValue") then
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

function DataManager:UpdateData(player : Player)
	if Settings.Experimental.CreateFolders == false then return end

	local profile : typeof(Profiles[player]) = self:GetProfile(player)
	local replica: typeof(Replicas[player]) = self:GetReplica(player)
	if profile ~= nil and replica ~= nil then
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

function PlayerAdded(player: Player)
	-- Natychmiastowe tworzenie folderów z szablonu
	if Settings.Experimental.CreateFolders == true then
		for _, templateFolder in pairs(script.Data:GetChildren()) do
			if not player:FindFirstChild(templateFolder.Name) then
				templateFolder:Clone().Parent = player
			end
		end
	else
		-- Jeśli CreateFolders jest false, od razu tworzymy leaderstats
		local folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end

	-- Ładowanie profilu
	local profile = PlayerStore:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			player:Kick("Profile session end - Please rejoin!")
		end)

		if player.Parent == Players then
			Profiles[player] = profile
		else
			profile:EndSession()
		end

		if Replica.ReadyPlayers[player] ~= nil then
			NewReplicaPlayer(player)
		else
			while Replica.ReadyPlayers[player] == nil do
				if Replica.ReadyPlayers[player] ~= nil then
					break
				end
				task.wait()
			end
			NewReplicaPlayer(player)
		end

		AddNewGlobalPlayer(player)
		ListenToMessages(player)

		-- Aktualizacja danych po załadowaniu profilu
		if Settings.Experimental.CreateFolders == true then
			self:UpdateData(player)
		else
			self:Leaderstats(player)
		end
		DataManager:SetupBoostListeners(player)
	else
		player:Kick("Profile load fail - Please rejoin!")
	end
end

local PlayerDataStoreToken = Replica.Token("PlayerDataStore")

function NewReplicaPlayer(player: Player)
	local profile = self:GetProfile(player)
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
	replica:Subscribe(player)

	if player.Parent == Players then
		Replicas[player] = replica
	else
		replica:Unsubscribe()
		Replicas[player] = nil
	end
end

function PlayerRemoving(player: Player)
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
	if ProductFunctions[productId] == nil then
		warn("[DataManager]: No product function under id: ".. productId)
		return
	end

	MarketPlaceService:PromptProductPurchase(player, productId)
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
			if ProductFunctions[recieptInfo.ProductId] == nil then
				warn("[DataManager]: No product found under id: " .. recieptInfo.ProductId)
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

					local price, productName = GetProductPrice(recieptInfo.ProductId)
					if price > 0 then
						DataManager:AddValue(player, "TotalStats.RobuxSpent", price)
					end

					---------------------------------------------------------------
					--  ➤  oryginalna logika produktu
					---------------------------------------------------------------
					ProductFunctions[recieptInfo.ProductId](recieptInfo, player, profile, DataManager)

					---------------------------------------------------------------
					--  ➤  wrzuć ogłoszenie do kolejki MessagingService
					---------------------------------------------------------------
					EnqueuePurchaseAnnouncement(player, recieptInfo.ProductId, productName, price)
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


local function _getParentKeyAndPath(profile, path: string)
	local parts = path:split(".")
	local t = profile.Data
	local i = 1
	if parts[1] == "Data" then i = 2 end
	for idx = i, #parts - 1 do
		t[parts[idx]] = t[parts[idx]] or {}
		t = t[parts[idx]]
	end
	return t, parts[#parts], parts
end


function DataManager:AdjustValue(player: Player, path: string, delta: number)
	local profile = self:GetProfile(player)
	local replica = self:GetReplica(player)
	if not profile or not replica then return end

	-- upewnij się, że ścieżka istnieje i ma początkowo 0
	ReconstructPath(player, path, 0)

	-- znajdź rodzica i klucz końcowy, żeby zapisać do profile.Data
	local parent, leafKey, pathTable = _getParentKeyAndPath(profile, path)

	local current = parent[leafKey]
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
	replica:Set(pathTable, final)         -- aktualizacja repliki

	-- poprawne sprawdzenie, czy modyfikujemy leaderstats
	local rootKey = (pathTable[1] == "Data") and pathTable[2] or pathTable[1]
	if rootKey == "leaderstats" and not Settings.Experimental.CreateFolders then
		self:Leaderstats(player)
	else
		self:UpdateData(player)
	end

	Debug(player)
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

			local function dfs(tbl)
				for k, v in pairs(tbl) do
					if typeof(v) == "table" then
						dfs(v)
					elseif typeof(v) == "number" and type(k) == "string" and k:sub(-4) == "Time" then
						if v > 0 then
							local boostName = k:sub(1, #k - 4) -- obcina "Time"
							DataManager:ResumeBoost(player, boostName)
						end
					end
				end
			end
			dfs(profile.Data)
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


DataManager.init = function()
	FillMessageFunctions()
	CheckVersion()

	SetupAnnouncementSubscription()

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(PlayerAdded, player)
	end
	Players.PlayerAdded:Connect(PlayerAdded)
	Players.PlayerRemoving:Connect(PlayerRemoving)
	DataManager.Premades = Premades
  
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(PlayerRemoving, player)
		end
	end)
end


MarketPlaceService.ProcessReceipt = ProcessReceipt

return DataManager
