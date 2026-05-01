local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GIFT_CLIENT_DEBUG_VERSION = "gifts-client-ui-slots-debug-2026-05-01"
local GIFT_STARTUP_DEBUG = false
local GIFT_SYNC_CLIENT_DEBUG = false
local GIFT_DEBUG = false
local REQUIRED_WAIT_SECONDS = 15
local OPTIONAL_WAIT_SECONDS = 5
local SYNC_REQUEST_RETRY_SECONDS = 1
local MAX_SYNC_REQUEST_ATTEMPTS = 10
local HUD_UPDATE_INTERVAL = 0.5
local COUNTDOWN_UPDATE_INTERVAL = 0.25

local function safeName(inst)
	if not inst then
		return "nil"
	end
	local ok, full = pcall(function()
		return inst:GetFullName()
	end)
	return ok and full or tostring(inst)
end

local function giftStartupLog(...)
	if GIFT_STARTUP_DEBUG then
		print("[GIFT][CLIENT]", ...)
	end
end

local function giftSyncClientLog(tag: string, ...)
	if GIFT_SYNC_CLIENT_DEBUG then
		print(tag, ...)
	end
end

local function giftDebugWarn(...)
	if GIFT_STARTUP_DEBUG then
		warn("[GIFT][CLIENT][WARN]", ...)
	end
end

local function giftStartupWarn(...)
	warn("[GIFT][CLIENT][WARN]", ...)
end

local function giftLog(tag: string, ...)
	if GIFT_DEBUG then
		print(tag, ...)
	end
end

local function giftError(...)
	warn("[GIFT][ERROR]", ...)
end

local function waitForChildLogged(parent: Instance?, childName: string, timeoutSeconds: number, label: string, suppressMissingWarning: boolean?)
	if not parent then
		if suppressMissingWarning then
			giftDebugWarn("missingParent", "path", label, "child", childName)
		else
			giftStartupWarn("missingParent", "path", label, "child", childName)
		end
		return nil
	end

	giftStartupLog("wait", "path", label, "parent", safeName(parent), "timeout", timeoutSeconds)
	local child = parent:WaitForChild(childName, timeoutSeconds)
	if child then
		giftStartupLog("found", "path", label, "instance", safeName(child), "class", child.ClassName)
	else
		if suppressMissingWarning then
			giftDebugWarn("missing", "path", label, "parent", safeName(parent), "timeout", timeoutSeconds)
		else
			giftStartupWarn("missing", "path", label, "parent", safeName(parent), "timeout", timeoutSeconds)
		end
	end
	return child
end

local function requireLogged(moduleScript: Instance?, label: string)
	if not moduleScript then
		giftStartupWarn("requireSkipped", "path", label, "reason", "module missing")
		return nil
	end
	if not moduleScript:IsA("ModuleScript") then
		giftStartupWarn("requireSkipped", "path", label, "class", moduleScript.ClassName)
		return nil
	end

	giftStartupLog("requireStart", "path", label, "module", safeName(moduleScript))
	local ok, result = pcall(require, moduleScript)
	if not ok then
		giftStartupWarn("requireFailed", "path", label, "error", tostring(result))
		return nil
	end
	giftStartupLog("requireOk", "path", label, "type", typeof(result))
	return result
end

local function findDescendantGuiButton(root: Instance, childName: string)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == childName and descendant:IsA("GuiButton") then
			return descendant
		end
	end
	return nil
end

local function getModalState(guiObject: GuiObject): boolean
	local ok, value = pcall(function()
		return guiObject.Modal
	end)
	return ok and value == true
end

local function setModalState(guiObject: GuiObject, value: boolean)
	pcall(function()
		guiObject.Modal = value
	end)
end

local function rectsOverlap(a: GuiObject, b: GuiObject): boolean
	local aPos = a.AbsolutePosition
	local aSize = a.AbsoluteSize
	local bPos = b.AbsolutePosition
	local bSize = b.AbsoluteSize

	return aPos.X < bPos.X + bSize.X
		and aPos.X + aSize.X > bPos.X
		and aPos.Y < bPos.Y + bSize.Y
		and aPos.Y + aSize.Y > bPos.Y
end

local function isEffectivelyVisible(guiObject: GuiObject, root: Instance): boolean
	local current: Instance? = guiObject
	while current and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("ScreenGui") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

local function getScreenGuiDisplayOrder(guiObject: Instance): number
	local screenGui = guiObject:FindFirstAncestorOfClass("ScreenGui")
	return screenGui and screenGui.DisplayOrder or 0
end

local function formatGuiRect(guiObject: GuiObject): string
	return string.format("pos=%s size=%s", tostring(guiObject.AbsolutePosition), tostring(guiObject.AbsoluteSize))
end

local player = Players.LocalPlayer
giftStartupLog(
	"start",
	"version",
	GIFT_CLIENT_DEBUG_VERSION,
	"script",
	safeName(script),
	"player",
	player and player.Name or "nil",
	"isStudio",
	tostring(RunService:IsStudio())
)

local guiRoot = waitForChildLogged(player, "PlayerGui", REQUIRED_WAIT_SECONDS, "Players.LocalPlayer.PlayerGui")
local mainGui = waitForChildLogged(guiRoot, "Frames", REQUIRED_WAIT_SECONDS, "PlayerGui.Frames")
local giftsFrame = waitForChildLogged(mainGui, "Gifts", REQUIRED_WAIT_SECONDS, "PlayerGui.Frames.Gifts")
local giftsMainFrame = waitForChildLogged(giftsFrame, "Main", REQUIRED_WAIT_SECONDS, "PlayerGui.Frames.Gifts.Main")

if not (guiRoot and mainGui and giftsFrame and giftsMainFrame) then
	giftStartupWarn(
		"fatalMissingGiftsUI",
		"version",
		GIFT_CLIENT_DEBUG_VERSION,
		"playerGui",
		safeName(guiRoot),
		"frames",
		safeName(mainGui),
		"gifts",
		safeName(giftsFrame),
		"main",
		safeName(giftsMainFrame)
	)
	return {}
end

local function countDirectChildrenNamed(parent: Instance?, childName: string): number
	if not parent then
		return 0
	end

	local count = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName then
			count += 1
		end
	end
	return count
end

local function logGiftsUiBinding(context: string)
	if not GIFT_STARTUP_DEBUG then
		return
	end

	giftStartupLog(
		"uiInstanceBinding",
		"context",
		context,
		"frames",
		safeName(mainGui),
		"gifts",
		safeName(giftsFrame),
		"main",
		safeName(giftsMainFrame),
		"visibleInstanceIsWired",
		tostring(mainGui:FindFirstChild("Gifts") == giftsFrame),
		"sameNamedGiftsCount",
		countDirectChildrenNamed(mainGui, "Gifts"),
		"mainChildren",
		#giftsMainFrame:GetChildren(),
		"mainDescendants",
		#giftsMainFrame:GetDescendants()
	)
end

local function refreshGiftsUiBinding(context: string): boolean
	local liveGifts = mainGui:FindFirstChild("Gifts")
	if not (liveGifts and liveGifts:IsA("Frame")) then
		giftDebugWarn("uiRebindSkipped", "context", context, "reason", "live Gifts frame missing", "current", safeName(giftsFrame))
		return false
	end

	local liveMain = liveGifts:FindFirstChild("Main")
	if not (liveMain and liveMain:IsA("GuiObject")) then
		giftDebugWarn(
			"uiRebindSkipped",
			"context",
			context,
			"reason",
			"live Gifts.Main missing",
			"gifts",
			safeName(liveGifts),
			"currentMain",
			safeName(giftsMainFrame)
		)
		return false
	end

	if liveGifts ~= giftsFrame or liveMain ~= giftsMainFrame then
		giftDebugWarn(
			"uiInstanceRebound",
			"context",
			context,
			"oldGifts",
			safeName(giftsFrame),
			"oldMain",
			safeName(giftsMainFrame),
			"newGifts",
			safeName(liveGifts),
			"newMain",
			safeName(liveMain),
			"newMainChildren",
			#liveMain:GetChildren(),
			"newMainDescendants",
			#liveMain:GetDescendants()
		)
		giftsFrame = liveGifts
		giftsMainFrame = liveMain
	end

	return true
end

refreshGiftsUiBinding("startup")
logGiftsUiBinding("startup")

local lastCloseClickAt = 0

local function hardenGiftsInputLayers()
	for _, childName in ipairs({ "BaseTexture", "Overlay", "OuterBorder" }) do
		local child = giftsFrame:FindFirstChild(childName)
		if child and child:IsA("GuiObject") then
			child.Active = false
			setModalState(child, false)
			giftStartupLog(
				"inputLayer",
				"path",
				safeName(child),
				"class",
				child.ClassName,
				"visible",
				tostring(child.Visible),
				"active",
				tostring(child.Active),
				"modal",
				tostring(getModalState(child)),
				"z",
				child.ZIndex
			)
		end
	end
end

