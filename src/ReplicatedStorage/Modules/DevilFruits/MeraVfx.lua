local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))

-- This module owns the runtime VFX for the Mera fruit.
-- It handles normal asset playback, procedural fallbacks, body flame placement, and trail cleanup.
local MeraVfx = {}

-- Debug and logging settings.
local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3

-- Shared asset lookup settings.
local ROOT_SEGMENTS = { "Assets", "VFX", "Mera" }
local DEFAULT_EMIT_COUNT = 20

-- FlameBurst tuning values.
local LEGACY_FIRE_BURST_RADIUS = 10
local PREVIOUS_FIRE_BURST_RADIUS = 50
local DEFAULT_FIRE_BURST_DISPERSE_BUFFER = 0.15
local DEFAULT_FIRE_BURST_DISPERSE_MIN_LIFETIME = 0.35
local DEFAULT_FIRE_BURST_FADE_TIME = 0.22
local FLAME_BURST_EFFECT_NAME = "Flame Burst"
local FLAME_BURST_PRIMARY_CHILD_NAME = "FX"

-- FlameDash asset names and role names.
local DEFAULT_FLAME_DASH_STAGE_LIFETIME = 0.4
local FLAME_DASH_EFFECT_NAME = "Flame Dash"
local FLAME_DASH_PRIMARY_CHILD_NAME = "FX"
local FLAME_DASH_SECONDARY_CHILD_NAME = "FX2"
local FLAME_DASH_HEAD_ROLE = "head"
local FLAME_DASH_TRAIL_ROLE = "trail"
local FLAME_DASH_HEAD_ASSET_CANDIDATES = { FLAME_DASH_PRIMARY_CHILD_NAME }
local FLAME_DASH_TRAIL_ASSET_CANDIDATES = { FLAME_DASH_SECONDARY_CHILD_NAME }
local FLAME_DASH_HEAD_PROCEDURAL_PATH = "procedural://Mera/FlameDash/HeadLockedFlame"
local FLAME_DASH_TRAIL_PROCEDURAL_PATH = "procedural://Mera/FlameDash/TrailStampFlame"

-- FlameDash body flame placement.
-- These values only control the flame that is welded to the player during the dash.
-- These values only move the body flame that is welded to the player.
-- The ground trail uses its own offsets below and should stay separate.
local FLAME_DASH_HEAD_FORWARD_OFFSET = 0
local FLAME_DASH_HEAD_UP_OFFSET = 0
-- These values convert live body extents into a centered body flame that wraps the avatar.
local FLAME_DASH_HEAD_TARGET_WIDTH_RATIO = 0.9
local FLAME_DASH_HEAD_TARGET_DEPTH_RATIO = 0.75
local FLAME_DASH_HEAD_REFERENCE_WIDTH = 1.8
local FLAME_DASH_HEAD_REFERENCE_HEIGHT = 5.2
local FLAME_DASH_HEAD_MIN_TARGET_WIDTH = 0.85
local FLAME_DASH_HEAD_MAX_TARGET_WIDTH = 1.8
local FLAME_DASH_HEAD_MIN_TARGET_DEPTH = 0.65
local FLAME_DASH_HEAD_MAX_TARGET_DEPTH = 1.6
local FLAME_DASH_HEAD_HEIGHT_RATIO = 1.05
local FLAME_DASH_HEAD_MIN_HEIGHT = 3.8
local FLAME_DASH_HEAD_MAX_HEIGHT = 6.2
local FLAME_DASH_HEAD_CENTER_UP_RATIO = 0.06
local FLAME_DASH_HEAD_MIN_CENTER_UP_OFFSET = 0.1
local FLAME_DASH_HEAD_MAX_CENTER_UP_OFFSET = 0.35

-- FlameDash ground trail placement and cleanup.
-- These values only belong to the ground trail layer.
local FLAME_DASH_TRAIL_BACK_OFFSET = 1.7
local FLAME_DASH_TRAIL_UP_OFFSET = -2.35
local FLAME_DASH_TRAIL_STAMP_LIFETIME = 0.28
local FLAME_DASH_TRAIL_POST_STOP_HOLD_DURATION = 0.65
local FLAME_DASH_TRAIL_ORDERED_FADE_DURATION = 0.09
local FLAME_DASH_TRAIL_ORDERED_FADE_STEP_INTERVAL = 0.04

-- Logging helpers.
-- Print low-noise info logs for VFX debugging.
local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraVfx:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MERA VFX] " .. message, ...))
end

-- Print low-noise warning logs for invalid assets or bad runtime structure.
local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MeraVfx:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MERA VFX][WARN] " .. message, ...))
end

