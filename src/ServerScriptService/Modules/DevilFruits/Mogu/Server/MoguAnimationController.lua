local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local AnimationLoadDiagnostics = require(Modules:WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local CommonAnimation = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("CommonAnimation"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local MoguAssetCatalog = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Shared"):WaitForChild("MoguAssetCatalog")
)

local MoguAnimationController = {}

local FRUIT_NAME = "Mogu Mogu no Mi"
local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 4
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.1
local resolvedAnimationByStage = {}

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MoguAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MOGU ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MoguAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MOGU ANIM][WARN] " .. message, ...))
end

local function getFruitConfig()
	return DevilFruitConfig.GetFruit(FRUIT_NAME) or {}
end

local function appendUniqueInstance(target, seen, instance)
	if typeof(instance) ~= "Instance" or seen[instance] then
		return
	end

	seen[instance] = true
	target[#target + 1] = instance
end

local function getAnimationRoots()
	local roots = {}
	local seen = {}
	local assetFolderName = getFruitConfig().AssetFolder or "Mogu"

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local assetsAnimationsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
	appendUniqueInstance(roots, seen, assetsAnimationsFolder and assetsAnimationsFolder:FindFirstChild(assetFolderName))

	local replicatedAnimationsFolder = ReplicatedStorage:FindFirstChild("Animations")
	appendUniqueInstance(roots, seen, replicatedAnimationsFolder and replicatedAnimationsFolder:FindFirstChild(assetFolderName))

	return roots
end

local function getStageAnimationConfig(stageKey, abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	return type(animationConfig) == "table" and animationConfig[stageKey] or {}
end

local function scoreAnimation(animation, candidateNames, keywords)
	local tokens = MoguAssetCatalog.CollectSearchTokens(animation, 0)
	return MoguAssetCatalog.ScoreTokens(tokens, candidateNames, keywords)
end

local function resolveAnimationAsset(stageKey, stageConfig)
	local cachedAnimation = resolvedAnimationByStage[stageKey]
	if cachedAnimation == false then
		return nil
	end

	if typeof(cachedAnimation) == "Instance" and cachedAnimation.Parent then
		return cachedAnimation
	end

	local configuredAssetName = type(stageConfig) == "table" and stageConfig.AssetName or nil
	local candidateNames = MoguAssetCatalog.GetAnimationCandidates(stageKey, configuredAssetName)
	local keywords = MoguAssetCatalog.GetAnimationKeywords(stageKey)
	local bestAnimation = nil
	local bestScore = 0
	local firstAnimation = nil

	for _, root in ipairs(getAnimationRoots()) do
		if typeof(root) ~= "Instance" then
			continue
		end

		if root:IsA("Animation") then
			firstAnimation = firstAnimation or root
			local score = scoreAnimation(root, candidateNames, keywords)
			if score > bestScore then
				bestAnimation = root
				bestScore = score
			end
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if not descendant:IsA("Animation") then
				continue
			end

			firstAnimation = firstAnimation or descendant
			local score = scoreAnimation(descendant, candidateNames, keywords)
			if score > bestScore then
				bestAnimation = descendant
				bestScore = score
			end
		end
	end

	if not bestAnimation and firstAnimation then
		bestAnimation = firstAnimation
	end

	resolvedAnimationByStage[stageKey] = bestAnimation or false
	if bestAnimation then
		logInfo(
			"resolved stage=%s asset=%s score=%s",
			tostring(stageKey),
			bestAnimation:GetFullName(),
			tostring(bestScore)
		)
	else
		logWarn("missing animation stage=%s candidates=%s", tostring(stageKey), table.concat(candidateNames, " | "))
	end

	return bestAnimation
end

local function playAnimation(character, stageKey, abilityConfig)
	local stageConfig = getStageAnimationConfig(stageKey, abilityConfig)
	local animation = resolveAnimationAsset(stageKey, stageConfig)
	if not animation then
		return nil
	end

	local animator = CommonAnimation.GetAnimatorFromCharacter(character, 0.25)
	if not animator then
		logWarn("animator missing stage=%s character=%s", tostring(stageKey), tostring(character and character.Name))
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		"ServerScriptService.Modules.DevilFruits.Mogu.Server.MoguAnimationController"
	)
	if not track then
		logWarn("animation failed stage=%s detail=%s", tostring(stageKey), tostring(loadFailure))
		return nil
	end

	local fadeTime = math.max(0, tonumber(stageConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(stageConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = stageConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)

	logInfo("play stage=%s asset=%s", tostring(stageKey), animation:GetFullName())

	return {
		Stage = stageKey,
		Track = track,
		StopFadeTime = math.max(0, tonumber(stageConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

function MoguAnimationController.PlayBurrowStartAnimation(character, abilityConfig)
	return playAnimation(character, "Start", abilityConfig)
end

function MoguAnimationController.PlayBurrowResolveAnimation(character, abilityConfig)
	return playAnimation(character, "Resolve", abilityConfig)
end

function MoguAnimationController.StopAnimation(animationState, reason)
	if type(animationState) ~= "table" then
		return false
	end

	CommonAnimation.StopTrack(animationState.Track, animationState.StopFadeTime)
	logInfo("stop stage=%s reason=%s", tostring(animationState.Stage), tostring(reason))
	return true
end

return MoguAnimationController
