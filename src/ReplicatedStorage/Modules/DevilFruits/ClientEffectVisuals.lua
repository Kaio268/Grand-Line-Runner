local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientEffectVisuals = {}
ClientEffectVisuals.__index = ClientEffectVisuals

local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local DEFAULT_MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_MERA_FRUIT_NAME = "Mera Mera no Mi"
local DEFAULT_FIRE_BURST_ABILITY = "FireBurst"
local DEFAULT_BOMU_FRUIT_NAME = "Bomu Bomu no Mi"
local DEFAULT_BOMU_DETONATION_ABILITY = "LandMine"
local DEFAULT_PHOENIX_FRUIT_NAME = "Tori Tori no Mi"
local DEFAULT_PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local DEFAULT_PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local DEFAULT_GOMU_FRUIT_NAME = "Gomu Gomu no Mi"
local DEFAULT_RUBBER_LAUNCH_ABILITY = "RubberLaunch"
local DEFAULT_PHOENIX_EFFECT_COLOR = Color3.fromRGB(108, 255, 214)
local DEFAULT_PHOENIX_EFFECT_ACCENT_COLOR = Color3.fromRGB(255, 188, 113)
local PHOENIX_SHIELD_HIT_COLOR = Color3.fromRGB(255, 48, 72)
local PHOENIX_SHIELD_HIT_ACCENT_COLOR = Color3.fromRGB(255, 169, 103)
local FLAT_RING_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local function resolvePlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function resolveColor(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function createPulse(name, position, color, initialSize, finalSize, duration)
	local pulse = Instance.new("Part")
	pulse.Name = name
	pulse.Shape = Enum.PartType.Ball
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanTouch = false
	pulse.CanQuery = false
	pulse.Material = Enum.Material.Neon
	pulse.Color = color
	pulse.Transparency = 0.18
	pulse.Size = Vector3.new(initialSize, initialSize, initialSize)
	pulse.CFrame = CFrame.new(position)
	pulse.Parent = Workspace

	local tween = TweenService:Create(pulse, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(finalSize, finalSize, finalSize),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if pulse.Parent then
			pulse:Destroy()
		end
	end)
end

function ClientEffectVisuals.new(config)
	config = config or {}

	return setmetatable({
		GetLocalRootPart = type(config.GetLocalRootPart) == "function" and config.GetLocalRootPart or function()
			return nil
		end,
		GetPlayerRootPart = type(config.GetPlayerRootPart) == "function" and config.GetPlayerRootPart or resolvePlayerRootPart,
		MinDirectionMagnitude = math.max(DEFAULT_MIN_DIRECTION_MAGNITUDE, tonumber(config.MinDirectionMagnitude) or DEFAULT_MIN_DIRECTION_MAGNITUDE),
		MeraFruitName = tostring(config.MeraFruitName or DEFAULT_MERA_FRUIT_NAME),
		FireBurstAbility = tostring(config.FireBurstAbility or DEFAULT_FIRE_BURST_ABILITY),
		BomuFruitName = tostring(config.BomuFruitName or DEFAULT_BOMU_FRUIT_NAME),
		BomuDetonationAbility = tostring(config.BomuDetonationAbility or DEFAULT_BOMU_DETONATION_ABILITY),
		PhoenixFruitName = tostring(config.PhoenixFruitName or DEFAULT_PHOENIX_FRUIT_NAME),
		PhoenixFlightAbility = tostring(config.PhoenixFlightAbility or DEFAULT_PHOENIX_FLIGHT_ABILITY),
		PhoenixShieldAbility = tostring(config.PhoenixShieldAbility or DEFAULT_PHOENIX_SHIELD_ABILITY),
		PhoenixEffectColor = resolveColor(config.PhoenixEffectColor, DEFAULT_PHOENIX_EFFECT_COLOR),
		PhoenixEffectAccentColor = resolveColor(config.PhoenixEffectAccentColor, DEFAULT_PHOENIX_EFFECT_ACCENT_COLOR),
		GomuFruitName = tostring(config.GomuFruitName or DEFAULT_GOMU_FRUIT_NAME),
		RubberLaunchAbility = tostring(config.RubberLaunchAbility or DEFAULT_RUBBER_LAUNCH_ABILITY),
	}, ClientEffectVisuals)
end

function ClientEffectVisuals:CreateMeraFlameDashEffectVisual(startPosition, endPosition, direction, isPredicted)
	if typeof(startPosition) ~= "Vector3" then
		return
	end

	local resolvedDirection = typeof(direction) == "Vector3" and direction or DEFAULT_DIRECTION
	if resolvedDirection.Magnitude <= self.MinDirectionMagnitude then
		resolvedDirection = DEFAULT_DIRECTION
	else
		resolvedDirection = resolvedDirection.Unit
	end

	local origin = startPosition + Vector3.new(0, 1.1, 0)
	local destination = typeof(endPosition) == "Vector3" and (endPosition + Vector3.new(0, 1.1, 0))
		or (origin + (resolvedDirection * 14))
	local segment = destination - origin
	local segmentLength = segment.Magnitude
	local primaryColor = isPredicted and Color3.fromRGB(255, 185, 92) or Color3.fromRGB(255, 137, 56)
	local accentColor = Color3.fromRGB(255, 232, 180)

	createPulse("MeraDashPulseStart", origin, primaryColor, 2.2, 6.2, 0.24)
	createPulse("MeraDashPulseEnd", destination, accentColor, 1.6, 4.4, 0.22)

	if segmentLength > 0.2 then
		local streak = Instance.new("Part")
		streak.Name = "MeraDashStreak"
		streak.Anchored = true
		streak.CanCollide = false
		streak.CanTouch = false
		streak.CanQuery = false
		streak.Material = Enum.Material.Neon
		streak.Color = primaryColor
		streak.Transparency = 0.12
		streak.Size = Vector3.new(1.15, 1.15, segmentLength)
		streak.CFrame = CFrame.lookAt(origin:Lerp(destination, 0.5), destination)
		streak.Parent = Workspace

		local aura = Instance.new("Part")
		aura.Name = "MeraDashAura"
		aura.Anchored = true
		aura.CanCollide = false
		aura.CanTouch = false
		aura.CanQuery = false
		aura.Material = Enum.Material.Neon
		aura.Color = accentColor
		aura.Transparency = 0.72
		aura.Size = Vector3.new(2.2, 2.2, segmentLength * 1.04)
		aura.CFrame = streak.CFrame
		aura.Parent = Workspace

		local streakTween = TweenService:Create(streak, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.2, 0.2, segmentLength * 1.1),
		})
		local auraTween = TweenService:Create(aura, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(3.6, 3.6, segmentLength * 1.12),
		})

		streakTween:Play()
		auraTween:Play()
		streakTween.Completed:Connect(function()
			if streak.Parent then
				streak:Destroy()
			end
		end)
		auraTween.Completed:Connect(function()
			if aura.Parent then
				aura:Destroy()
			end
		end)
	end

	for sampleIndex = 1, 6 do
		local alpha = sampleIndex / 7
		local samplePosition = origin:Lerp(destination, alpha)
		task.delay((sampleIndex - 1) * 0.02, function()
			createPulse("MeraDashTrail", samplePosition, primaryColor, 0.8, 2.1, 0.18)
		end)
	end