-- Small formatting helpers.
-- Build readable asset paths for logs.
local function buildPathLabel(effectName, childName)
	local segments = { "ReplicatedStorage" }
	for _, segment in ipairs(ROOT_SEGMENTS) do
		segments[#segments + 1] = segment
	end
	if typeof(effectName) == "string" and effectName ~= "" then
		segments[#segments + 1] = effectName
	end
	if typeof(childName) == "string" and childName ~= "" then
		segments[#segments + 1] = childName
	end

	return table.concat(segments, "/")
end

-- Format Vector3 values so placement logs are easy to read.
local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

-- Basic math and tree traversal helpers.
-- Read the larger side of a NumberRange.
local function getNumberRangeMax(range)
	if typeof(range) ~= "NumberRange" then
		return 0
	end

	return math.max(range.Min, range.Max)
end

-- Scale a NumberRange when an effect needs to grow or shrink.
local function scaleNumberRange(range, factor)
	if typeof(range) ~= "NumberRange" then
		return range
	end

	return NumberRange.new(range.Min * factor, range.Max * factor)
end

-- Scale a NumberSequence when an effect needs to grow or shrink.
local function scaleNumberSequence(sequence, factor)
	if typeof(sequence) ~= "NumberSequence" then
		return sequence
	end

	local keypoints = {}
	for _, keypoint in ipairs(sequence.Keypoints) do
		keypoints[#keypoints + 1] = NumberSequenceKeypoint.new(
			keypoint.Time,
			keypoint.Value * factor,
			keypoint.Envelope * factor
		)
	end

	return NumberSequence.new(keypoints)
end

-- Iterate a root object and all of its descendants in one pass.
local function iterateSelfAndDescendants(root)
	local items = { root }

	for _, descendant in ipairs(root:GetDescendants()) do
		items[#items + 1] = descendant
	end

	return items
end

-- Check whether an instance is a visual effect that can be turned on.
local function isActivatableEffect(item)
	return item:IsA("ParticleEmitter")
		or item:IsA("Trail")
		or item:IsA("Beam")
		or item:IsA("Smoke")
		or item:IsA("Fire")
		or item:IsA("Sparkles")
end

-- Collect all BaseParts under a root so we can move or scale a full effect tree.
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

-- Collect all Attachments under a root so trails and beams can be repaired.
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

-- Get a pivot CFrame from many different kinds of Roblox instances.
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

-- Create an invisible anchored part that acts as a runtime effect anchor.
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

-- Asset lookup and FlameDash role selection.
-- Find the shared Mera VFX root folder under ReplicatedStorage.
local function findRootFolder()
	local current = ReplicatedStorage
	local pathParts = { "ReplicatedStorage" }

	for _, segment in ipairs(ROOT_SEGMENTS) do
		current = current:FindFirstChild(segment)
		pathParts[#pathParts + 1] = segment
		if not current then
			logWarn("missing VFX folder/model/attachment/emitter path=%s detail=missing_folder", table.concat(pathParts, "/"))
			return nil
		end
	end

	return current
end

-- Find one named child effect and return both the instance and its log path.
local function getEffectChild(moveName, effectName, childName)
	local rootFolder = findRootFolder()
	local effectPath = buildPathLabel(effectName)
	local childPath = buildPathLabel(effectName, childName)
	if not rootFolder then
		return nil, childPath
	end

	local effectFolder = rootFolder:FindFirstChild(effectName)
	if not effectFolder then
		logWarn("missing VFX folder/model/attachment/emitter move=%s path=%s detail=missing_effect_folder", tostring(moveName), effectPath)
		return nil, childPath
	end

	local source = effectFolder:FindFirstChild(childName)
	if not source then
		logWarn("missing VFX folder/model/attachment/emitter move=%s path=%s detail=missing_effect_child", tostring(moveName), childPath)
		return nil, childPath
	end

	logInfo("move=%s vfx path selected=%s", tostring(moveName), childPath)
	return source, childPath
end

-- Flatten a direction so FlameDash placement stays relative to the ground plane.
local function getPlanarDirection(vector, fallbackDirection)
	local planarVector = typeof(vector) == "Vector3" and Vector3.new(vector.X, 0, vector.Z) or nil
	if planarVector and planarVector.Magnitude > 0.01 then
		return planarVector.Unit
	end

	local fallback = typeof(fallbackDirection) == "Vector3"
			and Vector3.new(fallbackDirection.X, 0, fallbackDirection.Z)
		or Vector3.new(0, 0, -1)
	if fallback.Magnitude <= 0.01 then
		fallback = Vector3.new(0, 0, -1)
	end

	return fallback.Unit
end

-- Create a simple runtime part for procedural VFX.
local function createRuntimePart(name, cframe, anchored)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = anchored == true
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.CFrame = cframe
	return part
end

-- Find a whole effect folder under the Mera VFX root.
local function getEffectFolder(effectName)
	local rootFolder = findRootFolder()
	if not rootFolder then
		return nil
	end

	return rootFolder:FindFirstChild(effectName)
end

-- Build a readable list of direct children so missing-role logs show what was available.
local function summarizeDirectChildren(folder)
	if not folder then
		return "<missing>"
	end

	local names = {}
	for _, child in ipairs(folder:GetChildren()) do
		names[#names + 1] = child.Name
	end
	table.sort(names)

	if #names == 0 then
		return "<empty>"
	end

	return table.concat(names, ",")
end

-- Resolve the FlameDash body flame or trail to either a real asset child or a procedural fallback.
local function resolveFlameDashRoleSpec(roleName)
	local normalizedRole = string.lower(tostring(roleName or ""))
	local candidates = normalizedRole == FLAME_DASH_HEAD_ROLE and FLAME_DASH_HEAD_ASSET_CANDIDATES
		or FLAME_DASH_TRAIL_ASSET_CANDIDATES
	local effectFolder = getEffectFolder(FLAME_DASH_EFFECT_NAME)
	local availableChildren = summarizeDirectChildren(effectFolder)
	if effectFolder then
		for _, childName in ipairs(candidates) do
			local source = effectFolder:FindFirstChild(childName)
			if source then
				local path = buildPathLabel(FLAME_DASH_EFFECT_NAME, childName)
				if normalizedRole == FLAME_DASH_HEAD_ROLE then
					logInfo("move=FlameDash selected path=%s", path)
				else
					logInfo("move=FlameDash selected fx2 path=%s", path)
				end
				return {
					Kind = "asset",
					Path = path,
					Source = source,
					ChildName = childName,
					AvailableChildren = availableChildren,
				}
			end
		end
	end

	local missingPath = buildPathLabel(FLAME_DASH_EFFECT_NAME, candidates[1])
	local proceduralPath = normalizedRole == FLAME_DASH_HEAD_ROLE and FLAME_DASH_HEAD_PROCEDURAL_PATH
		or FLAME_DASH_TRAIL_PROCEDURAL_PATH
	logWarn(
		"move=FlameDash role=%s path=%s detail=missing_role_asset_using_procedural available=%s",
		normalizedRole,
		missingPath,
		availableChildren
	)
	if normalizedRole == FLAME_DASH_HEAD_ROLE then
		logInfo("move=FlameDash selected path=%s", proceduralPath)
	else
		logInfo("move=FlameDash selected fx2 path=%s", proceduralPath)
	end

	return {
		Kind = "procedural",
		Path = proceduralPath,
		AvailableChildren = availableChildren,
	}
end

-- Remove wind-related pieces from FlameDash assets so the dash stays flame-focused.
local function stripNamedNoise(root, roleName, sourcePath)
	local removedCount = 0
	for _, item in ipairs(root:GetDescendants()) do
		local itemName = string.lower(item.Name)
		local shouldRemove = string.find(itemName, "wind", 1, true) ~= nil

		if shouldRemove then
			item:Destroy()
			removedCount += 1
		end
	end

	if removedCount > 0 then
		logWarn(
			"move=FlameDash role=%s path=%s detail=removed_noise_descendants:%d",
			tostring(roleName),
			tostring(sourcePath),
			removedCount
		)
	end
end

-- Create a state object that keeps a VFX anchor welded to the player's root part.
local function createRootLockedState(label, rootPart)
	if not rootPart or not rootPart.Parent then
		return nil
	end

	local container = Instance.new("Folder")
	container.Name = string.format("MeraVfx_%s", tostring(label):gsub("%s+", ""))
	container.Parent = Workspace

	local anchorPart = createRuntimePart(container.Name .. "_Anchor", rootPart.CFrame, false)
	anchorPart.Parent = container

	local weld = Instance.new("Weld")
	weld.Name = "RootLock"
	weld.Part0 = rootPart
	weld.Part1 = anchorPart
	weld.C0 = CFrame.new()
	weld.C1 = CFrame.new()
	weld.Parent = anchorPart

	return {
		Container = container,
		AnchorPart = anchorPart,
		RootPart = rootPart,
		RootWeld = weld,
		Destroyed = false,
		FallbackAttachments = {},
	}
end

-- Pick the torso parts that best represent the player's body for FlameDash body-flame sizing.
local function getFlameDashBodySourceParts(rootPart)
	local character = rootPart and rootPart.Parent
	if not character then
		return { rootPart }, "HumanoidRootPart"
	end

	local upperTorso = character:FindFirstChild("UpperTorso")
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local torso = character:FindFirstChild("Torso")

	if upperTorso and lowerTorso then
		return { upperTorso, lowerTorso }, "UpperTorso+LowerTorso"
	end

	if torso then
		return { torso }, "Torso"
	end

	if upperTorso then
		return { upperTorso }, "UpperTorso"
	end

	if lowerTorso then
		return { lowerTorso }, "LowerTorso"
	end

	return { rootPart }, "HumanoidRootPart"
end

-- Collect the visible body parts so the body flame can cover the avatar instead of only the root part.
local function getFlameDashVisibleBodyParts(rootPart)
	local character = rootPart and rootPart.Parent
	if not character then
		return { rootPart }, "HumanoidRootPart"
	end

	local bodyParts = {}
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
			bodyParts[#bodyParts + 1] = child
		end
	end

	if #bodyParts == 0 then
		return { rootPart }, "HumanoidRootPart"
	end

	return bodyParts, "CharacterBody"
end

-- Convert a list of body parts into one root-local bounds box.
local function computeLocalBoundsFromParts(rootPart, sourceParts)
	local minVector = Vector3.new(math.huge, math.huge, math.huge)
	local maxVector = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, part in ipairs(sourceParts) do
		if part and part:IsA("BasePart") then
			local localCenter = rootPart.CFrame:PointToObjectSpace(part.Position)
			local halfSize = part.Size * 0.5
			minVector = Vector3.new(
				math.min(minVector.X, localCenter.X - halfSize.X),
				math.min(minVector.Y, localCenter.Y - halfSize.Y),
				math.min(minVector.Z, localCenter.Z - halfSize.Z)
			)
			maxVector = Vector3.new(
				math.max(maxVector.X, localCenter.X + halfSize.X),
				math.max(maxVector.Y, localCenter.Y + halfSize.Y),
				math.max(maxVector.Z, localCenter.Z + halfSize.Z)
			)
		end
	end

	if minVector.X == math.huge or maxVector.X == -math.huge then
		local fallbackHalfSize = rootPart.Size * 0.5
		return -fallbackHalfSize, fallbackHalfSize
	end

	return minVector, maxVector
end

-- Build live body metrics so the FlameDash body flame can stay centered and scale from the avatar.
local function buildFlameDashBodyMetrics(rootPart)
	local sourceParts, sourceLabel = getFlameDashBodySourceParts(rootPart)
	local visibleBodyParts = getFlameDashVisibleBodyParts(rootPart)
	local coreMinVector, coreMaxVector = computeLocalBoundsFromParts(rootPart, sourceParts)
	local fullMinVector, fullMaxVector = computeLocalBoundsFromParts(rootPart, visibleBodyParts)
	local coreBodySize = coreMaxVector - coreMinVector
	local fullBodySize = fullMaxVector - fullMinVector
	local centerOffset = Vector3.new(0, (fullMinVector.Y + fullMaxVector.Y) * 0.5, 0)
	local centerUpOffset = math.clamp(
		fullBodySize.Y * FLAME_DASH_HEAD_CENTER_UP_RATIO,
		FLAME_DASH_HEAD_MIN_CENTER_UP_OFFSET,
		FLAME_DASH_HEAD_MAX_CENTER_UP_OFFSET
	)
	local targetWidth = math.clamp(
		math.max(coreBodySize.X, coreBodySize.Z) * FLAME_DASH_HEAD_TARGET_WIDTH_RATIO,
		FLAME_DASH_HEAD_MIN_TARGET_WIDTH,
		FLAME_DASH_HEAD_MAX_TARGET_WIDTH
	)
	local targetDepth = math.clamp(
		math.max(coreBodySize.Z * FLAME_DASH_HEAD_TARGET_DEPTH_RATIO, targetWidth * 0.58),
		FLAME_DASH_HEAD_MIN_TARGET_DEPTH,
		FLAME_DASH_HEAD_MAX_TARGET_DEPTH
	)
	local flameHeight = math.clamp(
		fullBodySize.Y * FLAME_DASH_HEAD_HEIGHT_RATIO,
		FLAME_DASH_HEAD_MIN_HEIGHT,
		FLAME_DASH_HEAD_MAX_HEIGHT
	)
	local widthScale = targetWidth / FLAME_DASH_HEAD_REFERENCE_WIDTH
	local heightScale = flameHeight / FLAME_DASH_HEAD_REFERENCE_HEIGHT

	return {
		SourceLabel = sourceLabel,
		SourceWidth = coreBodySize.X,
		SourceHeight = fullBodySize.Y,
		SourceDepth = coreBodySize.Z,
		CenterOffset = centerOffset,
		CenteredOffset = centerOffset + Vector3.new(0, centerUpOffset + FLAME_DASH_HEAD_UP_OFFSET, 0),
		TargetWidth = targetWidth,
		TargetDepth = targetDepth,
		WidthScale = math.max(widthScale, heightScale * 0.85),
		FlameHeight = flameHeight,
	}
end

-- Build the world-space placement for one FlameDash ground trail stamp.
local function buildTrailStampCFrame(position, direction)
	local resolvedDirection = getPlanarDirection(direction, Vector3.new(0, 0, -1))
	local anchoredPosition = position + Vector3.new(0, FLAME_DASH_TRAIL_UP_OFFSET, 0) - (resolvedDirection * FLAME_DASH_TRAIL_BACK_OFFSET)
	return CFrame.lookAt(anchoredPosition, anchoredPosition + resolvedDirection)
end

-- Shared runtime state and cleanup helpers.
-- Destroy a runtime VFX state and its container safely.
local function destroyState(state)
	if not state or state.Destroyed then
		return
	end

	state.Destroyed = true
	if typeof(state.Connection) == "RBXScriptConnection" then
		state.Connection:Disconnect()
		state.Connection = nil
	end
	if state.Container and state.Container.Parent then
		state.Container:Destroy()
	end
end

-- Estimate how long a FireBurst effect should linger before cleanup starts.
local function computeEffectDisperseLifetime(root)
	if not root then
		return DEFAULT_FIRE_BURST_DISPERSE_MIN_LIFETIME
	end

	local maxLifetime = 0
	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("ParticleEmitter") then
			maxLifetime = math.max(maxLifetime, getNumberRangeMax(item.Lifetime))
		elseif item:IsA("Trail") then
			maxLifetime = math.max(maxLifetime, tonumber(item.Lifetime) or 0)
		elseif item:IsA("Smoke") then
			maxLifetime = math.max(maxLifetime, 0.6)
		elseif item:IsA("Fire") then
			maxLifetime = math.max(maxLifetime, 0.4)
		elseif item:IsA("Sparkles") then
			maxLifetime = math.max(maxLifetime, 0.25)
		end
	end

	return math.max(maxLifetime, DEFAULT_FIRE_BURST_DISPERSE_MIN_LIFETIME)
end

-- Turn off every activatable effect in a tree without deleting it yet.
local function disableEffectTree(root)
	if not root then
		return
	end

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("ParticleEmitter")
			or item:IsA("Trail")
			or item:IsA("Beam")
			or item:IsA("Smoke")
			or item:IsA("Fire")
			or item:IsA("Sparkles")
		then
			item.Enabled = false
		end
	end
end

-- Fade visible BaseParts in a tree so cleanup looks softer.
local function tweenDisperseVisuals(root, fadeTime)
	if not root then
		return
	end

	local resolvedFadeTime = math.max(0.05, tonumber(fadeTime) or DEFAULT_FIRE_BURST_FADE_TIME)
	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("BasePart") and item.Transparency < 1 then
			local tween = TweenService:Create(item, TweenInfo.new(resolvedFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			})
			tween:Play()
		end
	end
end

-- Start the delayed FlameBurst disperse and cleanup pass.
local function scheduleFireBurstDisperse(state, duration)
	if not state or state.Destroyed then
		return
	end

	local effectRoot = state.EffectRoot
	if not effectRoot then
		return
	end

	local disperseLifetime = computeEffectDisperseLifetime(effectRoot)
	local cleanupDelay = math.max(
		disperseLifetime + DEFAULT_FIRE_BURST_DISPERSE_BUFFER,
		DEFAULT_FIRE_BURST_FADE_TIME + 0.05
	)

	task.delay(math.max(0, tonumber(duration) or 0), function()
		if state.Destroyed or not state.Container or not state.Container.Parent then
			return
		end

		logInfo("move=FlameBurst disperse start")
		disableEffectTree(effectRoot)
		tweenDisperseVisuals(effectRoot, math.min(DEFAULT_FIRE_BURST_FADE_TIME, cleanupDelay))

		task.delay(cleanupDelay, function()
			if state.Destroyed then
				return
			end

			logInfo("move=FlameBurst cleanup after disperse")
			destroyState(state)
		end)
	end)
end

-- Tree normalization and activation helpers.
-- Create or reuse a fallback attachment for broken asset descendants.
local function ensureFallbackAttachment(state, key)
	state.FallbackAttachments = state.FallbackAttachments or {}
	local existing = state.FallbackAttachments[key]
	if existing and existing.Parent then
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = string.format("%s_%s", state.Container.Name, key)
	attachment.Parent = state.AnchorPart
	state.FallbackAttachments[key] = attachment
	return attachment
end

-- Make sure trails and beams have two valid attachments before activation.
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
	logWarn("missing VFX folder/model/attachment/emitter path=%s detail=trail_attachment_fallback", tostring(label))
	return false
end

-- Apply common safety settings to BaseParts inside cloned effects.
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

-- Remove any scripts that accidentally came along inside a cloned VFX asset.
local function stripScripts(root, label)
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("ModuleScript") then
			logWarn("missing VFX folder/model/attachment/emitter path=%s detail=stripped_script:%s", tostring(label), item:GetFullName())
			item:Destroy()
		end
	end
end

-- Normalize a clone so invalid parents are repaired and effect pieces are safe to run.
local function normalizeTree(root, state, label)
	local fallbackAttachment = ensureFallbackAttachment(state, label .. "_Fallback")

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("BasePart") then
			makeBasePartSafe(item, state.AnchorPart)
		elseif item:IsA("Attachment") then
			if not item.Parent:IsA("BasePart") and not item.Parent:IsA("Attachment") then
				logWarn(
					"missing VFX folder/model/attachment/emitter path=%s detail=attachment_parent_invalid parentClass=%s parentName=%s",
					tostring(label),
					item.Parent.ClassName,
					item.Parent.Name
				)
				item.Parent = fallbackAttachment
			end
		elseif item:IsA("ParticleEmitter") then
			if not item.Parent:IsA("Attachment") and not item.Parent:IsA("BasePart") then
				logWarn(
					"missing VFX folder/model/attachment/emitter path=%s detail=emitter_parent_invalid parentClass=%s parentName=%s",
					tostring(label),
					item.Parent.ClassName,
					item.Parent.Name
				)
				item.Parent = fallbackAttachment
			end
		elseif item:IsA("Trail") or item:IsA("Beam") then
			ensureTrailAttachments(item, state, label)
		elseif item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
			if not item.Parent:IsA("BasePart") then
				logWarn("missing VFX folder/model/attachment/emitter path=%s detail=legacy_effect_parent_invalid", tostring(label))
				item.Parent = state.AnchorPart
			end
		end
	end
end

-- Clone an effect tree safely and convert clone failures into warning logs.
local function safeClone(source, label)
	local ok, result = pcall(function()
		return source:Clone()
	end)
	if not ok then
		logWarn("missing VFX folder/model/attachment/emitter path=%s detail=clone_failed:%s", tostring(label), tostring(result))
		return nil
	end

	return result
end

-- Move a clone into its runtime position while preserving its original local layout.
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

-- Turn on all usable emitters, beams, trails, and legacy effects in a tree.
local function activateTree(root, label, activationOptions)
	local defaultEmitCount = activationOptions
	local emitOnStart = true
	if type(activationOptions) == "table" then
		defaultEmitCount = activationOptions.DefaultEmitCount
		emitOnStart = activationOptions.EmitOnStart ~= false
	end

	local activatedCount = 0

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("ParticleEmitter") then
			local emitCount = tonumber(item:GetAttribute("EmitCount")) or defaultEmitCount or DEFAULT_EMIT_COUNT
			item.Enabled = true
			if emitOnStart and emitCount > 0 then
				local ok, err = pcall(function()
					item:Emit(emitCount)
				end)
				if not ok then
					logWarn("missing VFX folder/model/attachment/emitter path=%s detail=emit_failed:%s", tostring(label), tostring(err))
				end
			end
			activatedCount += 1
		elseif item:IsA("Trail") or item:IsA("Beam") then
			if item.Attachment0 and item.Attachment1 then
				item.Enabled = true
				activatedCount += 1
			else
				logWarn("missing VFX folder/model/attachment/emitter path=%s detail=trail_missing_attachments", tostring(label))
			end
		elseif item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
			item.Enabled = true
			activatedCount += 1
		end
	end

	if activatedCount == 0 then
		logWarn("missing VFX folder/model/attachment/emitter path=%s detail=no_activatable_effects", tostring(label))
	end

	return activatedCount
end

-- Build a facing CFrame from a world position and direction.
local function computeFacingCFrame(position, direction, fallbackDirection)
	local facing = typeof(direction) == "Vector3" and direction or fallbackDirection
	if typeof(facing) ~= "Vector3" or facing.Magnitude <= 0.01 then
		facing = Vector3.new(0, 0, -1)
	end

	return CFrame.lookAt(position, position + facing.Unit)
end

-- Build the initial anchor CFrame for a one-shot effect or runtime clone.
local function computeAnchorCFrame(options)
	local rotationCorrection = typeof(options.RotationCorrection) == "CFrame" and options.RotationCorrection or CFrame.new()
	local rootPart = options.RootPart
	if rootPart and rootPart.Parent then
		local offset = typeof(options.LocalOffset) == "CFrame" and options.LocalOffset or CFrame.new()
		return rootPart.CFrame * offset * rotationCorrection
	end

	local position = typeof(options.Position) == "Vector3" and options.Position or nil
	if position then
		local positionOffset = typeof(options.PositionOffset) == "Vector3" and options.PositionOffset or Vector3.zero
		position += positionOffset
		return computeFacingCFrame(position, options.Direction, options.FallbackDirection) * rotationCorrection
	end

	return nil
end

-- Create a generic runtime state with an invisible anchor part in Workspace.
local function createState(label, cframe)
	local container = Instance.new("Folder")
	container.Name = string.format("MeraVfx_%s", tostring(label):gsub("%s+", ""))
	container.Parent = Workspace

	local anchorPart = createAnchorPart(container.Name .. "_Anchor", cframe)
	anchorPart.Parent = container

	return {
		Container = container,
		AnchorPart = anchorPart,
		Destroyed = false,
		FallbackAttachments = {},
	}
end

-- Keep a runtime effect following a part for a short time without using a weld.
local function startFollowLoop(state, rootPart, localOffset, followDuration)
	if not state or not rootPart or followDuration <= 0 then
		return
	end

	task.spawn(function()
		local endAt = os.clock() + followDuration
		while not state.Destroyed and state.AnchorPart and state.AnchorPart.Parent and rootPart.Parent and os.clock() < endAt do
			state.AnchorPart.CFrame = rootPart.CFrame * localOffset
			RunService.Heartbeat:Wait()
		end
	end)
end

-- Scale a full VFX tree so one asset can be reused at different sizes.
local function applyEffectScale(root, anchorCFrame, effectScale)
	local scale = math.max(0.05, tonumber(effectScale) or 1)
	if math.abs(scale - 1) <= 0.001 then
		return
	end

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("BasePart") then
			local localCFrame = anchorCFrame:ToObjectSpace(item.CFrame)
			local rotation = localCFrame - localCFrame.Position
			item.Size = item.Size * scale
			item.CFrame = anchorCFrame * CFrame.new(localCFrame.Position * scale) * rotation
		elseif item:IsA("Attachment") then
			item.Position = item.Position * scale
		elseif item:IsA("ParticleEmitter") then
			item.Size = scaleNumberSequence(item.Size, scale)
			item.Speed = scaleNumberRange(item.Speed, scale)
			item.Acceleration = item.Acceleration * scale
		elseif item:IsA("Trail") then
			item.WidthScale = scaleNumberSequence(item.WidthScale, scale)
		elseif item:IsA("Beam") then
			item.Width0 *= scale
			item.Width1 *= scale
			item.CurveSize0 *= scale
			item.CurveSize1 *= scale
		elseif item:IsA("Smoke") then
			item.Size *= scale
			item.RiseVelocity *= math.sqrt(scale)
		elseif item:IsA("Fire") then
			item.Size *= scale
			item.Heat *= scale
		end
	end
end

-- Play one named asset effect with shared clone, activation, follow, and cleanup logic.
local function playEffect(moveName, effectName, childName, options)
	options = options or {}
	local requestedPath = buildPathLabel(effectName, childName)

	local anchorCFrame = computeAnchorCFrame(options)
	if not anchorCFrame then
		logWarn("missing VFX folder/model/attachment/emitter move=%s path=%s detail=missing_anchor", tostring(moveName), requestedPath)
		return nil, "missing_anchor", requestedPath
	end

	local source, sourcePath = getEffectChild(moveName, effectName, childName)
	if not source then
		return nil, "missing_source", requestedPath
	end

	local state = createState(effectName .. "_" .. childName, anchorCFrame)
	local clone = safeClone(source, sourcePath)
	if not clone then
		destroyState(state)
		return nil, "clone_failed", sourcePath
	end

	local sourcePivot = getPivotCFrame(source)
	if clone:IsA("Attachment") or clone:IsA("ParticleEmitter") or clone:IsA("Trail") or clone:IsA("Beam") then
		clone.Parent = state.AnchorPart
	else
		clone.Parent = state.Container
	end

	if type(options.PrepareClone) == "function" then
		local ok, err = pcall(options.PrepareClone, clone, sourcePath)
		if not ok then
			logWarn("missing VFX folder/model/attachment/emitter path=%s detail=prepare_clone_failed:%s", tostring(sourcePath), tostring(err))
		end
	end

	stripScripts(clone, sourcePath)
	applyPivot(clone, anchorCFrame, sourcePivot)
	applyEffectScale(clone, anchorCFrame, options.Scale)
	normalizeTree(clone, state, sourcePath)
	activateTree(state.Container, sourcePath, {
		DefaultEmitCount = tonumber(options.DefaultEmitCount) or DEFAULT_EMIT_COUNT,
		EmitOnStart = options.EmitOnStart ~= false,
	})
	state.EffectRoot = clone
	state.SourcePath = sourcePath

	local lifetime = math.max(0.25, tonumber(options.Lifetime) or 1.5)
	if options.AutoCleanup ~= false then
		Debris:AddItem(state.Container, lifetime)
	end

	local rootPart = options.RootPart
	local localOffset = typeof(options.LocalOffset) == "CFrame" and options.LocalOffset or CFrame.new()
	startFollowLoop(state, options.FollowPart or rootPart, localOffset, math.min(lifetime, math.max(0, tonumber(options.FollowDuration) or 0)))

	return state, nil, sourcePath
end

-- Install a FlameDash role asset directly onto an existing runtime state.
-- This is used by the body flame and the trail when real asset folders are available.
local function installRoleCloneOnState(state, spec, roleName, options)
	options = options or {}
	if not state or not spec or spec.Kind ~= "asset" or not spec.Source then
		return false
	end

	local clone = safeClone(spec.Source, spec.Path)
	if not clone then
		return false
	end

	local sourcePivot = getPivotCFrame(spec.Source)
	if clone:IsA("Attachment") or clone:IsA("ParticleEmitter") or clone:IsA("Trail") or clone:IsA("Beam") then
		clone.Parent = state.AnchorPart
	else
		clone.Parent = state.Container
	end

	stripScripts(clone, spec.Path)
	stripNamedNoise(clone, roleName, spec.Path)
	applyPivot(clone, state.AnchorPart.CFrame, sourcePivot)
	applyEffectScale(clone, state.AnchorPart.CFrame, tonumber(options.Scale))
	normalizeTree(clone, state, spec.Path)
	local activatedCount = activateTree(state.Container, spec.Path, {
		DefaultEmitCount = tonumber(options.DefaultEmitCount),
		EmitOnStart = options.EmitOnStart ~= false,
	})
	if activatedCount <= 0 then
		clone:Destroy()
		return false
	end
	state.EffectRoot = clone
	state.SourcePath = spec.Path
	state.SelectedPath = spec.Path
	return true
end

-- Procedural FlameDash fallbacks.
-- FlameDash body flame fallback.
-- This procedural effect is used when the body flame asset is missing or unusable.
local function createProceduralHeadEffect(state)
	-- This folder holds the body flame that stays on the player during FlameDash.
	local container = Instance.new("Folder")
	container.Name = "ProceduralHeadFlame"
	container.Parent = state.Container
	local bodyMetrics = state.BodyMetrics or buildFlameDashBodyMetrics(state.RootPart)
	local targetWidth = bodyMetrics.TargetWidth
	local targetDepth = bodyMetrics.TargetDepth or math.max(targetWidth * 0.58, FLAME_DASH_HEAD_MIN_TARGET_DEPTH)
	local flameHeight = bodyMetrics.FlameHeight
	local outerDiameter = math.max(targetWidth, targetDepth) * 0.92
	local lowerDiameter = math.max(targetWidth, targetDepth) * 0.74
	local spineWidth = targetWidth * 0.72
	local spineDepth = targetDepth

	-- This is the bright upper body flame that covers the chest and shoulders.
	local corePart = createRuntimePart("HeadCorePart", state.AnchorPart.CFrame * CFrame.new(0, flameHeight * 0.12, 0), false)
	corePart.Shape = Enum.PartType.Ball
	corePart.Size = Vector3.new(outerDiameter, outerDiameter, outerDiameter)
	corePart.Material = Enum.Material.Neon
	corePart.Color = Color3.fromRGB(255, 188, 72)
	corePart.Transparency = 0.12
	corePart.Parent = container
	makeBasePartSafe(corePart, state.AnchorPart)

	-- This fills the lower body so the fire reads like it covers the torso and hips too.
	local tailPart = createRuntimePart("HeadTailPart", state.AnchorPart.CFrame * CFrame.new(0, -flameHeight * 0.16, 0), false)
	tailPart.Shape = Enum.PartType.Ball
	tailPart.Size = Vector3.new(lowerDiameter, lowerDiameter, lowerDiameter)
	tailPart.Material = Enum.Material.Neon
	tailPart.Color = Color3.fromRGB(255, 101, 26)
	tailPart.Transparency = 0.24
	tailPart.Parent = container
	makeBasePartSafe(tailPart, state.AnchorPart)

	-- This is the main upright flame column, built vertically so it covers the body on a clean baseline.
	local spinePart = createRuntimePart("HeadSpinePart", state.AnchorPart.CFrame, false)
	spinePart.Size = Vector3.new(spineWidth, flameHeight, spineDepth)
	spinePart.Material = Enum.Material.Neon
	spinePart.Color = Color3.fromRGB(255, 126, 32)
	spinePart.Transparency = 0.32
	spinePart.Parent = container
	makeBasePartSafe(spinePart, state.AnchorPart)

	-- These attachments define the lower and upper ends of the body-flame beam.
	local topAttachment = Instance.new("Attachment")
	topAttachment.Name = "HeadTop"
	topAttachment.Position = Vector3.new(0, flameHeight * 0.46, 0)
	topAttachment.Parent = state.AnchorPart

	local bottomAttachment = Instance.new("Attachment")
	bottomAttachment.Name = "HeadBottom"
	bottomAttachment.Position = Vector3.new(0, -flameHeight * 0.38, 0)
	bottomAttachment.Parent = state.AnchorPart

	-- This beam ties the full body flame together from the lower body to the upper body.
	local beam = Instance.new("Beam")
	beam.Name = "HeadCore"
	beam.Attachment0 = topAttachment
	beam.Attachment1 = bottomAttachment
	beam.FaceCamera = true
	beam.Width0 = targetWidth * 0.62
	beam.Width1 = targetWidth * 0.34
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(0.65, 0.18),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 214)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 168, 58)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 74, 18)),
	})
	beam.Enabled = true
	beam.Parent = container

	-- These particles rise from the top of the body flame so the player reads like a moving fire form.
	local flameEmitter = Instance.new("ParticleEmitter")
	flameEmitter.Name = "HeadFlame"
	flameEmitter.Color = beam.Color
	flameEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.55, 0.22),
		NumberSequenceKeypoint.new(1, 1),
	})
	flameEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, targetWidth * 0.32),
		NumberSequenceKeypoint.new(0.5, targetWidth * 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	flameEmitter.Speed = NumberRange.new(2.4, 4.8)
	flameEmitter.Lifetime = NumberRange.new(0.18, 0.28)
	flameEmitter.Rate = 96
	flameEmitter.Rotation = NumberRange.new(0, 360)
	flameEmitter.RotSpeed = NumberRange.new(-120, 120)
	flameEmitter.EmissionDirection = Enum.NormalId.Top
	flameEmitter.SpreadAngle = Vector2.new(24, 24)
	flameEmitter.LightEmission = 1
	flameEmitter.LightInfluence = 0
	flameEmitter.LockedToPart = true
	flameEmitter.Enabled = true
	flameEmitter.Parent = topAttachment

	-- These embers soften the outside so the full body flame still feels alive and not like one solid block.
	local emberEmitter = Instance.new("ParticleEmitter")
	emberEmitter.Name = "HeadEmbers"
	emberEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 209, 122)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 111, 48)),
	})
	emberEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emberEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, targetWidth * 0.11),
		NumberSequenceKeypoint.new(1, 0),
	})
	emberEmitter.Speed = NumberRange.new(2.2, 4.2)
	emberEmitter.Lifetime = NumberRange.new(0.14, 0.22)
	emberEmitter.Rate = 42
	emberEmitter.Rotation = NumberRange.new(0, 360)
	emberEmitter.RotSpeed = NumberRange.new(-180, 180)
	emberEmitter.EmissionDirection = Enum.NormalId.Top
	emberEmitter.SpreadAngle = Vector2.new(28, 28)
	emberEmitter.LightEmission = 1
	emberEmitter.LightInfluence = 0
	emberEmitter.LockedToPart = true
	emberEmitter.Enabled = true
	emberEmitter.Parent = topAttachment

	-- This light keeps the body flame readable while it stays attached to the player.
	local glow = Instance.new("PointLight")
	glow.Name = "HeadGlow"
	glow.Color = Color3.fromRGB(255, 154, 56)
	glow.Range = math.max(12, flameHeight * 2)
	glow.Brightness = 3.5
	glow.Parent = corePart

	state.EffectRoot = container
	state.SourcePath = FLAME_DASH_HEAD_PROCEDURAL_PATH
	state.SelectedPath = FLAME_DASH_HEAD_PROCEDURAL_PATH
	return true