local function closeGiftsPanel(source: string)
	local now = os.clock()
	if now - lastCloseClickAt < 0.05 then
		return
	end
	lastCloseClickAt = now

	giftStartupLog(
		"xClicked",
		"source",
		source,
		"frame",
		safeName(giftsFrame),
		"wasVisible",
		tostring(giftsFrame.Visible)
	)

	giftsFrame:SetAttribute("OpenUIOpened", false)
	giftsMainFrame.Visible = false
	giftsFrame.Visible = false

	local scale = giftsFrame:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0
	end

	local blur = Lighting:FindFirstChild("BlurUI")
	if blur and blur:IsA("BlurEffect") then
		blur.Size = 0
	end

	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = 70
	end

	giftDebugWarn(
		"xForceClosed",
		"source",
		source,
		"frameVisible",
		tostring(giftsFrame.Visible),
		"mainVisible",
		tostring(giftsMainFrame.Visible),
		"scale",
		tostring(scale and scale.Scale or "nil")
	)

	task.delay(0.12, function()
		if giftsFrame.Parent and giftsFrame.Visible then
			giftDebugWarn(
				"xCloseOverridden",
				"source",
				source,
				"frame",
				safeName(giftsFrame),
				"frameVisible",
				tostring(giftsFrame.Visible),
				"mainVisible",
				tostring(giftsMainFrame.Visible),
				"sameNamedGiftsCount",
				countDirectChildrenNamed(mainGui, "Gifts")
			)
		end
	end)
end

local function auditGiftsInputBlockers(context: string)
	if not GIFT_STARTUP_DEBUG then
		return
	end

	local closeButton = findDescendantGuiButton(giftsFrame, "X")
	if not closeButton then
		giftDebugWarn("xAuditSkipped", "context", context, "reason", "X button missing", "frame", safeName(giftsFrame))
		return
	end

	local closeDisplayOrder = getScreenGuiDisplayOrder(closeButton)
	local closeZIndex = closeButton.ZIndex
	local blockerCount = 0

	for _, descendant in ipairs(guiRoot:GetDescendants()) do
		if descendant:IsA("GuiObject")
			and descendant ~= closeButton
			and not descendant:IsDescendantOf(closeButton)
			and not closeButton:IsDescendantOf(descendant)
			and isEffectivelyVisible(descendant, guiRoot)
			and rectsOverlap(descendant, closeButton)
		then
			local active = descendant.Active
			local modal = getModalState(descendant)
			local capturesInput = active or modal or descendant:IsA("GuiButton")
			local displayOrder = getScreenGuiDisplayOrder(descendant)
			local canBeAboveClose = displayOrder > closeDisplayOrder
				or (displayOrder == closeDisplayOrder and descendant.ZIndex >= closeZIndex)

			if capturesInput and canBeAboveClose then
				blockerCount += 1
				if blockerCount <= 20 then
					giftDebugWarn(
						"possibleInputBlocker",
						"context",
						context,
						"blocker",
						safeName(descendant),
						"class",
						descendant.ClassName,
						"displayOrder",
						displayOrder,
						"z",
						descendant.ZIndex,
						"active",
						tostring(active),
						"modal",
						tostring(modal),
						"visible",
						tostring(descendant.Visible),
						"backgroundTransparency",
						tostring(descendant.BackgroundTransparency),
						"rect",
						formatGuiRect(descendant),
						"close",
						formatGuiRect(closeButton)
					)
				end
			end
		end
	end

	giftStartupLog(
		"inputAudit",
		"context",
		context,
		"closeButton",
		safeName(closeButton),
		"displayOrder",
		closeDisplayOrder,
		"z",
		closeZIndex,
		"possibleBlockers",
		blockerCount
	)
end

local function bindGiftsCloseButton()
	hardenGiftsInputLayers()

	local closeButton = findDescendantGuiButton(giftsFrame, "X")
	if not closeButton then
		giftDebugWarn("xButtonMissing", "frame", safeName(giftsFrame))
		return
	end

	closeButton.Active = true
	closeButton.Selectable = true
	closeButton.ZIndex = math.max(closeButton.ZIndex, 100)
	setModalState(closeButton, false)

	local ancestor = closeButton.Parent
	while ancestor and ancestor ~= giftsFrame do
		if ancestor:IsA("GuiObject") then
			ancestor.ZIndex = math.max(ancestor.ZIndex, 90)
		end
		ancestor = ancestor.Parent
	end

	giftStartupLog(
		"xButtonFound",
		"button",
		safeName(closeButton),
		"class",
		closeButton.ClassName,
		"visible",
		tostring(closeButton.Visible),
		"active",
		tostring(closeButton.Active),
		"modal",
		tostring(getModalState(closeButton)),
		"z",
		closeButton.ZIndex,
		"sameNamedGiftsCount",
		countDirectChildrenNamed(mainGui, "Gifts"),
		"visibleInstanceIsWired",
		tostring(mainGui:FindFirstChild("Gifts") == giftsFrame)
	)

	closeButton.MouseButton1Click:Connect(function()
		closeGiftsPanel("MouseButton1Click")
	end)
	giftStartupLog("xConnectionMade", "signal", "MouseButton1Click", "button", safeName(closeButton))

	closeButton.Activated:Connect(function()
		closeGiftsPanel("Activated")
	end)
	giftStartupLog("xConnectionMade", "signal", "Activated", "button", safeName(closeButton))

	task.defer(function()
		auditGiftsInputBlockers("startup")
	end)
end

bindGiftsCloseButton()

giftsFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if giftsFrame.Visible then
		giftsMainFrame.Visible = true
		giftStartupLog(
			"panelVisibleRestore",
			"frame",
			safeName(giftsFrame),
			"main",
			safeName(giftsMainFrame),
			"mainVisible",
			tostring(giftsMainFrame.Visible)
		)
		task.defer(function()
			auditGiftsInputBlockers("panelVisible")
		end)
	end
end)

local Modules = waitForChildLogged(ReplicatedStorage, "Modules", REQUIRED_WAIT_SECONDS, "ReplicatedStorage.Modules")
local TimeRewardsFolder = waitForChildLogged(Modules, "TimeRewards", REQUIRED_WAIT_SECONDS, "ReplicatedStorage.Modules.TimeRewards")
local RewardsConfig = requireLogged(
	waitForChildLogged(TimeRewardsFolder, "Config", REQUIRED_WAIT_SECONDS, "ReplicatedStorage.Modules.TimeRewards.Config"),
	"ReplicatedStorage.Modules.TimeRewards.Config"
)
local Remote = waitForChildLogged(
	TimeRewardsFolder,
	"TimeRewardEvent",
	REQUIRED_WAIT_SECONDS,
	"ReplicatedStorage.Modules.TimeRewards.TimeRewardEvent"
)
if Remote and not Remote:IsA("RemoteEvent") then
	giftStartupWarn("remoteWrongClass", "path", safeName(Remote), "class", Remote.ClassName, "expected", "RemoteEvent")
	Remote = nil
elseif Remote then
	giftStartupLog("remoteFound", "path", safeName(Remote), "class", Remote.ClassName)
end

local SnapshotRequest = waitForChildLogged(
	TimeRewardsFolder,
	"TimeRewardSnapshotRequest",
	REQUIRED_WAIT_SECONDS,
	"ReplicatedStorage.Modules.TimeRewards.TimeRewardSnapshotRequest"
)
if SnapshotRequest and not SnapshotRequest:IsA("RemoteFunction") then
	giftStartupWarn(
		"snapshotWrongClass",
		"path",
		safeName(SnapshotRequest),
		"class",
		SnapshotRequest.ClassName,
		"expected",
		"RemoteFunction"
	)
	SnapshotRequest = nil
elseif SnapshotRequest then
	giftStartupLog("snapshotFound", "path", safeName(SnapshotRequest), "class", SnapshotRequest.ClassName)
end

local InstantRewardsEvent = waitForChildLogged(
	TimeRewardsFolder,
	"TriggerInstantRewards",
	OPTIONAL_WAIT_SECONDS,
	"ReplicatedStorage.Modules.TimeRewards.TriggerInstantRewards",
	true
)
if InstantRewardsEvent and not InstantRewardsEvent:IsA("BindableEvent") then
	giftStartupWarn(
		"instantRewardsWrongClass",
		"path",
		safeName(InstantRewardsEvent),
		"class",
		InstantRewardsEvent.ClassName,
		"expected",
		"BindableEvent"
	)
elseif InstantRewardsEvent then
	giftStartupLog("instantRewardsFound", "path", safeName(InstantRewardsEvent), "class", InstantRewardsEvent.ClassName)
else
	giftDebugWarn(
		"instantRewardsMissing",
		"path",
		"ReplicatedStorage.Modules.TimeRewards.TriggerInstantRewards",
		"note",
		"client does not use this event directly, but server-created instance should replicate here"
	)
end

local Shorten = requireLogged(
	waitForChildLogged(Modules, "Shorten", REQUIRED_WAIT_SECONDS, "ReplicatedStorage.Modules.Shorten"),
	"ReplicatedStorage.Modules.Shorten"
)

