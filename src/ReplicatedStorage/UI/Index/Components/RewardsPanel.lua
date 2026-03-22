local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function rewardChip(props)
	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Ink,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1 / 3, -8, 0, 56),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 14),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.BorderSoft,
			Transparency = 0.18,
		}),
		Icon = props.icon and props.icon ~= "" and e("ImageLabel", {
			BackgroundTransparency = 1,
			Image = props.icon,
			Position = UDim2.fromOffset(10, 12),
			Size = UDim2.fromOffset(30, 30),
			ScaleType = Enum.ScaleType.Fit,
		}) or nil,
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(props.icon and props.icon ~= "" and 46 or 12, 10),
			Size = UDim2.new(1, -(props.icon and props.icon ~= "" and 56 or 24), 0, 12),
			Text = tostring(props.label or ""),
			TextColor3 = Theme.Palette.MutedSoft,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Amount = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(props.icon and props.icon ~= "" and 46 or 12, 24),
			Size = UDim2.new(1, -(props.icon and props.icon ~= "" and 56 or 24), 0, 20),
			Text = tostring(props.amount or ""),
			TextColor3 = Theme.Palette.Text,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function statusButton(props)
	local reward = props.reward or {}
	local isClaimed = reward.claimed == true
	local isClaimable = reward.claimable == true
	local fillColor = Theme.Palette.SectionSoft
	local textColor = Theme.Palette.Text
	local strokeColor = Theme.Palette.BorderSoft
	local buttonText = "Locked"

	if isClaimed then
		fillColor = Theme.Palette.Emerald
		textColor = Theme.Palette.Ink
		strokeColor = Theme.Palette.Emerald
		buttonText = "Claimed"
	elseif isClaimable then
		fillColor = Theme.Palette.Gold
		textColor = Theme.Palette.Ink
		strokeColor = Theme.Palette.GoldSoft
		buttonText = "Claim"
	end

	local function triggerClaim()
		if isClaimable and props.onClaimRequested then
			props.onClaimRequested(reward.id)
		end
	end

	return e("TextButton", {
		Active = isClaimable,
		AnchorPoint = Vector2.new(1, 1),
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = isClaimable and 0 or 0.15,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -18, 1, -16),
		Size = UDim2.fromOffset(132, 38),
		Text = buttonText,
		TextColor3 = textColor,
		TextSize = 13,
		Font = Theme.Fonts.Button,
		Selectable = isClaimable,
		ZIndex = 3,
		[React.Event.Activated] = triggerClaim,
		[React.Event.MouseButton1Click] = triggerClaim,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 14),
		}),
		Stroke = e("UIStroke", {
			Color = strokeColor,
			Transparency = isClaimed and 0.18 or 0.08,
			Thickness = 1.2,
		}),
	})
end

local function rewardCard(props)
	local reward = props.reward or {}
	local accentColor = reward.claimed and Theme.Palette.Emerald or (reward.accentColor or Theme.Palette.Orange)
	local remainingText = reward.claimable and "Ready to claim"
		or reward.claimed and "Reward claimed"
		or string.format("%d more discoveries needed", reward.remaining or 0)

	local chipChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, item in ipairs(reward.rewards or {}) do
		chipChildren["Chip" .. tostring(index)] = e(rewardChip, {
			amount = item.amount,
			icon = item.icon,
			label = item.label,
			layoutOrder = index,
		})
	end

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Section,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, Theme.Layout.RewardCardHeight),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 22),
		}),
		Stroke = e("UIStroke", {
			Color = accentColor,
			Transparency = 0.08,
			Thickness = 1.2,
		}),
		Glow = e("UIStroke", {
			Color = accentColor,
			Transparency = 0.86,
			Thickness = 4,
		}),
		Gradient = e("UIGradient", {
			Rotation = 125,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.SectionSoft),
				ColorSequenceKeypoint.new(1, Theme.Palette.Section),
			}),
		}),
		TopStrip = e("Frame", {
			BackgroundColor3 = accentColor,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 4),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
		}),
		IconShell = e("Frame", {
			BackgroundColor3 = Theme.Palette.Ink,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(18, 18),
			Size = UDim2.fromOffset(64, 64),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 18),
			}),
			Stroke = e("UIStroke", {
				Color = accentColor,
				Transparency = 0.14,
			}),
			Icon = reward.icon and reward.icon ~= "" and e("ImageLabel", {
				BackgroundTransparency = 1,
				Image = reward.icon,
				Position = UDim2.fromOffset(10, 10),
				Size = UDim2.fromOffset(44, 44),
				ScaleType = Enum.ScaleType.Fit,
			}) or nil,
		}),
		ThresholdLabel = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(96, 18),
			Size = UDim2.new(1, -250, 0, 14),
			Text = "MILESTONE",
			TextColor3 = Theme.Palette.MutedSoft,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		ThresholdValue = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(96, 32),
			Size = UDim2.new(1, -250, 0, 32),
			Text = string.format("Collect %d Units", reward.threshold or 0),
			TextColor3 = Theme.Palette.Text,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		ThresholdInfo = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(96, 66),
			Size = UDim2.new(1, -250, 0, 16),
			Text = remainingText,
			TextColor3 = reward.claimable and Theme.Palette.Gold or Theme.Palette.Muted,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		RewardsRow = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(18, 96),
			Size = UDim2.new(1, -168, 0, 56),
		}, chipChildren),
		Button = e(statusButton, {
			onClaimRequested = props.onClaimRequested,
			reward = reward,
		}),
	})
end

local function RewardsPanel(props)
	local rewards = props.rewards or {}
	local children = {
		List = e("UIListLayout", {
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
		}),
	}

	for index, reward in ipairs(rewards) do
		children["Reward" .. tostring(index)] = e(rewardCard, {
			layoutOrder = index,
			onClaimRequested = props.onClaimRequested,
			reward = reward,
		})
	end

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Section,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 1, -2),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 22),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.BorderSoft,
			Transparency = 0.08,
			Thickness = 1.2,
		}),
		Gradient = e("UIGradient", {
			Rotation = 125,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.SectionSoft),
				ColorSequenceKeypoint.new(1, Theme.Palette.Section),
			}),
		}),
		HeaderTitle = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(18, 12),
			Size = UDim2.new(1, -36, 0, 24),
			Text = "Milestone Rewards",
			TextColor3 = Theme.Palette.Text,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		HeaderInfo = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(18, 40),
			Size = UDim2.new(1, -36, 0, 16),
			Text = "Each discovered variant moves your claim progress forward.",
			TextColor3 = Theme.Palette.Muted,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Scroller = #rewards > 0 and e("ScrollingFrame", {
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			Position = UDim2.fromOffset(14, 68),
			ScrollBarImageColor3 = Theme.Palette.Cyan,
			ScrollBarThickness = 8,
			Size = UDim2.new(1, -28, 1, -82),
		}, children) or nil,
		Empty = #rewards == 0 and e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromOffset(320, 26),
			Text = "No reward milestones available.",
			TextColor3 = Theme.Palette.Muted,
			TextSize = 18,
		}) or nil,
	})
end

return RewardsPanel
