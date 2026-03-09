local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Remote = ReplicatedStorage:WaitForChild("UpdateSetting")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local scrollingFrame = playerGui:WaitForChild("Frames"):WaitForChild("Settings"):WaitForChild("ScrollingFrame")
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Settings"))
local settingsFolder = player:WaitForChild("Settings", 10)

local function clamp(n, a, b)
	if n < a then return a end
	if n > b then return b end
	return n
end

local function clamp01(n)
	return clamp(n, 0, 1)
end

local function getFromPath(path)
	local current = player
	for seg in string.gmatch(path, "[^%.]+") do
		current = current and current:FindFirstChild(seg) or nil
		if not current then
			return nil
		end
	end
	return current
end

local function resolveSettingInstance(path)
	local inst = getFromPath(path)
	if inst then
		return inst
	end
	if string.sub(path, -6) == "Sounds" then
		local alt = string.sub(path, 1, #path - 6) .. "Souynds"
		return getFromPath(alt)
	end
	return nil
end

local BGMUSIC = SoundService:FindFirstChild("BGMUSIC")
local musicBase = {}
local soundsBase = {}
local currentMusicValue = 100
local currentSoundsValue = 100

local uiTickTemplate = SoundService:FindFirstChild("UI_Tick")
local function playSliderTick(value)
	local tmpl = uiTickTemplate
	if not (tmpl and tmpl:IsA("Sound")) then
		tmpl = SoundService:FindFirstChild("UI_Tick")
		if not (tmpl and tmpl:IsA("Sound")) then
			return
		end
		uiTickTemplate = tmpl
	end
	local v = clamp(tonumber(value) or 0, 0, 100)
	local minPitch = 0.75
	local maxPitch = 1.50
	local speed = minPitch + (v / 100) * (maxPitch - minPitch)

	local s = tmpl:Clone()
	s.Name = "UI_Tick_Clone"
	s.Looped = false
	s.PlaybackSpeed = speed
	s.Parent = SoundService
	s.Ended:Connect(function()
		if s then
			s:Destroy()
		end
	end)
	Debris:AddItem(s, 5)
	s:Play()
end

local function isInBGMUSIC(inst)
	return BGMUSIC and inst and inst:IsDescendantOf(BGMUSIC)
end

local function getBaseVolume(sound)
	local attr = sound:GetAttribute("BaseVolume")
	if typeof(attr) == "number" then
		return attr
	end
	sound:SetAttribute("BaseVolume", sound.Volume)
	return sound.Volume
end

local function applyMusicVolume(value)
	value = clamp(math.floor(value + 0.5), 0, 100)
	currentMusicValue = value
	local mul = value / 100
	for sound, base in pairs(musicBase) do
		if sound and sound.Parent and sound:IsA("Sound") and isInBGMUSIC(sound) then
			sound.Volume = base * mul
		end
	end
end

local function applySoundsVolume(value)
	value = clamp(math.floor(value + 0.5), 0, 100)
	currentSoundsValue = value
	local mul = value / 100
	for sound, base in pairs(soundsBase) do
		if sound and sound.Parent and sound:IsA("Sound") and not isInBGMUSIC(sound) then
			sound.Volume = base * mul
		end
	end
end

local function applyAudio(settingName, value)
	if settingName == "Music" then
		applyMusicVolume(value)
	elseif settingName == "Sounds" then
		applySoundsVolume(value)
	end
end

local function trackSound(sound)
	if not sound or not sound:IsA("Sound") then
		return
	end
	local base = getBaseVolume(sound)
	if isInBGMUSIC(sound) then
		if musicBase[sound] == nil then
			musicBase[sound] = base
		end
		sound.Volume = base * (currentMusicValue / 100)
	else
		if soundsBase[sound] == nil then
			soundsBase[sound] = base
		end
		sound.Volume = base * (currentSoundsValue / 100)
	end
end

for _, d in ipairs(SoundService:GetDescendants()) do
	if d:IsA("Sound") then
		trackSound(d)
	end
end

SoundService.DescendantAdded:Connect(function(d)
	if d:IsA("Sound") then
		trackSound(d)
	end
end)

SoundService.DescendantRemoving:Connect(function(d)
	if d:IsA("Sound") then
		musicBase[d] = nil
		soundsBase[d] = nil
	end
end)

do
	local mv = settingsFolder and (settingsFolder:FindFirstChild("Music") or settingsFolder:FindFirstChild("music"))
	if mv and (mv:IsA("NumberValue") or mv:IsA("IntValue")) then
		currentMusicValue = clamp(mv.Value, 0, 100)
	end
	local sv = settingsFolder and (settingsFolder:FindFirstChild("Sounds") or settingsFolder:FindFirstChild("Souynds") or settingsFolder:FindFirstChild("sounds"))
	if sv and (sv:IsA("NumberValue") or sv:IsA("IntValue")) then
		currentSoundsValue = clamp(sv.Value, 0, 100)
	end
	applyMusicVolume(currentMusicValue)
	applySoundsVolume(currentSoundsValue)
end

local MIN_X = 0.1
local MAX_X = 0.84
local RANGE_X = MAX_X - MIN_X

local function valueToX(value)
	value = clamp(value, 0, 100)
	return MAX_X - (value / 100) * RANGE_X
end

local function xToValue(x)
	x = clamp(x, MIN_X, MAX_X)
	return math.floor(((MAX_X - x) / RANGE_X) * 100 + 0.5)
end

local function findGradient(parent)
	if not parent then
		return nil
	end
	return parent:FindFirstChild("UIGradient") or parent:FindFirstChild("UIGradeint") or parent:FindFirstChildWhichIsA("UIGradient", true)
end

local function getGradColors(g)
	if not g then
		return nil, nil
	end
	local kps = g.Color.Keypoints
	if #kps == 0 then
		return Color3.new(1, 1, 1), Color3.new(1, 1, 1)
	end
	return kps[1].Value, kps[#kps].Value
end

local function setGradColors(g, c0, c1)
	if not g or not c0 or not c1 then
		return
	end
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c0),
		ColorSequenceKeypoint.new(1, c1),
	})
