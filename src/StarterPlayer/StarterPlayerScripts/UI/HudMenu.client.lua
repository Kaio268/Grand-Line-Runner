local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local HudMenuGroup = require(UiFolder:WaitForChild("Hud"):WaitForChild("HudMenuGroup"))

local e = React.createElement

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactHudMenuRoot"

local root = ReactRoblox.createRoot(rootContainer)

local TILE_DEFS = {
	{ name = "Store", label = "Store" },
	{ name = "Index", label = "Index", badgeText = "0" },
	{ name = "Gifts", label = "Gifts", badgeText = "0", timerText = "--" },
	{ name = "Settings", label = "Settings" },
	{ name = "Rebirth", label = "Rebirth", badgeText = "NEW" },
}

local PROTECTED_CHILDREN = {
	Not = true,
	Timer = true,
	ReactHudMenuTileRoot = true,
}

local destroyed = false
local renderQueued = false

local function isTextGuiObject(instance)
	return instance
		and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function isReactNode(instance)
	return typeof(instance) == "Instance" and string.sub(instance.Name, 1, 8) == "ReactHud"
end

local function estimateArea(guiObject)
	if not guiObject or not guiObject:IsA("GuiObject") then
		return 0
	end

	local absoluteSize = guiObject.AbsoluteSize
	local area = absoluteSize.X * absoluteSize.Y
	if area > 0 then
		return area
	end

	local size = guiObject.Size
	return (math.abs(size.X.Scale) * 1000 + math.abs(size.X.Offset))
		* (math.abs(size.Y.Scale) * 1000 + math.abs(size.Y.Offset))
end

local function isProtectedDescendant(button, descendant)
	local current = descendant
	while current and current ~= button do
		if PROTECTED_CHILDREN[current.Name] or isReactNode(current) then
			return true
		end
		current = current.Parent
	end

	return false
end

local function extractImageStyle(source, host)
	if not source or not source:IsA("GuiObject") then
		return nil
	end

	local isHost = source == host
	local imageSource = (source:IsA("ImageLabel") or source:IsA("ImageButton")) and source or nil
	if not imageSource or tostring(imageSource.Image or "") == "" then
		return nil
	end

	local style = {
		anchorPoint = isHost and Vector2.new(0, 0) or source.AnchorPoint,
		backgroundColor3 = source.BackgroundColor3,
		backgroundTransparency = isHost and 1 or source.BackgroundTransparency,
		image = imageSource.Image,
		imageColor3 = imageSource.ImageColor3,
		imageRectOffset = imageSource.ImageRectOffset,
		imageRectSize = imageSource.ImageRectSize,
		imageTransparency = imageSource.ImageTransparency,
		position = isHost and UDim2.fromScale(0, 0) or source.Position,
		rotation = source.Rotation,
		scaleType = imageSource.ScaleType,
		size = isHost and UDim2.fromScale(1, 1) or source.Size,
		sliceCenter = imageSource.ScaleType == Enum.ScaleType.Slice and imageSource.SliceCenter or nil,
		sliceScale = imageSource.ScaleType == Enum.ScaleType.Slice and imageSource.SliceScale or nil,
		zIndex = math.max(source.ZIndex, 4),
	}

	return style
end

local function clampNumber(value, minimum, maximum)
	local numeric = tonumber(value)
	if not numeric then
		return minimum
	end

	return math.clamp(numeric, minimum, maximum)
end

local function pickBackground(button)
	local bestCandidate = nil
	local bestArea = -1

	local function consider(candidate)
		local style = extractImageStyle(candidate, button)
		if not style then
			return
		end

		local area = estimateArea(candidate)
		if area > bestArea then
			bestArea = area
			bestCandidate = candidate
		end
	end

	consider(button)
	for _, descendant in ipairs(button:GetDescendants()) do
		if not isProtectedDescendant(button, descendant) then
			consider(descendant)
		end
	end

	return extractImageStyle(bestCandidate, button), bestCandidate
