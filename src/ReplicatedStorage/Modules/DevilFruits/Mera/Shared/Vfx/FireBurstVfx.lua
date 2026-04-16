--[[
	FireBurstVfx uses the authored `Flame burst` hierarchy directly.

	Authored phases:
	- `Start up`: charge / pre-cast visuals
	- `Burst`: main explosion visuals

	Runtime flow:
	- clone the full `Flame burst` root once
	- place it from the authored phase pivot instead of the wrapper folder
	- align the phase root to the player's facing direction
	- preserve the authored body/floor split so the burst stays on the player while
	  floor flames stay on the ground
	- play `Start up`
	- on release, reuse the same clone and play `Burst`
	- let startup floor flames linger briefly
	- clean up the whole authored root after particles finish
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MeraConfig = require(script.Parent.Parent:WaitForChild("MeraConfig"))
local VfxCommon = require(script.Parent:WaitForChild("VfxCommon"))

local FireBurstVfx = {}

local DEBUG_INFO = RunService:IsStudio()
local FLAME_BURST_CONFIG = MeraConfig.FlameBurst or {}
local SHARED_CONFIG = MeraConfig.Shared or {}

local ROOT_SEGMENTS = SHARED_CONFIG.RootSegments or { "Assets", "VFX", "Mera" }
local EFFECT_CANDIDATES = FLAME_BURST_CONFIG.EffectCandidates or { "Flame burst", "Flame Burst" }
local STARTUP_CHILD_CANDIDATES = FLAME_BURST_CONFIG.StartupChildCandidates or { "Start up", "Startup" }
local BURST_CHILD_CANDIDATES = FLAME_BURST_CONFIG.BurstChildCandidates or { "Burst", "FX" }
local BURST_SUPPRESSED_DESCENDANT_NAMES = FLAME_BURST_CONFIG.SuppressBurstDescendantNames
	or { "WindTornado", "windtwirl tech" }
local BURST_DEBUG_KEYWORDS = { "wind", "wave", "shock", "cres", "slam", "bubble", "ring" }

local DEFAULT_STARTUP_EMIT_COUNT = math.max(0, tonumber(FLAME_BURST_CONFIG.StartupEmitCount) or 3)
local DEFAULT_BURST_EMIT_COUNT = math.max(0, tonumber(FLAME_BURST_CONFIG.BurstEmitCount) or 6)
local DEFAULT_STARTUP_FADE_TIME = 0.08
local DEFAULT_STARTUP_HOLD_TIME = 0.18
local DEFAULT_BURST_FADE_TIME = math.max(0.12, tonumber(FLAME_BURST_CONFIG.FadeTime) or 0.22)
local DEFAULT_BURST_HOLD_TIME = 1.8
local DEFAULT_STARTUP_LINGER_AFTER_RELEASE = 0.2
local DEFAULT_STARTUP_SAFETY_LIFETIME = 4
local DEFAULT_BURST_CLEANUP_BUFFER = 2.2
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local LOOK_AT_DISTANCE = 4
local GROUND_RAYCAST_UP = 6
local GROUND_RAYCAST_DOWN = 18
local PHASE_FLOOR_REFERENCE_CANDIDATES = FLAME_BURST_CONFIG.PhaseFloorReferenceCandidates or { "Floo", "Ground" }
local ROOT_ROTATION_CORRECTION = FLAME_BURST_CONFIG.RootRotationCorrection

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	print(string.format("[MERA VFX][FIREBURST] " .. message, ...))
end

local function logWarn(message, ...)
	warn(string.format("[MERA VFX][FIREBURST] " .. message, ...))
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

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

local function buildNameLookup(names)
	local lookup = {}
	for _, name in ipairs(names or {}) do
		if type(name) == "string" and name ~= "" then
			lookup[name] = true
		end
	end

	return lookup
end

local function cancelTask(taskHandle)
	if taskHandle == nil then
		return
	end

	pcall(task.cancel, taskHandle)
end

local function removeNamedDescendants(root, names)
	if not root then
		return 0
	end

	local nameLookup = buildNameLookup(names)
	if next(nameLookup) == nil then
		return 0
	end

	local matches = {}
	eachSelfAndDescendants(root, function(item)
		if item ~= root and nameLookup[item.Name] then
			matches[#matches + 1] = item
		end
	end)

	local removedCount = 0
	for _, item in ipairs(matches) do
		if item.Parent then
			removedCount += 1
			pcall(function()
				item:Destroy()
			end)
		end
	end

	return removedCount
end

local function getRelativePath(root, item)
	if not (root and item) then
		return "<unknown>"
	end

	local segments = {}
	local current = item
	while current and current ~= root do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end

	if current == root then
		table.insert(segments, 1, root.Name)
	end

	return table.concat(segments, "/")
end

local function collectKeywordDescendants(root, keywords)
	local matches = {}
	if not root then
		return matches
	end

	eachSelfAndDescendants(root, function(item)
		if item == root then
			return
		end

		local loweredName = string.lower(item.Name)
		for _, keyword in ipairs(keywords or {}) do
			if string.find(loweredName, keyword, 1, true) then
				matches[#matches + 1] = string.format("%s[%s]", getRelativePath(root, item), item.ClassName)
				break
			end
		end
	end)

	table.sort(matches)
	return matches
end

local function setEffectAnchored(root, anchored)
	eachDescendantOfType(root, "BasePart", function(part)
		part.Anchored = anchored
	end)
end

local function getInstancePivotCFrame(instance)
	if not instance then
		return nil
	end

	if instance:IsA("Model") then
		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok then
			return pivot
		end
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.CFrame
		end
	end

	return nil
end

local function applyLocalRotationCorrection(baseCFrame, rotationCorrection)
	if typeof(rotationCorrection) ~= "CFrame" then
		return baseCFrame
	end

	return baseCFrame * rotationCorrection
end

local function resolveFireBurstDirection(direction, fallbackDirection)
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

local function repositionCloneFromAnchor(clone, anchorInstance, targetCFrame)
	if not clone or typeof(targetCFrame) ~= "CFrame" then
		return false
	end

	local currentPivot = getInstancePivotCFrame(anchorInstance) or getInstancePivotCFrame(clone)
	if not currentPivot then
		return false
	end

	local delta = targetCFrame * currentPivot:Inverse()
	local movedAnyPart = false
	eachDescendantOfType(clone, "BasePart", function(part)
		part.CFrame = delta * part.CFrame
		movedAnyPart = true
	end)

	return movedAnyPart
end

local function buildGroundRaycastParams(rootPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local filter = {}
	if rootPart and rootPart.Parent then
		filter[#filter + 1] = rootPart.Parent
	end
	params.FilterDescendantsInstances = filter

	return params
end

local function resolveGroundPosition(rootPart)
	local origin = rootPart.Position
	local rayOrigin = origin + Vector3.new(0, GROUND_RAYCAST_UP, 0)
	local rayDirection = Vector3.new(0, -GROUND_RAYCAST_DOWN, 0)
	local raycastResult = Workspace:Raycast(rayOrigin, rayDirection, buildGroundRaycastParams(rootPart))
	return raycastResult and raycastResult.Position or origin
end

local function findFireBurstRoot()
	local meraRoot = VfxCommon.FindAsset(table.unpack(ROOT_SEGMENTS))
	if not meraRoot then
		return nil, nil, "Assets/VFX/Mera not found"
	end

	for _, name in ipairs(EFFECT_CANDIDATES) do
		local child = meraRoot:FindFirstChild(name)
		if child then
			return child, string.format("Assets/VFX/Mera/%s", child.Name), nil
		end
	end

	return nil, nil, "Flame burst root not found"
end

local function findPhaseGroup(root, candidates)
	return VfxCommon.FindChild(root, candidates)
end

local function captureGroupState(group)
	if not group then
		return nil
	end

	local state = {
		Group = group,
		BaseParts = {},
		SurfaceVisuals = {},
		Effects = {},
	}

	eachSelfAndDescendants(group, function(item)
		if item:IsA("BasePart") then
			state.BaseParts[#state.BaseParts + 1] = {
				Instance = item,
				Transparency = item.Transparency,
			}
			return
		end

		if item:IsA("Decal") or item:IsA("Texture") then
			state.SurfaceVisuals[#state.SurfaceVisuals + 1] = {
				Instance = item,
				Transparency = item.Transparency,
			}
			return
		end

		if item:IsA("ParticleEmitter")
			or item:IsA("Beam")
			or item:IsA("Trail")
			or item:IsA("Smoke")
			or item:IsA("Fire")
			or item:IsA("Sparkles")
			or item:IsA("PointLight")
			or item:IsA("SpotLight")
			or item:IsA("SurfaceLight")
		then
			local enabled = nil
			local ok, result = pcall(function()
				return item.Enabled
			end)
			if ok then
				enabled = result
			end

			state.Effects[#state.Effects + 1] = {
				Instance = item,
				Enabled = enabled,
			}
		end
	end)

	return state
end

local function setGroupVisible(groupState, visible)
	if not groupState then
		return
	end

	for _, entry in ipairs(groupState.BaseParts) do
		if entry.Instance.Parent then
			entry.Instance.Transparency = visible and entry.Transparency or 1
		end
	end

	for _, entry in ipairs(groupState.SurfaceVisuals) do
		if entry.Instance.Parent then
			entry.Instance.Transparency = visible and entry.Transparency or 1
		end
	end
end

local function setGroupEffectsEnabled(groupState, enabled, restoreOriginal)
	if not groupState then
		return
	end

	for _, entry in ipairs(groupState.Effects) do
		local item = entry.Instance
		if not item.Parent or entry.Enabled == nil then
			continue
		end

		local targetEnabled = false
		if enabled then
			if item:IsA("ParticleEmitter") then
				if restoreOriginal then
					targetEnabled = entry.Enabled == true
				else
					targetEnabled = true
				end
			else
				targetEnabled = true
			end
		end

		pcall(function()
			item.Enabled = targetEnabled
		end)
	end
end

local function emitGroupParticles(groupState, emitCount)
	if not groupState then
		return
	end

	local resolvedCount = math.max(1, math.floor(tonumber(emitCount) or 0))
	if resolvedCount <= 0 then
		return
	end

	for _, entry in ipairs(groupState.Effects) do
		local item = entry.Instance
		if not (item.Parent and item:IsA("ParticleEmitter")) then
			continue
		end

		-- Keep authored-enabled emitters from getting a full extra burst, but still let
		-- authored-disabled or explicitly burst-driven emitters fire on activation.
		local explicitEmitCount = tonumber(item:GetAttribute("EmitCount"))
		local shouldManualEmit = entry.Enabled ~= true or explicitEmitCount ~= nil
		if shouldManualEmit then
			pcall(function()
				item:Emit(math.max(1, math.floor(explicitEmitCount or resolvedCount)))
			end)
		end
	end
end

local function hideGroup(groupState)
	if not groupState then
		return
	end

	setGroupEffectsEnabled(groupState, false, false)
	setGroupVisible(groupState, false)
end

local function quietGroup(groupState)
	if not groupState then
		return
	end

	setGroupEffectsEnabled(groupState, false, false)
end

local function activateGroup(groupState, emitCount)
	if not groupState then
		return false
	end

	setGroupVisible(groupState, true)
	setGroupEffectsEnabled(groupState, true, true)

	if tonumber(emitCount) and emitCount > 0 then
		emitGroupParticles(groupState, emitCount)
	end

	return true
end

local function isUsableRuntimeState(state)
	return type(state) == "table"
		and state.Kind == "FireBurst"
		and state.Clone ~= nil
		and state.Clone.Parent ~= nil
		and state.Stopped ~= true
end

local function destroyRuntimeState(state)
	if type(state) ~= "table" then
		return
	end

	cancelTask(state.StartupHideTask)
	cancelTask(state.CleanupTask)
	state.StartupHideTask = nil
	state.CleanupTask = nil

	local clone = state.Clone
	state.Clone = nil
	if clone and clone.Parent then
		pcall(function()
			clone:Destroy()
		end)
	end
end

local function scheduleDestroy(state, delaySeconds)
	if not isUsableRuntimeState(state) then
		return
	end

	cancelTask(state.CleanupTask)
	local clone = state.Clone
	local resolvedDelay = math.max(0, tonumber(delaySeconds) or 0)
	Debris:AddItem(clone, resolvedDelay + 1)
	state.CleanupTask = task.delay(resolvedDelay, function()
		if state.Clone ~= clone then
			return
		end

		destroyRuntimeState(state)
	end)
end

local function stopRuntimeState(state, options, defaults)
	if type(state) ~= "table" then
		return false
	end

	cancelTask(state.StartupHideTask)
	cancelTask(state.CleanupTask)
	state.StartupHideTask = nil
	state.CleanupTask = nil

	if state.Stopped then
		if options and options.ImmediateCleanup then
			destroyRuntimeState(state)
		end
		return false
	end

	state.Stopped = true

	if options and options.ImmediateCleanup then
		destroyRuntimeState(state)
		return true
	end

	quietGroup(state.StartupGroupState)
	quietGroup(state.BurstGroupState)

	local fadeTime = math.max(0, tonumber(options and options.FadeTime) or defaults.FadeTime)
	local holdTime = math.max(0, tonumber(options and options.HoldTime) or defaults.HoldTime)

	task.delay(fadeTime, function()
		hideGroup(state.StartupGroupState)
		hideGroup(state.BurstGroupState)
	end)

	scheduleDestroy(state, fadeTime + holdTime)
	return true
end

local function createRuntimeStateFromRoot(rootClone, assetPath)
	local startupGroup = findPhaseGroup(rootClone, STARTUP_CHILD_CANDIDATES)
	local burstGroup = findPhaseGroup(rootClone, BURST_CHILD_CANDIDATES)
	local startupGroupState = captureGroupState(startupGroup)

	local removedBurstDescendants = removeNamedDescendants(burstGroup, BURST_SUPPRESSED_DESCENDANT_NAMES)
	if removedBurstDescendants > 0 then
		logInfo(
			"burst descendants removed count=%d names=%s",
			removedBurstDescendants,
			table.concat(BURST_SUPPRESSED_DESCENDANT_NAMES, ",")
		)
	end

	local remainingBurstCandidates = collectKeywordDescendants(burstGroup, BURST_DEBUG_KEYWORDS)
	if #remainingBurstCandidates > 0 then
		logInfo("burst candidate descendants=%s", table.concat(remainingBurstCandidates, " | "))
	end

	local burstGroupState = captureGroupState(burstGroup)

	if not startupGroupState and not burstGroupState then
		return nil, "missing_startup_and_burst_groups"
	end

	return {
		Kind = "FireBurst",
		Clone = rootClone,
		AssetPath = assetPath,
		StartupGroupState = startupGroupState,
		BurstGroupState = burstGroupState,
		BurstTriggered = false,
		Stopped = false,
		StartupHideTask = nil,
		CleanupTask = nil,
	}
end

local function findPlacementAnchor(runtimeState)
	if runtimeState and runtimeState.StartupGroupState and runtimeState.StartupGroupState.Group then
		return runtimeState.StartupGroupState.Group
	end

	if runtimeState and runtimeState.BurstGroupState and runtimeState.BurstGroupState.Group then
		return runtimeState.BurstGroupState.Group
	end

	return runtimeState and runtimeState.Clone
end

local function findPhaseFloorReference(runtimeState)
	local candidateGroups = {
		runtimeState and runtimeState.StartupGroupState and runtimeState.StartupGroupState.Group,
		runtimeState and runtimeState.BurstGroupState and runtimeState.BurstGroupState.Group,
	}

	for _, group in ipairs(candidateGroups) do
		if group then
			for _, name in ipairs(PHASE_FLOOR_REFERENCE_CANDIDATES) do
				local direct = group:FindFirstChild(name)
				if direct and direct:IsA("BasePart") then
					return direct
				end

				local descendant = group:FindFirstChild(name, true)
				if descendant and descendant:IsA("BasePart") then
					return descendant
				end
			end
		end
	end

	return nil
end

local function buildPlacementCFrame(rootPart, direction, runtimeState)
	local resolvedDirection = resolveFireBurstDirection(direction, rootPart and rootPart.CFrame.LookVector or DEFAULT_DIRECTION)
	local groundPosition = resolveGroundPosition(rootPart)
	local anchorInstance = findPlacementAnchor(runtimeState)
	local anchorPivot = getInstancePivotCFrame(anchorInstance)
	local floorReference = findPhaseFloorReference(runtimeState)
	local floorOffset = 0

	if anchorPivot and floorReference then
		floorOffset = math.max(0, anchorPivot.Position.Y - floorReference.Position.Y)
	end

	local targetPosition = Vector3.new(rootPart.Position.X, groundPosition.Y + floorOffset, rootPart.Position.Z)
	local baseCFrame = CFrame.lookAt(targetPosition, targetPosition + (resolvedDirection * LOOK_AT_DISTANCE), Vector3.yAxis)
	local placementCFrame = applyLocalRotationCorrection(baseCFrame, ROOT_ROTATION_CORRECTION)

	return placementCFrame, {
		AnchorInstance = anchorInstance,
		AnchorPivot = anchorPivot,
		FloorReference = floorReference,
		GroundPosition = groundPosition,
		FloorOffset = floorOffset,
		ResolvedDirection = resolvedDirection,
	}
end

local function createFireBurstRootRuntime(options)
	local rootPart = options and options.RootPart
	if not rootPart or not rootPart.Parent then
		logInfo("skip create runtime reason=no_root")
		return nil
	end

	local rootSource, assetPath, err = findFireBurstRoot()
	if not rootSource then
		logWarn("root asset missing reason=%s", tostring(err))
		return nil
	end

	local clone = VfxCommon.Clone(rootSource, Workspace)
	if not clone then
		logWarn("root clone failed path=%s", tostring(assetPath))
		return nil
	end

	setEffectAnchored(clone, true)

	local runtimeState, stateError = createRuntimeStateFromRoot(clone, assetPath)
	if not runtimeState then
		pcall(function()
			clone:Destroy()
		end)
		logWarn("runtime creation failed path=%s reason=%s", tostring(assetPath), tostring(stateError))
		return nil
	end

	local placement, placementDebug = buildPlacementCFrame(rootPart, options and options.Direction, runtimeState)
	repositionCloneFromAnchor(clone, placementDebug and placementDebug.AnchorInstance, placement)

	hideGroup(runtimeState.StartupGroupState)
	hideGroup(runtimeState.BurstGroupState)

	logInfo(
		"root clone placed path=%s root=%s ground=%s floorOffset=%.2f direction=%s anchor=%s startup=%s burst=%s",
		tostring(assetPath),
		formatVector3(rootPart.Position),
		formatVector3(placementDebug and placementDebug.GroundPosition),
		tonumber(placementDebug and placementDebug.FloorOffset) or 0,
		formatVector3(placementDebug and placementDebug.ResolvedDirection),
		placementDebug and placementDebug.AnchorInstance and placementDebug.AnchorInstance.Name or "<none>",
		tostring(runtimeState.StartupGroupState ~= nil),
		tostring(runtimeState.BurstGroupState ~= nil)
	)

	return runtimeState
end

function FireBurstVfx.PlayStartup(options)
	local runtimeState = createFireBurstRootRuntime(options)
	if not runtimeState then
		return nil
	end

	if runtimeState.StartupGroupState then
		activateGroup(runtimeState.StartupGroupState, tonumber(options and options.EmitCount) or DEFAULT_STARTUP_EMIT_COUNT)
		logInfo("startup begin path=%s", tostring(runtimeState.AssetPath))
	else
		logWarn("startup group missing path=%s", tostring(runtimeState.AssetPath))
	end

	scheduleDestroy(runtimeState, DEFAULT_STARTUP_SAFETY_LIFETIME)
	return runtimeState
end

function FireBurstVfx.StopStartup(state, options)
	return stopRuntimeState(state, options, {
		FadeTime = DEFAULT_STARTUP_FADE_TIME,
		HoldTime = DEFAULT_STARTUP_HOLD_TIME,
	})
end

function FireBurstVfx.PlayBurst(options)
	local runtimeState = isUsableRuntimeState(options and options.ExistingState) and options.ExistingState or nil
	if not runtimeState then
		runtimeState = createFireBurstRootRuntime(options)
		if not runtimeState then
			return nil
		end
	end

	if runtimeState.BurstTriggered then
		return runtimeState
	end

	runtimeState.BurstTriggered = true

	if runtimeState.StartupGroupState then
		quietGroup(runtimeState.StartupGroupState)
		cancelTask(runtimeState.StartupHideTask)
		runtimeState.StartupHideTask = task.delay(DEFAULT_STARTUP_LINGER_AFTER_RELEASE, function()
			hideGroup(runtimeState.StartupGroupState)
			runtimeState.StartupHideTask = nil
		end)
	end

	if runtimeState.BurstGroupState then
		activateGroup(runtimeState.BurstGroupState, tonumber(options and options.EmitCount) or DEFAULT_BURST_EMIT_COUNT)
		logInfo("burst begin path=%s", tostring(runtimeState.AssetPath))
	else
		logWarn("burst group missing path=%s", tostring(runtimeState.AssetPath))
	end

	local duration = math.max(0.1, tonumber(options and options.Duration) or 0.6)
	scheduleDestroy(runtimeState, duration + DEFAULT_BURST_CLEANUP_BUFFER)
	return runtimeState
end

function FireBurstVfx.StopBurst(state, options)
	return stopRuntimeState(state, options, {
		FadeTime = DEFAULT_BURST_FADE_TIME,
		HoldTime = DEFAULT_BURST_HOLD_TIME,
	})
end

function FireBurstVfx.StopState(state, options)
	return FireBurstVfx.StopBurst(state, options)
end

return FireBurstVfx
