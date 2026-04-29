local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local MoguAssetCatalog = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Shared"):WaitForChild("MoguAssetCatalog")
)
local VfxCommon = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mera"):WaitForChild("Shared"):WaitForChild("Vfx"):WaitForChild("VfxCommon")
)

local MoguVfxController = {}
MoguVfxController.__index = MoguVfxController

local FRUIT_NAME = "Mogu Mogu no Mi"
local ABILITY_NAME = "Burrow"
local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 4
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local MIN_DIRECTION_MAGNITUDE = 0.01
local VFX_ANCHOR_SIZE = Vector3.new(0.25, 0.25, 0.25)
local GROUND_COLOR_PROBE_HEIGHT = 6
local GROUND_COLOR_PROBE_DEPTH = 18
local MIN_SCORE_BY_STAGE = {
	Entry = 42,
	Trail = 48,
	Resolve = 42,
}

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MoguVfxController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MOGU VFX] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MoguVfxController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MOGU VFX][WARN] " .. message, ...))
end

local function getFruitConfig()
	return DevilFruitConfig.GetFruit(FRUIT_NAME) or {}
end

local function getAbilityConfig()
	return DevilFruitConfig.GetAbility(FRUIT_NAME, ABILITY_NAME) or {}
end

local function getVfxConfig()
	return getAbilityConfig().Vfx or {}
end

local function getStageConfig(stageKey, abilityConfig)
	local vfxConfig = type(abilityConfig) == "table" and abilityConfig.Vfx or nil
	return type(vfxConfig) == "table" and vfxConfig[stageKey] or {}
end

local function getRootSegments()
	local configuredSegments = getVfxConfig().RootSegments
	if type(configuredSegments) == "table" and #configuredSegments > 0 then
		return configuredSegments
	end

	local assetFolderName = getFruitConfig().AssetFolder or "Mogu"
	return { "Assets", "VFX", assetFolderName }
end

