local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local Responsive = require(UiFolder:WaitForChild("Responsive"))
local HudLayout = require(UiFolder:WaitForChild("HudLayout"))

local e = React.createElement

local BOOST_METADATA = {
	x2MoneyTime = {
		label = "2x Beli",
		icon = "rbxassetid://123727379614328",
		accent = Color3.fromRGB(111, 230, 124),
		order = 1,
	},
	x15WalkSpeedTime = {
		label = "x1.5 Speed",
		icon = "rbxassetid://96331945137652",
		accent = Color3.fromRGB(100, 204, 255),
		order = 2,
	},
	xLuckTime = {
		label = "x1.25 Luck",
		icon = "rbxassetid://99305009492305",
		accent = Color3.fromRGB(205, 142, 255),
		order = 3,
	},
}

local DEFAULT_ACCENT = Color3.fromRGB(238, 191, 99)

local function isCompactViewport(layoutMode)
	return HudLayout.getBoostTimer(layoutMode or Responsive.getHudLayoutMode()).compact == true
end

local function shouldUseMobileCollapse(layoutMode)
	if tostring(layoutMode or Responsive.getHudLayoutMode()) == "phone" then
		return true
	end

	return Responsive.isPhoneViewport(Responsive.getViewportSize())
end

local function trimTimeSuffix(name)
	return string.sub(tostring(name or ""), 1, math.max(0, #tostring(name or "") - 4))
end

local function formatDuration(seconds)
	local total = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(total / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local secs = total % 60

	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end

	if minutes > 0 then
		return string.format("%dm %02ds", minutes, secs)
	end

	return string.format("%ds", secs)
end

local function humanizeBoostName(name)
	local raw = tostring(name or "Boost")
	local spaced = raw:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
	return spaced:gsub("x (%d)", "x%1")
end

local function formatBoostMultiplier(rawMultiplier)
	local multiplierText = tostring(rawMultiplier or "")
	if multiplierText == "15" then
		return "1.5"
	end

	return multiplierText
end

local function fallbackBoostLabel(baseName)
	local raw = tostring(baseName or "")
	local multiplier, effectName = raw:match("^x(%d+)(.+)$")
	if multiplier and effectName and effectName ~= "" then
		return string.format("x%s %s", formatBoostMultiplier(multiplier), humanizeBoostName(effectName))
	end

	return humanizeBoostName(raw)
end

local function getShortestRemaining(entries)
	local shortest = nil
	for _, entry in ipairs(entries or {}) do
		local remaining = tonumber(entry.remaining) or 0
		if remaining > 0 and (shortest == nil or remaining < shortest) then
			shortest = remaining
		end
	end
	return shortest
end

local function findDisplayMetadata(timeValue)
	local timeName = tostring(timeValue and timeValue.Name or "")
	local metadata = BOOST_METADATA[timeName]
	local baseName = trimTimeSuffix(timeName)
	local baseValue = timeValue and timeValue.Parent and timeValue.Parent:FindFirstChild(baseName) or nil

	local icon = metadata and metadata.icon or nil
	if (not icon or icon == "") and baseValue then
		local attributeIcon = baseValue:GetAttribute("Icon")
		if typeof(attributeIcon) == "string" and attributeIcon ~= "" then
			icon = attributeIcon
		end
	end

	local label = metadata and metadata.label or nil
	if (not label or label == "") and baseValue then
		local displayName = baseValue:GetAttribute("DisplayName") or baseValue:GetAttribute("Display_name")
		if typeof(displayName) == "string" and displayName ~= "" then
			label = displayName
		end
	end

	if not label or label == "" then
		label = fallbackBoostLabel(baseName)
	end

	return {
		key = timeName,
		label = label,
		icon = icon or "",
		accent = metadata and metadata.accent or DEFAULT_ACCENT,
		order = metadata and metadata.order or 999,
		remaining = math.max(0, math.floor(tonumber(timeValue and timeValue.Value) or 0)),
	}
end

local function snapshotBoosts(trackedPlayer)
	local potions = trackedPlayer and trackedPlayer:FindFirstChild("Potions")
	local entries = {}

	if potions then
		for _, descendant in ipairs(potions:GetDescendants()) do
			if descendant:IsA("NumberValue") and string.sub(descendant.Name, -4) == "Time" then
				local remaining = math.max(0, math.floor(tonumber(descendant.Value) or 0))
				if remaining > 0 then
					local entry = findDisplayMetadata(descendant)
					entry.remaining = remaining
					entries[#entries + 1] = entry
				end
			end
		end
	end

	table.sort(entries, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		if a.remaining ~= b.remaining then
			return a.remaining > b.remaining
		end
		return tostring(a.key) < tostring(b.key)
	end)

	local signatureParts = table.create(#entries)
	for index, entry in ipairs(entries) do
		signatureParts[index] = string.format("%s:%d", tostring(entry.key), tonumber(entry.remaining) or 0)
	end

	return {
		entries = entries,
		signature = table.concat(signatureParts, "|"),
	}
end

local function renderBoostRow(entry, index, compact, dense)
	local rowHeight = if dense then 22 elseif compact then 34 else 44
	local iconSize = if dense then 16 elseif compact then 24 else 32
	local labelHeight = if dense then 18 elseif compact then 24 else 30
	local labelTextSize = if dense then 10 elseif compact then 13 else 16
	local timerTextSize = if dense then 9 elseif compact then 12 else 15
	local horizontalPadding = if dense then 6 elseif compact then 8 else 10
	local rightPadding = if dense then 7 elseif compact then 9 else 12
	local verticalPadding = if dense then 2 elseif compact then 4 else 5
	local layoutPadding = if dense then 4 elseif compact then 6 else 8

	return e("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromRGB(10, 18, 31),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		LayoutOrder = index,
		Size = UDim2.fromOffset(0, rowHeight),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 999),
		}),
		Stroke = e("UIStroke", {
			Color = Color3.fromRGB(242, 209, 107),
			Thickness = 1,
			Transparency = 0.18,
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, horizontalPadding),
			PaddingRight = UDim.new(0, rightPadding),
			PaddingTop = UDim.new(0, verticalPadding),
			PaddingBottom = UDim.new(0, verticalPadding),
		}),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Padding = UDim.new(0, layoutPadding),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		Icon = entry.icon ~= "" and e("ImageLabel", {
			BackgroundTransparency = 1,
			Image = entry.icon,
			LayoutOrder = 1,
			Size = UDim2.fromOffset(iconSize, iconSize),
			ScaleType = Enum.ScaleType.Fit,
		}) or nil,
		Label = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, labelHeight),
			Text = tostring(entry.label),
			TextColor3 = Color3.fromRGB(247, 242, 230),
			TextSize = labelTextSize,
			TextStrokeColor3 = Color3.fromRGB(4, 6, 10),
			TextStrokeTransparency = 0.25,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Timer = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			LayoutOrder = 3,
			Size = UDim2.fromOffset(0, labelHeight),
			Text = formatDuration(entry.remaining),
			TextColor3 = entry.accent,
			TextSize = timerTextSize,
			TextStrokeColor3 = Color3.fromRGB(4, 6, 10),
			TextStrokeTransparency = 0.2,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function HudBoostTimer(props)
	local trackedPlayer = props.player or Players.LocalPlayer
	local boostState, setBoostState = React.useState(function()
		return snapshotBoosts(trackedPlayer)
	end)
	local mobileExpanded, setMobileExpanded = React.useState(false)

	React.useEffect(function()
		local destroyed = false
		local elapsed = 0

		local function refresh(forceRefresh)
			if destroyed then
				return
			end

			local nextState = snapshotBoosts(trackedPlayer)
			setBoostState(function(currentState)
				if forceRefresh ~= true and currentState.signature == nextState.signature then
					return currentState
				end
				return nextState
			end)
		end

		refresh(true)

		local connection = RunService.Heartbeat:Connect(function(deltaTime)
			elapsed += deltaTime
			if elapsed < 0.2 then
				return
			end

			elapsed = 0
			refresh(false)
		end)

		return function()
			destroyed = true
			connection:Disconnect()
		end
	end, { trackedPlayer })

	if #boostState.entries == 0 then
		return nil
	end
	local compact = isCompactViewport(props.layoutMode)
	local phone = shouldUseMobileCollapse(props.layoutMode)
	local showBoostRows = not phone or mobileExpanded == true

	if phone then
		local boostLayout = props.boostLayout or HudLayout.getBoostTimer(props.layoutMode)
		local laneHeight = math.max(tonumber(boostLayout.size and boostLayout.size.Y.Offset) or 118, 34)
		local summaryHeight = tonumber(boostLayout.collapsedHeight) or 34
		local stackGap = tonumber(boostLayout.stackGap) or 6
		local rowHeight = 22
		local rowGap = 4
		local contentHeight = (#boostState.entries * rowHeight) + (math.max(0, #boostState.entries - 1) * rowGap)
		local maxListHeight = math.max(0, laneHeight - summaryHeight - stackGap)
		local listHeight = if mobileExpanded then math.min(contentHeight, maxListHeight) else 0
		local shortestRemaining = getShortestRemaining(boostState.entries)
		local boostCount = #boostState.entries
		local summaryText = if shortestRemaining
			then string.format("Boosts x%d  %s", boostCount, formatDuration(shortestRemaining))
			else string.format("Boosts x%d", boostCount)
		local rowChildren = {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, rowGap),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),
		}

		for index, entry in ipairs(boostState.entries) do
			rowChildren[string.format("Boost_%s", tostring(entry.key))] = renderBoostRow(entry, index, compact, true)
		end

		return e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = false,
			Size = UDim2.fromScale(1, 1),
		}, {
			ExpandedList = mobileExpanded and listHeight > 0 and e("ScrollingFrame", {
				Active = contentHeight > listHeight,
				AnchorPoint = Vector2.new(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromOffset(0, contentHeight),
				ClipsDescendants = true,
				Position = UDim2.new(1, 0, 1, -(summaryHeight + stackGap)),
				ScrollBarImageColor3 = Color3.fromRGB(242, 209, 107),
				ScrollBarThickness = if contentHeight > listHeight then 3 else 0,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				Size = UDim2.new(1, 0, 0, listHeight),
				VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Left,
				ZIndex = 2,
			}, rowChildren) or nil,
			MobileSummary = e("TextButton", {
				AnchorPoint = Vector2.new(1, 1),
				AutoButtonColor = true,
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Color3.fromRGB(10, 18, 31),
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.fromOffset(0, summaryHeight),
				Text = summaryText,
				TextColor3 = Color3.fromRGB(247, 242, 230),
				TextSize = 13,
				TextStrokeColor3 = Color3.fromRGB(4, 6, 10),
				TextStrokeTransparency = 0.25,
				ZIndex = 3,
				[React.Event.Activated] = function()
					setMobileExpanded(function(current)
						return not current
					end)
				end,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(242, 209, 107),
					Thickness = 1,
					Transparency = 0.12,
				}),
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
				}),
			}),
		})
	end

	local children = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	}

	if showBoostRows then
		for index, entry in ipairs(boostState.entries) do
			children[string.format("Boost_%s", tostring(entry.key))] = renderBoostRow(entry, index, compact)
		end
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
	}, {
		Container = e("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(1, 0),
		}, children),
	})
end

return HudBoostTimer
