local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local HudStatNotificationService = require(script.Parent:WaitForChild("HudStatNotificationService"))
local HudStatPopup = require(script.Parent:WaitForChild("HudStatPopup"))
local HudStatsTheme = require(script.Parent:WaitForChild("HudStatsTheme"))

local e = React.createElement

local function appendNotification(list, notification)
	local nextList = table.create(#list + 1)
	for index, item in ipairs(list) do
		nextList[index] = item
	end
	nextList[#nextList + 1] = notification

	while #nextList > 6 do
		table.remove(nextList, 1)
	end

	return nextList
end

local function removeNotification(list, id)
	local nextList = {}
	for _, item in ipairs(list) do
		if item.id ~= id then
			nextList[#nextList + 1] = item
		end
	end
	return nextList
end

local function HudStatNotificationLayer(props)
	local surface = props.surface
	if typeof(surface) ~= "Instance" or not surface.Parent then
		return nil
	end

	local notifications, setNotifications = React.useState({})

	React.useEffect(function()
		local connection = HudStatNotificationService.subscribe(function(notification)
			setNotifications(function(current)
				return appendNotification(current, notification)
			end)
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	local children = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Padding = UDim.new(0, HudStatsTheme.Popup.Spacing),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	}

	for index, notification in ipairs(notifications) do
		children[string.format("Notification_%s", tostring(notification.id))] = e(HudStatPopup, {
			notification = notification,
			layoutOrder = index,
			onFinished = function(id)
				setNotifications(function(current)
					return removeNotification(current, id)
				end)
			end,
		})
	end

	return ReactRoblox.createPortal(e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
	}, children), surface)
end

return HudStatNotificationLayer
