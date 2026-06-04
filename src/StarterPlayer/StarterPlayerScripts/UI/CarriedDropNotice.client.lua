local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local CarriedDropNotice = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CarriedDropNotice"))

local BATCH_WINDOW_SECONDS = 0.18
local REMOTE_WAIT_TIMEOUT_SECONDS = 30

local pendingByKey = {}
local flushScheduled = false

local function showNotification(notice)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = notice.Title or CarriedDropNotice.Title,
			Text = notice.Text or CarriedDropNotice.GetMessage(notice.ReasonCode),
			Duration = notice.Duration or CarriedDropNotice.Duration,
		})
	end)
end

local function flushPending()
	flushScheduled = false
	local pending = pendingByKey
	pendingByKey = {}

	for _, notice in pairs(pending) do
		showNotification(notice)
	end
end

local function queueNotice(payload)
	local notice = CarriedDropNotice.BuildPayload(payload)
	if notice.SuppressToast == true then
		return
	end

	local key = string.format("%s|%s", notice.ReasonCode, notice.Text)
	local pending = pendingByKey[key]
	if pending then
		pending.Count += notice.Count
	else
		pendingByKey[key] = notice
	end

	if not flushScheduled then
		flushScheduled = true
		task.delay(BATCH_WINDOW_SECONDS, flushPending)
	end
end

local remote = CarriedDropNotice.GetRemote(REMOTE_WAIT_TIMEOUT_SECONDS)
if remote then
	remote.OnClientEvent:Connect(queueNotice)
end
