local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local CARD_HEIGHT = 192
local ACTION_BUTTON_WIDTH = 132
local SKIP_BUTTON_WIDTH = 104
local ACTION_BUTTON_HEIGHT = 40
local ACTION_BUTTON_GAP = 10

local SHELL = {
	Background = Color3.fromRGB(15, 27, 42),
	Header = Color3.fromRGB(16, 35, 59),
	Gold = Theme.Palette.Gold,
	GoldSoft = Theme.Palette.GoldSoft,
	GoldShadow = Theme.Palette.GoldShadow,
	Text = Theme.Palette.Text,
	Muted = Theme.Palette.Muted,
	Track = Color3.fromRGB(22, 32, 43),
	Secondary = Color3.fromRGB(191, 128, 20),
	SecondaryTop = Color3.fromRGB(234, 176, 47),
	SecondaryStroke = Color3.fromRGB(255, 230, 150),
	Disabled = Color3.fromRGB(65, 73, 84),
}

local function TutorialPrompt(props)
	local state = props.state or {}
	local step = state.step or {}
	local totalSteps = math.max(1, tonumber(state.totalSteps) or 1)
	local stepIndex = math.clamp(math.floor(tonumber(state.stepIndex) or 1), 1, totalSteps)
	local progress = math.clamp(tonumber(state.progress) or 0, 0, 1)
	local canAdvance = state.canAdvance == true
	local actionText = tostring(step.actionText or "")
	if actionText == "" then
		actionText = tostring(step.waitText or "Continue")
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = SHELL.Background,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.new(0.5, 0, 1, -112),
		Size = UDim2.new(0.86, 0, 0, CARD_HEIGHT),
		ZIndex = 180,
	}, {
		Constraint = e("UISizeConstraint", {
			MaxSize = Vector2.new(560, CARD_HEIGHT),
			MinSize = Vector2.new(320, 172),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 14),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = SHELL.GoldSoft,
			Thickness = 2,
			Transparency = 0.08,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, SHELL.Header),
				ColorSequenceKeypoint.new(1, SHELL.Background),
			}),
		}),
		StepLabel = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(18, 14),
			Size = UDim2.new(1, -36, 0, 18),
			Text = string.format("STEP %d / %d", stepIndex, totalSteps),
			TextColor3 = SHELL.GoldSoft,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 181,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(18, 34),
			Size = UDim2.new(1, -36, 0, 28),
			Text = tostring(step.title or "Tutorial"),
			TextColor3 = SHELL.Text,
			TextSize = 24,
			TextStrokeColor3 = SHELL.GoldShadow,
			TextStrokeTransparency = 0.55,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 181,
		}),
		Body = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(18, 66),
			Size = UDim2.new(1, -36, 0, 34),
			Text = tostring(step.body or ""),
			TextColor3 = SHELL.Text,
			TextSize = 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 181,
		}),
		Instruction = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(18, 102),
			Size = UDim2.new(1, -36, 0, 20),
			Text = tostring(step.instruction or ""),
			TextColor3 = SHELL.Muted,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 181,
		}),
		ProgressTrack = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = SHELL.Track,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 18, 1, -58),
			Size = UDim2.new(1, -36, 0, 10),
			ZIndex = 181,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = SHELL.GoldShadow,
				Thickness = 1,
				Transparency = 0.2,
			}),
			Fill = e("Frame", {
				BackgroundColor3 = SHELL.Gold,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(math.max(progress, canAdvance and 1 or 0), 1),
				ZIndex = 182,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Gradient = e("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, SHELL.GoldSoft),
						ColorSequenceKeypoint.new(1, SHELL.Gold),
					}),
				}),
			}),
		}),
		Skip = e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			AutoButtonColor = false,
			BackgroundColor3 = SHELL.Secondary,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Font = Theme.Fonts.Button,
			Position = UDim2.new(1, -(18 + ACTION_BUTTON_WIDTH + ACTION_BUTTON_GAP), 1, -14),
			Size = UDim2.fromOffset(SKIP_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT),
			Text = "Skip",
			TextColor3 = Color3.fromRGB(31, 24, 10),
			TextSize = 14,
			TextStrokeTransparency = 1,
			ZIndex = 184,
			[React.Event.Activated] = function()
				if props.onSkip then
					props.onSkip()
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = SHELL.SecondaryStroke,
				Thickness = 1.5,
				Transparency = 0.12,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, SHELL.SecondaryTop),
					ColorSequenceKeypoint.new(1, SHELL.Secondary),
				}),
			}),
		}),
		Action = e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			AutoButtonColor = false,
			BackgroundColor3 = if canAdvance then SHELL.Gold else SHELL.Disabled,
			BackgroundTransparency = if canAdvance then 0 else 0.18,
			BorderSizePixel = 0,
			Font = Theme.Fonts.Button,
			Position = UDim2.new(1, -18, 1, -14),
			Size = UDim2.fromOffset(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT),
			Text = actionText,
			TextColor3 = if canAdvance then Color3.fromRGB(31, 24, 10) else Color3.fromRGB(222, 228, 238),
			TextSize = 15,
			TextStrokeTransparency = 1,
			ZIndex = 184,
			[React.Event.Activated] = function()
				if canAdvance and props.onAdvance then
					props.onAdvance()
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = if canAdvance then SHELL.GoldSoft else Color3.fromRGB(96, 108, 126),
				Thickness = 1.5,
				Transparency = 0.08,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, if canAdvance then SHELL.GoldSoft else Color3.fromRGB(88, 99, 116)),
					ColorSequenceKeypoint.new(1, if canAdvance then SHELL.Gold else SHELL.Disabled),
				}),
			}),
		}),
	})
end

return TutorialPrompt
