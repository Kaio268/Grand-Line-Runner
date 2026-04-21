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
local timerLogStateByPath = {}

local GIFT_DEBUG = false

local function giftLog(tag: string, ...)
	if GIFT_DEBUG then
		print(tag, ...)
	end
end

local function giftError(...)
	warn("[GIFT][ERROR]", ...)
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

local function getGiftsSlotContainer()
	local scroll = giftsMainFrame:FindFirstChild("Scroll")
	if scroll and scroll:IsA("ScrollingFrame") then
		return scroll
	end
	if giftsMainFrame:IsA("ScrollingFrame") then
		return giftsMainFrame
	end
	return giftsMainFrame
end

local function getGiftsListLayout(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("UIListLayout") then
			return child
		end
	end
	return nil
end

local function formatRewardIdList(ids): string
	if #ids == 0 then
		return "none"
	end

	local values = table.create(#ids)
	for index, rewardId in ipairs(ids) do
		values[index] = tostring(rewardId)
	end
	return table.concat(values, ",")
end

local function logScrollState(context: string)
	local container = getGiftsSlotContainer()
	local layout = getGiftsListLayout(container)
	local slotCount = 0
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and string.match(child.Name, "^Slot%d+$") then
			slotCount += 1
		end
	end

	giftLog(
		"[GIFT][SCROLL]",
		string.format(
			"context=%s main=%s container=%s class=%s scrollingEnabled=%s active=%s canvasSize=%s automaticCanvasSize=%s clipsDescendants=%s layoutContentSize=%s slotCount=%d",
			context,
			safeName(giftsMainFrame),
			safeName(container),
			container.ClassName,
			tostring(container:IsA("ScrollingFrame") and container.ScrollingEnabled or false),
			tostring(container:IsA("GuiObject") and container.Active or false),
			tostring(container:IsA("ScrollingFrame") and container.CanvasSize or "n/a"),
			tostring(container:IsA("ScrollingFrame") and container.AutomaticCanvasSize or "n/a"),
			tostring(container:IsA("GuiObject") and container.ClipsDescendants or false),
			tostring(layout and layout.AbsoluteContentSize or "nil"),
			slotCount
		)
	)
end

giftLog(
	"[GIFT][BOOT]",
	string.format("module=%s giftsFrame=%s hud=%s", safeName(script), safeName(giftsFrame), safeName(hudFrame))
)

local function isTextGuiObject(obj: Instance?): boolean
	return obj ~= nil and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
end

local function isImageGuiObject(obj: Instance?): boolean
	return obj ~= nil and (obj:IsA("ImageLabel") or obj:IsA("ImageButton"))
end

local function getDirectTextObj(parent: Instance, name: string)
	local obj = parent:FindFirstChild(name)
	if isTextGuiObject(obj) then
		return obj
	end
	return nil
end

local function getDirectImageObj(parent: Instance, name: string)
	local obj = parent:FindFirstChild(name)
	if isImageGuiObject(obj) then
		return obj
	end
	return nil
end

local function getGiftSummaryTimer()
	local summary = hudGifts:FindFirstChild("GiftSummaryTimer")
	if isTextGuiObject(summary) then
		return summary
	end
	return nil
end

local function ensureGiftSummaryTimer()
	for _, child in ipairs(lButtons:GetChildren()) do
		if child:IsA("GuiObject") and child ~= hudGifts then
			local wrongTimer = child:FindFirstChild("Timer")
			if wrongTimer and wrongTimer:IsA("GuiObject") then
				wrongTimer:Destroy()
			end
			local wrongTimer2 = child:FindFirstChild("Timer2")
			if wrongTimer2 and wrongTimer2:IsA("GuiObject") then
				wrongTimer2:Destroy()
			end
			local misplaced = child:FindFirstChild("GiftSummaryTimer")
			if misplaced and misplaced:IsA("GuiObject") then
				misplaced:Destroy()
			end
		end
	end

	local giftsWrongTimer = hudGifts:FindFirstChild("Timer")
	if giftsWrongTimer and giftsWrongTimer:IsA("GuiObject") then
		giftsWrongTimer:Destroy()
	end
	local giftsWrongTimer2 = hudGifts:FindFirstChild("Timer2")
	if giftsWrongTimer2 and giftsWrongTimer2:IsA("GuiObject") then
		giftsWrongTimer2:Destroy()
	end

	local summary = hudGifts:FindFirstChild("GiftSummaryTimer")
	if summary and not isTextGuiObject(summary) then
		summary:Destroy()
		summary = nil
	end

	if not summary then
		summary = Instance.new("TextLabel")
		summary.Name = "GiftSummaryTimer"
		summary.Parent = hudGifts
	end

	summary.Visible = true
	summary.AnchorPoint = Vector2.new(0.5, 0)
	summary.BackgroundColor3 = Color3.fromRGB(7, 14, 24)
	summary.BackgroundTransparency = 0.16
	summary.BorderSizePixel = 0
	summary.Font = Enum.Font.GothamBold
	summary.Position = UDim2.new(0.5, 0, 0, 4)
	summary.Size = UDim2.fromOffset(60, 18)
	summary.TextColor3 = Color3.fromRGB(255, 255, 255)
	summary.TextScaled = false
	summary.TextSize = 13
	summary.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	summary.TextStrokeTransparency = 0
	summary.TextTransparency = 0
	summary.TextXAlignment = Enum.TextXAlignment.Center
	summary.TextYAlignment = Enum.TextYAlignment.Center
	summary.ZIndex = math.max(summary.ZIndex, 300)

	local corner = summary:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = summary
	end
	corner.CornerRadius = UDim.new(0, 9)

	local stroke = summary:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = summary
	end
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(255, 237, 203)
	stroke.Transparency = 0.6
	stroke.Thickness = 1
	stroke.Enabled = true

	local gradient = summary:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = summary
	end
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(29, 39, 57)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 13, 22)),
	})
	gradient.Rotation = 90
	gradient.Enabled = false

	return summary
