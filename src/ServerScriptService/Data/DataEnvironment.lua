local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local DataEnvironment = {}

local ENVIRONMENT_PRODUCTION = "Production"
local ENVIRONMENT_STAGING = "Staging"
local ENVIRONMENT_DEVELOPMENT = "Development"

local PLACE_ROLE_MAIN = "Main"
local PLACE_ROLE_AFK = "AFK"
local PLACE_ROLE_DEVELOPMENT = "Development"

local PRODUCTION_MAIN_PLACE_ID = 111129977331443
local PRODUCTION_AFK_PLACE_ID = 135767110031089
local REQUIRED_PRODUCTION_KEY_ID = "prod-release-v1"

DataEnvironment.Environments = {
	Production = ENVIRONMENT_PRODUCTION,
	Staging = ENVIRONMENT_STAGING,
	Development = ENVIRONMENT_DEVELOPMENT,
}

DataEnvironment.PlaceRoles = {
	Main = PLACE_ROLE_MAIN,
	AFK = PLACE_ROLE_AFK,
	Development = PLACE_ROLE_DEVELOPMENT,
}

DataEnvironment.Policy = {
	Production = {
		Environment = ENVIRONMENT_PRODUCTION,
		RequiredKeyId = REQUIRED_PRODUCTION_KEY_ID,
		Places = {
			Main = PRODUCTION_MAIN_PLACE_ID,
			AFK = PRODUCTION_AFK_PLACE_ID,
		},
	},
	Staging = {
		Environment = ENVIRONMENT_STAGING,
		Places = {},
	},
	Development = {
		Environment = ENVIRONMENT_DEVELOPMENT,
		Places = {},
	},
}

local function setAttribute(name, value)
	local ok = pcall(function()
		workspace:SetAttribute(name, value)
	end)
	return ok
end

local function recordDiagnostics(placeInfo, valid, keyId, message)
	setAttribute("DataEnvironment_Name", placeInfo.Environment)
	setAttribute("DataEnvironment_PlaceRole", placeInfo.PlaceRole)
	setAttribute("DataEnvironment_PlaceId", placeInfo.PlaceId)
	setAttribute("DataEnvironment_KeyId", keyId or "")
	setAttribute("DataEnvironment_Valid", valid == true)
	setAttribute("DataEnvironment_Error", if valid then "" else tostring(message or "invalid"))
end

local function fail(placeInfo, message)
	recordDiagnostics(placeInfo, false, nil, message)
	if RunService:IsStudio() then
		warn("[DataEnvironment]: " .. message)
	end
	error("[DataEnvironment]: " .. message, 3)
end

local EXPLICIT_PLACEHOLDER_VALUES = {
	[""] = true,
	["defaultkey_123"] = true,
	["replace_me"] = true,
	["your_key_here"] = true,
}

local function trimText(value)
	if typeof(value) ~= "string" then
		return nil
	end

	return value:match("^%s*(.-)%s*$")
end

local function isNonEmptyString(value)
	local trimmed = trimText(value)
	return trimmed ~= nil and trimmed ~= ""
end

local function isPlaceholder(value)
	local trimmed = trimText(value)
	if trimmed == nil then
		return true
	end

	local lowered = string.lower(trimmed)
	return EXPLICIT_PLACEHOLDER_VALUES[lowered] == true
		or lowered:find("replace", 1, true) ~= nil
		or lowered:find("todo", 1, true) ~= nil
		or lowered:find("change_me", 1, true) ~= nil
		or trimmed:find("<", 1, true) ~= nil
		or trimmed:find(">", 1, true) ~= nil
end

local function fnvFingerprint(value)
	local encoded = HttpService:JSONEncode({ tostring(value or "") })
	local hash = 2166136261
	for index = 1, #encoded do
		hash = bit32.bxor(hash, string.byte(encoded, index))
		hash = (hash * 16777619) % 4294967296
	end
	return string.format("fnv1a32:%08x", hash)
end

local function getKeyFingerprint(value)
	return fnvFingerprint(value)
