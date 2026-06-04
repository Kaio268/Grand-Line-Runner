local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ItemIconRegistry = require(Modules:WaitForChild("Configs"):WaitForChild("ItemIconRegistry"))
local CrewPreviewImages = require(Modules:WaitForChild("Crew"):WaitForChild("CrewPreviewImages"))

local RewardIconResolver = {}

local BOOST_IDENTIFIER_BY_KEY = {
	moneyboost = "MoneyBoost",
	beliboost = "MoneyBoost",
	x2money = "MoneyBoost",
	x2moneytime = "MoneyBoost",
	potionsx2moneytime = "MoneyBoost",
	speedboost = "SpeedBoost",
	walkspeedboost = "SpeedBoost",
	x15walkspeed = "SpeedBoost",
	x15walkspeedtime = "SpeedBoost",
	potionsx15walkspeedtime = "SpeedBoost",
	luckboost = "LuckBoost",
	xluck = "LuckBoost",
	xlucktime = "LuckBoost",
	potionsxlucktime = "LuckBoost",
	moneymult = "MoneyBoost",
	multipliersmoneymult = "MoneyBoost",
}

local REWARD_NAME_FIELDS = {
	"DisplayName",
	"displayName",
	"RewardName",
	"rewardName",
	"Name",
	"name",
	"ItemName",
	"itemName",
	"Key",
	"key",
}

local REWARD_ICON_FIELDS = {
	"Icon",
	"icon",
	"Image",
	"image",
	"PreviewImage",
	"previewImage",
	"StaticPreviewImage",
	"staticPreviewImage",
}

local REWARD_PATH_FIELDS = {
	"Path",
	"path",
	"FullPath",
	"fullPath",
	"Id",
	"id",
}

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeKey(value)
	local text = trim(value)
	text = text:gsub("%s+", "")
	text = text:gsub("[_%-%.]", "")
	return string.lower(text)
end

local function hasIcon(value)
	return typeof(value) == "string" and value ~= ""
end

local function readFirstString(source, fields)
	if typeof(source) ~= "table" then
		return ""
	end

	for _, field in ipairs(fields) do
		local value = source[field]
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end

	return ""
end

local function getExplicitIcon(reward)
	if typeof(reward) == "table" then
		local icon = readFirstString(reward, REWARD_ICON_FIELDS)
		if icon ~= "" then
			return icon
		end
		if typeof(reward[2]) == "string" then
			return reward[2]
		end
	end

	return ""
end

local function getNameCandidate(reward)
	if typeof(reward) == "table" then
		if typeof(reward[1]) == "string" and reward[1] ~= "" then
			return reward[1]
		end

		local named = readFirstString(reward, REWARD_NAME_FIELDS)
		if named ~= "" then
			return named
		end
	elseif typeof(reward) == "string" then
		return reward
	end

	return ""
end

local function getPathCandidate(reward)
	if typeof(reward) ~= "table" then
		return ""
	end

	return readFirstString(reward, REWARD_PATH_FIELDS)
end

local function stripAmountPrefix(text)
	local value = trim(text)
	value = value:gsub("^%+%s*", "")
	value = value:gsub("^%d[%d,%.]*%s*[xX]%s+", "")
	value = value:gsub("^%d[%d,%.]*%s+", "")
	return trim(value)
end

local function inferChestIdentifier(text)
	local lowerText = string.lower(text)
	if lowerText:find("devil%s*fruit%s*chest") then
		for _, rarity in ipairs({ "Common", "Rare", "Legendary", "Mythic" }) do
			if lowerText:find(string.lower(rarity), 1, true) then
				return rarity .. " Devil Fruit Chest"
			end
		end
		return "Devil Fruit Chest"
	end

	if lowerText:find("supply%s*chest") then
		return "Supply Chest"
	elseif lowerText:find("wooden%s*chest") or lowerText:find("wood%s*chest") then
		return "Wooden Chest"
	elseif lowerText:find("iron%s*chest") then
		return "Iron Chest"
	elseif lowerText:find("gold%s*chest") or lowerText:find("golden%s*chest") then
		return "Gold Chest"
	end

	return ""
end

local function inferBoostIdentifier(text)
	local key = normalizeKey(text)
	local direct = BOOST_IDENTIFIER_BY_KEY[key]
	if direct then
		return direct
	end

	local lowerText = string.lower(text)
	if lowerText:find("speed") or lowerText:find("walkspeed") then
		return "SpeedBoost"
	elseif lowerText:find("luck") then
		return "LuckBoost"
	elseif lowerText:find("money%s*boost") or lowerText:find("beli%s*boost") or lowerText:find("2x%s*beli") then
		return "MoneyBoost"
	end

	return ""
end

local function inferResourceIdentifier(text)
	local lowerText = string.lower(text)
	if lowerText:find("sea%s*beast%s*meat") then
		return "Sea Beast Meat"
	elseif lowerText:find("ancient%s*timber") then
		return "Ancient Timber"
	elseif lowerText:find("timber") then
		return "Timber"
	elseif lowerText:find("iron") then
		return "Iron"
	elseif lowerText:find("apple") then
		return "Apple"
	elseif lowerText:find("rice") then
		return "Rice"
	elseif lowerText:find("meat") then
		return "Meat"
	elseif lowerText:find("beli") or lowerText:find("doubloon") or lowerText:find("money") then
		return "Beli"
	end

	return ""
end

local function inferIdentifierFromPath(path)
	local pathText = trim(path)
	if pathText == "" then
		return ""
	end

	local boostIdentifier = inferBoostIdentifier(pathText)
	if boostIdentifier ~= "" then
		return boostIdentifier
	end

	local key = normalizeKey(pathText)
	if key:find("leaderstatsbeli", 1, true) or key:find("totalstatstotalbeli", 1, true) then
		return "Beli"
	end

	local finalSegment = pathText:match("([^%.]+)$") or pathText
	return trim(finalSegment)
