local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local TimeRewardsFolder = Modules:WaitForChild("TimeRewards")

local RewardsConfig = require(TimeRewardsFolder:WaitForChild("Config"))
local Remote = TimeRewardsFolder:WaitForChild("TimeRewardEvent")
local Shorten = require(Modules:WaitForChild("Shorten"))

local player = Players.LocalPlayer
local guiRoot = player:WaitForChild("PlayerGui")
local mainGui = guiRoot:WaitForChild("Frames")
local giftsFrame = mainGui:WaitForChild("Gifts")
local giftsMainFrame = giftsFrame:WaitForChild("Main")

local hudFrame = guiRoot:WaitForChild("HUD")
local lButtons = hudFrame:WaitForChild("LButtons")
local hudGifts = lButtons:WaitForChild("Gifts")
local hudTimer = hudGifts:WaitForChild("Timer")
local hudTimer2 = hudTimer:WaitForChild("Timer2")
local hudNot = hudGifts:WaitForChild("Not")
local hudNotText = hudNot:WaitForChild("TextLB")

local READY_TEXT = "Claim"
local CLAIMED_TEXT = "Claimed"
local WHITE_COLOR = Color3.new(1, 1, 1)
local GREEN_COLOR = Color3.new(0, 1, 0)

local endTimes = {}
local threads = {}
local slotsById = {}
local orderedIds = {}
local totalGifts = 0

local DEBUG = false
local function dprint(...)
	if DEBUG then
		print("[TimeRewardsClient]", ...)
	end
end
local function dwarn(...)
	warn("[TimeRewardsClient]", ...)
end

local function safeName(inst)
	if not inst then
		return "nil"
	end
	local ok, full = pcall(function()
		return inst:GetFullName()
	end)
	return ok and full or tostring(inst)
end

local function isSlotFrame(obj: Instance)
	if not obj:IsA("GuiObject") then
		return false
	end
	if obj == giftsMainFrame then
		return false
	end
	local rn = obj:FindFirstChild("RewName", true)
	local tm = obj:FindFirstChild("Timer", true)
	local ic = obj:FindFirstChild("Icon", true)
	return rn ~= nil and tm ~= nil and ic ~= nil
end

local function getDepthFromRoot(obj: Instance, root: Instance)
	local depth = 0
	local cur = obj
	while cur and cur ~= root do
		cur = cur.Parent
		depth += 1
	end
	if cur ~= root then
		return math.huge
	end
	return depth
end

local function getClaimButton(slotFrame: Instance)
	if slotFrame:IsA("GuiButton") then
		return slotFrame
	end
	for _, d in ipairs(slotFrame:GetDescendants()) do
		if d:IsA("GuiButton") then
			return d
		end
	end
	return nil
end

local function findTextObj(slotFrame: Instance, name: string)
	local obj = slotFrame:FindFirstChild(name, true)
	if obj and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
		return obj
	end
	return nil
end

local function findImageObj(slotFrame: Instance, name: string)
	local obj = slotFrame:FindFirstChild(name, true)
	if obj and (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) then
		return obj
	end
	return nil
end

local function setRewData(slotFrame: Instance, cfg)
	if not cfg then
		dwarn("Missing cfg for slot", safeName(slotFrame))
		return
	end

	local rewNameObj = findTextObj(slotFrame, "RewName")
	if rewNameObj then
		rewNameObj.Text = tostring(cfg.RewName or "")
	else
		dwarn("Missing RewName (anywhere) in", safeName(slotFrame))
	end

	local iconObj = findImageObj(slotFrame, "Icon")
	if iconObj then
		if cfg.Icon ~= nil then
			iconObj.Image = tostring(cfg.Icon)
		else
			dwarn("cfg.Icon is nil for id", slotFrame:GetAttribute("RewardId"))
		end
	else
		dwarn("Missing Icon (anywhere) in", safeName(slotFrame))
	end
end

local function setTimerText(slotFrame: Instance, text: string, color: Color3)
	local timerObj = findTextObj(slotFrame, "Timer")
	if timerObj then
		timerObj.Text = text
		timerObj.TextColor3 = color
	else
		dwarn("Missing Timer (anywhere) in", safeName(slotFrame))
	end
