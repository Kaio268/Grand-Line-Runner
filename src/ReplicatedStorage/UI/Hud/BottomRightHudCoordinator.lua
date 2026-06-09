local BottomRightHudCoordinator = {}

local reservations = {}
local subscribers = {}
local lastSignature = ""

local function normalizeRect(rect)
	if typeof(rect) ~= "table" then
		return nil
	end

	local x = tonumber(rect.x)
	local y = tonumber(rect.y)
	local width = tonumber(rect.width)
	local height = tonumber(rect.height)
	if not (x and y and width and height) then
		return nil
	end

	return {
		x = x,
		y = y,
		width = math.max(0, width),
		height = math.max(0, height),
	}
end

local function cloneReservation(reservation)
	if typeof(reservation) ~= "table" then
		return nil
	end

	local rect = normalizeRect(reservation.Rect or reservation.rect)
	if not rect then
		return nil
	end

	return {
		Key = tostring(reservation.Key or reservation.key or ""),
		Rect = rect,
		Padding = math.max(0, tonumber(reservation.Padding or reservation.padding) or 12),
		Priority = tonumber(reservation.Priority or reservation.priority) or 0,
		Source = reservation.Source or reservation.source,
	}
end

local function getReservationSignature(reservation)
	if not reservation then
		return ""
	end

	local rect = reservation.Rect
	return string.format(
		"%s:%.0f:%.0f:%.0f:%.0f:%.0f:%.0f:%s",
		tostring(reservation.Key),
		tonumber(reservation.Priority) or 0,
		tonumber(reservation.Padding) or 0,
		tonumber(rect and rect.x) or 0,
		tonumber(rect and rect.y) or 0,
		tonumber(rect and rect.width) or 0,
		tonumber(rect and rect.height) or 0,
		tostring(reservation.Source or "")
	)
end

local function selectActiveReservation()
	local active = nil
	for key, reservation in pairs(reservations) do
		local candidate = cloneReservation(reservation)
		if candidate then
			candidate.Key = key
			local activeRect = active and active.Rect or nil
			local candidateRect = candidate.Rect
			local candidatePriority = tonumber(candidate.Priority) or 0
			local activePriority = tonumber(active and active.Priority) or -math.huge
			local candidateHeight = tonumber(candidateRect and candidateRect.height) or 0
			local activeHeight = tonumber(activeRect and activeRect.height) or 0

			if
				not active
				or candidatePriority > activePriority
				or (candidatePriority == activePriority and candidateHeight > activeHeight)
			then
				active = candidate
			end
		end
	end

	return active
end

local function notifyIfChanged()
	local active = selectActiveReservation()
	local signature = getReservationSignature(active)
	if signature == lastSignature then
		return
	end

	lastSignature = signature
	for callback in pairs(subscribers) do
		task.defer(callback, cloneReservation(active))
	end
end

function BottomRightHudCoordinator.SetReservation(key, reservation)
	key = tostring(key or "")
	if key == "" then
		return
	end

	if typeof(reservation) ~= "table" or reservation.Visible == false then
		reservations[key] = nil
		notifyIfChanged()
		return
	end

	local normalized = cloneReservation(reservation)
	if not normalized then
		reservations[key] = nil
		notifyIfChanged()
		return
	end

	normalized.Key = key
	reservations[key] = normalized
	notifyIfChanged()
end

function BottomRightHudCoordinator.ClearReservation(key)
	key = tostring(key or "")
	if key == "" then
		return
	end

	if reservations[key] == nil then
		return
	end

	reservations[key] = nil
	notifyIfChanged()
end

function BottomRightHudCoordinator.GetActiveReservation()
	return cloneReservation(selectActiveReservation())
end

function BottomRightHudCoordinator.GetReservation(key)
	key = tostring(key or "")
	if key == "" then
		return nil
	end

	return cloneReservation(reservations[key])
end

function BottomRightHudCoordinator.HasReservation(key)
	return BottomRightHudCoordinator.GetReservation(key) ~= nil
end

function BottomRightHudCoordinator.Subscribe(callback)
	if typeof(callback) ~= "function" then
		return nil
	end

	subscribers[callback] = true
	return {
		Disconnect = function()
			subscribers[callback] = nil
		end,
	}
end

return BottomRightHudCoordinator
