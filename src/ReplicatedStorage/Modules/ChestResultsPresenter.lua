local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChestOpenResultFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestOpenResultFormatter"))
local ChestVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestVisuals"))
local DevilFruitAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Assets"))

local Presenter = {}

local GUI_NAME = "ChestResultsGui"
local CHEST_PREVIEW_VIEWPORT_NAME = "ChestPreviewViewport"
local CHEST_PREVIEW_WORLD_NAME = "ChestPreviewWorld"
local CHEST_PREVIEW_CAMERA_NAME = "ChestPreviewCamera"
local REWARD_ROW_SCROLLER_NAME = "RewardRowScroller"
local REWARD_ROW_CONTENT_NAME = "RewardRowContent"
local REWARD_PREVIEW_VIEWPORT_NAME = "RewardModelViewport"
local REWARD_PREVIEW_WORLD_NAME = "RewardPreviewWorld"
local REWARD_PREVIEW_CAMERA_NAME = "RewardPreviewCamera"
local MORE_REWARDS_SCROLLER_NAME = "MoreRewardsScroller"
local REWARD_TEMPLATE_NAME = "RewardCardTemplate"
local FEATURED_TEMPLATE_NAME = "FeaturedRewardCardTemplate"
local GENERATED_CARD_ATTRIBUTE = "ChestResultsGeneratedCard"
local REWARD_TYPE_DEVIL_FRUIT = "DevilFruit"
local SOURCE_VISIBLE_CARD_COUNT = 8
local MAX_RENDERED_REWARD_CARDS = 24
local REWARD_CARD_WIDTH_SCALE = 0.18
local REWARD_CARD_PADDING_SCALE = 0.025
local REWARD_CARD_PADDING = UDim.new(REWARD_CARD_PADDING_SCALE, 0)
local REWARD_ROW_WIDTH_SCALE = (SOURCE_VISIBLE_CARD_COUNT * REWARD_CARD_WIDTH_SCALE)
	+ ((SOURCE_VISIBLE_CARD_COUNT - 1) * REWARD_CARD_PADDING_SCALE)
local REWARD_ROW_HEIGHT_SCALE = 1.4
local REWARD_ROW_EDGE_PADDING_SCALE = REWARD_CARD_PADDING_SCALE
local REWARD_ROW_EDGE_PADDING_MIN = 12
local REWARD_ROW_EDGE_PADDING_MAX = 24
local MORE_REWARD_ROW_HEIGHT = 18
local MORE_REWARD_ROW_PADDING = 2
local MOUSE_WHEEL_SCROLL_STEP = 48

local DEFAULT_CHEST_IMAGE = "rbxassetid://104345752533382"
local CHEST_GLOW_IMAGE = "rbxassetid://109815397959071"
local CLAIM_CHEST_ICON = "rbxassetid://88825249018556"
local ANCHOR_LEFT_IMAGE = "rbxassetid://83296177901635"
local ANCHOR_RIGHT_IMAGE = "rbxassetid://87910431269362"
local SPARKLE_A_IMAGE = "rbxassetid://91082304413966"
local SPARKLE_B_IMAGE = "rbxassetid://95629190896984"
local CROWN_IMAGE = "rbxassetid://93958716853645"
local FEATURED_GLOW_IMAGE = "rbxassetid://114516018211032"

local queue = {}
local activeConnections = {}
local assetAvailabilityByKey = {}
local fruitAssetAvailabilityByKey = {}
local showing = false
local activeGui = nil

local function new(className, props, children)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

local function disconnectActiveConnections()
	for _, connection in ipairs(activeConnections) do
		connection:Disconnect()
	end
	table.clear(activeConnections)
end

local function ensureCorner(parent, radius)
	local corner = parent:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = parent
	end
	corner.CornerRadius = radius
	return corner
end

local function ensureStroke(parent, color, thickness, transparency, applyMode)
	local stroke = parent:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = parent
	end
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.ApplyStrokeMode = applyMode or stroke.ApplyStrokeMode
	return stroke
end

local function ensureGradient(parent, topColor, bottomColor)
	local gradient = parent:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = parent
	end
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	})
	return gradient
end

local function prepareScreenGui(gui)
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 650
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
end