end

local function findSecretsModule()
	local module = script.Parent:FindFirstChild("DataKeySecrets")
	if module ~= nil and module:IsA("ModuleScript") then
		return module
	end
	return nil
end

local function requireSecrets(placeInfo)
	local module = findSecretsModule()
	if module == nil then
		fail(placeInfo, "Missing private ServerScriptService.Data.DataKeySecrets module.")
	end

	local ok, secrets = pcall(require, module)
	if not ok then
		fail(placeInfo, "Private DataKeySecrets module failed to load.")
	end

	if typeof(secrets) ~= "table" then
		fail(placeInfo, "Private DataKeySecrets module must return a table.")
	end

	return secrets
end

local function getStagingPlaceRole(placeId)
	for role, stagingPlaceId in pairs(DataEnvironment.Policy.Staging.Places) do
		if tonumber(stagingPlaceId) == placeId then
			return role
		end
	end
	return nil
end

local function validateEntry(placeInfo, entry)
	if typeof(entry) ~= "table" then
		fail(placeInfo, string.format("Missing %s DataKeySecrets entry.", placeInfo.Environment))
	end

	local keyId = trimText(entry.KeyId)
	local dataKey = trimText(entry.DataKey)

	if not isNonEmptyString(keyId) or isPlaceholder(keyId) then
		fail(placeInfo, string.format("%s DataKeySecrets.KeyId is missing or still a placeholder.", placeInfo.Environment))
	end

	if not isNonEmptyString(dataKey) or isPlaceholder(dataKey) then
		fail(placeInfo, string.format("%s DataKeySecrets.DataKey is missing or still a placeholder.", placeInfo.Environment))
	end

	if placeInfo.Environment == ENVIRONMENT_PRODUCTION and keyId ~= REQUIRED_PRODUCTION_KEY_ID then
		fail(placeInfo, string.format(
			"Production DataKeySecrets.KeyId must be %s for the release production datastore.",
			REQUIRED_PRODUCTION_KEY_ID
		))
	end

	return keyId, dataKey
end

function DataEnvironment.ResolvePlace(placeId)
	local numericPlaceId = tonumber(placeId) or 0

	if numericPlaceId == PRODUCTION_MAIN_PLACE_ID then
		return {
			Environment = ENVIRONMENT_PRODUCTION,
			PlaceRole = PLACE_ROLE_MAIN,
			PlaceId = numericPlaceId,
			IsProduction = true,
			IsStudio = RunService:IsStudio(),
		}
	end

	if numericPlaceId == PRODUCTION_AFK_PLACE_ID then
		return {
			Environment = ENVIRONMENT_PRODUCTION,
			PlaceRole = PLACE_ROLE_AFK,
			PlaceId = numericPlaceId,
			IsProduction = true,
			IsStudio = RunService:IsStudio(),
		}
	end

	local stagingRole = getStagingPlaceRole(numericPlaceId)
	if stagingRole ~= nil then
		return {
			Environment = ENVIRONMENT_STAGING,
			PlaceRole = stagingRole,
			PlaceId = numericPlaceId,
			IsProduction = false,
			IsStudio = RunService:IsStudio(),
		}
	end

	if RunService:IsStudio() then
		return {
			Environment = ENVIRONMENT_DEVELOPMENT,
			PlaceRole = PLACE_ROLE_DEVELOPMENT,
			PlaceId = numericPlaceId,
			IsProduction = false,
			IsStudio = true,
		}
	end

	return {
		Environment = "Unknown",
		PlaceRole = "Unknown",
		PlaceId = numericPlaceId,
		IsProduction = false,
		IsStudio = false,
	}
end

function DataEnvironment.GetDiagnostics(resolution)
	return {
		Environment = resolution.Environment,
		PlaceRole = resolution.PlaceRole,
		PlaceId = resolution.PlaceId,
		KeyId = resolution.KeyId,
		KeyFingerprint = resolution.KeyFingerprint,
		KeyLength = resolution.KeyLength,
		Source = resolution.Source,
		IsProduction = resolution.IsProduction == true,
		IsStudio = resolution.IsStudio == true,
		Valid = true,
	}
