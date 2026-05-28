local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Responsive = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Responsive"))

local function safeWait(parent, name)
	local obj = parent:WaitForChild(name, 15)
	if not obj then
		error(("Missing %s in %s"):format(name, parent:GetFullName()))
	end
	return obj
end

local function findRemote(name, className)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and remote:IsA(className) then
		return remote
	end

	return nil
end

local testerStatusFunction = findRemote("TesterStatusRequest", "RemoteFunction")
local testerStatusChangedEvent = findRemote("TesterStatusChanged", "RemoteEvent")
local testerCommandRequestEvent = findRemote("TesterCommandRequest", "RemoteEvent")
local adminCommandFeedbackEvent = findRemote("AdminCommandFeedback", "RemoteEvent")
local isTester = false
local function refreshTesterStatus()
	testerStatusFunction = findRemote("TesterStatusRequest", "RemoteFunction") or testerStatusFunction
	if testerStatusFunction and testerStatusFunction:IsA("RemoteFunction") then
		local ok, result = pcall(function()
			return testerStatusFunction:InvokeServer()
		end)
		isTester = ok and result == true
	else
		isTester = false
	end
	return isTester
end

refreshTesterStatus()

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local playerGui = safeWait(player, "PlayerGui")

local statusRefreshQueued = false
local gui = nil

local function queueTesterStatusRefresh()
	if statusRefreshQueued then
		return
	end

	statusRefreshQueued = true
	task.defer(function()
		statusRefreshQueued = false
		local active = refreshTesterStatus()
		if gui and not active then
			gui.Enabled = false
		end
	end)
end

local testerStatusChangedConnected = false
local function bindTesterStatusChangedEvent()
	if testerStatusChangedConnected then
		return
	end

	testerStatusChangedEvent = findRemote("TesterStatusChanged", "RemoteEvent") or testerStatusChangedEvent
	if not (testerStatusChangedEvent and testerStatusChangedEvent:IsA("RemoteEvent")) then
		return
	end

	testerStatusChangedConnected = true
	testerStatusChangedEvent.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.IsTester) == "boolean" then
			isTester = payload.IsTester
			if gui and not isTester then
				gui.Enabled = false
			end
			return
		end

		queueTesterStatusRefresh()
	end)
end

bindTesterStatusChangedEvent()

ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "TesterStatusChanged" then
		task.defer(bindTesterStatusChangedEvent)
	elseif child.Name == "TesterStatusRequest" then
		testerStatusFunction = findRemote("TesterStatusRequest", "RemoteFunction") or testerStatusFunction
		queueTesterStatusRefresh()
	elseif child.Name == "TesterCommandRequest" then
		testerCommandRequestEvent = findRemote("TesterCommandRequest", "RemoteEvent") or testerCommandRequestEvent
	elseif child.Name == "AdminCommandFeedback" then
		adminCommandFeedbackEvent = findRemote("AdminCommandFeedback", "RemoteEvent") or adminCommandFeedbackEvent
	end
end)

player:GetAttributeChangedSignal("EquippedTitleId"):Connect(queueTesterStatusRefresh)

local COLORS = {
	Backdrop = Color3.fromRGB(4, 8, 18),
	PanelTop = Color3.fromRGB(14, 28, 55),
	PanelBottom = Color3.fromRGB(7, 13, 30),
	Panel = Color3.fromRGB(10, 21, 43),
	PanelSoft = Color3.fromRGB(16, 32, 60),
	PanelRaised = Color3.fromRGB(22, 44, 78),
	Border = Color3.fromRGB(69, 113, 158),
	BorderSoft = Color3.fromRGB(38, 70, 110),
	Text = Color3.fromRGB(245, 249, 255),
	Muted = Color3.fromRGB(160, 178, 203),
	Faint = Color3.fromRGB(96, 122, 156),
	Gold = Color3.fromRGB(255, 198, 72),
	GoldDark = Color3.fromRGB(150, 95, 24),
	Cyan = Color3.fromRGB(105, 225, 255),
	Green = Color3.fromRGB(77, 214, 147),
	Red = Color3.fromRGB(238, 78, 82),
	RedDark = Color3.fromRGB(125, 28, 40),
	Black = Color3.fromRGB(0, 0, 0),
}

