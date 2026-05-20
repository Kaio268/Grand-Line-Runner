local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local CARD_HEIGHT = 192
local FINALE_CARD_HEIGHT = 450
local FINALE_MAX_WIDTH = 700
local ACTION_BUTTON_WIDTH = 132
local SKIP_BUTTON_WIDTH = 104
local ACTION_BUTTON_HEIGHT = 40
local ACTION_BUTTON_GAP = 10
local FINALE_STEP_ID = "final_guidance"

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

local FINALE_ROWS = {
	{
		Icon = "C",
		Title = "Collect Crewmates",
		Detail = "Build your crew and grow stronger.",
		Color = Color3.fromRGB(54, 181, 255),
	},
	{
		Icon = "A",
		Title = "Unlock Abilities",
		Detail = "Discover mysterious powers.",
		Color = Color3.fromRGB(190, 93, 255),
	},
	{
		Icon = "$",
		Title = "Open Chests",
		Detail = "Claim rare loot and rewards.",
		Color = Color3.fromRGB(255, 213, 67),
	},
	{
		Icon = "Q",
		Title = "Complete Quests",
		Detail = "Earn rewards through challenges.",
		Color = Color3.fromRGB(104, 232, 111),
	},
	{
		Icon = "!",
		Title = "Push Deeper",
		Detail = "Risk more for greater glory.",
		Color = Color3.fromRGB(255, 102, 78),
	},
}

local function renderFinaleRows()
	local children = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 5),
		}),
	}

	for index, row in ipairs(FINALE_ROWS) do
		children["Row" .. tostring(index)] = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(8, 16, 27),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 38),
			ZIndex = 182,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = row.Color,
				Thickness = 1,
				Transparency = 0.48,
			}),
			Badge = e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = row.Color,
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.fromOffset(26, 26),
				ZIndex = 183,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Glow = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = row.Color,
					Thickness = 2,
					Transparency = 0.35,
				}),
				Icon = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Button,
					Size = UDim2.fromScale(1, 1),
					Text = row.Icon,
					TextColor3 = Color3.fromRGB(12, 20, 31),
					TextSize = 15,
					TextStrokeTransparency = 1,
					ZIndex = 184,
				}),
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.BodyStrong,
				Position = UDim2.fromOffset(44, 4),
				Size = UDim2.new(1, -56, 0, 16),
				Text = row.Title,
				TextColor3 = row.Color,
				TextSize = 14,
				TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
				TextStrokeTransparency = 0.45,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 183,
			}),
			Detail = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(44, 20),
				Size = UDim2.new(1, -56, 0, 14),
				Text = row.Detail,
				TextColor3 = SHELL.Text,
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 183,
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 134),
		Size = UDim2.new(1, -36, 0, 210),
		ZIndex = 182,
	}, children)
end

local function TutorialPrompt(props)
	local state = props.state or {}
	local step = state.step or {}
	local totalSteps = math.max(1, tonumber(state.totalSteps) or 1)
	local stepIndex = math.clamp(math.floor(tonumber(state.stepIndex) or 1), 1, totalSteps)
	local progress = math.clamp(tonumber(state.progress) or 0, 0, 1)
	local canAdvance = state.canAdvance == true
	local isFinale = tostring(step.id or "") == FINALE_STEP_ID
	local cardHeight = if isFinale then FINALE_CARD_HEIGHT else CARD_HEIGHT
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
		Position = UDim2.new(0.5, 0, 1, if isFinale then -48 else -112),
		Size = UDim2.new(if isFinale then 0.92 else 0.86, 0, 0, cardHeight),
		ZIndex = 180,
	}, {
		Constraint = e("UISizeConstraint", {
			MaxSize = Vector2.new(if isFinale then FINALE_MAX_WIDTH else 560, cardHeight),
			MinSize = Vector2.new(320, if isFinale then 340 else 172),
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
		FinaleHeadline = isFinale and e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(18, 70),
			Size = UDim2.new(1, -36, 0, 58),
			Text = "YOUR ADVENTURE\nSTARTS NOW!",
			TextColor3 = SHELL.GoldSoft,
			TextSize = 28,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.2,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 182,
		}, {
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 246, 179)),
					ColorSequenceKeypoint.new(0.55, SHELL.GoldSoft),
					ColorSequenceKeypoint.new(1, SHELL.Gold),
				}),
			}),
			Glow = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				Color = SHELL.GoldShadow,
				Thickness = 1.5,
				Transparency = 0.18,
			}),
		}) or nil,
		FinaleRows = isFinale and renderFinaleRows() or nil,
		Body = not isFinale and e("TextLabel", {
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
		}) or nil,
		Instruction = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = if isFinale then UDim2.new(0, 18, 1, -82) else UDim2.fromOffset(18, 102),
			Size = UDim2.new(1, -36, 0, 20),
			Text = tostring(step.instruction or ""),
			TextColor3 = if isFinale then SHELL.Text else SHELL.Muted,
			TextSize = if isFinale then 14 else 13,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = if isFinale then 0.45 else 1,
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