end

local H_ORANGE = 30 / 360
local H_RED = 0 / 360

local function toHue(color, hue, satMul, valMul)
	if not color then
		return nil
	end
	local h, s, v = color:ToHSV()
	s = clamp01(s * (satMul or 1))
	v = clamp01(v * (valMul or 1))
	return Color3.fromHSV(hue, s, v)
end

local function buildPalette(anchors)
	local p = {}

	local function gradPack(g0, g1, redValMul)
		local o0 = toHue(g0, H_ORANGE, 1, 1)
		local o1 = toHue(g1, H_ORANGE, 1, 1)
		local r0 = toHue(g0, H_RED, 1, redValMul or 1)
		local r1 = toHue(g1, H_RED, 1, redValMul or 1)
		return { g0 = g0, g1 = g1, o0 = o0, o1 = o1, r0 = r0, r1 = r1 }
	end

	local function colPack(g, redValMul)
		local o = toHue(g, H_ORANGE, 1, 1)
		local r = toHue(g, H_RED, 1, redValMul or 1)
		return { g = g, o = o, r = r }
	end

	p.main = gradPack(anchors.main0, anchors.main1, 1)
	p.bgMain = gradPack(anchors.bgmain0, anchors.bgmain1, 1)
	p.bgFrame = gradPack(anchors.bgframe0, anchors.bgframe1, 1)
	p.bh = gradPack(anchors.bh0, anchors.bh1, 0.75)
	p.stroke = colPack(anchors.stroke, 0.9)
	p.text = {
		g0 = anchors.text0,
		o0 = toHue(anchors.text0, H_ORANGE, 1, 1),
		r0 = toHue(anchors.text0, H_RED, 1, 1),
		white = anchors.text1 or Color3.new(1, 1, 1),
	}

	return p
end

local function computeTargets(palette, value)
	value = clamp(value, 0, 100)
	if value >= 51 then
		local t = (100 - value) / 49
		return {
			mode = "high",
			main0 = palette.main.g0:Lerp(palette.main.o0, t),
			main1 = palette.main.g1:Lerp(palette.main.o1, t),
			bgmain0 = palette.bgMain.g0:Lerp(palette.bgMain.o0, t),
			bgmain1 = palette.bgMain.g1:Lerp(palette.bgMain.o1, t),
			bgframe0 = palette.bgFrame.g0:Lerp(palette.bgFrame.o0, t),
			bgframe1 = palette.bgFrame.g1:Lerp(palette.bgFrame.o1, t),
			bh0 = palette.bh.g0:Lerp(palette.bh.o0, t),
			bh1 = palette.bh.g1:Lerp(palette.bh.o1, t),
			stroke = palette.stroke.g:Lerp(palette.stroke.o, t),
			text0 = palette.text.g0:Lerp(palette.text.o0, t),
			text1 = palette.text.white,
		}
	else
		local t = (51 - value) / 51
		return {
			mode = "low",
			main0 = palette.main.o0:Lerp(palette.main.r0, t),
			main1 = palette.main.o1:Lerp(palette.main.r1, t),
			bgmain0 = palette.bgMain.o0:Lerp(palette.bgMain.r0, t),
			bgmain1 = palette.bgMain.o1:Lerp(palette.bgMain.r1, t),
			bgframe0 = palette.bgFrame.o0,
			bgframe1 = palette.bgFrame.o1,
			bh0 = palette.bh.o0:Lerp(palette.bh.r0, t),
			bh1 = palette.bh.o1:Lerp(palette.bh.r1, t),
			stroke = palette.stroke.o:Lerp(palette.stroke.r, t),
			text0 = palette.text.o0:Lerp(palette.text.r0, t),
			text1 = palette.text.white,
		}
	end