end

-- FlameDash trail fallback.
-- This procedural stamp is used when the ground trail asset is missing or unusable.
local function createProceduralTrailStamp(stampState)
	-- This bright orb is the hottest point in each ground flame stamp.
	local emberPart = createRuntimePart("TrailCorePart", stampState.AnchorPart.CFrame, true)
	emberPart.Shape = Enum.PartType.Ball
	emberPart.Size = Vector3.new(1.15, 1.15, 1.15)
	emberPart.Material = Enum.Material.Neon
	emberPart.Color = Color3.fromRGB(255, 132, 44)
	emberPart.Transparency = 0.18
	emberPart.Parent = stampState.Container

	local streakPart = createRuntimePart("TrailStreakPart", stampState.AnchorPart.CFrame, true)
	streakPart.Size = Vector3.new(0.7, 0.7, 2.6)
	streakPart.Material = Enum.Material.Neon
	streakPart.Color = Color3.fromRGB(255, 164, 66)
	streakPart.Transparency = 0.28
	streakPart.Parent = stampState.Container

	local glow = Instance.new("PointLight")
	glow.Name = "TrailGlow"
	glow.Color = Color3.fromRGB(255, 142, 52)
	glow.Range = 8
	glow.Brightness = 1.8
	glow.Parent = emberPart

	-- This stretched part gives each trail stamp a short flame streak shape.
	local attachment = Instance.new("Attachment")
	attachment.Name = "TrailOrigin"
	attachment.Parent = stampState.AnchorPart

	-- These particles are the main burst of fire left on the ground.
	local flameEmitter = Instance.new("ParticleEmitter")
	flameEmitter.Name = "TrailFlame"
	flameEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 198)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 164, 66)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 86, 28)),
	})
	flameEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.6, 0.34),
		NumberSequenceKeypoint.new(1, 1),
	})
	flameEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.5, 0.54),
		NumberSequenceKeypoint.new(1, 0),
	})
	flameEmitter.Speed = NumberRange.new(0.8, 1.7)
	flameEmitter.Lifetime = NumberRange.new(0.12, 0.22)
	flameEmitter.Rate = 0
	flameEmitter.Rotation = NumberRange.new(0, 360)
	flameEmitter.RotSpeed = NumberRange.new(-140, 140)
	flameEmitter.EmissionDirection = Enum.NormalId.Back
	flameEmitter.SpreadAngle = Vector2.new(24, 24)
	flameEmitter.LightEmission = 1
	flameEmitter.LightInfluence = 0
	flameEmitter.Enabled = true
	flameEmitter.Parent = attachment

	-- These embers make the trail feel hotter and more alive.
	local emberEmitter = Instance.new("ParticleEmitter")
	emberEmitter.Name = "TrailEmbers"
	emberEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 209, 122)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 111, 48)),
	})
	emberEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 1),
	})
	emberEmitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	emberEmitter.Speed = NumberRange.new(1.2, 2.8)
	emberEmitter.Lifetime = NumberRange.new(0.08, 0.16)
	emberEmitter.Rate = 0
	emberEmitter.Rotation = NumberRange.new(0, 360)
	emberEmitter.RotSpeed = NumberRange.new(-180, 180)
	emberEmitter.EmissionDirection = Enum.NormalId.Back
	emberEmitter.SpreadAngle = Vector2.new(26, 26)
	emberEmitter.LightEmission = 1
	emberEmitter.LightInfluence = 0
	emberEmitter.Enabled = true
	emberEmitter.Parent = attachment

	flameEmitter:Emit(18)
	emberEmitter:Emit(12)
