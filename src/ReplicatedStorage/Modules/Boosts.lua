local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BoostReader = {}
BoostReader.__index = BoostReader

 local TIME_SUFFIX = "Time"  
local SCAN_COOLDOWN = 0.25   

 local cache = {
	-- [userId] = {
	--   lastScan = os.clock(),
	--   timeRefs = { ["x2MoneyTime"] = NumberValue, ... },
	--   boolRefs = { ["x2Money"] = BoolValue, ... },
	-- }
}

local function getSubjectPlayer(optionalPlayer: Player?)
	if RunService:IsClient() then
		return optionalPlayer or Players.LocalPlayer
	else
		return optionalPlayer
	end
end

local function ensureBucket(userId: number)
	cache[userId] = cache[userId] or { lastScan = 0, timeRefs = {}, boolRefs = {} }
	return cache[userId]
end

local function isAlive(inst: Instance?)
	return inst and inst.Parent ~= nil
end

 local function rescanPlayerTree(player: Player)
	local bucket = ensureBucket(player.UserId)
	bucket.timeRefs = {}
	bucket.boolRefs = {}

	for _, d in ipairs(player:GetDescendants()) do
		if d:IsA("NumberValue") then
 			if #d.Name > #TIME_SUFFIX and d.Name:sub(-#TIME_SUFFIX) == TIME_SUFFIX then
				bucket.timeRefs[d.Name] = d
			end
		elseif d:IsA("BoolValue") then
			bucket.boolRefs[d.Name] = d
		end
	end

	bucket.lastScan = os.clock()
end

local function getTimeValue(player: Player, timeName: string): NumberValue?
	local bucket = ensureBucket(player.UserId)
 	local ref = bucket.timeRefs[timeName]
	if not isAlive(ref) then
 		if os.clock() - bucket.lastScan >= SCAN_COOLDOWN then
			rescanPlayerTree(player)
			ref = bucket.timeRefs[timeName]
		else
			ref = nil
		end
	end
	return ref
end

local function getBoolValue(player: Player, name: string): BoolValue?
	local bucket = ensureBucket(player.UserId)
	local ref = bucket.boolRefs[name]
	if not isAlive(ref) then
		if os.clock() - bucket.lastScan >= SCAN_COOLDOWN then
			rescanPlayerTree(player)
			ref = bucket.boolRefs[name]
		else
			ref = nil
		end
	end
	return ref
end

 
function BoostReader:IsActive(boostName: string, player: Player?)
	local plr = getSubjectPlayer(player)
	if not plr then return false end

 	local timeRef = getTimeValue(plr, boostName .. TIME_SUFFIX)
	if timeRef and timeRef.Value and timeRef.Value > 0 then
		return true
	end

 	local boolRef = getBoolValue(plr, boostName)
	if boolRef and boolRef.Value == true then
		return true
	end

 	if os.clock() - ensureBucket(plr.UserId).lastScan >= SCAN_COOLDOWN then
		rescanPlayerTree(plr)
		timeRef = getTimeValue(plr, boostName .. TIME_SUFFIX)
		if timeRef and timeRef.Value > 0 then return true end
		boolRef = getBoolValue(plr, boostName)
		if boolRef and boolRef.Value == true then return true end
	end

	return false
end

 
function BoostReader:GetRemainingTime(boostName: string, player: Player?)
	local plr = getSubjectPlayer(player)
	if not plr then return 0 end
	local timeRef = getTimeValue(plr, boostName .. TIME_SUFFIX)
	if timeRef and timeRef.Value then
		return math.max(0, timeRef.Value)
	end
	return 0
end

 function BoostReader:GetBoost(boostName: string, multiplier: number, player: Player?)
	if typeof(multiplier) ~= "number" then multiplier = 1 end
	return self:IsActive(boostName, player) and multiplier or 1
end

 if RunService:IsClient() then
	local lp = Players.LocalPlayer
	if lp then
 		task.defer(function()
			rescanPlayerTree(lp)
		end)

 		lp.DescendantAdded:Connect(function()
			local bucket = ensureBucket(lp.UserId)
			if os.clock() - bucket.lastScan >= SCAN_COOLDOWN then
				rescanPlayerTree(lp)
			end
		end)
		lp.DescendantRemoving:Connect(function()
			local bucket = ensureBucket(lp.UserId)
			if os.clock() - bucket.lastScan >= SCAN_COOLDOWN then
				rescanPlayerTree(lp)
			end
		end)
	end
end

function BoostReader:GetCombined(list, player)
	local total = 1
	for name, base in pairs(list) do
		total *= self:GetBoost(name, base, player)
	end
	return total
end

return setmetatable({}, BoostReader)