end

local function auditSidebarTimers(context: string)
	for _, child in ipairs(lButtons:GetChildren()) do
		if child:IsA("GuiObject") then
			local timer = child:FindFirstChild("Timer")
			if timer and timer:IsA("GuiObject") then
				giftError(
					"Sidebar timer target detected",
					"context",
					context,
					"button",
					safeName(child),
					"timer",
					safeName(timer)
				)
				giftLog(
					"[HUD][TIMER]",
					string.format(
						"context=%s button=%s timer=%s visible=%s belongsToGiftsButton=%s validTarget=false",
						context,
						safeName(child),
						safeName(timer),
						tostring(timer.Visible),
						tostring(child == hudGifts)
					)
				)
			end

			local summary = child:FindFirstChild("GiftSummaryTimer")
			if summary and summary:IsA("GuiObject") then
				if child ~= hudGifts then
					giftError(
						"Non-Gifts summary timer target detected",
						"context",
						context,
						"button",
						safeName(child),
						"summary",
						safeName(summary)
					)
					giftLog(
						"[GIFT][SUMMARY]",
						string.format(
							"context=%s button=%s summary=%s validTarget=false",
							context,
							safeName(child),
							safeName(summary)
						)
					)
				else
					giftLog(
						"[GIFT][SUMMARY]",
						string.format(
							"context=%s button=%s summary=%s validTarget=true visible=%s",
							context,
							safeName(child),
							safeName(summary),
							tostring(summary.Visible)
						)
					)
				end
			end
		end
	end
end

local function isSlotFrame(obj: Instance)
	if not obj:IsA("GuiObject") then
		return false
	end
	if obj.Parent ~= getGiftsSlotContainer() then
		return false
	end
	return getDirectTextObj(obj, "RewName") ~= nil
		and getDirectTextObj(obj, "Timer") ~= nil
		and getDirectImageObj(obj, "Icon") ~= nil
end

local function getClaimButton(slotFrame: Instance)
	local directButton = slotFrame:FindFirstChild("ClaimButton")
	if directButton and directButton:IsA("GuiButton") then
		return directButton
	end

	if slotFrame:IsA("GuiButton") then
		return slotFrame
	end

	local firstButton = nil
	for _, d in ipairs(slotFrame:GetDescendants()) do
		if d.Name == "ClaimButton" and d:IsA("GuiButton") then
			return d
		end
		if not firstButton and d:IsA("GuiButton") then
			firstButton = d
		end
	end
	return firstButton
end

