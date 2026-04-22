--[[
	FlameDashVfx rebuilds Mera Flame Dash around a single attached active body layer
	and a repeated cloned flame trail behind the player while keeping the public API stable.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MeraConfig = require(script.Parent.Parent:WaitForChild("MeraConfig"))
local VfxCommon = require(script.Parent:WaitForChild("VfxCommon"))

local FlameDashVfx = {}

local DEBUG_CONFIG = MeraConfig.Debug or {}
local SHARED_CONFIG = MeraConfig.Shared or {}
local FLAME_DASH_CONFIG = MeraConfig.FlameDash or {}

local DEBUG_INFO = RunService:IsStudio() and DEBUG_CONFIG.EnableInfoLogsInStudio ~= false
local DEBUG_VERBOSE = DEBUG_INFO and DEBUG_CONFIG.EnableVerboseDebugLogs == true

local ROOT_SEGMENTS = SHARED_CONFIG.RootSegments or { "Assets", "VFX", "Mera" }
local EFFECT_CANDIDATES = FLAME_DASH_CONFIG.EffectCandidates or { "Flame Dash" }
local STARTUP_CHILD_CANDIDATES = FLAME_DASH_CONFIG.StartupChildCandidates or { "Startup", "Start up", "FX" }
local HEAD_CHILD_CANDIDATES = FLAME_DASH_CONFIG.HeadAssetCandidates or { "Dash", "FX" }
local ACTIVE_TRAIL_SOURCE_CHILD_CANDIDATES = { "FX" }
local TRAIL_CHILD_CANDIDATES = FLAME_DASH_CONFIG.TrailAssetCandidates
	or FLAME_DASH_CONFIG.PartAssetCandidates
	or { "Part", "FX2", "Trail" }

local DEFAULT_ACTIVE_EMIT_COUNT = math.max(1, tonumber(FLAME_DASH_CONFIG.DashEmitCount) or 10)
local DEFAULT_STARTUP_FADE_TIME = 0.05
local DEFAULT_STARTUP_HOLD_TIME = 0.05
local DEFAULT_ACTIVE_FADE_TIME = math.max(0.08, tonumber(SHARED_CONFIG.RuntimeStopFadeTime) or 0.12)
local DEFAULT_ACTIVE_HOLD_TIME = 0.18
local DEFAULT_TRAIL_SPACING = math.max(
	0.3,
	tonumber(FLAME_DASH_CONFIG.TrailCloneSpacing) or tonumber(FLAME_DASH_CONFIG.TrailSpacing) or 0.9
)
local DEFAULT_TRAIL_BACK_OFFSET = math.max(0, tonumber(FLAME_DASH_CONFIG.TrailBackOffset) or 1.6)
local DEFAULT_TRAIL_LIFETIME = math.max(
	0.12,
	tonumber(FLAME_DASH_CONFIG.TrailCloneLifetime) or tonumber(FLAME_DASH_CONFIG.TrailLifetime) or 0.22
)
local DEFAULT_TRAIL_DISABLE_FRACTION = 0.7
local DEFAULT_GROUND_TRAIL_RAYCAST_HEIGHT = math.max(
	2,
	tonumber(FLAME_DASH_CONFIG.GroundTrailRaycastHeight) or 8
)
local DEFAULT_GROUND_TRAIL_RAYCAST_DEPTH = math.max(
	4,
	tonumber(FLAME_DASH_CONFIG.GroundTrailRaycastDepth) or 40
)
local DEFAULT_GROUND_TRAIL_LIFT = math.max(
	0.02,
	tonumber(FLAME_DASH_CONFIG.GroundTrailLift) or 0.12
)
local TRAIL_RATE_DECAY_STAGES = {
	{ TimeFraction = 0.18, RateScale = 0.75 },
	{ TimeFraction = 0.42, RateScale = 0.42 },
	{ TimeFraction = 0.62, RateScale = 0.16 },
}
local DEFAULT_MAX_TRAIL_CLONES_PER_STEP = math.max(
	1,
	math.floor(tonumber(FLAME_DASH_CONFIG.MaxTrailClonesPerStep) or 6)
)
local DEFAULT_LOCAL_OFFSET = CFrame.Angles(0, math.rad(90), 0)
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local CLEANUP_BUFFER = 1.0
local FOLLOW_WELD_NAME = "MeraFlameDashFollowWeld"
local TRAIL_CLONE_NAME = "FlameDashTrailClone"
local LOG_PREFIX = "[flamedash]"

local MAX_TRAIL_CLONE_STREAM_RATE = math.max(
	1,
	tonumber(FLAME_DASH_CONFIG.MaxTrailCloneStreamRate)
		or tonumber(FLAME_DASH_CONFIG.MaxContinuousTrailStreamRate)
		or 90
)
local MAX_ACTIVE_HEAD_STREAM_RATE = math.max(
	1,
	tonumber(FLAME_DASH_CONFIG.MaxActiveHeadStreamRate) or 36
)
local DEFAULT_ACTIVE_HEAD_STREAM_RATE_SCALE = math.clamp(
	tonumber(FLAME_DASH_CONFIG.ActiveHeadStreamRateScale) or 0.8,
	0,
	1
)
-- This is the authored flame particle look the user kept calling the "bad trail visual".
-- It now comes from the `FX` source and is intentionally allowed only on cloned trail
-- instances behind the player.
local TRAIL_VISUAL_EMITTER_NAMES = {
	["fire"] = true,
	["fire 2"] = true,
	["specs"] = true,
}
local DEFAULT_TRAIL_CLONE_EMITTER_RATES = {
	["fire"] = 80,
	["fire 2"] = 65,
	["specs"] = 40,
	["shockwave"] = 0,
	["wind"] = 0,
}
local DEFAULT_ACTIVE_HEAD_EMITTER_RATES = {
	["fire"] = 20,
	["fire 2"] = 16,
	["specs"] = 10,
	["shockwave"] = 0,
	["wind"] = 0,
}
local ALWAYS_DISABLED_TRAIL_EMITTER_NAMES = {
	["shockwave"] = true,
	["wind"] = true,
}
local ALWAYS_DISABLED_HEAD_EMITTER_NAMES = {
	["shockwave"] = true,
	["wind"] = true,
}

local runtimeSequence = 0

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if select("#", ...) > 0 then
		print(LOG_PREFIX, string.format(message, ...))
	else
		print(LOG_PREFIX, tostring(message))
	end
end

local function logWarn(message, ...)
	if select("#", ...) > 0 then
		warn(LOG_PREFIX, string.format(message, ...))
	else
		warn(LOG_PREFIX, tostring(message))
	end
end

local function logDebug(message, ...)
	if not DEBUG_VERBOSE then
		return
	end

	if select("#", ...) > 0 then
		print(LOG_PREFIX, string.format(message, ...))
	else
		print(LOG_PREFIX, tostring(message))
	end
end

local function nextRuntimeId()
	runtimeSequence += 1
	return string.format("fd-%04d", runtimeSequence)
end

local function emitterKey(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end

	return string.lower(name)
end

local function buildDisabledEmitterNameSet()
	local set = {}
	local raw = FLAME_DASH_CONFIG.DisabledTrailEmitterNames
	if type(raw) ~= "table" then
		return set
	end

	for key, value in pairs(raw) do
		if type(key) == "string" and value == true then
			local normalized = emitterKey(key)
			if normalized then
				set[normalized] = true
			end
		elseif type(key) == "number" and type(value) == "string" then
			local normalized = emitterKey(value)
			if normalized then
				set[normalized] = true
			end
		end
	end

	return set
end

local DISABLED_EMITTER_NAMES = buildDisabledEmitterNameSet()

local function eachSelfAndDescendants(root, callback)
	if not root then
		return
	end

	callback(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		callback(descendant)
	end
end

local function eachDescendantOfType(root, className, callback)
	eachSelfAndDescendants(root, function(item)
		if item:IsA(className) then
			callback(item)
		end
	end)
end

local function safeGetFullName(instance)
	if not instance then
		return "<nil>"
	end

	local ok, path = pcall(function()
		return instance:GetFullName()
	end)
	if ok and type(path) == "string" and path ~= "" then
		return path
	end

	return instance.Name
end

local function isInstanceWithinRoot(instance, root)
	return instance ~= nil and root ~= nil and (instance == root or instance:IsDescendantOf(root))
end

local function shouldSuppressAttachedBodyLayer(bodyRoot, trailSourceRoot)
	if not bodyRoot or not trailSourceRoot then
		return false
	end

	-- Suppress the attached body only when it resolves to the exact same authored
	-- subtree as the trail source, or when the attached body is nested inside the
	-- trail source. If `FX` is only a child inside a larger body root, we keep the
	-- body root alive and suppress the trail profile inside it instead.
	return bodyRoot == trailSourceRoot or isInstanceWithinRoot(bodyRoot, trailSourceRoot)
end

local function isBasePart(instance)
	return instance and instance:IsA("BasePart")
end

local function findFirstBasePart(root)
	if isBasePart(root) then
		return root
	end

	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function findCandidateInstance(root, candidates)
	local direct = VfxCommon.FindChild(root, candidates or {})
	if direct then
		return direct
	end

	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		for _, candidateName in ipairs(candidates or {}) do
			if descendant.Name == candidateName then
				return descendant
			end
		end
	end

	return nil
end

local function buildRelativePathSegments(root, target)
	if not root or not target then
		return nil
	end

	local segments = {}
	local cursor = target
	while cursor and cursor ~= root do
		table.insert(segments, 1, cursor.Name)
		cursor = cursor.Parent
	end

	if cursor ~= root then
		return nil
	end

	return segments
end

local function resolveInstanceBySegments(root, segments)
	if not root then
		return nil
	end

	local cursor = root
	for _, segment in ipairs(segments or {}) do
		cursor = cursor:FindFirstChild(segment)
		if not cursor then
			return nil
		end
	end

	return cursor
end

local function setPartsWorldSafe(root, anchored)
	eachDescendantOfType(root, "BasePart", function(part)
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.Anchored = anchored
	end)
end

local function buildGroundTrailRaycastParams(ignoreList)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = ignoreList
	return params
end

local function clearFollowWeld(anchorPart)
	if not isBasePart(anchorPart) then
		return
	end

	local old = anchorPart:FindFirstChild(FOLLOW_WELD_NAME)
	if old and old:IsA("WeldConstraint") then
		old:Destroy()
	end
end

local function makeFollowWeld(anchorPart, rootPart)
	if not isBasePart(anchorPart) or not isBasePart(rootPart) then
		return nil
	end

	clearFollowWeld(anchorPart)

	local weld = Instance.new("WeldConstraint")
	weld.Name = FOLLOW_WELD_NAME
	weld.Part0 = anchorPart
	weld.Part1 = rootPart
	weld.Parent = anchorPart

	return weld
end

local function destroyNamedWelds(root)
	if not root then
		return
	end

	eachSelfAndDescendants(root, function(item)
		if item.Name == FOLLOW_WELD_NAME and item:IsA("WeldConstraint") then
			item:Destroy()
		end
	end)
end

local function setLightsEnabled(root, enabled)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			item.Enabled = enabled
		end
	end)
end

local function disableVisuals(root)
	if not root then
		return
	end

	VfxCommon.DisableEffects(root)
	setLightsEnabled(root, false)
end

local function setAuxVisualsEnabled(root, enabled, allowPathEffects)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
			item.Enabled = enabled
			return
		end

		if item:IsA("Beam") or item:IsA("Trail") then
			item.Enabled = allowPathEffects and enabled or false
			return
		end

		if item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			item.Enabled = enabled
		end
	end)
end

local function silenceParticleEmitters(root)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("ParticleEmitter") then
			item.Enabled = false
			item.Rate = 0
		end
	end)
end

local function hideTrailRenderableObjects(root)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("BasePart") then
			item.Transparency = 1
			item.CastShadow = false
			return
		end

		if item:IsA("Decal") or item:IsA("Texture") then
			item.Transparency = 1
			return
		end

		if item:IsA("Beam") or item:IsA("Trail") then
			item.Enabled = false
		end
	end)
