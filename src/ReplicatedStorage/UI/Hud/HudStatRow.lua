local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local HudStatCounter = require(script.Parent:WaitForChild("HudStatCounter"))
local HudCounterConfig = require(script.Parent:WaitForChild("HudCounterConfig"))

local e = React.createElement

local function HudStatRow(props)
	local surface = props.surface
	if typeof(surface) ~= "Instance" or not surface.Parent then
		return nil
	end

	local rowHeight = tonumber(props.rowHeight) or 42
	local rowSpacing = tonumber(props.rowSpacing) or 10
	local iconSlotWidth = tonumber(props.iconSlotWidth) or 40
	local barGap = tonumber(props.barGap) or 10
	local panelPadding = HudCounterConfig.PanelPadding

	local rowChildren = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Padding = UDim.new(0, rowSpacing),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	}

	for index, item in ipairs(props.items or {}) do
		local key = item.key or item.name or tostring(index)
		rowChildren[key] = e(HudStatCounter, {
			host = item.host,
			kind = item.kind,
			name = item.name,
			iconSource = item.iconSource,
			layoutOrder = index,
			rowHeight = rowHeight,
			iconSlotWidth = iconSlotWidth,
			barGap = barGap,
			sourceLabel = item.sourceLabel,
			showDivider = index < #props.items,
		})
	end

	return ReactRoblox.createPortal(e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, {
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, panelPadding.Top),
			PaddingBottom = UDim.new(0, panelPadding.Bottom),
			PaddingLeft = UDim.new(0, panelPadding.Left),
			PaddingRight = UDim.new(0, panelPadding.Right),
		}),
		Rows = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		}, rowChildren),
	}), surface)
end

return HudStatRow