local FONT = Enum.Font.GothamBold
local BODY_FONT = Enum.Font.Gotham
local PANEL_WIDTH = 940
local PANEL_HEIGHT = 650
local PANEL_PADDING = 24
local MOBILE_PANEL_SCALE_CAP = 0.82
local STATUS_OK = COLORS.Green
local STATUS_WARN = COLORS.Gold
local STATUS_ERROR = COLORS.Red

local CATEGORY_ORDER = {
	"All",
	"Debug",
	"Devil Fruits",
	"Chests",
	"Economy",
	"Progression",
	"Spawns",
	"Resets",
}

local function trimText(text)
	return tostring(text or ""):match("^%s*(.-)%s*$") or ""
end

local function cleanSingleLine(text, limit)
	local value = trimText(text):gsub("\r", ""):gsub("\n", " ")
	if limit and #value > limit then
		value = value:sub(1, limit)
	end
	return value
end

local function normalizeText(text)
	return string.lower(cleanSingleLine(text, 1000))
end

local function create(className, props, children)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

local function addCorner(parent, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius),
		Parent = parent,
	})
end

local function addStroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		Parent = parent,
	})
end

local function addPadding(parent, left, top, right, bottom)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, left or 0),
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or left or 0),
		PaddingBottom = UDim.new(0, bottom or top or 0),
		Parent = parent,
	})
end

local function addGradient(parent, topColor, bottomColor)
	return create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, topColor),
			ColorSequenceKeypoint.new(1, bottomColor),
		}),
		Rotation = 90,
		Parent = parent,
	})
end

local function getPanelScale(viewport)
	local availableX = math.max(340, viewport.X - (PANEL_PADDING * 2))
	local availableY = math.max(260, viewport.Y - (PANEL_PADDING * 2))
	local scale = math.min(availableX / PANEL_WIDTH, availableY / PANEL_HEIGHT, 1)

	if Responsive.isCompact(viewport) then
		scale = math.min(scale, MOBILE_PANEL_SCALE_CAP)
	end

	return math.clamp(scale, 0.55, 1)
end

local function getFeedbackColor(status)
	if status == "rejected" or status == "error" or status == "failed" then
		return STATUS_ERROR
	elseif status == "warning" then
		return STATUS_WARN
	end

	return STATUS_OK
end

local function buildFruitOptions()
	local options = {}
	for _, fruit in ipairs(DevilFruitConfig.GetAllFruits()) do
		options[#options + 1] = {
			Label = tostring(fruit.DisplayName or fruit.FruitKey or "Fruit"),
			Value = tostring(fruit.FruitKey or fruit.DisplayName or ""),
		}
	end
	return options
end

local FRUIT_OPTIONS = buildFruitOptions()
local CHEST_OPTIONS = {
	{ Label = "Wooden", Value = "Wooden" },
	{ Label = "Iron", Value = "Iron" },
	{ Label = "Gold", Value = "Gold" },
}
local RESOURCE_OPTIONS = {
	{ Label = "Timber", Value = "Timber" },
	{ Label = "Iron", Value = "Iron" },
	{ Label = "Ancient Timber", Value = "AncientTimber" },
	{ Label = "Apple", Value = "Apple" },
	{ Label = "Rice", Value = "Rice" },
	{ Label = "Meat", Value = "Meat" },
	{ Label = "Sea Beast Meat", Value = "SeaBeastMeat" },
}
local BOOST_OPTIONS = {
	{ Label = "2x Beli", Value = "2xbeli" },
	{ Label = "x1.5 Speed", Value = "speed" },
}
local ON_OFF_OPTIONS = {
	{ Label = "On", Value = "on" },
	{ Label = "Off", Value = "off" },
}

