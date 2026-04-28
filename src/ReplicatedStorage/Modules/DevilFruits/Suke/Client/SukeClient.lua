local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local AnimationLoadDiagnostics = require(DevilFruits:WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(DevilFruits:WaitForChild("DiagnosticLogLimiter"))
local AnimationResolver = require(DevilFruits:WaitForChild("Shared"):WaitForChild("AnimationResolver"))
local CommonAnimation = require(DevilFruits:WaitForChild("Shared"):WaitForChild("CommonAnimation"))

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
local DEFAULT_SHIMMER_COLOR = Color3.fromRGB(193, 255, 245)
local DEFAULT_SHIMMER_ACCENT_COLOR = Color3.fromRGB(255, 255, 255)
local DEFAULT_HIGHLIGHT_FILL_TRANSPARENCY = 0.88
local DEFAULT_HIGHLIGHT_OUTLINE_TRANSPARENCY = 0.36
local DEFAULT_PARTICLE_RATE = 14
local DEFAULT_PARTICLE_TRANSPARENCY = 0.7
local DEFAULT_PARTICLE_LIFETIME = 0.65
local DEFAULT_PULSE_PERIOD = 0.7
local DEFAULT_ANIMATION_KEY = "Suke.Suke1"
local DEFAULT_ANIMATION_FADE_TIME = 0.06
local DEFAULT_ANIMATION_STOP_FADE_TIME = 0.12
local DEFAULT_ANIMATION_PRIORITY = Enum.AnimationPriority.Action
local DEFAULT_EFFECT_DELAY = 0.35
local DEFAULT_EFFECT_MARKER_NAMES = { "Fade", "Invisible", "Invisibility", "Vanish", "Activate" }
local DEFAULT_WINDUP_CLEANUP_DELAY = 1.15
local DEFAULT_AUTHORED_VFX_NAME = "FX"
local DEFAULT_AUTHORED_VFX_OFFSET = CFrame.new(0, -0.305, 0)
local DEFAULT_AUTHORED_VFX_LIFETIME = 1.35
local DEFAULT_AUTHORED_VFX_EMIT_COUNT = 100
local SHIMMER_CLEANUP_BUFFER = 0.08
local HIGHLIGHT_FILL_PULSE_AMOUNT = 0.035
local HIGHLIGHT_OUTLINE_PULSE_AMOUNT = 0.08
local SHIMMER_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local AUTHORED_VFX_TEXTURE = "rbxassetid://8037777212"
local SOURCE_LABEL = "ReplicatedStorage.Modules.DevilFruits.Suke.Client.SukeClient"
local WARN_COOLDOWN = 4

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("SukeClient:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[SUKE CLIENT][WARN] " .. message, ...))
end

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

local function resolveCFrame(value, fallback)
	if typeof(value) == "CFrame" then
		return value
	elseif typeof(value) == "Vector3" then
		return CFrame.new(value)
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

local function getAnimationConfig()
	local abilityConfig = getAbilityConfig()
	return type(abilityConfig.Animation) == "table" and abilityConfig.Animation or {}
end

local function getEffectDelay(animationConfig)
	return math.max(0, tonumber(animationConfig.EffectDelay) or DEFAULT_EFFECT_DELAY)
end

local function getWindupCleanupDelay(animationConfig)
	return math.max(0, tonumber(animationConfig.WindupCleanupDelay) or DEFAULT_WINDUP_CLEANUP_DELAY)
end