if not (Modules and TimeRewardsFolder and RewardsConfig and Remote and SnapshotRequest and Shorten) then
	giftStartupWarn(
		"fatalMissingTimeRewardsDependency",
		"version",
		GIFT_CLIENT_DEBUG_VERSION,
		"modules",
		safeName(Modules),
		"timeRewardsFolder",
		safeName(TimeRewardsFolder),
		"config",
		tostring(RewardsConfig ~= nil),
		"remote",
		safeName(Remote),
		"snapshot",
		safeName(SnapshotRequest),
		"shorten",
		tostring(Shorten ~= nil)
	)
	return {}
end

local hudFrame = waitForChildLogged(guiRoot, "HUD", REQUIRED_WAIT_SECONDS, "PlayerGui.HUD")
local lButtons = waitForChildLogged(hudFrame, "LButtons", REQUIRED_WAIT_SECONDS, "PlayerGui.HUD.LButtons")
local hudGifts = waitForChildLogged(lButtons, "Gifts", REQUIRED_WAIT_SECONDS, "PlayerGui.HUD.LButtons.Gifts")

if not (hudFrame and lButtons and hudGifts) then
	giftStartupWarn(
		"fatalMissingGiftsHud",
		"hud",
		safeName(hudFrame),
		"lButtons",
		safeName(lButtons),
		"hudGifts",
		safeName(hudGifts)
	)
	return {}
end

local function isTextWidget(obj: Instance?): boolean
	return obj ~= nil and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
end

local function ensureHudNotificationBadge()
	local badge = hudGifts:FindFirstChild("Not")
	if not (badge and badge:IsA("GuiObject")) then
		giftDebugWarn("hudBadgeMissing", "button", safeName(hudGifts), "action", "creating fallback Not")
		badge = Instance.new("Frame")
		badge.Name = "Not"
		badge.BackgroundColor3 = Color3.fromRGB(235, 65, 92)
		badge.BorderSizePixel = 0
		badge.Position = UDim2.new(1, -24, 0, -4)
		badge.Size = UDim2.fromOffset(34, 22)
		badge.Visible = false
		badge.Parent = hudGifts
	end

	local text = badge:FindFirstChild("TextLB")
	if not isTextWidget(text) then
		giftDebugWarn("hudBadgeTextMissing", "badge", safeName(badge), "action", "creating fallback TextLB")
		if text then
			text:Destroy()
		end
		text = Instance.new("TextLabel")
		text.Name = "TextLB"
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.Size = UDim2.fromScale(1, 1)
		text.Text = "0"
		text.TextColor3 = Color3.new(1, 1, 1)
		text.TextScaled = true
		text.Parent = badge
	end

	giftStartupLog(
		"uiFound",
		"giftsFrame",
		safeName(giftsFrame),
		"giftsMain",
		safeName(giftsMainFrame),
		"hudGifts",
		safeName(hudGifts),
		"badge",
		safeName(badge),
		"badgeText",
		safeName(text)
	)

	return badge, text
end

local hudNot, hudNotText = ensureHudNotificationBadge()

local READY_TEXT = "Claim"
local CLAIMED_TEXT = "Claimed"
local LOADING_TEXT = "Loading"
local WHITE_COLOR = Color3.new(1, 1, 1)
local GREEN_COLOR = Color3.new(0, 1, 0)
local endTimes = {}
local threads = {}
local slotsById = {}
local claimButtonConnections = {}
local claimButtonInstances = {}
local orderedIds = {}
local totalGifts = 0
local timerLogStateByPath = {}
local giftSlotsFoundLogState = nil
local giftRenderDiagnosticsState = nil
local dumpedGiftsMainTreeContexts = {}

local PREFERRED_SLOT_CONTAINER_NAMES = {
	Scroll = true,
	ScrollingFrame = true,
	Holder = true,
	Rewards = true,
	RewardSlots = true,
	Slots = true,
	Content = true,
	Container = true,
	List = true,
	TimeRewardsSlots = true,
}

local FALLBACK_SLOT_CONTAINER_NAME = "TimeRewardsSlots"

local FALLBACK_STYLE = {
	SectionBackground = Color3.fromRGB(27, 46, 68),
	SectionHover = Color3.fromRGB(46, 74, 99),
	HeaderBackground = Color3.fromRGB(16, 35, 59),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
	ButtonA = Color3.fromRGB(212, 175, 55),
	ButtonB = Color3.fromRGB(242, 209, 107),
}

local function describeTreeNode(inst: Instance): string
	if inst:IsA("GuiObject") then
		return string.format(
			"class=%s visible=%s active=%s modal=%s z=%s layout=%s pos=%s size=%s children=%d",
			inst.ClassName,
			tostring(inst.Visible),
			tostring(inst.Active),
			tostring(getModalState(inst)),
			tostring(inst.ZIndex),
			tostring(inst.LayoutOrder),
			tostring(inst.Position),
			tostring(inst.Size),
			#inst:GetChildren()
		)
	end

	if inst:IsA("UIListLayout") then
		return string.format(
			"class=%s sort=%s padding=%s contentSize=%s children=%d",
			inst.ClassName,
			tostring(inst.SortOrder),
			tostring(inst.Padding),
			tostring(inst.AbsoluteContentSize),
			#inst:GetChildren()
		)
	end

	return string.format("class=%s children=%d", inst.ClassName, #inst:GetChildren())
end

local function dumpGiftsMainTree(context: string)
	if not GIFT_STARTUP_DEBUG then
		return
	end

	refreshGiftsUiBinding("dumpTree:" .. context)
	if dumpedGiftsMainTreeContexts[context] then
		return
	end
	dumpedGiftsMainTreeContexts[context] = true

	local descendants = giftsMainFrame:GetDescendants()
	giftDebugWarn(
		"mainTreeDump",
		"context",
		context,
		"root",
		safeName(giftsMainFrame),
		"rootInfo",
		describeTreeNode(giftsMainFrame),
		"descendants",
		#descendants
	)

	local lineCount = 0
	local function walk(parent: Instance, depth: number)
		if lineCount >= 240 then
			return
		end

		for _, child in ipairs(parent:GetChildren()) do
			lineCount += 1
			giftDebugWarn(
				"mainTreeNode",
				"context",
				context,
				"depth",
				depth,
				"name",
				child.Name,
				"path",
				safeName(child),
				"info",
				describeTreeNode(child)
			)

			if lineCount >= 240 then
				giftDebugWarn("mainTreeDumpTruncated", "context", context, "limit", 240, "totalDescendants", #descendants)
				return
			end
			walk(child, depth + 1)
		end
	end

	walk(giftsMainFrame, 1)
	if lineCount == 0 then
		giftDebugWarn("mainTreeEmpty", "context", context, "root", safeName(giftsMainFrame))
	end
end

local function getGiftsSlotContainer()
	refreshGiftsUiBinding("getSlotContainer")
	local scroll = giftsMainFrame:FindFirstChild("Scroll")
	if scroll and scroll:IsA("ScrollingFrame") then
		return scroll
	end

	local fallbackScroll = giftsMainFrame:FindFirstChild(FALLBACK_SLOT_CONTAINER_NAME)
	if fallbackScroll and fallbackScroll:IsA("ScrollingFrame") then
		return fallbackScroll
	end

	if giftsMainFrame:IsA("ScrollingFrame") then
		return giftsMainFrame
	end

	for _, descendant in ipairs(giftsMainFrame:GetDescendants()) do
		if descendant:IsA("ScrollingFrame") then
			return descendant
		end
	end

	for _, descendant in ipairs(giftsMainFrame:GetDescendants()) do
		if descendant:IsA("GuiObject") and PREFERRED_SLOT_CONTAINER_NAMES[descendant.Name] then
			return descendant
		end
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
	if not (GIFT_DEBUG or GIFT_STARTUP_DEBUG) then
		return
	end

	local container = getGiftsSlotContainer()
	local layout = getGiftsListLayout(container)
	local slotCount = 0
	for _, child in ipairs(giftsMainFrame:GetDescendants()) do
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

local function ensureFallbackChild(parent: Instance, className: string, name: string)
	local child = parent:FindFirstChild(name)
	if child and child.ClassName == className then
		return child
	end

	if child then
		giftStartupWarn(
			"fallbackChildClassMismatch",
			"parent",
			safeName(parent),
			"name",
			name,
			"existingClass",
			child.ClassName,
			"expectedClass",
			className,
			"action",
			"replace"
		)
		child:Destroy()
	end

	child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

local function ensureFallbackCorner(parent: Instance, radius: number)
	local corner = parent:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = parent
	end
	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function ensureFallbackStroke(parent: Instance, color: Color3, thickness: number)
	local stroke = parent:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = parent
	end
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = 0
	stroke.Enabled = true
	return stroke
end

local function ensureFallbackGradient(parent: Instance, topColor: Color3, bottomColor: Color3)
	local gradient = parent:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = parent
	end
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	})
	gradient.Rotation = 90
	gradient.Enabled = true
	return gradient
end

local function styleFallbackText(label: TextLabel, textSize: number, color: Color3)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.TextScaled = false
	label.TextSize = textSize
	label.TextStrokeColor3 = FALLBACK_STYLE.GoldShadow
	label.TextStrokeTransparency = 0.45
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextYAlignment = Enum.TextYAlignment.Center
end

