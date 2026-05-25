local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:FindFirstChild("Packages")
if not Packages then
	error("[LoadingScreen] ReplicatedStorage.Packages is not available")
end

local ReactModule = Packages:FindFirstChild("React")
if not ReactModule then
	error("[LoadingScreen] React package is not available")
end

local React = require(ReactModule)
local e = React.createElement

local PROGRESS_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local LOGO_FLOAT_TWEEN = TweenInfo.new(3.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local LOGO_PULSE_TWEEN = TweenInfo.new(2.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local TEXT_FADE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function textConstraint(minSize, maxSize)
	return e("UITextSizeConstraint", {
		MinTextSize = minSize,
		MaxTextSize = maxSize,
	})
end

local function gradient(color, transparency, rotation)
	return e("UIGradient", {
		Color = color,
		Rotation = rotation or 0,
		Transparency = transparency,
	})
end

local function corner(radius)
	return e("UICorner", {
		CornerRadius = UDim.new(0, radius),
	})
end

local function stroke(color, thickness, transparency)
	return e("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
	})
end

local function LoadingScreen(props)
	local progress = math.clamp(tonumber(props.progress) or 0, 0, 1)
	local statusMessage = tostring(props.statusMessage or "Charting the next tide")
	local tip = tostring(props.tip or "Tip: Push deeper for better rewards, but extract before the run turns against you.")
	local backgroundImage = tostring(props.backgroundImage or "")
	local logoImage = tostring(props.logoImage or "")
	local timedOut = props.timedOut == true

	local progressRef = React.useRef(nil)
	local logoRef = React.useRef(nil)
	local logoScaleRef = React.useRef(nil)
	local statusRef = React.useRef(nil)
	local tipRef = React.useRef(nil)

	React.useEffect(function()
		local fill = progressRef.current
		if not fill then
			return nil
		end

		local tween = TweenService:Create(fill, PROGRESS_TWEEN, {
			Size = UDim2.fromScale(progress, 1),
		})
		tween:Play()

		return function()
			tween:Cancel()
		end
	end, { progress })

	React.useEffect(function()
		local logo = logoRef.current
		local scale = logoScaleRef.current
		if not logo or not scale then
			return nil
		end

		local floatTween = TweenService:Create(logo, LOGO_FLOAT_TWEEN, {
			Position = UDim2.new(0.5, 0, 0.35, -10),
		})
		local pulseTween = TweenService:Create(scale, LOGO_PULSE_TWEEN, {
			Scale = 1.035,
		})

		floatTween:Play()
		pulseTween:Play()

		return function()
			floatTween:Cancel()
			pulseTween:Cancel()
		end
	end, {})

	React.useEffect(function()
		for _, label in ipairs({ statusRef.current, tipRef.current }) do
			if label then
				label.TextTransparency = 0.18
				local tween = TweenService:Create(label, TEXT_FADE_TWEEN, {
					TextTransparency = 0,
				})
				tween:Play()
			end
		end
		return nil
	end, { statusMessage, tip })

	return e("Frame", {
		BackgroundColor3 = Color3.fromRGB(10, 9, 13),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100,
	}, {
		Background = e("ImageLabel", {
			BackgroundTransparency = 1,
			Image = backgroundImage,
			ImageColor3 = Color3.fromRGB(255, 238, 218),
			Position = UDim2.fromScale(0, 0),
			ScaleType = Enum.ScaleType.Crop,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 100,
		}),

		WarmBloom = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 178, 72),
			BackgroundTransparency = 0.78,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.62, 0.34),
			Rotation = -8,
			Size = UDim2.fromScale(0.72, 0.58),
			ZIndex = 101,
		}, {
			Corner = corner(36),
			Gradient = gradient(ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 122)),
				ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 133, 54)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(43, 116, 190)),
			}), NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.92),
				NumberSequenceKeypoint.new(0.45, 0.26),
				NumberSequenceKeypoint.new(1, 0.96),
			}), 18),
		}),

		Vignette = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 102,
		}, {
			Gradient = gradient(ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)), NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.34, 0.72),
				NumberSequenceKeypoint.new(0.62, 0.64),
				NumberSequenceKeypoint.new(1, 0.08),
			}), 90),
		}),

		CinematicShade = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(12, 8, 10),
			BackgroundTransparency = 0.42,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 103,
		}, {
			Gradient = gradient(ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 10, 22)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 6, 7)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
			}), NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.42),
				NumberSequenceKeypoint.new(0.52, 0.8),
				NumberSequenceKeypoint.new(1, 0.24),
			}), 90),
		}),

		Logo = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = logoImage,
			Position = UDim2.fromScale(0.5, 0.35),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.72, 0.35),
			ZIndex = 105,
			ref = logoRef,
		}, {
			Scale = e("UIScale", {
				Scale = 1,
				ref = logoScaleRef,
			}),
			SizeConstraint = e("UISizeConstraint", {
				MaxSize = Vector2.new(930, 430),
				MinSize = Vector2.new(260, 130),
			}),
		}),

		Loading = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromScale(0.5, 0.64),
			Size = UDim2.fromScale(0.5, 0.055),
			Text = "Loading...",
			TextColor3 = Color3.fromRGB(248, 246, 238),
			TextScaled = true,
			TextStrokeColor3 = Color3.fromRGB(24, 14, 10),
			TextStrokeTransparency = 0.3,
			TextWrapped = true,
			ZIndex = 106,
		}, {
			Constraint = textConstraint(14, 34),
		}),

		Status = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromScale(0.5, 0.7),
			Size = UDim2.fromScale(0.7, 0.045),
			Text = statusMessage,
			TextColor3 = timedOut and Color3.fromRGB(255, 221, 130) or Color3.fromRGB(255, 214, 95),
			TextScaled = true,
			TextStrokeColor3 = Color3.fromRGB(24, 14, 10),
			TextStrokeTransparency = 0.3,
			TextWrapped = true,
			ZIndex = 106,
			ref = statusRef,
		}, {
			Constraint = textConstraint(12, 24),
		}),

		ProgressBar = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(19, 15, 18),
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.77),
			Size = UDim2.new(0.54, 0, 0, 18),
			ZIndex = 106,
		}, {
			Corner = corner(9),
			Stroke = stroke(Color3.fromRGB(255, 190, 65), 1.6, 0.18),
			SizeConstraint = e("UISizeConstraint", {
				MaxSize = Vector2.new(760, 18),
				MinSize = Vector2.new(260, 12),
			}),
			Fill = e("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 191, 58),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(progress, 1),
				ZIndex = 107,
				ref = progressRef,
			}, {
				Corner = corner(9),
				Gradient = gradient(ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 217, 91)),
					ColorSequenceKeypoint.new(0.56, Color3.fromRGB(255, 174, 47)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(83, 198, 111)),
				}), nil, 0),
			}),
		}),

		Tip = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromScale(0.5, 0.86),
			Size = UDim2.fromScale(0.76, 0.055),
			Text = tip,
			TextColor3 = Color3.fromRGB(250, 245, 230),
			TextScaled = true,
			TextStrokeColor3 = Color3.fromRGB(24, 14, 10),
			TextStrokeTransparency = 0.45,
			TextWrapped = true,
			ZIndex = 106,
			ref = tipRef,
		}, {
			Constraint = textConstraint(12, 22),
		}),
	})
end

return LoadingScreen
