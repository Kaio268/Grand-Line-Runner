local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local M = {}

local DEFAULTS = {
	color = Color3.new(0, 0, 0),
	transparency = 0.25,
	zindex = 1000,
	blockInput = true,

	showDuration = 0.60,
	moveDuration = 0.45,
	style = Enum.EasingStyle.Quad,
	dir = Enum.EasingDirection.Out,

	posMode = "center",
	centerReveal = true,

	arrowMargin = 14,  
	arrowHover = 10,        
	arrowHoverDuration = 1.1,
	arrowZOffset = 2,

	arrowHideDuration = 0.12,
	arrowShowDuration = 0.25,
}

local state = {
	gui = nil,
	top = nil, bottom = nil, left = nil, right = nil,
	activeTweens = {},
	visible = false,

	arrow = nil,
	arrowScale = nil,
	arrowHoverTween = nil,
}

local function copy(tbl)
	local t = {}
	for k, v in pairs(tbl) do
		t[k] = v
	end
	return t
end

local function localPlayer()
	return Players.LocalPlayer or Players.PlayerAdded:Wait()
end

local function ensureGui()
	local pg = localPlayer():WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("PointOnScreen")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "PointOnScreen"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = pg
	end
	state.gui = gui
	return gui
end

local function ensureFrame(parent, name, z, color, transp, active)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.Parent = parent
	end
	f.ZIndex = z
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transp
	f.Active = active
	f.Visible = true
	return f
end

local function ensureMasks(opts)
	local gui = ensureGui()
	state.top = ensureFrame(gui, "MaskTop", opts.zindex, opts.color, opts.transparency, opts.blockInput)
	state.bottom = ensureFrame(gui, "MaskBottom", opts.zindex, opts.color, opts.transparency, opts.blockInput)
	state.left = ensureFrame(gui, "MaskLeft", opts.zindex, opts.color, opts.transparency, opts.blockInput)
	state.right = ensureFrame(gui, "MaskRight", opts.zindex, opts.color, opts.transparency, opts.blockInput)
end

local function ensureArrow(z)
	local gui = ensureGui()
	local arrow = gui:FindFirstChild("arrow") or gui:FindFirstChild("Arrow")
	if not arrow then
		arrow = Instance.new("ImageLabel")
		arrow.Name = "Arrow"
		arrow.BackgroundTransparency = 1
		arrow.Image = "rbxassetid://6031090990"
		arrow.Parent = gui
	end
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.ZIndex = (state.top and state.top.ZIndex or DEFAULTS.zindex) + (z or DEFAULTS.arrowZOffset)

	local scale = arrow:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = arrow
	end
	state.arrow, state.arrowScale = arrow, scale
	return arrow, scale
end

local function toUDim2(v)
	if typeof(v) == "UDim2" then
		return v
	end
	if typeof(v) == "table" then
		if typeof(v[1]) == "table" and typeof(v[2]) == "table" then
			return UDim2.new(v[1][1] or 0, v[1][2] or 0, v[2][1] or 0, v[2][2] or 0)
		else
			return UDim2.new(v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0)
		end
	end
	error("Podaj UDim2 albo {{xS,xO},{yS,yO}} / {xS,xO,yS,yO}.")
end

local function viewport()
	while not workspace.CurrentCamera do
		task.wait()
	end
	local v = workspace.CurrentCamera.ViewportSize
	return v.X, v.Y
end

local function centerToTopLeft(centerPos, size)
	local sw, sh = viewport()

	local cx = centerPos.X.Scale + (centerPos.X.Offset / sw)
	local cy = centerPos.Y.Scale + (centerPos.Y.Offset / sh)
	local w = size.X.Scale + (size.X.Offset / sw)
	local h = size.Y.Scale + (size.Y.Offset / sh)

	local left = cx - w * 0.5
	local top = cy - h * 0.5

	return UDim2.new(left, 0, top, 0)
end

