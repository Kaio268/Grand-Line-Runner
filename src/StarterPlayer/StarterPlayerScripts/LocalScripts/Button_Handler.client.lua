local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local spr
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage.Modules:WaitForChild("spr"))
	end)
	if ok then
		spr = mod
	else
		spr = require(script:WaitForChild("spr"))
	end
end

local HOVER_MULT = 1.095
local PRESS_MULT = 0.885

local SCALE_D_HOVER = 0.36
local SCALE_F_HOVER = 8.8

local SCALE_D_PRESS = 0.58
local SCALE_F_PRESS = 12.0

local SCALE_D_RELEASE = 0.30
local SCALE_F_RELEASE = 9.2

local ROT_D_IN = 0.34
local ROT_F_IN = 7.6

local ROT_D_OUT = 0.30
local ROT_F_OUT = 7.2

local THICK_D = 0.40
local THICK_F = 9.0

local COLOR_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local WHITE = Color3.fromRGB(255, 255, 255)

local function isNearBlack(c: Color3)
	return c.R <= 0.02 and c.G <= 0.02 and c.B <= 0.02
end

local function hasNoAnimTag(inst: Instance)
	return CollectionService:HasTag(inst, "NoAnim")
end

local function getUIScale(btn: GuiButton)
	local s = btn:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Scale = 1
		s.Parent = btn
	end
	return s
end

local function pickIcon(btn: Instance)
	local icon = btn:FindFirstChild("IconAnimate", true)
	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		return icon
	end
	return nil
end

local function pickStroke(btn: Instance)
	local s = btn:FindFirstChild("UIStroke")
	if s and s:IsA("UIStroke") then
		return s
	end
	return btn:FindFirstChildOfClass("UIStroke")
end

local bound = setmetatable({}, { __mode = "k" })
local state = setmetatable({}, { __mode = "k" })
local pressed = setmetatable({}, { __mode = "k" })

local function cancelTween(tw)
	if tw then
		pcall(function()
			tw:Cancel()
		end)
	end
end

local function tweenProps(inst: Instance, props)
	local tw = TweenService:Create(inst, COLOR_TWEEN, props)
	tw:Play()
	return tw
end

local function refreshRefs(btn: GuiButton)
	local st = state[btn]
	if not st then
		return
	end

	if not st.uiScale or st.uiScale.Parent == nil then
		st.uiScale = btn:FindFirstChildOfClass("UIScale")
	end

	if not st.icon or st.icon.Parent == nil then
		st.icon = pickIcon(btn)
	end

	local stroke = pickStroke(btn)
	if stroke ~= st.stroke then
		st.stroke = stroke
		if stroke then
			st.strokeOrig = stroke.Color
			st.strokeWasBlack = isNearBlack(st.strokeOrig)
			st.thickOrig = stroke.Thickness
		else
			st.strokeOrig = nil
			st.strokeWasBlack = false
			st.thickOrig = nil
		end
	end
end

local function setScale(btn: GuiButton, target: number, d: number, f: number)
	local s = getUIScale(btn)
	spr.target(s, d, f, { Scale = target })
end

local function setRotation(icon: Instance, target: number, d: number, f: number)
	spr.target(icon, d, f, { Rotation = target })
end

local function setThickness(stroke: UIStroke, target: number)
	spr.target(stroke, THICK_D, THICK_F, { Thickness = target })
end

local function applyVisual(btn: GuiButton)
	if hasNoAnimTag(btn) then
		return
	end

	local st = state[btn]
	if not st then
		return
	end

	refreshRefs(btn)

	if not st.restScale then
		local s = btn:FindFirstChildOfClass("UIScale")
		st.restScale = s and s.Scale or 1
	end

	local targetScale
	if st.down then
		targetScale = st.restScale * PRESS_MULT
	elseif st.hover then
		targetScale = st.restScale * HOVER_MULT
	else
		targetScale = st.restScale
	end

	local d, f
	if st.down then
		d, f = SCALE_D_PRESS, SCALE_F_PRESS
	elseif st.hover then
		d, f = SCALE_D_HOVER, SCALE_F_HOVER
	else
		d, f = SCALE_D_RELEASE, SCALE_F_RELEASE
	end

	setScale(btn, targetScale, d, f)

	if st.bgWasBlack then
		cancelTween(st.bgTween)
		if st.hover then
			st.bgTween = tweenProps(btn, { BackgroundColor3 = WHITE })
		else
			st.bgTween = tweenProps(btn, { BackgroundColor3 = st.bgOrig })
		end
	end

	if st.stroke and st.strokeWasBlack then
		cancelTween(st.strokeTween)
		if st.hover then
			st.strokeTween = tweenProps(st.stroke, { Color = WHITE })
		else
			st.strokeTween = tweenProps(st.stroke, { Color = st.strokeOrig })
		end

		if st.thickOrig then
			if st.hover then
				setThickness(st.stroke, st.thickOrig + 0.65)
			else
				setThickness(st.stroke, st.thickOrig)
			end
		end
	end

	if st.icon then
		if st.hover then
			local sign = (math.random(0, 1) == 0) and -1 or 1
			local mag = math.random(3, 6)
			setRotation(st.icon, mag * sign, ROT_D_IN, ROT_F_IN)
		else
			setRotation(st.icon, 0, ROT_D_OUT, ROT_F_OUT)
		end
	end
