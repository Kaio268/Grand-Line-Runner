local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local HudStatRow = require(UiFolder:WaitForChild("Hud"):WaitForChild("HudStatRow"))
local HudStatNotificationLayer = require(UiFolder:WaitForChild("Hud"):WaitForChild("HudStatNotificationLayer"))
local HudCounterConfig = require(UiFolder:WaitForChild("Hud"):WaitForChild("HudCounterConfig"))

local e = React.createElement

local STAT_ORDER = {
	{ name = "Comet", kind = "Comet" },
	{ name = "Speed", kind = "Speed" },
	{ name = "Money", kind = "Money" },
}

local STAT_ICON_ASSET_OVERRIDES = {
	Comet = "",
	Speed = "rbxassetid://108512951338844",
	Money = "rbxassetid://76300573750363",
}

local iconOverrideSources = {}

local COUNTERS_LEFT_PADDING = HudCounterConfig.LeftPadding
local COUNTERS_BOTTOM_PADDING = HudCounterConfig.BottomPadding
local COUNTERS_WIDTH = HudCounterConfig.Width
local TARGET_ROW_HEIGHT = HudCounterConfig.RowHeight
local TARGET_ROW_SPACING = HudCounterConfig.RowSpacing
local ICON_SLOT_WIDTH = HudCounterConfig.IconSlotWidth
local BAR_GAP = HudCounterConfig.BarGap
local DISPLAY_LAYER_ZINDEX = HudCounterConfig.DisplayLayerZIndex

local PROTECTED_NAMES = {
	UIGradient = true,
	UIStroke = true,
	UIScale = true,
	ReactHudCountersLayer = true,
	ReactHudCountersStack = true,
	ReactHudMoneyRowAnchor = true,
	ReactHudMoneyParticles = true,
	ReactHudCounterNotifications = true,
}

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactHudCountersRoot"

local root = ReactRoblox.createRoot(rootContainer)

local destroyed = false
local renderQueued = false

local function isReactNode(instance)
	return typeof(instance) == "Instance" and string.sub(instance.Name, 1, 8) == "ReactHud"
end

local function setHiddenGuiObject(guiObject)
	if not guiObject or not guiObject:IsA("GuiObject") then
		return
	end

	guiObject.Visible = false
	guiObject.BackgroundTransparency = 1

	if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox") then
		guiObject.TextTransparency = 1
		guiObject.TextStrokeTransparency = 1
	end
end

local function ensureFrame(parent, name, zIndex)
	local frame = parent:FindFirstChild(name)
	if frame and frame:IsA("Frame") then
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = false
		frame.ZIndex = zIndex
		return frame
	end

	frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = false
	frame.ZIndex = zIndex
	frame.Parent = parent

	return frame
end

local function ensureDisplayLayer(hud)
	local layer = ensureFrame(hud, "ReactHudCountersLayer", DISPLAY_LAYER_ZINDEX)
	local moneyAnchor = ensureFrame(layer, "ReactHudMoneyRowAnchor", DISPLAY_LAYER_ZINDEX + 10)
	local moneyParticles = ensureFrame(moneyAnchor, "ReactHudMoneyParticles", DISPLAY_LAYER_ZINDEX + 11)
	local notifications = ensureFrame(layer, "ReactHudCounterNotifications", DISPLAY_LAYER_ZINDEX + 12)

	moneyParticles.AnchorPoint = Vector2.new(0, 0)
	moneyParticles.Position = UDim2.fromOffset(0, 0)
	moneyParticles.Size = UDim2.fromScale(1, 1)
	moneyParticles.ClipsDescendants = false

	notifications.AnchorPoint = Vector2.new(0, 0)
	notifications.ClipsDescendants = false

	return layer
end

