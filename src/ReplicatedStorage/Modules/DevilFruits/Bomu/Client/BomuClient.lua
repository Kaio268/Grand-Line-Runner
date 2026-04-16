local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local BomuClient = {}
BomuClient.__index = BomuClient

local DEFAULT_ANIMATION_CONFIG = {
	Plant = {
		AssetName = "BomuPlant",
		FadeTime = 0.05,
		StopFadeTime = 0.08,
		PlaybackSpeed = 1,
	},
	Detonate = {
		AssetName = "BomuDetonate",
		FadeTime = 0.03,
		StopFadeTime = 0.08,
		PlaybackSpeed = 1,
	},
	Jump = {
		AssetName = "BomuJump",
		FadeTime = 0.03,
		StopFadeTime = 0.08,
		PlaybackSpeed = 1,
	},
}

local function getCharacterFromPlayer(targetPlayer)
	if not targetPlayer then
		return nil
	end

	return targetPlayer.Character
end

local function getHumanoid(character)
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getAnimator(humanoid)
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function stopTrack(track, fadeTime)
	if track and track.IsPlaying then
		track:Stop(fadeTime or 0.08)
	end
end

local function setFxPartDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Transparency = 1
end

local function emitParticlesFromInstance(root, defaultEmitCount)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local emitCount = descendant:GetAttribute("EmitCount")
			if typeof(emitCount) ~= "number" then
				emitCount = defaultEmitCount or 15
			end
			descendant:Emit(emitCount)
		end
	end
end

local function setTransientFxEnabled(root, isEnabled)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = isEnabled
		end
	end
end

local function findAnimationsFolder()
	local assetsFolder = ReplicatedStorage:WaitForChild("Assets", 5)
	if not assetsFolder then
		return nil
	end

	local vfxFolder = assetsFolder:WaitForChild("VFX", 5)
	if not vfxFolder then
		return nil
	end

	local bomuFolder = vfxFolder:WaitForChild("Bomu", 5)
	if not bomuFolder then
		return nil
	end

	return bomuFolder:FindFirstChild("BomuAnim")
end

local function findBombFxTemplate()
	local assetsFolder = ReplicatedStorage:WaitForChild("Assets", 5)
	if not assetsFolder then
		return nil
	end

	local vfxFolder = assetsFolder:WaitForChild("VFX", 5)
	if not vfxFolder then
		return nil
	end

	local bomuFolder = vfxFolder:WaitForChild("Bomu", 5)
	if not bomuFolder then
		return nil
	end

	local bombFolder = bomuFolder:FindFirstChild("Bomb")
	if not bombFolder then
		return nil
	end

	local fx = bombFolder:FindFirstChild("FX")
	if fx and fx:IsA("BasePart") then
		return fx
	end

	return nil
end