local function ensureFallbackSlotContainer(expectedRewardCount: number)
	refreshGiftsUiBinding("ensureFallbackSlotContainer")
	giftsMainFrame.Visible = true
	giftsMainFrame.BackgroundTransparency = 1
	giftsMainFrame.BorderSizePixel = 0
	giftsMainFrame.ClipsDescendants = true
	giftsMainFrame.Size = UDim2.new(1, -42, 1, -126)
	giftsMainFrame.Position = UDim2.fromOffset(18, 116)
	giftsMainFrame.ZIndex = math.max(giftsMainFrame.ZIndex, 3)

	local scroll = giftsMainFrame:FindFirstChild("Scroll")
	if scroll and not scroll:IsA("ScrollingFrame") then
		giftStartupWarn(
			"slotContainerNameConflict",
			"path",
			safeName(scroll),
			"class",
			scroll.ClassName,
			"action",
			"replaceWithScrollingFrame"
		)
		scroll:Destroy()
		scroll = nil
	end

	if not scroll then
		scroll = giftsMainFrame:FindFirstChild(FALLBACK_SLOT_CONTAINER_NAME)
	end
	if scroll and not scroll:IsA("ScrollingFrame") then
		giftStartupWarn("fallbackContainerWrongClass", "path", safeName(scroll), "class", scroll.ClassName, "action", "replace")
		scroll:Destroy()
		scroll = nil
	end
	if not scroll then
		scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Scroll"
		scroll.Parent = giftsMainFrame
	end

	scroll.Active = true
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ClipsDescendants = true
	scroll.Position = UDim2.fromScale(0, 0)
	scroll.ScrollBarImageColor3 = FALLBACK_STYLE.GoldHighlight
	scroll.ScrollBarThickness = 8
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollingEnabled = true
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroll.Visible = true
	scroll.ZIndex = math.max(scroll.ZIndex, 4)
	scroll:SetAttribute("CreatedByTimeRewardsClient", true)

	local padding = scroll:FindFirstChild("ContentPadding")
	if not (padding and padding:IsA("UIPadding")) then
		if padding then
			padding:Destroy()
		end
		padding = Instance.new("UIPadding")
		padding.Name = "ContentPadding"
		padding.Parent = scroll
	end
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)

	local list = scroll:FindFirstChild("SlotLayout")
	if not (list and list:IsA("UIListLayout")) then
		if list then
			list:Destroy()
		end
		list = Instance.new("UIListLayout")
		list.Name = "SlotLayout"
		list.Parent = scroll
	end
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)

	for index = 1, expectedRewardCount do
		local slot = ensureFallbackChild(scroll, "Frame", "Slot" .. tostring(index))
		slot.BackgroundColor3 = FALLBACK_STYLE.SectionBackground
		slot.BackgroundTransparency = 0.25
		slot.BorderSizePixel = 0
		slot.Active = true
		slot.Size = UDim2.new(1, -30, 0, 96)
		slot.LayoutOrder = index
		slot.ClipsDescendants = true
		slot.Visible = true
		slot.ZIndex = math.max(slot.ZIndex, 4)
		slot:SetAttribute("CreatedByTimeRewardsClient", true)
		ensureFallbackCorner(slot, 10)
		ensureFallbackStroke(slot, FALLBACK_STYLE.GoldHighlight, 1.5)

		local rewName = ensureFallbackChild(slot, "TextLabel", "RewName")
		rewName.Size = UDim2.new(1, -192, 0, 22)
		rewName.Position = UDim2.fromOffset(68, 12)
		rewName.TextXAlignment = Enum.TextXAlignment.Left
		rewName.ZIndex = math.max(rewName.ZIndex, 5)
		styleFallbackText(rewName, 17, FALLBACK_STYLE.TextMain)

		local timer = ensureFallbackChild(slot, "TextLabel", "Timer")
		timer.Size = UDim2.new(1, -192, 0, 20)
		timer.Position = UDim2.fromOffset(68, 40)
		timer.TextXAlignment = Enum.TextXAlignment.Left
		timer.ZIndex = math.max(timer.ZIndex, 5)
		styleFallbackText(timer, 15, FALLBACK_STYLE.TextSecondary)

		local description = ensureFallbackChild(slot, "TextLabel", "RewardDescription")
		description.Size = UDim2.new(1, -192, 0, 16)
		description.Position = UDim2.fromOffset(68, 62)
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.ZIndex = math.max(description.ZIndex, 5)
		styleFallbackText(description, 12, FALLBACK_STYLE.TextSecondary)

		local icon = ensureFallbackChild(slot, "ImageLabel", "Icon")
		icon.Size = UDim2.fromOffset(44, 44)
		icon.Position = UDim2.fromOffset(12, 19)
		icon.BackgroundColor3 = FALLBACK_STYLE.HeaderBackground
		icon.BackgroundTransparency = 0.25
		icon.BorderSizePixel = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = math.max(icon.ZIndex, 5)
		ensureFallbackCorner(icon, 8)
		ensureFallbackStroke(icon, FALLBACK_STYLE.GoldHighlight, 1)

		local claimButton = ensureFallbackChild(slot, "TextButton", "ClaimButton")
		claimButton.Active = true
		claimButton.AnchorPoint = Vector2.new(1, 0.5)
		claimButton.AutoButtonColor = true
		claimButton.BackgroundColor3 = FALLBACK_STYLE.ButtonA
		claimButton.BackgroundTransparency = 0
		claimButton.BorderSizePixel = 0
		claimButton.Position = UDim2.new(1, -14, 0.5, 0)
		claimButton.Size = UDim2.fromOffset(92, 34)
		claimButton.Text = ""
		claimButton.Visible = true
		claimButton.ZIndex = math.max(claimButton.ZIndex, 6)
		ensureFallbackCorner(claimButton, 8)
		ensureFallbackStroke(claimButton, FALLBACK_STYLE.GoldShadow, 1)
		ensureFallbackGradient(claimButton, FALLBACK_STYLE.ButtonB, FALLBACK_STYLE.ButtonA)

		local claimText = ensureFallbackChild(claimButton, "TextLabel", "Text")
		claimText.Position = UDim2.fromOffset(0, 0)
		claimText.Size = UDim2.fromScale(1, 1)
		claimText.Text = READY_TEXT
		claimText.TextXAlignment = Enum.TextXAlignment.Center
		claimText.ZIndex = math.max(claimText.ZIndex, 7)
		styleFallbackText(claimText, 18, FALLBACK_STYLE.TextMain)
	end

	giftDebugWarn(
		"fallbackSlotsCreated",
		"count",
		expectedRewardCount,
		"container",
		safeName(scroll),
		"descendants",
		#scroll:GetDescendants()
	)

	return scroll
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
	if not GIFT_STARTUP_DEBUG then
		return
	end

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
	if obj == giftsMainFrame then
		return false
	end
	if not obj:IsDescendantOf(giftsMainFrame) then
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