local function getEffectMarkerNames(animationConfig)
	if type(animationConfig.EffectMarkerNames) ~= "table" then
		return DEFAULT_EFFECT_MARKER_NAMES
	end

	local markerNames = {}
	for _, markerName in ipairs(animationConfig.EffectMarkerNames) do
		if typeof(markerName) == "string" and markerName ~= "" then
			markerNames[#markerNames + 1] = markerName
		end
	end

	return if #markerNames > 0 then markerNames else DEFAULT_EFFECT_MARKER_NAMES
end

local function getVfxConfig()
	local abilityConfig = getAbilityConfig()
	return type(abilityConfig.Vfx) == "table" and abilityConfig.Vfx or {}
end

local function playFadeAnimation(targetPlayer)
	local animationConfig = getAnimationConfig()
	local animationKey = if typeof(animationConfig.AnimationKey) == "string" and animationConfig.AnimationKey ~= ""
		then animationConfig.AnimationKey
		else DEFAULT_ANIMATION_KEY
	local animation, descriptor = AnimationResolver.GetAnimation(animationKey, {
		Context = "Suke.Fade",
	})
	if not animation then
		logWarn("missing animation key=%s", tostring(animationKey))
		return nil
	end

	local character = getCharacter(targetPlayer)
	local animator = CommonAnimation.GetAnimatorFromCharacter(character, 0.25)
	if not animator then
		logWarn("animator missing player=%s", tostring(targetPlayer and targetPlayer.Name))
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(animator, animation, SOURCE_LABEL)
	if not track then
		logWarn(
			"animation failed player=%s key=%s detail=%s",
			tostring(targetPlayer.Name),
			tostring(animationKey),
			tostring(loadFailure)
		)
		return nil
	end

	local fadeTime = math.max(0, tonumber(animationConfig.FadeTime) or DEFAULT_ANIMATION_FADE_TIME)
	local playbackSpeed = math.max(0.01, tonumber(animationConfig.PlaybackSpeed) or 1)
	track.Priority = if typeof(animationConfig.Priority) == "EnumItem"
		then animationConfig.Priority
		else DEFAULT_ANIMATION_PRIORITY
	track.Looped = animationConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)
	AnimationLoadDiagnostics.LogTrackPlay(
		track,
		SOURCE_LABEL,
		"Suke.Fade",
		descriptor and descriptor.AnimationId,
		string.format("key=%s fade=%.3f speed=%.3f looped=%s", tostring(animationKey), fadeTime, playbackSpeed, tostring(track.Looped))
	)

	return {
		Track = track,
		StopFadeTime = math.max(0, tonumber(animationConfig.StopFadeTime) or DEFAULT_ANIMATION_STOP_FADE_TIME),
	}
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
	local authoredVfxName = if typeof(vfxConfig.AuthoredEffectName) == "string" and vfxConfig.AuthoredEffectName ~= ""
		then vfxConfig.AuthoredEffectName
		else DEFAULT_AUTHORED_VFX_NAME

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
		ShimmerColor = resolveColor(payload.ShimmerColor, resolveColor(vfxConfig.ShimmerColor, DEFAULT_SHIMMER_COLOR)),
		ShimmerAccentColor = resolveColor(
			payload.ShimmerAccentColor,
			resolveColor(vfxConfig.ShimmerAccentColor, DEFAULT_SHIMMER_ACCENT_COLOR)
		),
		HighlightFillTransparency = clampNumber(
			payload.HighlightFillTransparency,
			vfxConfig.HighlightFillTransparency or DEFAULT_HIGHLIGHT_FILL_TRANSPARENCY,
			0,
			1
		),
		HighlightOutlineTransparency = clampNumber(
			payload.HighlightOutlineTransparency,
			vfxConfig.HighlightOutlineTransparency or DEFAULT_HIGHLIGHT_OUTLINE_TRANSPARENCY,
			0,
			1
		),
		ParticleRate = clampNumber(payload.ParticleRate, vfxConfig.ParticleRate or DEFAULT_PARTICLE_RATE, 0, 80),
		ParticleTransparency = clampNumber(
			payload.ParticleTransparency,
			vfxConfig.ParticleTransparency or DEFAULT_PARTICLE_TRANSPARENCY,
			0,
			1
		),
		ParticleLifetime = clampNumber(
			payload.ParticleLifetime,
			vfxConfig.ParticleLifetime or DEFAULT_PARTICLE_LIFETIME,
			0.1,
			2
		),
		PulsePeriod = clampNumber(payload.PulsePeriod, vfxConfig.PulsePeriod or DEFAULT_PULSE_PERIOD, 0.2, 3),
		AuthoredVfxEnabled = vfxConfig.AuthoredEffectEnabled ~= false,
		AuthoredVfxName = authoredVfxName,
		AuthoredVfxOffset = resolveCFrame(vfxConfig.AuthoredEffectOffset, DEFAULT_AUTHORED_VFX_OFFSET),
		AuthoredVfxLifetime = clampNumber(
			vfxConfig.AuthoredEffectLifetime,
			DEFAULT_AUTHORED_VFX_LIFETIME,
			0.1,
			5
		),
		AuthoredVfxEmitCount = math.max(
			1,
			math.floor(tonumber(vfxConfig.AuthoredEffectEmitCount) or DEFAULT_AUTHORED_VFX_EMIT_COUNT)
		),
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
			-- Observer-only: attached visuals would otherwise reveal an invisible character.
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