end

local function pruneTrailPathEffects(root)
	if not root then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant:Destroy()
		end
	end
end

local function captureEmitterDefaults(root)
	local defaults = {}
	if not root then
		return defaults
	end

	eachSelfAndDescendants(root, function(item)
		if item:IsA("ParticleEmitter") then
			defaults[item] = {
				Enabled = item.Enabled ~= false,
				Rate = tonumber(item.Rate) or 0,
			}
		end
	end)

	return defaults
end

local function isTrailVisualEmitterName(key)
	return key ~= nil and TRAIL_VISUAL_EMITTER_NAMES[key] == true
end

local function silenceEmitterProfile(root, matcher)
	if not root or type(matcher) ~= "function" then
		return
	end

	eachSelfAndDescendants(root, function(item)
		if not item:IsA("ParticleEmitter") then
			return
		end

		local key = emitterKey(item.Name)
		if matcher(key, item) then
			item.Enabled = false
			item.Rate = 0
		end
	end)
end

local function emitterDisabled(key, extraDisabledNames)
	if not key then
		return false
	end

	if DISABLED_EMITTER_NAMES[key] then
		return true
	end

	return type(extraDisabledNames) == "table" and extraDisabledNames[key] == true
end

local function resolveConfiguredRate(rateTable, emitter)
	if type(rateTable) ~= "table" or not emitter then
		return nil
	end

	local key = emitterKey(emitter.Name)
	local rate = tonumber(rateTable[emitter.Name])
	if rate == nil and key then
		rate = tonumber(rateTable[key])
	end

	return rate
