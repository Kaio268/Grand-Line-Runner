local CrewMembers = require(script.Parent.Parent:WaitForChild("Crew"):WaitForChild("CrewMembers"))

local RandomCrewReward = {}

local HASH_MOD = 2147483647

local function getRandomCrewRarity(rewardData)
	if typeof(rewardData) ~= "table" then
		return nil
	end

	if rewardData.RandomCrewMember == true
		or rewardData.RandomCrew == true
		or rewardData.RandomCrewRarity ~= nil
		or rewardData.CrewRarity ~= nil
	then
		return tostring(rewardData.RandomCrewRarity or rewardData.CrewRarity or rewardData.Rarity or "Rare")
	end

	return nil
end

local function hashNumber(accumulator, value)
	local numberValue = math.abs(math.floor(tonumber(value) or 0))
	if numberValue == 0 then
		return (accumulator * 33) % HASH_MOD
	end

	while numberValue > 0 do
		accumulator = (accumulator * 33 + (numberValue % 10)) % HASH_MOD
		numberValue = math.floor(numberValue / 10)
	end

	return accumulator
end

local function hashString(accumulator, value)
	local text = tostring(value or "")
	for index = 1, #text do
		accumulator = (accumulator * 33 + string.byte(text, index)) % HASH_MOD
	end
	return accumulator
end

local function stableHash(...)
	local accumulator = 5381
	for _, value in ipairs({ ... }) do
		if typeof(value) == "number" then
			accumulator = hashNumber(accumulator, value)
		else
			accumulator = hashString(accumulator, value)
		end
		accumulator = (accumulator * 33 + 124) % HASH_MOD
	end
	return accumulator
end

local function getUserId(playerOrUserId)
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return tonumber(playerOrUserId.UserId) or 0
	end

	return tonumber(playerOrUserId) or 0
end

function RandomCrewReward.IsRandomCrewRewardData(rewardData): boolean
	return getRandomCrewRarity(rewardData) ~= nil
end

function RandomCrewReward.GetRarity(rewardData): string
	return getRandomCrewRarity(rewardData) or "Rare"
end

function RandomCrewReward.GetDisplayName(rewardData): string
	return string.format("Random %s Crewmate", RandomCrewReward.GetRarity(rewardData))
end

function RandomCrewReward.GetPoolForRarity(rarityName)
	local normalizedRarity = tostring(rarityName or "Rare")
	local pool = {}

	for _, entry in ipairs(CrewMembers.GetEntries()) do
		if tostring(entry.Rarity or "") == normalizedRarity then
			table.insert(pool, entry)
		end
	end

	return pool
end

function RandomCrewReward.ChooseForPlayer(playerOrUserId, rewardId, cycleStartPlayTime, rewardData)
	local rarity = RandomCrewReward.GetRarity(rewardData)
	local pool = RandomCrewReward.GetPoolForRarity(rarity)
	if #pool <= 0 then
		return nil
	end

	local seed = stableHash(getUserId(playerOrUserId), tonumber(rewardId) or 0, tonumber(cycleStartPlayTime) or 0, rarity)
	local index = (seed % #pool) + 1
	return table.clone(pool[index]), index, #pool
end

function RandomCrewReward.BuildPreviewInfo(playerOrUserId, rewardId, cycleStartPlayTime, rewardData)
	local rarity = RandomCrewReward.GetRarity(rewardData)
	local displayName = RandomCrewReward.GetDisplayName(rewardData)

	if playerOrUserId == nil or cycleStartPlayTime == nil then
		return {
			Resolved = false,
			DisplayName = displayName,
			BaseDisplayName = displayName,
			Rarity = rarity,
			Reason = "missing_player_context",
		}
	end

	local entry = RandomCrewReward.ChooseForPlayer(playerOrUserId, rewardId, cycleStartPlayTime, rewardData)
	if not entry then
		return {
			Resolved = false,
			DisplayName = displayName,
			BaseDisplayName = displayName,
			Rarity = rarity,
			Reason = "empty_random_crew_pool",
		}
	end

	return {
		Resolved = true,
		DisplayName = tostring(entry.DisplayName or entry.CrewMemberId or displayName),
		BaseDisplayName = tostring(entry.DisplayName or entry.CrewMemberId or displayName),
		CrewMemberId = tostring(entry.CrewMemberId or ""),
		GrantName = tostring(entry.LegacyId or entry.CrewMemberId or ""),
		LegacyId = tostring(entry.LegacyId or ""),
		ModelName = entry.ModelName,
		Rarity = tostring(entry.Rarity or rarity),
		Entry = table.clone(entry),
	}
end

return RandomCrewReward
