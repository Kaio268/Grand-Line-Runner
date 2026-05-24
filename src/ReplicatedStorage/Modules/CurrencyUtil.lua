local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local Shorten = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shorten"))

local CurrencyUtil = {}

local Primary = Economy.Currency.Primary
local LegacyKeys = Primary.LegacyKeys or {}

local LEGACY_LEADERSTAT_NAMES = {
	LegacyKeys.Leaderstat,
	LegacyKeys.LeaderstatMoney,
	LegacyKeys.LeaderstatTypo,
}

local LEGACY_TOTAL_NAMES = {
	LegacyKeys.Total,
	LegacyKeys.TotalMoney,
}

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

	for _, legacyName in ipairs(LEGACY_LEADERSTAT_NAMES) do
		if typeof(legacyName) == "string" and legacyName ~= "" then
			local value = leaderstats:FindFirstChild(legacyName)
			if isNumericValueObject(value) then
				return value
			end
		end
	end

	return nil
end

local function formatWholeCommaNumber(amount: number): string
	local number = tonumber(amount) or 0
	local sign = if number < 0 then "-" else ""
	local roundedText = tostring(math.floor(math.abs(number) + 0.5))
	local reversed = string.reverse(roundedText)
	local grouped = string.reverse((string.gsub(reversed, "(%d%d%d)", "%1,")))

	grouped = string.gsub(grouped, "^,", "")
	return sign .. grouped
end

local function roundWholeNumber(amount: number): number
	local number = tonumber(amount) or 0
	if number < 0 then
		return -math.floor(math.abs(number) + 0.5)
	end

	return math.floor(number + 0.5)
end

function CurrencyUtil.getConfig()
	return Primary
end

function CurrencyUtil.getPrimaryLeaderstatName()
	return Primary.Key
end

function CurrencyUtil.getDisplayName()
	return tostring(Primary.DisplayName or Primary.Key or "Beli")
end

function CurrencyUtil.getPrimaryPath()
	return Primary.Path
end

function CurrencyUtil.getTotalPath()
	return Primary.TotalPath
end

function CurrencyUtil.getCompactSuffix()
	return " " .. tostring(Primary.ShortLabel or CurrencyUtil.getDisplayName())
end

function CurrencyUtil.getPerSecondSuffix()
	return CurrencyUtil.getCompactSuffix() .. "/s"
end

function CurrencyUtil.getLegacyLeaderstatNames()
	return table.clone(LEGACY_LEADERSTAT_NAMES)
end

function CurrencyUtil.getLegacyTotalStatNames()
	return table.clone(LEGACY_TOTAL_NAMES)
end

function CurrencyUtil.getAmountFromTable(source)
	if typeof(source) ~= "table" then
		return 0
	end

	local direct = tonumber(source[Primary.Key])
	if direct ~= nil then
		return direct
	end

	for _, legacyName in ipairs(LEGACY_LEADERSTAT_NAMES) do
		local value = if typeof(legacyName) == "string" then tonumber(source[legacyName]) else nil
		if value ~= nil then
			return value
		end
	end

	return 0
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

function CurrencyUtil.formatCompactNumber(amount: number): string
	local rounded = roundWholeNumber(amount)
	if rounded < 0 then
		return "-" .. Shorten.roundNumber(math.abs(rounded))
	end

	return Shorten.roundNumber(rounded)
end

function CurrencyUtil.formatCount(amount: number): string
	return CurrencyUtil.formatCompactNumber(amount)
end

function CurrencyUtil.formatCurrency(amount: number): string
	return CurrencyUtil.formatCompactNumber(amount) .. CurrencyUtil.getCompactSuffix()
end

function CurrencyUtil.formatCurrencyPerSecond(amount: number): string
	return CurrencyUtil.formatCompactNumber(amount) .. CurrencyUtil.getPerSecondSuffix()
end

function CurrencyUtil.formatCompact(amount: number): string
	return CurrencyUtil.formatCurrency(amount)
end

function CurrencyUtil.formatPerSecond(amount: number): string
	return CurrencyUtil.formatCurrencyPerSecond(amount)
end

function CurrencyUtil.formatAmount(amount: number): string
	return CurrencyUtil.formatCurrency(amount)
end

function CurrencyUtil.formatIncomeNumber(amount: number): string
	return CurrencyUtil.formatCompactNumber(amount)
end

function CurrencyUtil.formatIncomeExact(amount: number): string
	return formatWholeCommaNumber(amount)
end

function CurrencyUtil.formatIncomeExactAmount(amount: number): string
	return CurrencyUtil.formatIncomeExact(amount) .. CurrencyUtil.getCompactSuffix()
end

function CurrencyUtil.formatIncomeExactPerSecond(amount: number): string
	return CurrencyUtil.formatIncomeExact(amount) .. CurrencyUtil.getPerSecondSuffix()
end

function CurrencyUtil.formatIncomeCompact(amount: number): string
	return CurrencyUtil.formatCurrency(amount)
end

function CurrencyUtil.formatIncomeCompactAmount(amount: number): string
	return CurrencyUtil.formatIncomeCompact(amount)
end

function CurrencyUtil.formatIncomePerSecond(amount: number): string
	return CurrencyUtil.formatCurrencyPerSecond(amount)
end

function CurrencyUtil.formatIncomeCompactPerSecond(amount: number): string
	return CurrencyUtil.formatIncomePerSecond(amount)
end

function CurrencyUtil.formatMultiplier(multiplier: number): string
	local numeric = tonumber(multiplier) or 1
	if numeric == math.floor(numeric) then
		return string.format("%dx %s", numeric, CurrencyUtil.getDisplayName())
	end

	return string.format("%.1fx %s", numeric, CurrencyUtil.getDisplayName())
end

return CurrencyUtil