local COMMANDS = {
	{
		Section = "Debug",
		Title = "Hitbox Visuals",
		Help = "Show ability and hazard hitboxes.",
		Controls = {
			{ Type = "select", Key = "state", Label = "State", Options = ON_OFF_OPTIONS, Default = "on" },
		},
		Build = function(values)
			return "/hitbox " .. values.state
		end,
	},
	{
		Section = "Debug",
		Title = "Invincible",
		Help = "Self-only test invincibility.",
		Controls = {
			{ Type = "select", Key = "state", Label = "State", Options = ON_OFF_OPTIONS, Default = "off" },
		},
		Build = function(values)
			return "/invincible " .. values.state
		end,
	},
	{
		Section = "Debug",
		Title = "Bounty Debug",
		Help = "Refresh and print your bounty breakdown.",
		Build = function()
			return "/bounty debug"
		end,
	},
	{
		Section = "Devil Fruits",
		Title = "Grant Fruit",
		Help = "Grant one fruit by alias. /fruit all is not available.",
		Controls = {
			{ Type = "select", Key = "fruit", Label = "Fruit", Options = FRUIT_OPTIONS, Default = FRUIT_OPTIONS[1] and FRUIT_OPTIONS[1].Value or "" },
		},
		Build = function(values)
			return "/fruit " .. values.fruit
		end,
	},
	{
		Section = "Devil Fruits",
		Title = "Equip Fruit",
		Help = "Equip a specific fruit by alias.",
		Controls = {
			{ Type = "select", Key = "fruit", Label = "Fruit", Options = FRUIT_OPTIONS, Default = FRUIT_OPTIONS[1] and FRUIT_OPTIONS[1].Value or "" },
		},
		Build = function(values)
			return "/fruit equip " .. values.fruit
		end,
	},
	{
		Section = "Devil Fruits",
		Title = "Clear Fruit",
		Help = "Clear equipped fruit.",
		Build = function()
			return "/fruit clear"
		end,
	},
	{
		Section = "Devil Fruits",
		Title = "Fruit Cooldowns",
		Help = "Toggle Devil Fruit cooldown bypass.",
		Controls = {
			{ Type = "select", Key = "state", Label = "State", Options = ON_OFF_OPTIONS, Default = "off" },
		},
		Build = function(values)
			return "/fruit nocd " .. values.state
		end,
	},
	{
		Section = "Chests",
		Title = "Give Chest",
		Help = "Server cap: 5 chests per command.",
		Controls = {
			{ Type = "select", Key = "tier", Label = "Tier", Options = CHEST_OPTIONS, Default = "Wooden" },
			{ Type = "number", Key = "amount", Label = "Amount", Placeholder = "1", Default = "1", PositiveOnly = true },
		},
		Build = function(values)
			return "/chest " .. values.tier .. " " .. values.amount
		end,
	},
	{
		Section = "Economy",
		Title = "Give Beli",
		Help = "Server cap: 25,000 absolute delta.",
		Controls = {
			{ Type = "number", Key = "amount", Label = "Delta", Placeholder = "1000", Default = "1000", AllowNegative = true },
		},
		Build = function(values)
			return "/beli " .. values.amount
		end,
	},
	{
		Section = "Economy",
		Title = "Give Resource or Food",
		Help = "Caps: Timber 600, Iron 220, Ancient Timber 15, Apple/Rice 100, Meat 50, Sea Beast Meat 15.",
		Controls = {
			{ Type = "select", Key = "resource", Label = "Resource", Options = RESOURCE_OPTIONS, Default = "Timber" },
			{ Type = "number", Key = "amount", Label = "Amount", Placeholder = "25", Default = "25", PositiveOnly = true },
		},
		Build = function(values)
			return "/give " .. values.resource .. " " .. values.amount
		end,
	},
	{
		Section = "Economy",
		Title = "Give Boost",
		Help = "Server cap: 30 minutes.",
		Controls = {
			{ Type = "select", Key = "boost", Label = "Boost", Options = BOOST_OPTIONS, Default = "2xbeli" },
			{ Type = "number", Key = "minutes", Label = "Minutes", Placeholder = "5", Default = "5", PositiveOnly = true },
		},
		Build = function(values)
			return "/boost " .. values.boost .. " " .. values.minutes
		end,
	},
	{
		Section = "Progression",
		Title = "Set Speed",
		Help = "Server cap: speed 1 through 50.",
		Controls = {
			{ Type = "number", Key = "amount", Label = "Speed", Placeholder = "5", Default = "5", PositiveOnly = true },
		},
		Build = function(values)
			return "/speed " .. values.amount
		end,
	},
	{
		Section = "Progression",
		Title = "Reset Speed",
		Help = "Restore your profile speed to default.",
		Build = function()
			return "/speed reset"
		end,
	},
	{
		Section = "Spawns",
		Title = "Spawn Chest",
		Help = "Spawn one shared chest in front of you.",
		Build = function()
			return "/spawn chest"
		end,
	},
	{
		Section = "Spawns",
		Title = "Spawn Crew",
		Help = "Start a crew reward test run for yourself.",
		Build = function()
			return "/spawn crew"
		end,
	},
	{
		Section = "Resets",
		Title = "Tutorial Reset",
		Help = "Reset your first-time tutorial state.",
		Build = function()
			return "/tutorial reset"
		end,
	},
	{
		Section = "Resets",
		Title = "Gifts Reset",
		Help = "Self-only gift claim reset.",
		Build = function()
			return "/gifts reset"
		end,
	},
	{
		Section = "Resets",
		Title = "Gifts Clear",
		Help = "Self-only gift claim clear.",
		Build = function()
			return "/gifts clear"
		end,
	},
}

