local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudStatNotificationService = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Hud"):WaitForChild("HudStatNotificationService"))
local CounterVisibilityUtil = require(script.Parent:WaitForChild("CounterVisibilityUtil"))
local Shorten = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shorten"))

local player = Players.LocalPlayer
local moneyValue = player:WaitForChild("HiddenLeaderstats"):WaitForChild("Speed")

local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("HUD")
local counters = hud:WaitForChild("Counters")

local counter = counters:WaitForChild("Speed")
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

CounterVisibilityUtil.hideCompatibilityCounter(counter, { icon })

local normalG0 = Color3.fromRGB(255, 121, 121)
local normalG1 = Color3.fromRGB(255, 201, 176)
local normalStroke = Color3.fromRGB(70, 14, 18)

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
	return formatNumber(n) .. " Speed"
end

local function pushNotif(delta)
	HudStatNotificationService.pushValueChange({
		kind = "Speed",
		delta = delta,
		valueText = formatNumber(math.abs(delta)),
		labelText = HudStatNotificationService.getLabelFromFormattedText(moneyText(0), counter.Name),
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
end)