local function layoutDisplayLayer(layer, rowCount)
	if not layer then
		return
	end

	local _, bottomRightInset = GuiService:GetGuiInset()
	local totalHeight = HudCounterConfig.getTotalHeight(rowCount)
	local moneyRowY = HudCounterConfig.getRowY(math.min(3, math.max(1, rowCount)))

	layer.AnchorPoint = Vector2.new(0, 1)
	layer.Position = UDim2.new(0, COUNTERS_LEFT_PADDING, 1, -(COUNTERS_BOTTOM_PADDING + bottomRightInset.Y))
	layer.Size = UDim2.new(0, COUNTERS_WIDTH, 0, totalHeight)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ClipsDescendants = false
	layer.ZIndex = DISPLAY_LAYER_ZINDEX

	local moneyAnchor = layer:FindFirstChild("ReactHudMoneyRowAnchor")
	if moneyAnchor and moneyAnchor:IsA("Frame") then
		moneyAnchor.Position = UDim2.new(0, HudCounterConfig.getContentLeft(), 0, moneyRowY)
		moneyAnchor.Size = UDim2.new(0, HudCounterConfig.getContentWidth(), 0, TARGET_ROW_HEIGHT)
		moneyAnchor.ZIndex = DISPLAY_LAYER_ZINDEX + 10
	end

	local notifications = layer:FindFirstChild("ReactHudCounterNotifications")
	if notifications and notifications:IsA("Frame") then
		local notificationHeight = HudCounterConfig.NotificationHeight
		notifications.Position = UDim2.new(
			0,
			HudCounterConfig.getNotificationX(),
			0,
			math.max(0, moneyRowY - notificationHeight + 6)
		)
		notifications.Size = UDim2.new(0, HudCounterConfig.NotificationWidth, 0, notificationHeight)
		notifications.ZIndex = DISPLAY_LAYER_ZINDEX + 12
	end
end

local function isProtectedDescendant(host, descendant)
	local current = descendant
	while current and current ~= host do
		if PROTECTED_NAMES[current.Name] or isReactNode(current) then
			return true
		end
		current = current.Parent
	end

	return false
end

local function findCounterIcon(counters, host, statName)
	local bestCandidate = nil
	local bestScore = -math.huge
	local hostWidth = math.max(host.AbsoluteSize.X, host.Size.X.Offset, 1)
	local hostHeight = math.max(host.AbsoluteSize.Y, host.Size.Y.Offset, 1)
	local hostY = host.AbsolutePosition.Y ~= 0 and host.AbsolutePosition.Y or host.Position.Y.Offset
	local statNameLower = string.lower(statName or host.Name or "")

	for _, descendant in ipairs(host:GetDescendants()) do
		if (descendant:IsA("ImageLabel") or descendant:IsA("ImageButton"))
			and not isProtectedDescendant(host, descendant)
		then
			local image = tostring(descendant.Image or "")
			if image ~= "" then
				local absoluteSize = descendant.AbsoluteSize
				local width = math.max(absoluteSize.X, descendant.Size.X.Offset, 1)
				local height = math.max(absoluteSize.Y, descendant.Size.Y.Offset, 1)
				local score = width * height
				local nameLower = string.lower(descendant.Name)

				if string.find(nameLower, "icon", 1, true) then
					score += 3000
				end
				if string.find(nameLower, "image", 1, true) then
					score += 500
				end
				if width > hostWidth * 0.85 or height > hostHeight * 0.85 then
					score -= 4000
				end
				if descendant.ImageTransparency >= 0.95 then
					score -= 3000
				end
				if descendant.ImageRectSize.X > 0 and descendant.ImageRectSize.Y > 0 then
					score += 900
				end
				if descendant.Position.X.Offset <= 0 then
					score += 400
				end

				if score > bestScore then
					bestScore = score
					bestCandidate = descendant
				end
			end
		end
	end

	local function considerExternal(candidate)
		if not candidate or not (candidate:IsA("ImageLabel") or candidate:IsA("ImageButton")) then
			return
		end
		if candidate:IsDescendantOf(host) then
			return
		end

		local parent = candidate.Parent
		if not parent or parent.Name == "Not" or isReactNode(parent) then
			return
		end

		local image = tostring(candidate.Image or "")
		if image == "" or candidate.ImageTransparency >= 0.95 then
			return
		end

		local absoluteSize = candidate.AbsoluteSize
		local width = math.max(absoluteSize.X, candidate.Size.X.Offset, 1)
		local height = math.max(absoluteSize.Y, candidate.Size.Y.Offset, 1)
		local score = width * height
		local nameLower = string.lower(candidate.Name)
		local candidateY = candidate.AbsolutePosition.Y ~= 0 and candidate.AbsolutePosition.Y or candidate.Position.Y.Offset
		local yDistance = math.abs(candidateY - hostY)

		if nameLower == statNameLower then
			score += 10000
		end
		if string.find(nameLower, statNameLower, 1, true) then
			score += 7000
		end
		if statNameLower == "money" and (string.find(nameLower, "cash", 1, true) or string.find(nameLower, "dollar", 1, true)) then
			score += 3500
		end
		if statNameLower == "speed" and string.find(nameLower, "shoe", 1, true) then
			score += 3500
		end
		if statNameLower == "comet" and string.find(nameLower, "cloud", 1, true) then
			score += 3500
		end

		score -= yDistance * 12

		if width > hostWidth * 0.9 or height > hostHeight * 1.4 then
			score -= 5000
		end

		if score > bestScore then
			bestScore = score
			bestCandidate = candidate
		end
	end

	if counters then
		for _, descendant in ipairs(counters:GetDescendants()) do
			if not isReactNode(descendant) then
				considerExternal(descendant)
			end
		end
	end

	return bestCandidate
