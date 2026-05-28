local DataStoreService = game:GetService("DataStoreService")

local TesterRoleStore = {}

local STORE_NAME = "AdminTesterRolesV1"
local STORE_KEY = "TesterOverrides"

local function normalizeUserId(userId)
	local numericUserId = tonumber(userId)
	if numericUserId == nil then
		return nil
	end

	numericUserId = math.floor(numericUserId)
	if numericUserId <= 0 then
		return nil
	end

	return numericUserId
end

local function normalizeSet(value)
	local result = {}
	if typeof(value) ~= "table" then
		return result
	end

	for userId, enabled in pairs(value) do
		local numericUserId = normalizeUserId(userId)
		if numericUserId ~= nil and enabled == true then
			result[tostring(numericUserId)] = true
		end
	end

	return result
end

local function normalizeState(value)
	local state = {
		Added = {},
		Removed = {},
		UpdatedAt = 0,
		UpdatedBy = 0,
	}

	if typeof(value) ~= "table" then
		return state
	end

	state.Added = normalizeSet(value.Added)
	state.Removed = normalizeSet(value.Removed)
	state.UpdatedAt = math.floor(tonumber(value.UpdatedAt) or 0)
	state.UpdatedBy = math.floor(tonumber(value.UpdatedBy) or 0)

	return state
end

local function getStore()
	local ok, storeOrError = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if ok then
		return storeOrError, nil
	end

	return nil, tostring(storeOrError)
end

function TesterRoleStore.Load()
	local store, storeError = getStore()
	if not store then
		local state = normalizeState(nil)
		state.Available = false
		state.Error = storeError
		warn("[TesterRoleStore] DataStore unavailable: " .. tostring(storeError))
		return state
	end

	local ok, valueOrError = pcall(function()
		return store:GetAsync(STORE_KEY)
	end)

	if not ok then
		local state = normalizeState(nil)
		state.Available = false
		state.Error = tostring(valueOrError)
		warn("[TesterRoleStore] Failed to load tester role overrides: " .. tostring(valueOrError))
		return state
	end

	local state = normalizeState(valueOrError)
	state.Available = true
	return state
end

function TesterRoleStore.SetTester(userId, enabled, actorUserId)
	local numericUserId = normalizeUserId(userId)
	local numericActorUserId = normalizeUserId(actorUserId) or 0
	if numericUserId == nil then
		return false, normalizeState(nil), "invalid_user_id"
	end

	local store, storeError = getStore()
	if not store then
		return false, normalizeState(nil), storeError or "store_unavailable"
	end

	local ok, stateOrError = pcall(function()
		return store:UpdateAsync(STORE_KEY, function(currentValue)
			local state = normalizeState(currentValue)
			local key = tostring(numericUserId)

			if enabled == true then
				state.Added[key] = true
				state.Removed[key] = nil
			else
				state.Added[key] = nil
				state.Removed[key] = true
			end

			state.UpdatedAt = os.time()
			state.UpdatedBy = numericActorUserId
			return state
		end)
	end)

	if not ok then
		return false, normalizeState(nil), tostring(stateOrError)
	end

	local state = normalizeState(stateOrError)
	state.Available = true
	return true, state, nil
end

return TesterRoleStore