end

local function setTimerCountdown(slotFrame: Instance, text: string)
	setTimerText(slotFrame, text, WHITE_COLOR)
end

local function setTimerReady(slotFrame: Instance)
	setTimerText(slotFrame, READY_TEXT, WHITE_COLOR)
end

local function setTimerClaimed(slotFrame: Instance)
	setTimerText(slotFrame, CLAIMED_TEXT, GREEN_COLOR)
end

local function stopCountdown(id: number)
	local th = threads[id]
	if th then
		task.cancel(th)
		threads[id] = nil
	end
end

local function updateHud()
	if totalGifts <= 0 then
		hudNot.Visible = false
		if hudTimer:IsA("TextLabel") or hudTimer:IsA("TextButton") or hudTimer:IsA("TextBox") then
			hudTimer.Text = "--"
		end
		if hudTimer2:IsA("TextLabel") or hudTimer2:IsA("TextButton") or hudTimer2:IsA("TextBox") then
			hudTimer2.Text = "--"
		end
		return
	end

	local now = os.clock()
	local readyCount = 0
	local minRemaining = nil

	for i = 1, totalGifts do
		local id = orderedIds[i]
		local slotFrame = slotsById[id]
		if slotFrame and slotFrame.Parent and not slotFrame:GetAttribute("Claimed") then
			local et = endTimes[id]
			if et then
				local rem = et - now
				if rem <= 0 then
					readyCount += 1
				else
					if minRemaining == nil or rem < minRemaining then
						minRemaining = rem
					end
				end
			end
		end
	end

	hudNot.Visible = readyCount > 0
	if readyCount > 0 then
		if hudNotText:IsA("TextLabel") or hudNotText:IsA("TextButton") or hudNotText:IsA("TextBox") then
			hudNotText.Text = tostring(readyCount)
		end
	end

	local text
	if readyCount > 0 then
		text = READY_TEXT
	else
		if minRemaining == nil then
			text = "--"
		else
			local secs = math.max(0, math.ceil(minRemaining))
			local ok, t = pcall(function()
				return Shorten.timeSuffixTwo(secs)
			end)
			text = ok and t or (tostring(secs) .. "s")
		end
	end

	if hudTimer:IsA("TextLabel") or hudTimer:IsA("TextButton") or hudTimer:IsA("TextBox") then
		hudTimer.Text = text
	end
	if hudTimer2:IsA("TextLabel") or hudTimer2:IsA("TextButton") or hudTimer2:IsA("TextBox") then
		hudTimer2.Text = text
	end
end

local function startCountdown(id: number)
	stopCountdown(id)

	local slotFrame = slotsById[id]
	if not slotFrame then
		dwarn("startCountdown: no slotFrame for id", id)
		return
	end

	threads[id] = task.spawn(function()
		while true do
			if not slotFrame.Parent then
				return
			end
			if slotFrame:GetAttribute("Claimed") then
				return
			end

			local endTime = endTimes[id]
			if not endTime then
				return
			end

			local remaining = math.max(0, math.ceil(endTime - os.clock()))
			if remaining <= 0 then
				setTimerReady(slotFrame)
				updateHud()
				return
			end

			local ok, txt = pcall(function()
				return Shorten.timeSuffixTwo(remaining)
			end)
			if ok then
				setTimerCountdown(slotFrame, txt)
			else
				setTimerCountdown(slotFrame, tostring(remaining) .. "s")
			end

			RunService.Heartbeat:Wait()
		end
	end)
end

local function hookButton(id: number)
	local slotFrame = slotsById[id]
	if not slotFrame then
		dwarn("hookButton: no slotFrame for id", id)
		return
	end
	if slotFrame:GetAttribute("Hooked") then
		return
	end

	local claimBtn = getClaimButton(slotFrame)
	if not claimBtn then
		dwarn("hookButton: no GuiButton inside", safeName(slotFrame), "for id", id)
		return
	end

	slotFrame:SetAttribute("Hooked", true)

	claimBtn.MouseButton1Click:Connect(function()
		if slotFrame:GetAttribute("Claimed") then
			return
		end
		Remote:FireServer(id)
	end)