end

local function collectIconCandidates(counters, hosts)
	local candidates = {}

	for _, descendant in ipairs(counters:GetDescendants()) do
		if (descendant:IsA("ImageLabel") or descendant:IsA("ImageButton"))
			and not isReactNode(descendant)
			and tostring(descendant.Image or "") ~= ""
			and descendant.ImageTransparency < 0.95
		then
			local parent = descendant.Parent
			if not (parent and parent.Name == "Not") then
				local belongsToHost = false
				for _, host in ipairs(hosts) do
					if descendant:IsDescendantOf(host) then
						belongsToHost = true
						break
					end
				end

				local absoluteSize = descendant.AbsoluteSize
				local width = math.max(absoluteSize.X, descendant.Size.X.Offset, 1)
				local height = math.max(absoluteSize.Y, descendant.Size.Y.Offset, 1)
				local score = width * height

				if belongsToHost then
					score += 6000
				end
				if descendant.ImageRectSize.X > 0 and descendant.ImageRectSize.Y > 0 then
					score += 1200
				end
				if descendant.Position.X.Offset <= 0 then
					score += 500
				end

				candidates[#candidates + 1] = {
					instance = descendant,
					score = score,
					y = descendant.AbsolutePosition.Y ~= 0 and descendant.AbsolutePosition.Y or descendant.Position.Y.Offset,
					name = string.lower(descendant.Name),
				}
			end
		end
	end

	table.sort(candidates, function(a, b)
		if a.y == b.y then
			return a.score > b.score
		end
		return a.y < b.y
	end)

	return candidates
end

