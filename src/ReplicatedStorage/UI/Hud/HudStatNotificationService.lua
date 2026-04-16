local HudStatNotificationService = {}

local emitter = Instance.new("BindableEvent")
local nextNotificationId = 0

local function trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function HudStatNotificationService.subscribe(callback)
	return emitter.Event:Connect(callback)
end

function HudStatNotificationService.snapshotIcon(iconSource)
	if not iconSource or not iconSource:IsA("GuiObject") then
		return nil
	end

	local image = tostring(iconSource.Image or "")
	if image == "" then
		return nil
	end

	return {
		image = image,
		imageColor3 = iconSource.ImageColor3,
		imageRectOffset = iconSource.ImageRectOffset,
		imageRectSize = iconSource.ImageRectSize,
		imageTransparency = tonumber(iconSource.ImageTransparency) or 0,
		rotation = tonumber(iconSource.Rotation) or 0,
	}
end

function HudStatNotificationService.getLabelFromFormattedText(formattedText, fallbackLabel)
	local raw = trim(formattedText)
	local label = trim((raw:gsub("^[-+]?[%d,%.]+", "")))

	if label ~= "" then
		return label
	end

	return trim(fallbackLabel)
end

function HudStatNotificationService.pushValueChange(payload)
	local delta = tonumber(payload and payload.delta) or 0
	if delta == 0 then
		return nil
	end

	nextNotificationId += 1

	local notification = {
		id = nextNotificationId,
		createdAt = os.clock(),
		delta = delta,
		isPositive = delta > 0,
		kind = tostring(payload and payload.kind or "Default"),
		valueText = tostring(payload and payload.valueText or ""),
		labelText = trim(payload and payload.labelText or ""),
		icon = payload and payload.icon,
	}

	if notification.valueText == "" then
		notification.valueText = tostring(math.abs(delta))
	end

	emitter:Fire(notification)
	return notification.id
end

return HudStatNotificationService
