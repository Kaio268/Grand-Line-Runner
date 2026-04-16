local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local rng = Random.new()

local player = Players.LocalPlayer
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local HudCounterConfig = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Hud"):WaitForChild("HudCounterConfig"))
local HudStatNotificationService = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Hud"):WaitForChild("HudStatNotificationService"))
local CounterVisibilityUtil = require(script.Parent:WaitForChild("CounterVisibilityUtil"))
local Shorten = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shorten"))
local currencyConfig = CurrencyUtil.getConfig()
local moneyValue = CurrencyUtil.waitForPrimaryValueObject(player, 10)
if not moneyValue then
	error("Primary currency value object was not found for CounterMoney")
end

local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("HUD")
local counters = hud:WaitForChild("Counters")

local counter = counters:WaitForChild("Money")
local textLabel = counter
local uiGradient = textLabel:WaitForChild("UIGradient")
local uiStroke = textLabel:WaitForChild("UIStroke")
local icon = counter:FindFirstChildWhichIsA("ImageLabel")

local function ensureFrame(parent, name, zIndex)
	local frame = parent:FindFirstChild(name)
	if frame and frame:IsA("Frame") then
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = false
		frame.ZIndex = zIndex
		return frame
	end

	frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = false
	frame.ZIndex = zIndex
	frame.Parent = parent

	return frame
end

local function ensureVisibleFxHosts()
	local displayLayer = ensureFrame(hud, "ReactHudCountersLayer", HudCounterConfig.DisplayLayerZIndex)
	local moneyAnchor = ensureFrame(displayLayer, "ReactHudMoneyRowAnchor", HudCounterConfig.DisplayLayerZIndex + 10)
	local notifications = ensureFrame(displayLayer, "ReactHudCounterNotifications", HudCounterConfig.DisplayLayerZIndex + 12)
	local particles = ensureFrame(moneyAnchor, "ReactHudMoneyParticles", HudCounterConfig.DisplayLayerZIndex + 11)

	local totalHeight = HudCounterConfig.getTotalHeight(3)
	local moneyRowY = HudCounterConfig.getRowY(3)
	local _, bottomRightInset = GuiService:GetGuiInset()

	displayLayer.AnchorPoint = Vector2.new(0, 1)
	displayLayer.Position = UDim2.new(0, HudCounterConfig.LeftPadding, 1, -(HudCounterConfig.BottomPadding + bottomRightInset.Y))
	displayLayer.Size = UDim2.new(0, HudCounterConfig.Width, 0, totalHeight)

	moneyAnchor.AnchorPoint = Vector2.new(0, 0)
	moneyAnchor.Position = UDim2.new(0, HudCounterConfig.getContentLeft(), 0, moneyRowY)
	moneyAnchor.Size = UDim2.new(0, HudCounterConfig.getContentWidth(), 0, HudCounterConfig.RowHeight)

	particles.AnchorPoint = Vector2.new(0, 0)
	particles.Position = UDim2.fromOffset(0, 0)
	particles.Size = UDim2.fromScale(1, 1)

	notifications.AnchorPoint = Vector2.new(0, 0)
	notifications.Position = UDim2.new(
		0,
		HudCounterConfig.getNotificationX(),
		0,
		math.max(0, moneyRowY - HudCounterConfig.NotificationHeight + 6)
	)
	notifications.Size = UDim2.new(0, HudCounterConfig.NotificationWidth, 0, HudCounterConfig.NotificationHeight)

	return moneyAnchor, notifications, particles
end

local function trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local textScale = textLabel:FindFirstChildOfClass("UIScale")
if not textScale then
	textScale = Instance.new("UIScale")
	textScale.Parent = textLabel
end

local iconScale
if icon then
	iconScale = icon:FindFirstChildOfClass("UIScale")
	if not iconScale then
		iconScale = Instance.new("UIScale")
		iconScale.Parent = icon
	end
end

local legacyNotFrame = counters:FindFirstChild("Not")
local moneyAnchor, _, particleLayer = ensureVisibleFxHosts()