local function formatRewardDescription(cfg): string
	if typeof(cfg) ~= "table" or typeof(cfg.Rewards) ~= "table" then
		return ""
	end

	local parts = {}
	for rewardName, rewardData in pairs(cfg.Rewards) do
		local amount = 1
		if typeof(rewardData) == "table" and rewardData.Amount ~= nil then
			amount = rewardData.Amount
		end

		parts[#parts + 1] = string.format("x%s %s", tostring(amount), tostring(rewardName))
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function ensureVisibleText(textObj: Instance?, fallbackSize: UDim2?, fallbackPosition: UDim2?)
	if not isTextGuiObject(textObj) then
		return nil
	end

	local label = textObj :: TextLabel
	label.Visible = true
	label.TextTransparency = 0
	label.BackgroundTransparency = 1
	label.ZIndex = math.max(label.ZIndex, 5)
	if label.Size.X.Offset == 0 and label.Size.X.Scale == 0 and fallbackSize then
		label.Size = fallbackSize
	end
	if label.Position.X.Offset == 0 and label.Position.X.Scale == 0 and fallbackPosition then
		label.Position = fallbackPosition
	end
	return label
end

local function ensureVisibleImage(imageObj: Instance?)
	if not isImageGuiObject(imageObj) then
		return nil
	end

	local image = imageObj :: ImageLabel
	image.Visible = true
	image.ImageTransparency = 0
	image.BackgroundTransparency = math.min(image.BackgroundTransparency, 0.35)
	image.ZIndex = math.max(image.ZIndex, 5)
	if image.Size.X.Offset == 0 and image.Size.X.Scale == 0 then
		image.Size = UDim2.fromOffset(44, 44)
	end
	return image
end

local function ensureRenderableGiftRow(slotFrame: Instance, layoutOrder: number)
	if not slotFrame:IsA("GuiObject") then
		return
	end

	local row = slotFrame :: GuiObject
	row.Visible = true
	row.Active = true
	row.ClipsDescendants = true
	row.LayoutOrder = layoutOrder
	row.ZIndex = math.max(row.ZIndex, 4)
	if row.Size.Y.Offset <= 0 and row.Size.Y.Scale == 0 then
		row.Size = UDim2.new(1, -30, 0, 96)
	elseif row.Size.Y.Offset < 70 and row.Size.Y.Scale == 0 then
		row.Size = UDim2.new(row.Size.X.Scale, row.Size.X.Offset, 0, 96)
	end
	if row.Size.X.Offset == 0 and row.Size.X.Scale == 0 then
		row.Size = UDim2.new(1, -30, row.Size.Y.Scale, math.max(row.Size.Y.Offset, 96))
	end

	local ancestor = row.Parent
	while ancestor and ancestor ~= giftsMainFrame do
		if ancestor:IsA("GuiObject") then
			ancestor.Visible = true
		end
		ancestor = ancestor.Parent
	end

	ensureVisibleText(getDirectTextObj(row, "RewName"), UDim2.new(1, -192, 0, 22), UDim2.fromOffset(68, 12))
	ensureVisibleText(getDirectTextObj(row, "Timer"), UDim2.new(1, -192, 0, 20), UDim2.fromOffset(68, 40))
	ensureVisibleText(getDirectTextObj(row, "RewardDescription"), UDim2.new(1, -192, 0, 16), UDim2.fromOffset(68, 62))
	ensureVisibleImage(getDirectImageObj(row, "Icon"))

	local claimButton = getClaimButton(row)
	if claimButton and claimButton:IsA("GuiObject") then
		claimButton.Visible = true
		claimButton.Active = true
		claimButton.ZIndex = math.max(claimButton.ZIndex, 6)
		if claimButton.Size.X.Offset == 0 and claimButton.Size.X.Scale == 0 then
			claimButton.Size = UDim2.fromOffset(92, 34)
		end
		local claimText = ensureVisibleText(
			claimButton:FindFirstChild("Text"),
			UDim2.fromScale(1, 1),
			UDim2.fromOffset(0, 0)
		)
		if claimText and claimText.Text == "" then
			claimText.Text = READY_TEXT
		end
	end
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

	local descriptionObj = getDirectTextObj(slotFrame, "RewardDescription")
	if descriptionObj then
		descriptionObj.Text = formatRewardDescription(cfg)
		descriptionObj.Visible = descriptionObj.Text ~= ""
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

local stopCountdown = nil
local hasReceivedServerSync = false
local hasAppliedServerSync = false
local syncRequestStopLogged = false
local syncEventConnected = false

local function logSyncRequestStop(reason: string)
	if syncRequestStopLogged then
		return
	end

	syncRequestStopLogged = true
	giftSyncClientLog("[GIFT][SYNC][REQUEST_STOP]", "reason", tostring(reason))
end

local function logSnapshotStatus(tag: string, ...)
	print(tag, ...)
end

local function setTimerLoading(slotFrame: Instance)
	setTimerText(slotFrame, LOADING_TEXT, WHITE_COLOR)
end

local function setAuthoritativeSyncPending(isPending: boolean)
	if isPending and hasReceivedServerSync then
		return
	end

	for i = 1, totalGifts do
		local id = orderedIds[i]
		local slotFrame = slotsById[id]
		if slotFrame then
			slotFrame:SetAttribute("ServerSyncPending", isPending)
			if isPending then
				stopCountdown(id)
				endTimes[id] = nil
				setTimerLoading(slotFrame)
			end

			local claimButton = getClaimButton(slotFrame)
			if claimButton then
				claimButton.Active = not isPending
				claimButton.AutoButtonColor = not isPending
			end
		end
	end
end

local summaryLogState = nil
local badgeLogState = nil
local formatDurationText
local requestServerSync = nil

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

local function getMappedGiftRowCount(): number
	local count = 0
	for i = 1, totalGifts do
		local id = orderedIds[i]
		local slotFrame = slotsById[id]
		if slotFrame and slotFrame.Parent and slotFrame:IsDescendantOf(giftsMainFrame) then
			count += 1
		end
	end
	return count
end

local function markSyncStateReceived(syncState)
	if typeof(syncState) == "table" then
		syncState.__ClientReceivedAt = os.clock()
	end

	return syncState
end

local function getEffectiveCurrentPlayTime(syncState)
	if typeof(syncState) ~= "table" then
		return nil
	end

	local currentPlayTime = tonumber(syncState.CurrentPlayTime)
	if not currentPlayTime then
		return nil
	end

	local receivedAt = tonumber(syncState.__ClientReceivedAt)
	if receivedAt then
		currentPlayTime += math.max(0, math.floor(os.clock() - receivedAt))
	end

	return currentPlayTime
end

local function getSyncStateSummary(syncState)
	if typeof(syncState) ~= "table" then
		return 0, nil, nil
	end

	return getClaimedCount(syncState.ClaimedRewards), getEffectiveCurrentPlayTime(syncState), tonumber(syncState.CycleStartPlayTime)
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

function stopCountdown(id: number)
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
			task.wait(COUNTDOWN_UPDATE_INTERVAL)
		end
	end)
end

local function hookButton(id: number)
	local slotFrame = slotsById[id]
	if not slotFrame then
		giftError("hookButton missing slot frame for id", id)
		return
	end

	local claimBtn = getClaimButton(slotFrame)
	if not claimBtn then
		giftError("hookButton missing claim button in", safeName(slotFrame), "for id", id)
		return
	end

	local existingConnection = claimButtonConnections[slotFrame]
	if existingConnection and claimButtonInstances[slotFrame] == claimBtn and slotFrame:GetAttribute("HookedRewardId") == id then
		return
	end
	if existingConnection then
		existingConnection:Disconnect()
		claimButtonConnections[slotFrame] = nil
		claimButtonInstances[slotFrame] = nil
	end

	slotFrame:SetAttribute("Hooked", true)
	slotFrame:SetAttribute("HookedRewardId", id)
	claimButtonInstances[slotFrame] = claimBtn
	giftStartupLog(
		"claimConnectionMade",
		"rewardId",
		id,
		"slot",
		safeName(slotFrame),
		"button",
		safeName(claimBtn),
		"class",
		claimBtn.ClassName,
		"visible",
		tostring(claimBtn.Visible),
		"active",
		tostring(claimBtn.Active),
		"z",
		claimBtn.ZIndex
	)

	claimButtonConnections[slotFrame] = claimBtn.Activated:Connect(function()
		giftStartupLog(
			"claimClicked",
			"rewardId",
			id,
			"slot",
			safeName(slotFrame),
			"button",
			safeName(claimBtn),
			"claimed",
			tostring(slotFrame:GetAttribute("Claimed"))
		)
		if slotFrame:GetAttribute("Claimed") then
			return
		end
		if slotFrame:GetAttribute("ServerSyncPending") then
			if requestServerSync then
				requestServerSync("claimWhilePending")
			end
			return
		end

		local endTime = endTimes[id]
		if endTime and endTime > os.clock() then
			local remaining = math.max(1, math.ceil(endTime - os.clock()))
			setTimerCountdown(slotFrame, formatDurationText(remaining))
			startCountdown(id)
			updateHud()
			return
		end

		Remote:FireServer(id)
	end)
end

local function collectSlotFrames()
	refreshGiftsUiBinding("collectSlotFrames")
	local candidates = {}

	for _, inst in ipairs(giftsMainFrame:GetDescendants()) do
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

local function cleanupClaimConnectionsForTemplates(templates)
	local live = {}
	for _, slotFrame in ipairs(templates) do
		live[slotFrame] = true
	end

	for slotFrame, connection in pairs(claimButtonConnections) do
		if not live[slotFrame] or slotFrame.Parent == nil then
			if connection then
				connection:Disconnect()
			end
			claimButtonConnections[slotFrame] = nil
			claimButtonInstances[slotFrame] = nil
		end
	end
end

local function estimateRowsCanvasHeight(rows): number
	local rowCount = 0
	local height = 18
	for _, row in ipairs(rows) do
		if row:IsA("GuiObject") then
			rowCount += 1
			height += math.max(row.Size.Y.Offset, row.AbsoluteSize.Y, 82)
		end
	end

	if rowCount > 1 then
		height += (rowCount - 1) * 10
	end
	return math.max(height, rowCount * 92)
end

local function forceGiftsLayout(context: string, rows)
	refreshGiftsUiBinding("forceLayout:" .. context)
	giftsMainFrame.Visible = true
	giftsMainFrame.BackgroundTransparency = 1
	giftsMainFrame.BorderSizePixel = 0
	giftsMainFrame.ClipsDescendants = true
	giftsMainFrame.Size = UDim2.new(1, -42, 1, -126)
	giftsMainFrame.Position = UDim2.fromOffset(18, 116)
	giftsMainFrame.ZIndex = math.max(giftsMainFrame.ZIndex, 3)

	local container = getGiftsSlotContainer()
	if container:IsA("GuiObject") then
		container.Visible = true
		container.Active = true
		container.ClipsDescendants = true
		container.ZIndex = math.max(container.ZIndex, 4)
		if container.Size.X.Offset == 0 and container.Size.X.Scale == 0 then
			container.Size = UDim2.fromScale(1, 1)
		end
	end

	if #rows == 0 then
		if container:IsA("ScrollingFrame") then
			container.AutomaticCanvasSize = Enum.AutomaticSize.None
			container.CanvasSize = UDim2.fromOffset(0, 0)
		end
		return
	end

	local layout = getGiftsListLayout(container)
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Name = "SlotLayout"
		layout.Parent = container
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 10)
	end

	for index, row in ipairs(rows) do
		ensureRenderableGiftRow(row, index)
	end

	if container:IsA("ScrollingFrame") then
		local canvasHeight = estimateRowsCanvasHeight(rows)
		local layoutHeight = layout.AbsoluteContentSize.Y
		if layoutHeight > 0 then
			canvasHeight = math.max(canvasHeight, layoutHeight + 24)
		end
		container.AutomaticCanvasSize = Enum.AutomaticSize.None
		container.CanvasSize = UDim2.fromOffset(0, canvasHeight)
		container.ScrollingEnabled = true
		container.ScrollingDirection = Enum.ScrollingDirection.Y
		container.ScrollBarThickness = math.max(container.ScrollBarThickness, 8)
	end
