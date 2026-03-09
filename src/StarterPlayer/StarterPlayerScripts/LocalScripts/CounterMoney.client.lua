local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local rng = Random.new()

local player = Players.LocalPlayer
local moneyValue = player:WaitForChild("leaderstats"):WaitForChild("Money")

local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("HUD")
local counters = hud:WaitForChild("Counters")

local counter = counters:WaitForChild("Money")
local textLabel = counter
local uiGradient = textLabel:WaitForChild("UIGradient")
local uiStroke = textLabel:WaitForChild("UIStroke")
local icon = counter:FindFirstChildWhichIsA("ImageLabel")

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

local notFrame = counters:WaitForChild("Not")
local plusTemplate = notFrame:WaitForChild("Plus")
local minusTemplate = notFrame:WaitForChild("Minus")
plusTemplate.Visible = false
minusTemplate.Visible = false

local particleLayer = counter:FindFirstChild("MoneyParticles")
if not particleLayer then
	particleLayer = Instance.new("Frame")
	particleLayer.Name = "MoneyParticles"
	particleLayer.BackgroundTransparency = 1
	particleLayer.BorderSizePixel = 0
	particleLayer.Size = UDim2.new(1, 0, 1, 0)
	particleLayer.Position = UDim2.new(0, 0, 0, 0)
	particleLayer.ClipsDescendants = false
	particleLayer.ZIndex = math.max(textLabel.ZIndex, counter.ZIndex) + 10
	particleLayer.Parent = counter
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
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end
	local s = tostring(math.floor(n + 0.5))
	local out = {}
	local count = 0
	for i = #s, 1, -1 do
		count += 1
		out[#out + 1] = s:sub(i, i)
		if count % 3 == 0 and i > 1 then
			out[#out + 1] = ","
		end
	end
	return sign .. table.concat(out):reverse()
end

local function moneyText(n)
	return formatNumber(n) .. "$"
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
	if icon then icon.Rotation = homeIconRot end
	if iconScale then iconScale.Scale = homeIconScale end
end

local function clearActive()
	if connRender then connRender:Disconnect() connRender = nil end
	if connValueChanged then connValueChanged:Disconnect() connValueChanged = nil end
	if connCompleted then connCompleted:Disconnect() connCompleted = nil end

	if activeTween then activeTween:Cancel() activeTween = nil end
	if activeNum then activeNum:Destroy() activeNum = nil end

	if restoreTween then restoreTween:Cancel() restoreTween = nil end
	if restoreBlend then restoreBlend:Destroy() restoreBlend = nil end

	if posTween then posTween:Cancel() posTween = nil end
	if rotTween then rotTween:Cancel() rotTween = nil end
	if textRotTween then textRotTween:Cancel() textRotTween = nil end
	if iconRotTween then iconRotTween:Cancel() iconRotTween = nil end
	if textScaleTween then textScaleTween:Cancel() textScaleTween = nil end
	if iconScaleTween then iconScaleTween:Cancel() iconScaleTween = nil end

	hardRestore()
end

local function animateBackToNormal(id)
	if restoreBlend then restoreBlend:Destroy() restoreBlend = nil end
	restoreBlend = Instance.new("NumberValue")
	restoreBlend.Value = 0

	local fromG0, fromG1 = currentG0, currentG1
	local fromS = currentS

	local c
	c = restoreBlend:GetPropertyChangedSignal("Value"):Connect(function()
		if id ~= animId then
			if c then c:Disconnect() end
			return
		end
		local a = restoreBlend.Value
		setGradient(fromG0:Lerp(normalG0, a), fromG1:Lerp(normalG1, a))
		setStroke(fromS:Lerp(normalStroke, a))
	end)

	restoreTween = TweenService:Create(restoreBlend, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
	restoreTween.Completed:Connect(function()
		if c then c:Disconnect() end
		if id ~= animId then return end
		if restoreBlend then restoreBlend:Destroy() restoreBlend = nil end
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
		if id ~= animId then return end
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
		if id ~= animId then return end
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
			if connRender then connRender:Disconnect() connRender = nil end
		end
	end)

	connCompleted = activeTween.Completed:Connect(function(state)
		if id ~= animId then return end
		if state ~= Enum.PlaybackState.Completed then return end

		displayed = target
		textLabel.Text = moneyText(target)

		if connValueChanged then connValueChanged:Disconnect() connValueChanged = nil end
		if activeNum then activeNum:Destroy() activeNum = nil end
		activeTween = nil

		animateBackToNormal(id)
	end)

	activeTween:Play()
end

local function ensureScale(o)
	local s = o:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Parent = o
	end
	return s
end

local function animateNotifIn(lbl)
	local s = ensureScale(lbl)
	lbl.Visible = true
	lbl.Rotation = rng:NextNumber(-8, 8)
	s.Scale = 0.35

	if lbl:IsA("TextLabel") or lbl:IsA("TextButton") then
		lbl.TextTransparency = 1
	end
	local st = lbl:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 1
	end

	local t1 = TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	local t2 = TweenService:Create(lbl, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0, TextTransparency = 0 })
	local t3
	if st then
		t3 = TweenService:Create(st, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 0 })
	end

	t1:Play()
	t2:Play()
	if t3 then t3:Play() end
end

local function animateNotifOut(lbl)
	if not lbl or not lbl.Parent then return end
	if lbl:GetAttribute("Closing") then return end
	lbl:SetAttribute("Closing", true)

	local s = ensureScale(lbl)
	local st = lbl:FindFirstChildOfClass("UIStroke")

	local t1 = TweenService:Create(s, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.2 })
	local t2 = TweenService:Create(lbl, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Rotation = rng:NextNumber(-14, 14), TextTransparency = 1 })
	local t3
	if st then
		t3 = TweenService:Create(st, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
	end

	local cleaned = false
	local function cleanup()
		if cleaned then return end
		cleaned = true
		if lbl and lbl.Parent then
			lbl:Destroy()
		end
	end

	t1.Completed:Connect(cleanup)
	task.delay(0.25, cleanup)

	t1:Play()
	t2:Play()
	if t3 then t3:Play() end
end

local notifQueue = {}
local notifOrder = 0
local notifUid = 0
local notifAlive = {}

local MAX_NOTIFS = 6
local NOTIF_LIFE = 1.6

local function removeQueue(uid)
	for i = #notifQueue, 1, -1 do
		if notifQueue[i] == uid then
			table.remove(notifQueue, i)
			return
		end
	end
end

local function pushNotif(delta)
	if delta == 0 then return end

	local template = delta > 0 and plusTemplate or minusTemplate
	local lbl = template:Clone()
	lbl.Parent = notFrame
	lbl.Visible = true

	notifOrder += 1
	lbl.LayoutOrder = notifOrder
	lbl.Text = (delta > 0 and "+" or "-") .. formatNumber(math.abs(delta)) .. "$"

	notifUid += 1
	local uid = notifUid
	notifAlive[uid] = true
	lbl:SetAttribute("NotifId", uid)

	table.insert(notifQueue, uid)

	animateNotifIn(lbl)

	task.delay(NOTIF_LIFE, function()
		if notifAlive[uid] then
			notifAlive[uid] = false
			removeQueue(uid)
			if lbl and lbl.Parent then
				animateNotifOut(lbl)
			end
		end
	end)

	while #notifQueue > MAX_NOTIFS do
		local oldUid = table.remove(notifQueue, 1)
		if notifAlive[oldUid] then
			notifAlive[oldUid] = false
		end
		for _, child in ipairs(notFrame:GetChildren()) do
			if child:IsA("GuiObject") and child:GetAttribute("NotifId") == oldUid then
				animateNotifOut(child)
				break
			end
		end
	end
end

local particles = {}
local particleConn

local function getBurstOriginPx()
	local cAbs = counter.AbsolutePosition
	local tAbs = textLabel.AbsolutePosition
	local tSize = textLabel.AbsoluteSize
	local x = (tAbs.X - cAbs.X) + tSize.X * 0.5
	local y = (tAbs.Y - cAbs.Y) + tSize.Y * 0.05
	return Vector2.new(x, y), Vector2.new(tSize.X, tSize.Y)
end

local function pxToScaleUdim2(px, absSize)
	if absSize.X <= 0 or absSize.Y <= 0 then
		return UDim2.new(0.5, 0, 0.5, 0)
	end
	return UDim2.new(px.X / absSize.X, 0, px.Y / absSize.Y, 0)
end

local function ensureParticleLoop()
	if particleConn then return end
	particleConn = RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local absSize = particleLayer.AbsoluteSize
		local damp = math.pow(0.985, dt * 60)

		for i = #particles, 1, -1 do
			local p = particles[i]
			local age = now - p.born

			if age >= p.life or not p.gui or not p.gui.Parent then
				if p.gui and p.gui.Parent then p.gui:Destroy() end
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
					if p.stroke then p.stroke.Transparency = a end
					if p.scale then p.scale.Scale = p.baseScale * (1 - 0.2 * a) end
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
		lbl.Text = "$"
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
		if p.gui and p.gui.Parent then p.gui:Destroy() end
	end

	ensureParticleLoop()
end

local last = moneyValue.Value
moneyValue:GetPropertyChangedSignal("Value"):Connect(function()
	local newVal = moneyValue.Value
	if newVal == last then return end
	local diff = newVal - last
	last = newVal
	animateMoney(newVal)
	pushNotif(diff)
	if diff > 0 then
		spawnDollarBurst()
	end
end)
