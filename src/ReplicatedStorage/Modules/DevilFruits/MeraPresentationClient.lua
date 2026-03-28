local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local AnimationLoadDiagnostics = require(Modules:WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local MeraVfx = require(Modules:WaitForChild("DevilFruits"):WaitForChild("MeraVfx"))

local MeraPresentationClient = {}
MeraPresentationClient.__index = MeraPresentationClient

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3
local DEFAULT_FADE_TIME = 0.05
local DEFAULT_STOP_FADE_TIME = 0.08
local PREVIOUS_FIRE_BURST_RADIUS = 50

local function logMove(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraPresentationClient:MOVE", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MERA MOVE] " .. message, ...))
end

local function logAnimInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraPresentationClient:ANIM", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MERA ANIM] " .. message, ...))
end

local function logAnimWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MeraPresentationClient:ANIM_WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MERA ANIM][WARN] " .. message, ...))
end

local function getPlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function buildAnimationPath(assetName)
	return string.format("ReplicatedStorage/Assets/Animations/Mera/%s", tostring(assetName or ""))
end

local function getAnimationFolder()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local animationsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
	local meraFolder = animationsFolder and animationsFolder:FindFirstChild("Mera")
	if meraFolder then
		return meraFolder
	end

	return nil
end

local function getAnimationAsset(moveName, assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		logAnimWarn("animation missing or failed to load move=%s detail=invalid_asset_name", tostring(moveName))
		return nil, nil
	end

	local animationPath = buildAnimationPath(assetName)
	local meraFolder = getAnimationFolder()
	if not meraFolder then
		logAnimWarn("animation missing or failed to load move=%s path=ReplicatedStorage/Assets/Animations/Mera detail=missing_folder", tostring(moveName))
		return nil, animationPath
	end

	local animation = meraFolder:FindFirstChild(assetName)
	if animation and animation:IsA("Animation") then
		logAnimInfo("move=%s animation selected=%s", tostring(moveName), animationPath)
		return animation, animationPath
	end

	logAnimWarn("animation missing or failed to load move=%s path=%s detail=missing_animation", tostring(moveName), animationPath)
	return nil, animationPath
end

local function getAnimator(targetPlayer)
	local character = targetPlayer and targetPlayer.Character
	if not character then
		logAnimWarn("animation missing or failed to load move=<unknown> detail=character_missing player=%s", tostring(targetPlayer))
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		logAnimWarn("animation missing or failed to load move=<unknown> detail=humanoid_missing player=%s", tostring(targetPlayer))
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")
	if animator and animator:IsA("Animator") then
		return animator
	end

	local ok, waitedAnimator = pcall(function()
		return humanoid:WaitForChild("Animator", 0.25)
	end)
	if ok and waitedAnimator and waitedAnimator:IsA("Animator") then
		return waitedAnimator
	end

	logAnimWarn("animation missing or failed to load move=<unknown> detail=animator_missing player=%s", tostring(targetPlayer))
	return nil
end

local function stopTrack(track, fadeTime)
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return
	end

	pcall(function()
		track:Stop(math.max(0, tonumber(fadeTime) or DEFAULT_STOP_FADE_TIME))
	end)
end

local function clearTrackBucket(bucket, fadeTime)
	if type(bucket) ~= "table" then
		return
	end

	for moveName, track in pairs(bucket) do
		stopTrack(track, fadeTime)
		bucket[moveName] = nil
	end
end

function MeraPresentationClient.new(config)
	local self = setmetatable({}, MeraPresentationClient)
	self.player = config and config.player or Players.LocalPlayer
	self.activeTracksByPlayer = setmetatable({}, { __mode = "k" })
	return self
end

function MeraPresentationClient:GetAnimationConfig(moveName)
	local abilityConfig = DevilFruitConfig.GetAbility("Mera Mera no Mi", moveName)
	return type(abilityConfig) == "table" and type(abilityConfig.Animation) == "table" and abilityConfig.Animation or nil
end

function MeraPresentationClient:GetAbilityConfig(moveName)
	local abilityConfig = DevilFruitConfig.GetAbility("Mera Mera no Mi", moveName)
	return type(abilityConfig) == "table" and abilityConfig or nil
end

function MeraPresentationClient:GetTrackBucket(targetPlayer)
	local bucket = self.activeTracksByPlayer[targetPlayer]
	if bucket then
		return bucket
	end

	bucket = {}
	self.activeTracksByPlayer[targetPlayer] = bucket
	return bucket
end

function MeraPresentationClient:PlayAnimation(targetPlayer, moveName, defaultAssetName)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local animationConfig = self:GetAnimationConfig(moveName)
	local assetName = (animationConfig and animationConfig.AssetName) or defaultAssetName
	local animation, animationPath = getAnimationAsset(moveName, assetName)
	if not animation then
		return nil
	end

	local animator = getAnimator(targetPlayer)
	if not animator then
		logAnimWarn("animation missing or failed to load move=%s path=%s detail=animator_missing", tostring(moveName), tostring(animationPath))
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		"ReplicatedStorage.Modules.DevilFruits.MeraPresentationClient"
	)
	if not track then
		logAnimWarn(
			"animation missing or failed to load move=%s path=%s detail=%s",
			tostring(moveName),
			tostring(animationPath),
			tostring(loadFailure)
		)
		return nil
	end

	local bucket = self:GetTrackBucket(targetPlayer)
	stopTrack(bucket[moveName], animationConfig and animationConfig.StopFadeTime)
	bucket[moveName] = track

	local fadeTime = math.max(0, tonumber(animationConfig and animationConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(animationConfig and animationConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = animationConfig and animationConfig.Looped == true or false
	track:Play(fadeTime, 1, playbackSpeed)
	track.Stopped:Connect(function()
		if bucket[moveName] == track then
			bucket[moveName] = nil
		end
	end)

	return track
end

function MeraPresentationClient:PlayFlameDashStartup(targetPlayer, _payload, _isPredicted)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	self:PlayAnimation(targetPlayer, "FlameDash", "FlameDash")
	return true
end

function MeraPresentationClient:PlayFlameDashComplete(_targetPlayer, _payload)
	return true
end

function MeraPresentationClient:MarkFlameDashTrailPredictedComplete(_targetPlayer, _reason, _finalPosition, _direction)
	return false
end

function MeraPresentationClient:StopFlameDashTrail(_targetPlayer, _reason, _finalPosition, _direction)
	return false
end

function MeraPresentationClient:PlayFireBurstRelease(targetPlayer, payload)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	local duration = math.max(0, tonumber(type(payload) == "table" and payload.Duration) or 0)
	local radius = math.max(0, tonumber(type(payload) == "table" and payload.Radius) or 0)
	logMove("move=FireBurst radius old=%s new=%s", tostring(PREVIOUS_FIRE_BURST_RADIUS), tostring(radius))
	MeraVfx.PlayFireBurst({
		RootPart = rootPart,
		Direction = rootPart.CFrame.LookVector,
		Duration = duration,
		Radius = radius,
	})

	logMove("move=FireBurst release player=%s", targetPlayer.Name)
	if duration > 0 then
		task.delay(duration, function()
			if targetPlayer.Parent ~= nil then
				logMove("move=FireBurst complete player=%s", targetPlayer.Name)
			end
		end)
	else
		logMove("move=FireBurst complete player=%s", targetPlayer.Name)
	end

	return true
end

function MeraPresentationClient:HandleCharacterRemoving(targetPlayer)
	local player = targetPlayer
	if not player or not player:IsA("Player") then
		player = self.player
	end

	local bucket = player and self.activeTracksByPlayer[player]
	if bucket then
		clearTrackBucket(bucket)
		self.activeTracksByPlayer[player] = nil
	end
end

function MeraPresentationClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer and leavingPlayer:IsA("Player") then
		self:HandleCharacterRemoving(leavingPlayer)
	end
end

return MeraPresentationClient