end

local function setupSlider(optionFrame, startValue, settingName, settingPath)
	local sliderFrame = optionFrame:FindFirstChild("Slider", true)
	if not sliderFrame then
		return
	end

	local main = sliderFrame:FindFirstChild("Main", true)
	if not main or not main:IsA("GuiButton") then
		return
	end

	local settingInst = resolveSettingInstance(settingPath)
	if settingInst and (settingInst:IsA("NumberValue") or settingInst:IsA("IntValue")) then
		startValue = settingInst.Value
	end

	local mainFrame = main:FindFirstChild("Frame")
	local g_main = findGradient(mainFrame)

	local bg = mainFrame and mainFrame:FindFirstChild("BG")
	local bgFrame = bg and bg:FindFirstChild("Frame")
	local bgMain = bg and bg:FindFirstChild("Main")
	local g_bg_frame = findGradient(bgFrame)
	local g_bg_main = findGradient(bgMain)

	local bh = mainFrame and (mainFrame:FindFirstChild("BH") or mainFrame:FindFirstChild("Bh") or mainFrame:FindFirstChild("bh"))
	local bhFrame = bh and (bh:FindFirstChild("Frame") or bh:FindFirstChildWhichIsA("Frame", true))
	local g_bh_frame = findGradient(bhFrame)

	local uiStroke = mainFrame and (mainFrame:FindFirstChild("UIStroke") or mainFrame:FindFirstChildWhichIsA("UIStroke", true))

	local textLabel = mainFrame and (mainFrame:FindFirstChild("TextLabel") or mainFrame:FindFirstChild("TextLabel", true))
	local g_text = findGradient(textLabel)
	local textStroke = textLabel and (textLabel:FindFirstChild("UIStroke") or textLabel:FindFirstChildWhichIsA("UIStroke", true))

	local valueLabel = textLabel
	if not valueLabel then
		local f = main:FindFirstChild("Frame")
		if f then
			local inner = f:FindFirstChild("Frame")
			local tl = inner and inner:FindFirstChild("TextLabel")
			if tl then
				valueLabel = tl
			end
		end
	end

	local a_main0, a_main1 = getGradColors(g_main)
	local a_bgmain0, a_bgmain1 = getGradColors(g_bg_main)
	local a_bgframe0, a_bgframe1 = getGradColors(g_bg_frame)
	local a_bh0, a_bh1 = getGradColors(g_bh_frame)
	local a_text0, a_text1 = getGradColors(g_text)
	local a_stroke = (uiStroke and uiStroke:IsA("UIStroke")) and uiStroke.Color or (textStroke and textStroke:IsA("UIStroke") and textStroke.Color) or Color3.new(1, 1, 1)

	local palette = buildPalette({
		main0 = a_main0 or Color3.new(1, 1, 1),
		main1 = a_main1 or Color3.new(1, 1, 1),
		bgmain0 = a_bgmain0 or (a_main0 or Color3.new(1, 1, 1)),
		bgmain1 = a_bgmain1 or (a_main1 or Color3.new(1, 1, 1)),
		bgframe0 = a_bgframe0 or (a_main0 or Color3.new(1, 1, 1)),
		bgframe1 = a_bgframe1 or (a_main1 or Color3.new(1, 1, 1)),
		bh0 = a_bh0 or (a_main0 or Color3.new(1, 1, 1)),
		bh1 = a_bh1 or (a_main1 or Color3.new(1, 1, 1)),
		text0 = a_text0 or Color3.new(1, 1, 1),
		text1 = a_text1 or Color3.new(1, 1, 1),
		stroke = a_stroke,
	})

	local colorTween, colorConn, colorVal

	local function cleanupTween()
		if colorTween then
			colorTween:Cancel()
			colorTween = nil
		end
		if colorConn then
			colorConn:Disconnect()
			colorConn = nil
		end
		if colorVal then
			colorVal:Destroy()
			colorVal = nil
		end
	end

	local function setDirect(targets)
		setGradColors(g_main, targets.main0, targets.main1)
		setGradColors(g_bg_main, targets.bgmain0, targets.bgmain1)
		setGradColors(g_bg_frame, targets.bgframe0, targets.bgframe1)
		setGradColors(g_bh_frame, targets.bh0, targets.bh1)
		setGradColors(g_text, targets.text0, targets.text1)

		if uiStroke and uiStroke:IsA("UIStroke") then
			uiStroke.Color = targets.stroke
		end
		if textStroke and textStroke:IsA("UIStroke") then
			textStroke.Color = targets.stroke
		end
	end

	local function tweenVisuals(targets, duration)
		cleanupTween()

		local grads = {}
		local strokeStart = (uiStroke and uiStroke:IsA("UIStroke")) and uiStroke.Color or nil
		local textStrokeStart = (textStroke and textStroke:IsA("UIStroke")) and textStroke.Color or nil

		local function addGrad(g, t0, t1)
			if not g then
				return
			end
			local s0, s1 = getGradColors(g)
			if not s0 or not s1 then
				return
			end
			grads[#grads + 1] = { g = g, s0 = s0, s1 = s1, t0 = t0, t1 = t1 }
		end

		addGrad(g_main, targets.main0, targets.main1)
		addGrad(g_bg_main, targets.bgmain0, targets.bgmain1)
		addGrad(g_bg_frame, targets.bgframe0, targets.bgframe1)
		addGrad(g_bh_frame, targets.bh0, targets.bh1)
		addGrad(g_text, targets.text0, targets.text1)

		colorVal = Instance.new("NumberValue")
		colorVal.Value = 0

		colorConn = colorVal.Changed:Connect(function(v)
			for _, it in ipairs(grads) do
				setGradColors(it.g, it.s0:Lerp(it.t0, v), it.s1:Lerp(it.t1, v))
			end
			if strokeStart and uiStroke and uiStroke:IsA("UIStroke") then
				uiStroke.Color = strokeStart:Lerp(targets.stroke, v)
			end
			if textStrokeStart and textStroke and textStroke:IsA("UIStroke") then
				textStroke.Color = textStrokeStart:Lerp(targets.stroke, v)
			end
		end)

		colorTween = TweenService:Create(colorVal, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
		colorTween.Completed:Connect(function()
			setDirect(targets)
			cleanupTween()
		end)
		colorTween:Play()
	end

	local function applyValue(v, doTween)
		v = clamp(math.floor(v + 0.5), 0, 100)
		main.Position = UDim2.new(valueToX(v), 0, 0.5, 0)
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = tostring(v)
		end
		applyAudio(settingName, v)

		local targets = computeTargets(palette, v)
		if doTween then
			tweenVisuals(targets, 0.12)
		else
			cleanupTween()
			setDirect(targets)
		end
	end

	local value = clamp(tonumber(startValue) or 0, 0, 100)
	applyValue(value, false)

	local dragging = false

	if settingInst and (settingInst:IsA("NumberValue") or settingInst:IsA("IntValue")) then
		settingInst:GetPropertyChangedSignal("Value"):Connect(function()
			if dragging then
				return
			end
			local v = clamp(settingInst.Value, 0, 100)
			value = v
			applyValue(v, false)
		end)
	end

	local function updateFromMouseX(mouseX)
		local rel = (mouseX - sliderFrame.AbsolutePosition.X) / sliderFrame.AbsoluteSize.X
		local x = clamp(rel, MIN_X, MAX_X)
		local newValue = xToValue(x)
		if newValue == value then
			return
		end
		value = newValue
		applyValue(value, true)
		playSliderTick(value)
	end

	local function finalize()
		if not dragging then
			return
		end
		dragging = false
		applyValue(value, false)
		Remote:FireServer(settingName, settingPath, value)
	end

	main.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromMouseX(input.Position.X)
		end
	end)

	main.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			finalize()
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			updateFromMouseX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			finalize()
		end
	end)