end

local function configureParticleEmitters(root, resolveRate)
	local enabledCount = 0
	local totalRate = 0
	local enabledEmitters = {}
	if not root then
		return enabledCount, totalRate, enabledEmitters
	end

	eachSelfAndDescendants(root, function(item)
		if not item:IsA("ParticleEmitter") then
			return
		end

		local rate, enabled = resolveRate(item)
		item.Rate = tonumber(rate) or 0
		item.Enabled = enabled == true and item.Rate > 0
		if item.Enabled then
			enabledCount += 1
			totalRate += item.Rate
			enabledEmitters[#enabledEmitters + 1] = {
				Emitter = item,
				BaseRate = item.Rate,
			}
		end
	end)

	return enabledCount, totalRate, enabledEmitters
end

local function emitFilteredParticleEmitters(root, count, extraDisabledNames)
	if not root then
		return
	end

	local emitCount = math.max(1, math.floor(tonumber(count) or DEFAULT_ACTIVE_EMIT_COUNT))
	eachSelfAndDescendants(root, function(item)
		if not item:IsA("ParticleEmitter") then
			return
		end

		if item.Enabled ~= true then
			return
		end

		local key = emitterKey(item.Name)
		if emitterDisabled(key, extraDisabledNames) then
			return
		end

		pcall(function()
			item:Emit(emitCount)
		end)
	end)
end

local function resolvePlanarDirection(direction, fallbackDirection)
	local fallback = typeof(fallbackDirection) == "Vector3" and fallbackDirection or DEFAULT_DIRECTION
	local candidate = typeof(direction) == "Vector3" and direction or fallback
	local planar = Vector3.new(candidate.X, 0, candidate.Z)
	if planar.Magnitude <= 0.01 then
		planar = Vector3.new(fallback.X, 0, fallback.Z)
	end
	if planar.Magnitude <= 0.01 then
		return DEFAULT_DIRECTION
	end

	return planar.Unit
end

local function getTargetCFrame(rootPart, options, localOffset)
	local offset = typeof(localOffset) == "CFrame" and localOffset or DEFAULT_LOCAL_OFFSET

	if type(options) == "table" and typeof(options.Position) == "Vector3" then
		local direction = resolvePlanarDirection(options.Direction, rootPart and rootPart.CFrame.LookVector)
		return CFrame.lookAt(options.Position, options.Position + direction) * offset
	end

	if isBasePart(rootPart) and rootPart.Parent then
		local direction = resolvePlanarDirection(options and options.Direction, rootPart.CFrame.LookVector)
		return CFrame.lookAt(rootPart.Position, rootPart.Position + direction) * offset
	end

	return nil
end

local function moveRootByAnchor(root, anchorPart, targetCFrame)
	if not root or not root.Parent or not isBasePart(anchorPart) or typeof(targetCFrame) ~= "CFrame" then
		return false
	end

	local delta = targetCFrame * anchorPart.CFrame:Inverse()
	local movedAnyPart = false

	eachDescendantOfType(root, "BasePart", function(part)
		part.CFrame = delta * part.CFrame
		movedAnyPart = true
	end)

	return movedAnyPart