CounterVisibilityUtil.hideCompatibilityCounter(counter, { icon })
if legacyNotFrame then
	CounterVisibilityUtil.hideGuiObject(legacyNotFrame)
	for _, child in ipairs(legacyNotFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			CounterVisibilityUtil.hideGuiObject(child)
		end
	end
end

local legacyParticleLayer = counter:FindFirstChild("MoneyParticles")
if legacyParticleLayer then
	CounterVisibilityUtil.hideGuiObject(legacyParticleLayer)
end

local normalG0 = Color3.fromRGB(62, 181, 35)
local normalG1 = Color3.fromRGB(198, 255, 76)
local normalStroke = Color3.fromRGB(31, 58, 25)

local upG0 = Color3.fromRGB(255, 255, 255)
local upG1 = Color3.fromRGB(255, 255, 255)
local upStroke = Color3.fromRGB(0, 0, 0)

local downG0 = Color3.fromRGB(245, 71, 71)
local downG1 = Color3.fromRGB(255, 117, 195)
local downStroke = Color3.fromRGB(61, 20, 20)

local currentG0, currentG1 = normalG0, normalG1
local currentS = normalStroke

local function setGradient(c0, c1)
	currentG0, currentG1 = c0, c1
	uiGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c0),
		ColorSequenceKeypoint.new(1, c1),
	})
end

local function setStroke(c)
	currentS = c
	uiStroke.Color = c
end

local function formatNumber(n)
	return Shorten.withCommas(math.floor((tonumber(n) or 0) + 0.5))
end

local function moneyText(n)
	return formatNumber(n) .. CurrencyUtil.getCompactSuffix()
end

local function pushNotif(delta)
	HudStatNotificationService.pushValueChange({
		kind = "Money",
		delta = delta,
		valueText = formatNumber(math.abs(delta)),
		labelText = HudStatNotificationService.getLabelFromFormattedText(moneyText(0), trim(CurrencyUtil.getCompactSuffix())),
		icon = HudStatNotificationService.snapshotIcon(icon),
	})
end

setGradient(normalG0, normalG1)
setStroke(normalStroke)

local displayed = moneyValue.Value
textLabel.Text = moneyText(displayed)

local animId = 0
local activeTween, activeNum
local connValueChanged, connRender, connCompleted
local restoreBlend, restoreTween
local posTween, rotTween, textRotTween, iconRotTween, textScaleTween, iconScaleTween

local homeCounterPos = counter.Position
local homeCounterRot = counter.Rotation
local homeTextRot = textLabel.Rotation
local homeTextScale = textScale.Scale
local homeIconRot = icon and icon.Rotation or 0
local homeIconScale = iconScale and iconScale.Scale or 1

local function hardRestore()
	counter.Position = homeCounterPos
	counter.Rotation = homeCounterRot
	textLabel.Rotation = homeTextRot
	textScale.Scale = homeTextScale
	if icon then
		icon.Rotation = homeIconRot
	end
	if iconScale then
		iconScale.Scale = homeIconScale
	end
end

local function clearActive()
	if connRender then
		connRender:Disconnect()
		connRender = nil
	end
	if connValueChanged then
		connValueChanged:Disconnect()
		connValueChanged = nil
	end
	if connCompleted then
		connCompleted:Disconnect()
		connCompleted = nil
	end

	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	if activeNum then
		activeNum:Destroy()
		activeNum = nil
	end

	if restoreTween then
		restoreTween:Cancel()
		restoreTween = nil
	end
	if restoreBlend then
		restoreBlend:Destroy()
		restoreBlend = nil
	end

	if posTween then
		posTween:Cancel()
		posTween = nil
	end
	if rotTween then
		rotTween:Cancel()
		rotTween = nil
	end
	if textRotTween then
		textRotTween:Cancel()
		textRotTween = nil
	end
	if iconRotTween then
		iconRotTween:Cancel()
		iconRotTween = nil
	end
	if textScaleTween then
		textScaleTween:Cancel()
		textScaleTween = nil
	end
	if iconScaleTween then
		iconScaleTween:Cancel()
		iconScaleTween = nil
	end

	hardRestore()
end

local function animateBackToNormal(id)
	if restoreBlend then
		restoreBlend:Destroy()
		restoreBlend = nil
	end
	restoreBlend = Instance.new("NumberValue")
	restoreBlend.Value = 0

	local fromG0, fromG1 = currentG0, currentG1
	local fromS = currentS

	local c
	c = restoreBlend:GetPropertyChangedSignal("Value"):Connect(function()
		if id ~= animId then
			if c then
			c:Disconnect()
		end
			return
		end
		local a = restoreBlend.Value
		setGradient(fromG0:Lerp(normalG0, a), fromG1:Lerp(normalG1, a))
		setStroke(fromS:Lerp(normalStroke, a))
	end)

	restoreTween = TweenService:Create(restoreBlend, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
	restoreTween.Completed:Connect(function()
		if c then
			c:Disconnect()
		end
		if id ~= animId then
			return
		end
		if restoreBlend then
		restoreBlend:Destroy()
		restoreBlend = nil
	end
		restoreTween = nil
	end)
	restoreTween:Play()

	posTween = TweenService:Create(counter, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = homeCounterPos })
	rotTween = TweenService:Create(counter, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = homeCounterRot })
	textRotTween = TweenService:Create(textLabel, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = homeTextRot })
	textScaleTween = TweenService:Create(textScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = homeTextScale })

	posTween:Play()
	rotTween:Play()
	textRotTween:Play()
	textScaleTween:Play()

	if icon then
		iconRotTween = TweenService:Create(icon, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = homeIconRot })
		iconRotTween:Play()
	end
	if iconScale then
		iconScaleTween = TweenService:Create(iconScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = homeIconScale })
		iconScaleTween:Play()
	end