local function eachSelfAndDescendants(root, callback)
	if not root then
		return
	end

	callback(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		callback(descendant)
	end
end

local function getAuthoredVfxTemplate(effectName)
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assetsFolder and assetsFolder:FindFirstChild("VFX")
	local sukeFolder = vfxFolder and vfxFolder:FindFirstChild("Suke")
	return sukeFolder and sukeFolder:FindFirstChild(effectName) or nil
end

local function createFallbackAuthoredVfxClone(effectName)
	local part = Instance.new("Part")
	part.Name = effectName
	part.Size = Vector3.new(5, 5, 5)
	part.Transparency = 1
	part.Anchored = false

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "small stars"
	emitter.Enabled = false
	emitter.Rate = 20
	emitter.Lifetime = NumberRange.new(0.125, 0.75)
	emitter.Speed = NumberRange.new(20, 20)
	emitter.SpreadAngle = Vector2.new(-360, 360)
	emitter.Texture = AUTHORED_VFX_TEXTURE
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.LockedToPart = true
	emitter.Drag = 10
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.1, 0.188),
		NumberSequenceKeypoint.new(0.2, 0),
		NumberSequenceKeypoint.new(0.3, 0.188),
		NumberSequenceKeypoint.new(0.4, 0),
		NumberSequenceKeypoint.new(0.5, 0.188),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0)
	emitter.ZOffset = 1
	emitter:SetAttribute("EmitCount", DEFAULT_AUTHORED_VFX_EMIT_COUNT)
	emitter:SetAttribute("EmitDelay", 0)
	emitter.Parent = part

	return part
end

local function configureAuthoredVfxClone(root)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
		elseif item:IsA("ParticleEmitter") then
			item.Enabled = false
		end
	end)
end

local function moveAuthoredVfxClone(root, targetCFrame)
	if root:IsA("BasePart") then
		root.CFrame = targetCFrame
		return true
	elseif root:IsA("Model") then
		local ok = pcall(function()
			root:PivotTo(targetCFrame)
		end)
		return ok
	end

	local part = root:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return false
	end

	local delta = targetCFrame.Position - part.Position
	eachSelfAndDescendants(root, function(item)
		if item:IsA("BasePart") then
			item.CFrame = item.CFrame + delta
		end
	end)
	return true
end

local function weldAuthoredVfxClone(root, rootPart)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("BasePart") and item ~= rootPart then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "SukeFadeFXWeld"
			weld.Part0 = rootPart
			weld.Part1 = item
			weld.Parent = item
		end
	end)
end

local function emitAuthoredVfx(root, defaultEmitCount, defaultLifetime)
	local cleanupDelay = defaultLifetime
	eachSelfAndDescendants(root, function(item)
		if not item:IsA("ParticleEmitter") then
			return
		end

		local emitCount = math.max(1, math.floor(tonumber(item:GetAttribute("EmitCount")) or defaultEmitCount))
		local emitDelay = math.max(0, tonumber(item:GetAttribute("EmitDelay")) or 0)
		cleanupDelay = math.max(cleanupDelay, emitDelay + item.Lifetime.Max)

		local function emit()
			if item and item.Parent then
				pcall(function()
					item:Emit(emitCount)
				end)
			end
		end

		if emitDelay > 0 then
			task.delay(emitDelay, emit)
		else
			emit()
		end
	end)
	return cleanupDelay
end

local function playAuthoredFadeVfx(character, rootPart, settings)
	if not settings.AuthoredVfxEnabled or not rootPart then
		return nil
	end

	local template = getAuthoredVfxTemplate(settings.AuthoredVfxName)
	local clone = nil
	if template then
		local ok = false
		ok, clone = pcall(function()
			return template:Clone()
		end)
		if not ok or not clone then
			logWarn("failed to clone authored vfx asset name=%s", tostring(settings.AuthoredVfxName))
			return nil
		end
	else
		clone = createFallbackAuthoredVfxClone(settings.AuthoredVfxName)
	end

	clone.Name = "SukeFadeAuthoredFX"
	configureAuthoredVfxClone(clone)
	if not moveAuthoredVfxClone(clone, rootPart.CFrame * settings.AuthoredVfxOffset) then
		clone:Destroy()
		return nil
	end

	-- The authored reference sits just below HumanoidRootPart; weld it there without adding physics influence.
	clone.Parent = character or rootPart.Parent
	weldAuthoredVfxClone(clone, rootPart)
	local cleanupDelay = emitAuthoredVfx(clone, settings.AuthoredVfxEmitCount, settings.AuthoredVfxLifetime)
	Debris:AddItem(clone, cleanupDelay + SHIMMER_CLEANUP_BUFFER)
	return clone
end

local function disconnectWindupSignals(windup)
	for _, connection in ipairs(windup.MarkerConnections or {}) do
		if connection then
			connection:Disconnect()
		end
	end
	windup.MarkerConnections = {}

	if windup.StoppedConnection then
		windup.StoppedConnection:Disconnect()
		windup.StoppedConnection = nil
	end
end

function SukeClient.Create(config)
	config = config or {}

	local self = setmetatable({}, SukeClient)
	self.player = config.player or Players.LocalPlayer
	self.playOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or function() end
	self.fadeStates = {}
	self.fadeWindupStates = {}
	return self
end

function SukeClient:ClearFadeWindup(targetPlayer, immediate)
	local windup = self.fadeWindupStates[targetPlayer]
	if not windup then
		return
	end

	self.fadeWindupStates[targetPlayer] = nil
	disconnectWindupSignals(windup)

	local animationState = windup.AnimationState
	if animationState and animationState.Track and not windup.TrackEnded then
		CommonAnimation.StopTrack(animationState.Track, if immediate then 0 else animationState.StopFadeTime)
	end