local function assignIcons(counters, hosts)
	local byName = {}
	local usedInstances = {}
	local candidates = collectIconCandidates(counters, hosts)

	local function takeCandidateForStat(statName)
		local statLower = string.lower(statName)
		for _, candidate in ipairs(candidates) do
			if not usedInstances[candidate.instance] then
				if candidate.name == statLower or string.find(candidate.name, statLower, 1, true) then
					usedInstances[candidate.instance] = true
					return candidate.instance
				end
			end
		end

		return nil
	end

	for _, host in ipairs(hosts) do
		byName[host.Name] = takeCandidateForStat(host.Name)
	end

	for _, host in ipairs(hosts) do
		if not byName[host.Name] then
			for _, candidate in ipairs(candidates) do
				if not usedInstances[candidate.instance] then
					usedInstances[candidate.instance] = true
					byName[host.Name] = candidate.instance
					break
				end
			end
		end
	end

	local orderedIcons = {}
	for _, host in ipairs(hosts) do
		orderedIcons[#orderedIcons + 1] = byName[host.Name]
	end

	return byName, orderedIcons
end

local function suppressLegacyHost(host)
	setHiddenGuiObject(host)

	for _, descendant in ipairs(host:GetDescendants()) do
		if descendant:IsA("GuiObject") and not isProtectedDescendant(host, descendant) then
			setHiddenGuiObject(descendant)
		end
	end
end

local function hideLegacyCounterArt(counters)
	if not counters then
		return
	end

	counters.BackgroundTransparency = 1
	counters.BorderSizePixel = 0
	counters.ClipsDescendants = false

	for _, descendant in ipairs(counters:GetDescendants()) do
		if descendant:IsA("GuiObject") and not isReactNode(descendant) then
			setHiddenGuiObject(descendant)
		end
	end
end

local function buildItems(counters)
	local items = {}
	local hosts = {}

	for _, stat in ipairs(STAT_ORDER) do
		local host = counters:FindFirstChild(stat.name)
		if host and (host:IsA("TextLabel") or host:IsA("TextButton") or host:IsA("TextBox")) then
			hosts[#hosts + 1] = host
		end
	end

	local iconByName, orderedIcons = assignIcons(counters, hosts)

	local function getIconOverrideSource(statName)
		local image = STAT_ICON_ASSET_OVERRIDES[statName]
		if not image then
			return nil
		end

		local existing = iconOverrideSources[statName]
		if existing and existing:IsA("ImageLabel") then
			existing.Image = image
			return existing
		end

		local source = Instance.new("ImageLabel")
		source.Name = "ReactHudCounterIconOverride_" .. tostring(statName)
		source.BackgroundTransparency = 1
		source.BorderSizePixel = 0
		source.Size = UDim2.fromOffset(38, 38)
		source.Image = image
		source.ImageTransparency = 0
		source.ImageColor3 = Color3.fromRGB(255, 255, 255)
		source.ScaleType = Enum.ScaleType.Fit
		iconOverrideSources[statName] = source
		return source
	end

	for index, host in ipairs(hosts) do
		local statKind = host.Name
		for _, stat in ipairs(STAT_ORDER) do
			if stat.name == host.Name then
				statKind = stat.kind
				break
			end
		end

		local iconSource = getIconOverrideSource(host.Name)
			or iconByName[host.Name]
			or orderedIcons[index]
			or findCounterIcon(counters, host, host.Name)

		suppressLegacyHost(host)
		if iconSource and iconSource:IsA("GuiObject") then
			setHiddenGuiObject(iconSource)
		end

		items[#items + 1] = {
			key = host.Name,
			host = host,
			iconSource = iconSource,
			kind = statKind,
			name = host.Name,
			sourceLabel = host.Name,
		}
	end

	hideLegacyCounterArt(counters)

	return items
end

local function render()
	if destroyed then
		return
	end

	local hud = playerGui:FindFirstChild("HUD")
	local counters = hud and hud:FindFirstChild("Counters")

	if not counters then
		root:render(nil)
		return
	end

	local items = buildItems(counters)
	local displayLayer = ensureDisplayLayer(hud)
	layoutDisplayLayer(displayLayer, #items)
	local notificationSurface = displayLayer:FindFirstChild("ReactHudCounterNotifications")

	root:render(e(React.Fragment, nil, {
		Rows = e(HudStatRow, {
			surface = displayLayer,
			items = items,
			rowHeight = TARGET_ROW_HEIGHT,
			rowSpacing = TARGET_ROW_SPACING,
			iconSlotWidth = ICON_SLOT_WIDTH,
			barGap = BAR_GAP,
			labelSlotWidth = HudCounterConfig.LabelSlotWidth,
		}),
		Notifications = notificationSurface and e(HudStatNotificationLayer, {
			surface = notificationSurface,
		}) or nil,
	}))
end

local function scheduleRender()
	if destroyed or renderQueued then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		render()
	end)
end

local relevantNames = {
	HUD = true,
	Counters = true,
	Comet = true,
	Speed = true,
	Money = true,
	Not = true,
}

local descendantAddedConnection = playerGui.DescendantAdded:Connect(function(descendant)
	if relevantNames[descendant.Name] then
		scheduleRender()
	end
end)

local descendantRemovingConnection = playerGui.DescendantRemoving:Connect(function(descendant)
	if relevantNames[descendant.Name] then
		scheduleRender()
	end
end)

render()

script.Destroying:Connect(function()
	destroyed = true
	descendantAddedConnection:Disconnect()
	descendantRemovingConnection:Disconnect()
	root:unmount()
end)