end

local function animateMoney(target)
	animId += 1
	local id = animId

	clearActive()

	homeCounterPos = counter.Position
	homeCounterRot = counter.Rotation
	homeTextRot = textLabel.Rotation
	homeTextScale = textScale.Scale
	homeIconRot = icon and icon.Rotation or 0
	homeIconScale = iconScale and iconScale.Scale or 1

	local start = displayed
	if start == target then
		textLabel.Text = moneyText(target)
		setGradient(normalG0, normalG1)
		setStroke(normalStroke)
		return
	end

	local isUp = target > start
	local delta = math.abs(target - start)
	local duration = math.clamp(0.10 + (math.log(delta + 1) / math.log(10)) * 0.10, 0.10, 0.55)

	local gradStart0, gradStart1 = currentG0, currentG1
	local strokeStart = currentS

	local gradEnd0, gradEnd1, strokeEnd
	if isUp then
		gradEnd0, gradEnd1, strokeEnd = upG0, upG1, upStroke
	else
		gradEnd0, gradEnd1, strokeEnd = downG0, downG1, downStroke
	end

	activeNum = Instance.new("NumberValue")
	activeNum.Value = start

	connValueChanged = activeNum:GetPropertyChangedSignal("Value"):Connect(function()
		if id ~= animId then
			return
		end
		local v = math.floor(activeNum.Value + 0.5)
		displayed = v
		textLabel.Text = moneyText(v)
	end)

	activeTween = TweenService:Create(activeNum, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })

	local t0 = os.clock()
	local counterShake = isUp and 1.15 or 1.45
	local counterRotAmp = isUp and 1.4 or 2.0
	local textRotAmp = isUp and 4.0 or 5.5
	local textPunch = isUp and 0.15 or 0.13
	local iconPunch = isUp and 0.06 or 0.05

	connRender = RunService.RenderStepped:Connect(function()
		if id ~= animId then
			return
		end
		local t = os.clock()
		local p = math.clamp((t - t0) / duration, 0, 1)

		setGradient(gradStart0:Lerp(gradEnd0, p), gradStart1:Lerp(gradEnd1, p))
		setStroke(strokeStart:Lerp(strokeEnd, p))

		local intensity = 0.35 + 0.65 * (1 - p)

		local nx = (math.noise((t - t0) * 22, id, 0) - 0.5) * 2
		local ny = (math.noise((t - t0) * 22, 0, id) - 0.5) * 2
		local ox = nx * counterShake * intensity
		local oy = ny * counterShake * intensity

		counter.Position = UDim2.new(homeCounterPos.X.Scale, homeCounterPos.X.Offset + ox, homeCounterPos.Y.Scale, homeCounterPos.Y.Offset + oy)
		counter.Rotation = homeCounterRot + math.sin((t - t0) * 18) * counterRotAmp * intensity

		textLabel.Rotation = homeTextRot + math.sin((t - t0) * 28) * textRotAmp * intensity
		textScale.Scale = homeTextScale * (1 + textPunch * (1 - p) + 0.03 * math.sin((t - t0) * 30))

		if icon then
			icon.Rotation = homeIconRot + math.sin((t - t0) * 18 + 0.6) * (counterRotAmp * 0.6) * intensity
		end
		if iconScale then
			iconScale.Scale = homeIconScale * (1 + iconPunch * (1 - p) + 0.015 * math.sin((t - t0) * 26 + 0.7))
		end

		if p >= 1 then
			if connRender then
		connRender:Disconnect()
		connRender = nil
	end
		end
	end)

	connCompleted = activeTween.Completed:Connect(function(state)
		if id ~= animId then
			return
		end
		if state ~= Enum.PlaybackState.Completed then
			return
		end

		displayed = target
		textLabel.Text = moneyText(target)

		if connValueChanged then
		connValueChanged:Disconnect()
		connValueChanged = nil
	end
		if activeNum then
		activeNum:Destroy()
		activeNum = nil
	end
		activeTween = nil

		animateBackToNormal(id)
	end)

	activeTween:Play()
