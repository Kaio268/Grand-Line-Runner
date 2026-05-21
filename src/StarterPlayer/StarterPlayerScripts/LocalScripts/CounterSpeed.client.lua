local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HudFolder = ReplicatedStorage:WaitForChild("UI"):WaitForChild("Hud")
local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")

local CounterVisibilityUtil = require(script.Parent:WaitForChild("CounterVisibilityUtil"))
local HitEffectConfig = require(ModulesFolder:WaitForChild("Configs"):WaitForChild("HitEffects"))
local HudStatNotificationService = require(HudFolder:WaitForChild("HudStatNotificationService"))
local HudStatsTheme = require(HudFolder:WaitForChild("HudStatsTheme"))
local MovementSpeedConfig = require(ModulesFolder:WaitForChild("Configs"):WaitForChild("MovementSpeed"))
local Shorten = require(ModulesFolder:WaitForChild("Shorten"))

local player = Players.LocalPlayer
local earnedSpeedValue = player:WaitForChild("HiddenLeaderstats"):WaitForChild("Speed")

local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("HUD")
local counters = hud:WaitForChild("Counters")

local counter = counters:WaitForChild("Speed")
local textLabel = counter
local uiGradient = textLabel:WaitForChild("UIGradient")
local uiStroke = textLabel:WaitForChild("UIStroke")
local icon = counter:FindFirstChildWhichIsA("ImageLabel")

local SPEED_DEBUFF_ATTRIBUTE = HudStatsTheme.SpeedDebuffAttribute or "SpeedDebuffActive"
local SLOW_CLEAR_GRACE_SECONDS = 0.18
local SPEED_CHANGE_MIN_ANIMATION_SECONDS = 0.10
local SPEED_CHANGE_MAX_ANIMATION_SECONDS = 0.34
local SPEED_CHANGE_BASE_ANIMATION_SECONDS = 0.08
local SPEED_CHANGE_LOG_SCALE_SECONDS = 0.075
local DISPLAY_SPEED_ATTRIBUTE = MovementSpeedConfig.Attributes.DisplaySpeed

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

local debuffG0 = Color3.fromRGB(179, 112, 255)
local debuffG1 = Color3.fromRGB(236, 198, 255)
local debuffStroke = Color3.fromRGB(64, 24, 104)

local upG0 = Color3.fromRGB(255, 255, 255)
local upG1 = Color3.fromRGB(255, 255, 255)
local upStroke = Color3.fromRGB(0, 0, 0)

local downG0 = Color3.fromRGB(245, 71, 71)
local downG1 = Color3.fromRGB(255, 117, 195)
local downStroke = Color3.fromRGB(61, 20, 20)

local currentG0, currentG1 = normalG0, normalG1
local currentS = normalStroke
local currentHumanoid = nil
local currentCharacter = nil
local characterConnections = {}
local speedDebuffActive = false
local slowClearToken = 0
local pendingEarnedSpeedAnimation = false
local pendingEarnedSpeedAnimationToken = 0

local displayed = 0
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

local function getRestingColors()
	if speedDebuffActive then
		return debuffG0, debuffG1, debuffStroke
	end

	return normalG0, normalG1, normalStroke
end

local function setRestingColors()
	local g0, g1, stroke = getRestingColors()
	setGradient(g0, g1)
	setStroke(stroke)
end

local function formatDisplayNumber(value)
	local numeric = math.max(0, tonumber(value) or 0)
	local roundedInteger = math.floor(numeric + 0.5)
	if math.abs(numeric - roundedInteger) < 0.05 then
		return Shorten.withCommas(roundedInteger)
	end

	local roundedTenth = math.floor((numeric * 10) + 0.5) / 10
	return Shorten.withCommas(roundedTenth)
end

local function formatWholeNumber(value)
	return Shorten.withCommas(math.floor((tonumber(value) or 0) + 0.5))
end

local function speedText(value)
	return formatDisplayNumber(value) .. " Speed"
end

local function pushNotif(delta)
	HudStatNotificationService.pushValueChange({
		kind = "Speed",
		delta = delta,
		valueText = formatWholeNumber(math.abs(delta)),
		labelText = HudStatNotificationService.getLabelFromFormattedText(speedText(0), counter.Name),
		icon = HudStatNotificationService.snapshotIcon(icon),
	})
end

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

local function setDisplayedSpeed(value)
	displayed = math.max(0, tonumber(value) or 0)
	textLabel.Text = speedText(displayed)
end