local function layoutFromRect(posTL, size)
	local sw, sh = viewport()

	local left = posTL.X.Scale + (posTL.X.Offset / sw)
	local top = posTL.Y.Scale + (posTL.Y.Offset / sh)
	local width = size.X.Scale + (size.X.Offset / sw)
	local height = size.Y.Scale + (size.Y.Offset / sh)

	local right = left + width
	local bottom = top + height

	return {
		top = {
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(1, 0, top, 0),
		},
		bottom = {
			Position = UDim2.new(0, 0, bottom, 0),
			Size = UDim2.new(1, 0, 1 - bottom, 0),
		},
		left = {
			Position = UDim2.new(0, 0, top, 0),
			Size = UDim2.new(left, 0, height, 0),
		},
		right = {
			Position = UDim2.new(right, 0, top, 0),
			Size = UDim2.new(1 - right, 0, height, 0),
		},
	}
end

local function applyLayout(layout, opts)
	for name, goals in pairs(layout) do
		local f = state[name]
		f.Position = goals.Position
		f.Size = goals.Size
		if opts then
			f.BackgroundColor3 = opts.color
			f.BackgroundTransparency = opts.transparency
			f.ZIndex = opts.zindex
			f.Active = opts.blockInput
			f.Visible = true
		end
	end
end

local function stopMaskTweens()
	for _, t in ipairs(state.activeTweens) do
		if t.PlaybackState == Enum.PlaybackState.Playing then
			t:Cancel()
		end
	end
	state.activeTweens = {}
end

local function tweenLayout(layoutGoals, tweenInfo, includeTransparency, targetTransp)
	local list = {}
	for name, goals in pairs(layoutGoals) do
		local f = state[name]
		local props = { Position = goals.Position, Size = goals.Size }
		if includeTransparency then
			props.BackgroundTransparency = targetTransp
		end
		table.insert(list, TweenService:Create(f, tweenInfo, props))
	end
	state.activeTweens = list
	for _, tw in ipairs(list) do
		tw:Play()
	end
	if list[1] then
		list[1].Completed:Wait()
	end
end

local function rectPixels(posTL, size)
	local sw, sh = viewport()

	local leftScale = posTL.X.Scale + (posTL.X.Offset / sw)
	local topScale = posTL.Y.Scale + (posTL.Y.Offset / sh)
	local widthScale = size.X.Scale + (size.X.Offset / sw)
	local heightScale = size.Y.Scale + (size.Y.Offset / sh)

	local left = leftScale * sw
	local top = topScale * sh
	local width = widthScale * sw
	local height = heightScale * sh

	return sw, sh, left, top, width, height
end

local function bestSide(sw, sh, left, top, width, height)
	local rightW = math.max(0, sw - (left + width))
	local leftW = math.max(0, left)
	local topH = math.max(0, top)
	local botH = math.max(0, sh - (top + height))
	local areas = {
		left = leftW * sh,
		right = rightW * sh,
		top = topH * sw,
		bottom = botH * sw,
	}
	local best, bestA = "right", -1
	for side, a in pairs(areas) do
		if a > bestA then
			best, bestA = side, a
		end
	end
	return best
end