local function createRewardCardTemplate(name, featured)
	local frame = new("Frame", {
		Name = name,
		BackgroundColor3 = Color3.fromRGB(15, 27, 42),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		LayoutOrder = -1000,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		ZIndex = 6,
	})
	ensureCorner(frame, UDim.new(0.1, 0))
	local stroke = ensureStroke(
		frame,
		if featured then Color3.fromRGB(255, 216, 107) else Color3.fromRGB(212, 175, 55),
		if featured then 5 else 2,
		0.2,
		Enum.ApplyStrokeMode.Contextual
	)
	ensureGradient(stroke, Color3.fromRGB(255, 232, 129), Color3.fromRGB(176, 111, 28))

	new("TextLabel", {
		Name = "RewardName",
		BackgroundTransparency = 1,
		Font = Enum.Font.SourceSans,
		Position = UDim2.fromScale(0, 0.03),
		Size = UDim2.fromScale(1, 0.18),
		Text = featured and "Devil Fruit" or "Reward",
		TextColor3 = if featured then Color3.fromRGB(255, 104, 104) else Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 8,
		Parent = frame,
	})
	new("ImageLabel", {
		Name = "RewardIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = "",
		Position = UDim2.fromScale(0.5, 0.46),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(0.7, 0.5),
		ZIndex = 7,
		Parent = frame,
	})
	local amountBox = new("Frame", {
		Name = "AmountBox",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(7, 17, 28),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.68, 0.15),
		ZIndex = 8,
		Parent = frame,
	})
	ensureCorner(amountBox, UDim.new(0.15, 0))
	ensureStroke(
		amountBox,
		if featured then Color3.fromRGB(250, 213, 103) else Color3.fromRGB(212, 175, 55),
		if featured then 2.5 else 2,
		0.2,
		Enum.ApplyStrokeMode.Contextual
	)
	new("TextLabel", {
		Name = "Amount Text",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Size = UDim2.fromScale(1, 1),
		Text = "+1",
		TextColor3 = Color3.fromRGB(255, 235, 180),
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 9,
		Parent = amountBox,
	})

	if featured then
		new("ImageLabel", {
			Name = "CrownImage",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = CROWN_IMAGE,
			Position = UDim2.fromScale(0.5, -0.055),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.45, 0.3),
			ZIndex = 9,
			Parent = frame,
		})
		new("ImageLabel", {
			Name = "DevilFruitGlow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = FEATURED_GLOW_IMAGE,
			Position = UDim2.fromScale(0.475, 0.46),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.8, 0.9),
			ZIndex = 4,
			Parent = frame,
		})
		local sparkleSpecs = {
			{ "SmallSparkle1", SPARKLE_A_IMAGE, UDim2.fromScale(0.2, 0.425), UDim2.fromScale(0.4, 0.4), 0 },
			{ "SmallSparkle2", SPARKLE_B_IMAGE, UDim2.fromScale(0.85, 0.28), UDim2.fromScale(0.55, 0.55), 0 },
			{ "SmallSparkle3", SPARKLE_B_IMAGE, UDim2.fromScale(0.45, -0.2), UDim2.fromScale(0.4, 0.4), 0 },
			{ "SmallSparkle4", SPARKLE_A_IMAGE, UDim2.fromScale(0.95, 1), UDim2.fromScale(0.45, 0.45), 0.1 },
		}
		for _, spec in ipairs(sparkleSpecs) do
			new("ImageLabel", {
				Name = spec[1],
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = spec[2],
				ImageColor3 = Color3.fromRGB(255, 216, 107),
				ImageTransparency = spec[5],
				Position = spec[3],
				ScaleType = Enum.ScaleType.Fit,
				Size = spec[4],
				ZIndex = 6,
				Parent = frame,
			})
		end
	end

	return frame
end

