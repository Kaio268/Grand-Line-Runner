local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement
local SEGMENT_GAP_PX = 0
local AVATAR_MARKER_SIZE = 30
local WAVE_MARKER_SIZE = 18

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
		size = props.size or AVATAR_MARKER_SIZE,
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
		size = props.size or WAVE_MARKER_SIZE,
		zIndex = 9,
		children = {
			Icon = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(20, 24, 34),
				BackgroundTransparency = 0.05,
				BorderSizePixel = 0,
				Image = "",
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				ZIndex = 9,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(255, 196, 150),
					Transparency = 0.25,
					Thickness = 1.2,
				}),
				Image = e("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Image = props.image or "",
					ImageColor3 = Color3.new(1, 1, 1),
					Position = UDim2.fromScale(0.5, 0.5),
					ScaleType = Enum.ScaleType.Fit,
					Size = UDim2.fromScale(0.72, 0.72),
					ZIndex = 10,
				}),
			}),
		},
	})
end

local function segmentRow(props)
	local sections = getSections(props)
	local compact = props.compact == true
	local children = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, SEGMENT_GAP_PX),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local count = #sections
	local radius = compact and 9 or 13

	for index, section in ipairs(sections) do
		local color = section.color
			or if section.isImpact
				then Color3.fromRGB(170, 58, 56)
				else SEGMENT_COLORS[((index - 1) % #SEGMENT_COLORS) + 1]
		local widthScale = section.widthScale or (1 / count)
		local isFirst = index == 1
		local isLast = index == count
		local light = color:Lerp(Color3.new(1, 1, 1), 0.5)
		local deep = color:Lerp(Color3.new(0, 0, 0), 0.42)

		local segmentChildren = {
			-- diagonal multi-stop sheen: bright tint -> biome color -> deep shade
			Sheen = e("UIGradient", {
				Rotation = 35,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, light),
					ColorSequenceKeypoint.new(0.5, color),
					ColorSequenceKeypoint.new(1, deep),
				}),
			}),
			-- glassy top highlight
			Gloss = e("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0.5, 0),
				ZIndex = 6,
			}, {
				Fade = e("UIGradient", {
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.5),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			}),
			-- bottom depth shade
			Shade = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0.46, 0),
				ZIndex = 6,
			}, {
				Fade = e("UIGradient", {
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(1, 0.62),
					}),
				}),
			}),
			Label = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -10, 1, 0),
				Text = section.label or ("Biome " .. tostring(index)),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextSize = compact and 7 or 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextStrokeColor3 = Color3.fromRGB(8, 10, 16),
				TextStrokeTransparency = 0.3,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 7,
			}),
		}

		-- Round only the outer ends so the segments read as one continuous bar.
		if isFirst or isLast then
			segmentChildren.Corner = e("UICorner", {
				CornerRadius = UDim.new(0, radius),
			})
		end

		children["Segment" .. tostring(index)] = e("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			LayoutOrder = index,
			Size = UDim2.new(widthScale, 0, 1, 0),
			ZIndex = 6,
		}, segmentChildren)
	end

	-- Angled, beveled dividers overlaid at the section boundaries for a faceted look.
	local cumulative = 0
	for index = 1, count - 1 do
		cumulative += sections[index].widthScale or (1 / count)
		children["Divider" .. tostring(index)] = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(10, 13, 21),
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(cumulative, 0.5),
			Rotation = 14,
			Size = UDim2.new(0, compact and 2 or 3, 1.5, 0),
			ZIndex = 7,
		}, {
			Edge = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 66, 88)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 13, 21)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 66, 88)),
				}),
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	}, children)
end

local function WaveProgressBar(props)
	local compact = props.compact == true
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
			Position = UDim2.new(0.5, 0, 0, compact and 8 or 16),
			Size = UDim2.fromOffset(compact and 390 or 920, compact and 36 or 70),
			ZIndex = 5,
		}, {
			Constraint = e("UISizeConstraint", {
				MaxSize = compact and Vector2.new(430, 36) or Vector2.new(1040, 70),
				MinSize = compact and Vector2.new(280, 32) or Vector2.new(560, 64),
			}),
			IconBacking = compact and e("Frame", {
				BackgroundColor3 = Color3.fromRGB(8, 12, 20),
				BackgroundTransparency = 0.38,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 2),
				Size = UDim2.new(1, 0, 0, 32),
				ZIndex = 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 14),
				}),
			}) or nil,
			Backdrop = e("Frame", {
				BackgroundColor3 = Color3.fromRGB(11, 15, 24),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, compact and 7 or 16),
				Size = UDim2.new(1, 0, 0, compact and 20 or 40),
				ZIndex = 5,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 14),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(150, 170, 205),
					Transparency = 0.5,
					Thickness = 1.1,
				}),
				Segments = segmentRow(props),
			}),
			Waves = e("Folder", nil, waveMarkers),
			Players = e("Folder", nil, playerMarkers),
		}),
	})
end

return WaveProgressBar