local function showArrowAt(posTL, size, opts)
	ensureArrow(opts.arrowZOffset)

	local sw, sh, l, t, w, h = rectPixels(posTL, size)
	local side = bestSide(sw, sh, l, t, w, h)

	local cx, cy = l + w * 0.5, t + h * 0.5
	local ax, ay, rot, dirX, dirY
	local halfX = math.max(1, state.arrow.AbsoluteSize.X * 0.5)
	local halfY = math.max(1, state.arrow.AbsoluteSize.Y * 0.5)

	if side == "right" then
		ax, ay, rot, dirX, dirY = l + w + opts.arrowMargin + halfX, cy, -90, -1, 0
	elseif side == "left" then
		ax, ay, rot, dirX, dirY = l - (opts.arrowMargin + halfX), cy, 90, 1, 0
	elseif side == "top" then
		ax, ay, rot, dirX, dirY = cx, t - (opts.arrowMargin + halfY), 180, 0, 1
	else
		ax, ay, rot, dirX, dirY = cx, t + h + opts.arrowMargin + halfY, 0, 0, -1
	end

	if state.arrowHoverTween then
		state.arrowHoverTween:Cancel()
		state.arrowHoverTween = nil
	end

	local axScale = ax / sw
	local ayScale = ay / sh

	state.arrow.Position = UDim2.new(axScale, 0, ayScale, 0)
	state.arrow.Rotation = rot
	state.arrow.Visible = true

	state.arrowScale.Scale = 0
	TweenService:Create(
		state.arrowScale,
		TweenInfo.new(DEFAULTS.arrowShowDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	local p1ScaleX = (ax + dirX * opts.arrowHover) / sw
	local p1ScaleY = (ay + dirY * opts.arrowHover) / sh
	local p2ScaleX = (ax - dirX * opts.arrowHover) / sw
	local p2ScaleY = (ay - dirY * opts.arrowHover) / sh

	local p1 = UDim2.new(p1ScaleX, 0, p1ScaleY, 0)
	local p2 = UDim2.new(p2ScaleX, 0, p2ScaleY, 0)

	state.arrow.Position = p1
	state.arrowHoverTween = TweenService:Create(
		state.arrow,
		TweenInfo.new(opts.arrowHoverDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = p2 }
	)
	state.arrowHoverTween:Play()
end

local function placeArrowAt(posTL, size, opts)
	ensureArrow(opts.arrowZOffset)

	local sw, sh, l, t, w, h = rectPixels(posTL, size)
	local side = bestSide(sw, sh, l, t, w, h)

	local cx, cy = l + w * 0.5, t + h * 0.5
	local ax, ay, rot
	local halfX = math.max(1, state.arrow.AbsoluteSize.X * 0.5)
	local halfY = math.max(1, state.arrow.AbsoluteSize.Y * 0.5)

	if side == "right" then
		ax, ay, rot = l + w + opts.arrowMargin + halfX, cy, -90
	elseif side == "left" then
		ax, ay, rot = l - (opts.arrowMargin + halfX), cy, 90
	elseif side == "top" then
		ax, ay, rot = cx, t - (opts.arrowMargin + halfY), 180
	else
		ax, ay, rot = cx, t + h + opts.arrowMargin + halfY, 0
	end

	if state.arrowHoverTween then
		state.arrowHoverTween:Cancel()
		state.arrowHoverTween = nil
	end

	state.arrow.Position = UDim2.new(ax / sw, 0, ay / sh, 0)
	state.arrow.Rotation = rot
	state.arrow.Visible = true

	if state.arrowScale then
		state.arrowScale.Scale = 1
	end
end

local function hideArrowQuick()
	if not state.arrow or not state.arrowScale then
		return
	end
	if state.arrowHoverTween then
		state.arrowHoverTween:Cancel()
		state.arrowHoverTween = nil
	end
	local tw = TweenService:Create(
		state.arrowScale,
		TweenInfo.new(DEFAULTS.arrowHideDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	tw:Play()
	tw.Completed:Wait()
	state.arrow.Visible = false
end

function M.Set(sizeArg, positionArg, options)
	local opts = copy(DEFAULTS)
	options = options or {}
	for k, v in pairs(options) do
		opts[k] = v
	end

	local size = toUDim2(sizeArg)
	local posIn = toUDim2(positionArg)
	local posTL = (opts.posMode == "center") and centerToTopLeft(posIn, size) or posIn

	ensureMasks(opts)
	ensureArrow(opts.arrowZOffset)

	stopMaskTweens()

	local firstShow = not state.visible
	local duration = options.duration or (firstShow and opts.showDuration or opts.moveDuration)
	local tInfo = TweenInfo.new(duration, opts.style, opts.dir)

	if not firstShow then
		hideArrowQuick()
	end

	if firstShow then
		for _, f in ipairs({ state.top, state.bottom, state.left, state.right }) do
			f.BackgroundTransparency = 0
			f.Active = opts.blockInput
			f.Visible = true
		end

		local startPos, startSize
		if opts.centerReveal then
			startPos, startSize = UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0, 0, 0, 0)
		else
			startPos, startSize = posTL, UDim2.new(0, 0, 0, 0)
		end

		applyLayout(layoutFromRect(startPos, startSize), {
			color = opts.color,
			transparency = 0,
			zindex = opts.zindex,
			blockInput = opts.blockInput,
		})
		tweenLayout(layoutFromRect(posTL, size), tInfo, true, opts.transparency)

		state.visible = true
	else
		tweenLayout(layoutFromRect(posTL, size), tInfo, false, nil)
	end

	showArrowAt(posTL, size, opts)

	for _, f in ipairs({ state.top, state.bottom, state.left, state.right }) do
		f.BackgroundColor3 = opts.color
		f.ZIndex = opts.zindex
	end
end

function M.Update(sizeArg, positionArg, options)
	local opts = copy(DEFAULTS)
	options = options or {}
	for k, v in pairs(options) do
		opts[k] = v
	end

	local size = toUDim2(sizeArg)
	local posIn = toUDim2(positionArg)
	local posTL = (opts.posMode == "center") and centerToTopLeft(posIn, size) or posIn

	ensureMasks(opts)
	stopMaskTweens()

	applyLayout(layoutFromRect(posTL, size), {
		color = opts.color,
		transparency = opts.transparency,
		zindex = opts.zindex,
		blockInput = opts.blockInput,
	})

	if opts.hideArrow then
		if state.arrowHoverTween then
			state.arrowHoverTween:Cancel()
			state.arrowHoverTween = nil
		end
		if state.arrow then
			state.arrow.Visible = false
		end
	else
		placeArrowAt(posTL, size, opts)
	end

	for _, f in ipairs({ state.top, state.bottom, state.left, state.right }) do
		f.BackgroundColor3 = opts.color
		f.ZIndex = opts.zindex
		f.Visible = true
	end

	state.visible = true
end

function M.Hide(options)
	if not state.top then
		return
	end
	local opts = options or {}
	local t = TweenInfo.new(
		opts.duration or 0.25,
		opts.style or Enum.EasingStyle.Quad,
		opts.dir or Enum.EasingDirection.In
	)

	if state.arrowHoverTween then
		state.arrowHoverTween:Cancel()
		state.arrowHoverTween = nil
	end
	if state.arrow and state.arrowScale then
		local atw = TweenService:Create(state.arrowScale, TweenInfo.new(0.15), { Scale = 0 })
		atw:Play()
		atw.Completed:Connect(function()
			if state.arrow then
				state.arrow.Visible = false
			end
		end)
	end

	for _, f in ipairs({ state.top, state.bottom, state.left, state.right }) do
		if f then
			local tw = TweenService:Create(f, t, { BackgroundTransparency = 1 })
			tw.Completed:Connect(function()
				if f and f.Parent then
					f.Active = false
					f.Visible = false
				end
			end)
			tw:Play()
		end
	end

	state.visible = false
end

function M.Clear()
	if state.arrowHoverTween then
		state.arrowHoverTween:Cancel()
		state.arrowHoverTween = nil
	end
	local gui = ensureGui()
	for _, name in ipairs({ "MaskTop", "MaskBottom", "MaskLeft", "MaskRight" }) do
		local f = gui:FindFirstChild(name)
		if f then
			f:Destroy()
		end
	end
	if state.arrow then
		state.arrow.Visible = false
	end
	state.top, state.bottom, state.left, state.right = nil, nil, nil, nil
	state.visible = false
end

return M