local function getBaseWalkSpeed()
	local replicatedBase = player:GetAttribute(MovementSpeedConfig.Attributes.BaseWalkSpeed)
	if typeof(replicatedBase) == "number" and replicatedBase >= 0 then
		return replicatedBase
	end

	return math.max(0, tonumber(MovementSpeedConfig.FallbackBaseWalkSpeed) or 16)
end

local function getDisplayedGameSpeedFromWalkSpeed(walkSpeed)
	return math.max(0, (tonumber(walkSpeed) or 0) - getBaseWalkSpeed())
end

local function getReplicatedDisplaySpeed()
	local replicatedDisplaySpeed = player:GetAttribute(DISPLAY_SPEED_ATTRIBUTE)
	if typeof(replicatedDisplaySpeed) == "number" and replicatedDisplaySpeed >= 0 then
		return replicatedDisplaySpeed
	end

	return nil
end

local function getCurrentDisplayedGameSpeed()
	local replicatedDisplaySpeed = getReplicatedDisplaySpeed()
	if replicatedDisplaySpeed ~= nil then
		return replicatedDisplaySpeed
	end

	if currentHumanoid and currentHumanoid.Parent then
		return getDisplayedGameSpeedFromWalkSpeed(currentHumanoid.WalkSpeed)
	end

	return math.max(0, tonumber(earnedSpeedValue.Value) or 0)
end

local function animateBackToResting(id)
	if restoreBlend then
		restoreBlend:Destroy()
		restoreBlend = nil
	end
	restoreBlend = Instance.new("NumberValue")
	restoreBlend.Value = 0

	local fromG0, fromG1 = currentG0, currentG1
	local fromS = currentS
	local targetG0, targetG1, targetS = getRestingColors()

	local c
	c = restoreBlend:GetPropertyChangedSignal("Value"):Connect(function()
		if id ~= animId then
			if c then
				c:Disconnect()
			end
			return
		end
		local a = restoreBlend.Value
		setGradient(fromG0:Lerp(targetG0, a), fromG1:Lerp(targetG1, a))
		setStroke(fromS:Lerp(targetS, a))
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

local function animateSpeed(target)
	animId += 1
	local id = animId

	clearActive()

	homeCounterPos = counter.Position
	homeCounterRot = counter.Rotation
	homeTextRot = textLabel.Rotation
	homeTextScale = textScale.Scale
	homeIconRot = icon and icon.Rotation or 0
	homeIconScale = iconScale and iconScale.Scale or 1

	target = math.max(0, tonumber(target) or 0)
	local start = displayed
	if math.abs(start - target) < 0.05 then
		setDisplayedSpeed(target)
		setRestingColors()
		return
	end

	local isUp = target > start
	local delta = math.abs(target - start)
	local duration = math.clamp(
		SPEED_CHANGE_BASE_ANIMATION_SECONDS + (math.log(delta + 1) / math.log(10)) * SPEED_CHANGE_LOG_SCALE_SECONDS,
		SPEED_CHANGE_MIN_ANIMATION_SECONDS,
		SPEED_CHANGE_MAX_ANIMATION_SECONDS
	)

	local gradStart0, gradStart1 = currentG0, currentG1
	local strokeStart = currentS

	local gradEnd0, gradEnd1, strokeEnd
	if speedDebuffActive then
		gradEnd0, gradEnd1, strokeEnd = getRestingColors()
	elseif isUp then
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
		setDisplayedSpeed(activeNum.Value)
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

		if p >= 1 and connRender then
			connRender:Disconnect()
			connRender = nil
		end
	end)

	connCompleted = activeTween.Completed:Connect(function(state)
		if id ~= animId then
			return
		end
		if state ~= Enum.PlaybackState.Completed then
			return
		end

		setDisplayedSpeed(target)

		if connValueChanged then
			connValueChanged:Disconnect()
			connValueChanged = nil
		end
		if activeNum then
			activeNum:Destroy()
			activeNum = nil
		end
		activeTween = nil

		animateBackToResting(id)
	end)

	activeTween:Play()
end

local function syncDisplayedSpeed(animate)
	local target = getCurrentDisplayedGameSpeed()
	if animate then
		animateSpeed(target)
		return
	end

	clearActive()
	setDisplayedSpeed(target)
	setRestingColors()
end

local function setSpeedDebuffActive(active)
	if speedDebuffActive == active then
		if counter:GetAttribute(SPEED_DEBUFF_ATTRIBUTE) ~= active then
			counter:SetAttribute(SPEED_DEBUFF_ATTRIBUTE, active)
		end
		return
	end

	speedDebuffActive = active
	counter:SetAttribute(SPEED_DEBUFF_ATTRIBUTE, active)
	setRestingColors()