local function logHudBinding()
	giftLog(
		"[GIFT][BIND]",
		string.format(
			"hudButton=%s badge=%s badgeText=%s summaryTimer=%s",
			safeName(hudGifts),
			safeName(hudNot),
			safeName(hudNotText),
			safeName(getGiftSummaryTimer())
		)
	)
	auditSidebarTimers("bind")
	logScrollState("bind")
end

local function setRewData(slotFrame: Instance, cfg)
	if not cfg then
		giftError("Missing reward config for slot", safeName(slotFrame))
		return
	end

	local rewNameObj = getDirectTextObj(slotFrame, "RewName")
	local titleAssigned = false
	if rewNameObj then
		rewNameObj.Text = tostring(cfg.RewName or "")
		titleAssigned = true
	else
		giftError("Missing RewName label in", safeName(slotFrame))
	end

	local iconObj = getDirectImageObj(slotFrame, "Icon")
	local iconAssigned = false
	if iconObj then
		if cfg.Icon ~= nil then
			iconObj.Image = tostring(cfg.Icon)
			iconAssigned = true
		else
			giftError("Reward icon is nil for id", slotFrame:GetAttribute("RewardId"))
		end
	else
		giftError("Missing Icon image in", safeName(slotFrame))
	end

	giftLog(
		"[GIFT][ROW]",
		string.format(
			"slot=%s rewardId=%s rewardName=%s titleAssigned=%s iconAssigned=%s",
			safeName(slotFrame),
			tostring(slotFrame:GetAttribute("RewardId")),
			tostring(cfg.RewName or ""),
			tostring(titleAssigned),
			tostring(iconAssigned)
		)
	)
end

local function setTimerText(slotFrame: Instance, text: string, color: Color3)
	local rewardId = slotFrame:GetAttribute("RewardId")
	if not isSlotFrame(slotFrame) then
		giftError("Refused to write timer outside Gifts row", safeName(slotFrame), "rewardId", rewardId)
		giftLog(
			"[GIFT][TIMER]",
			string.format(
				"rewardId=%s row=%s timer=nil text=%s belongsToGifts=false fallbackUsed=false",
				tostring(rewardId),
				safeName(slotFrame),
				text
			)
		)
		return
	end

	local timerObj = getDirectTextObj(slotFrame, "Timer")
	if timerObj then
		timerObj.Text = text
		timerObj.TextColor3 = color
		local timerPath = safeName(timerObj)
		local stateKey = string.format("%s|%s|%s", tostring(rewardId), text, tostring(color))
		if timerLogStateByPath[timerPath] ~= stateKey then
			timerLogStateByPath[timerPath] = stateKey
			giftLog(
				"[GIFT][TIMER]",
				string.format(
					"rewardId=%s row=%s timer=%s text=%s belongsToGifts=true fallbackUsed=false",
					tostring(rewardId),
					safeName(slotFrame),
					timerPath,
					text
				)
			)
		end
	else
		giftError("Missing direct Timer label in", safeName(slotFrame))
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

local summaryLogState = nil
local badgeLogState = nil
local formatDurationText

local function setSummaryTimer(text: string, nextRewardId: number?, nextRemaining: number?, readyCount: number)
	local summary = ensureGiftSummaryTimer()

	summary.Visible = true
	summary.Text = tostring(text ~= nil and text ~= "" and text or "--")
	summary.TextColor3 = Color3.fromRGB(255, 255, 255)
	summary.TextTransparency = 0
	summary.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	summary.TextStrokeTransparency = 0
	summary.ZIndex = math.max(summary.ZIndex, 40)

	local remainingText = nextRemaining ~= nil and formatDurationText(nextRemaining) or "nil"
	local stateKey = string.format("%s|%s|%s|%s", text, tostring(nextRewardId), remainingText, tostring(readyCount))
	if summaryLogState ~= stateKey then
		summaryLogState = stateKey
		giftLog(
			"[GIFT][SUMMARY]",
			string.format(
				"nextRewardId=%s nextRemaining=%s readyCount=%s summary=%s text=%s",
				tostring(nextRewardId),
				remainingText,
				tostring(readyCount),
				safeName(summary),
				text
			)
		)
	end
end

formatDurationText = function(seconds: number): string
	local clampedSeconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	local ok, formattedText = pcall(function()
		return Shorten.timeSuffixTwo(clampedSeconds)
	end)
	if ok then
		return formattedText
	end
	return tostring(clampedSeconds) .. "s"
end

