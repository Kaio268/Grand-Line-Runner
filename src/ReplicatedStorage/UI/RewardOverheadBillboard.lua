local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Responsive = require(script.Parent:WaitForChild("Responsive"))
local IndexTheme = require(script.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local PANEL_FILL = Color3.fromRGB(17, 26, 39)
local PANEL_FILL_SOFT = Color3.fromRGB(29, 43, 61)
local TEXT = Color3.fromRGB(239, 239, 235)
local MUTED = Color3.fromRGB(194, 203, 216)
local SHADOW = Color3.fromRGB(0, 0, 0)

local TIMER_SAFE = Color3.fromRGB(111, 230, 124)
local TIMER_WARNING = Color3.fromRGB(255, 196, 88)
local TIMER_CRITICAL = Color3.fromRGB(255, 104, 104)
local DEFAULT_ACCENT = Color3.fromRGB(242, 209, 107)

local function formatRemaining(seconds)
	local safeSeconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	local minutes = math.floor(safeSeconds / 60)
	local remainder = safeSeconds % 60
	return string.format("%d:%02d", minutes, remainder)
end

local function blendColor(baseColor, accentColor, alpha)
	return baseColor:Lerp(accentColor, math.clamp(alpha or 0, 0, 1))
end

local function getPillWidth(text, minimum, maximum)
	return math.clamp((#tostring(text or "") * 7) + 24, minimum, maximum)
end

local function getTimerState(remaining, totalSeconds)
	local safeRemaining = math.max(0, tonumber(remaining) or 0)
	local safeTotal = math.max(0, tonumber(totalSeconds) or 0)
	local ratio = if safeTotal > 0 then safeRemaining / safeTotal else nil

	if (ratio ~= nil and ratio <= 0.15) or (ratio == nil and safeRemaining <= 5) then
		return {
			color = TIMER_CRITICAL,
			fill = blendColor(Color3.fromRGB(12, 16, 24), TIMER_CRITICAL, 0.18),
			urgent = safeRemaining <= 5,
		}
	elseif (ratio ~= nil and ratio <= 0.6) or (ratio == nil and safeRemaining <= 15) then
		return {
			color = TIMER_WARNING,
			fill = blendColor(Color3.fromRGB(12, 16, 24), TIMER_WARNING, 0.16),
			urgent = false,
		}
	end

	return {
		color = TIMER_SAFE,
		fill = blendColor(Color3.fromRGB(12, 16, 24), TIMER_SAFE, 0.14),
		urgent = false,
	}
end

local function pill(text, textColor, size, position, textSize)
	return e("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = blendColor(PANEL_FILL_SOFT, textColor, 0.18),
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		ZIndex = 3,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Stroke = e("UIStroke", {
			Color = textColor,
			Transparency = 0.28,
			Thickness = 1,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = IndexTheme.Fonts.Label,
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextColor3 = textColor,
			TextSize = textSize,
			TextStrokeColor3 = SHADOW,
			TextStrokeTransparency = 0.42,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function RewardOverheadBillboard(props)
	props = props or {}
	local mobile = Responsive.isMobile()
	local remaining = tonumber(props.remaining)
	local showTimer = remaining ~= nil
	local timerState = if showTimer then getTimerState(remaining, props.totalSeconds) else nil
	local urgentPulseOn = showTimer
		and timerState.urgent == true
		and math.floor(math.max(0, remaining)) % 2 == 0

	local accentColor = props.accentColor or DEFAULT_ACCENT
	local metaColor = props.metaColor or accentColor
	local extraColor = props.extraColor or accentColor
	local title = tostring(props.title or "Reward")
	local typeLabel = tostring(props.typeLabel or "Reward")
	local extraLabel = tostring(props.extraLabel or "")
	local metaLabel = tostring(props.metaLabel or "")
	local helperText = tostring(props.helperText or "")
	local hasHelper = helperText ~= ""
	local hasExtra = extraLabel ~= ""
	local hasMeta = metaLabel ~= ""

	local panelWidth = if showTimer
		then (if hasExtra then (if mobile then 360 else 420) else (if mobile then 332 else 372))
		else (if hasExtra then (if mobile then 292 else 328) else (if mobile then 256 else 280))
	local panelHeight = if showTimer then (if mobile then 92 else 98) else (if hasHelper then 76 else 58)
	local timerWidth = if showTimer then (if mobile then 108 else 126) else 0
	local contentX = if showTimer then timerWidth + 24 else 12
	local contentWidth = panelWidth - contentX - 12
	local pillHeight = if mobile then 18 else 22
	local labelTextSize = if mobile then 10 else 12
	local titleTextSize = if mobile then 18 else 20
	local helperTextSize = if mobile then 11 else 13
	local typePillWidth = getPillWidth(typeLabel, if mobile then 62 else 68, if mobile then 88 else 98)
	local extraPillWidth = getPillWidth(extraLabel, if mobile then 56 else 64, if mobile then 78 else 92)
	local metaPillWidth = getPillWidth(metaLabel, if mobile then 64 else 72, if mobile then 96 else 112)
	local metaPillX = contentX + typePillWidth + (if hasExtra then extraPillWidth + 16 else 8)
	local pillY = if showTimer then 52 else 40
	local helperY = if showTimer then 72 else 58
	local outerColor = if showTimer then timerState.color else (props.borderColor or accentColor)
	local glowTransparency = if urgentPulseOn then 0.22 elseif showTimer then 0.58 else (props.glowTransparency or 0.84)
	local panelFill = props.panelFill or PANEL_FILL
	local panelStart = props.panelStart or blendColor(PANEL_FILL_SOFT, accentColor, 0.18)
	local panelEnd = props.panelEnd or blendColor(PANEL_FILL, accentColor, 0.08)

	return e("BillboardGui", {
		Adornee = props.adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = tonumber(props.maxDistance) or 58,
		Size = UDim2.fromOffset(panelWidth, panelHeight),
		StudsOffsetWorldSpace = Vector3.new(0, tonumber(props.offsetY) or 4.6, 0),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Panel = e("Frame", {
			BackgroundColor3 = panelFill,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = outerColor,
				Transparency = 0,
				Thickness = if urgentPulseOn then 2.6 else 1.65,
			}),
			Glow = e("Frame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 0,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = outerColor,
					Transparency = glowTransparency,
					Thickness = if urgentPulseOn then 4.4 else 3,
				}),
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, panelStart),
					ColorSequenceKeypoint.new(1, panelEnd),
				}),
			}),
			Timer = if showTimer
				then e("Frame", {
					BackgroundColor3 = timerState.fill,
					BackgroundTransparency = if urgentPulseOn then 0.01 else 0.06,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(10, 10),
					Size = UDim2.fromOffset(timerWidth, panelHeight - 20),
					ZIndex = 2,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 9),
					}),
					Stroke = e("UIStroke", {
						Color = timerState.color,
						Transparency = if urgentPulseOn then 0.05 else 0.32,
						Thickness = if urgentPulseOn then 2.2 else 1.4,
					}),
					Caption = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = IndexTheme.Fonts.Label,
						Position = UDim2.fromOffset(8, 7),
						Size = UDim2.new(1, -16, 0, 12),
						Text = "DESPAWN",
						TextColor3 = timerState.color,
						TextSize = 9,
						TextStrokeColor3 = SHADOW,
						TextStrokeTransparency = 0.5,
					}),
					Value = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = IndexTheme.Fonts.Display,
						Position = UDim2.fromOffset(8, if mobile then 20 else 21),
						Size = UDim2.new(1, -16, 0, if mobile then 36 else 40),
						Text = formatRemaining(remaining),
						TextColor3 = timerState.color,
						TextScaled = true,
						TextSize = if mobile then 32 else 38,
						TextStrokeColor3 = SHADOW,
						TextStrokeTransparency = 0.18,
					}, {
						TextSizeConstraint = e("UITextSizeConstraint", {
							MaxTextSize = if mobile then 32 else 38,
							MinTextSize = 16,
						}),
					}),
					Subcaption = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = IndexTheme.Fonts.Label,
						Position = UDim2.fromOffset(8, panelHeight - 36),
						Size = UDim2.new(1, -16, 0, 14),
						Text = "REMAINING",
						TextColor3 = MUTED,
						TextSize = 9,
						TextStrokeColor3 = SHADOW,
						TextStrokeTransparency = 0.55,
					}),
				})
				else nil,
			Name = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = IndexTheme.Fonts.Display,
				Position = UDim2.fromOffset(contentX, if showTimer then 11 else 7),
				Size = UDim2.fromOffset(contentWidth, if showTimer then 30 else 24),
				Text = title,
				TextColor3 = TEXT,
				TextSize = titleTextSize,
				TextStrokeColor3 = SHADOW,
				TextStrokeTransparency = 0.24,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
			}),
			Type = pill(
				typeLabel,
				accentColor,
				UDim2.fromOffset(typePillWidth, pillHeight),
				UDim2.fromOffset(contentX, pillY),
				labelTextSize
			),
			Extra = if hasExtra
				then pill(
					extraLabel,
					extraColor,
					UDim2.fromOffset(extraPillWidth, pillHeight),
					UDim2.fromOffset(contentX + typePillWidth + 8, pillY),
					labelTextSize
				)
				else nil,
			Meta = if hasMeta
				then pill(
					metaLabel,
					metaColor,
					UDim2.fromOffset(metaPillWidth, pillHeight),
					UDim2.fromOffset(metaPillX, pillY),
					labelTextSize
				)
				else nil,
			Helper = if hasHelper
				then e("TextLabel", {
					BackgroundTransparency = 1,
					Font = IndexTheme.Fonts.Label,
					Position = UDim2.fromOffset(contentX, helperY),
					Size = UDim2.fromOffset(contentWidth, 16),
					Text = helperText,
					TextColor3 = MUTED,
					TextSize = helperTextSize,
					TextStrokeColor3 = SHADOW,
					TextStrokeTransparency = 0.46,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 3,
				})
				else nil,
		}),
	})
end

return RewardOverheadBillboard