local function createBaseTemplate(gui)
	gui:ClearAllChildren()

	new("Frame", {
		Name = "DarkOverlay",
		BackgroundColor3 = Color3.fromRGB(2, 6, 10),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = gui,
	})

	local mainFrame = new("Frame", {
		Name = "MainFrame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.75, 0.82),
		ZIndex = 2,
		Parent = gui,
	}, {
		new("UISizeConstraint", {
			MaxSize = Vector2.new(1080, 680),
			MinSize = Vector2.new(300, 260),
		}),
	})

	new("ImageLabel", {
		Name = "ChestGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = CHEST_GLOW_IMAGE,
		ImageTransparency = 0.4,
		Position = UDim2.fromScale(0.49, 0.42),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(0.64, 0.64),
		ZIndex = 3,
		Parent = mainFrame,
	})
	new("ImageLabel", {
		Name = "ChestImage",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Image = DEFAULT_CHEST_IMAGE,
		Position = UDim2.fromScale(0.5, 0.15),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(0.48, 0.48),
		ZIndex = 4,
		Parent = mainFrame,
	})

	local rewardsFrame = new("Frame", {
		Name = "RewardsFrame",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Position = UDim2.fromScale(0.5, 0.645),
		Size = UDim2.fromScale(0.66, 0.22),
		ZIndex = 5,
		Parent = mainFrame,
	})
	new("UIListLayout", {
		Name = "UIListLayout",
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = REWARD_CARD_PADDING,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = rewardsFrame,
	})
	createRewardCardTemplate(REWARD_TEMPLATE_NAME, false).Parent = rewardsFrame
	createRewardCardTemplate(FEATURED_TEMPLATE_NAME, true).Parent = rewardsFrame

	local buttonFrame = new("Frame", {
		Name = "ButtonFrame",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.55, 0.1),
		ZIndex = 8,
		Parent = mainFrame,
	})
	new("UIListLayout", {
		Name = "UIListLayout",
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Parent = buttonFrame,
	})
	local claimButton = new("TextButton", {
		Name = "ClaimCloseButton",
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(250, 229, 3),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(250, 50),
		Text = "CLAIM & CLOSE",
		TextColor3 = Color3.fromRGB(58, 33, 3),
		TextSize = 22,
		TextWrapped = true,
		ZIndex = 8,
		Parent = buttonFrame,
	})
	ensureCorner(claimButton, UDim.new(1, 0))
	ensureStroke(claimButton, Color3.fromRGB(199, 144, 5), 3, 0, Enum.ApplyStrokeMode.Border)
	ensureGradient(claimButton, Color3.fromRGB(255, 221, 60), Color3.fromRGB(248, 169, 9))
	new("ImageLabel", {
		Name = "ChestIcon",
		BackgroundTransparency = 1,
		Image = CLAIM_CHEST_ICON,
		ImageTransparency = 0.15,
		Position = UDim2.fromScale(0.05, 0.125),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(0.125, 0.75),
		ZIndex = 9,
		Parent = claimButton,
	})

	local headerFrame = new("Frame", {
		Name = "HeaderFrame",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.15, 0.02),
		Size = UDim2.fromScale(0.72, 0.22),
		ZIndex = 10,
		Parent = mainFrame,
	})
	local congratsText = new("TextLabel", {
		Name = "CongratsText",
		BackgroundTransparency = 1,
		Font = Enum.Font.Bangers,
		Position = UDim2.fromScale(0, -0.1),
		Size = UDim2.fromScale(1, 0.65),
		Text = "CONGRATS!",
		TextColor3 = Color3.fromRGB(255, 216, 107),
		TextScaled = true,
		TextStrokeColor3 = Color3.fromRGB(135, 68, 0),
		TextStrokeTransparency = 0.25,
		TextWrapped = true,
		ZIndex = 12,
		Parent = headerFrame,
	})
	ensureStroke(congratsText, Color3.fromRGB(92, 47, 0), 4, 0.2, Enum.ApplyStrokeMode.Contextual)
	ensureGradient(congratsText, Color3.fromRGB(255, 232, 129), Color3.fromRGB(238, 142, 23))
	new("TextLabel", {
		Name = "CongratsGlow",
		BackgroundTransparency = 1,
		Font = Enum.Font.Bangers,
		Position = UDim2.fromScale(-0.02, -0.19),
		Size = UDim2.fromScale(1.04, 0.85),
		Text = "CONGRATS!",
		TextColor3 = Color3.fromRGB(246, 185, 59),
		TextScaled = true,
		TextTransparency = 0.45,
		TextWrapped = true,
		ZIndex = 11,
		Parent = headerFrame,
	})
	local subtitle = new("TextLabel", {
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.58, 0.165),
		Text = "You opened 1 Chest",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 12,
		Parent = headerFrame,
	})
	ensureStroke(subtitle, Color3.fromRGB(106, 60, 8), 2, 0.45, Enum.ApplyStrokeMode.Contextual)
	for _, lineSpec in ipairs({
		{ "LeftLine", Vector2.new(1, 0.5), UDim2.fromScale(0.31, 0.64) },
		{ "RightLine", Vector2.new(0, 0.5), UDim2.fromScale(0.69, 0.64) },
	}) do
		local line = new("Frame", {
			Name = lineSpec[1],
			AnchorPoint = lineSpec[2],
			BackgroundColor3 = Color3.fromRGB(212, 175, 55),
			BorderSizePixel = 0,
			Position = lineSpec[3],
			Size = UDim2.fromScale(0.15, 0.012),
			ZIndex = 12,
			Parent = headerFrame,
		})
		ensureGradient(line, Color3.fromRGB(255, 216, 107), Color3.fromRGB(175, 112, 9))
	end
	new("ImageLabel", {
		Name = "LeftAnchor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = ANCHOR_LEFT_IMAGE,
		Position = UDim2.fromScale(0.205, 0.42),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(0.1, 0.35),
		ZIndex = 12,
		Parent = headerFrame,
	})
	new("ImageLabel", {
		Name = "RightAnchor",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = ANCHOR_RIGHT_IMAGE,
		Position = UDim2.fromScale(0.793, 0.42),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromScale(0.1, 0.35),
		ZIndex = 12,
		Parent = headerFrame,
	})

	for _, spec in ipairs({
		{ "SmallSparkle1", SPARKLE_A_IMAGE, UDim2.fromScale(0.375, 0.425), UDim2.fromScale(0.15, 0.15), 0.35 },
		{ "SmallSparkle2", SPARKLE_B_IMAGE, UDim2.fromScale(0.62, 0.29), UDim2.fromScale(0.125, 0.125), 0.3 },
		{ "SmallSparkle3", SPARKLE_A_IMAGE, UDim2.fromScale(0.62, 0.52), UDim2.fromScale(0.1, 0.1), 0.3 },
	}) do
		new("ImageLabel", {
			Name = spec[1],
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = spec[2],
			ImageColor3 = Color3.fromRGB(255, 216, 107),
			ImageTransparency = spec[5],
			Position = spec[3],
			ScaleType = Enum.ScaleType.Fit,
			Size = spec[4],
			ZIndex = 6,
			Parent = mainFrame,
		})
	end

	local exitButton = new("TextButton", {
		Name = "ExitButton",
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(167, 25, 18),
		BorderSizePixel = 0,
		Font = Enum.Font.SourceSans,
		Position = UDim2.fromScale(0.9, 0.08),
		Size = UDim2.fromScale(0.03, 0.05),
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 50,
		Parent = gui,
	})
	ensureCorner(exitButton, UDim.new(0, 15))
	ensureStroke(exitButton, Color3.fromRGB(212, 175, 55), 2, 0, Enum.ApplyStrokeMode.Border)
end

local function getRewardsFrame(gui)
	local mainFrame = gui:FindFirstChild("MainFrame")
	return mainFrame and mainFrame:FindFirstChild("RewardsFrame") or nil
end

local function prepareTemplate(template)
	if template and template:IsA("GuiObject") then
		template.Visible = false
		template.LayoutOrder = -1000
		template.Size = UDim2.fromOffset(0, 0)
		template:SetAttribute(GENERATED_CARD_ATTRIBUTE, nil)
	end
end

local function findCardSource(rewardsFrame, preferredName)
	local preferred = rewardsFrame:FindFirstChild(preferredName)
	if preferred and preferred:IsA("Frame") then
		return preferred
	end
	for _, child in ipairs(rewardsFrame:GetChildren()) do
		if child:IsA("Frame")
			and child.Name ~= REWARD_TEMPLATE_NAME
			and child.Name ~= FEATURED_TEMPLATE_NAME
			and child:GetAttribute(GENERATED_CARD_ATTRIBUTE) ~= true then
			return child
		end
	end
	return nil
end

local function ensureRewardTemplates(rewardsFrame)
	local rewardTemplate = rewardsFrame:FindFirstChild(REWARD_TEMPLATE_NAME)
	if not (rewardTemplate and rewardTemplate:IsA("Frame")) then
		local source = findCardSource(rewardsFrame, "Rice")
		rewardTemplate = if source then source:Clone() else createRewardCardTemplate(REWARD_TEMPLATE_NAME, false)
		rewardTemplate.Name = REWARD_TEMPLATE_NAME
		rewardTemplate.Parent = rewardsFrame
	end

	local featuredTemplate = rewardsFrame:FindFirstChild(FEATURED_TEMPLATE_NAME)
	if not (featuredTemplate and featuredTemplate:IsA("Frame")) then
		local source = findCardSource(rewardsFrame, "Devil Fruit")
		featuredTemplate = if source then source:Clone() else createRewardCardTemplate(FEATURED_TEMPLATE_NAME, true)
		featuredTemplate.Name = FEATURED_TEMPLATE_NAME
		featuredTemplate.Parent = rewardsFrame
	end

	prepareTemplate(rewardTemplate)
	prepareTemplate(featuredTemplate)

	return rewardTemplate, featuredTemplate
