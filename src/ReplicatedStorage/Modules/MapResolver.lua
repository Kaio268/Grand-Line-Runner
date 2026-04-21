local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local MapResolver = {}

local DEFAULT_MAP_NAME = "Map"
local ACTIVE_MAP_ATTRIBUTE = "ActiveMapName"
local STUDIO_STARTUP_ACTIVE_MAP_NAME = DEFAULT_MAP_NAME
local warnedMessages = {}
local tracedStates = {}
local DEBUG_TRACE = RunService:IsStudio()

local PATH_LABELS = {
	Map = "active map root",
	MapRoot = "active map root",
	ActiveMapRoot = "active map root",
	SpawnPart = "active map SpawnPart",
	SpawnFolder = "active map SpawnPart",
	HitBox = "active map HitBox",
	WaveFolder = "active map WaveFolder",
	WaveStart = "active map WaveFolder.Start",
	WaveEnd = "active map WaveFolder.End",
	CorridorEntry = "active map corridor entry",
	CorridorDeepEnd = "active map corridor deep end",
	ExtractionZone = "active map GrandLineRush.ExtractionZone",
	ExtractionTouch = "active map extraction touch part",
	ExtractionTouchPart = "active map extraction touch part",
	PlotSystem = "Workspace.PlotSystem",
	ShipArea = "Workspace.PlotSystem.Plots or PlotSystem",
}