local function addSearchPart(parts, value)
	local text = normalizeText(value)
	if text ~= "" then
		parts[#parts + 1] = text
	end
end

local function addControlSearchParts(parts, control)
	addSearchPart(parts, control.Label)
	addSearchPart(parts, control.Key)
	addSearchPart(parts, control.Placeholder)

	for _, option in ipairs(control.Options or {}) do
		addSearchPart(parts, option.Label)
		addSearchPart(parts, option.Value)
	end
end

local function addFruitSearchParts(parts)
	for _, fruit in ipairs(DevilFruitConfig.GetAllFruits()) do
		addSearchPart(parts, fruit.Id)
		addSearchPart(parts, fruit.FruitKey)
		addSearchPart(parts, fruit.DisplayName)
		addSearchPart(parts, fruit.Rarity)
		for _, alias in ipairs(fruit.Aliases or {}) do
			addSearchPart(parts, alias)
		end
	end
end

local function buildCommandSearchText(command)
	local parts = {}
	addSearchPart(parts, command.Title)
	addSearchPart(parts, command.Section)
	addSearchPart(parts, command.Help)
	addSearchPart(parts, command.Id)

	for _, keyword in ipairs(command.Keywords or {}) do
		addSearchPart(parts, keyword)
	end

	for _, control in ipairs(command.Controls or {}) do
		addControlSearchParts(parts, control)
	end

	if command.Section == "Devil Fruits" then
		addSearchPart(parts, "df")
		addSearchPart(parts, "devil fruit")
		addFruitSearchParts(parts)
	end

	return table.concat(parts, " ")
end

for _, command in ipairs(COMMANDS) do
	command.SearchText = buildCommandSearchText(command)
end

gui = create("ScreenGui", {
	Name = "GrandLineRushTesterCommands",
	DisplayOrder = 10000,
	Enabled = false,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

local dim = create("Frame", {
	Name = "Dim",
	BackgroundColor3 = COLORS.Backdrop,
	BackgroundTransparency = 0.26,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Parent = gui,
})

local outerScroll = create("Frame", {
	Name = "TesterCommandOverlay",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	Parent = dim,
})

local shadow = create("Frame", {
	Name = "Shadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COLORS.Black,
	BackgroundTransparency = 0.58,
	BorderSizePixel = 0,
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
	Visible = false,
	Parent = outerScroll,
})
addCorner(shadow, 22)
local shadowScale = create("UIScale", {
	Name = "ResponsiveScale",
	Scale = 1,
	Parent = shadow,
})

local main = create("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COLORS.Panel,
	BorderSizePixel = 0,
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
	Visible = false,
	Parent = outerScroll,
})
addCorner(main, 20)
addStroke(main, COLORS.Border, 2, 0.1)
addGradient(main, COLORS.PanelTop, COLORS.PanelBottom)
local mainScale = create("UIScale", {
	Name = "ResponsiveScale",
	Scale = 1,
	Parent = main,
})

local header = create("Frame", {
	Name = "Header",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(24, 18),
	Size = UDim2.new(1, -48, 0, 78),
	Parent = main,
})

local icon = create("Frame", {
	Name = "TesterIcon",
	BackgroundColor3 = COLORS.Gold,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.fromOffset(54, 54),
	Parent = header,
})
addCorner(icon, 15)
addStroke(icon, COLORS.GoldDark, 2, 0)
create("TextLabel", {
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Size = UDim2.fromScale(1, 1),
	Text = "T",
	TextColor3 = Color3.fromRGB(31, 25, 11),
	TextSize = 28,
	Parent = icon,
})

create("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Position = UDim2.fromOffset(70, 7),
	Size = UDim2.new(1, -150, 0, 32),
	Text = "Tester Commands",
	TextColor3 = COLORS.Text,
	TextSize = 28,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

create("TextLabel", {
	Name = "Warning",
	BackgroundTransparency = 1,
	Font = BODY_FONT,
	Position = UDim2.fromOffset(71, 43),
	Size = UDim2.new(1, -170, 0, 24),
	Text = "Tester commands are logged. Use only for testing.",
	TextColor3 = COLORS.Gold,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = header,
})

local closeButton = create("TextButton", {
	Name = "Close",
	AutoButtonColor = true,
	BackgroundColor3 = COLORS.RedDark,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBlack,
	Position = UDim2.new(1, -52, 0, 10),
	Size = UDim2.fromOffset(46, 46),
	Text = "X",
	TextColor3 = COLORS.Text,
	TextSize = 22,
	Parent = header,
})
addCorner(closeButton, 14)
addStroke(closeButton, COLORS.Red, 1, 0.05)

local contentRoot = create("Frame", {
	Name = "Content",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(24, 106),
	Size = UDim2.new(1, -48, 1, -130),
	Parent = main,
})

local nav = create("Frame", {
	Name = "SectionNav",
	BackgroundColor3 = COLORS.Panel,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(0, 160, 1, -42),
	Parent = contentRoot,
})
addCorner(nav, 16)
addStroke(nav, COLORS.BorderSoft, 1, 0.2)
addPadding(nav, 10, 10, 10, 10)
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = nav,
})

local searchBox = create("TextBox", {
	Name = "CommandSearch",
	BackgroundColor3 = Color3.fromRGB(7, 17, 36),
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Font = BODY_FONT,
	PlaceholderColor3 = COLORS.Faint,
	PlaceholderText = "Search commands, fruits, speed, chest, spawn...",
	Position = UDim2.fromOffset(172, 0),
	Size = UDim2.new(1, -172, 0, 42),
	Text = "",
	TextColor3 = COLORS.Text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = contentRoot,
})
addCorner(searchBox, 14)
addStroke(searchBox, COLORS.BorderSoft, 1, 0.22)
addPadding(searchBox, 14, 0, 14, 0)

local commandScroll = create("ScrollingFrame", {
	Name = "CommandScroll",
	Active = true,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = COLORS.Panel,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	Position = UDim2.fromOffset(172, 54),
	ScrollBarImageColor3 = COLORS.Gold,
	ScrollBarThickness = 7,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Size = UDim2.new(1, -172, 1, -96),
	Parent = contentRoot,
})
addCorner(commandScroll, 16)
addStroke(commandScroll, COLORS.BorderSoft, 1, 0.2)

local commandPadding = addPadding(commandScroll, 14, 14, 14, 14)
local commandLayout = create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	Padding = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = commandScroll,
})

