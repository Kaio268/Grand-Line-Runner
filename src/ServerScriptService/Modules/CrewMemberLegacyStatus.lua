local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local CrewMemberLegacyFallbackTelemetry = require(script.Parent:WaitForChild("CrewMemberLegacyFallbackTelemetry"))
local CrewMigrationPlanner = require(script.Parent:WaitForChild("CrewMigrationPlanner"))
local CrewStorage = require(script.Parent:WaitForChild("CrewStorage"))
local dataManagerModule = nil
local function getDataManager()
	if dataManagerModule == nil then
		dataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerModule
end
local DataManager = setmetatable({}, {
	__index = function(_, key)
		local value = getDataManager()[key]
		if typeof(value) == "function" then
			return function(_, ...)
				return value(getDataManager(), ...)
			end
		end
		return value
	end,
})

local CrewMemberLegacyStatus = {}

CrewMemberLegacyStatus.DenyFlagAliases = {
	displayhelpers = "CrewMemberDisplayHelperLegacyFallbackDenyEnabled",
	displayhelper = "CrewMemberDisplayHelperLegacyFallbackDenyEnabled",
	helpers = "CrewMemberDisplayHelperLegacyFallbackDenyEnabled",
	standincome = "CrewMemberStandIncomeLegacyFallbackReadDenyEnabled",
	stand = "CrewMemberStandIncomeLegacyFallbackReadDenyEnabled",
	income = "CrewMemberStandIncomeLegacyFallbackReadDenyEnabled",
	progression = "CrewMemberFoodProgressionLegacyFallbackReadDenyEnabled",
	food = "CrewMemberFoodProgressionLegacyFallbackReadDenyEnabled",
}

local FALLBACK_CATEGORIES = {
	"display_helper_legacy_fallback",
	"stand_income_legacy_fallback_read",
	"food_progression_legacy_fallback_read",
	"canonicalSelected",
	"allowedCompatibilityFallback",
	"allowedBrookFallback",
	"deniedUnknownFallback",
}

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneValue(child)
	end
	return copy
end

local function countForSurface(counts, surface)
	return math.max(0, tonumber(counts[tostring(surface or "")]) or 0)
end

local function summarizeLegacyWriteAudit()
	local summary = {
		DirectLegacyWriteCount = 0,
		ApprovedMirrorWriteCount = 0,
		WrapperUsageCount = 0,
		FallbackCount = 0,
		UnexpectedDirectWriteCount = 0,
		LastOffendingSource = "",
		LastOffendingPath = "",
		LastOffendingRoot = "",
		PlayerCount = 0,
		PlayersWithoutProfile = 0,
	}

	for _, player in ipairs(Players:GetPlayers()) do
		local audit = DataManager:GetLegacyDeprecationStatus(player)
		if typeof(audit) ~= "table" then
			summary.PlayersWithoutProfile += 1
			continue
		end

		summary.PlayerCount += 1
		summary.DirectLegacyWriteCount += math.max(0, tonumber(audit.DirectLegacyWriteCount) or 0)
		summary.ApprovedMirrorWriteCount += math.max(0, tonumber(audit.ApprovedMirrorWriteCount) or 0)
		summary.WrapperUsageCount += math.max(0, tonumber(audit.WrapperUsageCount) or 0)
		summary.FallbackCount += math.max(0, tonumber(audit.FallbackCount) or 0)
		summary.UnexpectedDirectWriteCount += math.max(0, tonumber(audit.UnexpectedDirectWriteCount) or 0)

		if tostring(audit.LastOffendingPath or "") ~= "" then
			summary.LastOffendingSource = tostring(audit.LastOffendingSource or "")
			summary.LastOffendingPath = tostring(audit.LastOffendingPath or "")
			summary.LastOffendingRoot = tostring(audit.LastOffendingRoot or "")
		end
	end

	return summary
end

local function summarizeMigration(player)
	local report = nil
	local ok, result = pcall(function()
		return CrewMigrationPlanner.BuildMigrationCompareReport(player)
	end)
	if ok == true and typeof(result) == "table" then
		report = result
	end

	return {
		Ok = ok == true and report ~= nil,
		Error = if ok == true then nil else tostring(result),
		BlockingCount = if report then math.max(0, tonumber(report.BlockingCount) or 0) else -1,
		UnclassifiedCount = if report then math.max(0, tonumber(report.UnclassifiedCount) or 0) else -1,
		Report = report,
	}
end