end

local function pickIcon(button, backgroundCandidate)
	local bestCandidate = nil
	local bestScore = -math.huge
	local buttonArea = math.max(estimateArea(button), 1)

	local function consider(candidate)
		local style = extractImageStyle(candidate, button)
		if not style then
			return
		end

		local area = estimateArea(candidate)
		if candidate == backgroundCandidate or area <= 0 then
			return
		end

		local score = area
		local nameLower = string.lower(candidate.Name)
		if string.find(nameLower, "icon", 1, true) then
			score += buttonArea
		elseif string.find(nameLower, "image", 1, true) then
			score += buttonArea * 0.25
		end

		if area >= buttonArea * 0.82 then
			score -= buttonArea
		end

		if score > bestScore then
			bestScore = score
			bestCandidate = candidate
		end
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if not isProtectedDescendant(button, descendant) then
			consider(descendant)
		end
	end

	return extractImageStyle(bestCandidate, button)
end

local function pickTitleStyle(button)
	local bestCandidate = nil
	local bestScore = -math.huge

	local function consider(candidate)
		if not candidate:IsA("TextLabel") and not candidate:IsA("TextButton") and not candidate:IsA("TextBox") then
			return
		end

		if isProtectedDescendant(button, candidate) then
			return
		end

		local text = tostring(candidate.Text or "")
		if text == "" then
			return
		end

		local score = estimateArea(candidate) + candidate.AbsolutePosition.Y + candidate.Position.Y.Offset
		if string.find(string.lower(text), string.lower(button.Name), 1, true) then
			score += 100000
		end

		if score > bestScore then
			bestScore = score
			bestCandidate = candidate
		end
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		consider(descendant)
	end

	if not bestCandidate then
		return nil
	end

	return {
		anchorPoint = bestCandidate.AnchorPoint,
		backgroundTransparency = 1,
		font = bestCandidate.Font,
		fontFace = bestCandidate.FontFace,
		position = bestCandidate.Position,
		rotation = bestCandidate.Rotation,
		size = bestCandidate.Size,
		textColor3 = bestCandidate.TextColor3,
		textSize = bestCandidate.TextSize,
		textStrokeColor3 = bestCandidate.TextStrokeColor3,
		textStrokeTransparency = bestCandidate.TextStrokeTransparency,
		textTransparency = bestCandidate.TextTransparency,
		textWrapped = bestCandidate.TextWrapped,
		textXAlignment = bestCandidate.TextXAlignment,
		textYAlignment = bestCandidate.TextYAlignment,
		zIndex = math.max(bestCandidate.ZIndex, 8),
	}
end

local function findAccentStyle(button, backgroundCandidate, iconStyle)
	local bestCandidate = nil
	local bestScore = -math.huge
	local buttonArea = math.max(estimateArea(button), 1)
	local iconImage = iconStyle and iconStyle.image or nil

	local function consider(candidate)
		local style = extractImageStyle(candidate, button)
		if not style then
			return
		end

		local area = estimateArea(candidate)
		if candidate == backgroundCandidate or style.image == iconImage or area <= 0 then
			return
		end

		local score = area
		if area >= buttonArea * 0.82 then
			score -= buttonArea
		end

		if score > bestScore then
			bestScore = score
			bestCandidate = candidate
		end
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if not isProtectedDescendant(button, descendant) then
			consider(descendant)
		end
	end

	return extractImageStyle(bestCandidate, button)
end

local function ensureContainer(hud)
	local lButtons = hud:FindFirstChild("LButtons")
	if lButtons and lButtons:IsA("GuiObject") then
		lButtons.ClipsDescendants = false
		return lButtons
	end

	local created = Instance.new("Frame")
	created.Name = "LButtons"
	created.BackgroundTransparency = 1
	created.BorderSizePixel = 0
	created.ClipsDescendants = false
	created.Position = UDim2.fromOffset(18, 116)
	created.Size = UDim2.fromOffset(96, 480)
	created.Parent = hud

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = created

	return created