end

local function rowIsOutsideScrollViewport(row: GuiObject, container: Instance): boolean
	if not container:IsA("GuiObject") then
		return false
	end
	if row.AbsoluteSize.Y <= 0 or container.AbsoluteSize.Y <= 0 then
		return true
	end

	local rowTop = row.AbsolutePosition.Y
	local rowBottom = rowTop + row.AbsoluteSize.Y
	local viewTop = container.AbsolutePosition.Y
	local viewBottom = viewTop + container.AbsoluteSize.Y
	return rowBottom <= viewTop or rowTop >= viewBottom
end

local function logGiftRenderDiagnostics(context: string, rows)
	if not GIFT_STARTUP_DEBUG then
		return
	end

	local container = getGiftsSlotContainer()
	local layout = getGiftsListLayout(container)
	local rowParts = {}
	for index, row in ipairs(rows) do
		if row:IsA("GuiObject") then
			rowParts[#rowParts + 1] = string.format(
				"%d:%s:%s:%s:%s",
				index,
				row.Name,
				tostring(row.Visible),
				tostring(row.Size),
				tostring(row.AbsoluteSize)
			)
		end
	end

	local stateKey = table.concat(rowParts, "|")
		.. "|container="
		.. safeName(container)
		.. "|canvas="
		.. tostring(container:IsA("ScrollingFrame") and container.CanvasSize or "n/a")
	if giftRenderDiagnosticsState == stateKey then
		return
	end
	giftRenderDiagnosticsState = stateKey

	giftDebugWarn(
		"renderDiagnostics",
		"context",
		context,
		"rewardCount",
		#orderedIds,
		"rowCount",
		#rows,
		"mapped",
		totalGifts,
		"main",
		safeName(giftsMainFrame),
		"mainVisible",
		tostring(giftsMainFrame.Visible),
		"mainSize",
		tostring(giftsMainFrame.Size),
		"mainAbsoluteSize",
		tostring(giftsMainFrame.AbsoluteSize),
		"container",
		safeName(container),
		"containerVisible",
		tostring(container:IsA("GuiObject") and container.Visible or "n/a"),
		"containerSize",
		tostring(container:IsA("GuiObject") and container.Size or "n/a"),
		"containerAbsoluteSize",
		tostring(container:IsA("GuiObject") and container.AbsoluteSize or "n/a"),
		"canvasSize",
		tostring(container:IsA("ScrollingFrame") and container.CanvasSize or "n/a"),
		"automaticCanvasSize",
		tostring(container:IsA("ScrollingFrame") and container.AutomaticCanvasSize or "n/a"),
		"layoutContentSize",
		tostring(layout and layout.AbsoluteContentSize or "nil")
	)

	for index, row in ipairs(rows) do
		if row:IsA("GuiObject") then
			local claimButton = getClaimButton(row)
			giftDebugWarn(
				"rowRenderState",
				"context",
				context,
				"index",
				index,
				"rewardId",
				tostring(row:GetAttribute("RewardId")),
				"row",
				safeName(row),
				"parent",
				safeName(row.Parent),
				"visible",
				tostring(row.Visible),
				"size",
				tostring(row.Size),
				"absoluteSize",
				tostring(row.AbsoluteSize),
				"z",
				row.ZIndex,
				"layout",
				row.LayoutOrder,
				"outsideScrollViewport",
				tostring(rowIsOutsideScrollViewport(row, container)),
				"claim",
				safeName(claimButton),
				"claimVisible",
				tostring(claimButton and claimButton:IsA("GuiObject") and claimButton.Visible or "nil"),
				"claimSize",
				tostring(claimButton and claimButton:IsA("GuiObject") and claimButton.Size or "nil"),
				"claimAbsoluteSize",
				tostring(claimButton and claimButton:IsA("GuiObject") and claimButton.AbsoluteSize or "nil"),
				"claimZ",
				tostring(claimButton and claimButton:IsA("GuiObject") and claimButton.ZIndex or "nil")
			)
		end
	end
end

