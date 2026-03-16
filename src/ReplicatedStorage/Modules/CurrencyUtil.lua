local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))

local CurrencyUtil = {}

local Primary = Economy.Currency.Primary

local function isNumericValueObject(value)
	return value
		and value:IsA("ValueBase")
		and typeof(value.Value) == "number"
end

local function findStrictPrimaryValueObject(player: Player)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	local value = leaderstats:FindFirstChild(Primary.Key)
	if isNumericValueObject(value) then
		return value
	end

	return nil
end

local function findLegacyValueObject(player: Player)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	local value = leaderstats:FindFirstChild(Primary.LegacyKeys.Leaderstat)
		or leaderstats:FindFirstChild(Primary.LegacyKeys.LeaderstatTypo)

	if isNumericValueObject(value) then
		return value
	end

	return nil
end

function CurrencyUtil.getConfig()
	return Primary
end

function CurrencyUtil.getPrimaryLeaderstatName()
	return Primary.Key
end

function CurrencyUtil.getPrimaryPath()
	return Primary.Path
end

function CurrencyUtil.getTotalPath()
	return Primary.TotalPath
end

function CurrencyUtil.getCompactSuffix()
	return " " .. Primary.ShortLabel
end

function CurrencyUtil.getPerSecondSuffix()
	return CurrencyUtil.getCompactSuffix() .. "/s"
end

function CurrencyUtil.findPrimaryValueObject(player: Player): NumberValue?
	return findStrictPrimaryValueObject(player) or findLegacyValueObject(player)
end

function CurrencyUtil.waitForPrimaryValueObject(player: Player, timeout: number?): NumberValue?
	local leaderstats = player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats", timeout)
	if not leaderstats then
		return nil
	end

	local existingPrimary = findStrictPrimaryValueObject(player)
	if existingPrimary then
		return existingPrimary
	end

	local value = leaderstats:WaitForChild(Primary.Key, timeout)

	if isNumericValueObject(value) then
		return value
	end

	return findLegacyValueObject(player)
end

function CurrencyUtil.formatCompact(amount: number): string
	local rounded = math.floor((tonumber(amount) or 0) + 0.5)
	return tostring(rounded) .. CurrencyUtil.getCompactSuffix()
end

function CurrencyUtil.formatPerSecond(amount: number): string
	local rounded = math.floor((tonumber(amount) or 0) + 0.5)
	return tostring(rounded) .. CurrencyUtil.getPerSecondSuffix()
end

return CurrencyUtil