end

local function ensureRewardLayout(rewardsFrame)
	rewardsFrame.AnchorPoint = Vector2.new(0.5, 0)
	rewardsFrame.ClipsDescendants = false
	rewardsFrame.Position = UDim2.fromScale(0.5, 0.645)
	rewardsFrame.Size = UDim2.fromScale(0.66, 0.22)
	rewardsFrame.ZIndex = 5

	local staleScroller = rewardsFrame:FindFirstChild("RewardCardScroller")
	if staleScroller then
		staleScroller:Destroy()
	end

	for _, child in ipairs(rewardsFrame:GetChildren()) do
		if child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function ensureRewardRow(rewardsFrame)
	ensureRewardLayout(rewardsFrame)

	local scroller = rewardsFrame:FindFirstChild(REWARD_ROW_SCROLLER_NAME)
	if not (scroller and scroller:IsA("ScrollingFrame")) then
		if scroller then
			scroller:Destroy()
		end
		scroller = Instance.new("ScrollingFrame")
		scroller.Name = REWARD_ROW_SCROLLER_NAME
		scroller.Parent = rewardsFrame
	end

	scroller.Active = true
	scroller.AnchorPoint = Vector2.new(0.5, 0.5)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.CanvasSize = UDim2.fromOffset(0, 0)
	scroller.ClipsDescendants = true
	scroller.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroller.Position = UDim2.fromScale(0.5, 0.5)
	scroller.ScrollBarImageTransparency = 1
	scroller.ScrollBarThickness = 0
	scroller.ScrollingDirection = Enum.ScrollingDirection.X
	scroller.ScrollingEnabled = true
	scroller.Selectable = true
	scroller.Size = UDim2.fromScale(REWARD_ROW_WIDTH_SCALE, REWARD_ROW_HEIGHT_SCALE)
	scroller.ZIndex = rewardsFrame.ZIndex

	local content = scroller:FindFirstChild(REWARD_ROW_CONTENT_NAME)
	if not (content and content:IsA("Frame")) then
		if content then
			content:Destroy()
		end
		content = Instance.new("Frame")
		content.Name = REWARD_ROW_CONTENT_NAME
		content.Parent = scroller
	end

	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ClipsDescendants = false
	content.Position = UDim2.fromScale(0, 0)
	content.ZIndex = rewardsFrame.ZIndex

	local layout = content:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Name = "UIListLayout"
		layout.Parent = content
	end

	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center

	return scroller, content, layout
end

local function ensureTemplate(gui)
	prepareScreenGui(gui)

	local mainFrame = gui:FindFirstChild("MainFrame")
	local rewardsFrame = getRewardsFrame(gui)
	if not (mainFrame and mainFrame:IsA("Frame") and rewardsFrame and rewardsFrame:IsA("GuiObject")) then
		createBaseTemplate(gui)
		rewardsFrame = getRewardsFrame(gui)
	end

	if not rewardsFrame then
		return false
	end

	ensureRewardTemplates(rewardsFrame)
	ensureRewardLayout(rewardsFrame)
	return true
end

local function getOrCreateGui()
	if not RunService:IsClient() then
		return nil
	end

	local player = Players.LocalPlayer
	if not player then
		return nil
	end

	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 5)
	if not playerGui then
		return nil
	end

	local gui = playerGui:FindFirstChild(GUI_NAME)
	local createdGui = false
	if not (gui and gui:IsA("ScreenGui")) then
		local starterTemplate = StarterGui:FindFirstChild(GUI_NAME)
		if starterTemplate and starterTemplate:IsA("ScreenGui") then
			gui = starterTemplate:Clone()
			gui.Parent = playerGui
		else
			gui = Instance.new("ScreenGui")
			gui.Name = GUI_NAME
			gui.Parent = playerGui
		end
		createdGui = true
	end

	if not ensureTemplate(gui) then
		return nil
	end

	if createdGui or not showing then
		gui.Enabled = false
	end

	activeGui = gui
	return gui
end

local function findTextLabel(root, name)
	local instance = root and root:FindFirstChild(name, true)
	return if instance and instance:IsA("TextLabel") then instance else nil
end

local function findImageLabel(root, name)
	local instance = root and root:FindFirstChild(name, true)
	return if instance and instance:IsA("ImageLabel") then instance else nil
end

local function findViewportFrame(root, name)
	local instance = root and root:FindFirstChild(name, true)
	return if instance and instance:IsA("ViewportFrame") then instance else nil
end

local function syncViewportToChestImage(viewport, chestImage)
	viewport.AnchorPoint = chestImage.AnchorPoint
	viewport.Position = chestImage.Position
	viewport.Size = chestImage.Size
	viewport.Rotation = chestImage.Rotation
	viewport.ZIndex = chestImage.ZIndex
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = false
	viewport.Ambient = Color3.fromRGB(190, 190, 190)
	viewport.LightColor = Color3.fromRGB(255, 244, 219)
	viewport.LightDirection = Vector3.new(-0.35, -1, -0.45)
end

local function ensureChestPreviewViewport(gui)
	local mainFrame = gui:FindFirstChild("MainFrame")
	local chestImage = findImageLabel(gui, "ChestImage")
	if not (mainFrame and mainFrame:IsA("GuiObject") and chestImage) then
		return nil, chestImage
	end

	local viewport = findViewportFrame(mainFrame, CHEST_PREVIEW_VIEWPORT_NAME)
	if not viewport then
		viewport = Instance.new("ViewportFrame")
		viewport.Name = CHEST_PREVIEW_VIEWPORT_NAME
		viewport.Visible = false
		viewport.Parent = mainFrame
	end

	syncViewportToChestImage(viewport, chestImage)
	return viewport, chestImage
