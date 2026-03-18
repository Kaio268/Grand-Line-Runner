local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function RedeemCodesPanel(props)
	local codeText, setCodeText = React.useState("")

	local function submitCode()
		if props.onRedeemRequested then
			props.onRedeemRequested(codeText)
		end
	end

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, 182),
		ZIndex = props.zIndex,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 24),
		}),
		Stroke = e("UIStroke", {
			Color = Color3.fromRGB(90, 124, 184),
			Transparency = 0.08,
			Thickness = 1.25,
		}),
		Gradient = e("UIGradient", {
			Rotation = 120,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.BoardSoft),
				ColorSequenceKeypoint.new(1, Theme.Palette.Panel),
			}),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 24),
			PaddingRight = UDim.new(0, 24),
			PaddingTop = UDim.new(0, 22),
			PaddingBottom = UDim.new(0, 22),
		}),
		Eyebrow = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0, 14),
			Text = props.eyebrow or "Redeem",
			TextColor3 = Theme.Palette.Cyan,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 34),
			Text = props.title or "Redeem Codes",
			TextColor3 = Theme.Palette.Text,
			TextSize = 30,
			TextStrokeTransparency = 0.68,
			TextStrokeColor3 = Theme.Palette.Shadow,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(0, 58),
			Size = UDim2.new(1, 0, 0, 34),
			Text = props.description or "",
			TextColor3 = Theme.Palette.Muted,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}),
		Input = e("TextBox", {
			BackgroundColor3 = Theme.Palette.Ink,
			BackgroundTransparency = 0.14,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = Theme.Fonts.Body,
			PlaceholderText = props.placeholder or "Enter code",
			Position = UDim2.new(0, 0, 1, -62),
			Size = UDim2.new(0.68, -8, 0, 48),
			Text = codeText,
			TextColor3 = Theme.Palette.Text,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
			[React.Change.Text] = function(rbx)
				setCodeText(rbx.Text)
			end,
			[React.Event.FocusLost] = function(enterPressed)
				if enterPressed then
					submitCode()
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(86, 118, 171),
				Transparency = 0.12,
				Thickness = 1.1,
			}),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
			}),
		}),
		Button = e("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Palette.Cyan,
			BorderSizePixel = 0,
			Position = UDim2.new(1, 0, 1, -62),
			Size = UDim2.new(0.32, 0, 0, 48),
			Text = "",
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
			[React.Event.Activated] = submitCode,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(137, 246, 255),
				Transparency = 0.12,
				Thickness = 1.1,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Theme.Palette.Cyan),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(72, 184, 255)),
				}),
			}),
			Label = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -16, 1, -8),
				Text = props.buttonText or "Redeem",
				TextColor3 = Theme.Palette.Ink,
				TextSize = 15,
				TextWrapped = true,
				ZIndex = props.zIndex and (props.zIndex + 2) or nil,
			}),
		}),
		Helper = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyRegular,
			Position = UDim2.new(0, 0, 1, -12),
			Size = UDim2.new(1, 0, 0, 10),
			Text = props.helperText or "",
			TextColor3 = Theme.Palette.MutedSoft,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}),
	})
end

return RedeemCodesPanel