end

local function setupSwitch(optionFrame, startValue, settingName, settingPath)
	local onBtn = optionFrame:FindFirstChild("ON", true)
	local offBtn = optionFrame:FindFirstChild("OFF", true)
	if not onBtn or not offBtn then
		return
	end
	if not onBtn:IsA("GuiButton") or not offBtn:IsA("GuiButton") then
		return
	end

	local settingInst = resolveSettingInstance(settingPath)
	if settingInst and settingInst:IsA("BoolValue") then
		startValue = settingInst.Value
	end

	local state = startValue == true

	local function apply()
		onBtn.Visible = state
		offBtn.Visible = not state
	end

	apply()

	if settingInst and settingInst:IsA("BoolValue") then
		settingInst:GetPropertyChangedSignal("Value"):Connect(function()
			state = settingInst.Value == true
			apply()
		end)
	end

	onBtn.MouseButton1Click:Connect(function()
		state = false
		apply()
		Remote:FireServer(settingName, settingPath, state)
	end)

	offBtn.MouseButton1Click:Connect(function()
		state = true
		apply()
		Remote:FireServer(settingName, settingPath, state)
	end)
end

for settingName, data in pairs(Config) do
	local optionFrame = scrollingFrame:FindFirstChild(settingName)
	if optionFrame and type(data) == "table" then
		if data.Type == "Slider" then
			setupSlider(optionFrame, data.Start, settingName, data.Path)
		elseif data.Type == "Switch" then
			setupSwitch(optionFrame, data.Start, settingName, data.Path)
		end
	end
end
