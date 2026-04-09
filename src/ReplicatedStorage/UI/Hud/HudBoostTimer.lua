local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local BOOST_METADATA = {
	x2MoneyTime = {
		label = "x2 Doubloons",
		icon = "rbxassetid://102766068687661",
		accent = Color3.fromRGB(111, 230, 124),
		order = 1,
	},
	x15WalkSpeedTime = {
		label = "x1.5 Speed",
		icon = "rbxassetid://89427336475199",
		accent = Color3.fromRGB(100, 204, 255),
		order = 2,
	},
}

local DEFAULT_ACCENT = Color3.fromRGB(238, 191, 99)

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
		label = humanizeBoostName(baseName)
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

local function HudBoostTimer(props)
	local trackedPlayer = props.player or Players.LocalPlayer
	local boostState, setBoostState = React.useState(function()
		return snapshotBoosts(trackedPlayer)
	end)

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

	local children = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	}

	for index, entry in ipairs(boostState.entries) do
		children[string.format("Boost_%s", tostring(entry.key))] = e("Frame", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.fromOffset(0, 28),
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			Icon = entry.icon ~= "" and e("ImageLabel", {
				BackgroundTransparency = 1,
				Image = entry.icon,
				LayoutOrder = 1,
				Size = UDim2.fromOffset(24, 24),
				ScaleType = Enum.ScaleType.Fit,
			}) or nil,
			Label = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 2,
				Size = UDim2.fromOffset(0, 24),
				Text = tostring(entry.label),
				TextColor3 = Color3.fromRGB(247, 242, 230),
				TextSize = 13,
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
				Size = UDim2.fromOffset(0, 24),
				Text = formatDuration(entry.remaining),
				TextColor3 = entry.accent,
				TextSize = 12,
				TextStrokeColor3 = Color3.fromRGB(4, 6, 10),
				TextStrokeTransparency = 0.2,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
	}, {
		Container = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 0),
		}, children),
	})
end

return HudBoostTimer