local function evaluateHudState()
	local now = os.clock()
	local readyCount = 0
	local readyIds = {}
	local nextRewardId = nil
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
					table.insert(readyIds, id)
					if nextRewardId == nil then
						nextRewardId = id
						minRemaining = 0
					end
				elseif minRemaining == nil or rem < minRemaining then
					minRemaining = rem
					nextRewardId = id
				end
			end
		end
	end

	return {
		readyCount = readyCount,
		readyIds = readyIds,
		nextRewardId = nextRewardId,
		minRemaining = minRemaining,
	}
end

local function logBadgeState(hudState)
	local nextRemainingText = hudState.minRemaining ~= nil and formatDurationText(hudState.minRemaining) or "nil"
	local reason = "allMappedRewardsClaimed"
	if hudState.readyCount > 0 then
		reason = "claimableRewardIds=" .. formatRewardIdList(hudState.readyIds)
	elseif hudState.nextRewardId ~= nil then
		reason = "nextRewardId=" .. tostring(hudState.nextRewardId)
	end

	local stateKey = string.format(
		"%d|%s|%s|%s",
		hudState.readyCount,
		formatRewardIdList(hudState.readyIds),
		tostring(hudState.nextRewardId),
		nextRemainingText
	)
	if badgeLogState ~= stateKey then
		badgeLogState = stateKey
		giftLog(
			"[GIFT][BADGE]",
			string.format(
				"badge=%s badgeText=%s readyCount=%d claimableRewardIds=%s nextRewardId=%s nextRemaining=%s reason=%s",
				safeName(hudNot),
				safeName(hudNotText),
				hudState.readyCount,
				formatRewardIdList(hudState.readyIds),
				tostring(hudState.nextRewardId),
				nextRemainingText,
				reason
			)
		)
	end
end

local function getClaimedCount(rawClaimedRewards): number
	local count = 0
	if typeof(rawClaimedRewards) ~= "table" then
		return count
	end

	for _, claimed in pairs(rawClaimedRewards) do
		if claimed == true then
			count += 1
		end
	end

	return count
end

local function summarizeRewardEntries(cfg): string
	if typeof(cfg) ~= "table" or typeof(cfg.Rewards) ~= "table" then
		return "none"
	end

	local rewardNames = {}
	for rewardName in pairs(cfg.Rewards) do
		table.insert(rewardNames, tostring(rewardName))
	end
	table.sort(rewardNames)

	return table.concat(rewardNames, ",")
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
		if isTextGuiObject(hudNotText) then
			hudNotText.Text = "0"
		end
		setSummaryTimer("--", nil, nil, 0)
		return
	end

	local hudState = evaluateHudState()

	hudNot.Visible = hudState.readyCount > 0
	if isTextGuiObject(hudNotText) then
		hudNotText.Text = tostring(hudState.readyCount)
	end
	logBadgeState(hudState)

	if hudState.readyCount > 0 then
		setSummaryTimer(READY_TEXT, hudState.nextRewardId, 0, hudState.readyCount)
	elseif hudState.minRemaining ~= nil then
		setSummaryTimer(
			formatDurationText(hudState.minRemaining),
			hudState.nextRewardId,
			hudState.minRemaining,
			hudState.readyCount
		)
	else
		setSummaryTimer("--", nil, nil, hudState.readyCount)
	end
end

local function startCountdown(id: number)
	stopCountdown(id)

	local slotFrame = slotsById[id]
	if not slotFrame then
		giftError("startCountdown missing slot frame for id", id)
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

			setTimerCountdown(slotFrame, formatDurationText(remaining))
			RunService.Heartbeat:Wait()
		end
	end)
end

local function hookButton(id: number)
	local slotFrame = slotsById[id]
	if not slotFrame then
		giftError("hookButton missing slot frame for id", id)
		return
	end
	if slotFrame:GetAttribute("Hooked") then
		return
	end

	local claimBtn = getClaimButton(slotFrame)
	if not claimBtn then
		giftError("hookButton missing claim button in", safeName(slotFrame), "for id", id)
		return
	end

	slotFrame:SetAttribute("Hooked", true)

	claimBtn.Activated:Connect(function()
		if slotFrame:GetAttribute("Claimed") then
			return
		end
		Remote:FireServer(id)
	end)
end

