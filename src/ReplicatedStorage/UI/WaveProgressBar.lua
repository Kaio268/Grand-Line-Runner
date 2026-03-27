local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement
local SEGMENT_GAP_PX = 4

local SEGMENT_COLORS = {
	Color3.fromRGB(56, 67, 98),
	Color3.fromRGB(64, 79, 113),
	Color3.fromRGB(72, 90, 124),
	Color3.fromRGB(81, 101, 136),
	Color3.fromRGB(90, 112, 148),
	Color3.fromRGB(101, 125, 164),
	Color3.fromRGB(112, 141, 182),
	Color3.fromRGB(125, 160, 202),
}

local function getSections(props)
	local sections = props.sections or {}
	if #sections > 0 then
		return sections
	end

	local fallback = {}
	for index = 1, #SEGMENT_COLORS do
		fallback[index] = {
			label = "Biome " .. tostring(index),
			index = index,
		}
	end
	return fallback
end

local function marker(props)
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(props.alpha, props.yScale or 0.5),
		Size = UDim2.fromOffset(props.size or 28, props.size or 28),
		ZIndex = props.zIndex or 6,
	}, props.children)
end

local function avatarMarker(props)
	local userId = props.userId
	local image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
	local dead = props.isDead == true

	return marker({
		alpha = props.alpha,
		yScale = 0.5,
		size = 24,
		zIndex = 8,
		children = {
				Backdrop = e("Frame", {
					BackgroundColor3 = dead and Color3.fromRGB(72, 41, 49) or Color3.fromRGB(21, 27, 41),
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 8,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Stroke = e("UIStroke", {
					Color = dead and Color3.fromRGB(255, 128, 128) or Color3.fromRGB(223, 236, 255),
					Transparency = 0.08,
					Thickness = 1.5,
				}),
				Image = e("ImageLabel", {
					BackgroundTransparency = 1,
					Image = image,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 8,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
				}),
				Skull = dead and e("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBlack,
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1, 1),
					Text = "X",
					TextColor3 = Color3.fromRGB(255, 244, 244),
					TextSize = 18,
					TextStrokeColor3 = Color3.fromRGB(62, 18, 18),
					TextStrokeTransparency = 0.2,
					ZIndex = 9,
				}) or nil,
			}),
		},
	})
end

local function waveMarker(props)
	return marker({
		alpha = props.alpha,
		yScale = 0.5,
		size = 24,
		zIndex = 9,
		children = {
			Icon = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(22, 25, 36),
				BackgroundTransparency = 0.04,
				BorderSizePixel = 0,
				Image = props.image or "",
				ImageColor3 = Color3.new(1, 1, 1),
				Position = UDim2.fromScale(0.5, 0.5),
				Rotation = 45,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 9,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 7),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(255, 183, 132),
					Transparency = 0.1,
					Thickness = 1.4,
				}),
				ImageRotationFix = e("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Image = props.image or "",
					ImageColor3 = Color3.new(1, 1, 1),
					Position = UDim2.fromScale(0.5, 0.5),
					Rotation = -45,
					ScaleType = Enum.ScaleType.Fit,
					Size = UDim2.fromScale(0.68, 0.68),
					ZIndex = 10,
				}),
			}),
		},
	})
end

local function segmentRow(props)
	local sections = getSections(props)
	local children = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, SEGMENT_GAP_PX),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, section in ipairs(sections) do
		local color = if section.isImpact
			then Color3.fromRGB(104, 56, 54)
			else SEGMENT_COLORS[((index - 1) % #SEGMENT_COLORS) + 1]
		local widthScale = section.widthScale or (1 / #sections)
		children["Segment" .. tostring(index)] = e("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(widthScale, -SEGMENT_GAP_PX, 1, 0),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.06)),
					ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.22)),
				}),
			}),
			Stroke = e("UIStroke", {
				Color = if section.isImpact
					then Color3.fromRGB(255, 189, 168)
					else color:Lerp(Color3.new(1, 1, 1), 0.2),
				Transparency = if section.isImpact then 0.15 else 0.3,
				Thickness = if section.isImpact then 1.6 else 1,
			}),
			Label = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamMedium,
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.new(1, -6, 0, 14),
				Text = section.label or ("Biome " .. tostring(index)),
				TextColor3 = if section.isImpact
					then Color3.fromRGB(255, 228, 214)
					else Color3.fromRGB(233, 241, 255),
				TextSize = 10,
				TextTransparency = if section.isImpact then 0.05 else 0.16,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				ZIndex = 6,
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, children)
end

local function WaveProgressBar(props)
	local playerMarkers = {}
	for index, markerProps in ipairs(props.players or {}) do
		playerMarkers["Player" .. tostring(index)] = e(avatarMarker, markerProps)
	end

	local waveMarkers = {}
	for index, markerProps in ipairs(props.waves or {}) do
		waveMarkers["Wave" .. tostring(index)] = e(waveMarker, markerProps)
	end

	return e("ScreenGui", {
		DisplayOrder = props.displayOrder or 18,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
	}, {
		Root = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, 18),
			Size = UDim2.fromOffset(820, 80),
			ZIndex = 5,
		}, {
			Constraint = e("UISizeConstraint", {
				MaxSize = Vector2.new(940, 80),
				MinSize = Vector2.new(500, 72),
			}),
			Backdrop = e("Frame", {
				BackgroundColor3 = Color3.fromRGB(11, 15, 24),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 16),
				Size = UDim2.new(1, 0, 0, 40),
				ZIndex = 5,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 14),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(109, 131, 171),
					Transparency = 0.18,
					Thickness = 1.4,
				}),
				Segments = segmentRow(props),
			}),
			Waves = e("Folder", nil, waveMarkers),
			Players = e("Folder", nil, playerMarkers),
		}),
	})
end

return WaveProgressBar
