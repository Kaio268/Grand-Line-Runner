local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local HieConfig = require(script.Parent:WaitForChild("HieConfig"))

local HieVfx = {}

local DEBUG_ENABLED = RunService:IsStudio()
local ROOT_SEGMENTS = { "Assets", "VFX", "Hie" }
local FREEZE_SHOT_NAME = "Freeze Shot"
local ICE_BOOST_NAME = "Ice Boost"
local FREEZE_PROJECTILE_CHILDREN = { "ice shard", "A" }
local FREEZE_PROJECTILE_CORE_NAME = "ice shard"
local FREEZE_IMPACT_CHILDREN = { "explosion", "B", "smoke", "snowflake", "specs", "stars" }
local ICE_BOOST_CHILDREN = { "FX", "A", "Attachment", "B", "smoke", "snowflake", "specs", "stars" }
local DEFAULT_EMIT_COUNT = 20

-- Freeze Shot visual defaults/fallbacks.
-- Main projectile and impact scale should be edited in Modules/Configs/DevilFruits.lua -> Hie -> FreezeShot.
local FREEZE_SHOT_VISUAL_DEFAULTS = {
	ProjectileScale = 1.2,
	ProjectileParticleScale = 1.12,
	ProjectileTrailWidthScale = 1.16,
	ProjectileLightRangeScale = 1.12,
	ProjectileEmitCount = 14,
	ImpactScale = 1.45,
	ImpactParticleSpeedScale = 1.15,
	ImpactLightRangeScale = 1.35,
	ImpactEmitCount = 32,
	ImpactBriefContinuousDuration = 0.12,
}
local FREEZE_SHOT_PROJECTILE_PARTICLE_RATIO = FREEZE_SHOT_VISUAL_DEFAULTS.ProjectileParticleScale
	/ FREEZE_SHOT_VISUAL_DEFAULTS.ProjectileScale
local FREEZE_SHOT_PROJECTILE_TRAIL_RATIO = FREEZE_SHOT_VISUAL_DEFAULTS.ProjectileTrailWidthScale
	/ FREEZE_SHOT_VISUAL_DEFAULTS.ProjectileScale
local FREEZE_SHOT_PROJECTILE_LIGHT_RATIO = FREEZE_SHOT_VISUAL_DEFAULTS.ProjectileLightRangeScale
	/ FREEZE_SHOT_VISUAL_DEFAULTS.ProjectileScale
local FREEZE_SHOT_IMPACT_PARTICLE_SPEED_RATIO = FREEZE_SHOT_VISUAL_DEFAULTS.ImpactParticleSpeedScale
	/ FREEZE_SHOT_VISUAL_DEFAULTS.ImpactScale
local FREEZE_SHOT_IMPACT_LIGHT_RATIO = FREEZE_SHOT_VISUAL_DEFAULTS.ImpactLightRangeScale
	/ FREEZE_SHOT_VISUAL_DEFAULTS.ImpactScale

local IMPACT_LIFETIME = 2.5
local ICE_BOOST_ROOT_OFFSET = CFrame.new(0, -2.5, 0)
local INFO_COOLDOWN = 0.25
local WARN_COOLDOWN = 3

local function debugLog(message, ...)
	if not DEBUG_ENABLED then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("HieVfx:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[HIE VFX] " .. message, ...))
end