end

local function collectSlotFrames()
	local candidates = {}
	for _, inst in ipairs(giftsMainFrame:GetDescendants()) do
		if isSlotFrame(inst) then
			table.insert(candidates, inst)
		end
	end

	table.sort(candidates, function(a, b)
		return getDepthFromRoot(a, giftsMainFrame) < getDepthFromRoot(b, giftsMainFrame)
	end)

	local candSet = {}
	for _, c in ipairs(candidates) do
		candSet[c] = true
	end

	local top = {}
	for _, c in ipairs(candidates) do
		local p = c.Parent
		local nested = false
		while p and p ~= giftsMainFrame do
			if candSet[p] then
				nested = true
				break
			end
			p = p.Parent
		end
		if not nested then
			table.insert(top, c)
		end
	end

	table.sort(top, function(a, b)
		local la = a.LayoutOrder or 0
		local lb = b.LayoutOrder or 0
		if la ~= lb then
			return la < lb
		end
		return a.Name < b.Name
	end)

	return top
end

local function buildSlotsOnce()
	table.clear(orderedIds)
	for id in pairs(RewardsConfig) do
		table.insert(orderedIds, id)
	end
	table.sort(orderedIds, function(a, b)
		return a < b
	end)

	local templates = collectSlotFrames()
	totalGifts = math.min(#orderedIds, #templates)
	table.clear(slotsById)

	for i = 1, totalGifts do
		local id = orderedIds[i]
		local slotFrame = templates[i]

		slotsById[id] = slotFrame
		slotFrame.Visible = true
		slotFrame:SetAttribute("RewardId", id)
		slotFrame:SetAttribute("Claimed", false)
		slotFrame:SetAttribute("Hooked", false)

		setRewData(slotFrame, RewardsConfig[id])
		setTimerCountdown(slotFrame, "--")
		hookButton(id)
	end

	updateHud()
end

local function buildSlotsWithWait()
	for _ = 1, 50 do
		buildSlotsOnce()
		if totalGifts > 0 then
			return true
		end
		task.wait(0.2)
	end
	dwarn("No slot frames found after waiting.")
	return false
end

local function normalizeClaimedRewards(rawClaimedRewards)
	local claimedRewards = {}
	if typeof(rawClaimedRewards) ~= "table" then
		return claimedRewards
	end

	for rawKey, rawValue in pairs(rawClaimedRewards) do
		local id = tonumber(rawKey)
		if id and rawValue == true then
			claimedRewards[tostring(id)] = true
		end
	end

	return claimedRewards
end

local function initialiseButtonsFromLegacyEpoch(serverStartEpoch: number)
	for i = 1, totalGifts do
		local id = orderedIds[i]
		local cfg = RewardsConfig[id]
		local slotFrame = slotsById[id]

		if slotFrame and cfg then
			stopCountdown(id)
			slotFrame:SetAttribute("Claimed", false)
			setRewData(slotFrame, cfg)

			if cfg.Time == nil then
				setTimerCountdown(slotFrame, "ERR")
			else
				local elapsed = os.time() - serverStartEpoch
				local remaining = math.max(0, cfg.Time - elapsed)
				endTimes[id] = os.clock() + remaining

				if remaining > 0 then
					setTimerCountdown(slotFrame, Shorten.timeSuffixTwo(remaining))
					startCountdown(id)
				else
					setTimerReady(slotFrame)
				end
			end
		end
	end

	updateHud()
end

local function initialiseButtonsFromState(syncState)
	if typeof(syncState) ~= "table" then
		dwarn("syncState payload must be a table, got", typeof(syncState))
		return
	end

	local cycleStartPlayTime = tonumber(syncState.CycleStartPlayTime)
	local currentPlayTime = tonumber(syncState.CurrentPlayTime)
	if not cycleStartPlayTime or not currentPlayTime then
		dwarn("syncState missing play time fields", syncState)
		return
	end

	local claimedRewards = normalizeClaimedRewards(syncState.ClaimedRewards)
	local elapsedPlayTime = math.max(0, currentPlayTime - cycleStartPlayTime)

	for i = 1, totalGifts do
		local id = orderedIds[i]
		local cfg = RewardsConfig[id]
		local slotFrame = slotsById[id]

		if slotFrame and cfg then
			stopCountdown(id)
			setRewData(slotFrame, cfg)

			local claimed = claimedRewards[tostring(id)] == true
			slotFrame:SetAttribute("Claimed", claimed)

			if claimed then
				endTimes[id] = nil
				setTimerClaimed(slotFrame)
			elseif cfg.Time == nil then
				setTimerCountdown(slotFrame, "ERR")
			else
				local remaining = math.max(0, cfg.Time - elapsedPlayTime)
				endTimes[id] = os.clock() + remaining

				if remaining > 0 then
					setTimerCountdown(slotFrame, Shorten.timeSuffixTwo(remaining))
					startCountdown(id)
				else
					setTimerReady(slotFrame)
				end
			end
		end
	end

	updateHud()
end

local building = false
local pendingState = nil

local function applyPendingState()
	if pendingState == nil then
		return
	end

	local state = pendingState
	pendingState = nil

	if typeof(state) == "table" then
		initialiseButtonsFromState(state)
	elseif typeof(state) == "number" then
		initialiseButtonsFromLegacyEpoch(state)
	else
		dwarn("Unsupported pending time reward state", typeof(state))
	end
end

task.spawn(function()
	building = true
	local ok = buildSlotsWithWait()
	building = false
	if ok then
		applyPendingState()
	end
end)

task.spawn(function()
	while true do
		updateHud()
		RunService.Heartbeat:Wait()
	end
end)

Remote.OnClientEvent:Connect(function(action, a, b, c)
	if action == "syncState" then
		if totalGifts == 0 then
			pendingState = a
			if not building then
				task.spawn(function()
					building = true
					local ok = buildSlotsWithWait()
					building = false
					if ok then
						applyPendingState()
					end
				end)
			end
			return
		end
		initialiseButtonsFromState(a)

	elseif action == "startCycle" or action == "cycleReset" then
		if typeof(a) ~= "number" then
			dwarn("startCycle/cycleReset bad epoch:", a, "typeof:", typeof(a))
			return
		end
		if totalGifts == 0 then
			pendingState = a
			if not building then
				task.spawn(function()
					building = true
					local ok = buildSlotsWithWait()
					building = false
					if ok then
						applyPendingState()
					end
				end)
			end
			return
		end
		initialiseButtonsFromLegacyEpoch(a)

	elseif action == "forceReady" then
		for i = 1, totalGifts do
			local id = orderedIds[i]
			local slotFrame = slotsById[id]
			if slotFrame and not slotFrame:GetAttribute("Claimed") then
				endTimes[id] = os.clock()
				stopCountdown(id)
				setTimerReady(slotFrame)
			end
		end
		updateHud()

	elseif action == "claimed" then
		local id = a
		local slotFrame = slotsById[id]
		if not slotFrame then
			dwarn("claimed: no slotFrame for id", id)
			return
		end
		slotFrame:SetAttribute("Claimed", true)
		stopCountdown(id)
		setTimerClaimed(slotFrame)
		updateHud()

	elseif action == "notReady" then
		local id = tonumber(a)
		local remaining = tonumber(b)
		local slotFrame = id and slotsById[id]
		if slotFrame and not slotFrame:GetAttribute("Claimed") and remaining then
			local clampedRemaining = math.max(0, math.ceil(remaining))
			endTimes[id] = os.clock() + clampedRemaining
			stopCountdown(id)
			if clampedRemaining > 0 then
				local ok, text = pcall(function()
					return Shorten.timeSuffixTwo(clampedRemaining)
				end)
				setTimerCountdown(slotFrame, ok and text or (tostring(clampedRemaining) .. "s"))
				startCountdown(id)
			else
				setTimerReady(slotFrame)
			end
		end
		updateHud()

	elseif action == "alreadyClaimed" then
		updateHud()

	else
		dwarn("Unknown action:", action)
	end
end)

return {}
