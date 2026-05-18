local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	Backdrop = Color3.fromRGB(3, 8, 18),
	Panel = Color3.fromRGB(15, 27, 42),
	PanelSoft = Color3.fromRGB(24, 42, 61),
	Gold = Color3.fromRGB(212, 175, 55),
	GoldSoft = Color3.fromRGB(242, 209, 107),
	Text = Color3.fromRGB(240, 236, 226),
	Muted = Color3.fromRGB(186, 195, 208),
	Button = Color3.fromRGB(28, 52, 79),
	ButtonHover = Color3.fromRGB(40, 73, 108),
}

local function responseButton(props)
	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = props.hovered and THEME.ButtonHover or THEME.Button,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 48),
		Text = "",
		[React.Event.Activated] = props.onActivated,
		[React.Event.MouseEnter] = props.onMouseEnter,
		[React.Event.MouseLeave] = props.onMouseLeave,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = THEME.GoldSoft,
			Transparency = props.hovered and 0.08 or 0.24,
			Thickness = 1.2,
		}),
		Number = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.fromOffset(32, 48),
			Text = tostring(props.index),
			TextColor3 = THEME.GoldSoft,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(48, 0),
			Size = UDim2.new(1, -60, 1, 0),
			Text = props.text,
			TextColor3 = THEME.Text,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function NpcDialogScreen(props)
	local hoveredIndex, setHoveredIndex = React.useState(nil)
	local responseChildren = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, response in ipairs(props.responses or {}) do
		responseChildren["Response" .. tostring(index)] = e(responseButton, {
			hovered = hoveredIndex == index,
			index = index,
			layoutOrder = index,
			onActivated = function()
				props.onRespond(index)
			end,
			onMouseEnter = function()
				setHoveredIndex(index)
			end,
			onMouseLeave = function()
				setHoveredIndex(nil)
			end,
			text = tostring(response),
		})
	end

	return e("ScreenGui", {
		DisplayOrder = 175,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Backdrop = e("Frame", {
			BackgroundColor3 = THEME.Backdrop,
			BackgroundTransparency = 0.42,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}),
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = THEME.Panel,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 1, -36),
			Size = UDim2.fromOffset(560, 176 + (#(props.responses or {}) * 58)),
		}, {
			SizeConstraint = e("UISizeConstraint", {
				MaxSize = Vector2.new(560, 420),
				MinSize = Vector2.new(420, 220),
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),
			Stroke = e("UIStroke", {
				Color = THEME.GoldSoft,
				Transparency = 0.08,
				Thickness = 1.6,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.fromOffset(20, 18),
				Size = UDim2.new(1, -40, 0, 28),
				Text = string.upper(props.title or "Dialog"),
				TextColor3 = THEME.GoldSoft,
				TextSize = 22,
				TextStrokeColor3 = THEME.GoldSoft,
				TextStrokeTransparency = 0.5,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Message = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				Position = UDim2.fromOffset(20, 56),
				Size = UDim2.new(1, -40, 0, 44),
				Text = props.message or "",
				TextColor3 = THEME.Muted,
				TextSize = 15,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
			Responses = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(20, 110),
				Size = UDim2.new(1, -40, 1, -130),
			}, responseChildren),
		}),
	})
end

return NpcDialogScreen
