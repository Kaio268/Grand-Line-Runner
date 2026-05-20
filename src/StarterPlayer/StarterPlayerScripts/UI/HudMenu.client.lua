local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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
rootContainer.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)
local HUD_DEBUG = false

local function hudLog(tag, ...)
	if HUD_DEBUG then
		print(tag, ...)
	end
end

local function hudError(...)
	warn("[HUD][ERROR]", ...)
end

local function safeName(instance)
	if not instance then
		return "nil"
	end

	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)
	return ok and fullName or tostring(instance)
end

local TILE_DEFS = {
	{ name = "Store", label = "Store" },
	{ name = "Index", label = "Index", badgeText = "0" },
	{ name = "Gifts", label = "Gifts", badgeText = "0", hasSummaryTimer = true },
	{ name = "Settings", label = "Settings" },
	{ name = "Rebirth", label = "Rebirth", badgeText = "NEW" },
	{ name = "Quest", label = "Quest", badgeText = "" },
}

local function getHudLayout()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local mobile = UserInputService.TouchEnabled or viewport.Y < 1000
	local compact = mobile or viewport.X < 700 or viewport.Y < 500
	local tileSize = if mobile then 56 elseif compact then 72 else 98
	local columnGap = if mobile then 4 elseif compact then 6 else 10
	local rowGap = if mobile then 4 elseif compact then 6 else 10
	local stepX = tileSize + columnGap
	local stepY = tileSize + rowGap

	return {
		tileSize = tileSize,
		columnGap = columnGap,
		rowGap = rowGap,
		stepX = stepX,
		stepY = stepY,
		mobile = mobile,
		containerPosition = if mobile then UDim2.fromOffset(118, 138) elseif compact then UDim2.fromOffset(8, 160) else UDim2.fromOffset(10, 250),
		positions = {
			Store = Vector2.new(0, 0),
			Index = Vector2.new(stepX, 0),
			Gifts = Vector2.new(0, stepY),
			Quest = Vector2.new(stepX, stepY),
			Rebirth = Vector2.new(0, stepY * 2),
			Settings = Vector2.new(stepX, stepY * 2),
		},
	}
end

local HUD_ICON_ASSET_OVERRIDES = {
	Store = "rbxassetid://87636652264235",
	Index = "rbxassetid://77322372470208",
	Gifts = "rbxassetid://131189007512696",
	Claim = "rbxassetid://131189007512696",
	Settings = "rbxassetid://125384263224347",
	Rebirth = "rbxassetid://116163404622119",
	Quest = "rbxassetid://78184151901761",
}

local HUD_ICON_SIZE_OVERRIDES = {
	Store = Vector2.new(98, 98),
	Index = Vector2.new(85, 85),
	Gifts = Vector2.new(85, 85),
	Settings = Vector2.new(88, 88),
	Rebirth = Vector2.new(82, 82),
	Quest = Vector2.new(94, 94),
}

local HUD_ICON_SCALE_TYPE_OVERRIDES = {
	Quest = Enum.ScaleType.Fit,
}

local PROTECTED_CHILDREN = {
	Not = true,
	GiftSummaryTimer = true,
	ReactHudMenuTileRoot = true,
}

local HOVER_IDLE_SCALE = 1
local HOVER_ACTIVE_SCALE = 0.95
local HOVER_TWEEN = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HUD_BUTTON_NO_ANIM_TAG = "NoAnim"

local destroyed = false
local renderQueued = false
local hoverBindings = {}

local function isTextGuiObject(instance)
	return instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
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

local function ensureContainer(hud)
	local layout = getHudLayout()
	local lButtons = hud:FindFirstChild("LButtons")
	local containerWidth = (layout.tileSize * 2) + layout.columnGap
	local containerHeight = (layout.tileSize * 3) + (layout.rowGap * 2)
	if lButtons and lButtons:IsA("GuiObject") then
		lButtons.Visible = true
		lButtons.ClipsDescendants = false
		lButtons.Size = UDim2.fromOffset(containerWidth, containerHeight)
		lButtons.Position = layout.containerPosition
		return lButtons
	end

	local created = Instance.new("Frame")
	created.Name = "LButtons"
	created.BackgroundTransparency = 1
	created.BorderSizePixel = 0
	created.ClipsDescendants = false
	created.Visible = true
	created.Position = layout.containerPosition
	created.Size = UDim2.fromOffset(containerWidth, containerHeight)
	created.Parent = hud

	return created