end

local function ensureShell(container, definition, index)
	local existing = container:FindFirstChild(definition.name)
	if existing and existing:IsA("GuiButton") then
		existing.ClipsDescendants = false
		return existing
	end

	local button = Instance.new("ImageButton")
	button.Name = definition.name
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.ClipsDescendants = false
	button.ImageTransparency = 1
	button.LayoutOrder = index
	button.Size = UDim2.fromOffset(84, 84)

	local hasLayout = container:FindFirstChildOfClass("UIListLayout") ~= nil
	if not hasLayout then
		button.Position = UDim2.fromOffset(0, (index - 1) * 94)
	end

	button.Parent = container
	return button
end

local function readBadgeDisplayText(badge, defaultText)
	local fallback = tostring(defaultText or "")
	if fallback ~= "" then
		return fallback
	end

	if isTextGuiObject(badge) then
		local badgeText = tostring(badge.Text or "")
		if badgeText ~= "" then
			return badgeText
		end
	end

	local existingText = badge and badge:FindFirstChild("TextLB", true)
	if isTextGuiObject(existingText) then
		local text = tostring(existingText.Text or "")
		if text ~= "" then
			return text
		end
	end

	return fallback
end

local function ensureBadge(button, defaultText)
	local badge = button:FindFirstChild("Not")
	if not badge or not badge:IsA("GuiObject") then
		badge = Instance.new("Frame")
		badge.Name = "Not"
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.BackgroundColor3 = Color3.fromRGB(245, 82, 82)
		badge.BorderSizePixel = 0
		badge.Position = UDim2.new(1, -4, 0, 4)
		badge.Size = UDim2.fromOffset(34, 22)
		badge.Visible = false
		badge.ZIndex = math.max(button.ZIndex + 10, 12)
		badge.Parent = button

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 11)
		corner.Parent = badge

		local stroke = Instance.new("UIStroke")
		stroke.Name = "ReactHudBadgeStroke"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Color3.fromRGB(255, 236, 211)
		stroke.Transparency = 0.35
		stroke.Thickness = 1
		stroke.Parent = badge

		local gradient = Instance.new("UIGradient")
		gradient.Name = "ReactHudBadgeGradient"
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 119, 114)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(223, 58, 89)),
		})
		gradient.Rotation = 90
		gradient.Parent = badge
	end

	button.ClipsDescendants = false

	local badgeTextValue = readBadgeDisplayText(badge, defaultText)

	if badge:IsA("GuiObject") then
		badge.ClipsDescendants = false
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.BackgroundColor3 = Color3.fromRGB(232, 72, 102)
		badge.Position = UDim2.new(1, 8, 0, -6)
		badge.ZIndex = math.max(badge.ZIndex, button.ZIndex + 28, 32)
		if badgeTextValue == "NEW" then
			badge.Size = UDim2.fromOffset(42, 22)
		else
			badge.Size = UDim2.fromOffset(34, 22)
		end
	end

	local textLabel = badge:FindFirstChild("TextLB")
	if not textLabel then
		textLabel = Instance.new("TextLabel")
		textLabel.Name = "TextLB"
		textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		textLabel.BackgroundTransparency = 1
		textLabel.BorderSizePixel = 0
		textLabel.Font = Enum.Font.GothamBlack
		textLabel.Position = UDim2.fromScale(0.5, 0.5)
		textLabel.Size = UDim2.new(1, -4, 1, -4)
		textLabel.Text = badgeTextValue
		textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		textLabel.TextScaled = true
		textLabel.TextStrokeColor3 = Color3.fromRGB(82, 12, 29)
		textLabel.TextStrokeTransparency = 0.08
		textLabel.ZIndex = math.max(badge.ZIndex + 1, 33)
		textLabel.Parent = badge
	end

	if isTextGuiObject(textLabel) then
		if badgeTextValue ~= "" then
			textLabel.Text = badgeTextValue
		end
		textLabel.TextStrokeColor3 = Color3.fromRGB(82, 12, 29)
		textLabel.TextStrokeTransparency = 0.08
		textLabel.ZIndex = math.max(textLabel.ZIndex, badge.ZIndex + 1, 33)
	end

	for _, descendant in ipairs(badge:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = math.max(descendant.ZIndex, badge.ZIndex + 1, 33)
		elseif descendant:IsA("UIStroke") then
			descendant.Enabled = true
		elseif descendant:IsA("UIGradient") then
			descendant.Enabled = true
		end
	end

	return badge
end

local function ensureTimer(button, defaultText)
	local timer = button:FindFirstChild("Timer")
	if not timer then
		timer = Instance.new("TextLabel")
		timer.Name = "Timer"
		timer.AnchorPoint = Vector2.new(0.5, 0)
		timer.BackgroundColor3 = Color3.fromRGB(7, 14, 24)
		timer.BackgroundTransparency = 0.08
		timer.BorderSizePixel = 0
		timer.Font = Enum.Font.GothamBold
		timer.Position = UDim2.new(0.5, 0, 0, 6)
		timer.Size = UDim2.new(1, -10, 0, 20)
		timer.Text = tostring(defaultText or "--")
		timer.TextColor3 = Color3.fromRGB(255, 245, 224)
		timer.TextScaled = true
		timer.TextStrokeColor3 = Color3.fromRGB(5, 8, 15)
		timer.TextStrokeTransparency = 0.08
		timer.ZIndex = math.max(button.ZIndex + 9, 11)
		timer.Parent = button

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 9)
		corner.Parent = timer

		local stroke = Instance.new("UIStroke")
		stroke.Name = "ReactHudTimerStroke"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = Color3.fromRGB(255, 237, 203)
		stroke.Transparency = 0.6
		stroke.Thickness = 1
		stroke.Parent = timer

		local gradient = Instance.new("UIGradient")
		gradient.Name = "ReactHudTimerGradient"
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(29, 39, 57)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 13, 22)),
		})
		gradient.Rotation = 90
		gradient.Parent = timer
	end

	if isTextGuiObject(timer) then
		timer.BackgroundTransparency = 0.08
		timer.TextStrokeColor3 = Color3.fromRGB(5, 8, 15)
		timer.TextStrokeTransparency = 0.08
		timer.ZIndex = math.max(timer.ZIndex, button.ZIndex + 9, 11)
	end

	local timer2 = timer:FindFirstChild("Timer2")
	if not timer2 then
		timer2 = Instance.new("TextLabel")
		timer2.Name = "Timer2"
		timer2.AnchorPoint = Vector2.new(0.5, 0.5)
		timer2.BackgroundTransparency = 1
		timer2.BorderSizePixel = 0
		timer2.Font = Enum.Font.GothamBold
		timer2.Position = UDim2.fromScale(0.5, 0.5)
		timer2.Size = UDim2.new(1, 0, 1, 0)
		timer2.Text = tostring(defaultText or "--")
		timer2.TextColor3 = timer.TextColor3
		timer2.TextScaled = true
		timer2.TextStrokeColor3 = timer.TextStrokeColor3
		timer2.TextStrokeTransparency = timer.TextStrokeTransparency
		timer2.ZIndex = math.max(timer.ZIndex + 1, 12)
		timer2.Parent = timer
	end

	if isTextGuiObject(timer2) then
		timer2.TextStrokeColor3 = timer.TextStrokeColor3
		timer2.TextStrokeTransparency = timer.TextStrokeTransparency
		timer2.ZIndex = math.max(timer2.ZIndex, timer.ZIndex + 1, 12)
	end

	return timer