local function warnOnce(key, message)
	if warnedMessages[key] then
		return
	end

	warnedMessages[key] = true
	warn(message)
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function formatInstancePosition(instance)
	if not instance then
		return "<nil>"
	end

	if instance:IsA("BasePart") then
		return formatVector3(instance.Position)
	end

	local childParts = {}
	for _, child in ipairs(instance:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(childParts, string.format("%s=%s", child.Name, formatVector3(child.Position)))
			if #childParts >= 3 then
				break
			end
		end
	end

	if #childParts > 0 then
		return string.format("<%s childParts: %s>", instance.ClassName, table.concat(childParts, ", "))
	end

	return string.format("<not_a_basepart:%s>", instance.ClassName)
end

local function mapTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[MAP TRACE] " .. message, ...))
end

local function isNonEmptyString(value)
	return typeof(value) == "string" and value ~= ""
end

local function formatContextSuffix(context)
	if not isNonEmptyString(context) then
		return ""
	end

	return string.format(":%s", context)
end

local function ensureStartupActiveMapAttribute()
	local attributeValue = Workspace:GetAttribute(ACTIVE_MAP_ATTRIBUTE)
	if isNonEmptyString(attributeValue) then
		return attributeValue
	end

	if DEBUG_TRACE
		and isNonEmptyString(STUDIO_STARTUP_ACTIVE_MAP_NAME)
		and Workspace:FindFirstChild(STUDIO_STARTUP_ACTIVE_MAP_NAME) then
		Workspace:SetAttribute(ACTIVE_MAP_ATTRIBUTE, STUDIO_STARTUP_ACTIVE_MAP_NAME)
		mapTrace(
			"Seeded ActiveMapName=%s before startup map resolution",
			STUDIO_STARTUP_ACTIVE_MAP_NAME
		)
		return STUDIO_STARTUP_ACTIVE_MAP_NAME
	end

	return nil
end

local function getRequestedMapName(options)
	if options and isNonEmptyString(options.mapName) then
		return options.mapName
	end

	local attributeValue = ensureStartupActiveMapAttribute() or Workspace:GetAttribute(ACTIVE_MAP_ATTRIBUTE)
	if isNonEmptyString(attributeValue) then
		return attributeValue
	end

	return DEFAULT_MAP_NAME
end

local function getChild(parent, name, className)
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(name)
	if not child then
		return nil
	end

	if className and not child:IsA(className) then
		return nil
	end

	return child
end

local function resolveActiveMap(options)
	local requestedMapName = getRequestedMapName(options)
	local map = Workspace:FindFirstChild(requestedMapName)
	local usingFallback = false

	if not map and requestedMapName ~= DEFAULT_MAP_NAME then
		local fallbackMap = Workspace:FindFirstChild(DEFAULT_MAP_NAME)
		if fallbackMap then
			map = fallbackMap
			usingFallback = true
		end
	end

	return map, requestedMapName, usingFallback
end

local function collectRefs(options)
	local refs = {}
	local warnings = {}

	local map, requestedMapName, usingFallback = resolveActiveMap(options)
	refs.Map = map
	refs.ActiveMap = map
	refs.RequestedMapName = requestedMapName
	refs.ActiveMapName = map and map.Name or requestedMapName
	refs.UsingMapFallback = usingFallback

	if not map then
		warnings[#warnings + 1] = string.format(
			"Could not resolve active map '%s' and no '%s' fallback exists in Workspace.",
			tostring(requestedMapName),
			DEFAULT_MAP_NAME
		)
	elseif usingFallback then
		warnings[#warnings + 1] = string.format(
			"Active map '%s' was not found; falling back to Workspace.%s.",
			tostring(requestedMapName),
			DEFAULT_MAP_NAME
		)
	end

	local waveFolder = getChild(map, "WaveFolder")
	local corridorFolder = getChild(waveFolder, "GrandLineRush")
	local plotSystem = getChild(Workspace, "PlotSystem")

	refs.SpawnPart = getChild(map, "SpawnPart")
	refs.SpawnFolder = refs.SpawnPart
	refs.HitBox = getChild(map, "HitBox", "BasePart")
	refs.WaveFolder = waveFolder
	refs.WaveStart = getChild(waveFolder, "Start", "BasePart")
	refs.WaveEnd = getChild(waveFolder, "End", "BasePart")
	refs.CorridorEntry = refs.WaveEnd
	refs.CorridorDeepEnd = refs.WaveStart
	refs.CorridorFolder = corridorFolder
	refs.GrandLineRushFolder = corridorFolder
	refs.ExtractionZone = getChild(corridorFolder, "ExtractionZone", "BasePart")
	refs.ExtractionTouch = refs.ExtractionZone or refs.HitBox
	refs.ExtractionTouchPart = refs.ExtractionTouch
	refs.ClientWavesFolder = getChild(waveFolder, "ClientWaves")
	refs.ClientWaves = refs.ClientWavesFolder
	refs.PlotSystem = plotSystem
	refs.ShipArea = plotSystem and (plotSystem:FindFirstChild("Plots") or plotSystem) or nil
	refs.Warnings = warnings
	refs.MapRoot = refs.Map
	refs.ActiveMapRoot = refs.Map

	return refs
end

local function traceResolvedRefs(refs, options)
	if not DEBUG_TRACE then
		return
	end

	local context = (options and options.context) or "MapResolver"
	local stateKey = table.concat({
		tostring(context),
		tostring(refs.RequestedMapName),
		tostring(refs.ActiveMapName),
		tostring(refs.UsingMapFallback),
		formatInstancePath(refs.MapRoot),
		formatInstancePath(refs.SpawnPart),
		formatInstancePath(refs.HitBox),
		formatInstancePath(refs.WaveFolder),
		formatInstancePath(refs.WaveStart),
		formatInstancePath(refs.WaveEnd),
	}, "|")

	if tracedStates[stateKey] then
		return
	end

	tracedStates[stateKey] = true
	mapTrace(
		"context=%s requestedMap=%s activeMap=%s usingFallback=%s map=%s spawnPart=%s spawnPos=%s hitBox=%s hitBoxPos=%s waveFolder=%s waveStart=%s waveStartPos=%s waveEnd=%s waveEndPos=%s",
		tostring(context),
		tostring(refs.RequestedMapName),
		tostring(refs.ActiveMapName),
		tostring(refs.UsingMapFallback),
		formatInstancePath(refs.MapRoot),
		formatInstancePath(refs.SpawnPart),
		formatInstancePosition(refs.SpawnPart),
		formatInstancePath(refs.HitBox),
		formatInstancePosition(refs.HitBox),
		formatInstancePath(refs.WaveFolder),
		formatInstancePath(refs.WaveStart),
		formatInstancePosition(refs.WaveStart),
		formatInstancePath(refs.WaveEnd),
		formatInstancePosition(refs.WaveEnd)
	)
end

local function hasRequiredRefs(refs, requiredKeys)
	for _, key in ipairs(requiredKeys or {}) do
		if refs[key] == nil then
			return false
		end
	end

	return true
end

local function warnForRefs(refs, requiredKeys, options)
	local context = options and options.context
	local contextSuffix = formatContextSuffix(context)

	for _, message in ipairs(refs.Warnings or {}) do
		warnOnce(
			string.format("resolver%s:%s:%s", contextSuffix, refs.RequestedMapName or "unknown", message),
			string.format("[MapResolver%s] %s", contextSuffix, message)
		)
	end

	for _, key in ipairs(requiredKeys or {}) do
		if refs[key] == nil then
			local label = PATH_LABELS[key] or key
			warnOnce(
				string.format("resolver%s:missing:%s:%s", contextSuffix, tostring(key), refs.ActiveMapName or "unknown"),
				string.format("[MapResolver%s] Missing %s.", contextSuffix, label)
			)
		end
	end
end

function MapResolver.GetActiveMap(options)
	return collectRefs(options).Map
end

function MapResolver.GetActiveMapRoot(options)
	return collectRefs(options).MapRoot
end

function MapResolver.GetRefs(options)
	options = options or {}

	local refs = collectRefs(options)
	traceResolvedRefs(refs, options)
	if options.warn == true or options.required ~= nil then
		warnForRefs(refs, options.required, options)
	end

	return refs
end

function MapResolver.AreRefsReady(refs, requiredKeys)
	return hasRequiredRefs(refs or {}, requiredKeys)
end

function MapResolver.HasRefs(refs, requiredKeys)
	return MapResolver.AreRefsReady(refs, requiredKeys)
end

function MapResolver.WarnMissing(requiredKeys, context, refs)
	if refs == nil or refs.Warnings == nil then
		refs = collectRefs()
	end

	warnForRefs(refs, requiredKeys, {
		context = context,
	})

	return refs
end

function MapResolver.WaitForRefs(requiredKeys, timeoutSeconds, options)
	options = options or {}

	local deadline = timeoutSeconds and (os.clock() + timeoutSeconds) or nil
	local pollInterval = tonumber(options.pollInterval) or 0.2

	while true do
		local refs = collectRefs(options)
		traceResolvedRefs(refs, options)
		if hasRequiredRefs(refs, requiredKeys) then
			if options.warn == true then
				warnForRefs(refs, nil, options)
			end
			return refs
		end

		warnForRefs(refs, requiredKeys, options)

		if deadline and os.clock() >= deadline then
			return refs
		end

		task.wait(pollInterval)
	end
end

function MapResolver.WaitForRefsUntil(requiredKeys, timeoutSeconds, options)
	return MapResolver.WaitForRefs(requiredKeys, timeoutSeconds, options)
end

function MapResolver.GetWaveParts(options)
	local refs = collectRefs(options)
	if not hasRequiredRefs(refs, { "WaveFolder", "WaveStart", "WaveEnd" }) then
		return nil
	end

	return refs.WaveFolder, refs.WaveStart, refs.WaveEnd, refs
end

return MapResolver