end

local particles = {}
local particleConn

local function getBurstOriginPx()
	local anchorSize = moneyAnchor.AbsoluteSize
	local barX = HudCounterConfig.getBarX()
	local barWidth = math.max(1, anchorSize.X - barX)
	local x = barX + (barWidth * 0.45)
	local y = anchorSize.Y * 0.5
	return Vector2.new(x, y), anchorSize
end

local function pxToScaleUdim2(px, absSize)
	if absSize.X <= 0 or absSize.Y <= 0 then
		return UDim2.new(0.5, 0, 0.5, 0)
	end
	return UDim2.new(px.X / absSize.X, 0, px.Y / absSize.Y, 0)
end

local function ensureParticleLoop()
	if particleConn then
		return
	end
	particleConn = RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local absSize = particleLayer.AbsoluteSize
		local damp = math.pow(0.985, dt * 60)

		for i = #particles, 1, -1 do
			local p = particles[i]
			local age = now - p.born

			if age >= p.life or not p.gui or not p.gui.Parent then
				if p.gui and p.gui.Parent then
				p.gui:Destroy()
			end
				table.remove(particles, i)
			else
				p.vel = (p.vel * damp) + Vector2.new(0, p.g * dt)
				p.pos = p.pos + p.vel * dt
				p.rot = p.rot + p.rotVel * dt

				p.gui.Position = pxToScaleUdim2(p.pos, absSize)
				p.gui.Rotation = p.rot

				if age > p.fadeStart then
					local a = math.clamp((age - p.fadeStart) / (p.life - p.fadeStart), 0, 1)
					p.gui.TextTransparency = a
					if p.stroke then
					p.stroke.Transparency = a
				end
					if p.scale then
					p.scale.Scale = p.baseScale * (1 - 0.2 * a)
				end
				end
			end
		end

		if #particles == 0 and particleConn then
			particleConn:Disconnect()
			particleConn = nil
		end
	end)
end

local function spawnDollarBurst()
	local originPx, tSize = getBurstOriginPx()
	local count = rng:NextInteger(2, 3)
	local absSize = particleLayer.AbsoluteSize
	local spreadX = tSize.X * 0.35

	for _ = 1, count do
		local sizeScaleX = rng:NextNumber(1, 0.3)
		local sizeScaleY = rng:NextNumber(1, 0.3)

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.BorderSizePixel = 0
		lbl.AnchorPoint = Vector2.new(0.5, 0.5)
		lbl.Size = UDim2.new(sizeScaleX, 0, sizeScaleY, 0)
		lbl.Position = pxToScaleUdim2(originPx, absSize)
		lbl.ZIndex = particleLayer.ZIndex + 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.Text = currencyConfig.ShortLabel
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(90, 255, 49)
		lbl.TextTransparency = 0
		lbl.Parent = particleLayer

		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(0, 0, 0)
		st.Thickness = 2
		st.Parent = lbl

		local sc = Instance.new("UIScale")
		sc.Scale = 0.35
		sc.Parent = lbl

		TweenService:Create(sc, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

		local startPos = Vector2.new(
			originPx.X + rng:NextNumber(-spreadX, spreadX),
			originPx.Y + rng:NextNumber(-6, 6)
		)

		local vel = Vector2.new(
			rng:NextNumber(-260, 260),
			rng:NextNumber(-820, -560)
		)

		local state = {
			gui = lbl,
			stroke = st,
			scale = sc,
			baseScale = rng:NextNumber(1.05, 1.45),
			pos = startPos,
			vel = vel,
			rot = rng:NextNumber(-25, 25),
			rotVel = rng:NextNumber(-260, 260),
			born = os.clock(),
			life = rng:NextNumber(0.85, 1.15),
			fadeStart = rng:NextNumber(0.45, 0.65),
			g = rng:NextNumber(1400, 1900),
		}

		lbl.Rotation = state.rot
		sc.Scale = 0.35 * state.baseScale
		lbl.Position = pxToScaleUdim2(state.pos, absSize)

		table.insert(particles, state)
	end

	while #particles > 30 do
		local p = table.remove(particles, 1)
		if p.gui and p.gui.Parent then
				p.gui:Destroy()
			end
	end

	ensureParticleLoop()
end

local last = moneyValue.Value
moneyValue:GetPropertyChangedSignal("Value"):Connect(function()
	local newVal = moneyValue.Value
	if newVal == last then
		return
	end
	local diff = newVal - last
	last = newVal
	animateMoney(newVal)
	pushNotif(diff)
	if diff > 0 then
		spawnDollarBurst()
	end
end)