end

-- Drop one FlameDash trail stamp at the requested world position.
local function emitFlameDashTrailStamp(state, position, direction)
	if not state or state.Destroyed then
		return nil
	end

	local stampCFrame = buildTrailStampCFrame(position, direction)
	local stampState = createState("FlameDash_TrailStamp", stampCFrame)
	stampState.SelectedPath = state.SelectedPath
	local created = false
	if state.Spec and state.Spec.Kind == "asset" then
		created = installRoleCloneOnState(stampState, state.Spec, FLAME_DASH_TRAIL_ROLE, {
			DefaultEmitCount = 8,
			EmitOnStart = true,
			Scale = state.Scale,
		})
	end

	if not created then
		if state.Spec and state.Spec.Kind == "asset" and state.SelectedPath ~= FLAME_DASH_TRAIL_PROCEDURAL_PATH then
			logWarn(
				"move=FlameDash role=trail path=%s detail=asset_inactive_using_procedural",
				tostring(state.Spec.Path)
			)
			logInfo("move=FlameDash selected fx2 path=%s", FLAME_DASH_TRAIL_PROCEDURAL_PATH)
		end
		createProceduralTrailStamp(stampState)
		stampState.SourcePath = FLAME_DASH_TRAIL_PROCEDURAL_PATH
		stampState.SelectedPath = FLAME_DASH_TRAIL_PROCEDURAL_PATH
		state.SelectedPath = FLAME_DASH_TRAIL_PROCEDURAL_PATH
	end

	state.Stamps = state.Stamps or {}
	state.Stamps[#state.Stamps + 1] = stampState
	state.StampCount = (state.StampCount or 0) + 1
	return stampState
end

-- Remove every trail stamp immediately.
-- This is used only for hard cleanup cases, not the normal ordered fade.
local function cleanupTrailStampsImmediately(state)
	for _, stampState in ipairs(state.Stamps or {}) do
		destroyState(stampState)
	end

	state.Stamps = {}
end

-- Fade a single trail stamp out before destroying it.
local function fadeTrailStamp(stampState, fadeDuration)
	if not stampState or stampState.Destroyed then
		return
	end

	disableEffectTree(stampState.Container)
	tweenDisperseVisuals(stampState.Container, fadeDuration)
	task.delay(math.max(0.05, fadeDuration) + 0.03, function()
		destroyState(stampState)
	end)
end

-- Fade the whole trail in order from the oldest stamp to the newest one.
-- This is the normal shutdown path for the FlameDash ground trail.
local function beginOrderedTrailFade(state, options)
	local validStamps = {}
	for _, stampState in ipairs(state.Stamps or {}) do
		if stampState and not stampState.Destroyed and stampState.Container and stampState.Container.Parent then
			validStamps[#validStamps + 1] = stampState
		end
	end

	local holdDuration = math.max(0, tonumber(options.HoldDuration) or FLAME_DASH_TRAIL_POST_STOP_HOLD_DURATION)
	local fadeDuration = math.max(0.05, tonumber(options.OrderedFadeDuration) or FLAME_DASH_TRAIL_ORDERED_FADE_DURATION)
	local stepInterval = math.max(0.02, tonumber(options.OrderedFadeStepInterval) or FLAME_DASH_TRAIL_ORDERED_FADE_STEP_INTERVAL)

	state.Stamps = {}

	task.spawn(function()
		task.wait(holdDuration)

		if type(options.OnOrderedFadeStart) == "function" then
			pcall(options.OnOrderedFadeStart, #validStamps)
		end

		for index, stampState in ipairs(validStamps) do
			if type(options.OnOrderedFadeStep) == "function" then
				pcall(options.OnOrderedFadeStep, index, #validStamps)
			end

			fadeTrailStamp(stampState, fadeDuration)
			task.wait(stepInterval)
		end

		task.wait(fadeDuration + 0.05)
		if type(options.OnOrderedFadeComplete) == "function" then
			pcall(options.OnOrderedFadeComplete)
		end
	end)
end

-- Public API.
-- Simple debug helper for removing temporary placeholder visuals.
function MeraVfx.LogRemovedPlaceholder(moveName)
	logInfo("removed placeholder VFX move=%s", tostring(moveName))
end

-- FlameBurst playback.
-- This uses the shared effect player, then schedules the disperse and cleanup pass.
function MeraVfx.PlayFlameBurst(options)
	options = options or {}
	local duration = math.max(0, tonumber(options.Duration) or 0)
	local radius = math.max(0, tonumber(options.Radius) or 0)
	local abilityConfig = DevilFruitConfig.GetAbility("Mera Mera no Mi", "FireBurst")
	local baseRadius = math.max(1, tonumber(abilityConfig and abilityConfig.VisualBaseRadius) or LEGACY_FIRE_BURST_RADIUS)
	local previousVisualScale = math.max(0.25, PREVIOUS_FIRE_BURST_RADIUS / baseRadius)
	local visualScale = math.max(0.25, radius / baseRadius)
	local selectedPath = buildPathLabel(FLAME_BURST_EFFECT_NAME, FLAME_BURST_PRIMARY_CHILD_NAME)
	logInfo("move=FlameBurst visualScale old=%.2f new=%.2f", previousVisualScale, visualScale)
	logInfo("move=FlameBurst selected path=%s", selectedPath)

	local state = playEffect("FlameBurst", FLAME_BURST_EFFECT_NAME, FLAME_BURST_PRIMARY_CHILD_NAME, {
		RootPart = options.RootPart,
		Direction = options.Direction,
		LocalOffset = options.LocalOffset,
		Lifetime = math.max(duration + 1.5, 1.8),
		DefaultEmitCount = tonumber(options.DefaultEmitCount) or 30,
		Scale = visualScale,
		AutoCleanup = false,
	})

	if state then
		scheduleFireBurstDisperse(state, duration)
	end

	return state
end

MeraVfx.PlayFireBurst = MeraVfx.PlayFlameBurst

-- Shared FlameDash asset playback.
-- This can play either the body flame asset or the trail asset by child name.
function MeraVfx.PlayFlameDashEffect(options)
	options = options or {}

	local stageName = options.StageName or options.FolderName or FLAME_DASH_PRIMARY_CHILD_NAME
	if stageName ~= FLAME_DASH_PRIMARY_CHILD_NAME and stageName ~= FLAME_DASH_SECONDARY_CHILD_NAME then
		logWarn("missing VFX folder/model/attachment/emitter move=FlameDash path=%s detail=invalid_stage", buildPathLabel(FLAME_DASH_EFFECT_NAME))
		return nil
	end

	local rootPart = options.RootPart
	local direction = options.Direction
	if not direction and rootPart and rootPart.Parent then
		direction = rootPart.CFrame.LookVector
	end

	if stageName == FLAME_DASH_PRIMARY_CHILD_NAME then
		logInfo("move=FlameDash selected path=%s", buildPathLabel(FLAME_DASH_EFFECT_NAME, stageName))
	else
		logInfo("move=FlameDash selected fx2 path=%s", buildPathLabel(FLAME_DASH_EFFECT_NAME, stageName))
	end

	return playEffect("FlameDash", FLAME_DASH_EFFECT_NAME, stageName, {
		RootPart = rootPart,
		Direction = direction,
		LocalOffset = options.LocalOffset,
		Lifetime = math.max(0.1, tonumber(options.Lifetime) or DEFAULT_FLAME_DASH_STAGE_LIFETIME),
		DefaultEmitCount = tonumber(options.DefaultEmitCount),
		Scale = tonumber(options.Scale),
		FollowDuration = math.max(0, tonumber(options.FollowDuration) or 0),
		AutoCleanup = options.AutoCleanup ~= false,
	})
end

-- Small wrapper kept for callers that want a FlameDash burst by folder name.
function MeraVfx.PlayFlameDashBurst(options)
	options = options or {}
	return MeraVfx.PlayFlameDashEffect({
		StageName = options.StageName or options.FolderName,
		RootPart = options.RootPart,
		Direction = options.Direction,
		LocalOffset = options.LocalOffset,
		Lifetime = options.Lifetime,
		DefaultEmitCount = options.DefaultEmitCount,
		Scale = options.Scale,
		FollowDuration = options.FollowDuration,
		AutoCleanup = options.AutoCleanup,
	})
end

-- FlameDash body flame start.
-- FlameDash is currently trail-only, so the on-player body flame is disabled.
function MeraVfx.StartFlameDashHead(options)
	return nil
end

-- FlameDash body flame update.
-- FlameDash is currently trail-only, so there is no body flame to update.
function MeraVfx.UpdateFlameDashHead(state, options)
	return false
end

-- FlameDash body flame stop.
function MeraVfx.StopFlameDashHead(state)
	if state then
		destroyState(state)
	end
	return true
end

-- FlameDash trail start.
-- This creates the trail state that will collect every ground stamp during the dash.
function MeraVfx.StartFlameDashTrail(options)
	options = options or {}
	local rootPart = options.RootPart
	if not rootPart or not rootPart.Parent then
		logWarn("move=FlameDash role=trail path=%s detail=missing_root_part", FLAME_DASH_TRAIL_PROCEDURAL_PATH)
		return nil
	end

	local spec = resolveFlameDashRoleSpec(FLAME_DASH_TRAIL_ROLE)
	return {
		RootPart = rootPart,
		Spec = spec,
		RequestedPath = spec.Path,
		SelectedPath = spec.Path,
		Lifetime = math.max(FLAME_DASH_TRAIL_STAMP_LIFETIME, tonumber(options.Lifetime) or FLAME_DASH_TRAIL_STAMP_LIFETIME),
		Scale = tonumber(options.Scale),
		StampCount = 0,
		Stamps = {},
		Destroyed = false,
	}
end

-- Add one more stamp to the FlameDash ground trail.
function MeraVfx.UpdateFlameDashTrail(state, options)
	options = options or {}
	if not state or state.Destroyed then
		return nil
	end

	local position = typeof(options.Position) == "Vector3" and options.Position or nil
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local direction = getPlanarDirection(options.Direction, state.RootPart and state.RootPart.CFrame.LookVector or Vector3.new(0, 0, -1))
	return emitFlameDashTrailStamp(state, position, direction)
end

-- Stop the FlameDash trail.
-- Normal shutdown keeps the trail visible briefly, then fades it oldest to newest.
function MeraVfx.StopFlameDashTrail(state, options)
	options = options or {}
	if not state or state.Destroyed then
		return false
	end

	if options.ImmediateCleanup == true then
		state.Destroyed = true
		cleanupTrailStampsImmediately(state)
		return true
	end

	local finalPosition = typeof(options.FinalPosition) == "Vector3" and options.FinalPosition or nil
	if finalPosition then
		MeraVfx.UpdateFlameDashTrail(state, {
			Position = finalPosition,
			Direction = options.Direction,
		})
	end

	state.Destroyed = true
	beginOrderedTrailFade(state, options)
	return true
end

return MeraVfx