local statusLabel = create("TextLabel", {
	Name = "Status",
	BackgroundColor3 = COLORS.PanelSoft,
	BorderSizePixel = 0,
	Font = BODY_FONT,
	Position = UDim2.new(0, 0, 1, -34),
	Size = UDim2.new(1, 0, 0, 34),
	Text = "Ready.",
	TextColor3 = COLORS.Muted,
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = contentRoot,
})
addCorner(statusLabel, 12)
addStroke(statusLabel, COLORS.BorderSoft, 1, 0.35)
addPadding(statusLabel, 12, 0, 12, 0)

local categoryButtons = {}
local selectedCategory = "All"
local searchQuery = ""
local lastSentAt = 0
local renderCommandList

local function setStatus(text, color)
	statusLabel.Text = cleanSingleLine(text, 180)
	statusLabel.TextColor3 = color or COLORS.Muted
end

local function updateCategoryButtonStyles()
	for categoryName, button in pairs(categoryButtons) do
		local active = categoryName == selectedCategory
		button.BackgroundColor3 = active and COLORS.Gold or COLORS.PanelRaised
		button.TextColor3 = active and Color3.fromRGB(31, 24, 10) or COLORS.Text
	end
end

for index, categoryName in ipairs(CATEGORY_ORDER) do
	local button = create("TextButton", {
		Name = categoryName:gsub("%s+", "") .. "Button",
		AutoButtonColor = true,
		BackgroundColor3 = categoryName == selectedCategory and COLORS.Gold or COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, 36),
		Text = categoryName,
		TextColor3 = categoryName == selectedCategory and Color3.fromRGB(31, 24, 10) or COLORS.Text,
		TextSize = 12,
		Parent = nav,
	})
	addCorner(button, 10)
	categoryButtons[categoryName] = button
	button.Activated:Connect(function()
		selectedCategory = categoryName
		updateCategoryButtonStyles()
		if renderCommandList then
			renderCommandList()
		end
	end)
