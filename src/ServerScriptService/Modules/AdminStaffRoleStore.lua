local DataStoreService = game:GetService("DataStoreService")

local AdminStaffRoleStore = {}

local STORE_NAME = "AdminStaffRolesV1"
local STORE_KEY = "RoleOverrides"

local ROLE_FIELDS = {
	Admin = {
		Added = "AdminsAdded",
		Removed = "AdminsRemoved",
	},
	SuperAdmin = {
		Added = "SuperAdminsAdded",
		Removed = "SuperAdminsRemoved",
	},
}

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
		AdminsAdded = {},
		AdminsRemoved = {},
		SuperAdminsAdded = {},
		SuperAdminsRemoved = {},
		UpdatedAt = 0,
		UpdatedBy = 0,
	}

	if typeof(value) ~= "table" then
		return state
	end

	state.AdminsAdded = normalizeSet(value.AdminsAdded)
	state.AdminsRemoved = normalizeSet(value.AdminsRemoved)
	state.SuperAdminsAdded = normalizeSet(value.SuperAdminsAdded)
	state.SuperAdminsRemoved = normalizeSet(value.SuperAdminsRemoved)
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

function AdminStaffRoleStore.Load()
	local store, storeError = getStore()
	if not store then
		local state = normalizeState(nil)
		state.Available = false
		state.Error = storeError
		warn("[AdminStaffRoleStore] DataStore unavailable: " .. tostring(storeError))
		return state
	end

	local ok, valueOrError = pcall(function()
		return store:GetAsync(STORE_KEY)
	end)

	if not ok then
		local state = normalizeState(nil)
		state.Available = false
		state.Error = tostring(valueOrError)
		warn("[AdminStaffRoleStore] Failed to load staff role overrides: " .. tostring(valueOrError))
		return state
	end

	local state = normalizeState(valueOrError)
	state.Available = true
	return state
end

function AdminStaffRoleStore.SetRole(roleName, userId, enabled, actorUserId)
	local fields = ROLE_FIELDS[tostring(roleName or "")]
	if fields == nil then
		return false, normalizeState(nil), "invalid_role"
	end

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
			local added = state[fields.Added]
			local removed = state[fields.Removed]

			if enabled == true then
				added[key] = true
				removed[key] = nil
			else
				added[key] = nil
				removed[key] = true
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

return AdminStaffRoleStore