end

local function clearChestPreview(viewport)
	if not viewport then
		return
	end

	viewport.CurrentCamera = nil
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end
end

local function resetChestPreview(gui)
	local viewport = findViewportFrame(gui, CHEST_PREVIEW_VIEWPORT_NAME)
	if viewport then
		clearChestPreview(viewport)
		viewport.Visible = false
	end

	local chestImage = findImageLabel(gui, "ChestImage")
	if chestImage then
		chestImage.Visible = true
	end
end

local function hasChestAsset(visualKey)
	local key = tostring(visualKey or "")
	if key == "" then
		return false
	end

	local cached = assetAvailabilityByKey[key]
	if cached ~= nil then
		return cached
	end

	local template = ChestVisuals.GetAssetTemplate(key)
	local hasAsset = template ~= nil
	assetAvailabilityByKey[key] = hasAsset
	return hasAsset
end

local function hasFruitPreviewAsset(fruitKey)
	local key = tostring(fruitKey or "")
	if key == "" then
		return false
	end

	local cached = fruitAssetAvailabilityByKey[key]
	if cached ~= nil then
		return cached
	end

	local hasAsset = DevilFruitAssets.HasWorldModel(key) == true
	fruitAssetAvailabilityByKey[key] = hasAsset
	return hasAsset
end

local function freezePreviewPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
end

local function freezePreviewModel(model)
	if model:IsA("BasePart") then
		freezePreviewPart(model)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			freezePreviewPart(descendant)
		end
	end
end

local function createChestPreviewModel(visualKey)
	if not hasChestAsset(visualKey) then
		return nil
	end

	local ok, model = pcall(function()
		return ChestVisuals.CreatePreviewModel(visualKey)
	end)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		if typeof(model) == "Instance" then
			model:Destroy()
		end
		return nil
	end

	if model:GetAttribute("ChestVisualAssetName") == nil then
		model:Destroy()
		return nil
	end

	freezePreviewModel(model)
	return model
end

local function fitPreviewModel(model, camera, visualKey)
	model:PivotTo(ChestVisuals.GetPreviewRotation(visualKey))
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-boundsCFrame.Position) * model:GetPivot())
	local _, centeredBoundsSize = model:GetBoundingBox()
	boundsSize = centeredBoundsSize

	local maxSize = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z, 1)
	local fieldOfView = 34
	local distance = (maxSize * 0.5) / math.tan(math.rad(fieldOfView) * 0.5) * 1.45
	local focus = Vector3.new(0, boundsSize.Y * 0.03, 0)

	camera.FieldOfView = fieldOfView
	camera.CFrame = CFrame.lookAt(Vector3.new(distance * 0.36, distance * 0.18, distance), focus)
end

local function renderChestPreview(gui, model)
	local viewport, chestImage = ensureChestPreviewViewport(gui)
	if chestImage then
		chestImage.Image = tostring(model.chestImage or DEFAULT_CHEST_IMAGE)
		chestImage.Visible = true
	end
	if not viewport then
		return false
	end

	clearChestPreview(viewport)

	local visualKey = tostring(model.chestVisualKey or "")
	local previewModel = createChestPreviewModel(visualKey)
	if not previewModel then
		viewport.Visible = false
		return false
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = CHEST_PREVIEW_WORLD_NAME
	worldModel.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Name = CHEST_PREVIEW_CAMERA_NAME
	camera.Parent = viewport

	previewModel.Parent = worldModel
	local ok = pcall(function()
		fitPreviewModel(previewModel, camera, visualKey)
	end)
	if not ok then
		clearChestPreview(viewport)
		viewport.Visible = false
		return false
	end

	viewport.CurrentCamera = camera
	viewport.Visible = true
	if chestImage then
		chestImage.Visible = false
	end
	return true
end

local function clearRewardPreview(viewport)
	if not viewport then
		return
	end

	viewport.CurrentCamera = nil
	for _, child in ipairs(viewport:GetChildren()) do
		child:Destroy()
	end
end

local function getRewardRowMetrics(rewardsFrame, cardCount)
	local sourceSize = rewardsFrame.AbsoluteSize
	local sourceWidth = math.max(1, sourceSize.X)
	local sourceHeight = math.max(1, sourceSize.Y)
	local safeCardCount = math.max(0, tonumber(cardCount) or 0)
	local cardWidth = math.max(1, math.floor((sourceWidth * REWARD_CARD_WIDTH_SCALE) + 0.5))
	local cardHeight = math.max(1, math.floor(sourceHeight + 0.5))
	local padding = math.max(0, math.floor((sourceWidth * REWARD_CARD_PADDING_SCALE) + 0.5))
	local edgePadding = math.clamp(
		math.floor((sourceWidth * REWARD_ROW_EDGE_PADDING_SCALE) + 0.5),
		REWARD_ROW_EDGE_PADDING_MIN,
		REWARD_ROW_EDGE_PADDING_MAX
	)
	local baseRowWidth = math.max(1, math.floor((sourceWidth * REWARD_ROW_WIDTH_SCALE) + 0.5))
	local rowWidth = baseRowWidth + (edgePadding * 2)
	local rowHeight = math.max(1, math.floor((sourceHeight * REWARD_ROW_HEIGHT_SCALE) + 0.5))
	local cardContentWidth = (safeCardCount * cardWidth) + (math.max(0, safeCardCount - 1) * padding)
	local contentWidth = cardContentWidth + (edgePadding * 2)

	return {
		cardHeight = cardHeight,
		cardWidth = cardWidth,
		contentWidth = contentWidth,
		edgePadding = edgePadding,
		padding = padding,
		rowHeight = rowHeight,
		rowWidth = rowWidth,
	}