local function appendUniqueInstance(target, seen, instance)
	if typeof(instance) ~= "Instance" or seen[instance] then
		return
	end

	seen[instance] = true
	target[#target + 1] = instance
end

local function getVfxRoots()
	local roots = {}
	local seen = {}
	local assetFolderName = getFruitConfig().AssetFolder or "Mogu"

	appendUniqueInstance(roots, seen, VfxCommon.FindAsset(table.unpack(getRootSegments())))

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assetsFolder and assetsFolder:FindFirstChild("VFX")
	appendUniqueInstance(roots, seen, vfxFolder and vfxFolder:FindFirstChild(assetFolderName))

	local replicatedVfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	appendUniqueInstance(roots, seen, replicatedVfxFolder and replicatedVfxFolder:FindFirstChild(assetFolderName))

	return roots
end

local function isEffectRootCandidate(instance)
	if typeof(instance) ~= "Instance" then
		return false
	end

	return instance:IsA("Model") or instance:IsA("Folder") or instance:IsA("BasePart")
end

local function findExactEffectRoot(assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		return nil
	end

	for _, root in ipairs(getVfxRoots()) do
		if typeof(root) ~= "Instance" then
			continue
		end

		local directChild = root:FindFirstChild(assetName)
		if isEffectRootCandidate(directChild) then
			return directChild
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant.Name == assetName and isEffectRootCandidate(descendant) then
				return descendant
			end
		end
	end

	return nil
end

local function getEffectCandidateContainers(root)
	local candidates = {}
	local seen = {}
	if typeof(root) ~= "Instance" then
		return candidates
	end

	for _, child in ipairs(root:GetChildren()) do
		if isEffectRootCandidate(child) then
			appendUniqueInstance(candidates, seen, child)
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant == root then
			continue
		end
		if descendant:IsA("Model") or descendant:IsA("Folder") then
			appendUniqueInstance(candidates, seen, descendant)
		end
	end

	if #candidates == 0 and isEffectRootCandidate(root) then
		appendUniqueInstance(candidates, seen, root)
	end

	return candidates
end

local function scoreEffectRoot(effectRoot, candidateNames, keywords)
	local tokens = MoguAssetCatalog.CollectSearchTokens(effectRoot, 24)
	local score = MoguAssetCatalog.ScoreTokens(tokens, candidateNames, keywords)
	if effectRoot:IsA("Model") or effectRoot:IsA("Folder") then
		score += 6
	end
	return score
end

local function resolveEffectRoot(stageKey, abilityConfig)
	local stageConfig = getStageConfig(stageKey, abilityConfig)
	if stageConfig.UseAuthoredAsset == false then
		return nil
	end

	local exactEffectRoot = findExactEffectRoot(stageConfig.AssetName)
	if exactEffectRoot then
		logInfo("resolved stage=%s asset=%s mode=exact", tostring(stageKey), exactEffectRoot:GetFullName())
		return exactEffectRoot
	end

	local candidateNames = MoguAssetCatalog.GetVfxCandidates(stageKey, stageConfig.AssetName)
	local keywords = MoguAssetCatalog.GetVfxKeywords(stageKey)
	local bestEffectRoot = nil
	local bestScore = 0

	for _, root in ipairs(getVfxRoots()) do
		for _, effectRoot in ipairs(getEffectCandidateContainers(root)) do
			local score = scoreEffectRoot(effectRoot, candidateNames, keywords)
			if score > bestScore then
				bestEffectRoot = effectRoot
				bestScore = score
			end
		end
	end

	if bestEffectRoot and bestScore >= (MIN_SCORE_BY_STAGE[stageKey] or 42) then
		logInfo(
			"resolved stage=%s asset=%s score=%s",
			tostring(stageKey),
			bestEffectRoot:GetFullName(),
			tostring(bestScore)
		)
		return bestEffectRoot
	end

	logWarn(
		"missing vfx stage=%s bestScore=%s candidates=%s",
		tostring(stageKey),
		tostring(bestScore),
		table.concat(candidateNames, " | ")
	)
	return nil
end

local function eachDescendantOfType(root, className, callback)
	if not root then
		return
	end

	if root:IsA(className) then
		callback(root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA(className) then
			callback(descendant)
		end
	end
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

local function captureVisualState(root)
	local state = {
		BaseParts = {},
		SurfaceVisuals = {},
		Effects = {},
	}

	eachSelfAndDescendants(root, function(item)
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
			local ok, value = pcall(function()
				return item.Enabled
			end)
			if ok then
				enabled = value
			end

			state.Effects[#state.Effects + 1] = {
				Instance = item,
				Enabled = enabled,
			}
		end
	end)

	return state
end

local function setVisualVisible(state, visible)
	for _, entry in ipairs(state.BaseParts or {}) do
		if entry.Instance.Parent then
			entry.Instance.Transparency = visible and entry.Transparency or 1
		end
	end

	for _, entry in ipairs(state.SurfaceVisuals or {}) do
		if entry.Instance.Parent then
			entry.Instance.Transparency = visible and entry.Transparency or 1
		end
	end
end

local function setNonParticleEffectsEnabled(root, enabled)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("ParticleEmitter") then
			return
		end

		if item:IsA("Beam")
			or item:IsA("Trail")
			or item:IsA("Smoke")
			or item:IsA("Fire")
			or item:IsA("Sparkles")
			or item:IsA("PointLight")
			or item:IsA("SpotLight")
			or item:IsA("SurfaceLight")
		then
			pcall(function()
				item.Enabled = enabled
			end)
		end
	end)
end

local function deactivateAllEffects(root)
	eachSelfAndDescendants(root, function(item)
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
			pcall(function()
				item.Enabled = false
			end)
		end
	end)
end

local function readNumberAttribute(instance, attributeName, fallback)
	local value = instance and instance:GetAttribute(attributeName)
	local numeric = tonumber(value)
	if numeric ~= nil then
		return numeric
	end

	return fallback
end

local function hasTruthyAttribute(instance, attributeName)
	if not instance then
		return false
	end

	local value = instance:GetAttribute(attributeName)
	if value == nil or value == false then
		return false
	end

	if typeof(value) == "string" then
		local normalized = string.lower(value)
		return normalized ~= "false" and normalized ~= "0"
	end

	return true
end

local function parseColor3(value)
	if typeof(value) == "Color3" then
		return value
	end

	if typeof(value) == "Vector3" then
		return Color3.new(math.clamp(value.X, 0, 1), math.clamp(value.Y, 0, 1), math.clamp(value.Z, 0, 1))
	end

	if typeof(value) ~= "string" or value == "" then
		return nil
	end

	local components = {}
	for component in string.gmatch(value, "[-%d%.eE]+") do
		components[#components + 1] = tonumber(component)
		if #components >= 3 then
			break
		end
	end

	if #components < 3 then
		return nil
	end

	return Color3.new(
		math.clamp(components[1], 0, 1),
		math.clamp(components[2], 0, 1),
		math.clamp(components[3], 0, 1)
	)
end

local function resolveGroundSample(worldPosition)
	if typeof(worldPosition) ~= "Vector3" then
		return {
			Found = false,
			Color = nil,
		}
	end

	local origin = worldPosition + Vector3.new(0, GROUND_COLOR_PROBE_HEIGHT, 0)
	local cast = Vector3.new(0, -(GROUND_COLOR_PROBE_HEIGHT + GROUND_COLOR_PROBE_DEPTH), 0)
	local result = Workspace:Raycast(origin, cast)
	return {
		Found = result ~= nil,
		Color = result and result.Instance and result.Instance.Color or nil,
	}
end

local function applyGroundColor(emitter, groundSample)
	if not hasTruthyAttribute(emitter, "UseGroundColor") then
		return
	end

	local groundColor = groundSample and groundSample.Color or nil
	groundColor = groundColor or parseColor3(emitter:GetAttribute("GrassColor"))
	if not groundColor then
		return
	end

	emitter.Color = ColorSequence.new(groundColor)
end

local function tweenParticleTimeScale(emitter)
	local startTimeScale = readNumberAttribute(emitter, "TimeScale_Start", nil)
	local endTimeScale = readNumberAttribute(emitter, "TimeScale_End", nil)
	if startTimeScale ~= nil then
		pcall(function()
			emitter.TimeScale = startTimeScale
		end)
	end

	if endTimeScale == nil then
		return
	end

	local tweenDuration = math.max(0, readNumberAttribute(emitter, "TimeScale_Duration", 0) or 0)
	if tweenDuration <= 0 then
		pcall(function()
			emitter.TimeScale = endTimeScale
		end)
		return
	end

	pcall(function()
		TweenService:Create(emitter, TweenInfo.new(tweenDuration, Enum.EasingStyle.Linear), {
			TimeScale = endTimeScale,
		}):Play()
	end)
end

local function scheduleAuthoredParticleEmitter(emitter, defaultEmitCount, groundSample)
	emitter.Enabled = false

	if hasTruthyAttribute(emitter, "GroundOnly") and not (groundSample and groundSample.Found) then
		return 0
	end

	applyGroundColor(emitter, groundSample)

	local emitDelay = math.max(0, readNumberAttribute(emitter, "EmitDelay", 0) or 0)
	local emitDuration = math.max(0, readNumberAttribute(emitter, "EmitDuration", 0) or 0)
	local emitCount = readNumberAttribute(emitter, "EmitCount", nil)
		or readNumberAttribute(emitter, "BurstCount", nil)
		or defaultEmitCount
	emitCount = math.max(0, math.floor(tonumber(emitCount) or 0))

	task.delay(emitDelay, function()
		if not emitter.Parent then
			return
		end

		tweenParticleTimeScale(emitter)
		if emitCount > 0 then
			pcall(function()
				emitter:Emit(emitCount)
			end)
		end

		if emitDuration > 0 then
			emitter.Enabled = true
			task.delay(emitDuration, function()
				if emitter.Parent then
					emitter.Enabled = false
				end
			end)
		end
	end)

	return emitDelay + emitDuration + math.max(0, emitter.Lifetime.Max)
end

local function activateAuthoredVfx(root, defaultEmitCount, worldPosition)
	local groundSample = resolveGroundSample(worldPosition)
	local longestLifetime = 0

	deactivateAllEffects(root)
	setNonParticleEffectsEnabled(root, true)

	eachSelfAndDescendants(root, function(item)
		if not item:IsA("ParticleEmitter") then
			return
		end

		longestLifetime = math.max(
			longestLifetime,
			scheduleAuthoredParticleEmitter(item, defaultEmitCount, groundSample)
		)
	end)

	return longestLifetime
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

local function positionClone(clone, targetCFrame)
	if typeof(clone) ~= "Instance" or typeof(targetCFrame) ~= "CFrame" then
		return nil
	end

	local pivotCFrame = getInstancePivotCFrame(clone)
	if pivotCFrame then
		local delta = targetCFrame * pivotCFrame:Inverse()
		local movedAnyPart = false
		eachDescendantOfType(clone, "BasePart", function(part)
			part.CFrame = delta * part.CFrame
			part.Anchored = true
			movedAnyPart = true
		end)

		return movedAnyPart and clone or nil
	end

	local anchor = Instance.new("Part")
	anchor.Name = "MoguVfxAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = VFX_ANCHOR_SIZE
	anchor.CFrame = targetCFrame
	anchor.Parent = Workspace

	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Name = "AnchorAttachment"
	anchorAttachment.Parent = anchor

	if clone.Parent == Workspace then
		clone.Parent = anchor
	end

	if clone:IsA("Attachment") then
		clone.Parent = anchor
	elseif clone:IsA("ParticleEmitter") or clone:IsA("Trail") or clone:IsA("Beam") then
		clone.Parent = anchorAttachment
	elseif clone:IsA("Smoke") or clone:IsA("Fire") or clone:IsA("Sparkles") then
		clone.Parent = anchor
	end

	return anchor
end

local function resolveDirection(direction)
	local candidate = typeof(direction) == "Vector3" and Vector3.new(direction.X, 0, direction.Z) or DEFAULT_DIRECTION
	if candidate.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return DEFAULT_DIRECTION
	end
	return candidate.Unit
end

local function playStageEffect(stageKey, worldPosition, direction, abilityConfig)
	if typeof(worldPosition) ~= "Vector3" then
		return false
	end

	local effectRoot = resolveEffectRoot(stageKey, abilityConfig)
	if not effectRoot then
		return false
	end

	local stageConfig = getStageConfig(stageKey, abilityConfig)
	local facingDirection = resolveDirection(direction)
	local targetCFrame = CFrame.lookAt(worldPosition, worldPosition + facingDirection, Vector3.yAxis)
	local clone = VfxCommon.Clone(effectRoot, Workspace)
	if not clone then
		logWarn("clone failed stage=%s asset=%s", tostring(stageKey), effectRoot:GetFullName())
		return false
	end

	local cleanupRoot = positionClone(clone, targetCFrame)
	if not cleanupRoot then
		logWarn("position failed stage=%s asset=%s", tostring(stageKey), effectRoot:GetFullName())
		clone:Destroy()
		return false
	end

	local visualState = captureVisualState(clone)
	setVisualVisible(visualState, true)
	local defaultEmitCount = math.max(1, math.floor(tonumber(stageConfig.EmitCount) or 8))
	local authoredLifetime = activateAuthoredVfx(clone, defaultEmitCount, worldPosition)
	local activeTime = math.max(0.05, tonumber(stageConfig.ActiveTime) or 0.15, authoredLifetime)
	task.delay(activeTime, function()
		if cleanupRoot.Parent then
			deactivateAllEffects(clone)
			setVisualVisible(visualState, false)
		end
	end)
	VfxCommon.Cleanup(cleanupRoot, activeTime + math.max(0.2, tonumber(stageConfig.CleanupBuffer) or 0.6))
	return true
end

function MoguVfxController.new()
	return setmetatable({}, MoguVfxController)
end

function MoguVfxController:PlayEntry(position, direction, abilityConfig)
	return playStageEffect("Entry", position, direction, abilityConfig or getAbilityConfig())
end

function MoguVfxController:PlayTrail(position, direction, abilityConfig)
	return playStageEffect("Trail", position, direction, abilityConfig or getAbilityConfig())
end

function MoguVfxController:PlayResolve(position, direction, abilityConfig)
	return playStageEffect("Resolve", position, direction, abilityConfig or getAbilityConfig())
end

function MoguVfxController:HandleCharacterRemoving()
end

function MoguVfxController:HandlePlayerRemoving()
end

return MoguVfxController
