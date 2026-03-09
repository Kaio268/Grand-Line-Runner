--[[
It wasn't writed to support big amounts of data, so be aware that this module
can (and propably) contain bugs.
]]

--// Services
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")

--// Variables
local MAX_RETRIES = 10
local RETRY_TIME = 0.1

--// Global Store
local GlobalStore = {}
GlobalStore.__index = GlobalStore

local function DeepCopyTable(t)
	local copy = {}
	for key, value in pairs(t) do
		if type(value) == "table" then
			copy[key] = DeepCopyTable(value)
		else
			copy[key] = value
		end
	end
	return copy
end

local function ReconcileTable(target : {any}, t : {any})
	for k, v in pairs(t) do
		if target[k] == nil then
			if type(v) ==  "table" then
				target[k] = DeepCopyTable(v)
			else
				target[k] = v
			end
			target[k] = v
		elseif type(target[k]) == "table" and type(v) == "table" then
			ReconcileTable(target[k], v)
		end
	end
end

local function GetAsync(data_store : DataStore, key : string, _return)
	local success, value = pcall(function()
		return data_store:GetAsync(key)
	end)
	
	if success then
		if value == nil then return _return end
		return value
	else
		return _return
	end
end

local function SetAsync(data_store : DataStore, key : string, value)
	local success = pcall(function()
		return data_store:SetAsync(key, value)
	end)
	
	if success then
		return true
	else
		return false
	end
end

function GlobalStore.New(key: string, template : {any})
	local data_store = DataStoreService:GetDataStore(key)
	local template_store = DataStoreService:GetDataStore("__GS__"..key)
	
	local self = {
		data_store = data_store,
		data = {},
		template = {},
		unix_timestamp = os.time()
	}
	setmetatable(self, GlobalStore)
	
	local stored_template = GetAsync(template_store, "template", {})
	ReconcileTable(stored_template, template)
	SetAsync(template_store, "template", stored_template)
	ReconcileTable(self.template, stored_template)
	
	local unix_timestamp = GetAsync(template_store, "unix_timestamp", nil)
	if unix_timestamp == nil  then
		SetAsync(template_store, "unix_timestamp", os.time())
		unix_timestamp = GetAsync(template_store, "unix_timestamp", os.time())
	end
	self.unix_timestamp = unix_timestamp

	for k, v in pairs(self.template) do
		local value = self:Get(k, true) or nil
		if value == nil then
			self:Set(k, v, true)
			value = self:Get(k) or v
		end
		
		self.data[k] = value
	end
	
	return self
end

function GlobalStore:Set(key, value, dontWarn : boolean?)
	local succed = false
	
	local try_num = 0
	while not succed do
		local success = pcall(function()
			self.data_store:SetAsync(key, value)
		end)

		try_num += 1
		if try_num >= MAX_RETRIES then
			if dontWarn ~= true then
				warn("[GlobalStore]: Failed to SetAsync from Data Store | key: "..key.." | value: ".. tostring(nil))
				warn(value)	
			end
			break 
		end

		if success then
			self.data[key] = value
			break
		end
		
		task.wait(RETRY_TIME)
	end
	
	return self
end

function GlobalStore:Get(key, dontWarn : boolean?)
	if self.data[key] then return self.data[key] end
	local succed = false
	local val = nil

	local try_num = 0
	while not succed do
		local success, value = pcall(function()
			return self.data_store:GetAsync(key)
		end)
		
		try_num += 1
		if try_num >= MAX_RETRIES  then 
			if dontWarn ~= true then
				warn("[GlobalStore]: Failed to GetAsync from Data Store | key: "..key)
				warn(value)	
			end
			break 
		end

		if success then
			self.data[key] = value
			val = value
			break
		end
		
		task.wait(RETRY_TIME)
	end
	
	return val
end

return GlobalStore
