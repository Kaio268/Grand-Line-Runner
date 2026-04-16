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
MoguAnimationController.__index = MoguAnimationController

local FRUIT_NAME = "Mogu Mogu no Mi"
local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 4
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.1
local MIN_SCORE_BY_STAGE = {
	Start = 40,
	Resolve = 40,
}

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MoguClientAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MOGU CLIENT ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MoguClientAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MOGU CLIENT ANIM][WARN] " .. message, ...))
end

local function getFruitConfig()
	return DevilFruitConfig.GetFruit(FRUIT_NAME) or {}
end

local function getStageAnimationConfig(stageKey, abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	return type(animationConfig) == "table" and animationConfig[stageKey] or {}
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

local function findExactAnimation(assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		return nil
	end

	for _, root in ipairs(getAnimationRoots()) do
		if typeof(root) ~= "Instance" then
			continue
		end

		local directChild = root:FindFirstChild(assetName)
		if directChild and directChild:IsA("Animation") then
			return directChild
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant.Name == assetName and descendant:IsA("Animation") then
				return descendant
			end
		end
	end

	return nil
end

local function resolveAnimationAsset(stageKey, stageConfig)
	local exactAnimation = findExactAnimation(stageConfig.AssetName)
	if exactAnimation then
		logInfo("resolved stage=%s asset=%s mode=exact", tostring(stageKey), exactAnimation:GetFullName())
		return exactAnimation
	end

	local candidateNames = MoguAssetCatalog.GetAnimationCandidates(stageKey, stageConfig.AssetName)
	local keywords = MoguAssetCatalog.GetAnimationKeywords(stageKey)
	local bestAnimation = nil
	local bestScore = 0

	for _, root in ipairs(getAnimationRoots()) do
		if typeof(root) ~= "Instance" then
			continue
		end

		if root:IsA("Animation") then
			local score = MoguAssetCatalog.ScoreTokens(
				MoguAssetCatalog.CollectSearchTokens(root, 0),
				candidateNames,
				keywords
			)
			if score > bestScore then
				bestAnimation = root
				bestScore = score
			end
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if not descendant:IsA("Animation") then
				continue
			end

			local score = MoguAssetCatalog.ScoreTokens(
				MoguAssetCatalog.CollectSearchTokens(descendant, 0),
				candidateNames,
				keywords
			)
			if score > bestScore then
				bestAnimation = descendant
				bestScore = score
			end
		end
	end

	if bestAnimation and bestScore >= (MIN_SCORE_BY_STAGE[stageKey] or 40) then
		logInfo("resolved stage=%s asset=%s score=%s", tostring(stageKey), bestAnimation:GetFullName(), tostring(bestScore))
		return bestAnimation
	end

	logWarn("missing animation stage=%s bestScore=%s candidates=%s", tostring(stageKey), tostring(bestScore), table.concat(candidateNames, " | "))
	return nil
end

local function playAnimationForPlayer(targetPlayer, stageKey, abilityConfig)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local stageConfig = getStageAnimationConfig(stageKey, abilityConfig)
	local animation = resolveAnimationAsset(stageKey, stageConfig)
	if not animation then
		return nil
	end

	local character = targetPlayer.Character
	local animator = CommonAnimation.GetAnimatorFromCharacter(character, 0.25)
	if not animator then
		logWarn("animator missing stage=%s player=%s", tostring(stageKey), tostring(targetPlayer.Name))
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		"ReplicatedStorage.Modules.DevilFruits.Mogu.Client.MoguAnimationController"
	)
	if not track then
		logWarn("animation failed stage=%s player=%s detail=%s", tostring(stageKey), tostring(targetPlayer.Name), tostring(loadFailure))
		return nil
	end

	local fadeTime = math.max(0, tonumber(stageConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(stageConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = stageConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)

	return {
		Stage = stageKey,
		Track = track,
		StopFadeTime = math.max(0, tonumber(stageConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

function MoguAnimationController.new()
	return setmetatable({}, MoguAnimationController)
end

function MoguAnimationController:PlayStart(targetPlayer, abilityConfig)
	return playAnimationForPlayer(targetPlayer, "Start", abilityConfig)
end

function MoguAnimationController:PlayResolve(targetPlayer, abilityConfig)
	return playAnimationForPlayer(targetPlayer, "Resolve", abilityConfig)
end

function MoguAnimationController:StopAnimation(animationState, reason)
	if type(animationState) ~= "table" then
		return false
	end

	CommonAnimation.StopTrack(animationState.Track, animationState.StopFadeTime)
	logInfo("stop stage=%s reason=%s", tostring(animationState.Stage), tostring(reason))
	return true
end

return MoguAnimationController