end

local function getMaxCanvasX(scroller)
	return math.max(0, scroller.AbsoluteCanvasSize.X - scroller.AbsoluteSize.X)
end

local function clampRewardRowCanvas(scroller)
	local maxX = getMaxCanvasX(scroller)
	if scroller.CanvasPosition.X > maxX then
		scroller.CanvasPosition = Vector2.new(maxX, 0)
	elseif scroller.CanvasPosition.Y ~= 0 then
		scroller.CanvasPosition = Vector2.new(scroller.CanvasPosition.X, 0)
	end
end

local function updateRewardRowMetrics(rewardsFrame, scroller, content, layout, cardCount)
	local metrics = getRewardRowMetrics(rewardsFrame, cardCount)
	scroller.Size = UDim2.fromOffset(metrics.rowWidth, metrics.rowHeight)
	layout.Padding = UDim.new(0, metrics.padding)

	local contentPadding = content:FindFirstChildOfClass("UIPadding")
	if not contentPadding then
		contentPadding = Instance.new("UIPadding")
		contentPadding.Name = "RewardRowContentPadding"
		contentPadding.Parent = content
	end
	contentPadding.PaddingBottom = UDim.new(0, 0)
	contentPadding.PaddingLeft = UDim.new(0, metrics.edgePadding)
	contentPadding.PaddingRight = UDim.new(0, metrics.edgePadding)
	contentPadding.PaddingTop = UDim.new(0, 0)

	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("GuiObject") and child:GetAttribute(GENERATED_CARD_ATTRIBUTE) == true then
			child.Size = UDim2.fromOffset(metrics.cardWidth, metrics.cardHeight)
		end
	end

	local layoutWidth = math.max(0, layout.AbsoluteContentSize.X)
	local contentWidth = math.max(metrics.rowWidth, metrics.contentWidth, layoutWidth + (metrics.edgePadding * 2))
	content.Size = UDim2.fromOffset(contentWidth, metrics.rowHeight)
	scroller.CanvasSize = UDim2.fromOffset(contentWidth, 0)
	clampRewardRowCanvas(scroller)

	return metrics
end

local function isPointInsideGuiObject(guiObject, position)
	local absolutePosition = guiObject.AbsolutePosition
	local absoluteSize = guiObject.AbsoluteSize
	return position.X >= absolutePosition.X
		and position.X <= absolutePosition.X + absoluteSize.X
		and position.Y >= absolutePosition.Y
		and position.Y <= absolutePosition.Y + absoluteSize.Y
end

local function isInputOverNestedScroller(scroller, input)
	local position = Vector2.new(input.Position.X, input.Position.Y)
	for _, descendant in ipairs(scroller:GetDescendants()) do
		if descendant:IsA("ScrollingFrame")
			and descendant ~= scroller
			and descendant.Visible
			and isPointInsideGuiObject(descendant, position)
		then
			return true
		end
	end

	return false
end

local function connectRewardRowEvents(rewardsFrame, scroller, content, layout, cardCount)
	local function refresh()
		updateRewardRowMetrics(rewardsFrame, scroller, content, layout, cardCount)
	end

	activeConnections[#activeConnections + 1] = rewardsFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	activeConnections[#activeConnections + 1] = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refresh)
	activeConnections[#activeConnections + 1] = scroller.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel or isInputOverNestedScroller(scroller, input) then
			return
		end

		local maxX = getMaxCanvasX(scroller)
		if maxX <= 0 then
			return
		end

		local nextX = math.clamp(
			scroller.CanvasPosition.X - (input.Position.Z * MOUSE_WHEEL_SCROLL_STEP),
			0,
			maxX
		)
		scroller.CanvasPosition = Vector2.new(nextX, 0)
	end)

	task.defer(refresh)
end

local function resetRewardPreview(card)
	local viewport = findViewportFrame(card, REWARD_PREVIEW_VIEWPORT_NAME)
	if viewport then
		clearRewardPreview(viewport)
		viewport.Visible = false
	end
end

local function syncViewportToRewardIcon(viewport, icon)
	viewport.AnchorPoint = icon.AnchorPoint
	viewport.Position = icon.Position
	viewport.Rotation = icon.Rotation
	viewport.Size = icon.Size
	viewport.ZIndex = icon.ZIndex
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = false
	viewport.Ambient = Color3.fromRGB(206, 196, 186)
	viewport.LightColor = Color3.fromRGB(255, 252, 246)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
end

local function ensureRewardPreviewViewport(card, icon)
	if not (icon and icon.Parent) then
		return nil
	end

	local viewport = findViewportFrame(card, REWARD_PREVIEW_VIEWPORT_NAME)
	if not viewport then
		viewport = Instance.new("ViewportFrame")
		viewport.Name = REWARD_PREVIEW_VIEWPORT_NAME
		viewport.Visible = false
	end

	viewport.Parent = icon.Parent
	syncViewportToRewardIcon(viewport, icon)
	return viewport
end

local function sanitizeFruitRewardPreviewModel(model)
	freezePreviewModel(model)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("PointLight")
			or descendant:IsA("SpotLight")
			or descendant:IsA("SurfaceLight")
		then
			descendant.Enabled = false
		end
	end
end

local function createDevilFruitRewardPreviewModel(fruitKey)
	if not hasFruitPreviewAsset(fruitKey) then
		return nil
	end

	local ok, model = pcall(function()
		return DevilFruitAssets.ClonePreviewWorldModel(fruitKey)
	end)
	if not ok or typeof(model) ~= "Instance" then
		if typeof(model) == "Instance" then
			model:Destroy()
		end
		return nil
	end

	sanitizeFruitRewardPreviewModel(model)
	return model
end

local function getFruitRewardPreviewBoundingInfo(previewModel)
	if previewModel:IsA("BasePart") then
		return previewModel.CFrame, previewModel.Size
	end

	local ok, cf, size = pcall(function()
		return previewModel:GetBoundingBox()
	end)
	if ok then
		return cf, size
	end

	local part = previewModel:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.CFrame, part.Size
	end

	return CFrame.new(), Vector3.new(1, 1, 1)
end

local function fitDevilFruitRewardPreviewModel(previewModel, camera, fruitKey)
	local rotation = CFrame.Angles(math.rad(-10), math.rad(24), 0)
	if tostring(fruitKey or "") == "Tori" then
		rotation = CFrame.Angles(math.rad(-4), math.rad(24), 0)
	end

	pcall(function()
		if previewModel:IsA("Model") or previewModel:IsA("WorldModel") then
			previewModel:PivotTo(rotation)
		elseif previewModel:IsA("BasePart") then
			previewModel.CFrame = rotation
		end
	end)

	freezePreviewModel(previewModel)

	local boxCF, boxSize = getFruitRewardPreviewBoundingInfo(previewModel)
	local maxSize = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)

	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(
		boxCF.Position + Vector3.new(maxSize * 0.9, maxSize * 0.4, maxSize * 1.8),
		boxCF.Position
	)