end

local function clearHoverBinding(button)
	local binding = hoverBindings[button]
	if not binding then
		return
	end

	for _, connection in ipairs(binding.connections) do
		connection:Disconnect()
	end

	hoverBindings[button] = nil
end

local function ensureHoverScale(button)
	if not button or not button:IsA("GuiButton") then
		return
	end

	if hoverBindings[button] then
		return
	end

	local scale = button:FindFirstChild("ReactHudHoverScale")
	if not scale or not scale:IsA("UIScale") then
		scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Name = "ReactHudHoverScale"
		scale.Parent = button
	end
	scale.Scale = HOVER_IDLE_SCALE

	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("UIScale") and child ~= scale then
			child.Scale = HOVER_IDLE_SCALE
		end
	end

	local activeTween = nil
	local function tweenTo(targetScale)
		if activeTween then
			activeTween:Cancel()
		end

		activeTween = TweenService:Create(scale, HOVER_TWEEN, {
			Scale = targetScale,
		})
		activeTween:Play()
	end

	local function resetToIdle()
		tweenTo(HOVER_IDLE_SCALE)
	end

	hoverBindings[button] = {
		connections = {
			button.MouseEnter:Connect(function()
				tweenTo(HOVER_ACTIVE_SCALE)
			end),
			button.MouseLeave:Connect(function()
				resetToIdle()
			end),
			button.MouseButton1Up:Connect(function()
				resetToIdle()
			end),
			button.Activated:Connect(function()
				resetToIdle()
				task.defer(resetToIdle)
			end),
			button.Destroying:Connect(function()
				clearHoverBinding(button)
			end),
		},
	}
end