end

-- ============================================================================
-- ATTACHED ACTIVE BODY FLAME
-- The attached body layer must never reuse the trail flame profile on-player.
-- If the authored body root overlaps the trail source, the attached body layer is
-- suppressed entirely to avoid leaking the trail visual in the wrong place.
-- ============================================================================

local function findFlameDashRoot()
	local roots = {}
	local primaryRoot = VfxCommon.FindAsset(table.unpack(ROOT_SEGMENTS))
	if primaryRoot then
		roots[#roots + 1] = primaryRoot
	end

	local legacyRoot = VfxCommon.FindAsset("VFX", "Mera")
	if legacyRoot and legacyRoot ~= primaryRoot then
		roots[#roots + 1] = legacyRoot
	end

	local bareRoot = VfxCommon.FindAsset("Mera")
	if bareRoot and bareRoot ~= primaryRoot and bareRoot ~= legacyRoot then
		roots[#roots + 1] = bareRoot
	end

	for _, root in ipairs(roots) do
		for _, effectName in ipairs(EFFECT_CANDIDATES) do
			local effectRoot = root:FindFirstChild(effectName)
			if effectRoot then
				return effectRoot
			end
		end
	end

	return nil
end

local function isLiveState(state)
	return type(state) == "table"
		and state.Kind == "FlameDash"
		and state.Destroyed ~= true
		and state.Clone ~= nil
		and state.Clone.Parent ~= nil
end

local function disconnectTrailLoop(state)
	if type(state) ~= "table" then
		return
	end

	if state.TrailConnection then
		state.TrailConnection:Disconnect()
		state.TrailConnection = nil
	end
end

local function detachFollow(state)
	if type(state) ~= "table" then
		return
	end

	if state.FollowWeld and state.FollowWeld.Parent then
		state.FollowWeld:Destroy()
	end
	state.FollowWeld = nil
end

local function destroyRuntimeState(state)
	if type(state) ~= "table" or state.Destroyed == true then
		return
	end

	state.Destroyed = true
	disconnectTrailLoop(state)
	detachFollow(state)

	local clone = state.Clone
	state.Clone = nil
	if clone and clone.Parent then
		pcall(function()
			clone:Destroy()
		end)
	end
end

local function scheduleDestroy(state, delaySeconds)
	if not isLiveState(state) then
		return
	end

	local clone = state.Clone
	local resolvedDelay = math.max(0, tonumber(delaySeconds) or 0)

	Debris:AddItem(clone, resolvedDelay + CLEANUP_BUFFER)
	task.delay(resolvedDelay, function()
		if not isLiveState(state) then
			return
		end
		if state.Clone ~= clone then
			return
		end

		destroyRuntimeState(state)
	end)
end

local function attachFollow(state, options)
	if not isLiveState(state) then
		return false
	end

	local rootPart = state.RootPart
	local clone = state.Clone
	local anchorPart = state.AnchorPart

	if not isBasePart(rootPart) or not rootPart.Parent or not clone or not clone.Parent or not isBasePart(anchorPart) then
		return false
	end

	local targetCFrame = getTargetCFrame(rootPart, options, state.LocalOffset)
	if typeof(targetCFrame) ~= "CFrame" then
		return false
	end

	detachFollow(state)

	if not moveRootByAnchor(clone, anchorPart, targetCFrame) then
		return false
	end

	state.FollowWeld = makeFollowWeld(anchorPart, rootPart)
	return state.FollowWeld ~= nil
end

local function snapToFinal(state, options)
	if not isLiveState(state) then
		return false
	end

	local targetCFrame
	local finalPosition = type(options) == "table" and options.FinalPosition or nil
	local direction = type(options) == "table" and options.Direction or nil
	if typeof(finalPosition) == "Vector3" then
		local resolvedDirection = resolvePlanarDirection(direction, state.RootPart and state.RootPart.CFrame.LookVector)
		targetCFrame = CFrame.lookAt(finalPosition, finalPosition + resolvedDirection) * state.LocalOffset
	else
		targetCFrame = getTargetCFrame(state.RootPart, options, state.LocalOffset)
	end

	if typeof(targetCFrame) ~= "CFrame" then
		return false
	end

	return moveRootByAnchor(state.Clone, state.AnchorPart, targetCFrame)
end

local function resolveHeadEmitterRate(state, emitter)
	local key = emitterKey(emitter.Name)
	if isTrailVisualEmitterName(key) then
		return 0, false
	end
	if emitterDisabled(key, ALWAYS_DISABLED_HEAD_EMITTER_NAMES) then
		return 0, false
	end

	local rate = resolveConfiguredRate(FLAME_DASH_CONFIG.ActiveHeadEmitterRates, emitter)
	if rate == nil then
		local captured = state.EmitterDefaults[emitter]
		if captured and captured.Enabled then
			local capturedRate = math.max(0, tonumber(captured.Rate) or 0)
			if capturedRate > 0 then
				rate = capturedRate * DEFAULT_ACTIVE_HEAD_STREAM_RATE_SCALE
			end
		end
	end
	if rate == nil and key then
		rate = DEFAULT_ACTIVE_HEAD_EMITTER_RATES[key]
	end

	rate = tonumber(rate) or 0
	if rate <= 0 then
		return 0, false
	end

	return math.min(rate, MAX_ACTIVE_HEAD_STREAM_RATE), true
end

local function enableActiveHeadLayer(state)
	if not isLiveState(state) or state.HeadActive == true then
		return isLiveState(state)
	end

	local headRoot = state.HeadRoot
	if not headRoot or not headRoot.Parent then
		state.HeadActive = true
		return true
	end
	if state.SuppressAttachedBodyFlame == true then
		state.HeadActive = true
		logInfo("runtime active body suppressed id=%s reason=trail_visual_overlap", tostring(state.RuntimeId))
		return true
	end

	local enabledCount, totalRate = configureParticleEmitters(headRoot, function(emitter)
		return resolveHeadEmitterRate(state, emitter)
	end)

	setAuxVisualsEnabled(headRoot, true, true)
	emitFilteredParticleEmitters(headRoot, DEFAULT_ACTIVE_EMIT_COUNT, ALWAYS_DISABLED_HEAD_EMITTER_NAMES)
	state.HeadActive = true

	logInfo(
		"runtime active id=%s head=%s emitters=%d totalRate=%.1f",
		tostring(state.RuntimeId),
		safeGetFullName(headRoot),
		enabledCount,
		totalRate
	)

	return true
end

-- ============================================================================
-- TRAIL TEMPLATE SOURCE
-- The trail source carries the same authored flame look, but it stays hidden and
-- silent on the runtime clone. It exists only to be cloned behind the player.
-- ============================================================================

local function resolveTrailCloneEmitterRate(emitter)
	local key = emitterKey(emitter.Name)
	if not isTrailVisualEmitterName(key) then
		return 0, false
	end
	if emitterDisabled(key, ALWAYS_DISABLED_TRAIL_EMITTER_NAMES) then
		return 0, false
	end

	local rate = resolveConfiguredRate(FLAME_DASH_CONFIG.TrailCloneEmitterRates, emitter)
	if rate == nil then
		rate = resolveConfiguredRate(FLAME_DASH_CONFIG.ContinuousTrailEmitterRates, emitter)
	end
	if rate == nil and key then
		rate = DEFAULT_TRAIL_CLONE_EMITTER_RATES[key]
	end

	rate = tonumber(rate) or 0
	if rate <= 0 then
		return 0, false
	end

	return math.min(rate, MAX_TRAIL_CLONE_STREAM_RATE), true
end

local function configureTrailClone(root)
	hideTrailRenderableObjects(root)
	local enabledCount, totalRate, enabledEmitters = configureParticleEmitters(root, resolveTrailCloneEmitterRate)
	setAuxVisualsEnabled(root, true, false)
	return enabledCount, totalRate, enabledEmitters
end

local function applyEmitterRateScale(emitterStates, rateScale)
	for _, emitterState in ipairs(emitterStates or {}) do
		local emitter = emitterState.Emitter
		if emitter and emitter.Parent then
			local scaledRate = math.max(0, (tonumber(emitterState.BaseRate) or 0) * math.max(0, tonumber(rateScale) or 0))
			emitter.Rate = scaledRate
			emitter.Enabled = scaledRate > 0
		end
	end
end

local function scheduleTrailCloneRateDecay(trailClone, emitterStates, lifetime)
	if not trailClone or trailClone.Parent == nil or #emitterStates == 0 then
		return
	end

	for _, stage in ipairs(TRAIL_RATE_DECAY_STAGES) do
		local delayTime = math.max(0, lifetime * math.max(0, tonumber(stage.TimeFraction) or 0))
		local rateScale = math.max(0, tonumber(stage.RateScale) or 0)
		task.delay(delayTime, function()
			if trailClone and trailClone.Parent then
				applyEmitterRateScale(emitterStates, rateScale)
			end
		end)
	end
end

local function resolveTrailSpawnData(state, samplePosition, direction)
	local trailDirection = resolvePlanarDirection(direction, state.LastTrailDirection)
	local spawnPosition = samplePosition - (trailDirection * state.TrailBackOffset)
	local spawnCFrame = CFrame.lookAt(spawnPosition, spawnPosition + trailDirection) * state.LocalOffset
	return spawnPosition, trailDirection, spawnCFrame
end

local function resolveGroundTrailPosition(state, airSpawnPosition)
	if not isLiveState(state) or typeof(airSpawnPosition) ~= "Vector3" then
		return nil
	end

	local rayOrigin = airSpawnPosition + Vector3.new(0, state.GroundTrailRaycastHeight, 0)
	local rayDirection = Vector3.new(0, -(state.GroundTrailRaycastHeight + state.GroundTrailRaycastDepth), 0)
	local result = Workspace:Raycast(rayOrigin, rayDirection, state.GroundTrailRaycastParams)
	if not result then
		return nil
	end

	return result.Position + (result.Normal * state.GroundTrailLift)
end

local function spawnTrailCloneRoot(state, spawnCFrame, cloneName)
	if not isLiveState(state) or not state.TrailTemplateRoot or typeof(spawnCFrame) ~= "CFrame" then
		return nil
	end

	local ok, trailClone = pcall(function()
		return state.TrailTemplateRoot:Clone()
	end)
	if not ok or not trailClone then
		return nil
	end

	trailClone.Name = type(cloneName) == "string" and cloneName or TRAIL_CLONE_NAME
	destroyNamedWelds(trailClone)
	trailClone.Parent = Workspace
	setPartsWorldSafe(trailClone, true)

	local cloneAnchor = resolveInstanceBySegments(trailClone, state.TrailTemplateAnchorSegments)
	if not isBasePart(cloneAnchor) then
		trailClone:Destroy()
		return nil
	end

	if not moveRootByAnchor(trailClone, cloneAnchor, spawnCFrame) then
		trailClone:Destroy()
		return nil
	end

	local enabledCount, totalRate, enabledEmitters = configureTrailClone(trailClone)
	if enabledCount <= 0 then
		trailClone:Destroy()
		return nil
	end

	local lifetime = state.TrailLifetime
	scheduleTrailCloneRateDecay(trailClone, enabledEmitters, lifetime)
	task.delay(lifetime * DEFAULT_TRAIL_DISABLE_FRACTION, function()
		if trailClone and trailClone.Parent then
			disableVisuals(trailClone)
			setAuxVisualsEnabled(trailClone, false, false)
		end
	end)

	Debris:AddItem(trailClone, lifetime + CLEANUP_BUFFER)
	return trailClone, enabledCount, totalRate
end

-- ============================================================================
-- ACTIVE CLONED TRAIL BEHIND PLAYER
-- This is the only place where the authored trail flame profile is allowed to
-- render. The system samples movement and drops filtered FX2 clones behind the
-- player at consistent spacing.
-- ============================================================================

local function spawnTrailCloneAt(state, samplePosition, direction)
	if not isLiveState(state) or not state.TrailTemplateRoot then
		return nil
	end

	local airSpawnPosition, trailDirection, airSpawnCFrame = resolveTrailSpawnData(state, samplePosition, direction)
	local trailClone, enabledCount, totalRate = spawnTrailCloneRoot(state, airSpawnCFrame, TRAIL_CLONE_NAME)
	if not trailClone then
		return nil
	end

	local groundSpawnPosition = resolveGroundTrailPosition(state, airSpawnPosition)
	if groundSpawnPosition then
		local middleSpawnPosition = airSpawnPosition:Lerp(groundSpawnPosition, 0.5)
		local middleSpawnCFrame = CFrame.lookAt(
			middleSpawnPosition,
			middleSpawnPosition + trailDirection
		) * state.LocalOffset
		spawnTrailCloneRoot(state, middleSpawnCFrame, "FlameDashMiddleTrailClone")

		local groundSpawnCFrame = CFrame.lookAt(
			groundSpawnPosition,
			groundSpawnPosition + trailDirection
		) * state.LocalOffset
		spawnTrailCloneRoot(state, groundSpawnCFrame, "FlameDashGroundTrailClone")
	end

	logDebug(
		"runtime trail clone id=%s emitters=%d totalRate=%.1f at=%s",
		tostring(state.RuntimeId),
		enabledCount,
		totalRate,
		tostring(samplePosition)
	)

	return trailClone
end

local function updateTrailDirectionFromMovement(state, currentPosition, previousPosition)
	local delta = currentPosition - previousPosition
	local planarDelta = Vector3.new(delta.X, 0, delta.Z)
	if planarDelta.Magnitude > 0.01 then
		state.LastTrailDirection = planarDelta.Unit
	end
	return delta, planarDelta.Magnitude
end

local function ensureTrailLoop(state)
	if not isLiveState(state) then
		return false
	end

	if state.TrailConnection then
		return true
	end

	state.TrailConnection = RunService.Heartbeat:Connect(function(_dt)
		if not isLiveState(state) or state.Stopped == true then
			disconnectTrailLoop(state)
			return
		end

		local currentPosition = state.RootPart.Position
		local previousPosition = state.LastSamplePosition or currentPosition
		local delta, planarDistance = updateTrailDirectionFromMovement(state, currentPosition, previousPosition)
		local distance = delta.Magnitude

		if distance > 0.001 and planarDistance > 0.001 then
			local spacing = math.max(0.3, tonumber(state.TrailSpacing) or DEFAULT_TRAIL_SPACING)
			local carriedDistance = math.max(0, tonumber(state.DistanceSinceLastClone) or 0)
			local remaining = distance
			local traveled = 0
			local clonesSpawned = 0

			while remaining > 0 and clonesSpawned < state.MaxTrailClonesPerStep do
				local toNext = spacing - carriedDistance
				if toNext > remaining then
					carriedDistance += remaining
					remaining = 0
					break
				end

				traveled += toNext
				remaining -= toNext
				carriedDistance = 0
				clonesSpawned += 1

				local alpha = math.clamp(traveled / distance, 0, 1)
				local samplePosition = previousPosition:Lerp(currentPosition, alpha)
				spawnTrailCloneAt(state, samplePosition, state.LastTrailDirection)
			end

			state.DistanceSinceLastClone = math.min(spacing, carriedDistance)
		end

		state.LastSamplePosition = currentPosition
	end)

	return true
end

-- ============================================================================
-- SUPPRESSED STARTUP / WIND / OFF-FLAME PATHS
-- Startup stays visually silent. Wind is removed from every path. The authored
-- trail flame profile is suppressed everywhere except the cloned trail behind
-- the player so the off-flame/on-player artifact cannot come back.
-- ============================================================================

local function suppressTrailTemplateSource(state)
	if not isLiveState(state) then
		return
	end

	local trailRoot = state.TrailTemplateSourceRoot or state.TrailTemplateRoot
	if not trailRoot then
		return
	end

	hideTrailRenderableObjects(trailRoot)
	disableVisuals(trailRoot)
	silenceParticleEmitters(trailRoot)
	silenceEmitterProfile(trailRoot, function(key)
		return isTrailVisualEmitterName(key) or emitterDisabled(key, ALWAYS_DISABLED_TRAIL_EMITTER_NAMES)
	end)
	setAuxVisualsEnabled(trailRoot, false, false)
end

local function suppressAttachedBodyTrailProfile(state)
	if not isLiveState(state) then
		return
	end

	local headRoot = state.AttachedActiveBodyRoot or state.HeadRoot
	if not headRoot then
		return
	end

	silenceEmitterProfile(headRoot, function(key)
		return isTrailVisualEmitterName(key) or emitterDisabled(key, ALWAYS_DISABLED_HEAD_EMITTER_NAMES)
	end)
end

local function suppressStartupWindAndOffFlamePaths(state)
	suppressTrailTemplateSource(state)
	suppressAttachedBodyTrailProfile(state)
end

local function applyRuntimeOptions(state, options)
	if type(state) ~= "table" or type(options) ~= "table" then
		return
	end

	if typeof(options.LocalOffset) == "CFrame" then
		state.LocalOffset = options.LocalOffset
	end

	if typeof(options.Direction) == "Vector3" then
		state.LastTrailDirection = resolvePlanarDirection(options.Direction, state.LastTrailDirection)
	end

	if tonumber(options.TrailCloneSpacing) then
		state.TrailSpacing = math.max(0.3, tonumber(options.TrailCloneSpacing))
	elseif tonumber(options.TrailSpacing) then
		state.TrailSpacing = math.max(0.3, tonumber(options.TrailSpacing))
	end

	if tonumber(options.TrailCloneLifetime) then
		state.TrailLifetime = math.max(0.12, tonumber(options.TrailCloneLifetime))
	elseif tonumber(options.TrailLifetime) then
		state.TrailLifetime = math.max(0.12, tonumber(options.TrailLifetime))
	end

	if tonumber(options.TrailBackOffset) then
		state.TrailBackOffset = math.max(0, tonumber(options.TrailBackOffset))
	end

	if tonumber(options.MaxTrailClonesPerStep) then
		state.MaxTrailClonesPerStep = math.max(1, math.floor(tonumber(options.MaxTrailClonesPerStep)))
	end
end

local function createRuntimeState(options)
	local rootPart = type(options) == "table" and options.RootPart or nil
	if not isBasePart(rootPart) or not rootPart.Parent then
		logWarn("runtime creation skipped reason=missing_root")
		return nil
	end

	local effectRoot = findFlameDashRoot()
	if not effectRoot then
		logWarn("runtime creation skipped reason=missing_effect_root")
		return nil
	end

	local clone = VfxCommon.Clone(effectRoot, Workspace)
	if not clone then
		logWarn("runtime creation skipped reason=clone_failed")
		return nil
	end

	local runtimeId = nextRuntimeId()
	local attachedActiveBodyRoot = findCandidateInstance(clone, HEAD_CHILD_CANDIDATES)
		or findCandidateInstance(clone, STARTUP_CHILD_CANDIDATES)
	local trailTemplateSourceRoot = findCandidateInstance(clone, ACTIVE_TRAIL_SOURCE_CHILD_CANDIDATES)
		or findCandidateInstance(clone, TRAIL_CHILD_CANDIDATES)
	local anchorPart = findFirstBasePart(attachedActiveBodyRoot) or findFirstBasePart(clone)
	local trailAnchor = findFirstBasePart(trailTemplateSourceRoot)

	if not isBasePart(anchorPart) or not trailTemplateSourceRoot or not isBasePart(trailAnchor) then
		clone:Destroy()
		logWarn("runtime creation skipped reason=missing_head_or_trail")
		return nil
	end

	local emitterDefaults = captureEmitterDefaults(clone)
	setPartsWorldSafe(clone, false)
	disableVisuals(clone)
	setAuxVisualsEnabled(clone, false, false)

	pruneTrailPathEffects(trailTemplateSourceRoot)

	local initialDirection = resolvePlanarDirection(
		type(options) == "table" and options.Direction or nil,
		rootPart.CFrame.LookVector
	)

	local state = {
		RuntimeId = runtimeId,
		Kind = "FlameDash",
		Clone = clone,
		RootPart = rootPart,
		AnchorPart = anchorPart,
		AttachedActiveBodyRoot = attachedActiveBodyRoot,
		HeadRoot = attachedActiveBodyRoot,
		TrailTemplateSourceRoot = trailTemplateSourceRoot,
		TrailTemplateRoot = trailTemplateSourceRoot,
		TrailTemplateAnchorSegments = buildRelativePathSegments(trailTemplateSourceRoot, trailAnchor) or {},
		EmitterDefaults = emitterDefaults,
		FollowWeld = nil,
		TrailConnection = nil,
		LocalOffset = (type(options) == "table" and typeof(options.LocalOffset) == "CFrame" and options.LocalOffset)
			or DEFAULT_LOCAL_OFFSET,
		LastSamplePosition = rootPart.Position,
		LastTrailDirection = initialDirection,
		DistanceSinceLastClone = 0,
		TrailSpacing = DEFAULT_TRAIL_SPACING,
		TrailLifetime = DEFAULT_TRAIL_LIFETIME,
		TrailBackOffset = DEFAULT_TRAIL_BACK_OFFSET,
		GroundTrailRaycastHeight = DEFAULT_GROUND_TRAIL_RAYCAST_HEIGHT,
		GroundTrailRaycastDepth = DEFAULT_GROUND_TRAIL_RAYCAST_DEPTH,
		GroundTrailLift = DEFAULT_GROUND_TRAIL_LIFT,
		GroundTrailRaycastParams = buildGroundTrailRaycastParams({
			rootPart.Parent,
			clone,
		}),
		MaxTrailClonesPerStep = DEFAULT_MAX_TRAIL_CLONES_PER_STEP,
		StartupPlayed = false,
		HeadActive = false,
		DashPlayed = false,
		Stopped = false,
		Destroyed = false,
		SuppressAttachedBodyFlame = shouldSuppressAttachedBodyLayer(
			attachedActiveBodyRoot,
			trailTemplateSourceRoot
		),
	}

	applyRuntimeOptions(state, options)
	suppressStartupWindAndOffFlamePaths(state)

	if not attachFollow(state, options) then
		destroyRuntimeState(state)
		logWarn("runtime creation skipped reason=follow_attach_failed")
		return nil
	end

	logInfo(
		"runtime created id=%s root=%s head=%s trail=%s bodySuppressed=%s",
		tostring(runtimeId),
		safeGetFullName(rootPart),
		safeGetFullName(attachedActiveBodyRoot),
		safeGetFullName(trailTemplateSourceRoot),
		tostring(state.SuppressAttachedBodyFlame)
	)

	return state
end

local function getOrCreateRuntimeState(options)
	if type(options) == "table" and isLiveState(options.RuntimeState) then
		return options.RuntimeState
	end

	return createRuntimeState(options)
end

local function updateRuntimeTransform(state, options)
	if not isLiveState(state) then
		return false
	end

	applyRuntimeOptions(state, options)

	if not state.FollowWeld or state.FollowWeld.Parent == nil then
		return attachFollow(state, options)
	end

	return true
end

local function stopRuntimeState(state, options, defaults)
	if not isLiveState(state) then
		return false
	end

	if state.Stopped then
		if type(options) == "table" and options.ImmediateCleanup == true then
			destroyRuntimeState(state)
		end
		return false
	end

	state.Stopped = true
	disconnectTrailLoop(state)

	if type(options) == "table" and options.ImmediateCleanup == true then
		destroyRuntimeState(state)
		return true
	end

	detachFollow(state)
	snapToFinal(state, options)
	disableVisuals(state.Clone)
	setAuxVisualsEnabled(state.Clone, false, false)

	local fadeTime = math.max(0, tonumber(type(options) == "table" and options.FadeTime) or defaults.FadeTime)
	local holdTime = math.max(0, tonumber(type(options) == "table" and options.HoldTime) or defaults.HoldTime)
	scheduleDestroy(state, fadeTime + holdTime)

	logInfo("runtime stopped id=%s", tostring(state.RuntimeId))
	return true
end

function FlameDashVfx.PlayFlameDashStartup(options)
	local state = getOrCreateRuntimeState(options)
	if not state then
		return nil
	end

	updateRuntimeTransform(state, options)
	suppressStartupWindAndOffFlamePaths(state)

	if not state.StartupPlayed then
		state.StartupPlayed = true
		logInfo("runtime startup suppressed id=%s", tostring(state.RuntimeId))
	end

	return state
end

function FlameDashVfx.StartFlameDashHead(options)
	local state = getOrCreateRuntimeState(options)
	if not state then
		return nil
	end

	updateRuntimeTransform(state, options)
	suppressStartupWindAndOffFlamePaths(state)
	enableActiveHeadLayer(state)
	return state
end

function FlameDashVfx.StartFlameDashPart(options)
	local state = getOrCreateRuntimeState(options)
	if not state then
		return nil
	end

	updateRuntimeTransform(state, options)
	suppressStartupWindAndOffFlamePaths(state)
	enableActiveHeadLayer(state)

	if not state.DashPlayed then
		state.DashPlayed = true
		state.LastSamplePosition = state.RootPart.Position
		state.DistanceSinceLastClone = 0
		spawnTrailCloneAt(state, state.RootPart.Position, state.LastTrailDirection)
		logInfo(
			"runtime trail started id=%s spacing=%.2f lifetime=%.2f backOffset=%.2f",
			tostring(state.RuntimeId),
			state.TrailSpacing,
			state.TrailLifetime,
			state.TrailBackOffset
		)
	end

	ensureTrailLoop(state)
	return state
end

function FlameDashVfx.UpdateFlameDashHead(state, options)
	return updateRuntimeTransform(state, options)
end

function FlameDashVfx.UpdateFlameDashPart(state, options)
	return updateRuntimeTransform(state, options)
end

function FlameDashVfx.StopFlameDashHead(state, options)
	return stopRuntimeState(state, options, {
		FadeTime = DEFAULT_ACTIVE_FADE_TIME,
		HoldTime = DEFAULT_ACTIVE_HOLD_TIME,
	})
end

function FlameDashVfx.StopFlameDashPart(state, options)
	return stopRuntimeState(state, options, {
		FadeTime = DEFAULT_ACTIVE_FADE_TIME,
		HoldTime = DEFAULT_ACTIVE_HOLD_TIME,
	})
end

function FlameDashVfx.StopFlameDashStartup(state, options)
	if type(options) ~= "table" then
		options = {}
	end

	return stopRuntimeState(state, options, {
		FadeTime = DEFAULT_STARTUP_FADE_TIME,
		HoldTime = DEFAULT_STARTUP_HOLD_TIME,
	})
end

function FlameDashVfx.PlayStartup(options)
	return FlameDashVfx.PlayFlameDashStartup(options)
end

function FlameDashVfx.StopStartup(state, options)
	return FlameDashVfx.StopFlameDashStartup(state, options)
end

function FlameDashVfx.StartBody(options)
	return FlameDashVfx.StartFlameDashHead(options)
end

function FlameDashVfx.UpdateBody(state, options)
	return FlameDashVfx.UpdateFlameDashHead(state, options)
end

function FlameDashVfx.StopBody(state, options)
	return FlameDashVfx.StopFlameDashHead(state, options)
end

function FlameDashVfx.StartTrail(options)
	return FlameDashVfx.StartFlameDashPart(options)
end

function FlameDashVfx.UpdateTrail(state, options)
	return FlameDashVfx.UpdateFlameDashPart(state, options)
end

function FlameDashVfx.StopTrail(state, options)
	return FlameDashVfx.StopFlameDashPart(state, options)
end

return FlameDashVfx