end

function DataEnvironment.ResolveDataKey()
	local placeInfo = DataEnvironment.ResolvePlace(game.PlaceId)
	if placeInfo.Environment == "Unknown" then
		fail(placeInfo, string.format(
			"Place %s is not mapped to a data environment; live servers cannot choose a fallback datastore.",
			tostring(placeInfo.PlaceId)
		))
	end

	local secrets = requireSecrets(placeInfo)
	local entry = secrets[placeInfo.Environment]
	local keyId, dataKey = validateEntry(placeInfo, entry)

	local resolution = {
		Environment = placeInfo.Environment,
		PlaceRole = placeInfo.PlaceRole,
		PlaceId = placeInfo.PlaceId,
		KeyId = keyId,
		DataKey = dataKey,
		KeyFingerprint = getKeyFingerprint(dataKey),
		KeyLength = #dataKey,
		Source = "DataKeySecrets",
		IsProduction = placeInfo.IsProduction == true,
		IsStudio = placeInfo.IsStudio == true,
	}

	recordDiagnostics(resolution, true, keyId, nil)
	setAttribute("DataEnvironment_KeyFingerprint", resolution.KeyFingerprint)
	setAttribute("DataEnvironment_KeyLength", resolution.KeyLength)
	return resolution
end

function DataEnvironment.GetActiveDiagnostics(resolution)
	local diagnostics = nil
	if typeof(resolution) == "table" then
		diagnostics = DataEnvironment.GetDiagnostics(resolution)
	else
		diagnostics = {
			Environment = workspace:GetAttribute("DataEnvironment_Name"),
			PlaceRole = workspace:GetAttribute("DataEnvironment_PlaceRole"),
			PlaceId = workspace:GetAttribute("DataEnvironment_PlaceId"),
			KeyId = workspace:GetAttribute("DataEnvironment_KeyId"),
			KeyFingerprint = workspace:GetAttribute("DataEnvironment_KeyFingerprint"),
			KeyLength = workspace:GetAttribute("DataEnvironment_KeyLength"),
			Source = "DataKeySecrets",
			Valid = workspace:GetAttribute("DataEnvironment_Valid") == true,
		}
	end

	diagnostics.BootModeValid = workspace:GetAttribute("DataEnvironment_BootModeValid") == true
	diagnostics.ExpectedBootMode = workspace:GetAttribute("DataEnvironment_ExpectedBootMode") or ""
	diagnostics.ObservedBootMode = workspace:GetAttribute("DataEnvironment_ObservedBootMode") or ""
	diagnostics.Error = workspace:GetAttribute("DataEnvironment_Error") or ""
	return diagnostics
end

function DataEnvironment.ValidateBootMode(resolution, requestedBootMode)
	local expectedBootMode = nil
	if resolution.PlaceRole == PLACE_ROLE_MAIN then
		expectedBootMode = PLACE_ROLE_MAIN
	elseif resolution.PlaceRole == PLACE_ROLE_AFK then
		expectedBootMode = PLACE_ROLE_AFK
	end

	setAttribute("DataEnvironment_ExpectedBootMode", expectedBootMode or "")
	setAttribute("DataEnvironment_ObservedBootMode", requestedBootMode or "")

	if expectedBootMode == nil or requestedBootMode == expectedBootMode then
		setAttribute("DataEnvironment_BootModeValid", true)
		return true
	end

	setAttribute("DataEnvironment_BootModeValid", false)
	local message = string.format(
		"Place role %s expects DataManager boot mode %s, but got %s.",
		tostring(resolution.PlaceRole),
		tostring(expectedBootMode),
		tostring(requestedBootMode)
	)

	if RunService:IsStudio() then
		warn("[DataEnvironment]: " .. message)
		return false, message
	end

	error("[DataEnvironment]: " .. message, 2)
end

return DataEnvironment