local function ensureShell(container, definition, index)
	local layout = getHudLayout()
	local mappedPosition = layout.positions[definition.name]
	local existing = container:FindFirstChild(definition.name)
	if existing and existing:IsA("GuiButton") then
		existing.Visible = true
		existing.Active = true
		existing.ClipsDescendants = true
		existing.Size = UDim2.fromOffset(layout.tileSize, layout.tileSize)
		existing.LayoutOrder = index
		CollectionService:AddTag(existing, HUD_BUTTON_NO_ANIM_TAG)
		if mappedPosition then
			existing.Position = UDim2.fromOffset(mappedPosition.X, mappedPosition.Y)
		end
		return existing
	end

	local button = Instance.new("ImageButton")
	button.Name = definition.name
	button.AutoButtonColor = false
	button.Active = true
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.ClipsDescendants = true
	button.ImageTransparency = 1
	button.Visible = true
	button.LayoutOrder = index
	button.Size = UDim2.fromOffset(layout.tileSize, layout.tileSize)
	CollectionService:AddTag(button, HUD_BUTTON_NO_ANIM_TAG)
	if mappedPosition then
		button.Position = UDim2.fromOffset(mappedPosition.X, mappedPosition.Y)
	else
		button.Position = UDim2.fromOffset(0, (index - 1) * layout.stepY)
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

	local layout = getHudLayout()
	button.ClipsDescendants = false

	local badgeTextValue = readBadgeDisplayText(badge, defaultText)

	if badge:IsA("GuiObject") then
		badge.ClipsDescendants = false
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.BackgroundColor3 = Color3.fromRGB(232, 72, 102)
		badge.Position = layout.mobile and UDim2.new(1, 3, 0, -3) or UDim2.new(1, 8, 0, -6)
		badge.ZIndex = math.max(badge.ZIndex, button.ZIndex + 28, 32)
		if badgeTextValue == "NEW" then
			badge.Size = layout.mobile and UDim2.fromOffset(28, 14) or UDim2.fromOffset(42, 22)
		else
			badge.Size = layout.mobile and UDim2.fromOffset(24, 14) or UDim2.fromOffset(34, 22)
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
		textLabel.TextSize = layout.mobile and 9 or textLabel.TextSize
		textLabel.ZIndex = math.max(textLabel.ZIndex, badge.ZIndex + 1, 33)
	end

	for _, descendant in ipairs(badge:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = math.max(descendant.ZIndex, badge.ZIndex + 1, 33)
		elseif descendant:IsA("UIStroke") or descendant:IsA("UIGradient") then
			descendant.Enabled = true
		end
	end

	return badge
end

local function removeSidebarTimers(button, context, keepGiftSummary)
	local timers = {}
	for _, descendant in ipairs(button:GetDescendants()) do
		if
			descendant:IsA("GuiObject")
			and (
				descendant.Name == "Timer"
				or descendant.Name == "Timer2"
				or (descendant.Name == "GiftSummaryTimer" and keepGiftSummary ~= true)
			)
		then
			table.insert(timers, descendant)
		end
	end

	if #timers == 0 then
		hudLog("[HUD][TIMER]", string.format("context=%s button=%s timers=0", context, safeName(button)))
		return
	end

	for _, timer in ipairs(timers) do
		local timerPath = safeName(timer)
		timer:Destroy()
		hudLog("[HUD][TIMER]", string.format("context=%s button=%s removed=%s", context, safeName(button), timerPath))
	end
end

local function ensureGiftSummaryTimer(button)
	for _, sibling in ipairs(button.Parent:GetChildren()) do
		if sibling:IsA("GuiObject") then
			local wrongTimer = sibling:FindFirstChild("Timer")
			if wrongTimer and wrongTimer:IsA("GuiObject") then
				wrongTimer:Destroy()
			end
			local wrongTimer2 = sibling:FindFirstChild("Timer2")
			if wrongTimer2 and wrongTimer2:IsA("GuiObject") then
				wrongTimer2:Destroy()
			end
			if sibling ~= button then
				local wrongSummary = sibling:FindFirstChild("GiftSummaryTimer")
				if wrongSummary and wrongSummary:IsA("GuiObject") then
					wrongSummary:Destroy()
				end
			end
		end
	end

	local summary = button:FindFirstChild("GiftSummaryTimer")
	if summary and not summary:IsA("TextLabel") then
		summary:Destroy()
		summary = nil
	end

	if not summary then
		summary = Instance.new("TextLabel")
		summary.Name = "GiftSummaryTimer"
		summary.Parent = button
	end

	summary.Visible = true
	local layout = getHudLayout()
	summary.AnchorPoint = Vector2.new(0.5, 0)
	summary.BackgroundColor3 = Color3.fromRGB(7, 14, 24)
	summary.BackgroundTransparency = 0.16
	summary.BorderSizePixel = 0
	summary.Font = Enum.Font.GothamBold
	summary.Position = UDim2.new(0.5, 0, 0, layout.mobile and 2 or 4)
	summary.Size = layout.mobile and UDim2.fromOffset(42, 12) or UDim2.fromOffset(60, 18)
	summary.Text = tostring(summary.Text ~= "" and summary.Text or "--")
	summary.TextColor3 = Color3.fromRGB(255, 255, 255)
	summary.TextScaled = false
	summary.TextSize = layout.mobile and 8 or 13
	summary.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	summary.TextStrokeTransparency = 0
	summary.TextXAlignment = Enum.TextXAlignment.Center
	summary.TextYAlignment = Enum.TextYAlignment.Center
	summary.ZIndex = math.max(button.ZIndex + 300, 300)

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
	stroke.Name = "ReactHudGiftSummaryTimerStroke"
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
	gradient.Name = "ReactHudGiftSummaryTimerGradient"
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(29, 39, 57)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 13, 22)),
	})
	gradient.Rotation = 90
	gradient.Enabled = false

	hudLog("[HUD][TIMER]", string.format("button=%s summaryTimer=%s", safeName(button), safeName(summary)))

	return summary