end

local function makeSelector(parent, control, values)
	local selectedValue = tostring(control.Default or ((control.Options and control.Options[1]) and control.Options[1].Value) or "")
	values[control.Key] = selectedValue

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Text = tostring(control.Label or "Select"),
		TextColor3 = COLORS.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})

	local optionGrid = create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = parent,
	})

	local layout = create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(8, 8),
		CellSize = UDim2.new(0.5, -4, 0, 30),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = optionGrid,
	})

	local buttons = {}
	local function refresh()
		for value, button in pairs(buttons) do
			local active = value == values[control.Key]
			button.BackgroundColor3 = active and COLORS.Gold or COLORS.PanelRaised
			button.TextColor3 = active and Color3.fromRGB(31, 24, 10) or COLORS.Text
		end
	end

	for optionIndex, option in ipairs(control.Options or {}) do
		local value = tostring(option.Value or "")
		local text = tostring(option.Label or value)
		local button = create("TextButton", {
			AutoButtonColor = true,
			BackgroundColor3 = COLORS.PanelRaised,
			BorderSizePixel = 0,
			Font = FONT,
			LayoutOrder = optionIndex,
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextColor3 = COLORS.Text,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = optionGrid,
		})
		addCorner(button, 10)
		buttons[value] = button
		button.Activated:Connect(function()
			values[control.Key] = value
			refresh()
		end)
	end

	local function updateSelectorHeight()
		optionGrid.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSelectorHeight)
	task.defer(updateSelectorHeight)
	refresh()
end