function BomuClient.Create(config)
	local self = setmetatable({}, BomuClient)

	self.player = config and config.player or Players.LocalPlayer
	self.playOptionalEffect = type(config and config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or nil
	self.activeTracks = {}
	self.animationFolder = findAnimationsFolder()
	self.bombFxTemplate = findBombFxTemplate()

	if self.animationFolder then
		print("[BomuClient] Animation folder found:", self.animationFolder:GetFullName())
	else
		warn("[BomuClient] Could not find animation folder at ReplicatedStorage.Assets.VFX.Bomu.BomuAnim")
	end

	if self.bombFxTemplate then
		print("[BomuClient] Bomb FX template found:", self.bombFxTemplate:GetFullName())
	else
		warn("[BomuClient] Could not find bomb FX template at ReplicatedStorage.Assets.VFX.Bomu.Bomb.FX")
	end

	return self
end

function BomuClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:BuildRequestPayload(abilityName, abilityConfig, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:GetAnimationConfig(animationType)
	return DEFAULT_ANIMATION_CONFIG[animationType]
end

function BomuClient:GetAnimationInstance(animationType)
	if not self.animationFolder or not self.animationFolder.Parent then
		self.animationFolder = findAnimationsFolder()
	end

	if not self.animationFolder then
		return nil
	end

	local config = self:GetAnimationConfig(animationType)
	if not config then
		return nil
	end

	local animation = self.animationFolder:FindFirstChild(config.AssetName)
	if animation and animation:IsA("Animation") then
		return animation
	end

	return nil
end

function BomuClient:PlayAnimation(targetPlayer, animationType)
	local character = getCharacterFromPlayer(targetPlayer)
	local humanoid = getHumanoid(character)
	if not humanoid then
		return false
	end

	local animator = getAnimator(humanoid)
	if not animator then
		return false
	end

	local config = self:GetAnimationConfig(animationType)
	if not config then
		return false
	end

	local animation = self:GetAnimationInstance(animationType)
	if not animation then
		warn("[BomuClient] Missing animation asset for", animationType, "expected", config.AssetName)
		return false
	end

	local previousTrack = self.activeTracks[targetPlayer]
	if previousTrack then
		stopTrack(previousTrack, config.FadeTime)
		self.activeTracks[targetPlayer] = nil
	end

	local track = animator:LoadAnimation(animation)
	track:Play(config.FadeTime or 0.05)

	if typeof(config.PlaybackSpeed) == "number" then
		track:AdjustSpeed(config.PlaybackSpeed)
	end

	self.activeTracks[targetPlayer] = track

	track.Stopped:Connect(function()
		if self.activeTracks[targetPlayer] == track then
			self.activeTracks[targetPlayer] = nil
		end
	end)

	print("[BomuClient] Playing animation", animationType, "for", targetPlayer and targetPlayer.Name)

	return true
end

function BomuClient:PlayBombVfx(worldPosition, animationType)
	if typeof(worldPosition) ~= "Vector3" then
		return false
	end

	if not self.bombFxTemplate or not self.bombFxTemplate.Parent then
		self.bombFxTemplate = findBombFxTemplate()
	end

	if not self.bombFxTemplate then
		warn("[BomuClient] Bomb FX template missing")
		return false
	end

	local clone = self.bombFxTemplate:Clone()
	clone.Name = "BomuBombFX"
	setFxPartDefaults(clone)

	local yOffset = 0
	if animationType == "Jump" then
		yOffset = 0.4
	end

	clone.CFrame = CFrame.new(worldPosition + Vector3.new(0, yOffset, 0))
	clone.Parent = workspace

	setTransientFxEnabled(clone, true)
	emitParticlesFromInstance(clone, animationType == "Jump" and 18 or 14)

	task.delay(0.2, function()
		if clone and clone.Parent then
			setTransientFxEnabled(clone, false)
		end
	end)

	Debris:AddItem(clone, 2)
	print("[BomuClient] Played Bomb VFX", animationType, "at", worldPosition)

	return true
end

function BomuClient:PlayPlantVfx(worldPosition)
	if typeof(worldPosition) ~= "Vector3" then
		return false
	end

	local pulse = Instance.new("Part")
	pulse.Name = "BomuPlantPulse"
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanTouch = false
	pulse.CanQuery = false
	pulse.Shape = Enum.PartType.Ball
	pulse.Material = Enum.Material.Neon
	pulse.Color = Color3.fromRGB(255, 89, 89)
	pulse.Transparency = 0.25
	pulse.Size = Vector3.new(1.1, 1.1, 1.1)
	pulse.CFrame = CFrame.new(worldPosition + Vector3.new(0, 0.35, 0))
	pulse.Parent = workspace

	task.spawn(function()
		for _ = 1, 6 do
			if not pulse.Parent then
				break
			end
			pulse.Size += Vector3.new(0.18, 0.18, 0.18)
			pulse.Transparency += 0.1
			task.wait(0.03)
		end
	end)

	Debris:AddItem(pulse, 0.3)
	print("[BomuClient] Played Plant VFX at", worldPosition)

	return true
end

function BomuClient:HandleEffect(targetPlayer, abilityName, payload)
	print("[BomuClient] HandleEffect fired")
	print("targetPlayer =", targetPlayer)
	print("abilityName =", abilityName)
	print("payload =", payload)

	if typeof(payload) == "table" then
		for key, value in pairs(payload) do
			print("[BomuClient payload]", key, value)
		end
	end

	if abilityName ~= "LandMine" then
		return false
	end

	if typeof(payload) ~= "table" then
		return false
	end

	local action = payload.Action

	if action == "Placed" then
		local minePosition = payload.MinePosition or payload.OriginPosition
		self:PlayPlantVfx(minePosition)

		if self.playOptionalEffect then
			self.playOptionalEffect("BomuPlant", targetPlayer, payload)
		end

		self:PlayAnimation(targetPlayer, "Plant")
		return true
	end

	if action == "Detonated" then
		local animationType = payload.AnimationType

		if animationType ~= "Jump" and animationType ~= "Detonate" then
			animationType = payload.OwnerLaunched and "Jump" or "Detonate"
		end

		local vfxPosition = payload.OriginPosition or payload.MinePosition
		self:PlayBombVfx(vfxPosition, animationType)

		if self.playOptionalEffect then
			self.playOptionalEffect("BomuDetonate", targetPlayer, payload)
		end

		self:PlayAnimation(targetPlayer, animationType)
		return true
	end

	return false
end

function BomuClient:HandleStateEvent(eventName, abilityName, value, payload)
	print("[BomuClient] HandleStateEvent fired", eventName, abilityName, value, payload)

	if typeof(payload) == "table" then
		for key, val in pairs(payload) do
			print("[BomuClient state payload]", key, val)
		end
	end

	return false
end

function BomuClient:Update()
end

function BomuClient:HandleCharacterRemoving()
	for player, track in pairs(self.activeTracks) do
		stopTrack(track, 0.05)
		self.activeTracks[player] = nil
	end
end

function BomuClient:HandlePlayerRemoving(leavingPlayer)
	local track = self.activeTracks[leavingPlayer]
	if track then
		stopTrack(track, 0.05)
		self.activeTracks[leavingPlayer] = nil
	end
end

return BomuClient