end

local function inferIdentifierFromText(text)
	local value = stripAmountPrefix(text)
	if value == "" then
		return ""
	end

	local chestIdentifier = inferChestIdentifier(value)
	if chestIdentifier ~= "" then
		return chestIdentifier
	end

	local boostIdentifier = inferBoostIdentifier(value)
	if boostIdentifier ~= "" then
		return boostIdentifier
	end

	local resourceIdentifier = inferResourceIdentifier(value)
	if resourceIdentifier ~= "" then
		return resourceIdentifier
	end

	return value
end

local function inferIdentifierFromTable(reward)
	local rewardType = string.lower(tostring(reward.Type or reward.type or reward.RewardType or reward.rewardType or reward.Kind or reward.kind or ""))
	if rewardType == "currency" or rewardType == "beli" then
		return "Beli"
	elseif rewardType == "food" or rewardType == "material" or rewardType == "resource" then
		return tostring(reward.Key or reward.key or reward.Name or reward.name or "")
	elseif rewardType == "boost" or rewardType == "potion" then
		return inferBoostIdentifier(getNameCandidate(reward))
	elseif rewardType == "devilfruit" or rewardType == "devil_fruit" then
		return "Devil Fruit"
	elseif rewardType == "chest" then
		local chestKind = tostring(reward.ChestKind or reward.chestKind or "")
		local fruitRarity = tostring(reward.FruitRarity or reward.fruitRarity or reward.Rarity or reward.rarity or "")
		if chestKind == "DevilFruit" or fruitRarity ~= "" then
			return (fruitRarity ~= "" and fruitRarity or "Common") .. " Devil Fruit Chest"
		end

		local tier = tostring(reward.Tier or reward.tier or reward.ChestTier or reward.chestTier or "")
		if tier ~= "" then
			return tier .. " Chest"
		end
	end

	local pathIdentifier = inferIdentifierFromPath(getPathCandidate(reward))
	if pathIdentifier ~= "" then
		return pathIdentifier
	end

	return inferIdentifierFromText(getNameCandidate(reward))
end

local function isCrewReward(reward, identifier)
	if typeof(reward) == "table" then
		local rewardType = string.lower(tostring(reward.Type or reward.type or reward.RewardType or reward.rewardType or reward.Kind or reward.kind or ""))
		if rewardType:find("crew", 1, true) then
			return true
		end
		if tostring(reward.CrewMemberId or reward.crewMemberId or reward.CrewRewardName or reward.crewRewardName or "") ~= "" then
			return true
		end
	end

	return CrewPreviewImages.Has({
		DisplayName = identifier,
		Name = identifier,
		CrewMemberName = identifier,
	})
end

local function resolveCrewIcon(reward, identifier)
	if identifier == "" then
		return ""
	end

	local icon = CrewPreviewImages.Resolve(reward, {
		DisplayName = identifier,
		Name = identifier,
		CrewMemberName = identifier,
	})
	return tostring(icon or "")
end

local function copyResolved(displayName, icon, category)
	local fallback = ItemIconRegistry.Resolve("FallbackReward")
	local resolvedDisplay = if displayName ~= "" then displayName else fallback.DisplayName
	local resolvedIcon = if hasIcon(icon) then icon else fallback.Icon
	local resolvedCategory = if tostring(category or "") ~= "" then tostring(category) else fallback.Category

	return {
		DisplayName = resolvedDisplay,
		displayName = resolvedDisplay,
		Icon = resolvedIcon,
		icon = resolvedIcon,
		Category = resolvedCategory,
		category = resolvedCategory,
	}
end

function RewardIconResolver.Resolve(reward, fallbackIcon)
	local explicitIcon = getExplicitIcon(reward)
	local displayName = trim(getNameCandidate(reward))
	local identifier = if typeof(reward) == "table" then inferIdentifierFromTable(reward) else inferIdentifierFromText(displayName)
	identifier = trim(identifier)

	if hasIcon(explicitIcon) then
		return copyResolved(displayName ~= "" and displayName or identifier, explicitIcon, "Reward")
	end

	if identifier ~= "" and isCrewReward(reward, identifier) then
		local crewIcon = resolveCrewIcon(reward, identifier)
		if hasIcon(crewIcon) then
			return copyResolved(displayName ~= "" and displayName or identifier, crewIcon, "Crew")
		end
	end

	local record = ItemIconRegistry.Resolve(identifier)
	if record.Key ~= "FallbackReward" then
		return copyResolved(
			displayName ~= "" and displayName or record.DisplayName,
			record.Icon,
			record.Category
		)
	end

	if hasIcon(fallbackIcon) then
		return copyResolved(displayName ~= "" and displayName or identifier, fallbackIcon, "Reward")
	end

	return copyResolved(displayName ~= "" and displayName or identifier, record.Icon, record.Category)
end

function RewardIconResolver.GetIcon(reward, fallbackIcon)
	return RewardIconResolver.Resolve(reward, fallbackIcon).icon
end

function RewardIconResolver.GetDisplayName(reward, fallbackName)
	local resolved = RewardIconResolver.Resolve(reward)
	local resolvedDisplayName = tostring(resolved.displayName or "")
	if resolvedDisplayName ~= "" and resolvedDisplayName ~= "Reward" then
		return resolved.displayName
	end
	if fallbackName ~= nil and tostring(fallbackName) ~= "" then
		return tostring(fallbackName)
	end
	return resolvedDisplayName
end

return RewardIconResolver