local function collectSlotFrames()
	local candidates = {}
	local slotContainer = getGiftsSlotContainer()
	for _, inst in ipairs(slotContainer:GetChildren()) do
		if isSlotFrame(inst) then
			table.insert(candidates, inst)
		end
	end

	table.sort(candidates, function(a, b)
		local la = a.LayoutOrder or 0
		local lb = b.LayoutOrder or 0
		if la ~= lb then
			return la < lb
		end
		return a.Name < b.Name
	end)

	return candidates
end

local function buildSlotsOnce()
	table.clear(orderedIds)
	for id in pairs(RewardsConfig) do
		table.insert(orderedIds, id)
	end
	table.sort(orderedIds, function(a, b)
		return a < b
	end)

	logScrollState("buildSlots")

	local templates = collectSlotFrames()
	totalGifts = math.min(#orderedIds, #templates)
	table.clear(slotsById)

	giftLog(
		"[GIFT][DATA]",
		string.format(
			"slotTemplates=%d configRewards=%d renderable=%d slotContainer=%s",
			#templates,
			#orderedIds,
			totalGifts,
			safeName(getGiftsSlotContainer())
		)
	)
	auditSidebarTimers("rowmap")

	for i = 1, totalGifts do
		local id = orderedIds[i]
		local slotFrame = templates[i]
		local cfg = RewardsConfig[id]
		local rowTimer = getDirectTextObj(slotFrame, "Timer")
		local rowTitle = getDirectTextObj(slotFrame, "RewName")

		slotsById[id] = slotFrame
		slotFrame.Visible = true
		slotFrame:SetAttribute("RewardId", id)
		slotFrame:SetAttribute("Claimed", false)
		slotFrame:SetAttribute("Hooked", false)

		giftLog(
			"[GIFT][ROWMAP]",
			string.format(
				"mapped rewardId=%d slot=%s rowName=%s timer=%s title=%s rewardName=%s rewards=%s fallbackUsed=false",
				id,
				safeName(slotFrame),
				slotFrame.Name,
				safeName(rowTimer),
				safeName(rowTitle),
				tostring(cfg and cfg.RewName or ""),
				summarizeRewardEntries(cfg)
			)
		)

		setRewData(slotFrame, cfg)
		setTimerCountdown(slotFrame, "--")
		hookButton(id)
	end

	updateHud()
end

local function buildSlotsWithWait()
	local expectedRewards = 0
	for _ = 1, 50 do
		buildSlotsOnce()
		expectedRewards = #orderedIds
		-- Accept partial slot sets so countdown sync still runs even when UI exposes fewer
		-- visible slot templates than configured rewards.
		if totalGifts > 0 then
			return true
		end
		task.wait(0.2)
	end
	logScrollState("waitTimeout")
	giftError(
		"Gifts UI did not expose all reward slots after waiting",
		"expected",
		expectedRewards,
		"found",
		totalGifts,
		"container",
		safeName(getGiftsSlotContainer())
	)
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
	giftLog("[GIFT][DATA]", string.format("applying legacy epoch=%d", serverStartEpoch))

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
					setTimerCountdown(slotFrame, formatDurationText(remaining))
					startCountdown(id)
					giftLog(
						"[GIFT][RENDER]",
						string.format(
							"rewardId=%d rewardName=%s state=countdown remaining=%s",
							id,
							tostring(cfg.RewName or ""),
							formatDurationText(remaining)
						)
					)
				else
					setTimerReady(slotFrame)
					giftLog(
						"[GIFT][RENDER]",
						string.format("rewardId=%d rewardName=%s state=ready", id, tostring(cfg.RewName or ""))
					)
				end
			end
		end
	end

	updateHud()
end

local function initialiseButtonsFromState(syncState)
	if typeof(syncState) ~= "table" then
		giftError("syncState payload must be a table, got", typeof(syncState))
		return
	end

	local cycleStartPlayTime = tonumber(syncState.CycleStartPlayTime)
	local currentPlayTime = tonumber(syncState.CurrentPlayTime)
	if not cycleStartPlayTime or not currentPlayTime then
		giftError("syncState missing play time fields", syncState)
		return
	end

	local claimedRewards = normalizeClaimedRewards(syncState.ClaimedRewards)
	local elapsedPlayTime = math.max(0, currentPlayTime - cycleStartPlayTime)

	giftLog(
		"[GIFT][DATA]",
		string.format(
			"received syncState claimed=%d currentPlayTime=%d cycleStart=%d elapsed=%d",
			getClaimedCount(claimedRewards),
			currentPlayTime,
			cycleStartPlayTime,
			elapsedPlayTime
		)
	)

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
				giftLog(
					"[GIFT][RENDER]",
					string.format("rewardId=%d rewardName=%s state=claimed", id, tostring(cfg.RewName or ""))
				)
			elseif cfg.Time == nil then
				setTimerCountdown(slotFrame, "ERR")
				giftError("Reward config missing Time for id", id)
			else
				local remaining = math.max(0, cfg.Time - elapsedPlayTime)
				endTimes[id] = os.clock() + remaining

				if remaining > 0 then
					setTimerCountdown(slotFrame, formatDurationText(remaining))
					startCountdown(id)
					giftLog(
						"[GIFT][RENDER]",
						string.format(
							"rewardId=%d rewardName=%s state=countdown remaining=%s",
							id,
							tostring(cfg.RewName or ""),
							formatDurationText(remaining)
						)
					)
				else
					setTimerReady(slotFrame)
					giftLog(
						"[GIFT][RENDER]",
						string.format("rewardId=%d rewardName=%s state=ready", id, tostring(cfg.RewName or ""))
					)
				end
			end
		end
	end

	updateHud()
end

local building = false
local pendingState = nil
local hasReceivedServerSync = false

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
		giftError("Unsupported pending time reward state", typeof(state))
	end
end

logHudBinding()

giftsFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if giftsFrame.Visible then
		logScrollState("panelOpen")
		giftLog("[GIFT][OPEN]", string.format("panel=%s visible=true slots=%d", safeName(giftsFrame), totalGifts))
	end
end)