local function warnLog(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("HieVfx:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[HIE VFX][WARN] " .. message, ...))
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function scaleNumberSequence(sequence, scale)
	if typeof(sequence) ~= "NumberSequence" or typeof(scale) ~= "number" then
		return sequence
	end

	local scaledKeypoints = table.create(#sequence.Keypoints)
	for index, keypoint in ipairs(sequence.Keypoints) do
		scaledKeypoints[index] = NumberSequenceKeypoint.new(
			keypoint.Time,
			math.max(0, keypoint.Value * scale),
			math.max(0, keypoint.Envelope * scale)
		)
	end

	return NumberSequence.new(scaledKeypoints)
end

local function scaleNumberRange(range, scale)
	if typeof(range) ~= "NumberRange" or typeof(scale) ~= "number" then
		return range
	end

	return NumberRange.new(
		math.max(0, range.Min * scale),
		math.max(0, range.Max * scale)
	)
end

local function resolvePositiveNumber(value, fallback)
	local numericValue = tonumber(value)
	if numericValue and numericValue > 0 then
		return numericValue
	end

	return fallback
end

local function getFreezeShotVisualConfig()
	local resolvedConfig = table.clone(FREEZE_SHOT_VISUAL_DEFAULTS)
	local abilityConfig = HieConfig.GetAbilityConfig("FreezeShot")
	if typeof(abilityConfig) ~= "table" then
		return resolvedConfig
	end

	local projectileScale = resolvePositiveNumber(abilityConfig.VisualProjectileScale, resolvedConfig.ProjectileScale)
	local impactScale = resolvePositiveNumber(abilityConfig.VisualImpactScale, resolvedConfig.ImpactScale)

	resolvedConfig.ProjectileScale = projectileScale
	resolvedConfig.ProjectileParticleScale = resolvePositiveNumber(
		abilityConfig.VisualProjectileParticleScale,
		projectileScale * FREEZE_SHOT_PROJECTILE_PARTICLE_RATIO
	)
	resolvedConfig.ProjectileTrailWidthScale = resolvePositiveNumber(
		abilityConfig.VisualProjectileTrailWidthScale,
		projectileScale * FREEZE_SHOT_PROJECTILE_TRAIL_RATIO
	)
	resolvedConfig.ProjectileLightRangeScale = resolvePositiveNumber(
		abilityConfig.VisualProjectileLightRangeScale,
		projectileScale * FREEZE_SHOT_PROJECTILE_LIGHT_RATIO
	)
	resolvedConfig.ProjectileEmitCount = resolvePositiveNumber(
		abilityConfig.VisualProjectileEmitCount,
		resolvedConfig.ProjectileEmitCount
	)

	resolvedConfig.ImpactScale = impactScale
	resolvedConfig.ImpactParticleSpeedScale = resolvePositiveNumber(
		abilityConfig.VisualImpactParticleSpeedScale,
		impactScale * FREEZE_SHOT_IMPACT_PARTICLE_SPEED_RATIO
	)
	resolvedConfig.ImpactLightRangeScale = resolvePositiveNumber(
		abilityConfig.VisualImpactLightRangeScale,
		impactScale * FREEZE_SHOT_IMPACT_LIGHT_RATIO
	)
	resolvedConfig.ImpactEmitCount = resolvePositiveNumber(
		abilityConfig.VisualImpactEmitCount,
		resolvedConfig.ImpactEmitCount
	)
	resolvedConfig.ImpactBriefContinuousDuration = math.max(
		0,
		tonumber(abilityConfig.VisualImpactBriefContinuousDuration) or resolvedConfig.ImpactBriefContinuousDuration
	)

	return resolvedConfig
end

local function buildPathLabel(effectName, childName)
	local segments = { "ReplicatedStorage" }
	for _, segment in ipairs(ROOT_SEGMENTS) do
		table.insert(segments, segment)
	end
	if typeof(effectName) == "string" and effectName ~= "" then
		table.insert(segments, effectName)
	end
	if typeof(childName) == "string" and childName ~= "" then
		table.insert(segments, childName)
	end

	return table.concat(segments, "/")
end

local function findRootFolder()
	local current = ReplicatedStorage
	local pathParts = { "ReplicatedStorage" }

	for _, segment in ipairs(ROOT_SEGMENTS) do
		current = current:FindFirstChild(segment)
		table.insert(pathParts, segment)
		if not current then
			warnLog("asset path mismatch: missing folder: %s", table.concat(pathParts, "/"))
			return nil
		end
	end

	return current
end

local function getEffectFolder(effectName)
	local rootFolder = findRootFolder()
	if not rootFolder then
		return nil, buildPathLabel(effectName)
	end

	local effectFolder = rootFolder:FindFirstChild(effectName)
	if not effectFolder then
		warnLog("asset path mismatch: missing folder: %s", buildPathLabel(effectName))
		return nil, buildPathLabel(effectName)
	end

	debugLog("%s asset found: %s", effectName, buildPathLabel(effectName))
	return effectFolder, buildPathLabel(effectName)
end

local function collectBaseParts(root)
	local baseParts = {}

	if root:IsA("BasePart") then
		baseParts[#baseParts + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			baseParts[#baseParts + 1] = descendant
		end
	end

	return baseParts
end

local function collectAttachments(root)
	local attachments = {}

	if root:IsA("Attachment") then
		attachments[#attachments + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") then
			attachments[#attachments + 1] = descendant
		end
	end

	return attachments
end

local function iterateSelfAndDescendants(root)
	local items = { root }

	for _, descendant in ipairs(root:GetDescendants()) do
		items[#items + 1] = descendant
	end

	return items
end

local function computeFacingCFrame(position, velocity, fallbackDirection)
	local facing = typeof(velocity) == "Vector3" and velocity.Magnitude > 0.01 and velocity.Unit or fallbackDirection
	if typeof(facing) ~= "Vector3" or facing.Magnitude <= 0.01 then
		facing = Vector3.new(0, 0, -1)
	end

	return CFrame.lookAt(position, position + facing)
end

local function getPivotCFrame(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	local baseParts = collectBaseParts(instance)
	if #baseParts > 0 then
		return baseParts[1].CFrame
	end

	return nil
end

local function resolveReferenceCFrame(effectFolder, childNames, fallbackCFrame)
	for _, childName in ipairs(childNames) do
		local child = effectFolder:FindFirstChild(childName)
		if child then
			local pivot = getPivotCFrame(child)
			if pivot then
				return pivot
			end
		end
	end

	return fallbackCFrame
end

local function createAnchorPart(name, cframe)
	local anchorPart = Instance.new("Part")
	anchorPart.Name = name
	anchorPart.Anchored = true
	anchorPart.Transparency = 1
	anchorPart.CanCollide = false
	anchorPart.CanTouch = false
	anchorPart.CanQuery = false
	anchorPart.CastShadow = false
	anchorPart.Size = Vector3.new(0.5, 0.5, 0.5)
	anchorPart.CFrame = cframe
	anchorPart.Parent = Workspace
	return anchorPart
end

local function destroyState(state)
	if not state or state.Destroyed then
		return
	end

	state.Destroyed = true

	if state.Container and state.Container.Parent then
		state.Container:Destroy()
	end
end

local function ensureFallbackAttachment(state, key)
	state.FallbackAttachments = state.FallbackAttachments or {}
	local existing = state.FallbackAttachments[key]
	if existing and existing.Parent then
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = string.format("%s_%s", state.EffectName:gsub("%s+", ""), key)
	attachment.Parent = state.AnchorPart
	state.FallbackAttachments[key] = attachment
	return attachment
end

local function ensureTrailAttachments(trailLike, state, label)
	if trailLike.Attachment0 and trailLike.Attachment1 then
		return true
	end

	local attachments = collectAttachments(trailLike.Parent)
	if #attachments >= 2 then
		trailLike.Attachment0 = attachments[1]
		trailLike.Attachment1 = attachments[2]
		return true
	end

	local attachment0 = ensureFallbackAttachment(state, label .. "_A0")
	local attachment1 = ensureFallbackAttachment(state, label .. "_A1")
	attachment0.Position = Vector3.new(0, 0, -0.6)
	attachment1.Position = Vector3.new(0, 0, 0.6)
	trailLike.Attachment0 = attachment0
	trailLike.Attachment1 = attachment1
	warnLog("expected attachment/emitter not found: %s", label)
	return false
end

local function makeBasePartSafe(part, anchorPart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true

	if part ~= anchorPart then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchorPart
		weld.Part1 = part
		weld.Parent = part
	end
end

local function stripScripts(root, label)
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("ModuleScript") then
			warnLog("stripping script descendant from %s: %s", label, item:GetFullName())
			item:Destroy()
		end
	end
end

local function normalizeTree(root, state, label)
	local fallbackAttachment = ensureFallbackAttachment(state, label .. "_Fallback")

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("BasePart") then
			makeBasePartSafe(item, state.AnchorPart)
		elseif item:IsA("Attachment") then
			if not item.Parent:IsA("BasePart") and not item.Parent:IsA("Attachment") then
				warnLog("expected attachment/emitter not found: %s", label)
				item.Parent = fallbackAttachment
			end
		elseif item:IsA("ParticleEmitter") then
			if not item.Parent:IsA("Attachment") and not item.Parent:IsA("BasePart") then
				warnLog("expected attachment/emitter not found: %s", label)
				item.Parent = fallbackAttachment
			end
		elseif item:IsA("Trail") or item:IsA("Beam") then
			ensureTrailAttachments(item, state, label)
		elseif item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
			if not item.Parent:IsA("BasePart") then
				warnLog("expected attachment/emitter not found: %s", label)
				item.Parent = state.AnchorPart
			end
		end
	end
end

local function safeClone(source, label)
	local ok, result = pcall(function()
		return source:Clone()
	end)
	if not ok then
		warnLog("failed to clone %s: %s", label, tostring(result))
		return nil
	end

	return result
end

local function applyPivot(clone, targetPivot, sourcePivot)
	if clone:IsA("Model") then
		clone:PivotTo(targetPivot)
		return
	end

	if clone:IsA("BasePart") then
		clone.CFrame = targetPivot
		return
	end

	local baseParts = collectBaseParts(clone)
	if #baseParts == 0 or not sourcePivot then
		return
	end

	local delta = targetPivot * sourcePivot:Inverse()
	for _, part in ipairs(baseParts) do
		part.CFrame = delta * part.CFrame
	end
end

local function mountChild(effectFolder, state, childName, referenceCFrame)
	local source = effectFolder:FindFirstChild(childName)
	if not source then
		warnLog("missing child: %s", buildPathLabel(state.EffectName, childName))
		return nil
	end

	local clone = safeClone(source, buildPathLabel(state.EffectName, childName))
	if not clone then
		return nil
	end

	local sourcePivot = getPivotCFrame(source)
	local localOffset = sourcePivot and referenceCFrame:ToObjectSpace(sourcePivot) or CFrame.new()
	local targetPivot = state.AnchorPart.CFrame * localOffset

	if clone:IsA("Attachment") or clone:IsA("ParticleEmitter") or clone:IsA("Trail") or clone:IsA("Beam") then
		clone.Parent = state.AnchorPart
	else
		clone.Parent = state.Container
	end

	stripScripts(clone, childName)
	applyPivot(clone, targetPivot, sourcePivot)
	normalizeTree(clone, state, buildPathLabel(state.EffectName, childName))
	state.Mounted[#state.Mounted + 1] = clone
	state.MountedByName[childName] = clone
	if state.EffectName == FREEZE_SHOT_NAME and childName == FREEZE_PROJECTILE_CORE_NAME then
		state.CoreClone = clone
		state.CorePositionOffset = CFrame.new(localOffset.Position)
	end
	return clone
end

local function activateTree(root, stage, defaultEmitCount, options)
	options = options or {}

	local leaveParticleEmittersEnabled = options.LeaveParticleEmittersEnabled ~= false
	local enableTrailsAndBeams = options.EnableTrailsAndBeams ~= false
	local enableContinuousClasses = options.EnableContinuousClasses ~= false
	local continuousDuration = math.max(0, tonumber(options.ContinuousDuration) or 0)

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("ParticleEmitter") then
			local emitCount = tonumber(item:GetAttribute("EmitCount")) or defaultEmitCount or DEFAULT_EMIT_COUNT
			item.Enabled = leaveParticleEmittersEnabled
			if emitCount > 0 then
				local ok, err = pcall(function()
					item:Emit(emitCount)
				end)
				if not ok then
					warnLog("%s emit failed: %s", stage, tostring(err))
				end
			end
			if not leaveParticleEmittersEnabled then
				item.Enabled = false
			end
		elseif item:IsA("Trail") or item:IsA("Beam") then
			if enableTrailsAndBeams and item.Attachment0 and item.Attachment1 then
				item.Enabled = true
			else
				item.Enabled = false
				if enableTrailsAndBeams then
					warnLog("expected attachment/emitter not found: %s", stage)
				end
			end
		elseif item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
			item.Enabled = enableContinuousClasses
			if enableContinuousClasses and continuousDuration > 0 then
				local continuousItem = item
				task.delay(continuousDuration, function()
					if continuousItem and continuousItem.Parent then
						continuousItem.Enabled = false
					end
				end)
			end
		end
	end
end

local function amplifyFreezeShotProjectileTree(root, freezeShotVisualConfig)
	freezeShotVisualConfig = freezeShotVisualConfig or getFreezeShotVisualConfig()

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("Attachment") then
			item.Position *= freezeShotVisualConfig.ProjectileScale
		elseif item:IsA("ParticleEmitter") then
			item.Size = scaleNumberSequence(item.Size, freezeShotVisualConfig.ProjectileParticleScale)
		elseif item:IsA("Trail") then
			item.WidthScale = scaleNumberSequence(item.WidthScale, freezeShotVisualConfig.ProjectileTrailWidthScale)
		elseif item:IsA("Beam") then
			item.Width0 = math.max(0, item.Width0 * freezeShotVisualConfig.ProjectileTrailWidthScale)
			item.Width1 = math.max(0, item.Width1 * freezeShotVisualConfig.ProjectileTrailWidthScale)
		elseif item:IsA("Smoke") or item:IsA("Fire") then
			item.Size = math.max(0, (tonumber(item.Size) or 0) * freezeShotVisualConfig.ProjectileScale)
		elseif item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			item.Range = math.max(0, (tonumber(item.Range) or 0) * freezeShotVisualConfig.ProjectileLightRangeScale)
		elseif item:IsA("BasePart") then
			item.Size *= freezeShotVisualConfig.ProjectileScale
		end
	end
end

local function amplifyFreezeShotImpactTree(root, freezeShotVisualConfig)
	freezeShotVisualConfig = freezeShotVisualConfig or getFreezeShotVisualConfig()

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("Attachment") then
			item.Position *= freezeShotVisualConfig.ImpactScale
		elseif item:IsA("ParticleEmitter") then
			item.Size = scaleNumberSequence(item.Size, freezeShotVisualConfig.ImpactScale)
			item.Speed = scaleNumberRange(item.Speed, freezeShotVisualConfig.ImpactParticleSpeedScale)
		elseif item:IsA("Trail") then
			item.WidthScale = scaleNumberSequence(item.WidthScale, freezeShotVisualConfig.ImpactScale)
		elseif item:IsA("Beam") then
			item.Width0 = math.max(0, item.Width0 * freezeShotVisualConfig.ImpactScale)
			item.Width1 = math.max(0, item.Width1 * freezeShotVisualConfig.ImpactScale)
		elseif item:IsA("Smoke") then
			item.Size = math.max(0, (tonumber(item.Size) or 0) * freezeShotVisualConfig.ImpactScale)
			item.RiseVelocity = (tonumber(item.RiseVelocity) or 0) * freezeShotVisualConfig.ImpactParticleSpeedScale
		elseif item:IsA("Fire") then
			item.Size = math.max(0, (tonumber(item.Size) or 0) * freezeShotVisualConfig.ImpactScale)
			item.Heat = (tonumber(item.Heat) or 0) * freezeShotVisualConfig.ImpactParticleSpeedScale
		elseif item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			item.Range = math.max(0, (tonumber(item.Range) or 0) * freezeShotVisualConfig.ImpactLightRangeScale)
		elseif item:IsA("BasePart") then
			item.Size *= freezeShotVisualConfig.ImpactScale
		end
	end
end

local function createState(effectName, cframe)
	local container = Instance.new("Folder")
	container.Name = string.format("HieVfx_%s", effectName:gsub("%s+", ""))
	container.Parent = Workspace

	local anchorPart = createAnchorPart(container.Name .. "_Anchor", cframe)
	anchorPart.Parent = container

	return {
		EffectName = effectName,
		Container = container,
		AnchorPart = anchorPart,
		Mounted = {},
		MountedByName = {},
		CoreClone = nil,
		CorePositionOffset = CFrame.new(),
		Destroyed = false,
	}
end

local function applyFreezeShotCoreOrientation(state, anchorCFrame, orientationCorrectionCFrame)
	local coreClone = state and state.CoreClone
	if not coreClone then
		return false
	end

	local currentPivot = getPivotCFrame(coreClone)
	if not currentPivot then
		return false
	end

	local correction = typeof(orientationCorrectionCFrame) == "CFrame" and orientationCorrectionCFrame or CFrame.new()
	local positionOffset = typeof(state.CorePositionOffset) == "CFrame" and state.CorePositionOffset or CFrame.new()
	local targetPivot = anchorCFrame * positionOffset * correction
	applyPivot(coreClone, targetPivot, currentPivot)
	return true
end

function HieVfx.CreateFreezeShotProjectile(options)
	options = options or {}

	local position = typeof(options.Position) == "Vector3" and options.Position or Vector3.zero
	local velocity = typeof(options.Velocity) == "Vector3" and options.Velocity or Vector3.new(0, 0, -1)
	local fallbackDirection = typeof(options.Direction) == "Vector3" and options.Direction or nil

	debugLog("Freeze Shot start")

	local effectFolder = getEffectFolder(FREEZE_SHOT_NAME)
	if not effectFolder then
		return nil
	end

	local state = createState(FREEZE_SHOT_NAME, computeFacingCFrame(position, velocity, fallbackDirection))
	local referenceCFrame = resolveReferenceCFrame(effectFolder, FREEZE_PROJECTILE_CHILDREN, state.AnchorPart.CFrame)
	local mountedCount = 0

	for _, childName in ipairs(FREEZE_PROJECTILE_CHILDREN) do
		if mountChild(effectFolder, state, childName, referenceCFrame) then
			mountedCount += 1
		end
	end

	if mountedCount == 0 then
		warnLog("expected attachment/emitter not found: %s", buildPathLabel(FREEZE_SHOT_NAME))
		destroyState(state)
		return nil
	end

	local freezeShotVisualConfig = getFreezeShotVisualConfig()
	for _, clone in ipairs(state.Mounted) do
		amplifyFreezeShotProjectileTree(clone, freezeShotVisualConfig)
		activateTree(clone, FREEZE_SHOT_NAME .. " projectile", freezeShotVisualConfig.ProjectileEmitCount)
	end

	debugLog("Freeze Shot projectile spawned at: %s", formatVector3(position))
	return state
end

function HieVfx.HasFreezeShotCore(state)
	return state ~= nil and state.CoreClone ~= nil
end

function HieVfx.SetFreezeShotProjectileTransform(state, position, velocity, fallbackDirection, orientationCorrectionCFrame)
	if not state or state.Destroyed or not state.AnchorPart or not state.AnchorPart.Parent then
		return false, false, nil
	end

	local anchorCFrame = computeFacingCFrame(position, velocity, fallbackDirection)
	state.AnchorPart.CFrame = anchorCFrame

	local coreFound = applyFreezeShotCoreOrientation(state, anchorCFrame, orientationCorrectionCFrame)
	return true, coreFound, anchorCFrame.LookVector
end

function HieVfx.TriggerFreezeShotImpact(position)
	if typeof(position) ~= "Vector3" then
		warnLog("Freeze Shot impact aborted: invalid position %s", tostring(position))
		return false
	end

	debugLog("Freeze Shot impact triggered")

	local effectFolder = getEffectFolder(FREEZE_SHOT_NAME)
	if not effectFolder then
		return false
	end

	local state = createState(FREEZE_SHOT_NAME .. "_Impact", CFrame.new(position))
	local referenceCFrame = resolveReferenceCFrame(effectFolder, FREEZE_IMPACT_CHILDREN, state.AnchorPart.CFrame)
	local mountedCount = 0

	for _, childName in ipairs(FREEZE_IMPACT_CHILDREN) do
		if mountChild(effectFolder, state, childName, referenceCFrame) then
			mountedCount += 1
		end
	end

	if mountedCount == 0 then
		warnLog("expected attachment/emitter not found: %s", buildPathLabel(FREEZE_SHOT_NAME, "explosion"))
		destroyState(state)
		return false
	end

	local freezeShotVisualConfig = getFreezeShotVisualConfig()
	for _, clone in ipairs(state.Mounted) do
		amplifyFreezeShotImpactTree(clone, freezeShotVisualConfig)
		activateTree(clone, FREEZE_SHOT_NAME .. " impact", freezeShotVisualConfig.ImpactEmitCount, {
			LeaveParticleEmittersEnabled = false,
			ContinuousDuration = freezeShotVisualConfig.ImpactBriefContinuousDuration,
		})
	end

	Debris:AddItem(state.Container, IMPACT_LIFETIME)
	return true
end

function HieVfx.CleanupFreezeShotProjectile(state, reason)
	if not state then
		return
	end

	destroyState(state)
	if DEBUG_ENABLED then
		debugLog("Freeze Shot cleanup complete reason=%s", tostring(reason))
	end
end

function HieVfx.GetFreezeShotVisualConfig()
	return getFreezeShotVisualConfig()
end

local function getIceBoostCFrame(rootPart)
	return rootPart.CFrame * ICE_BOOST_ROOT_OFFSET
end

function HieVfx.CreateIceBoostEffect(options)
	options = options or {}

	local rootPart = options.RootPart
	if not rootPart then
		warnLog("Ice Boost start aborted: missing root part")
		return nil
	end

	debugLog("Ice Boost start")

	local effectFolder = getEffectFolder(ICE_BOOST_NAME)
	if not effectFolder then
		return nil
	end

	local state = createState(ICE_BOOST_NAME, getIceBoostCFrame(rootPart))
	state.TargetPlayer = options.TargetPlayer
	state.Duration = math.max(0, tonumber(options.Duration) or 0)
	state.EndedAt = os.clock() + state.Duration

	local referenceCFrame = resolveReferenceCFrame(effectFolder, ICE_BOOST_CHILDREN, state.AnchorPart.CFrame)
	local mountedCount = 0

	for _, childName in ipairs(ICE_BOOST_CHILDREN) do
		if mountChild(effectFolder, state, childName, referenceCFrame) then
			mountedCount += 1
		end
	end

	if mountedCount == 0 then
		warnLog("expected attachment/emitter not found: %s", buildPathLabel(ICE_BOOST_NAME))
		destroyState(state)
		return nil
	end

	for _, clone in ipairs(state.Mounted) do
		activateTree(clone, ICE_BOOST_NAME .. " start", 18)
	end

	debugLog("Ice Boost loop enabled")
	return state
end

function HieVfx.UpdateIceBoostEffect(state, rootPart)
	if not state or state.Destroyed or not rootPart then
		return false
	end

	state.AnchorPart.CFrame = getIceBoostCFrame(rootPart)
	return true
end

function HieVfx.CleanupIceBoostEffect(state, reason)
	if not state then
		return
	end

	destroyState(state)
	if DEBUG_ENABLED then
		debugLog("Ice Boost cleanup complete reason=%s", tostring(reason))
	end
end

return HieVfx
