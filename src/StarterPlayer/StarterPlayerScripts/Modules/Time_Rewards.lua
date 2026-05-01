local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GIFT_CLIENT_DEBUG_VERSION = "gifts-client-ui-slots-debug-2026-05-01"
local GIFT_STARTUP_DEBUG = true
local GIFT_DEBUG = false
local REQUIRED_WAIT_SECONDS = 15
local OPTIONAL_WAIT_SECONDS = 5

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

local function waitForChildLogged(parent: Instance?, childName: string, timeoutSeconds: number, label: string)
	if not parent then
		giftStartupWarn("missingParent", "path", label, "child", childName)
		return nil
	end

	giftStartupLog("wait", "path", label, "parent", safeName(parent), "timeout", timeoutSeconds)
	local child = parent:WaitForChild(childName, timeoutSeconds)
	if child then
		giftStartupLog("found", "path", label, "instance", safeName(child), "class", child.ClassName)
	else
		giftStartupWarn("missing", "path", label, "parent", safeName(parent), "timeout", timeoutSeconds)
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

	giftStartupWarn(
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
end

local function auditGiftsInputBlockers(context: string)
	local closeButton = findDescendantGuiButton(giftsFrame, "X")
	if not closeButton then
		giftStartupWarn("xAuditSkipped", "context", context, "reason", "X button missing", "frame", safeName(giftsFrame))
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
					giftStartupWarn(
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
		giftStartupWarn("xButtonMissing", "frame", safeName(giftsFrame))
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
		closeButton.ZIndex
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

local InstantRewardsEvent = waitForChildLogged(
	TimeRewardsFolder,
	"TriggerInstantRewards",
	OPTIONAL_WAIT_SECONDS,
	"ReplicatedStorage.Modules.TimeRewards.TriggerInstantRewards"
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
	giftStartupWarn(
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

if not (Modules and TimeRewardsFolder and RewardsConfig and Remote and Shorten) then
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
		giftStartupWarn("hudBadgeMissing", "button", safeName(hudGifts), "action", "creating fallback Not")
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
		giftStartupWarn("hudBadgeTextMissing", "badge", safeName(badge), "action", "creating fallback TextLB")
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
local WHITE_COLOR = Color3.new(1, 1, 1)
local GREEN_COLOR = Color3.new(0, 1, 0)
local endTimes = {}
local threads = {}
local slotsById = {}
local orderedIds = {}
local totalGifts = 0
local timerLogStateByPath = {}
local giftSlotsFoundLogState = nil
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
	if dumpedGiftsMainTreeContexts[context] then
		return
	end
	dumpedGiftsMainTreeContexts[context] = true

	local descendants = giftsMainFrame:GetDescendants()
	giftStartupWarn(
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
			giftStartupWarn(
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
				giftStartupWarn("mainTreeDumpTruncated", "context", context, "limit", 240, "totalDescendants", #descendants)
				return
			end
			walk(child, depth + 1)
		end
	end

	walk(giftsMainFrame, 1)
	if lineCount == 0 then
		giftStartupWarn("mainTreeEmpty", "context", context, "root", safeName(giftsMainFrame))
	end
end

local function getGiftsSlotContainer()
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
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
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
		slot.Size = UDim2.new(1, -30, 0, 82)
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

	giftStartupWarn(
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

	claimBtn.Activated:Connect(function()
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
	for attempt = 1, 10 do
		buildSlotsOnce()
		expectedRewards = #orderedIds
		-- Accept partial slot sets so countdown sync still runs even when UI exposes fewer
		-- visible slot templates than configured rewards.
		if totalGifts > 0 then
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
		"no slot-shaped descendants under Gifts.Main",
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
	if totalGifts > 0 then
		return true
	end

	for _ = 1, 40 do
		buildSlotsOnce()
		expectedRewards = #orderedIds
		if totalGifts > 0 then
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

giftStartupLog("remoteClientConnectionMade", "signal", "OnClientEvent", "remote", safeName(Remote))
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
