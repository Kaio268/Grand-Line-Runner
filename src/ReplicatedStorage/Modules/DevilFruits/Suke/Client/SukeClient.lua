local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))

local SukeClient = {}
SukeClient.__index = SukeClient

local FRUIT_NAME = "Suke Suke no Mi"
local ABILITY_NAME = "Fade"
local DEFAULT_DURATION = 3
local DEFAULT_FADE_OUT_TIME = 0.22
local DEFAULT_FADE_IN_TIME = 0.28
local DEFAULT_LOCAL_BODY_TRANSPARENCY = 0.68
local DEFAULT_LOCAL_DECAL_TRANSPARENCY = 0.72
local DEFAULT_OBSERVER_BODY_TRANSPARENCY = 1
local DEFAULT_OBSERVER_DECAL_TRANSPARENCY = 1
local SHIMMER_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local function clampNumber(value, fallback, minValue, maxValue)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return fallback
	end

	return math.clamp(numericValue, minValue, maxValue)
end

local function resolveColor(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function getCharacter(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	return targetPlayer.Character
end

local function getRootPart(targetPlayer)
	local character = getCharacter(targetPlayer)
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function isFadePart(part)
	if not part:IsA("BasePart") or part.Name == "HumanoidRootPart" then
		return false
	end

	return part.Transparency < 1
end

local function getAbilityConfig()
	return DevilFruitConfig.GetAbility(FRUIT_NAME, ABILITY_NAME) or {}
end

local function getVfxConfig()
	local abilityConfig = getAbilityConfig()
	return type(abilityConfig.Vfx) == "table" and abilityConfig.Vfx or {}
end

local function resolveSettings(payload, isLocalViewer)
	local abilityConfig = getAbilityConfig()
	local vfxConfig = getVfxConfig()
	payload = payload or {}

	local localBodyTransparency = payload.LocalBodyTransparency
		or abilityConfig.LocalBodyTransparency
		or payload.BodyTransparency
		or abilityConfig.BodyTransparency
		or DEFAULT_LOCAL_BODY_TRANSPARENCY

	local localDecalTransparency = payload.LocalDecalTransparency
		or abilityConfig.LocalDecalTransparency
		or payload.DecalTransparency
		or abilityConfig.DecalTransparency
		or DEFAULT_LOCAL_DECAL_TRANSPARENCY

	local observerBodyTransparency = payload.ObserverBodyTransparency
		or abilityConfig.ObserverBodyTransparency
		or DEFAULT_OBSERVER_BODY_TRANSPARENCY

	local observerDecalTransparency = payload.ObserverDecalTransparency
		or abilityConfig.ObserverDecalTransparency
		or DEFAULT_OBSERVER_DECAL_TRANSPARENCY

	return {
		Duration = clampNumber(payload.Duration, abilityConfig.Duration or DEFAULT_DURATION, 0.1, 10),
		FadeOutTime = clampNumber(payload.FadeOutTime, abilityConfig.FadeOutTime or DEFAULT_FADE_OUT_TIME, 0, 1),
		FadeInTime = clampNumber(payload.FadeInTime, abilityConfig.FadeInTime or DEFAULT_FADE_IN_TIME, 0, 1),
		BodyTransparency = if isLocalViewer
			then clampNumber(localBodyTransparency, DEFAULT_LOCAL_BODY_TRANSPARENCY, 0, 0.95)
			else clampNumber(observerBodyTransparency, DEFAULT_OBSERVER_BODY_TRANSPARENCY, 0, 1),
		DecalTransparency = if isLocalViewer
			then clampNumber(localDecalTransparency, DEFAULT_LOCAL_DECAL_TRANSPARENCY, 0, 0.98)
			else clampNumber(observerDecalTransparency, DEFAULT_OBSERVER_DECAL_TRANSPARENCY, 0, 1),
		ShowShimmer = isLocalViewer,
		ShimmerColor = resolveColor(payload.ShimmerColor, resolveColor(vfxConfig.ShimmerColor, Color3.fromRGB(193, 255, 245))),
		ShimmerAccentColor = resolveColor(payload.ShimmerAccentColor, resolveColor(vfxConfig.ShimmerAccentColor, Color3.fromRGB(255, 255, 255))),
		HighlightFillTransparency = clampNumber(payload.HighlightFillTransparency, vfxConfig.HighlightFillTransparency or 0.88, 0, 1),
		HighlightOutlineTransparency = clampNumber(payload.HighlightOutlineTransparency, vfxConfig.HighlightOutlineTransparency or 0.36, 0, 1),
		ParticleRate = clampNumber(payload.ParticleRate, vfxConfig.ParticleRate or 14, 0, 80),
		ParticleTransparency = clampNumber(payload.ParticleTransparency, vfxConfig.ParticleTransparency or 0.7, 0, 1),
		ParticleLifetime = clampNumber(payload.ParticleLifetime, vfxConfig.ParticleLifetime or 0.65, 0.1, 2),
		PulsePeriod = clampNumber(payload.PulsePeriod, vfxConfig.PulsePeriod or 0.7, 0.2, 3),
	}
end

local function createTween(state, instance, duration, goals, easingStyle, easingDirection)
	if duration <= 0 then
		for propertyName, value in pairs(goals) do
			instance[propertyName] = value
		end
		return nil
	end

	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Sine, easingDirection or Enum.EasingDirection.Out),
		goals
	)
	state.Tweens[#state.Tweens + 1] = tween
	tween:Play()
	return tween
end

local function cancelTweens(state)
	for _, tween in ipairs(state.Tweens or {}) do
		if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
			tween:Cancel()
		end
	end

	state.Tweens = {}
end

local function collectFadeEntries(character, shouldHideAttachedVisuals)
	local partEntries = {}
	local decalEntries = {}
	local hiddenVisualEntries = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if isFadePart(descendant) then
			partEntries[#partEntries + 1] = {
				Instance = descendant,
				Original = descendant.LocalTransparencyModifier,
			}
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			decalEntries[#decalEntries + 1] = {
				Instance = descendant,
				Original = descendant.Transparency,
			}
		elseif shouldHideAttachedVisuals and (
			descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("Highlight")
		) then
			hiddenVisualEntries[#hiddenVisualEntries + 1] = {
				Instance = descendant,
				Original = descendant.Enabled,
			}
			descendant.Enabled = false
		end
	end

	return partEntries, decalEntries, hiddenVisualEntries
end

local function createHighlight(character, settings)
	local highlight = Instance.new("Highlight")
	highlight.Name = "SukeFadeShimmer"
	highlight.Adornee = character
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = settings.ShimmerColor
	highlight.OutlineColor = settings.ShimmerAccentColor
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Parent = character
	return highlight
end

local function createShimmerAttachment(rootPart, settings)
	if not rootPart then
		return nil
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "SukeFadeShimmerAttachment"
	attachment.Parent = rootPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SukeFadeParticles"
	emitter.Texture = SHIMMER_TEXTURE
	emitter.Color = ColorSequence.new(settings.ShimmerColor, settings.ShimmerAccentColor)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, math.clamp(settings.ParticleTransparency + 0.08, 0, 1)),
		NumberSequenceKeypoint.new(0.45, settings.ParticleTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	emitter.Lifetime = NumberRange.new(settings.ParticleLifetime * 0.75, settings.ParticleLifetime)
	emitter.Rate = settings.ParticleRate
	emitter.Speed = NumberRange.new(0.15, 0.7)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.35
	emitter.LightInfluence = 0
	emitter.LockedToPart = true
	emitter.Parent = attachment

	return attachment, emitter
end

local function findSukeVfxTemplate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	local vfxFolder = assets:FindFirstChild("VFX")
	if not vfxFolder then
		return nil
	end

	local sukeFolder = vfxFolder:FindFirstChild("Suke")
	if not sukeFolder then
		return nil
	end

	local template = sukeFolder:FindFirstChild("FadeVFX")
	if template and template:IsA("Model") then
		return template
	end

	return nil
end

function SukeClient.Create(config)
	config = config or {}

	local self = setmetatable({}, SukeClient)
	self.player = config.player or Players.LocalPlayer
	self.playOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or function() end
	self.fadeStates = {}
	self.vfxTemplate = findSukeVfxTemplate()

	if self.vfxTemplate then
		print("[SukeClient] VFX template found:", self.vfxTemplate:GetFullName())
	else
		warn("[SukeClient] Could not find Suke VFX template at ReplicatedStorage.Assets.VFX.Suke.FadeVFX")
	end

	return self
end

function SukeClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName ~= ABILITY_NAME and typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function SukeClient:BuildRequestPayload(abilityName, _abilityEntry, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return nil
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function SukeClient:SpawnFadeVfx(targetPlayer, settings)
	local rootPart = getRootPart(targetPlayer)
	if not rootPart then
		return nil
	end

	if not self.vfxTemplate or not self.vfxTemplate.Parent then
		self.vfxTemplate = findSukeVfxTemplate()
	end

	if not self.vfxTemplate then
		warn("[SukeClient] Suke VFX template missing")
		return nil
	end

	local fxTemplate = self.vfxTemplate:FindFirstChild("FX", true)
	if not fxTemplate or not fxTemplate:IsA("BasePart") then
		warn("[SukeClient] FadeVFX is missing an FX BasePart")
		return nil
	end

	local fxClone = fxTemplate:Clone()
	fxClone.Name = "SukeFadeBurst"
	fxClone.Anchored = true
	fxClone.CanCollide = false
	fxClone.CanTouch = false
	fxClone.CanQuery = false
	fxClone.Massless = true
	fxClone.Transparency = 1
	fxClone.CFrame = rootPart.CFrame + Vector3.new(0, 0.25, 0)
	fxClone.Parent = workspace

	for _, descendant in ipairs(fxClone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local emitCount = descendant:GetAttribute("EmitCount")
			if typeof(emitCount) ~= "number" then
				emitCount = 8
			end
			descendant:Emit(emitCount)
		elseif descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = true
		end
	end

	task.delay(0.08, function()
		if fxClone and fxClone.Parent then
			for _, descendant in ipairs(fxClone:GetDescendants()) do
				if descendant:IsA("Beam") or descendant:IsA("Trail") then
					descendant.Enabled = false
				end
			end
		end
	end)

	Debris:AddItem(fxClone, 0.2)

	print("[SukeClient] Spawned quick fade spark burst for", targetPlayer.Name)
	return fxClone
end

function SukeClient:ClearFade(targetPlayer, immediate)
	local state = self.fadeStates[targetPlayer]
	if not state then
		return
	end

	self.fadeStates[targetPlayer] = nil
	cancelTweens(state)

	local fadeInTime = immediate and 0 or state.Settings.FadeInTime
	for _, entry in ipairs(state.PartEntries or {}) do
		local part = entry.Instance
		if part and part.Parent then
			createTween(state, part, fadeInTime, {
				LocalTransparencyModifier = entry.Original,
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		end
	end

	for _, entry in ipairs(state.DecalEntries or {}) do
		local decal = entry.Instance
		if decal and decal.Parent then
			createTween(state, decal, fadeInTime, {
				Transparency = entry.Original,
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		end
	end

	for _, entry in ipairs(state.HiddenVisualEntries or {}) do
		local visual = entry.Instance
		if visual and visual.Parent then
			visual.Enabled = entry.Original
		end
	end

	if state.Emitter then
		state.Emitter.Enabled = false
	end

	if state.Highlight and state.Highlight.Parent then
		createTween(state, state.Highlight, fadeInTime, {
			FillTransparency = 1,
			OutlineTransparency = 1,
		}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	end

	task.delay(fadeInTime + 0.08, function()
		if state.Highlight and state.Highlight.Parent then
			state.Highlight:Destroy()
		end

		if state.Attachment and state.Attachment.Parent then
			state.Attachment:Destroy()
		end
	end)
end

function SukeClient:StartFade(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local character = getCharacter(targetPlayer)
	if not character then
		return false
	end

	self:ClearFade(targetPlayer, true)

	local isLocalViewer = targetPlayer == self.player
	local settings = resolveSettings(payload, isLocalViewer)
	local partEntries, decalEntries, hiddenVisualEntries = collectFadeEntries(character, not isLocalViewer)
	local highlight = settings.ShowShimmer and createHighlight(character, settings) or nil
	local attachment = nil
	local emitter = nil

	if settings.ShowShimmer then
		attachment, emitter = createShimmerAttachment(getRootPart(targetPlayer), settings)
	end

	local state = {
		Settings = settings,
		PartEntries = partEntries,
		DecalEntries = decalEntries,
		HiddenVisualEntries = hiddenVisualEntries,
		Highlight = highlight,
		Attachment = attachment,
		Emitter = emitter,
		StartedAt = os.clock(),
		PulseStartsAt = os.clock() + settings.FadeOutTime,
		Tweens = {},
	}
	self.fadeStates[targetPlayer] = state

	self:SpawnFadeVfx(targetPlayer, settings)

	for _, entry in ipairs(partEntries) do
		local part = entry.Instance
		if part and part.Parent then
			createTween(state, part, settings.FadeOutTime, {
				LocalTransparencyModifier = if settings.BodyTransparency >= 1
					then 1
					else math.max(entry.Original, settings.BodyTransparency),
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		end
	end

	for _, entry in ipairs(decalEntries) do
		local decal = entry.Instance
		if decal and decal.Parent then
			createTween(state, decal, settings.FadeOutTime, {
				Transparency = if settings.DecalTransparency >= 1
					then 1
					else math.max(entry.Original, settings.DecalTransparency),
			}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		end
	end

	if highlight then
		createTween(state, highlight, settings.FadeOutTime, {
			FillTransparency = settings.HighlightFillTransparency,
			OutlineTransparency = settings.HighlightOutlineTransparency,
		}, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	end

	if settings.ShowShimmer then
		self.playOptionalEffect(targetPlayer, FRUIT_NAME, ABILITY_NAME)
	end

	task.delay(math.max(settings.FadeOutTime, settings.Duration - settings.FadeInTime), function()
		if self.fadeStates[targetPlayer] == state then
			self:ClearFade(targetPlayer, false)
		end
	end)

	return true
end

function SukeClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= ABILITY_NAME then
		return false
	end

	local phase = payload and payload.Phase or "Start"
	if phase ~= "Start" and phase ~= "Instant" then
		return false
	end

	return self:StartFade(targetPlayer, payload)
end

function SukeClient:HandleStateEvent()
	return false
end

function SukeClient:Update()
	local now = os.clock()
	for targetPlayer, state in pairs(self.fadeStates) do
		local character = getCharacter(targetPlayer)
		if not character then
			self:ClearFade(targetPlayer, true)
		elseif state.Highlight and state.Highlight.Parent and now >= state.PulseStartsAt then
			local settings = state.Settings
			local pulseSpeed = (math.pi * 2) / settings.PulsePeriod
			local pulse = (math.sin((now - state.StartedAt) * pulseSpeed) + 1) * 0.5
			state.Highlight.FillTransparency = math.clamp(settings.HighlightFillTransparency - (pulse * 0.035), 0, 1)
			state.Highlight.OutlineTransparency = math.clamp(settings.HighlightOutlineTransparency - (pulse * 0.08), 0, 1)
		end
	end
end

function SukeClient:HandleEquipped()
	return false
end

function SukeClient:HandleUnequipped()
	self:HandleCharacterRemoving()
	return false
end

function SukeClient:HandleCharacterRemoving()
	self:ClearFade(self.player, true)
end

function SukeClient:HandlePlayerRemoving(leavingPlayer)
	self:ClearFade(leavingPlayer, true)
end

return SukeClient