end

local function renderDevilFruitRewardPreview(card, icon, reward)
	local fruitKey = tostring(reward.fruitKey or "")
	if tostring(reward.rewardType or "") ~= REWARD_TYPE_DEVIL_FRUIT or fruitKey == "" then
		return false
	end

	local viewport = ensureRewardPreviewViewport(card, icon)
	if not viewport then
		return false
	end

	clearRewardPreview(viewport)

	local previewModel = createDevilFruitRewardPreviewModel(fruitKey)
	if not previewModel then
		viewport.Visible = false
		return false
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = REWARD_PREVIEW_WORLD_NAME
	worldModel.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Name = REWARD_PREVIEW_CAMERA_NAME
	camera.Parent = viewport

	previewModel.Parent = worldModel
	local ok = pcall(function()
		fitDevilFruitRewardPreviewModel(previewModel, camera, fruitKey)
	end)
	if not ok then
		clearRewardPreview(viewport)
		viewport.Visible = false
		return false
	end

	viewport.CurrentCamera = camera
	viewport.Visible = true
	icon.Visible = false
	return true
end

local function resetMoreRewardsCard(card)
	local scroller = card:FindFirstChild(MORE_REWARDS_SCROLLER_NAME, true)
	if scroller then
		scroller:Destroy()
	end
end

local function getRewardAmountText(reward)
	local amountText = tostring(reward.amountText or "")
	if amountText ~= "" then
		return amountText
	end

	local amount = math.max(0, tonumber(reward.amount) or 0)
	if amount > 0 then
		return "+" .. tostring(amount)
	end

	return "+1"
end

local function createMoreRewardRow(parent, reward, index)
	local row = new("Frame", {
		Name = "MoreRewardRow" .. tostring(index),
		BackgroundColor3 = Color3.fromRGB(9, 20, 32),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = index,
		Size = UDim2.new(1, -2, 0, MORE_REWARD_ROW_HEIGHT),
		ZIndex = parent.ZIndex + 1,
		Parent = parent,
	})
	ensureCorner(row, UDim.new(0, 4))

	local iconImage = tostring(reward.icon or "")
	new("ImageLabel", {
		Name = "MiniIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Image = iconImage,
		Position = UDim2.new(0, 2, 0.5, 0),
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(14, 14),
		Visible = iconImage ~= "",
		ZIndex = row.ZIndex + 1,
		Parent = row,
	})

	new("TextLabel", {
		Name = "MiniName",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(0.62, -18, 1, 0),
		Text = tostring(reward.name or "Reward"),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	}, {
		new("UITextSizeConstraint", {
			MaxTextSize = 9,
			MinTextSize = 6,
		}),
	})

	new("TextLabel", {
		Name = "MiniAmount",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.38, -2, 1, 0),
		Text = getRewardAmountText(reward),
		TextColor3 = Color3.fromRGB(255, 235, 180),
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = row.ZIndex + 1,
		Parent = row,
	}, {
		new("UITextSizeConstraint", {
			MaxTextSize = 9,
			MinTextSize = 6,
		}),
	})

	return row
end

local function renderMoreRewardsCard(card, icon, reward)
	resetMoreRewardsCard(card)

	local overflowRewards = if typeof(reward.overflowRewards) == "table" then reward.overflowRewards else {}
	if #overflowRewards <= 0 then
		return false
	end

	resetRewardPreview(card)
	if icon then
		icon.Visible = false
	end

	local scroller = new("ScrollingFrame", {
		Name = MORE_REWARDS_SCROLLER_NAME,
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.51),
		ScrollBarImageTransparency = 0.75,
		ScrollBarThickness = 2,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = true,
		Selectable = true,
		Size = UDim2.fromScale(0.9, 0.54),
		ZIndex = card.ZIndex + 2,
		Parent = card,
	}, {
		new("UIListLayout", {
			Name = "UIListLayout",
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, MORE_REWARD_ROW_PADDING),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
		new("UIPadding", {
			PaddingBottom = UDim.new(0, 1),
			PaddingLeft = UDim.new(0, 1),
			PaddingRight = UDim.new(0, 1),
			PaddingTop = UDim.new(0, 1),
		}),
	})

	local renderedRows = 0
	for _, overflowReward in ipairs(overflowRewards) do
		if typeof(overflowReward) == "table" then
			renderedRows += 1
			createMoreRewardRow(scroller, overflowReward, renderedRows)
		end
	end

	if renderedRows <= 0 then
		scroller:Destroy()
		if icon then
			icon.Visible = true
		end
		return false
	end

	return true