local function makeNumberInput(parent, control, values)
	values[control.Key] = tostring(control.Default or "")

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Text = tostring(control.Label or "Amount"),
		TextColor3 = COLORS.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})

	local box = create("TextBox", {
		BackgroundColor3 = Color3.fromRGB(7, 17, 36),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = BODY_FONT,
		LayoutOrder = 2,
		PlaceholderColor3 = COLORS.Faint,
		PlaceholderText = tostring(control.Placeholder or ""),
		Size = UDim2.new(1, 0, 0, 34),
		Text = tostring(control.Default or ""),
		TextColor3 = COLORS.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	addCorner(box, 10)
	addStroke(box, COLORS.BorderSoft, 1, 0.28)
	addPadding(box, 10, 0, 10, 0)

	box:GetPropertyChangedSignal("Text"):Connect(function()
		values[control.Key] = cleanSingleLine(box.Text, 24)
	end)
end

local function validateControlValues(command, values)
	for _, control in ipairs(command.Controls or {}) do
		if control.Type == "number" then
			local raw = cleanSingleLine(values[control.Key], 24)
			local parsed = tonumber(raw)
			if parsed == nil or parsed ~= parsed then
				return false, tostring(control.Label or "Amount") .. " must be a number."
			end
			if control.PositiveOnly == true and parsed <= 0 then
				return false, tostring(control.Label or "Amount") .. " must be positive."
			end
			if control.AllowNegative ~= true and parsed < 0 then
				return false, tostring(control.Label or "Amount") .. " cannot be negative."
			end
			values[control.Key] = raw
		elseif control.Type == "select" then
			local value = cleanSingleLine(values[control.Key], 80)
			if value == "" then
				return false, tostring(control.Label or "Selection") .. " is required."
			end
			values[control.Key] = value
		end
	end

	return true
end

local function makeCommandCard(command, layoutOrder)
	local card = create("Frame", {
		Name = command.Title:gsub("%W+", "") .. "Card",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.PanelSoft,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, -2, 0, 0),
		Parent = commandScroll,
	})
	addCorner(card, 14)
	addStroke(card, COLORS.BorderSoft, 1, 0.25)
	addPadding(card, 14, 12, 14, 12)

	local layout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = card,
	})

	local headerRow = create("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = card,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -136, 1, 0),
		Text = command.Title,
		TextColor3 = COLORS.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = headerRow,
	})

	local categoryTag = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(14, 34, 63),
		BorderSizePixel = 0,
		Font = FONT,
		Position = UDim2.new(1, 0, 0, 1),
		Size = UDim2.fromOffset(126, 22),
		Text = command.Section,
		TextColor3 = COLORS.Cyan,
		TextSize = 10,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = headerRow,
	})
	addCorner(categoryTag, 10)

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 34),
		Text = command.Help,
		TextColor3 = COLORS.Muted,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	local values = {}
	local nextLayoutOrder = 3
	for _, control in ipairs(command.Controls or {}) do
		local holder = create("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = nextLayoutOrder,
			Size = UDim2.fromScale(1, 0),
			Parent = card,
		})
		nextLayoutOrder += 1
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = holder,
		})

		if control.Type == "select" then
			makeSelector(holder, control, values)
		elseif control.Type == "number" then
			makeNumberInput(holder, control, values)
		end
	end

	local runButton = create("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.Gold,
		BorderSizePixel = 0,
		Font = FONT,
		LayoutOrder = nextLayoutOrder,
		Size = UDim2.fromOffset(150, 36),
		Text = "Run",
		TextColor3 = Color3.fromRGB(31, 24, 10),
		TextSize = 14,
		Parent = card,
	})
	addCorner(runButton, 10)
	addStroke(runButton, COLORS.GoldDark, 1, 0.08)

	runButton.Activated:Connect(function()
		if not refreshTesterStatus() then
			gui.Enabled = false
			setStatus("Equip the Tester title or get tester access first.", STATUS_ERROR)
			return
		end

		local ok, message = validateControlValues(command, values)
		if not ok then
			setStatus(message, STATUS_ERROR)
			return
		end

		local commandText = command.Build(values)
		if type(commandText) ~= "string" or trimText(commandText) == "" then
			setStatus("Command is not ready.", STATUS_ERROR)
			return
		end

		lastSentAt = os.clock()
		testerCommandRequestEvent = findRemote("TesterCommandRequest", "RemoteEvent") or testerCommandRequestEvent
		if not (testerCommandRequestEvent and testerCommandRequestEvent:IsA("RemoteEvent")) then
			setStatus("Tester command remote is not ready yet. Try again in a moment.", STATUS_ERROR)
			return
		end

		testerCommandRequestEvent:FireServer(commandText)
		setStatus("Waiting for server confirmation...", COLORS.Muted)
	end)

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		card.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y + 24)
	end)
end

local function updateCommandCanvas()
	commandScroll.CanvasSize = UDim2.fromOffset(0, commandLayout.AbsoluteContentSize.Y + 28)
end
commandLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCommandCanvas)

local function commandMatchesFilters(command)
	if selectedCategory ~= "All" and command.Section ~= selectedCategory then
		return false
	end

	local query = normalizeText(searchQuery)
	if query == "" then
		return true
	end

	return string.find(tostring(command.SearchText or ""), query, 1, true) ~= nil
end

local function clearCommandList()
	for _, child in ipairs(commandScroll:GetChildren()) do
		if child ~= commandLayout and child ~= commandPadding then
			child:Destroy()
		end
	end
end