end

function SukeClient:ActivateFadeFromWindup(targetPlayer, windup)
	if self.fadeWindupStates[targetPlayer] ~= windup or windup.Activated then
		return false
	end

	windup.Activated = true
	return self:StartFade(targetPlayer, windup.Payload)
end

function SukeClient:ArmFadeActivation(targetPlayer, windup, animationConfig)
	local animationState = windup.AnimationState
	local track = animationState and animationState.Track
	local markerNames = getEffectMarkerNames(animationConfig)
	local effectDelay = getEffectDelay(animationConfig)

	if track then
		for _, markerName in ipairs(markerNames) do
			windup.MarkerConnections[#windup.MarkerConnections + 1] = track:GetMarkerReachedSignal(markerName):Connect(function()
				self:ActivateFadeFromWindup(targetPlayer, windup)
			end)
		end
	end

	task.delay(effectDelay, function()
		self:ActivateFadeFromWindup(targetPlayer, windup)
	end)
end

function SukeClient:StartFadeWindup(targetPlayer, payload, isPredicted)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local character = getCharacter(targetPlayer)
	if not character then
		return false
	end

	local existingWindup = self.fadeWindupStates[targetPlayer]
	if existingWindup then
		if payload ~= nil then
			existingWindup.Payload = payload
		end
		existingWindup.ServerConfirmed = existingWindup.ServerConfirmed or not isPredicted
		return true
	end

	local animationConfig = getAnimationConfig()
	local animationState = playFadeAnimation(targetPlayer)
	local windup = {
		AnimationState = animationState,
		MarkerConnections = {},
		Payload = payload,
		ServerConfirmed = not isPredicted,
		StartedAt = os.clock(),
		TrackEnded = false,
	}
	self.fadeWindupStates[targetPlayer] = windup

	-- The animation begins on input; invisibility arms from a marker or timed fallback.
	self:ArmFadeActivation(targetPlayer, windup, animationConfig)

	local track = animationState and animationState.Track
	if track then
		windup.StoppedConnection = track.Stopped:Connect(function()
			windup.TrackEnded = true
			if self.fadeWindupStates[targetPlayer] == windup then
				self:ClearFadeWindup(targetPlayer, false)
			end
		end)
	else
		task.delay(getWindupCleanupDelay(animationConfig), function()
			if self.fadeWindupStates[targetPlayer] == windup then
				self:ClearFadeWindup(targetPlayer, true)
			end
		end)
	end

	return true
end

function SukeClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName ~= ABILITY_NAME then
		if typeof(fallbackBuilder) == "function" then
			return fallbackBuilder()
		end

		return nil
	end

	local payload = nil
	if typeof(fallbackBuilder) == "function" then
		payload = fallbackBuilder()
	end

	self:StartFadeWindup(self.player, payload, true)
	return payload
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

	if immediate and state.AuthoredVfx and state.AuthoredVfx.Parent then
		state.AuthoredVfx:Destroy()
	end

	task.delay(fadeInTime + SHIMMER_CLEANUP_BUFFER, function()
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
	local rootPart = getRootPart(targetPlayer)
	local highlight = settings.ShowShimmer and createHighlight(character, settings) or nil
	local attachment = nil
	local emitter = nil
	if settings.ShowShimmer then
		attachment, emitter = createShimmerAttachment(rootPart, settings)
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
	state.AuthoredVfx = playAuthoredFadeVfx(character, rootPart, settings)

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

	return self:StartFadeWindup(targetPlayer, payload, false)
end

function SukeClient:HandleStateEvent(eventName, abilityName)
	if abilityName == ABILITY_NAME and eventName == "Denied" then
		self:ClearFadeWindup(self.player, true)
		self:ClearFade(self.player, true)
		return true
	end

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
			state.Highlight.FillTransparency =
				math.clamp(settings.HighlightFillTransparency - (pulse * HIGHLIGHT_FILL_PULSE_AMOUNT), 0, 1)
			state.Highlight.OutlineTransparency =
				math.clamp(settings.HighlightOutlineTransparency - (pulse * HIGHLIGHT_OUTLINE_PULSE_AMOUNT), 0, 1)
		end
	end

	for targetPlayer in pairs(self.fadeWindupStates) do
		if not getCharacter(targetPlayer) then
			self:ClearFadeWindup(targetPlayer, true)
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
	self:ClearFadeWindup(self.player, true)
	self:ClearFade(self.player, true)
end

function SukeClient:HandlePlayerRemoving(leavingPlayer)
	self:ClearFadeWindup(leavingPlayer, true)
	self:ClearFade(leavingPlayer, true)
end

return SukeClient