end

local function onEnter(btn: GuiButton)
	if hasNoAnimTag(btn) then
		return
	end
	local st = state[btn]
	if not st then
		return
	end
	st.hover = true
	applyVisual(btn)
end

local function onLeave(btn: GuiButton)
	if hasNoAnimTag(btn) then
		return
	end
	local st = state[btn]
	if not st then
		return
	end
	st.hover = false
	applyVisual(btn)
end

local function onDown(btn: GuiButton)
	if hasNoAnimTag(btn) then
		return
	end
	local st = state[btn]
	if not st then
		return
	end
	st.down = true
	pressed[btn] = true
	applyVisual(btn)
end

local function onUp(btn: GuiButton)
	if hasNoAnimTag(btn) then
		return
	end
	local st = state[btn]
	if not st then
		return
	end
	st.down = false
	pressed[btn] = nil
	applyVisual(btn)
end

local function unbindButton(btn: GuiButton)
	local st = state[btn]
	if not st then
		bound[btn] = nil
		pressed[btn] = nil
		return
	end

	cancelTween(st.bgTween)
	cancelTween(st.strokeTween)

	if st.conns then
		for _, c in ipairs(st.conns) do
			pcall(function()
				c:Disconnect()
			end)
		end
	end

	state[btn] = nil
	bound[btn] = nil
	pressed[btn] = nil
end

local function bindButton(inst: Instance)
	if not inst:IsA("GuiButton") then
		return
	end
	if bound[inst] then
		return
	end
	if hasNoAnimTag(inst) then
		return
	end

	bound[inst] = true

	local bgOrig = inst.BackgroundColor3

	state[inst] = {
		hover = false,
		down = false,

		uiScale = inst:FindFirstChildOfClass("UIScale"),
		restScale = nil,

		bgOrig = bgOrig,
		bgWasBlack = isNearBlack(bgOrig),
		bgTween = nil,

		stroke = nil,
		strokeOrig = nil,
		strokeWasBlack = false,
		thickOrig = nil,
		strokeTween = nil,

		icon = nil,

		conns = {},
	}

	refreshRefs(inst)

	local st = state[inst]

	table.insert(st.conns, inst.MouseEnter:Connect(function()
		onEnter(inst)
	end))

	table.insert(st.conns, inst.MouseLeave:Connect(function()
		onLeave(inst)
	end))

	table.insert(st.conns, inst.MouseButton1Down:Connect(function()
		onDown(inst)
	end))

	table.insert(st.conns, inst.MouseButton1Up:Connect(function()
		onUp(inst)
	end))

	table.insert(st.conns, inst.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			onDown(inst)
		end
	end))

	table.insert(st.conns, inst.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			onUp(inst)
		end
	end))

	table.insert(st.conns, inst.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unbindButton(inst)
		end
	end))
end

for _, inst in ipairs(playerGui:GetDescendants()) do
	bindButton(inst)
end

playerGui.DescendantAdded:Connect(function(inst)
	bindButton(inst)
end)

CollectionService:GetInstanceAddedSignal("NoAnim"):Connect(function(inst)
	if inst:IsA("GuiButton") then
		unbindButton(inst)
	end
end)

CollectionService:GetInstanceRemovedSignal("NoAnim"):Connect(function(inst)
	bindButton(inst)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	for btn in pairs(pressed) do
		if state[btn] then
			onUp(btn)
		else
			pressed[btn] = nil
		end
	end
end)