end

local function ensureCompatibility(button, definition)
	if definition.badgeText or button:FindFirstChild("Not") then
		ensureBadge(button, definition.badgeText)
	end

	if definition.timerText then
		ensureTimer(button, definition.timerText)
	end
end

local function hideLegacyVisuals(button)
	button.BackgroundTransparency = 1

	if button:IsA("ImageButton") then
		button.ImageTransparency = 1
	end

	if button:IsA("TextButton") then
		button.TextTransparency = 1
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if not isProtectedDescendant(button, descendant) and not isReactNode(descendant) then
			if descendant:IsA("GuiObject") then
				descendant.Visible = false
			elseif descendant:IsA("UIStroke") or descendant:IsA("UIGradient") then
				descendant.Enabled = false
			end
		end
	end
end

local function normalizeTitleStyle(titleStyle)
	local style = titleStyle or {}

	return {
		anchorPoint = Vector2.new(0.5, 1),
		backgroundTransparency = 1,
		font = style.font or Enum.Font.GothamBold,
		fontFace = style.fontFace,
		position = UDim2.new(0.5, 0, 1, -6),
		rotation = 0,
		size = UDim2.new(1, -12, 0, clampNumber(style.textSize, 15, 18) + 6),
		textColor3 = Color3.fromRGB(255, 250, 240),
		textSize = clampNumber(style.textSize, 15, 18),
		textStrokeColor3 = Color3.fromRGB(6, 10, 18),
		textStrokeTransparency = 0.02,
		textTransparency = 0,
		textWrapped = false,
		textXAlignment = Enum.TextXAlignment.Center,
		textYAlignment = Enum.TextYAlignment.Center,
		zIndex = math.max(clampNumber(style.zIndex, 12, 20), 12),
	}