local function formatCounts(counts, orderedKeys)
	local parts = {}
	for _, key in ipairs(orderedKeys) do
		parts[#parts + 1] = string.format("%s=%d", tostring(key), countForSurface(counts, key))
	end
	return table.concat(parts, " ")
end

local function formatMapCounts(counts)
	local keys = {}
	for key in pairs(counts or {}) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	if #keys == 0 then
		return "none"
	end
	return formatCounts(counts, keys)
end

local function formatValueMap(values)
	local keys = {}
	for key in pairs(values or {}) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	if #keys == 0 then
		return "none"
	end

	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = string.format("%s=%s", key, tostring(values[key]))
	end
	return table.concat(parts, " ")
end

local function summarizeFlags(flags)
	local parts = {}
	local flagNames = {}
	for flagName in pairs(CrewStorage.LegacyDenyFlags) do
		flagNames[#flagNames + 1] = flagName
	end
	table.sort(flagNames)
	for _, flagName in ipairs(flagNames) do
		parts[#parts + 1] = string.format("%s=%s", flagName, tostring(flags[flagName] == true))
	end
	return table.concat(parts, " ")
end

function CrewMemberLegacyStatus.ResolveDenyFlagName(alias)
	local normalized = tostring(alias or ""):lower():gsub("[^%w]", "")
	return CrewMemberLegacyStatus.DenyFlagAliases[normalized]
end

function CrewMemberLegacyStatus.Build(player)
	local flags = CrewStorage.GetShadowFlags()
	local environment = CrewStorage.GetShadowEnvironment()
	local legacyAudit = summarizeLegacyWriteAudit()
	local fallbackUsage = CrewMemberLegacyFallbackTelemetry.GetSummary()
	local migration = summarizeMigration(player)
	local blockingZero = migration.BlockingCount == 0
	local unclassifiedZero = migration.UnclassifiedCount == 0
	local deniedUnknownZero = countForSurface(fallbackUsage.CategoryCounts, "deniedUnknownFallback") == 0

	local eligibility = {
		BrainrotStorageRetired = true,
		DisplayHelperFallback = deniedUnknownZero and blockingZero and unclassifiedZero,
		StandIncomeFallback = deniedUnknownZero and blockingZero and unclassifiedZero,
		FoodProgressionFallback = countForSurface(
			fallbackUsage.CategoryCounts,
			"food_progression_legacy_fallback_read"
		) == 0 and blockingZero and unclassifiedZero,
		UnexpectedLegacyWritesFrozen = legacyAudit.UnexpectedDirectWriteCount == 0,
	}

	local deletionReadiness = {
		BrainrotStorageRoot = blockingZero and unclassifiedZero,
		FoodProgressionFallback = countForSurface(
			fallbackUsage.CategoryCounts,
			"food_progression_legacy_fallback_read"
		) == 0 and countForSurface(
			fallbackUsage.CategoryDeniedCounts,
			"food_progression_legacy_fallback_read"
		) == 0 and blockingZero and unclassifiedZero,
		DisplayHelperFallback = false,
		StandIncomeFallback = false,
	}

	return {
		Environment = environment,
		Flags = flags,
		ProductionDenyFlags = CrewStorage.ProductionShadowFlags,
		StagingDenyFlags = CrewStorage.StagingShadowFlags,
		LegacyWriteAudit = legacyAudit,
		FallbackUsage = fallbackUsage,
		Migration = migration,
		Eligibility = eligibility,
		DeletionReadiness = deletionReadiness,
	}
end

function CrewMemberLegacyStatus.Print(player)
	local status = CrewMemberLegacyStatus.Build(player)
	local legacyAudit = status.LegacyWriteAudit
	local fallbackUsage = status.FallbackUsage
	local migration = status.Migration

	print(string.format(
		"[CrewLegacyStatus] environment staging=%s source=%s placeId=%s gameId=%s",
		tostring(status.Environment.IsStaging == true),
		tostring(status.Environment.Source or ""),
		tostring(status.Environment.PlaceId or 0),
		tostring(status.Environment.GameId or 0)
	))
	print("[CrewLegacyStatus] denyFlags " .. summarizeFlags(status.Flags))
	print("[CrewLegacyStatus] productionDefaultDenyFlags " .. summarizeFlags(status.ProductionDenyFlags))
	print("[CrewLegacyStatus] stagingDefaultDenyFlags " .. summarizeFlags(status.StagingDenyFlags))
	print("[CrewLegacyStatus] aliasCompatibility removed=true")
	print(string.format(
		"[CrewLegacyStatus] legacyWrites unexpected=%d approvedMirror=%d direct=%d wrapper=%d fallbackAudit=%d lastOffender={source=%s,path=%s,root=%s}",
		legacyAudit.UnexpectedDirectWriteCount,
		legacyAudit.ApprovedMirrorWriteCount,
		legacyAudit.DirectLegacyWriteCount,
		legacyAudit.WrapperUsageCount,
		legacyAudit.FallbackCount,
		tostring(legacyAudit.LastOffendingSource or ""),
		tostring(legacyAudit.LastOffendingPath or ""),
		tostring(legacyAudit.LastOffendingRoot or "")
	))
	print("[CrewLegacyStatus] fallbackUsage " .. formatCounts(fallbackUsage.CategoryCounts, FALLBACK_CATEGORIES))
	print("[CrewLegacyStatus] fallbackDenied " .. formatMapCounts(fallbackUsage.CategoryDeniedCounts))
	print(string.format(
		"[CrewLegacyStatus] migration blocking=%d unclassified=%d ok=%s error=%s",
		migration.BlockingCount,
		migration.UnclassifiedCount,
		tostring(migration.Ok == true),
		tostring(migration.Error or "")
	))
	print("[CrewLegacyStatus] eligibility " .. formatValueMap(status.Eligibility))
	print("[CrewLegacyStatus] deletionReadiness " .. formatValueMap(status.DeletionReadiness))

	local summary = string.format(
		"legacy status printed. aliasCompatibility=removed unexpectedWrites=%d fallback=%d blocking=%d unclassified=%d",
		legacyAudit.UnexpectedDirectWriteCount,
		fallbackUsage.TotalCount,
		migration.BlockingCount,
		migration.UnclassifiedCount
	)
	return status, summary
end

return CrewMemberLegacyStatus