end

function ClientEffectVisuals:CreateFallbackBurstEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.MeraFruitName or abilityName ~= self.FireBurstAbility then
		return
	end

	payload = payload or {}

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	local radius = tonumber(payload.Radius) or 10

	local ring = Instance.new("Part")
	ring.Name = "MeraFireBurstRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 136, 32)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(rootPart.Position) * FLAT_RING_ROTATION
	ring.Parent = Workspace

	local tween = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, radius * 2.6, radius * 2.6),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

function ClientEffectVisuals:GetEffectOriginPosition(targetPlayer, payload)
	if typeof(payload) == "table" and typeof(payload.OriginPosition) == "Vector3" then
		return payload.OriginPosition
	end

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	return rootPart and rootPart.Position or nil
end

function ClientEffectVisuals:CreateBomuDetonationEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.BomuFruitName or abilityName ~= self.BomuDetonationAbility then
		return
	end

	if payload and payload.Action ~= "Detonated" then
		return
	end

	local originPosition = self:GetEffectOriginPosition(targetPlayer, payload)
	if not originPosition then
		return
	end

	local radius = math.max(1, tonumber(payload and payload.Radius) or 8)
	local blastDiameter = radius * 2
	local initialDiameter = math.max(1.5, blastDiameter * 0.2)

	local flash = Instance.new("Part")
	flash.Name = "BomuDetonationFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 225, 153)
	flash.Transparency = 0.12
	flash.Size = Vector3.new(initialDiameter, initialDiameter, initialDiameter)
	flash.CFrame = CFrame.new(originPosition)
	flash.Parent = Workspace

	local ring = Instance.new("Part")
	ring.Name = "BomuDetonationRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 171, 82)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.25, math.max(0.5, initialDiameter), math.max(0.5, initialDiameter))
	ring.CFrame = CFrame.new(originPosition) * FLAT_RING_ROTATION
	ring.Parent = Workspace

	local flashTween = TweenService:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(blastDiameter, blastDiameter, blastDiameter),
	})
	local ringTween = TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.25, blastDiameter, blastDiameter),
	})

	flashTween:Play()
	ringTween:Play()

	flashTween.Completed:Connect(function()
		if flash.Parent then
			flash:Destroy()
		end
	end)

	ringTween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