end

local function setCardText(card, reward)
	resetMoreRewardsCard(card)

	local nameLabel = findTextLabel(card, "RewardName")
	if nameLabel then
		nameLabel.Text = tostring(reward.name or "Reward")
		if reward.isFeatured == true then
			nameLabel.TextColor3 = Color3.fromRGB(255, 104, 104)
		else
			nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end

	local icon = findImageLabel(card, "RewardIcon")
	local renderedPreview = false
	local renderedMoreRewards = false
	if icon then
		icon.Image = tostring(reward.icon or "")
		icon.Visible = true
		renderedMoreRewards = renderMoreRewardsCard(card, icon, reward)
		if not renderedMoreRewards then
			renderedPreview = renderDevilFruitRewardPreview(card, icon, reward)
		end
	end
	if not renderedPreview then
		resetRewardPreview(card)
	end

	local amountBox = card:FindFirstChild("AmountBox", true)
	local amountLabel = amountBox and (
		amountBox:FindFirstChild("Amount Text")
			or amountBox:FindFirstChild("AmountText")
			or amountBox:FindFirstChildWhichIsA("TextLabel")
	)
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = tostring(reward.amountText or "+1")
	end
end

local function clearRewardCards(rewardsFrame, content)
	for _, child in ipairs(rewardsFrame:GetChildren()) do
		local keep = child.Name == REWARD_TEMPLATE_NAME
			or child.Name == FEATURED_TEMPLATE_NAME
			or child.Name == REWARD_ROW_SCROLLER_NAME
		if (child:IsA("GuiObject") and not keep) or child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	if content then
		for _, child in ipairs(content:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
end

local function renderRewardCards(rewardsFrame, model)
	local rewardTemplate, featuredTemplate = ensureRewardTemplates(rewardsFrame)
	local scroller, content, layout = ensureRewardRow(rewardsFrame)
	clearRewardCards(rewardsFrame, content)

	local cards = {}
	if typeof(model.featuredReward) == "table" then
		local featured = table.clone(model.featuredReward)
		featured.isFeatured = true
		cards[#cards + 1] = featured
	end
	for _, reward in ipairs(model.rewardCards or {}) do
		if typeof(reward) == "table" then
			cards[#cards + 1] = reward
		end
	end

	local visibleCards = {}
	if #cards > MAX_RENDERED_REWARD_CARDS then
		for index = 1, math.min(#cards, MAX_RENDERED_REWARD_CARDS) do
			visibleCards[#visibleCards + 1] = cards[index]
		end

		local overflowRewards = {}
		for index = MAX_RENDERED_REWARD_CARDS + 1, #cards do
			overflowRewards[#overflowRewards + 1] = cards[index]
		end
		visibleCards[#visibleCards + 1] = {
			name = "More Rewards",
			amountText = "+" .. tostring(#overflowRewards),
			icon = CLAIM_CHEST_ICON,
			overflowRewards = overflowRewards,
		}
	else
		for index = 1, #cards do
			visibleCards[#visibleCards + 1] = cards[index]
		end
	end

	local metrics = updateRewardRowMetrics(rewardsFrame, scroller, content, layout, #visibleCards)
	scroller.CanvasPosition = Vector2.new(0, 0)

	for index, reward in ipairs(visibleCards) do
		local template = if reward.isFeatured == true then featuredTemplate else rewardTemplate
		local card = template:Clone()
		card.Name = "RewardCard" .. tostring(index)
		card.LayoutOrder = index
		card.Size = UDim2.fromOffset(metrics.cardWidth, metrics.cardHeight)
		card.Visible = true
		card:SetAttribute(GENERATED_CARD_ATTRIBUTE, true)
		setCardText(card, reward)
		card.Parent = content
	end

	updateRewardRowMetrics(rewardsFrame, scroller, content, layout, #visibleCards)
	connectRewardRowEvents(rewardsFrame, scroller, content, layout, #visibleCards)
end

local function renderGui(gui, openResult)
	local model = ChestOpenResultFormatter.BuildResultsScreenModel(openResult)
	if typeof(model) ~= "table" then
		return false
	end

	local subtitle = findTextLabel(gui, "Subtitle")
	if subtitle then
		subtitle.Text = tostring(model.subtitle or "You opened a Chest")
	end

	renderChestPreview(gui, model)

	local rewardsFrame = getRewardsFrame(gui)
	if not rewardsFrame then
		return false
	end
	renderRewardCards(rewardsFrame, model)

	return true
end

local function showNext()
	disconnectActiveConnections()

	local openResult = table.remove(queue, 1)
	if openResult == nil then
		showing = false
		if activeGui then
			resetChestPreview(activeGui)
			activeGui.Enabled = false
		end
		return
	end

	local gui = getOrCreateGui()
	if not gui or not renderGui(gui, openResult) then
		showing = false
		return
	end

	showing = true
	gui.Enabled = true

	local function closeCurrent()
		gui.Enabled = false
		showNext()
	end

	local claimButton = gui:FindFirstChild("ClaimCloseButton", true)
	if claimButton and claimButton:IsA("GuiButton") then
		activeConnections[#activeConnections + 1] = claimButton.Activated:Connect(closeCurrent)
	end

	local exitButton = gui:FindFirstChild("ExitButton")
	if exitButton and exitButton:IsA("GuiButton") then
		activeConnections[#activeConnections + 1] = exitButton.Activated:Connect(closeCurrent)
	end
end

function Presenter.Enqueue(openResult)
	if not RunService:IsClient() then
		return false
	end

	if typeof(openResult) ~= "table" then
		return false
	end

	if getOrCreateGui() == nil then
		return false
	end

	local wasShowing = showing
	queue[#queue + 1] = openResult
	if not showing then
		showNext()
	end

	return wasShowing or showing
end

return Presenter