local function makeEmptyState()
	local empty = create("Frame", {
		BackgroundColor3 = COLORS.PanelSoft,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Size = UDim2.new(1, -2, 0, 88),
		Parent = commandScroll,
	})
	addCorner(empty, 14)
	addStroke(empty, COLORS.BorderSoft, 1, 0.25)

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		Position = UDim2.fromOffset(14, 12),
		Size = UDim2.new(1, -28, 0, 24),
		Text = "No tester commands found",
		TextColor3 = COLORS.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = empty,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Position = UDim2.fromOffset(14, 40),
		Size = UDim2.new(1, -28, 0, 34),
		Text = "Try All, a different category, or a shorter search.",
		TextColor3 = COLORS.Muted,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = empty,
	})
end

renderCommandList = function()
	clearCommandList()
	updateCategoryButtonStyles()
	commandScroll.CanvasPosition = Vector2.new(0, 0)

	local order = 0
	for _, command in ipairs(COMMANDS) do
		if commandMatchesFilters(command) then
			order += 1
			makeCommandCard(command, order)
		end
	end

	if order == 0 then
		makeEmptyState()
	end

	task.defer(updateCommandCanvas)
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchQuery = cleanSingleLine(searchBox.Text, 120)
	if renderCommandList then
		renderCommandList()
	end
end)

renderCommandList()

local function updateCanvas()
	local viewport = outerScroll.AbsoluteSize
	local scale = getPanelScale(viewport)

	mainScale.Scale = scale
	shadowScale.Scale = scale
	commandScroll.ScrollBarThickness = scale < 1 and 4 or 7
	commandPadding.PaddingLeft = UDim.new(0, scale < 0.7 and 10 or 14)
	commandPadding.PaddingRight = UDim.new(0, scale < 0.7 and 10 or 14)

	main.Position = UDim2.fromScale(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, math.floor(10 * scale), 0.5, math.floor(12 * scale))
end

outerScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas)
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateCanvas)
end
task.defer(updateCanvas)

local function setPanelOpen(open)
	gui.Enabled = open == true
	dim.Visible = open == true
	outerScroll.Visible = open == true
	main.Visible = open == true
	shadow.Visible = open == true
	if open == true then
		task.defer(updateCanvas)
	end
end

closeButton.Activated:Connect(function()
	setPanelOpen(false)
end)

local adminCommandFeedbackConnected = false
local function bindAdminCommandFeedbackEvent()
	if adminCommandFeedbackConnected then
		return
	end

	adminCommandFeedbackEvent = findRemote("AdminCommandFeedback", "RemoteEvent") or adminCommandFeedbackEvent
	if not (adminCommandFeedbackEvent and adminCommandFeedbackEvent:IsA("RemoteEvent")) then
		return
	end

	adminCommandFeedbackConnected = true
	adminCommandFeedbackEvent.OnClientEvent:Connect(function(payload)
		if not gui.Enabled and (os.clock() - lastSentAt) > 8 then
			return
		end

		if typeof(payload) ~= "table" then
			setStatus("Server confirmed tester command.", STATUS_OK)
			return
		end

		local status = tostring(payload.Status or payload.status or "success")
		local message = cleanSingleLine(payload.Message or payload.message or "", 180)
		if message == "" then
			local displayName = cleanSingleLine(payload.DisplayName or payload.CommandName or "Tester command", 60)
			local detail = cleanSingleLine(payload.Detail or payload.detail or "", 110)
			message = if detail ~= "" then displayName .. ": " .. detail else displayName .. " confirmed."
		end

		setStatus(message, getFeedbackColor(status))
	end)
end

bindAdminCommandFeedbackEvent()

ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "AdminCommandFeedback" then
		task.defer(bindAdminCommandFeedbackEvent)
	end
end)

local lastToggleRequestedAt = 0
local function requestTesterPanelToggle()
	local now = os.clock()
	if now - lastToggleRequestedAt < 0.08 then
		return
	end
	lastToggleRequestedAt = now

	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end

	if not refreshTesterStatus() then
		setPanelOpen(false)
		return
	end

	local nextOpen = not gui.Enabled
	setPanelOpen(nextOpen)
end

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.F8 then
		return
	end

	requestTesterPanelToggle()
end)