function ClientEffectVisuals:CreatePhoenixFlightEffect(targetPlayer, fruitName, abilityName)
	if fruitName ~= self.PhoenixFruitName or abilityName ~= self.PhoenixFlightAbility then
		return
	end

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	local burst = Instance.new("Part")
	burst.Name = "PhoenixFlightBurst"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Material = Enum.Material.Neon
	burst.Color = self.PhoenixEffectColor
	burst.Transparency = 0.18
	burst.Size = Vector3.new(2.25, 2.25, 2.25)
	burst.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 1.5, 0))
	burst.Parent = Workspace

	local ring = Instance.new("Part")
	ring.Name = "PhoenixFlightRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = self.PhoenixEffectAccentColor
	ring.Transparency = 0.28
	ring.Size = Vector3.new(0.22, 4.8, 4.8)
	ring.CFrame = CFrame.new(rootPart.Position) * FLAT_RING_ROTATION
	ring.Parent = Workspace

	local burstTween = TweenService:Create(burst, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(7, 7, 7),
	})
	local ringTween = TweenService:Create(ring, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.22, 9, 9),
	})

	burstTween:Play()
	ringTween:Play()

	burstTween.Completed:Connect(function()
		if burst.Parent then
			burst:Destroy()
		end
	end)

	ringTween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

