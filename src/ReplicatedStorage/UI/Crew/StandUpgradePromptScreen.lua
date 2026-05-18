local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	Backdrop = Color3.fromRGB(7, 14, 25),
	Panel = Color3.fromRGB(18, 27, 40),
	PanelSoft = Color3.fromRGB(28, 42, 61),
	Gold = Color3.fromRGB(212, 175, 55),
	GoldSoft = Color3.fromRGB(242, 209, 107),
	Text = Color3.fromRGB(241, 237, 226),
	Muted = Color3.fromRGB(187, 196, 211),
	Confirm = Color3.fromRGB(212, 175, 55),
	ConfirmHover = Color3.fromRGB(242, 209, 107),
	Cancel = Color3.fromRGB(28, 42, 61),
	CancelHover = Color3.fromRGB(45, 64, 88),
}

local function promptButton(props)
	local hovered, setHovered = React.useState(false)

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = if hovered then props.hoverColor3 else props.color3,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(0.5, -10, 0, 44),
		Text = props.text,
		TextColor3 = props.textColor3,
		TextSize = 18,
		[React.Event.Activated] = props.onActivated,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldSoft,
			Transparency = 0.12,
			Thickness = 1.2,
		}),
	})
end

local function StandUpgradePromptScreen(props)
	if props.visible ~= true then
		return e(React.Fragment)
	end

	return e("ScreenGui", {
		DisplayOrder = 140,
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
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = THEME.Panel,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(460, 250),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldSoft,
				Transparency = 0.1,
				Thickness = 1.5,
			}),
			Padding = e("UIPadding", {
				PaddingBottom = UDim.new(0, 18),
				PaddingLeft = UDim.new(0, 18),
				PaddingRight = UDim.new(0, 18),
				PaddingTop = UDim.new(0, 16),
			}),
			Accent = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Size = UDim2.new(1, 0, 0, 18),
				Text = "CREWMATE UPGRADE",
				TextColor3 = THEME.GoldSoft,
				TextSize = 14,
				TextStrokeColor3 = THEME.GoldSoft,
				TextStrokeTransparency = 0.6,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(0, 24),
				Size = UDim2.new(1, 0, 0, 30),
				Text = props.title,
				TextColor3 = THEME.Text,
				TextSize = 24,
				TextStrokeColor3 = THEME.GoldSoft,
				TextStrokeTransparency = 0.64,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			BodyCard = e("Frame", {
				BackgroundColor3 = THEME.PanelSoft,
				BackgroundTransparency = 0.14,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 64),
				Size = UDim2.new(1, 0, 0, 108),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = e("UIStroke", {
					Color = THEME.Gold,
					Transparency = 0.42,
					Thickness = 1,
				}),
				Body = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Position = UDim2.fromOffset(12, 10),
					Size = UDim2.new(1, -24, 1, -20),
					Text = props.body,
					TextColor3 = THEME.Muted,
					TextSize = 18,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
			}),
			Buttons = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.new(1, 0, 0, 44),
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 20),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Confirm = e(promptButton, {
					color3 = THEME.Confirm,
					hoverColor3 = THEME.ConfirmHover,
					layoutOrder = 1,
					onActivated = props.onConfirm,
					text = props.confirmText,
					textColor3 = THEME.Backdrop,
				}),
				Cancel = e(promptButton, {
					color3 = THEME.Cancel,
					hoverColor3 = THEME.CancelHover,
					layoutOrder = 2,
					onActivated = props.onCancel,
					text = "Cancel",
					textColor3 = THEME.Text,
				}),
			}),
		}),
	})
end

return StandUpgradePromptScreen