end

local function hasActiveSlowDebuff()
	local effectName = player:GetAttribute(HitEffectConfig.Attributes.Type)
	local speedMultiplier = player:GetAttribute(HitEffectConfig.Attributes.WalkSpeedMultiplier)

	return effectName == "Slow" and typeof(speedMultiplier) == "number" and speedMultiplier < 1
end

local function updateSlowDebuffState()
	if hasActiveSlowDebuff() then
		slowClearToken += 1
		setSpeedDebuffActive(true)
		return
	end

	slowClearToken += 1
	local token = slowClearToken
	task.delay(SLOW_CLEAR_GRACE_SECONDS, function()
		if token ~= slowClearToken then
			return
		end
		if hasActiveSlowDebuff() then
			return
		end
		setSpeedDebuffActive(false)
	end)
end

local function disconnectCharacterConnections()
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	currentCharacter = nil
	currentHumanoid = nil
end

local function bindCharacter(character)
	disconnectCharacterConnections()
	currentCharacter = character

	if not character then
		syncDisplayedSpeed(false)
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		syncDisplayedSpeed(false)
		return
	end

	currentHumanoid = humanoid
	characterConnections[#characterConnections + 1] = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		pendingEarnedSpeedAnimation = false
		if getReplicatedDisplaySpeed() == nil then
			syncDisplayedSpeed(true)
		end
	end)
	characterConnections[#characterConnections + 1] = character.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil or character ~= currentCharacter then
			return
		end
		disconnectCharacterConnections()
		syncDisplayedSpeed(false)
	end)

	syncDisplayedSpeed(false)
end

local function scheduleEarnedSpeedAnimationFallback()
	pendingEarnedSpeedAnimationToken += 1
	local token = pendingEarnedSpeedAnimationToken
	task.delay(0.08, function()
		if token ~= pendingEarnedSpeedAnimationToken or not pendingEarnedSpeedAnimation then
			return
		end

		pendingEarnedSpeedAnimation = false
		syncDisplayedSpeed(true)
	end)
end

setRestingColors()
counter:SetAttribute(SPEED_DEBUFF_ATTRIBUTE, false)
setDisplayedSpeed(getCurrentDisplayedGameSpeed())
updateSlowDebuffState()

player:GetAttributeChangedSignal(HitEffectConfig.Attributes.Type):Connect(function()
	updateSlowDebuffState()
	if getReplicatedDisplaySpeed() == nil then
		syncDisplayedSpeed(true)
	end
end)
player:GetAttributeChangedSignal(HitEffectConfig.Attributes.WalkSpeedMultiplier):Connect(function()
	updateSlowDebuffState()
	if getReplicatedDisplaySpeed() == nil then
		syncDisplayedSpeed(true)
	end
end)
player:GetAttributeChangedSignal(HitEffectConfig.Attributes.Until):Connect(function()
	updateSlowDebuffState()
	if getReplicatedDisplaySpeed() == nil then
		syncDisplayedSpeed(true)
	end
end)
player:GetAttributeChangedSignal(MovementSpeedConfig.Attributes.BaseWalkSpeed):Connect(function()
	if getReplicatedDisplaySpeed() ~= nil then
		return
	end

	syncDisplayedSpeed(true)
end)
player:GetAttributeChangedSignal(DISPLAY_SPEED_ATTRIBUTE):Connect(function()
	pendingEarnedSpeedAnimation = false
	syncDisplayedSpeed(true)
end)

player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
end)
player.CharacterRemoving:Connect(function(character)
	if character ~= currentCharacter then
		return
	end

	disconnectCharacterConnections()
	syncDisplayedSpeed(false)
end)

if player.Character then
	task.defer(bindCharacter, player.Character)
else
	syncDisplayedSpeed(false)
end

local lastEarnedSpeed = earnedSpeedValue.Value
earnedSpeedValue:GetPropertyChangedSignal("Value"):Connect(function()
	local newVal = earnedSpeedValue.Value
	if newVal == lastEarnedSpeed then
		return
	end

	local diff = newVal - lastEarnedSpeed
	lastEarnedSpeed = newVal
	if getReplicatedDisplaySpeed() == nil then
		pendingEarnedSpeedAnimation = true
		scheduleEarnedSpeedAnimationFallback()
	else
		pendingEarnedSpeedAnimation = false
	end
	pushNotif(diff)
end)