function ClientEffectVisuals:CreatePhoenixShieldEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.PhoenixFruitName or abilityName ~= self.PhoenixShieldAbility then
		return
	end

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	payload = payload or {}

	local radius = math.max(1, tonumber(payload.Radius) or 13)
	local duration = math.max(0.1, tonumber(payload.Duration) or 2.75)
	local endTime = os.clock() + duration

	local ring = Instance.new("Part")
	ring.Name = "PhoenixShieldRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = self.PhoenixEffectColor
	ring.Transparency = 0.32
	ring.Size = Vector3.new(0.24, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(rootPart.Position - Vector3.new(0, 2.6, 0)) * FLAT_RING_ROTATION
	ring.Parent = Workspace

	local aura = Instance.new("Part")
	aura.Name = "PhoenixShieldAura"
	aura.Shape = Enum.PartType.Ball
	aura.Anchored = true
	aura.CanCollide = false
	aura.CanTouch = false
	aura.CanQuery = false
	aura.Material = Enum.Material.ForceField
	aura.Color = self.PhoenixEffectAccentColor
	aura.Transparency = 0.72
	aura.Size = Vector3.new(4.5, 4.5, 4.5)
	aura.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 1.5, 0))
	aura.Parent = Workspace

	local ringTween = TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
		Transparency = 0.82,
	})
	local auraTween = TweenService:Create(aura, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
		Transparency = 1,
	})

	ringTween:Play()
	auraTween:Play()

	task.spawn(function()
		while ring.Parent and aura.Parent and os.clock() < endTime do
			local currentRootPart = self.GetPlayerRootPart(targetPlayer)
			if not currentRootPart then
				break
			end

			ring.CFrame = CFrame.new(currentRootPart.Position - Vector3.new(0, 2.6, 0)) * FLAT_RING_ROTATION
			aura.CFrame = CFrame.new(currentRootPart.Position + Vector3.new(0, 1.5, 0))
			RunService.Heartbeat:Wait()
		end

		if ring.Parent then
			ring:Destroy()
		end
		if aura.Parent then
			aura:Destroy()
		end
	end)
end

function ClientEffectVisuals:CreatePhoenixShieldHitEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.PhoenixFruitName or abilityName ~= self.PhoenixShieldAbility then
		return
	end

	payload = payload or {}

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	local hitPosition = typeof(payload.HitPosition) == "Vector3" and payload.HitPosition or nil
	if not hitPosition then
		if not rootPart then
			return
		end

		hitPosition = rootPart.Position + Vector3.new(0, 1.5, 0)
	end

	local radius = math.max(1, tonumber(payload.Radius) or 13)
	local rippleDiameter = math.clamp(radius * 0.55, 3.5, 8)

	createPulse("PhoenixShieldHitFlash", hitPosition, PHOENIX_SHIELD_HIT_ACCENT_COLOR, 1.5, rippleDiameter, 0.2)

	local ripple = Instance.new("Part")
	ripple.Name = "PhoenixShieldHitRipple"
	ripple.Shape = Enum.PartType.Cylinder
	ripple.Anchored = true
	ripple.CanCollide = false
	ripple.CanTouch = false
	ripple.CanQuery = false
	ripple.Material = Enum.Material.Neon
	ripple.Color = PHOENIX_SHIELD_HIT_COLOR
	ripple.Transparency = 0.08
	ripple.Size = Vector3.new(0.2, 1.8, 1.8)
	ripple.CFrame = CFrame.new(hitPosition) * FLAT_RING_ROTATION
	ripple.Parent = Workspace

	local rippleTween = TweenService:Create(ripple, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, rippleDiameter, rippleDiameter),
	})

	rippleTween:Play()
	rippleTween.Completed:Connect(function()
		if ripple.Parent then
			ripple:Destroy()
		end
	end)

	if rootPart then
		local shieldFlash = Instance.new("Part")
		shieldFlash.Name = "PhoenixShieldHitShell"
		shieldFlash.Shape = Enum.PartType.Ball
		shieldFlash.Anchored = true
		shieldFlash.CanCollide = false
		shieldFlash.CanTouch = false
		shieldFlash.CanQuery = false
		shieldFlash.Material = Enum.Material.ForceField
		shieldFlash.Color = PHOENIX_SHIELD_HIT_COLOR
		shieldFlash.Transparency = 0.45
		shieldFlash.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		shieldFlash.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 1.5, 0))
		shieldFlash.Parent = Workspace

		local shellTween = TweenService:Create(shieldFlash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(radius * 2.12, radius * 2.12, radius * 2.12),
		})

		shellTween:Play()
		shellTween.Completed:Connect(function()
			if shieldFlash.Parent then
				shieldFlash:Destroy()
			end
		end)
	end
end

function ClientEffectVisuals:CreateRubberLaunchEffect(_targetPlayer, fruitName, abilityName, _payload)
	if fruitName ~= self.GomuFruitName or abilityName ~= self.RubberLaunchAbility then
		return
	end

	return
end

return ClientEffectVisuals