local function buildSlotsOnce()
	refreshGiftsUiBinding("buildSlotsOnce")
	table.clear(orderedIds)
	for id in pairs(RewardsConfig) do
		if typeof(id) == "number" then
			table.insert(orderedIds, id)
		end
	end
	table.sort(orderedIds, function(a, b)
		return a < b
	end)

	logScrollState("buildSlots")

	local templates = collectSlotFrames()
	cleanupClaimConnectionsForTemplates(templates)
	totalGifts = math.min(#orderedIds, #templates)
	table.clear(slotsById)
	local slotContainerPath = safeName(getGiftsSlotContainer())
	local slotLogState = string.format("%d|%d|%d|%s", #templates, #orderedIds, totalGifts, slotContainerPath)
	if giftSlotsFoundLogState ~= slotLogState then
		giftSlotsFoundLogState = slotLogState
		giftStartupLog(
			"giftSlotsFound",
			"slotTemplates",
			#templates,
			"configRewards",
			#orderedIds,
			"renderable",
			totalGifts,
			"container",
			slotContainerPath
		)
	end

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
		if claimButtonConnections[slotFrame] == nil then
			slotFrame:SetAttribute("Hooked", false)
			slotFrame:SetAttribute("HookedRewardId", nil)
		end
		ensureRenderableGiftRow(slotFrame, i)

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

	if #templates > 0 then
		forceGiftsLayout("buildSlotsOnce", templates)
		logGiftRenderDiagnostics("buildSlotsOnce", templates)
	end
	updateHud()
end

local function buildSlotsWithWait()
	local expectedRewards = 0
	for attempt = 1, 15 do
		buildSlotsOnce()
		expectedRewards = #orderedIds
		if expectedRewards > 0 and totalGifts >= expectedRewards then
			return true
		end
		if attempt == 1 then
			dumpGiftsMainTree("firstEmptySlotPass")
		end
		task.wait(0.2)
	end

	dumpGiftsMainTree("beforeFallbackSlotCreate")
	giftStartupWarn(
		"slotBuildFallback",
		"reason",
		if totalGifts <= 0 then "no slot-shaped descendants under Gifts.Main" else "incomplete slot-shaped descendants under Gifts.Main",
		"expected",
		expectedRewards,
		"found",
		totalGifts,
		"container",
		safeName(getGiftsSlotContainer())
	)
	ensureFallbackSlotContainer(math.max(expectedRewards, 1))
	dumpGiftsMainTree("afterFallbackSlotCreate")
	buildSlotsOnce()
	expectedRewards = #orderedIds
	if expectedRewards > 0 and totalGifts >= expectedRewards then
		return true
	end

	for _ = 1, 40 do
		buildSlotsOnce()
		expectedRewards = #orderedIds
		if expectedRewards > 0 and totalGifts >= expectedRewards then
			return true
		end
		task.wait(0.2)
	end

	logScrollState("waitTimeout")
	dumpGiftsMainTree("waitTimeout")
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
	setAuthoritativeSyncPending(false)

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

	local rows = collectSlotFrames()
	forceGiftsLayout("legacyState", rows)
	logGiftRenderDiagnostics("legacyState", rows)
	updateHud()
end

local function initialiseButtonsFromState(syncState)
	if typeof(syncState) ~= "table" then
		giftError("syncState payload must be a table, got", typeof(syncState))
		return false, 0
	end

	local cycleStartPlayTime = tonumber(syncState.CycleStartPlayTime)
	local currentPlayTime = getEffectiveCurrentPlayTime(syncState)
	if not cycleStartPlayTime or not currentPlayTime then
		giftError("syncState missing play time fields", syncState)
		return false, 0
	end

	local claimedRewards = normalizeClaimedRewards(syncState.ClaimedRewards)
	local elapsedPlayTime = math.max(0, currentPlayTime - cycleStartPlayTime)
	setAuthoritativeSyncPending(false)
	local timersUpdated = 0

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
			timersUpdated += 1
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

	local rows = collectSlotFrames()
	forceGiftsLayout("syncState", rows)
	logGiftRenderDiagnostics("syncState", rows)
	updateHud()
	return true, timersUpdated
end

local building = false
local rebuildScheduled = false
local suppressGiftTreeRebuilds = 0
local pendingState = nil
local latestRewardState = nil
local latestSyncState = nil

local function withGiftTreeRebuildsSuppressed(callback)
	suppressGiftTreeRebuilds += 1
	local ok, result = pcall(callback)
	suppressGiftTreeRebuilds = math.max(0, suppressGiftTreeRebuilds - 1)
	if not ok then
		error(result, 2)
	end
	return result
end

local function applySyncStateNow(syncState, context: string)
	local claimedCount, currentPlayTime, cycleStartPlayTime = getSyncStateSummary(syncState)
	local ok, timersUpdated = initialiseButtonsFromState(syncState)
	giftSyncClientLog(
		"[GIFT][SYNC][APPLY]",
		"context",
		tostring(context),
		"payloadType",
		typeof(syncState),
		"claimed",
		claimedCount,
		"currentPlayTime",
		tostring(currentPlayTime),
		"cycleStart",
		tostring(cycleStartPlayTime),
		"rowCount",
		getMappedGiftRowCount(),
		"timersUpdated",
		tonumber(timersUpdated) or 0,
		"ok",
		tostring(ok)
	)
	if ok == true then
		hasAppliedServerSync = true
		logSyncRequestStop("sync_applied")
	end
	return ok == true
end

local function applyRewardState(state)
	if typeof(state) == "table" then
		applySyncStateNow(state, "pending")
	elseif typeof(state) == "number" then
		initialiseButtonsFromLegacyEpoch(state)
	else
		giftError("Unsupported pending time reward state", typeof(state))
	end
end

local function applyPendingState()
	if pendingState == nil then
		return
	end

	local state = pendingState
	pendingState = nil
	applyRewardState(state)
end

local function applyLatestStateOrFallback(context: string)
	if latestSyncState ~= nil then
		local claimedCount, currentPlayTime, cycleStartPlayTime = getSyncStateSummary(latestSyncState)
		giftSyncClientLog(
			"[GIFT][SYNC][REAPPLY_AFTER_REBUILD]",
			"context",
			tostring(context),
			"claimed",
			claimedCount,
			"currentPlayTime",
			tostring(currentPlayTime),
			"cycleStart",
			tostring(cycleStartPlayTime),
			"rowCount",
			getMappedGiftRowCount()
		)
		applySyncStateNow(latestSyncState, "rebuild:" .. tostring(context))
	elseif latestRewardState ~= nil then
		pendingState = latestRewardState
		applyPendingState()
	elseif not hasReceivedServerSync then
		setAuthoritativeSyncPending(true)
		updateHud()
		if requestServerSync then
			requestServerSync("slotsReady")
		end
	end
end

local function getConfiguredRewardCount(): number
	local count = 0
	for id in pairs(RewardsConfig) do
		if typeof(id) == "number" then
			count += 1
		end
	end
	return count
end

local function hasCompleteLiveSlotMapping(): boolean
	refreshGiftsUiBinding("hasCompleteLiveSlotMapping")
	local expected = 0
	for id in pairs(RewardsConfig) do
		if typeof(id) == "number" then
			expected += 1
			local slotFrame = slotsById[id]
			if not (slotFrame and slotFrame.Parent and slotFrame:IsDescendantOf(giftsMainFrame)) then
				return false
			end
		end
	end

	return expected > 0 and totalGifts >= expected
end

local function runSlotBuild(context: string): boolean
	if building then
		return false
	end

	refreshGiftsUiBinding("runSlotBuild:" .. context)
	building = true
	giftDebugWarn(
		"slotBuildStart",
		"context",
		context,
		"expected",
		getConfiguredRewardCount(),
		"currentTotal",
		totalGifts,
		"mainChildren",
		#giftsMainFrame:GetChildren(),
		"mainDescendants",
		#giftsMainFrame:GetDescendants()
	)
	local buildOk, buildResult = pcall(function()
		return withGiftTreeRebuildsSuppressed(buildSlotsWithWait)
	end)
	building = false
	if not buildOk then
		giftError("slot build failed", "context", context, "error", tostring(buildResult))
		return false
	end
	local ok = buildResult == true
	giftDebugWarn(
		"slotBuildDone",
		"context",
		context,
		"ok",
		tostring(ok),
		"expected",
		getConfiguredRewardCount(),
		"total",
		totalGifts,
		"mainChildren",
		#giftsMainFrame:GetChildren(),
		"mainDescendants",
		#giftsMainFrame:GetDescendants()
	)
	if ok then
		applyLatestStateOrFallback(context)
	end
	return ok
end

local function scheduleSlotRebuild(context: string)
	if suppressGiftTreeRebuilds > 0 then
		return
	end

	if rebuildScheduled then
		return
	end

	rebuildScheduled = true
	task.delay(0.15, function()
		rebuildScheduled = false

		refreshGiftsUiBinding("scheduledRebuild:" .. context)
		local expectedRewards = getConfiguredRewardCount()
		local templates = collectSlotFrames()
		if expectedRewards > 0 and #templates >= expectedRewards and hasCompleteLiveSlotMapping() then
			if latestSyncState ~= nil then
				giftSyncClientLog(
					"[GIFT][SYNC][REAPPLY_AFTER_REBUILD]",
					"context",
					"scheduledRebuildReady:" .. tostring(context),
					"rowCount",
					getMappedGiftRowCount()
				)
				applySyncStateNow(latestSyncState, "scheduledRebuildReady:" .. tostring(context))
			elseif pendingState ~= nil then
				applyPendingState()
			end
			return
		end

		giftDebugWarn(
			"slotRebuildNeeded",
			"context",
			context,
			"expected",
			expectedRewards,
			"mapped",
			totalGifts,
			"templates",
			#templates,
			"mainChildren",
			#giftsMainFrame:GetChildren(),
			"mainDescendants",
			#giftsMainFrame:GetDescendants()
		)

		if building then
			scheduleSlotRebuild(context .. ":afterCurrentBuild")
			return
		end

		runSlotBuild(context)
	end)
end

local giftMainDescendantAddedConnection = nil
local giftMainDescendantRemovingConnection = nil
local giftFrameVisibleConnection = nil
local watchedGiftsFrame = nil
local watchedGiftsMainFrame = nil

local function isGiftContentStructureName(name: string): boolean
	return name == "Main"
		or name == "Scroll"
		or name == "ClaimButton"
		or string.match(name, "^Slot%d+$") ~= nil
end

local function isGiftRootStructureName(name: string): boolean
	return name == "Gifts" or name == "Main" or name == "Scroll" or string.match(name, "^Slot%d+$") ~= nil
end

local function bindGiftContentTreeWatchers(context: string)
	if not refreshGiftsUiBinding("bindWatchers:" .. context) then
		return
	end

	if watchedGiftsFrame == giftsFrame
		and watchedGiftsMainFrame == giftsMainFrame
		and giftMainDescendantAddedConnection
		and giftMainDescendantRemovingConnection
		and giftFrameVisibleConnection then
		return
	end

	if giftMainDescendantAddedConnection then
		giftMainDescendantAddedConnection:Disconnect()
		giftMainDescendantAddedConnection = nil
	end
	if giftMainDescendantRemovingConnection then
		giftMainDescendantRemovingConnection:Disconnect()
		giftMainDescendantRemovingConnection = nil
	end
	if giftFrameVisibleConnection then
		giftFrameVisibleConnection:Disconnect()
		giftFrameVisibleConnection = nil
	end
	watchedGiftsFrame = giftsFrame
	watchedGiftsMainFrame = giftsMainFrame

	giftMainDescendantAddedConnection = giftsMainFrame.DescendantAdded:Connect(function(descendant)
		if suppressGiftTreeRebuilds > 0 then
			return
		end
		if isGiftContentStructureName(descendant.Name) then
			scheduleSlotRebuild("descendantAdded:" .. descendant.Name)
		end
	end)

	giftMainDescendantRemovingConnection = giftsMainFrame.DescendantRemoving:Connect(function(descendant)
		if suppressGiftTreeRebuilds > 0 then
			return
		end
		if isGiftContentStructureName(descendant.Name) or isSlotFrame(descendant) then
			scheduleSlotRebuild("descendantRemoving:" .. descendant.Name)
		end
	end)

	giftFrameVisibleConnection = giftsFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if giftsFrame.Visible then
			giftsMainFrame.Visible = true
			logScrollState("panelOpen")
			scheduleSlotRebuild("panelOpen")
			if latestSyncState == nil or not hasAppliedServerSync then
				setAuthoritativeSyncPending(true)
				if requestServerSync then
					requestServerSync("panelOpenMissingSync")
				end
			end
			task.defer(function()
				local rows = collectSlotFrames()
				forceGiftsLayout("panelOpen", rows)
				logGiftRenderDiagnostics("panelOpen", rows)
			end)
			giftLog("[GIFT][OPEN]", string.format("panel=%s visible=true slots=%d", safeName(giftsFrame), totalGifts))
		end
	end)

	giftStartupLog("contentWatchersBound", "context", context, "main", safeName(giftsMainFrame))
end

bindGiftContentTreeWatchers("startup")

mainGui.DescendantAdded:Connect(function(descendant)
	if suppressGiftTreeRebuilds > 0 then
		return
	end
	if isGiftRootStructureName(descendant.Name) then
		task.defer(function()
			if refreshGiftsUiBinding("mainGuiDescendantAdded:" .. descendant.Name) then
				bindGiftContentTreeWatchers("mainGuiDescendantAdded:" .. descendant.Name)
				scheduleSlotRebuild("mainGuiDescendantAdded:" .. descendant.Name)
			end
		end)
	end
end)

mainGui.DescendantRemoving:Connect(function(descendant)
	if suppressGiftTreeRebuilds > 0 then
		return
	end
	if isGiftRootStructureName(descendant.Name) then
		task.delay(0.25, function()
			if refreshGiftsUiBinding("mainGuiDescendantRemoving:" .. descendant.Name) then
				bindGiftContentTreeWatchers("mainGuiDescendantRemoving:" .. descendant.Name)
				scheduleSlotRebuild("mainGuiDescendantRemoving:" .. descendant.Name)
			end
		end)
	end
end)

logHudBinding()

if giftsFrame.Visible then
	logScrollState("panelOpen")
	scheduleSlotRebuild("initialPanelOpen")
	giftLog("[GIFT][OPEN]", string.format("panel=%s visible=true slots=%d", safeName(giftsFrame), totalGifts))
end

task.spawn(function()
	runSlotBuild("initial")
end)

task.spawn(function()
	while true do
		updateHud()
		task.wait(HUD_UPDATE_INTERVAL)
	end
end)

local snapshotRequestLoopRunning = false

local function getLatestSnapshotClaimedCount(): number
	local claimedCount = 0
	if latestSyncState ~= nil then
		claimedCount = getSyncStateSummary(latestSyncState)
	end
	return tonumber(claimedCount) or 0
end

local function logSnapshotRequest(reason: string, attempt: number)
	logSnapshotStatus(
		"[GIFT][SNAPSHOT][REQUEST]",
		"attempt",
		attempt,
		"reason",
		tostring(reason),
		"claimed",
		getLatestSnapshotClaimedCount(),
		"rowCount",
		getMappedGiftRowCount(),
		"playerDataReady",
		tostring(player:GetAttribute("PlayerDataReady") == true)
	)
end

local function logSnapshotFailure(reason: string, attempt: number, errorReason: string)
	warn(
		"[GIFT][SNAPSHOT][FAILED]",
		"attempt",
		attempt,
		"reason",
		tostring(reason),
		"error",
		tostring(errorReason),
		"claimed",
		getLatestSnapshotClaimedCount(),
		"rowCount",
		getMappedGiftRowCount(),
		"playerDataReady",
		tostring(player:GetAttribute("PlayerDataReady") == true)
	)
end

local function requestSnapshotAttempt(reason: string, attempt: number): boolean
	logSnapshotRequest(reason, attempt)

	local ok, response = pcall(function()
		return SnapshotRequest:InvokeServer()
	end)
	if not ok then
		logSnapshotFailure(reason, attempt, tostring(response))
		return false
	end

	if typeof(response) ~= "table" then
		logSnapshotFailure(reason, attempt, "invalid_response_" .. typeof(response))
		return false
	end

	if response.ok ~= true then
		logSnapshotFailure(reason, attempt, tostring(response.error or "server_rejected"))
		return false
	end

	local syncState = response.state
	if typeof(syncState) ~= "table" then
		logSnapshotFailure(reason, attempt, "invalid_state_" .. typeof(syncState))
		return false
	end

	syncState = markSyncStateReceived(syncState)
	latestSyncState = syncState
	latestRewardState = syncState
	hasReceivedServerSync = true

	local claimedCount = getSyncStateSummary(syncState)
	local applied = false
	if hasCompleteLiveSlotMapping() then
		applied = applySyncStateNow(syncState, "snapshot:" .. tostring(reason))
	else
		pendingState = syncState
		scheduleSlotRebuild("snapshot:" .. tostring(reason))
	end

	logSnapshotStatus(
		"[GIFT][SNAPSHOT][SUCCESS]",
		"attempt",
		attempt,
		"reason",
		tostring(reason),
		"claimed",
		tonumber(claimedCount) or 0,
		"rowCount",
		getMappedGiftRowCount(),
		"playerDataReady",
		tostring(player:GetAttribute("PlayerDataReady") == true),
		"applied",
		tostring(applied)
	)

	return applied
end

local function logSnapshotFinalFailure(reason: string)
	warn(
		"[GIFT][SNAPSHOT][FAILED]",
		"no authoritative snapshot applied after retries",
		"reason",
		tostring(reason),
		"claimed",
		getLatestSnapshotClaimedCount(),
		"rowCount",
		getMappedGiftRowCount(),
		"playerDataReady",
		tostring(player:GetAttribute("PlayerDataReady") == true),
		"remote",
		safeName(SnapshotRequest),
		"onClientEventConnected",
		tostring(syncEventConnected),
		"panelVisible",
		tostring(giftsFrame.Visible),
		"hasReceivedServerSync",
		tostring(hasReceivedServerSync),
		"hasAppliedServerSync",
		tostring(hasAppliedServerSync)
	)
end

requestServerSync = function(reason: string)
	if hasAppliedServerSync then
		logSyncRequestStop("sync_applied")
		return
	end

	if snapshotRequestLoopRunning then
		return
	end

	snapshotRequestLoopRunning = true
	syncRequestStopLogged = false

	task.spawn(function()
		for attempt = 1, MAX_SYNC_REQUEST_ATTEMPTS do
			if hasAppliedServerSync then
				logSyncRequestStop("sync_applied")
				snapshotRequestLoopRunning = false
				return
			end

			if requestSnapshotAttempt(reason, attempt) then
				snapshotRequestLoopRunning = false
				return
			end

			local deadline = os.clock() + SYNC_REQUEST_RETRY_SECONDS
			while os.clock() < deadline do
				if hasAppliedServerSync then
					logSyncRequestStop("sync_applied")
					snapshotRequestLoopRunning = false
					return
				end
				task.wait(0.1)
			end
		end

		snapshotRequestLoopRunning = false
		if not hasAppliedServerSync then
			logSnapshotFinalFailure(reason)
		end
	end)
end

giftStartupLog("remoteClientConnectionMade", "signal", "OnClientEvent", "remote", safeName(Remote))
syncEventConnected = true
Remote.OnClientEvent:Connect(function(action, a, b, c)
	local claimedCount, currentPlayTime, cycleStartPlayTime = getSyncStateSummary(a)
	giftSyncClientLog(
		"[GIFT][SYNC][CLIENT][RECEIVED]",
		"action",
		tostring(action),
		"payloadType",
		typeof(a),
		"claimed",
		claimedCount,
		"currentPlayTime",
		tostring(currentPlayTime),
		"cycleStart",
		tostring(cycleStartPlayTime),
		"rowCount",
		getMappedGiftRowCount()
	)

	if action == "syncState" then
		a = markSyncStateReceived(a)
		hasReceivedServerSync = true
		latestSyncState = a
		latestRewardState = a
		local claimedPayload = if typeof(a) == "table" then a.ClaimedRewards else nil
		giftLog(
			"[GIFT][DATA]",
			"remoteAction=syncState",
			"claimedCount",
			getClaimedCount(claimedPayload),
			"totalSlots",
			totalGifts
		)
		if not hasCompleteLiveSlotMapping() then
			pendingState = a
			giftSyncClientLog(
				"[GIFT][SYNC][DEFER_APPLY_ROWS_NOT_READY]",
				"action",
				tostring(action),
				"payloadType",
				typeof(a),
				"claimed",
				getClaimedCount(claimedPayload),
				"currentPlayTime",
				tostring(currentPlayTime),
				"cycleStart",
				tostring(cycleStartPlayTime),
				"rowCount",
				getMappedGiftRowCount(),
				"totalGifts",
				totalGifts
			)
			scheduleSlotRebuild("remote:syncState")
			return
		end
		applySyncStateNow(a, "remote:syncState")
	elseif action == "startCycle" or action == "cycleReset" then
		hasReceivedServerSync = true
		if typeof(a) ~= "number" then
			giftError("startCycle/cycleReset bad epoch", a, "typeof", typeof(a))
			return
		end
		latestRewardState = a
		giftLog("[GIFT][DATA]", "remoteAction", action, "epoch", a)
		if not hasCompleteLiveSlotMapping() then
			pendingState = a
			scheduleSlotRebuild("remote:" .. action)
			return
		end
		initialiseButtonsFromLegacyEpoch(a)
	elseif action == "forceReady" then
		giftLog("[GIFT][RENDER]", "remoteAction=forceReady", "totalSlots", totalGifts)
		if not hasCompleteLiveSlotMapping() then
			scheduleSlotRebuild("remote:forceReady")
		end
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
		if typeof(latestRewardState) == "table" and id ~= nil then
			local claimedRewards = latestRewardState.ClaimedRewards
			if typeof(claimedRewards) ~= "table" then
				claimedRewards = {}
				latestRewardState.ClaimedRewards = claimedRewards
			end
			claimedRewards[tostring(id)] = true
		end
		local slotFrame = slotsById[id]
		if not slotFrame then
			giftError("claimed action missing slot frame for id", id)
			scheduleSlotRebuild("remote:claimedMissingSlot")
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

task.defer(function()
	if not hasReceivedServerSync then
		setAuthoritativeSyncPending(true)
		requestServerSync("clientConnected")
	end
end)

return {}