end

local function ensureCompatibility(button, definition)
	if definition.badgeText or button:FindFirstChild("Not") then
		ensureBadge(button, definition.badgeText)
	end

	removeSidebarTimers(button, definition.name, definition.hasSummaryTimer == true)
	if definition.hasSummaryTimer == true then
		ensureGiftSummaryTimer(button)
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

local function logVisualTree(button)
	if HUD_DEBUG ~= true then
		return
	end

	local visualRoot = button:FindFirstChild("ReactHudMenuTileRoot")
	if not visualRoot or not visualRoot:IsA("GuiObject") then
		hudError("Missing React sidebar visual root for", safeName(button))
		return
	end

	hudLog(
		"[HUD][VISUAL]",
		string.format(
			"button=%s root=%s visible=%s zIndex=%s",
			safeName(button),
			safeName(visualRoot),
			tostring(visualRoot.Visible),
			tostring(visualRoot.ZIndex)
		)
	)

	for _, descendant in ipairs(visualRoot:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			local imageTransparency = "n/a"
			if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				imageTransparency = tostring(descendant.ImageTransparency)
			end

			local textTransparency = "n/a"
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				textTransparency = tostring(descendant.TextTransparency)
			end

			hudLog(
				"[HUD][VISUAL]",
				string.format(
					"node=%s visible=%s backgroundTransparency=%s imageTransparency=%s textTransparency=%s zIndex=%s",
					safeName(descendant),
					tostring(descendant.Visible),
					tostring(descendant.BackgroundTransparency),
					imageTransparency,
					textTransparency,
					tostring(descendant.ZIndex)
				)
			)
		end
	end
end

local function normalizeTitleStyle(titleStyle)
	local style = titleStyle or {}

	return {
		anchorPoint = Vector2.new(0.5, 0),
		backgroundTransparency = 1,
		font = style.font or Enum.Font.GothamBold,
		fontFace = style.fontFace,
		position = UDim2.fromScale(0.5, 0.78),
		rotation = 0,
		size = UDim2.new(1, -8, 0, clampNumber(style.textSize, 16, 20) + 4),
		textColor3 = Color3.fromRGB(255, 250, 240),
		textSize = clampNumber(style.textSize, 16, 20),
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
	local overrideIcon = HUD_ICON_ASSET_OVERRIDES[button.Name]
	if overrideIcon then
		if iconStyle then
			iconStyle.image = overrideIcon
		else
			iconStyle = {
				anchorPoint = Vector2.new(0.5, 0.5),
				backgroundTransparency = 1,
				image = overrideIcon,
				imageColor3 = Color3.fromRGB(255, 255, 255),
				imageRectOffset = Vector2.zero,
				imageRectSize = Vector2.zero,
				imageTransparency = 0,
				position = UDim2.fromScale(0.5, 0.34),
				rotation = 0,
				scaleType = Enum.ScaleType.Fit,
				size = UDim2.fromOffset(54, 54),
				zIndex = 18,
			}
		end
	end

	if iconStyle then
		local iconSize = HUD_ICON_SIZE_OVERRIDES[button.Name] or Vector2.new(66, 66)
		local layout = getHudLayout()
		local mobileIconInset = if button.Name == "Store" or button.Name == "Quest" or button.Name == "Settings" then 2 else 6
		local maxIconSize = layout.mobile and math.max(42, layout.tileSize - mobileIconInset) or math.huge
		iconStyle.position = UDim2.fromScale(0.5, layout.mobile and 0.36 or 0.34)
		iconStyle.size = UDim2.fromOffset(math.min(iconSize.X, maxIconSize), math.min(iconSize.Y, maxIconSize))
		iconStyle.scaleType = HUD_ICON_SCALE_TYPE_OVERRIDES[button.Name] or Enum.ScaleType.Fit
		iconStyle.backgroundTransparency = 1
		iconStyle.zIndex = math.max(clampNumber(iconStyle.zIndex, 14, 24), 18)
	end

	local titleStyle = normalizeTitleStyle(pickTitleStyle(button))
	local layout = getHudLayout()
	if layout.mobile then
		titleStyle.position = UDim2.fromScale(0.5, 0.73)
		titleStyle.size = UDim2.new(1, -6, 0, 11)
		titleStyle.textSize = 9
		titleStyle.textWrapped = false
	end

	return {
		background = backgroundStyle,
		icon = iconStyle,
		accent = nil,
		title = titleStyle,
		titleBand = buildTitleBandStyle(),
		showBackground = false,
		showTitleBand = false,
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
	if hud:IsA("ScreenGui") then
		hud.Enabled = true
	end
	local container = ensureContainer(hud)
	local tiles = {}

	hudLog("[HUD][BOOT]", "hud", hud:GetFullName(), "enabled", hud.Enabled, "sidebar", container:GetFullName())

	for index, definition in ipairs(TILE_DEFS) do
		local button = ensureShell(container, definition, index)
		ensureHoverScale(button)
		ensureCompatibility(button, definition)
		local style = buildTileStyle(button)
		hideLegacyVisuals(button)
		hudLog(
			"[HUD][VISIBILITY]",
			string.format(
				"button=%s visible=%s active=%s imageTransparency=%s backgroundTransparency=%s",
				button:GetFullName(),
				tostring(button.Visible),
				tostring(button.Active),
				tostring(button:IsA("ImageButton") and button.ImageTransparency or "n/a"),
				tostring(button.BackgroundTransparency)
			)
		)

		tiles[index] = {
			name = definition.name,
			label = definition.label,
			host = button,
			style = style,
		}
	end

	refreshOpenUiBindings()
	task.defer(function()
		for _, tile in ipairs(tiles) do
			logVisualTree(tile.host)
		end
	end)

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

local hudConnections = {}

local function disconnectHudConnections()
	for _, connection in ipairs(hudConnections) do
		connection:Disconnect()
	end
	table.clear(hudConnections)
end

local function shouldRefreshForHudDescendant(descendant)
	if descendant.Name == "LButtons" then
		return true
	end
	for _, definition in ipairs(TILE_DEFS) do
		if descendant.Name == definition.name then
			return true
		end
	end
	return false
end

local function bindHudConnections()
	disconnectHudConnections()
	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return
	end

	hudConnections[#hudConnections + 1] = hud.DescendantAdded:Connect(function(descendant)
		if shouldRefreshForHudDescendant(descendant) then
			task.defer(scheduleRender)
		end
	end)
	hudConnections[#hudConnections + 1] = hud.DescendantRemoving:Connect(function(descendant)
		if shouldRefreshForHudDescendant(descendant) then
			task.defer(scheduleRender)
		end
	end)
end

local childAddedConnection = playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUD" then
		bindHudConnections()
		task.defer(scheduleRender)
	end
end)

local childRemovedConnection = playerGui.ChildRemoved:Connect(function(child)
	if child.Name == "HUD" then
		disconnectHudConnections()
		task.defer(scheduleRender)
	end
end)

local viewportConnections = {}
local function bindViewportConnections()
	for _, connection in ipairs(viewportConnections) do
		connection:Disconnect()
	end
	table.clear(viewportConnections)

	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnections[#viewportConnections + 1] = camera:GetPropertyChangedSignal("ViewportSize"):Connect(scheduleRender)
	end
	viewportConnections[#viewportConnections + 1] = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindViewportConnections()
		scheduleRender()
	end)
end

bindHudConnections()
bindViewportConnections()
scheduleRender()

script.Destroying:Connect(function()
	destroyed = true
	childAddedConnection:Disconnect()
	childRemovedConnection:Disconnect()
	disconnectHudConnections()
	for _, connection in ipairs(viewportConnections) do
		connection:Disconnect()
	end
	for button in pairs(hoverBindings) do
		clearHoverBinding(button)
	end
	root:unmount()
end)