end

local function buildTitleBandStyle()
	return {
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -4),
		size = UDim2.new(1, -8, 0, 28),
		zIndex = 10,
	}
end

local function buildTileStyle(button)
	local backgroundStyle, backgroundCandidate = pickBackground(button)
	local iconStyle = pickIcon(button, backgroundCandidate)

	return {
		background = backgroundStyle,
		icon = iconStyle,
		accent = findAccentStyle(button, backgroundCandidate, iconStyle),
		title = normalizeTitleStyle(pickTitleStyle(button)),
		titleBand = buildTitleBandStyle(),
	}
end

local function refreshOpenUiBindings()
	local openUiScript = playerGui:FindFirstChild("OpenUI")
	if not openUiScript then
		return
	end

	local moduleScript = openUiScript:FindFirstChild("Open_UI")
	if not moduleScript then
		return
	end

	local ok, controller = pcall(require, moduleScript)
	if ok and controller and controller.RefreshButtons then
		controller:RefreshButtons()
	end
end

local function buildTiles()
	local hud = playerGui:FindFirstChild("HUD") or playerGui:WaitForChild("HUD")
	local container = ensureContainer(hud)
	local tiles = {}

	for index, definition in ipairs(TILE_DEFS) do
		local button = ensureShell(container, definition, index)
		ensureCompatibility(button, definition)
		local style = buildTileStyle(button)
		hideLegacyVisuals(button)

		tiles[index] = {
			name = definition.name,
			label = definition.label,
			host = button,
			style = style,
		}
	end

	refreshOpenUiBindings()

	return tiles
end

local function render()
	local tiles = buildTiles()
	root:render(e(HudMenuGroup, {
		tiles = tiles,
	}))
end

local function scheduleRender()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			render()
		end
	end)
end

playerGui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "HUD" or descendant.Name == "LButtons" then
		task.defer(scheduleRender)
		return
	end

	for _, definition in ipairs(TILE_DEFS) do
		if descendant.Name == definition.name then
			task.defer(scheduleRender)
			return
		end
	end
end)

playerGui.DescendantRemoving:Connect(function(descendant)
	if descendant.Name == "HUD" or descendant.Name == "LButtons" then
		task.defer(scheduleRender)
		return
	end

	for _, definition in ipairs(TILE_DEFS) do
		if descendant.Name == definition.name then
			task.defer(scheduleRender)
			return
		end
	end
end)

scheduleRender()

script.Destroying:Connect(function()
	destroyed = true
	root:unmount()
end)
