local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PremiumCrewStealConfig")
)

local Cooldowns = {}

local pairCooldowns = {}
local cooldownMap = nil

local function getPairKey(buyerUserId, victimUserId)
	return tostring(buyerUserId or "") .. ":" .. tostring(victimUserId or "")
end

local function nowSeconds(now)
	return math.floor(tonumber(now) or os.time())
end

local function getCooldownDuration()
	return math.max(0, math.floor(tonumber(Config.Cooldowns.BuyerVictimSeconds) or 0))
end

local function getMemoryStoreMap()
	if cooldownMap ~= nil then
		return cooldownMap, nil
	end

	local mapName = tostring(Config.Cooldowns.MemoryStoreName or "PremiumCrewStealCooldowns_v1")
	local ok, result = pcall(function()
		return MemoryStoreService:GetHashMap(mapName)
	end)
	if ok and result then
		cooldownMap = result
		return cooldownMap, nil
	end

	warn("[PremiumCrewStealCooldowns] MemoryStore cooldown persistence unavailable: " .. tostring(result))
	return nil, "cooldown_persistence_unavailable"
end

local function readPersistentExpiry(key)
	local map, mapReason = getMemoryStoreMap()
	if not map then
		return nil, mapReason or "cooldown_persistence_unavailable"
	end

	local ok, result = pcall(function()
		return map:GetAsync(key)
	end)
	if ok then
		return tonumber(result), nil
	end

	warn("[PremiumCrewStealCooldowns] MemoryStore cooldown read failed key=" .. tostring(key) .. " error=" .. tostring(result))
	return nil, "cooldown_persistence_unavailable"
end

local function verifyPersistentWrite(key, now)
	local map, mapReason = getMemoryStoreMap()
	if not map then
		return false, mapReason or "cooldown_persistence_unavailable"
	end

	local ok, err = pcall(function()
		map:SetAsync("verify:" .. tostring(key), nowSeconds(now), 60)
	end)
	if not ok then
		warn("[PremiumCrewStealCooldowns] MemoryStore cooldown verify write failed key=" .. tostring(key) .. " error=" .. tostring(err))
		return false, "cooldown_persistence_unavailable"
	end
	return true, nil
end

local function writePersistentExpiry(key, expiresAt)
	local duration = getCooldownDuration()
	if duration <= 0 then
		return true, nil
	end

	local map, mapReason = getMemoryStoreMap()
	if not map then
		return false, mapReason or "cooldown_persistence_unavailable"
	end

	local buffer = math.max(0, math.floor(tonumber(Config.Cooldowns.MemoryStoreExpiryBufferSeconds) or 60))
	local ttl = math.max(1, duration + buffer)
	local ok, err = pcall(function()
		map:SetAsync(key, expiresAt, ttl)
	end)
	if not ok then
		warn("[PremiumCrewStealCooldowns] MemoryStore cooldown write failed key=" .. tostring(key) .. " error=" .. tostring(err))
		return false, "cooldown_persistence_unavailable"
	end
	return true, nil
end

local function prune(now)
	now = nowSeconds(now)
	for key, expiresAt in pairs(pairCooldowns) do
		if (tonumber(expiresAt) or 0) <= now then
			pairCooldowns[key] = nil
		end
	end
end

function Cooldowns.CanSteal(buyerUserId, victimUserId, now)
	now = nowSeconds(now)
	prune(now)

	local key = getPairKey(buyerUserId, victimUserId)
	local expiresAt = tonumber(pairCooldowns[key]) or 0
	if expiresAt <= now then
		local persistentExpiry, persistentReason = readPersistentExpiry(key)
		if persistentReason then
			return false, persistentReason, 0
		end
		expiresAt = tonumber(persistentExpiry) or 0
		if expiresAt > now then
			pairCooldowns[key] = expiresAt
		end
	end
	if expiresAt > now then
		return false, "buyer_victim_cooldown", expiresAt - now
	end

	local writeOk, writeReason = verifyPersistentWrite(key, now)
	if writeOk ~= true then
		return false, writeReason or "cooldown_persistence_unavailable", 0
	end

	return true, nil, 0
end

function Cooldowns.MarkSteal(buyerUserId, victimUserId, now)
	now = nowSeconds(now)
	local duration = getCooldownDuration()
	if duration <= 0 then
		return true, nil
	end

	local key = getPairKey(buyerUserId, victimUserId)
	local expiresAt = now + duration
	local ok, reason = writePersistentExpiry(key, expiresAt)
	if ok ~= true then
		return false, reason or "cooldown_persistence_unavailable"
	end
	pairCooldowns[key] = expiresAt
	return true, nil
end

function Cooldowns.ClearPlayer(playerOrUserId)
	local userId = if typeof(playerOrUserId) == "Instance" then playerOrUserId.UserId else tonumber(playerOrUserId)
	if not userId then
		return
	end

	local prefix = tostring(userId) .. ":"
	local suffix = ":" .. tostring(userId)
	for key in pairs(pairCooldowns) do
		if string.sub(key, 1, #prefix) == prefix or string.sub(key, -#suffix) == suffix then
			pairCooldowns[key] = nil
		end
	end
end

return Cooldowns