if giftsFrame.Visible then
	logScrollState("panelOpen")
	giftLog("[GIFT][OPEN]", string.format("panel=%s visible=true slots=%d", safeName(giftsFrame), totalGifts))
end

task.spawn(function()
	building = true
	local ok = buildSlotsWithWait()
	building = false
	if ok then
		applyPendingState()
		-- Fallback: if the server sync has not arrived yet, start local countdowns
		-- from now so timers do not remain as "--" in UI.
		if not hasReceivedServerSync then
			initialiseButtonsFromLegacyEpoch(os.time())
		end
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
		hasReceivedServerSync = true
		local claimedPayload = if typeof(a) == "table" then a.ClaimedRewards else nil
		giftLog(
			"[GIFT][DATA]",
			"remoteAction=syncState",
			"claimedCount",
			getClaimedCount(claimedPayload),
			"totalSlots",
			totalGifts
		)
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
		hasReceivedServerSync = true
		if typeof(a) ~= "number" then
			giftError("startCycle/cycleReset bad epoch", a, "typeof", typeof(a))
			return
		end
		giftLog("[GIFT][DATA]", "remoteAction", action, "epoch", a)
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
		giftLog("[GIFT][RENDER]", "remoteAction=forceReady", "totalSlots", totalGifts)
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
			giftError("claimed action missing slot frame for id", id)
			return
		end
		slotFrame:SetAttribute("Claimed", true)
		stopCountdown(id)
		endTimes[id] = nil
		setTimerClaimed(slotFrame)
		giftLog(
			"[GIFT][RENDER]",
			string.format(
				"remoteAction=claimed rewardId=%s rewardName=%s amount=%s",
				tostring(id),
				tostring(b),
				tostring(c)
			)
		)
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
				setTimerCountdown(slotFrame, formatDurationText(clampedRemaining))
				startCountdown(id)
				giftLog(
					"[GIFT][RENDER]",
					string.format(
						"remoteAction=notReady rewardId=%d remaining=%s",
						id,
						formatDurationText(clampedRemaining)
					)
				)
			else
				setTimerReady(slotFrame)
				giftLog("[GIFT][RENDER]", string.format("remoteAction=notReady rewardId=%d state=ready", id))
			end
		elseif id == nil or remaining == nil then
			giftError("notReady payload missing id or remaining", a, b)
		end
		updateHud()
	elseif action == "alreadyClaimed" then
		giftLog("[GIFT][RENDER]", "remoteAction=alreadyClaimed", "rewardId", a)
		updateHud()
	else
		giftError("Unknown time reward action", action)
	end
end)

return {}
