local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Responsive = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Responsive"))
local HudLayout = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("HudLayout"))

local WARNING_THROTTLE_SECONDS = 5
local warningTimes = {}

local function warnThrottled(key, message)
	local now = os.clock()
	local previous = warningTimes[key]
	if previous and now - previous < WARNING_THROTTLE_SECONDS then
		return
	end

	warningTimes[key] = now
	warn("[AdminPanel] " .. tostring(message))
end

local function safeWait(parent, name)
	local obj = parent:WaitForChild(name, 15)
	if not obj then
		error(("Missing %s in %s"):format(name, parent:GetFullName()))
	end
	return obj
end

local function waitForOptionalChild(parent, name, className, timeoutSeconds)
	local obj = parent:FindFirstChild(name) or parent:WaitForChild(name, timeoutSeconds or 15)
	if not obj then
		warnThrottled("missing_" .. name, ("%s is unavailable in %s."):format(name, parent:GetFullName()))
		return nil
	end
	if className and not obj:IsA(className) then
		warnThrottled(
			"wrong_class_" .. name,
			("%s exists in %s but is a %s, expected %s."):format(name, parent:GetFullName(), obj.ClassName, className)
		)
		return nil
	end
	return obj
end

local function trimText(text)
	return tostring(text or ""):match("^%s*(.-)%s*$") or ""
end

local function normalizeText(text)
	return string.lower(trimText(text))
end

local function cleanSingleLine(text, limit)
	local value = trimText(text):gsub("\r", ""):gsub("\n", " ")
	if limit and #value > limit then
		value = value:sub(1, limit)
	end
	return value
end

local function inputValue(values, key, fallback)
	local value = cleanSingleLine(values[key], 120)
	if value == "" then
		return fallback or ""
	end
	return value
end

local function numberValue(values, key, fallback)
	local raw = inputValue(values, key, tostring(fallback or ""))
	local parsed = tonumber(raw)
	if not parsed then
		return fallback
	end
	return parsed
end

local function getOrCreateFrame(parent, name)
	local frame = parent:FindFirstChild(name)
	if frame and frame:IsA("Frame") then
		return frame
	end
	if frame then
		frame:Destroy()
	end

	frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function getOrCreateTextLabel(parent, name)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		return label
	end
	if label then
		label:Destroy()
	end

	label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(245, 249, 255)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.25
	label.TextSize = 20
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function getOrCreateImageLabel(parent, name)
	local image = parent:FindFirstChild(name)
	if image and image:IsA("ImageLabel") then
		return image
	end
	if image then
		image:Destroy()
	end

	image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Parent = parent
	return image
end

local function ensureAnnouncementTemplate(playerGui)
	local hud = playerGui:FindFirstChild("HUD") or playerGui:WaitForChild("HUD", 15)
	if not (hud and hud:IsA("ScreenGui")) then
		warnThrottled("missing_hud_fallback", "PlayerGui.HUD was unavailable; using a local admin announcement fallback.")
		hud = playerGui:FindFirstChild("AdminAnnouncementFallback")
		if not (hud and hud:IsA("ScreenGui")) then
			if hud then
				hud:Destroy()
			end
			hud = Instance.new("ScreenGui")
			hud.Name = "AdminAnnouncementFallback"
			hud.DisplayOrder = 10050
			hud.IgnoreGuiInset = true
			hud.ResetOnSpawn = false
			hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			hud.Parent = playerGui
		end
	end

	local adminInfo = hud:FindFirstChild("AdminInfo")
	if not (adminInfo and adminInfo:IsA("Frame")) then
		warnThrottled("missing_admin_info_fallback", "HUD.AdminInfo was unavailable; creating a local admin announcement host.")
		adminInfo = getOrCreateFrame(hud, "AdminInfo")
	end
	adminInfo.Visible = true
	adminInfo.Size = UDim2.new(1, 0, 0, 180)
	adminInfo.Position = UDim2.fromOffset(0, 16)
	adminInfo.ClipsDescendants = false

	local announcementTemplate = adminInfo:FindFirstChild("AnnTemplate")
	if not (announcementTemplate and announcementTemplate:IsA("Frame")) then
		warnThrottled("missing_ann_template_fallback", "HUD.AdminInfo.AnnTemplate was unavailable; creating a local fallback template.")
		announcementTemplate = getOrCreateFrame(adminInfo, "AnnTemplate")
	end
	announcementTemplate.Visible = false
	announcementTemplate.Size = UDim2.fromOffset(460, 80)
	announcementTemplate.Position = UDim2.fromOffset(16, 0)
	announcementTemplate.BackgroundTransparency = 0.08
	announcementTemplate.BackgroundColor3 = Color3.fromRGB(10, 21, 43)
	announcementTemplate.ClipsDescendants = false

	local textLB = getOrCreateTextLabel(announcementTemplate, "TextLB")
	textLB.Position = UDim2.fromOffset(84, 16)
	textLB.Size = UDim2.new(1, -104, 0, 44)
	textLB.Text = ""
	textLB.TextWrapped = true
	textLB.ZIndex = math.max(textLB.ZIndex, 2)

	local shadow = getOrCreateTextLabel(textLB, "Shadow")
	shadow.Position = UDim2.fromOffset(2, 2)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Text = ""
	shadow.TextColor3 = Color3.fromRGB(0, 0, 0)
	shadow.TextTransparency = 0.25
	shadow.ZIndex = math.max(textLB.ZIndex - 1, 1)

	local pfp = getOrCreateImageLabel(announcementTemplate, "PFP")
	pfp.Position = UDim2.fromOffset(14, 12)
	pfp.Size = UDim2.fromOffset(56, 56)
	pfp.ZIndex = math.max(pfp.ZIndex, 2)

	return announcementTemplate
end

local adminStatusFunction = waitForOptionalChild(ReplicatedStorage, "AdminStatusRequest", "RemoteFunction", 15)
local isAdmin = false
if adminStatusFunction and adminStatusFunction:IsA("RemoteFunction") then
	local ok, result = pcall(function()
		return adminStatusFunction:InvokeServer()
	end)
	isAdmin = ok and result == true
	if not ok then
		warnThrottled("admin_status_failed", "AdminStatusRequest failed: " .. tostring(result))
	end
end

local broadcastEvent = waitForOptionalChild(ReplicatedStorage, "AdminAnnouncementBroadcast", "RemoteEvent", 15)

local playerGui = safeWait(player, "PlayerGui")
local framesFolder = playerGui:FindFirstChild("Frames")
local template = ensureAnnouncementTemplate(playerGui)

template.Visible = false

local oldAdminPanel = framesFolder and framesFolder:FindFirstChild("AdminPanel")
if oldAdminPanel and oldAdminPanel:IsA("GuiObject") then
	oldAdminPanel.Visible = false
end

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
	Blue = Color3.fromRGB(62, 153, 255),
	Green = Color3.fromRGB(77, 214, 147),
	Red = Color3.fromRGB(238, 78, 82),
	RedDark = Color3.fromRGB(125, 28, 40),
	Black = Color3.fromRGB(0, 0, 0),
}

local FONT = Enum.Font.GothamBold
local BODY_FONT = Enum.Font.Gotham
local PANEL_WIDTH = 1040
local PANEL_HEIGHT = 660
local PANEL_PADDING = 28
local MOBILE_PANEL_SCALE_CAP = 0.78

local function getDashboardScale(viewport)
	local availableX = math.max(360, viewport.X - (PANEL_PADDING * 2))
	local availableY = math.max(260, viewport.Y - (PANEL_PADDING * 2))
	local scale = math.min(availableX / PANEL_WIDTH, availableY / PANEL_HEIGHT, 1)

	if Responsive.isCompact(viewport) then
		scale = math.min(scale, MOBILE_PANEL_SCALE_CAP)
	end

	return math.clamp(scale, 0.55, 1)
end

local CATEGORIES = {
	"All",
	"Devil Fruits",
	"Currency",
	"Player Stats",
	"Access",
	"Boosts",
	"Progression",
	"Bounty",
	"Resources",
	"Spawning",
	"Chests",
	"Ship",
	"Server Ops",
	"Inventory",
	"Gifts",
	"Diagnostics",
	"Danger Zone",
	"Panel Actions",
}

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

local function setButtonStyle(button, active, dangerous)
	if dangerous then
		button.BackgroundColor3 = active and COLORS.Red or COLORS.RedDark
		button.TextColor3 = COLORS.Text
	elseif active then
		button.BackgroundColor3 = COLORS.Gold
		button.TextColor3 = Color3.fromRGB(32, 23, 8)
	else
		button.BackgroundColor3 = COLORS.PanelRaised
		button.TextColor3 = COLORS.Text
	end
end

local function pulseButton(button)
	local scale = button:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = button
	end
	scale.Scale = 1
	TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.04 }):Play()
	task.delay(0.1, function()
		if scale and scale.Parent then
			TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
end

local function makeCommandText(command)
	return tostring(command.syntax or "")
end

local COMMANDS = {
	{
		id = "fruit_grant",
		category = "Devil Fruits",
		marker = "DF",
		name = "Grant Fruit",
		syntax = "/fruit <fruitAlias>",
		description = "Grant a Devil Fruit reward through the existing reward flow.",
		example = "/fruit mera",
		inputs = {
			{ key = "fruit", label = "Fruit alias", placeholder = "mera, tori, gomu..." },
		},
		build = function(values)
			return "/fruit " .. inputValue(values, "fruit", "<fruitAlias>")
		end,
	},
	{
		id = "fruit_all",
		category = "Devil Fruits",
		marker = "DF",
		name = "Grant All Fruits",
		syntax = "/fruit all",
		description = "Grant every configured Devil Fruit reward.",
		example = "/fruit all",
		build = function()
			return "/fruit all"
		end,
	},
	{
		id = "fruit_equip",
		category = "Devil Fruits",
		marker = "EQ",
		name = "Equip Fruit",
		syntax = "/fruit equip <fruitAlias>",
		description = "Directly equip a Devil Fruit and persist it.",
		example = "/fruit equip tori",
		inputs = {
			{ key = "fruit", label = "Fruit alias", placeholder = "tori" },
		},
		build = function(values)
			return "/fruit equip " .. inputValue(values, "fruit", "<fruitAlias>")
		end,
	},
	{
		id = "fruit_clear",
		category = "Devil Fruits",
		marker = "CL",
		name = "Clear Equipped Fruit",
		syntax = "/fruit clear | /fruit none | /fruit remove",
		description = "Clear the currently equipped Devil Fruit.",
		example = "/fruit clear",
		build = function()
			return "/fruit clear"
		end,
	},
	{
		id = "fruit_nocd",
		category = "Devil Fruits",
		marker = "CD",
		name = "Fruit Cooldown Bypass",
		syntax = "/fruit nocd on|off",
		description = "Toggle Devil Fruit cooldown bypass for yourself.",
		example = "/fruit nocd on",
		inputs = {
			{ key = "state", label = "State", placeholder = "on or off", default = "on" },
		},
		build = function(values)
			return "/fruit nocd " .. inputValue(values, "state", "on")
		end,
	},
	{
		id = "ability_hitboxes",
		category = "Devil Fruits",
		marker = "HB",
		name = "Hitboxes",
		syntax = "/hitbox on|off",
		description = "Toggle local client-side hitbox visuals for ability effects and hazards.",
		example = "/hitbox on",
		inputs = {
			{ key = "state", label = "State", placeholder = "on or off", default = "on" },
		},
		build = function(values)
			return "/hitbox " .. inputValue(values, "state", "on")
		end,
	},
	{
		id = "admin_invincible",
		category = "Access",
		marker = "IV",
		name = "Invincible",
		syntax = "/invincible on|off|toggle",
		description = "Toggle admin-only immunity to hazards and disruptive hit effects.",
		example = "/invincible on",
		inputs = {
			{ key = "state", label = "State", placeholder = "on, off, or toggle", default = "on" },
		},
		build = function(values)
			return "/invincible " .. inputValue(values, "state", "on")
		end,
	},
	{
		id = "admin_enable",
		category = "Access",
		marker = "AD",
		name = "Admin On",
		syntax = "/admin true",
		description = "Enable active Admin status for SuperAdmin testing.",
		example = "/admin true",
		build = function()
			return "/admin true"
		end,
	},
	{
		id = "admin_disable",
		category = "Access",
		marker = "AD",
		name = "Admin Off",
		syntax = "/admin false",
		description = "Disable active Admin status while keeping SuperAdmin command authority.",
		example = "/admin false",
		build = function()
			return "/admin false"
		end,
	},
	{
		id = "vip_test_on",
		category = "Access",
		marker = "VIP",
		name = "VIP Test On",
		syntax = "/vip true",
		description = "Force effective VIP on for this server session without changing Marketplace ownership.",
		example = "/vip true",
		build = function()
			return "/vip true"
		end,
	},
	{
		id = "vip_test_off",
		category = "Access",
		marker = "VIP",
		name = "VIP Test Off",
		syntax = "/vip false",
		description = "Force effective VIP off for this server session to test non-VIP access.",
		example = "/vip false",
		build = function()
			return "/vip false"
		end,
	},
	{
		id = "vip_test_state",
		category = "Access",
		marker = "VIP",
		name = "VIP Test State",
		syntax = "/vip state",
		description = "Show current effective VIP state, real VIP state, and override source.",
		example = "/vip state",
		build = function()
			return "/vip state"
		end,
	},
	{
		id = "money_delta",
		category = "Currency",
		marker = "BE",
		name = "Adjust Beli",
		syntax = "/beli <delta>",
		description = "Add or subtract Beli.",
		example = "/beli 1000",
		inputs = {
			{ key = "amount", label = "Delta", placeholder = "1000 or -500" },
		},
		build = function(values)
			return "/beli " .. inputValue(values, "amount", "<delta>")
		end,
	},
	{
		id = "money_set",
		category = "Currency",
		marker = "BE",
		name = "Set Beli",
		syntax = "/beli set <amount>",
		description = "Set Beli to an exact amount.",
		example = "/beli set 25000",
		inputs = {
			{ key = "amount", label = "Amount", placeholder = "25000" },
		},
		build = function(values)
			return "/beli set " .. inputValue(values, "amount", "<amount>")
		end,
	},
	{
		id = "money_clear",
		category = "Currency",
		marker = "BE",
		name = "Clear Beli",
		syntax = "/beli clear | /beli reset | /beli zero",
		description = "Set Beli to zero.",
		example = "/beli clear",
		build = function()
			return "/beli clear"
		end,
	},
	{
		id = "speed_set",
		category = "Player Stats",
		marker = "SP",
		name = "Set Speed",
		syntax = "/speed <amount> or /setspeed <amount>",
		description = "Set the player's Speed stat.",
		example = "/speed 3",
		inputs = {
			{ key = "amount", label = "Speed", placeholder = "3" },
		},
		build = function(values)
			return "/speed " .. inputValue(values, "amount", "<amount>")
		end,
	},
	{
		id = "speed_set_explicit",
		category = "Player Stats",
		marker = "SP",
		name = "Set Speed Explicitly",
		syntax = "/speed set <amount>",
		description = "Set the player's Speed stat with explicit syntax.",
		example = "/speed set 5",
		inputs = {
			{ key = "amount", label = "Speed", placeholder = "5" },
		},
		build = function(values)
			return "/speed set " .. inputValue(values, "amount", "<amount>")
		end,
	},
	{
		id = "speed_reset",
		category = "Player Stats",
		marker = "SP",
		name = "Reset Speed",
		syntax = "/speed reset | /speed clear | /speed default",
		description = "Restore Speed to the profile default.",
		example = "/speed reset",
		build = function()
			return "/speed reset"
		end,
	},
	{
		id = "boost",
		category = "Boosts",
		marker = "x2",
		name = "Grant Boost",
		syntax = "/boost <boostType> [minutes]",
		description = "Grant a timed boost. Use 2xbeli/x2beli for Beli boosts, or speed/walkspeed for movement boosts.",
		example = "/boost 2xbeli 5",
		inputs = {
			{ key = "boost", label = "Boost type", placeholder = "2xbeli", default = "2xbeli" },
			{ key = "minutes", label = "Minutes", placeholder = "5", default = "5" },
		},
		build = function(values)
			return "/boost " .. inputValue(values, "boost", "2xbeli") .. " " .. inputValue(values, "minutes", "5")
		end,
	},
	{
		id = "rebirth_set",
		category = "Progression",
		marker = "RB",
		name = "Set Rebirths",
		syntax = "/rebirth set <amount>",
		description = "Set Rebirths to an exact amount.",
		example = "/rebirth set 10",
		inputs = {
			{ key = "amount", label = "Amount", placeholder = "10" },
		},
		build = function(values)
			return "/rebirth set " .. inputValue(values, "amount", "<amount>")
		end,
	},
	{
		id = "rebirth_add",
		category = "Progression",
		marker = "RB",
		name = "Add Rebirths",
		syntax = "/rebirth add <amount>",
		description = "Add Rebirths to the current total.",
		example = "/rebirth add 1",
		inputs = {
			{ key = "amount", label = "Amount", placeholder = "1" },
		},
		build = function(values)
			return "/rebirth add " .. inputValue(values, "amount", "<amount>")
		end,
	},
	{
		id = "rebirth_reset",
		category = "Progression",
		marker = "RB",
		name = "Reset Rebirths",
		syntax = "/rebirth reset | /rebirth clear | /rebirth zero",
		description = "Reset Rebirths to zero.",
		example = "/rebirth reset",
		build = function()
			return "/rebirth reset"
		end,
	},
	{
		id = "bounty_set",
		category = "Bounty",
		marker = "BO",
		name = "Set Bounty",
		syntax = "/bounty set <amount>",
		description = "Set lifetime extraction bounty.",
		example = "/bounty set 5000",
		inputs = {
			{ key = "amount", label = "Amount", placeholder = "5000" },
		},
		build = function(values)
			return "/bounty set " .. inputValue(values, "amount", "<amount>")
		end,
	},
	{
		id = "bounty_add",
		category = "Bounty",
		marker = "BO",
		name = "Add Bounty",
		syntax = "/bounty add <amount>",
		description = "Add to lifetime extraction bounty.",
		example = "/bounty add 250",
		inputs = {
			{ key = "amount", label = "Amount", placeholder = "250" },
		},
		build = function(values)
			return "/bounty add " .. inputValue(values, "amount", "<amount>")
		end,
	},
	{
		id = "bounty_reset",
		category = "Bounty",
		marker = "BO",
		name = "Reset Bounty",
		syntax = "/bounty reset | /bounty clear | /bounty zero",
		description = "Reset lifetime extraction bounty.",
		example = "/bounty reset",
		build = function()
			return "/bounty reset"
		end,
	},
	{
		id = "bounty_debug",
		category = "Bounty",
		marker = "BO",
		name = "Bounty Debug",
		syntax = "/bounty debug | /bounty info | /bounty status",
		description = "Refresh and print bounty breakdown information.",
		example = "/bounty debug",
		build = function()
			return "/bounty debug"
		end,
	},
	{
		id = "give_resource",
		category = "Resources",
		marker = "RS",
		name = "Give Resource",
		syntax = "/give <resource> <amount>",
		description = "Grant Beli, configured materials, or configured food resources.",
		example = "/give timber 25",
		inputs = {
			{ key = "resource", label = "Resource", placeholder = "beli, timber, iron..." },
			{ key = "amount", label = "Amount", placeholder = "25" },
		},
		build = function(values)
			return "/give " .. inputValue(values, "resource", "<resource>") .. " " .. inputValue(values, "amount", "<amount>")
		end,
	},
	{
		id = "spawn_chest",
		category = "Spawning",
		marker = "SP",
		name = "Spawn Chest",
		syntax = "/spawn chest",
		description = "Spawn a shared chest reward in front of you.",
		example = "/spawn chest",
		build = function()
			return "/spawn chest"
		end,
	},
	{
		id = "spawn_crew",
		category = "Spawning",
		marker = "SP",
		name = "Spawn Crew",
		syntax = "/spawn crew",
		description = "Start a live crew reward run.",
		example = "/spawn crew",
		build = function()
			return "/spawn crew"
		end,
	},
	{
		id = "hazards_toggle",
		category = "Spawning",
		marker = "HZ",
		name = "Hazards",
		syntax = "/hazards true|false",
		description = "Enable or disable corridor hazard spawning and clear active hazards when disabled.",
		example = "/hazards false",
		inputs = {
			{ key = "state", label = "State", placeholder = "true or false", default = "false" },
		},
		build = function(values)
			return "/hazards " .. inputValue(values, "state", "false")
		end,
	},
	{
		id = "chest_grant",
		category = "Chests",
		marker = "CH",
		name = "Grant Chest",
		syntax = "/chest <tier> [amount]",
		description = "Grant standard extraction chest tools. Known tiers are wood, wooden, iron, and gold.",
		example = "/chest gold 2",
		inputs = {
			{ key = "tier", label = "Chest tier", placeholder = "wood, iron, gold" },
			{ key = "amount", label = "Amount", placeholder = "1", default = "1" },
		},
		build = function(values)
			local amount = inputValue(values, "amount", "")
			local command = "/chest " .. inputValue(values, "tier", "<tier>")
			if amount ~= "" then
				command ..= " " .. amount
			end
			return command
		end,
	},
	{
		id = "chestrush_start",
		category = "Server Ops",
		marker = "CR",
		name = "Chest Rush Start",
		syntax = "/chestrush start",
		description = "Force-start Chest Rush across the active server state.",
		example = "/chestrush start",
		build = function()
			return "/chestrush start"
		end,
	},
	{
		id = "chestrush_stop",
		category = "Server Ops",
		marker = "CR",
		name = "Chest Rush Stop",
		syntax = "/chestrush stop",
		description = "Stop a forced Chest Rush and return to scheduled state.",
		example = "/chestrush stop",
		build = function()
			return "/chestrush stop"
		end,
	},
	{
		id = "chestrush_status",
		category = "Server Ops",
		marker = "CR",
		name = "Chest Rush Status",
		syntax = "/chestrush status",
		description = "Print Chest Rush active, forced, scheduled, and remaining-time status.",
		example = "/chestrush status",
		build = function()
			return "/chestrush status"
		end,
	},
	{
		id = "ship_reset",
		category = "Ship",
		marker = "SH",
		name = "Reset Ship",
		syntax = "/shipreset",
		description = "Reset your ship progression.",
		example = "/shipreset",
		build = function()
			return "/shipreset"
		end,
	},
	{
		id = "server_restart_10",
		category = "Server Ops",
		marker = "RS",
		name = "Restart In 10m",
		syntax = "/restart 10",
		description = "Schedule a soft restart for all servers in 10 minutes.",
		example = "/restart 10",
		build = function()
			return "/restart 10"
		end,
	},
	{
		id = "server_restart_5",
		category = "Server Ops",
		marker = "RS",
		name = "Restart In 5m",
		syntax = "/restart 5",
		description = "Schedule a soft restart for all servers in 5 minutes.",
		example = "/restart 5",
		build = function()
			return "/restart 5"
		end,
	},
	{
		id = "server_restart_1",
		category = "Server Ops",
		marker = "RS",
		name = "Restart In 1m",
		syntax = "/restart 1",
		description = "Schedule a soft restart for all servers in 1 minute.",
		example = "/restart 1",
		build = function()
			return "/restart 1"
		end,
	},
	{
		id = "server_restart_cancel",
		category = "Server Ops",
		marker = "RS",
		name = "Cancel Restart",
		syntax = "/restart cancel",
		description = "Cancel the active soft restart across servers.",
		example = "/restart cancel",
		build = function()
			return "/restart cancel"
		end,
	},
	{
		id = "clear_inventory",
		category = "Inventory",
		marker = "IN",
		name = "Clear Inventory",
		syntax = "/clear inv | /clear inventory",
		description = "Clear inventory-related profile data and refresh runtime inventory state.",
		example = "/clear inv",
		build = function()
			return "/clear inv"
		end,
	},
	{
		id = "tutorial_reset",
		category = "Progression",
		marker = "TU",
		name = "Reset Tutorial",
		syntax = "/tutorial reset",
		description = "Reset your tutorial flags and tutorial-only entities so the first-time tutorial can be tested again.",
		example = "/tutorial reset",
		build = function()
			return "/tutorial reset"
		end,
	},
	{
		id = "gifts_reset",
		category = "Gifts",
		marker = "GF",
		name = "Reset Gifts",
		syntax = "/gifts reset [playerName]",
		description = "Reset Gifts claims for yourself or an online target.",
		example = "/gifts reset YonkoKaio",
		inputs = {
			{ key = "target", label = "Player name or UserId", placeholder = "optional" },
		},
		build = function(values)
			local target = inputValue(values, "target", "")
			return target ~= "" and ("/gifts reset " .. target) or "/gifts reset"
		end,
	},
	{
		id = "gifts_clear",
		category = "Gifts",
		marker = "GF",
		name = "Clear Gifts",
		syntax = "/gifts clear [playerName]",
		description = "Clear Gifts claims for yourself or an online target.",
		example = "/gifts clear",
		inputs = {
			{ key = "target", label = "Player name or UserId", placeholder = "optional" },
		},
		build = function(values)
			local target = inputValue(values, "target", "")
			return target ~= "" and ("/gifts clear " .. target) or "/gifts clear"
		end,
	},
	{
		id = "giftreset",
		category = "Gifts",
		marker = "GF",
		name = "Gift Reset Alias",
		syntax = "/giftreset [playerName]",
		description = "Alias for resetting Gifts claims.",
		example = "/giftreset YonkoKaio",
		inputs = {
			{ key = "target", label = "Player name or UserId", placeholder = "optional" },
		},
		build = function(values)
			local target = inputValue(values, "target", "")
			return target ~= "" and ("/giftreset " .. target) or "/giftreset"
		end,
	},
	{
		id = "data_diag",
		category = "Diagnostics",
		marker = "DG",
		name = "Data Diagnostics",
		syntax = "/datadiag",
		description = "Print active data environment diagnostics for this server.",
		example = "/datadiag",
		build = function()
			return "/datadiag"
		end,
	},
	{
		id = "data_recover_dryrun",
		category = "Diagnostics",
		marker = "DR",
		name = "Data Recovery Dry Run",
		syntax = "/datarecover mode=dryrun userId=<id> source=<store> target=<store>",
		description = "Compare a source and target player profile without restoring data.",
		example = "/datarecover mode=dryrun userId=123456 source=production target=production",
		inputs = {
			{ key = "userId", label = "UserId", placeholder = "123456" },
			{ key = "source", label = "Source store", placeholder = "production", default = "production" },
			{ key = "target", label = "Target store", placeholder = "production", default = "production" },
		},
		build = function(values)
			return "/datarecover mode=dryrun userId="
				.. inputValue(values, "userId", "<id>")
				.. " source="
				.. inputValue(values, "source", "production")
				.. " target="
				.. inputValue(values, "target", "production")
		end,
	},
	{
		id = "data_recover_restore",
		category = "Danger Zone",
		marker = "DR",
		name = "Data Recovery Restore",
		syntax = "/datarecover mode=restore userId=<id> source=<store> target=<store> confirm",
		description = "Restore one player from a source store into a target store. The server requires confirm for the restore step.",
		example = "/datarecover mode=restore userId=123456 source=historical-fallback target=production confirm",
		dangerous = true,
		inputs = {
			{ key = "userId", label = "UserId", placeholder = "123456" },
			{ key = "source", label = "Source store", placeholder = "historical-fallback", default = "historical-fallback" },
			{ key = "target", label = "Target store", placeholder = "production", default = "production" },
		},
		build = function(values, confirm)
			local command = "/datarecover mode=restore userId="
				.. inputValue(values, "userId", "<id>")
				.. " source="
				.. inputValue(values, "source", "historical-fallback")
				.. " target="
				.. inputValue(values, "target", "production")
			return confirm and (command .. " confirm") or command
		end,
	},
	{
		id = "crewcanary_status",
		category = "Diagnostics",
		marker = "CC",
		name = "Crew Canary Status",
		syntax = "/crewcanary status",
		description = "Print crew canonical read-gate canary status.",
		example = "/crewcanary status",
		build = function()
			return "/crewcanary status"
		end,
	},
	{
		id = "crewcanary_advanced",
		category = "Diagnostics",
		marker = "CC",
		name = "Crew Canary Advanced",
		syntax = "/crewcanary <args>",
		description = "Send custom crew canary debug arguments through the existing admin command parser.",
		example = "/crewcanary status",
		inputs = {
			{ key = "args", label = "Arguments", placeholder = "status", default = "status" },
		},
		build = function(values)
			return "/crewcanary " .. inputValue(values, "args", "status")
		end,
	},
	{
		id = "wipeplayer",
		category = "Danger Zone",
		marker = "!!",
		name = "Wipe Player",
		syntax = "/wipeplayer <playerName|userId>",
		description = "Start the two-step permanent profile wipe flow. Run confirm within 20 seconds to complete it.",
		example = "/wipeplayer 123456",
		dangerous = true,
		inputs = {
			{ key = "target", label = "Player name or UserId", placeholder = "123456" },
		},
		build = function(values, confirm)
			local command = "/wipeplayer " .. inputValue(values, "target", "<playerName|userId>")
			return confirm and (command .. " confirm") or command
		end,
	},
	{
		id = "wipeplayer_confirm",
		category = "Danger Zone",
		marker = "!!",
		name = "Confirm Wipe Player",
		syntax = "/wipeplayer <playerName|userId> confirm",
		description = "Send the confirm command for an existing pending wipe.",
		example = "/wipeplayer 123456 confirm",
		dangerous = true,
		confirmOnly = true,
		inputs = {
			{ key = "target", label = "Player name or UserId", placeholder = "123456" },
		},
		build = function(values)
			return "/wipeplayer " .. inputValue(values, "target", "<playerName|userId>") .. " confirm"
		end,
	},
	{
		id = "resetprogress",
		category = "Danger Zone",
		marker = "!!",
		name = "Reset Progress",
		syntax = "/resetprogress <playerName|userId>",
		description = "Start the two-step permanent progress reset flow. Run confirm within 20 seconds to complete it.",
		example = "/resetprogress 123456",
		dangerous = true,
		inputs = {
			{ key = "target", label = "Player name or UserId", placeholder = "123456" },
		},
		build = function(values, confirm)
			local command = "/resetprogress " .. inputValue(values, "target", "<playerName|userId>")
			return confirm and (command .. " confirm") or command
		end,
	},
	{
		id = "resetprogress_confirm",
		category = "Danger Zone",
		marker = "!!",
		name = "Confirm Reset Progress",
		syntax = "/resetprogress <playerName|userId> confirm",
		description = "Send the confirm command for an existing pending progress reset.",
		example = "/resetprogress 123456 confirm",
		dangerous = true,
		confirmOnly = true,
		inputs = {
			{ key = "target", label = "Player name or UserId", placeholder = "123456" },
		},
		build = function(values)
			return "/resetprogress " .. inputValue(values, "target", "<playerName|userId>") .. " confirm"
		end,
	},
	{
		id = "panel_announcement",
		category = "Panel Actions",
		marker = "AN",
		name = "Announcement Broadcast",
		syntax = "Announcement broadcast",
		description = "Send a filtered announcement to all servers through the existing admin panel remote.",
		example = "Treasure storm begins in 60 seconds.",
		panelAction = "announcement",
		inputs = {
			{ key = "message", label = "Message", placeholder = "Announcement text" },
			{ key = "duration", label = "Duration seconds", placeholder = "10", default = "10" },
		},
		build = function(values)
			return ("Announcement: %s (%ss)"):format(inputValue(values, "message", "<message>"), inputValue(values, "duration", "10"))
		end,
	},
	{
		id = "panel_luck",
		category = "Panel Actions",
		marker = "LK",
		name = "Server Luck",
		syntax = "Server Luck: multiplier + duration",
		description = "Activate server luck through the existing server-validated admin panel remote.",
		example = "x8 for 600 seconds",
		panelAction = "serverLuck",
		inputs = {
			{ key = "multiplier", label = "Multiplier", placeholder = "8", default = "8" },
			{ key = "seconds", label = "Duration seconds", placeholder = "600", default = "600" },
		},
		build = function(values)
			return ("Server Luck: x%s for %ss"):format(inputValue(values, "multiplier", "8"), inputValue(values, "seconds", "600"))
		end,
	},
	{
		id = "panel_main_event",
		category = "Panel Actions",
		marker = "EV",
		name = "Main Event",
		syntax = "Main Event: event name + duration",
		description = "Start a main event through the existing server-validated admin panel remote.",
		example = "Comet for 600 seconds",
		panelAction = "mainEvent",
		inputs = {
			{ key = "eventName", label = "Event name", placeholder = "Comet", default = "Comet" },
			{ key = "seconds", label = "Duration seconds", placeholder = "600", default = "600" },
		},
		build = function(values)
			return ("Main Event: %s for %ss"):format(inputValue(values, "eventName", "Comet"), inputValue(values, "seconds", "600"))
		end,
	},
}

for _, command in ipairs(COMMANDS) do
	local parts = {}
	table.insert(parts, tostring(command.name or ""))
	table.insert(parts, tostring(command.syntax or ""))
	table.insert(parts, tostring(command.description or ""))
	table.insert(parts, tostring(command.example or ""))
	table.insert(parts, tostring(command.category or ""))
	table.insert(parts, tostring(command.marker or ""))
	for _, input in ipairs(command.inputs or {}) do
		table.insert(parts, tostring(input.label or ""))
		table.insert(parts, tostring(input.placeholder or ""))
	end
	command.searchText = normalizeText(table.concat(parts, " "))
end

local updateAdminLauncherVisibility = nil

local function buildDashboard()
	local requestEvent = safeWait(ReplicatedStorage, "AdminAnnouncementRequest")
	local luckRequestEvent = safeWait(ReplicatedStorage, "AdminLuckRequest")
	local mainEventRequestEvent = safeWait(ReplicatedStorage, "AdminMainEventRequest")
	local adminCommandRequestEvent = safeWait(ReplicatedStorage, "AdminCommandRequest")
	local adminCommandFeedbackEvent = safeWait(ReplicatedStorage, "AdminCommandFeedback")
	local adminRosterFunction = safeWait(ReplicatedStorage, "AdminRosterRequest")
	local adminTesterRoleFunction = safeWait(ReplicatedStorage, "AdminTesterRoleRequest")
	local adminConsoleActionFunction = safeWait(ReplicatedStorage, "AdminConsoleActionRequest")
	local adminCorridorRewardsFunction = safeWait(ReplicatedStorage, "AdminCorridorRewardsRequest")
	local adminRosterUpdatedEvent = safeWait(ReplicatedStorage, "AdminRosterUpdated")
	local currentTab = "Commands"
	local tabButtons = {}
	local setActiveTab

	local gui = create("ScreenGui", {
		Name = "GrandLineRushAdminDashboard",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 120,
		Enabled = false,
		Parent = playerGui,
	})

	local dim = create("Frame", {
		Name = "Dim",
		BackgroundColor3 = COLORS.Backdrop,
		BackgroundTransparency = 0.24,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = gui,
	})

	local outerScroll = create("ScrollingFrame", {
		Name = "AdminDashboardScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = COLORS.Gold,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		CanvasSize = UDim2.fromOffset(PANEL_WIDTH + PANEL_PADDING * 2, PANEL_HEIGHT + PANEL_PADDING * 2),
		Parent = dim,
	})

	local shadow = create("Frame", {
		Name = "Shadow",
		BackgroundColor3 = COLORS.Black,
		BackgroundTransparency = 0.58,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		Parent = outerScroll,
	})
	addCorner(shadow, 24)
	local shadowScale = create("UIScale", {
		Name = "ResponsiveScale",
		Scale = 1,
		Parent = shadow,
	})

	local main = create("Frame", {
		Name = "Panel",
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
		Parent = outerScroll,
	})
	addCorner(main, 22)
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
		Size = UDim2.new(1, -48, 0, 72),
		Parent = main,
	})

	local icon = create("Frame", {
		Name = "AdminIcon",
		BackgroundColor3 = COLORS.Gold,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromOffset(56, 56),
		Parent = header,
	})
	addCorner(icon, 16)
	addStroke(icon, COLORS.GoldDark, 2, 0)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "A",
		TextColor3 = Color3.fromRGB(31, 25, 11),
		TextSize = 28,
		Size = UDim2.fromScale(1, 1),
		Parent = icon,
	})

	create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "Grand Line Rush Admin",
		TextColor3 = COLORS.Text,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(72, 8),
		Size = UDim2.new(1, -730, 0, 32),
		Parent = header,
	})

	create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = "Command and moderation console",
		TextColor3 = COLORS.Muted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(73, 42),
		Size = UDim2.new(1, -730, 0, 22),
		Parent = header,
	})

	local closeButton = create("TextButton", {
		Name = "Close",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.RedDark,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "X",
		TextColor3 = COLORS.Text,
		TextSize = 22,
		Position = UDim2.new(1, -58, 0, 10),
		Size = UDim2.fromOffset(48, 48),
		Parent = header,
	})
	addCorner(closeButton, 14)
	addStroke(closeButton, COLORS.Red, 1, 0.05)

	local tabBar = create("Frame", {
		Name = "TopTabs",
		BackgroundColor3 = Color3.fromRGB(7, 17, 36),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -650, 0, 18),
		Size = UDim2.fromOffset(574, 38),
		Parent = header,
	})
	addCorner(tabBar, 14)
	addStroke(tabBar, COLORS.BorderSoft, 1, 0.2)
	addPadding(tabBar, 4, 4, 4, 4)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})

	tabButtons.Commands = create("TextButton", {
		Name = "CommandsTab",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.Gold,
		BorderSizePixel = 0,
		Font = FONT,
		LayoutOrder = 1,
		Text = "Commands",
		TextColor3 = Color3.fromRGB(31, 24, 10),
		TextSize = 11,
		Size = UDim2.fromOffset(112, 30),
		Parent = tabBar,
	})
	addCorner(tabButtons.Commands, 10)

	tabButtons.Admins = create("TextButton", {
		Name = "AdminsTab",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		LayoutOrder = 2,
		Text = "Staff",
		TextColor3 = COLORS.Text,
		TextSize = 11,
		Size = UDim2.fromOffset(78, 30),
		Parent = tabBar,
	})
	addCorner(tabButtons.Admins, 10)

	tabButtons.AllPlayers = create("TextButton", {
		Name = "AllPlayersTab",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		LayoutOrder = 3,
		Text = "Players",
		TextColor3 = COLORS.Text,
		TextSize = 11,
		Size = UDim2.fromOffset(92, 30),
		Parent = tabBar,
	})
	addCorner(tabButtons.AllPlayers, 10)

	tabButtons.Testers = create("TextButton", {
		Name = "TestersTab",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		LayoutOrder = 4,
		Text = "Testers",
		TextColor3 = COLORS.Text,
		TextSize = 11,
		Size = UDim2.fromOffset(86, 30),
		Parent = tabBar,
	})
	addCorner(tabButtons.Testers, 10)

	tabButtons.Audit = create("TextButton", {
		Name = "AuditTab",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		LayoutOrder = 5,
		Text = "Audit",
		TextColor3 = COLORS.Text,
		TextSize = 11,
		Size = UDim2.fromOffset(74, 30),
		Parent = tabBar,
	})
	addCorner(tabButtons.Audit, 10)

	tabButtons.Rewards = create("TextButton", {
		Name = "RewardsTab",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		LayoutOrder = 6,
		Text = "Rewards",
		TextColor3 = COLORS.Text,
		TextSize = 11,
		Size = UDim2.fromOffset(86, 30),
		Parent = tabBar,
	})
	addCorner(tabButtons.Rewards, 10)

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 102),
		Size = UDim2.new(1, -48, 1, -126),
		Parent = main,
	})

	local commandView = create("Frame", {
		Name = "CommandsView",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = content,
	})

	local rosterView = create("Frame", {
		Name = "AdminRosterView",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = content,
	})

	local rewardsView = create("Frame", {
		Name = "CorridorRewardsView",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = content,
	})

	local rewardsHeader = create("Frame", {
		Name = "RewardsHeader",
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 54),
		Parent = rewardsView,
	})
	addCorner(rewardsHeader, 18)
	addStroke(rewardsHeader, COLORS.BorderSoft, 1, 0.2)

	local rewardsTitleLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "Corridor Rewards",
		TextColor3 = COLORS.Text,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.fromOffset(300, 28),
		Parent = rewardsHeader,
	})

	local rewardsUpdatedLabel = create("TextLabel", {
		Name = "RewardsUpdated",
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = "Waiting for snapshot...",
		TextColor3 = COLORS.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(19, 34),
		Size = UDim2.new(1, -340, 0, 16),
		Parent = rewardsHeader,
	})

	local rewardsBackButton = create("TextButton", {
		Name = "BackRewards",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Back",
		TextColor3 = COLORS.Text,
		TextSize = 13,
		Position = UDim2.new(1, -238, 0, 10),
		Size = UDim2.fromOffset(100, 34),
		Visible = false,
		Parent = rewardsHeader,
	})
	addCorner(rewardsBackButton, 12)
	addStroke(rewardsBackButton, COLORS.BorderSoft, 1, 0.2)

	local rewardsRefreshButton = create("TextButton", {
		Name = "RefreshRewards",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Refresh",
		TextColor3 = COLORS.Text,
		TextSize = 13,
		Position = UDim2.new(1, -126, 0, 10),
		Size = UDim2.fromOffset(108, 34),
		Parent = rewardsHeader,
	})
	addCorner(rewardsRefreshButton, 12)
	addStroke(rewardsRefreshButton, COLORS.BorderSoft, 1, 0.2)

	local rewardsScroll = create("ScrollingFrame", {
		Name = "RewardsScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = COLORS.Gold,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 1, -66),
		Parent = rewardsView,
	})
	addPadding(rewardsScroll, 0, 0, 8, 10)
	local rewardsLayout = create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rewardsScroll,
	})

	local leftPane = create("Frame", {
		Name = "CommandBrowser",
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0, 392, 1, 0),
		Parent = commandView,
	})
	addCorner(leftPane, 18)
	addStroke(leftPane, COLORS.BorderSoft, 1, 0.2)
	addPadding(leftPane, 16, 16, 16, 16)

	local searchBox = create("TextBox", {
		Name = "Search",
		BackgroundColor3 = Color3.fromRGB(7, 17, 36),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = BODY_FONT,
		PlaceholderColor3 = COLORS.Faint,
		PlaceholderText = "Search commands, aliases, categories...",
		Text = "",
		TextColor3 = COLORS.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -32, 0, 42),
		Parent = leftPane,
	})
	addCorner(searchBox, 12)
	addStroke(searchBox, COLORS.BorderSoft, 1, 0.2)
	addPadding(searchBox, 14, 0, 14, 0)

	local categoryScroll = create("ScrollingFrame", {
		Name = "Categories",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = COLORS.Gold,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Position = UDim2.fromOffset(16, 70),
		Size = UDim2.new(1, -32, 0, 44),
		Parent = leftPane,
	})
	local categoryLayout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = categoryScroll,
	})

	local commandList = create("ScrollingFrame", {
		Name = "CommandList",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = COLORS.Gold,
		Position = UDim2.fromOffset(16, 128),
		Size = UDim2.new(1, -32, 1, -144),
		Parent = leftPane,
	})
	local commandLayout = create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = commandList,
	})

	local rightPane = create("Frame", {
		Name = "CommandDetails",
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(412, 0),
		Size = UDim2.new(1, -412, 1, 0),
		Parent = commandView,
	})
	addCorner(rightPane, 18)
	addStroke(rightPane, COLORS.BorderSoft, 1, 0.2)

	local rightHeader = create("Frame", {
		Name = "DetailsHeader",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -40, 0, 34),
		Parent = rightPane,
	})
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "Command Details",
		TextColor3 = COLORS.Text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 1),
		Parent = rightHeader,
	})

	local detailsScroll = create("ScrollingFrame", {
		Name = "DetailsScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = COLORS.Gold,
		Position = UDim2.fromOffset(20, 60),
		Size = UDim2.new(1, -40, 1, -174),
		Parent = rightPane,
	})
	addPadding(detailsScroll, 0, 0, 8, 0)
	local detailsLayout = create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = detailsScroll,
	})

	local previewFrame = create("Frame", {
		Name = "PreviewFrame",
		BackgroundColor3 = Color3.fromRGB(6, 15, 31),
		BorderSizePixel = 0,
		Position = UDim2.new(0, 20, 1, -102),
		Size = UDim2.new(1, -40, 0, 46),
		Parent = rightPane,
	})
	addCorner(previewFrame, 12)
	addStroke(previewFrame, COLORS.BorderSoft, 1, 0.25)
	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = "Generated preview",
		TextColor3 = COLORS.Faint,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(1, -28, 0, 14),
		Parent = previewFrame,
	})
	local previewLabel = create("TextLabel", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = "",
		TextColor3 = COLORS.Gold,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, 19),
		Size = UDim2.new(1, -28, 0, 22),
		Parent = previewFrame,
	})

	local runButton = create("TextButton", {
		Name = "RunButton",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.Gold,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Run Command",
		TextColor3 = Color3.fromRGB(31, 24, 10),
		TextSize = 16,
		Position = UDim2.new(1, -196, 1, -44),
		Size = UDim2.fromOffset(176, 34),
		Parent = rightPane,
	})
	addCorner(runButton, 12)
	addStroke(runButton, COLORS.GoldDark, 1, 0.05)

	local statusLabel = create("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = "Press P to toggle this dashboard.",
		TextColor3 = COLORS.Muted,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 20, 1, -42),
		Size = UDim2.new(1, -236, 0, 30),
		Parent = rightPane,
	})

	local rosterHeader = create("Frame", {
		Name = "RosterHeader",
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 54),
		Parent = rosterView,
	})
	addCorner(rosterHeader, 18)
	addStroke(rosterHeader, COLORS.BorderSoft, 1, 0.2)

	local rosterTitleLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "Admin Roster",
		TextColor3 = COLORS.Text,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 8),
		Size = UDim2.fromOffset(260, 28),
		Parent = rosterHeader,
	})

	local rosterUpdatedLabel = create("TextLabel", {
		Name = "RosterUpdated",
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = "Waiting for roster...",
		TextColor3 = COLORS.Muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(19, 34),
		Size = UDim2.new(1, -220, 0, 16),
		Parent = rosterHeader,
	})

	local rosterRefreshButton = create("TextButton", {
		Name = "RefreshRoster",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Refresh",
		TextColor3 = COLORS.Text,
		TextSize = 13,
		Position = UDim2.new(1, -126, 0, 10),
		Size = UDim2.fromOffset(108, 34),
		Parent = rosterHeader,
	})
	addCorner(rosterRefreshButton, 12)
	addStroke(rosterRefreshButton, COLORS.BorderSoft, 1, 0.2)

	local function makeRosterPanel(panelName, title, accentColor, position, size)
		local panel = create("Frame", {
			Name = panelName,
			BackgroundColor3 = COLORS.Panel,
			BorderSizePixel = 0,
			Position = position,
			Size = size,
			Parent = rosterView,
		})
		addCorner(panel, 18)
		addStroke(panel, accentColor, 1, 0.25)

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = FONT,
			Text = title,
			TextColor3 = accentColor,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -140, 0, 24),
			Parent = panel,
		})

		local countLabel = create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = "0 listed",
			TextColor3 = COLORS.Muted,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(1, -124, 0, 15),
			Size = UDim2.fromOffset(108, 18),
			Parent = panel,
		})

		local list = create("ScrollingFrame", {
			Name = "List",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = accentColor,
			Position = UDim2.fromOffset(14, 48),
			Size = UDim2.new(1, -28, 1, -62),
			Parent = panel,
		})
		addPadding(list, 0, 0, 6, 0)
		local layout = create("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})

		return {
			Panel = panel,
			CountLabel = countLabel,
			List = list,
			Layout = layout,
			AccentColor = accentColor,
		}
	end

	local superAdminRoster = makeRosterPanel(
		"SuperAdminRoster",
		"SuperAdmins",
		COLORS.Gold,
		UDim2.fromOffset(0, 66),
		UDim2.new(0.5, -10, 1, -66)
	)
	local adminRoster = makeRosterPanel(
		"AdminRoster",
		"Admins",
		COLORS.Blue,
		UDim2.new(0.5, 10, 0, 66),
		UDim2.new(0.5, -10, 1, -66)
	)
	local allPlayersRoster = makeRosterPanel(
		"AllPlayersRoster",
		"All Players",
		COLORS.Green,
		UDim2.fromOffset(0, 66),
		UDim2.new(1, 0, 1, -66)
	)
	allPlayersRoster.Panel.Visible = false

	local testerAddBar = create("Frame", {
		Name = "TesterAddBar",
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 58),
		Visible = false,
		Parent = rosterView,
	})
	addCorner(testerAddBar, 18)
	addStroke(testerAddBar, COLORS.Gold, 1, 0.25)

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "Add Tester",
		TextColor3 = COLORS.Gold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.fromOffset(120, 20),
		Parent = testerAddBar,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = "UserId is preferred; username also works when Roblox can resolve it.",
		TextColor3 = COLORS.Muted,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 31),
		Size = UDim2.new(1, -360, 0, 18),
		Parent = testerAddBar,
	})

	local testerAddBox = create("TextBox", {
		Name = "TesterTarget",
		BackgroundColor3 = Color3.fromRGB(7, 17, 36),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = BODY_FONT,
		PlaceholderColor3 = COLORS.Faint,
		PlaceholderText = "UserId or username",
		Text = "",
		TextColor3 = COLORS.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(1, -330, 0, 11),
		Size = UDim2.fromOffset(190, 36),
		Parent = testerAddBar,
	})
	addCorner(testerAddBox, 12)
	addStroke(testerAddBox, COLORS.BorderSoft, 1, 0.2)
	addPadding(testerAddBox, 12, 0, 12, 0)

	local testerAddButton = create("TextButton", {
		Name = "AddTester",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.Gold,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Add Tester",
		TextColor3 = Color3.fromRGB(31, 24, 10),
		TextSize = 13,
		Position = UDim2.new(1, -126, 0, 11),
		Size = UDim2.fromOffset(108, 36),
		Parent = testerAddBar,
	})
	addCorner(testerAddButton, 12)

	local testerRoster = makeRosterPanel(
		"TesterRoster",
		"Testers",
		COLORS.Gold,
		UDim2.fromOffset(0, 134),
		UDim2.new(1, 0, 1, -134)
	)
	testerRoster.Panel.Visible = false

	local auditRoster = makeRosterPanel(
		"AuditRoster",
		"Audit Log",
		COLORS.Red,
		UDim2.fromOffset(0, 66),
		UDim2.new(1, 0, 1, -66)
	)
	auditRoster.Panel.Visible = false

	local currentCategory = "All"
	local selectedCommand = COMMANDS[1]
	local inputBoxes = {}
	local categoryButtons = {}
	local commandCards = {}
	local pendingDanger = nil
	local rosterLoading = false
	local testerRoleLoading = false
	local lastRosterRefresh = 0
	local lastRosterPayload = nil
	local rosterRefreshQueued = false
	local rewardsLoading = false
	local lastRewardsRefresh = 0
	local lastRewardsPayload = nil
	local rewardsAutoRefreshToken = 0
	local rewardsDetailMode = "Overview"
	local renderCommandList
	local renderRoster
	local renderRewards
	local requestRoster
	local requestRewards
	local requestConsoleAction
	local requestTesterRoleChange

	local confirmLayer = create("Frame", {
		Name = "AdminConfirmLayer",
		BackgroundColor3 = COLORS.Black,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = main,
	})
	local confirmBox = create("Frame", {
		Name = "ConfirmBox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(430, 220),
		Parent = confirmLayer,
	})
	addCorner(confirmBox, 18)
	addStroke(confirmBox, COLORS.Red, 2, 0.12)
	addGradient(confirmBox, COLORS.PanelTop, COLORS.PanelBottom)
	local confirmTitle = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "Confirm Action",
		TextColor3 = COLORS.Text,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(22, 20),
		Size = UDim2.new(1, -44, 0, 28),
		Parent = confirmBox,
	})
	local confirmBody = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = "",
		TextColor3 = COLORS.Muted,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(22, 62),
		Size = UDim2.new(1, -44, 0, 84),
		Parent = confirmBox,
	})
	local confirmCancel = create("TextButton", {
		Name = "Cancel",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Cancel",
		TextColor3 = COLORS.Text,
		TextSize = 14,
		Position = UDim2.new(1, -220, 1, -54),
		Size = UDim2.fromOffset(92, 34),
		Parent = confirmBox,
	})
	addCorner(confirmCancel, 12)
	local confirmButton = create("TextButton", {
		Name = "Confirm",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.RedDark,
		BorderSizePixel = 0,
		Font = FONT,
		Text = "Confirm",
		TextColor3 = COLORS.Text,
		TextSize = 14,
		Position = UDim2.new(1, -116, 1, -54),
		Size = UDim2.fromOffset(94, 34),
		Parent = confirmBox,
	})
	addCorner(confirmButton, 12)
	addStroke(confirmButton, COLORS.Red, 1, 0.1)
	local confirmCallback = nil

	local function hideConfirm()
		confirmCallback = nil
		confirmLayer.Visible = false
	end

	local function showConfirm(title, body, callback)
		confirmTitle.Text = cleanSingleLine(title, 80)
		confirmBody.Text = cleanSingleLine(body, 260)
		confirmCallback = callback
		confirmLayer.Visible = true
	end

	confirmCancel.Activated:Connect(hideConfirm)
	confirmButton.Activated:Connect(function()
		local callback = confirmCallback
		hideConfirm()
		if callback then
			callback()
		end
	end)

	local function setStatus(text, color)
		statusLabel.Text = cleanSingleLine(text, 180)
		statusLabel.TextColor3 = color or COLORS.Muted
	end

	local function getFeedbackColor(status)
		if status == "error" or status == "rejected" then
			return COLORS.Red
		elseif status == "warning" then
			return COLORS.Gold
		end
		return COLORS.Green
	end

	local function readSnapshotCount(value)
		return math.max(0, math.floor(tonumber(value) or 0))
	end

	local function formatSnapshotNumber(value)
		local n = readSnapshotCount(value)
		if n >= 1000 then
			local text = tostring(n)
			local result = ""
			while #text > 3 do
				result = "," .. text:sub(-3) .. result
				text = text:sub(1, -4)
			end
			return text .. result
		end
		return tostring(n)
	end

	local function clearRewardsBody()
		for _, child in ipairs(rewardsScroll:GetChildren()) do
			if child ~= rewardsLayout and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function orderedCountItems(counts, preferredOrder, limit)
		local items = {}
		local used = {}
		if typeof(preferredOrder) == "table" then
			for _, key in ipairs(preferredOrder) do
				local value = readSnapshotCount(counts and counts[key])
				if value > 0 then
					items[#items + 1] = {
						Key = tostring(key),
						Value = value,
					}
					used[tostring(key)] = true
				end
			end
		end
		if typeof(counts) == "table" then
			local rest = {}
			for key, value in pairs(counts) do
				local keyText = tostring(key)
				if used[keyText] ~= true then
					local count = readSnapshotCount(value)
					if count > 0 then
						rest[#rest + 1] = {
							Key = keyText,
							Value = count,
						}
					end
				end
			end
			table.sort(rest, function(a, b)
				if a.Value == b.Value then
					return a.Key < b.Key
				end
				return a.Value > b.Value
			end)
			for _, item in ipairs(rest) do
				items[#items + 1] = item
			end
		end
		local maxItems = math.max(1, math.floor(tonumber(limit) or 8))
		while #items > maxItems do
			table.remove(items)
		end
		return items
	end

	local function formatSnapshotSeconds(value)
		local seconds = tonumber(value)
		if not seconds then
			return "n/a"
		end
		seconds = math.max(0, math.floor(seconds))
		if seconds >= 60 then
			return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
		end
		return ("%ds"):format(seconds)
	end

	local function incrementRewardsCount(counts, key, amount)
		local normalizedKey = cleanSingleLine(key, 48)
		if normalizedKey == "" then
			normalizedKey = "Unknown"
		end
		counts[normalizedKey] = (tonumber(counts[normalizedKey]) or 0) + (amount or 1)
	end

	local function makeRewardsMetricCard(parent, title, value, subtitle, accentColor, order, onActivated, footer)
		local cardProps = {
			Name = "Metric",
			BackgroundColor3 = COLORS.Panel,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = parent,
		}
		if onActivated then
			cardProps.AutoButtonColor = true
			cardProps.Text = ""
		end
		local card = create(if onActivated then "TextButton" else "Frame", cardProps)
		addCorner(card, 14)
		addStroke(card, accentColor or COLORS.BorderSoft, 1, 0.25)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = title,
			TextColor3 = COLORS.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 9),
			Size = UDim2.new(1, -24, 0, 16),
			Parent = card,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = tostring(value or ""),
			TextColor3 = accentColor or COLORS.Text,
			TextSize = if onActivated then 25 else 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 27),
			Size = UDim2.new(1, -24, 0, 28),
			Parent = card,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = subtitle,
			TextColor3 = COLORS.Faint,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(12, 56),
			Size = UDim2.new(1, -24, 0, 14),
			Parent = card,
		})
		if footer and footer ~= "" then
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = FONT,
				Text = footer,
				TextColor3 = accentColor or COLORS.Gold,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(12, 77),
				Size = UDim2.new(1, -24, 0, 16),
				Parent = card,
			})
		end
		if onActivated then
			card.Activated:Connect(function()
				pulseButton(card)
				onActivated()
			end)
		end
		return card
	end

	local function setRewardsDetailMode(mode)
		rewardsDetailMode = tostring(mode or "Overview")
		if rewardsDetailMode == "" then
			rewardsDetailMode = "Overview"
		end
		if renderRewards then
			renderRewards(lastRewardsPayload)
		end
	end

	local function getRewardsDetailTitle()
		if rewardsDetailMode == "ActiveWorld" then
			return "Active World Details"
		elseif rewardsDetailMode == "Chests" then
			return "Chests Details"
		elseif rewardsDetailMode == "Crewmates" then
			return "Crewmates Details"
		elseif rewardsDetailMode == "Dropped" then
			return "Dropped Details"
		elseif rewardsDetailMode == "Carried" then
			return "Carried Details"
		elseif rewardsDetailMode == "ChestRush" then
			return "Chest Rush Details"
		end
		return "Corridor Rewards"
	end

	local function makeRewardsMetricGrid(cards, order, columns, cellWidth, cellHeight)
		local safeCards = if typeof(cards) == "table" then cards else {}
		local safeColumns = math.max(1, math.floor(tonumber(columns) or 3))
		local safeCellWidth = math.max(120, math.floor(tonumber(cellWidth) or 220))
		local safeCellHeight = math.max(72, math.floor(tonumber(cellHeight) or 88))
		local rows = math.max(1, math.ceil(#safeCards / safeColumns))
		local grid = create("Frame", {
			Name = "RewardsSummary",
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, rows * safeCellHeight + math.max(0, rows - 1) * 10),
			Parent = rewardsScroll,
		})
		create("UIGridLayout", {
			CellPadding = UDim2.fromOffset(10, 10),
			CellSize = UDim2.fromOffset(safeCellWidth, safeCellHeight),
			FillDirectionMaxCells = safeColumns,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		for index, card in ipairs(safeCards) do
			makeRewardsMetricCard(
				grid,
				card.Title,
				card.Value,
				card.Subtitle,
				card.AccentColor,
				card.Order or index,
				card.OnActivated,
				card.Footer
			)
		end
	end

	local function makeRewardsPanel(title, subtitle, counts, preferredOrder, accentColor, order)
		local items = orderedCountItems(counts, preferredOrder, 10)
		local rowCount = math.max(1, #items)
		local panel = create("Frame", {
			Name = title:gsub("%W+", "") .. "Panel",
			BackgroundColor3 = COLORS.Panel,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 48 + rowCount * 24),
			Parent = rewardsScroll,
		})
		addCorner(panel, 16)
		addStroke(panel, accentColor or COLORS.BorderSoft, 1, 0.25)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = FONT,
			Text = title,
			TextColor3 = accentColor or COLORS.Text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 9),
			Size = UDim2.new(1, -28, 0, 20),
			Parent = panel,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = subtitle,
			TextColor3 = COLORS.Faint,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 29),
			Size = UDim2.new(1, -28, 0, 14),
			Parent = panel,
		})
		if #items == 0 then
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY_FONT,
				Text = "None active",
				TextColor3 = COLORS.Muted,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(14, 47),
				Size = UDim2.new(1, -28, 0, 20),
				Parent = panel,
			})
			return
		end
		for index, item in ipairs(items) do
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY_FONT,
				Text = item.Key,
				TextColor3 = COLORS.Text,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(14, 45 + (index - 1) * 24),
				Size = UDim2.new(1, -96, 0, 20),
				Parent = panel,
			})
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = FONT,
				Text = formatSnapshotNumber(item.Value),
				TextColor3 = accentColor or COLORS.Gold,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.new(1, -76, 0, 45 + (index - 1) * 24),
				Size = UDim2.fromOffset(58, 20),
				Parent = panel,
			})
		end
	end

	local function makeRewardsDetailPanel(details, order, title, subtitle)
		local list = if typeof(details) == "table" then details else {}
		local shown = math.min(#list, 10)
		local rowCount = math.max(1, shown)
		local panel = create("Frame", {
			Name = "RewardDetailsPanel",
			BackgroundColor3 = COLORS.Panel,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 52 + rowCount * 40),
			Parent = rewardsScroll,
		})
		addCorner(panel, 16)
		addStroke(panel, COLORS.BorderSoft, 1, 0.25)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = FONT,
			Text = title or "Recent Active Reward Details",
			TextColor3 = COLORS.Text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -28, 0, 20),
			Parent = panel,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = subtitle or "Capped list from the server snapshot",
			TextColor3 = COLORS.Faint,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 30),
			Size = UDim2.new(1, -28, 0, 14),
			Parent = panel,
		})
		if shown == 0 then
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY_FONT,
				Text = "No active reward details.",
				TextColor3 = COLORS.Muted,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(14, 52),
				Size = UDim2.new(1, -28, 0, 22),
				Parent = panel,
			})
			return
		end
		for index = 1, shown do
			local detail = list[index]
			local label = cleanSingleLine(detail.DisplayName or detail.CrewMemberId or detail.ChestId or detail.Kind or "Reward", 64)
			local status = cleanSingleLine(detail.Status or "", 24)
			local source = cleanSingleLine(detail.Source or "", 24)
			local owner = cleanSingleLine(detail.OwnerName or detail.HolderName or detail.SpawnedByName or "", 28)
			local extra = cleanSingleLine(detail.Tier or detail.Rarity or detail.Variant or "", 28)
			local line = string.format("%s  %s  %s", status, source, extra)
			local remaining = tonumber(detail.TimeRemainingSeconds)
			local age = tonumber(detail.AgeSeconds)
			if owner ~= "" then
				line ..= "  @" .. owner
			end
			if remaining then
				line ..= "  rem " .. formatSnapshotSeconds(remaining)
			elseif age then
				line ..= "  age " .. formatSnapshotSeconds(age)
			end
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = FONT,
				Text = label,
				TextColor3 = COLORS.Text,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(14, 47 + (index - 1) * 40),
				Size = UDim2.new(1, -28, 0, 17),
				Parent = panel,
			})
			create("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY_FONT,
				Text = line,
				TextColor3 = COLORS.Muted,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(14, 64 + (index - 1) * 40),
				Size = UDim2.new(1, -28, 0, 15),
				Parent = panel,
			})
		end
	end

	local function getRewardsSnapshotParts(snapshot)
		local summary = if typeof(snapshot.Summary) == "table" then snapshot.Summary else {}
		local chests = if typeof(snapshot.Chests) == "table" then snapshot.Chests else {}
		local crewmates = if typeof(snapshot.Crewmates) == "table" then snapshot.Crewmates else {}
		local runtime = if typeof(snapshot.Runtime) == "table" then snapshot.Runtime else {}
		local spawnedRuntime = if typeof(runtime.Spawned) == "table" then runtime.Spawned else {}
		local carriedRuntime = if typeof(runtime.Carried) == "table" then runtime.Carried else {}
		local chestRush = if typeof(snapshot.ChestRush) == "table" then snapshot.ChestRush else {}
		return summary, chests, crewmates, runtime, spawnedRuntime, carriedRuntime, chestRush
	end

	local function getRewardDetails(snapshot, predicate, limit)
		local details = if typeof(snapshot.Details) == "table" then snapshot.Details else {}
		local maxRows = math.max(1, math.floor(tonumber(limit) or 20))
		local filtered = {}
		for _, detail in ipairs(details) do
			if typeof(detail) == "table" and (not predicate or predicate(detail)) then
				filtered[#filtered + 1] = detail
				if #filtered >= maxRows then
					break
				end
			end
		end
		return filtered
	end

	local function isChestDetail(detail)
		return tostring(detail.RewardType or "") == "Chest" or tostring(detail.Kind or "") == "SharedChest"
	end

	local function isCrewDetail(detail)
		return tostring(detail.RewardType or "") == "Crew" or tostring(detail.Kind or "") == "PhysicalCrew"
	end

	local function isDroppedDetail(detail)
		return tostring(detail.Status or "") == "Dropped"
	end

	local function isCarriedDetail(detail)
		local status = tostring(detail.Status or "")
		return status == "Carried" or status == "Held"
	end

	local function isActiveWorldDetail(detail)
		local status = tostring(detail.Status or "")
		return status ~= "Carried" and status ~= "Held" and status ~= "Claimed"
	end

	local function getDetailPlayerCounts(details)
		local counts = {}
		for _, detail in ipairs(details) do
			local owner = cleanSingleLine(detail.OwnerName or detail.HolderName or "", 48)
			if owner == "" then
				local userId = tonumber(detail.OwnerUserId or detail.HolderUserId)
				owner = if userId and userId > 0 then "User " .. tostring(math.floor(userId)) else "Unknown"
			end
			incrementRewardsCount(counts, owner)
		end
		return counts
	end

	local function getDetailRewardTypeCounts(details)
		local counts = {}
		for _, detail in ipairs(details) do
			local rewardType = cleanSingleLine(detail.RewardType or detail.Kind or "", 48)
			if rewardType == "SharedChest" then
				rewardType = "Chest"
			elseif rewardType == "PhysicalCrew" or rewardType == "LegacyRunReward" then
				rewardType = cleanSingleLine(detail.RewardType or "Crew", 48)
			end
			incrementRewardsCount(counts, rewardType)
		end
		return counts
	end

	local function getDetailSourceCounts(details)
		local counts = {}
		for _, detail in ipairs(details) do
			incrementRewardsCount(counts, detail.Source)
		end
		return counts
	end

	local function getRewardsCapText(chests, activeChests)
		local maxActive = tonumber(chests.MaxActive)
		if maxActive then
			return ("Cap: %s / %s"):format(formatSnapshotNumber(activeChests), formatSnapshotNumber(maxActive))
		end
		return "Cap unavailable"
	end

	local function renderRewardsOverview(snapshot)
		local summary, chests, crewmates, _, _, carriedRuntime, chestRush = getRewardsSnapshotParts(snapshot)
		local activeChests = readSnapshotCount(summary.ActiveChests)
		local activeCrewmates = readSnapshotCount(summary.ActiveCrewmates)
		local droppedChests = readSnapshotCount(chests.Dropped)
		local droppedCrewmates = readSnapshotCount(crewmates.Dropped)
		local heldCrewmates = readSnapshotCount(crewmates.Held)
		local carriedChests = readSnapshotCount(carriedRuntime.Chests)
		local carriedCrewmates = readSnapshotCount(carriedRuntime.Crewmates) + heldCrewmates
		local carriedTotal = carriedChests + carriedCrewmates
		local rushActive = chestRush.Active == true
		local rushLabel = if rushActive then "Active" else "Inactive"

		makeRewardsMetricGrid({
			{
				Title = "Active World Rewards",
				Value = formatSnapshotNumber(summary.ActiveWorldRewards),
				Subtitle = ("%s chests, %s crewmates"):format(formatSnapshotNumber(activeChests), formatSnapshotNumber(activeCrewmates)),
				AccentColor = COLORS.Gold,
				OnActivated = function()
					setRewardsDetailMode("ActiveWorld")
				end,
				Footer = "Click for details",
			},
			{
				Title = "Chests",
				Value = formatSnapshotNumber(activeChests) .. " active",
				Subtitle = getRewardsCapText(chests, activeChests),
				AccentColor = COLORS.Blue,
				OnActivated = function()
					setRewardsDetailMode("Chests")
				end,
				Footer = "Click for details",
			},
			{
				Title = "Crewmates",
				Value = formatSnapshotNumber(activeCrewmates) .. " active",
				Subtitle = ("%s held, %s dropped"):format(formatSnapshotNumber(heldCrewmates), formatSnapshotNumber(droppedCrewmates)),
				AccentColor = COLORS.Green,
				OnActivated = function()
					setRewardsDetailMode("Crewmates")
				end,
				Footer = "Click for details",
			},
			{
				Title = "Dropped",
				Value = formatSnapshotNumber(summary.DroppedRewards),
				Subtitle = ("%s chests, %s crewmates"):format(formatSnapshotNumber(droppedChests), formatSnapshotNumber(droppedCrewmates)),
				AccentColor = COLORS.Red,
				OnActivated = function()
					setRewardsDetailMode("Dropped")
				end,
				Footer = "Click for details",
			},
			{
				Title = "Carried",
				Value = formatSnapshotNumber(carriedTotal),
				Subtitle = ("%s chests, %s crewmates"):format(formatSnapshotNumber(carriedChests), formatSnapshotNumber(carriedCrewmates)),
				AccentColor = COLORS.Muted,
				OnActivated = function()
					setRewardsDetailMode("Carried")
				end,
				Footer = "Click for details",
			},
			{
				Title = "Chest Rush",
				Value = rushLabel,
				Subtitle = ("%s | interval %s"):format(getRewardsCapText(chests, activeChests), formatSnapshotSeconds(chests.SpawnIntervalSeconds)),
				AccentColor = if rushActive then COLORS.Gold else COLORS.Faint,
				OnActivated = function()
					setRewardsDetailMode("ChestRush")
				end,
				Footer = "Click for details",
			},
		}, 1, 3, 302, 112)
	end

	local function renderActiveWorldDetails(snapshot)
		local summary, chests, crewmates = getRewardsSnapshotParts(snapshot)
		makeRewardsMetricGrid({
			{ Title = "Active World", Value = formatSnapshotNumber(summary.ActiveWorldRewards), Subtitle = "not carried", AccentColor = COLORS.Gold },
			{ Title = "Chests", Value = formatSnapshotNumber(summary.ActiveChests), Subtitle = getRewardsCapText(chests, summary.ActiveChests), AccentColor = COLORS.Blue },
			{ Title = "Crewmates", Value = formatSnapshotNumber(summary.ActiveCrewmates), Subtitle = "world available", AccentColor = COLORS.Green },
			{ Title = "Dropped", Value = formatSnapshotNumber(summary.DroppedRewards), Subtitle = "recoverable", AccentColor = COLORS.Red },
		}, 1, 4, 224, 78)
		makeRewardsPanel("World Chests By Tier", "World-available shared chest tiers", chests.ByTier, { "Wooden", "Iron", "Gold" }, COLORS.Blue, 10)
		makeRewardsPanel("World Crew By Status", "Spawned, dropped, and tutorial crewmates", crewmates.ByStatus, { "Spawned", "Dropped", "Tutorial", "Held" }, COLORS.Green, 20)
		makeRewardsDetailPanel(getRewardDetails(snapshot, isActiveWorldDetail, 20), 30, "Active World Rows", "World-available rewards from the latest snapshot")
	end

	local function renderChestDetails(snapshot)
		local summary, chests, _, _, _, _, chestRush = getRewardsSnapshotParts(snapshot)
		local rushLabel = if chestRush.Active == true then "Active" else "Inactive"
		makeRewardsMetricGrid({
			{ Title = "Active Chests", Value = formatSnapshotNumber(summary.ActiveChests), Subtitle = "world active", AccentColor = COLORS.Blue },
			{ Title = "Chest Cap", Value = getRewardsCapText(chests, summary.ActiveChests), Subtitle = "current server cap", AccentColor = COLORS.Gold },
			{ Title = "Chest Rush", Value = rushLabel, Subtitle = "current event state", AccentColor = if chestRush.Active == true then COLORS.Gold else COLORS.Faint },
			{ Title = "Next Spawn", Value = formatSnapshotSeconds(chests.NextSpawnInSeconds), Subtitle = "normal shared chest timer", AccentColor = COLORS.Muted },
		}, 1, 4, 224, 78)
		makeRewardsPanel("Chests By Tier", "Wooden, Iron, and Gold", chests.ByTier, { "Wooden", "Iron", "Gold" }, COLORS.Blue, 10)
		makeRewardsPanel("Chests By Source", "Normal, Chest Rush, admin debug, and dropped", chests.BySource, { "Normal", "ChestRush", "AdminDebug", "Dropped" }, COLORS.Gold, 20)
		makeRewardsPanel("Chests By Depth", "Shared world chest depth bands", chests.ByDepthBand, { "Shallow", "Mid", "Deep", "Abyssal" }, COLORS.Muted, 30)
		makeRewardsDetailPanel(getRewardDetails(snapshot, isChestDetail, 20), 40, "Recent Chest Rows", "Tier, source, depth, status, and time")
	end

	local function renderCrewmateDetails(snapshot)
		local _, _, crewmates = getRewardsSnapshotParts(snapshot)
		makeRewardsMetricGrid({
			{ Title = "Active Crewmates", Value = formatSnapshotNumber(crewmates.WorldAvailableCount), Subtitle = "world available", AccentColor = COLORS.Green },
			{ Title = "Spawned", Value = formatSnapshotNumber(crewmates.Spawned), Subtitle = "available pickups", AccentColor = COLORS.Green },
			{ Title = "Held", Value = formatSnapshotNumber(crewmates.Held), Subtitle = "currently held", AccentColor = COLORS.Gold },
			{ Title = "Dropped", Value = formatSnapshotNumber(crewmates.Dropped), Subtitle = "recoverable", AccentColor = COLORS.Red },
		}, 1, 4, 224, 78)
		makeRewardsPanel("Crewmates By Rarity", "Current physical crewmate rarities", crewmates.ByRarity, nil, COLORS.Green, 10)
		makeRewardsPanel("Crewmates By Variant", "Normal, Golden, Diamond, and event variants", crewmates.ByVariant, { "Normal", "Golden", "Diamond" }, COLORS.Green, 20)
		makeRewardsPanel("Crewmates By Status", "Spawned, held, dropped, tutorial", crewmates.ByStatus, { "Spawned", "Held", "Dropped", "Tutorial" }, COLORS.Gold, 30)
		makeRewardsPanel("Top Crew Names", "Top active crew member names or ids", crewmates.ByCrewMember, nil, COLORS.Blue, 40)
		makeRewardsDetailPanel(getRewardDetails(snapshot, isCrewDetail, 20), 50, "Recent Crew Rows", "Name, rarity, variant, holder, and time")
	end

	local function renderDroppedDetails(snapshot)
		local summary, chests, crewmates = getRewardsSnapshotParts(snapshot)
		local droppedDetails = getRewardDetails(snapshot, isDroppedDetail, 20)
		makeRewardsMetricGrid({
			{ Title = "Dropped Rewards", Value = formatSnapshotNumber(summary.DroppedRewards), Subtitle = "recoverable in world", AccentColor = COLORS.Red },
			{ Title = "Dropped Chests", Value = formatSnapshotNumber(chests.Dropped), Subtitle = "shared chest drops", AccentColor = COLORS.Blue },
			{ Title = "Dropped Crew", Value = formatSnapshotNumber(crewmates.Dropped), Subtitle = "physical crewmates", AccentColor = COLORS.Green },
		}, 1, 3, 302, 78)
		makeRewardsPanel("Dropped By Type", "Dropped rewards from visible detail rows", getDetailRewardTypeCounts(droppedDetails), { "Chest", "Crew" }, COLORS.Gold, 10)
		makeRewardsPanel("Dropped By Source", "Dropped reward sources from visible rows", getDetailSourceCounts(droppedDetails), { "Dropped", "Normal", "ChestRush", "AdminDebug" }, COLORS.Muted, 20)
		makeRewardsDetailPanel(droppedDetails, 30, "Dropped Reward Rows", "Dropped rewards only")
	end

	local function renderCarriedDetails(snapshot)
		local _, _, crewmates, _, _, carriedRuntime = getRewardsSnapshotParts(snapshot)
		local heldCrewmates = readSnapshotCount(crewmates.Held)
		local carriedChests = readSnapshotCount(carriedRuntime.Chests)
		local carriedCrewmates = readSnapshotCount(carriedRuntime.Crewmates) + heldCrewmates
		local carriedDetails = getRewardDetails(snapshot, isCarriedDetail, 20)
		makeRewardsMetricGrid({
			{ Title = "Carried Rewards", Value = formatSnapshotNumber(carriedChests + carriedCrewmates), Subtitle = "held by players", AccentColor = COLORS.Muted },
			{ Title = "Carried Chests", Value = formatSnapshotNumber(carriedChests), Subtitle = "carry slots", AccentColor = COLORS.Blue },
			{ Title = "Carried Crew", Value = formatSnapshotNumber(carriedCrewmates), Subtitle = "held or carry slots", AccentColor = COLORS.Green },
			{ Title = "Players", Value = formatSnapshotNumber(#orderedCountItems(getDetailPlayerCounts(carriedDetails), nil, 100)), Subtitle = "with carried rows", AccentColor = COLORS.Gold },
		}, 1, 4, 224, 78)
		makeRewardsPanel("Carried By Player", "Held and carried rewards grouped by player", getDetailPlayerCounts(carriedDetails), nil, COLORS.Gold, 10)
		makeRewardsPanel("Carried By Type", "Held and carried rows grouped by type", getDetailRewardTypeCounts(carriedDetails), { "Chest", "Crew" }, COLORS.Muted, 20)
		makeRewardsDetailPanel(carriedDetails, 30, "Carried Reward Rows", "Player, reward, type, and status")
	end

	local function renderChestRushDetails(snapshot)
		local _, chests, _, _, _, _, chestRush = getRewardsSnapshotParts(snapshot)
		local rushActive = chestRush.Active == true
		makeRewardsMetricGrid({
			{ Title = "Chest Rush", Value = if rushActive then "Active" else "Inactive", Subtitle = "current event state", AccentColor = if rushActive then COLORS.Gold else COLORS.Faint },
			{ Title = "Chest Cap", Value = formatSnapshotNumber(chests.MaxActive), Subtitle = "modified active cap", AccentColor = COLORS.Gold },
			{ Title = "Spawn Interval", Value = formatSnapshotSeconds(chests.SpawnIntervalSeconds), Subtitle = "current shared interval", AccentColor = COLORS.Blue },
			{ Title = "Next Spawn", Value = formatSnapshotSeconds(chests.NextSpawnInSeconds), Subtitle = "shared chest timer", AccentColor = COLORS.Muted },
		}, 1, 4, 224, 78)
		makeRewardsPanel("Chest Rush Sources", "Chest source counts in the world", chests.BySource, { "ChestRush", "Normal", "AdminDebug", "Dropped" }, COLORS.Gold, 10)
		makeRewardsPanel("Chest Rush Tiers", "Current chest tier mix", chests.ByTier, { "Wooden", "Iron", "Gold" }, COLORS.Blue, 20)
		makeRewardsDetailPanel(getRewardDetails(snapshot, function(detail)
			return isChestDetail(detail) and tostring(detail.Source or "") == "ChestRush"
		end, 20), 30, "Chest Rush Chest Rows", "Chests stamped with ChestRush source")
	end

	renderRewards = function(payload)
		clearRewardsBody()
		rewardsTitleLabel.Text = getRewardsDetailTitle()
		rewardsBackButton.Visible = rewardsDetailMode ~= "Overview"
		if typeof(payload) ~= "table" or payload.Success == false or typeof(payload.Snapshot) ~= "table" then
			local message = if typeof(payload) == "table" then cleanSingleLine(payload.Message, 140) else ""
			if message == "" then
				message = "Corridor reward snapshot unavailable."
			end
			makeRewardsPanel("Snapshot Unavailable", message, {}, nil, COLORS.Red, 1)
			return
		end

		local snapshot = payload.Snapshot
		if rewardsDetailMode == "ActiveWorld" then
			renderActiveWorldDetails(snapshot)
		elseif rewardsDetailMode == "Chests" then
			renderChestDetails(snapshot)
		elseif rewardsDetailMode == "Crewmates" then
			renderCrewmateDetails(snapshot)
		elseif rewardsDetailMode == "Dropped" then
			renderDroppedDetails(snapshot)
		elseif rewardsDetailMode == "Carried" then
			renderCarriedDetails(snapshot)
		elseif rewardsDetailMode == "ChestRush" then
			renderChestRushDetails(snapshot)
		else
			renderRewardsOverview(snapshot)
		end

		task.defer(function()
			if rewardsScroll.Parent then
				rewardsScroll.CanvasSize = UDim2.fromOffset(0, rewardsLayout.AbsoluteContentSize.Y + 12)
			end
		end)
	end

	requestRewards = function()
		if rewardsLoading then
			return
		end

		if not adminCorridorRewardsFunction:IsA("RemoteFunction") then
			rewardsUpdatedLabel.Text = "Reward snapshot remote unavailable."
			lastRewardsPayload = {
				Success = false,
				Message = "Reward snapshot remote unavailable.",
			}
			renderRewards(lastRewardsPayload)
			return
		end

		rewardsLoading = true
		rewardsUpdatedLabel.Text = "Loading reward snapshot..."
		setButtonStyle(rewardsRefreshButton, true, false)

		task.spawn(function()
			local ok, payload = pcall(function()
				return adminCorridorRewardsFunction:InvokeServer()
			end)

			rewardsLoading = false
			if not gui.Parent then
				return
			end

			if ok and typeof(payload) == "table" and payload.Success ~= false then
				lastRewardsRefresh = os.clock()
				lastRewardsPayload = payload
				rewardsUpdatedLabel.Text = "Updated now"
				renderRewards(payload)
			else
				local message = "Unable to load corridor reward snapshot."
				if ok and typeof(payload) == "table" then
					message = cleanSingleLine(payload.Message, 140)
				end
				if message == "" then
					message = "Unable to load corridor reward snapshot."
				end
				lastRewardsPayload = {
					Success = false,
					Message = message,
				}
				rewardsUpdatedLabel.Text = message
				renderRewards(lastRewardsPayload)
			end

			setButtonStyle(rewardsRefreshButton, false, false)
		end)
	end

	local function startRewardsAutoRefresh()
		rewardsAutoRefreshToken += 1
		local token = rewardsAutoRefreshToken
		task.spawn(function()
			while gui.Parent and gui.Enabled and currentTab == "Rewards" and rewardsAutoRefreshToken == token do
				if requestRewards and os.clock() - lastRewardsRefresh >= 4 then
					requestRewards()
				end
				task.wait(1)
			end
		end)
	end

	local function updateTabButtons()
		for tabName, button in pairs(tabButtons) do
			setButtonStyle(button, tabName == currentTab, false)
		end
	end

	setActiveTab = function(tabName)
		if tabName == "Admins" or tabName == "AllPlayers" or tabName == "Testers" or tabName == "Audit" or tabName == "Rewards" then
			currentTab = tabName
		else
			currentTab = "Commands"
		end
		commandView.Visible = currentTab == "Commands"
		rosterView.Visible = currentTab ~= "Commands" and currentTab ~= "Rewards"
		rewardsView.Visible = currentTab == "Rewards"
		updateTabButtons()

		if currentTab == "Rewards" then
			renderRewards(lastRewardsPayload)
			if requestRewards and os.clock() - lastRewardsRefresh > 1 then
				requestRewards()
			end
			startRewardsAutoRefresh()
			return
		end

		rewardsAutoRefreshToken += 1
		if currentTab ~= "Commands" and renderRoster then
			renderRoster(lastRosterPayload)
		end

		if currentTab ~= "Commands" and requestRoster and os.clock() - lastRosterRefresh > 2 then
			requestRoster()
		end
	end

	tabButtons.Commands.Activated:Connect(function()
		pulseButton(tabButtons.Commands)
		setActiveTab("Commands")
	end)

	tabButtons.Admins.Activated:Connect(function()
		pulseButton(tabButtons.Admins)
		setActiveTab("Admins")
	end)

	tabButtons.AllPlayers.Activated:Connect(function()
		pulseButton(tabButtons.AllPlayers)
		setActiveTab("AllPlayers")
	end)

	tabButtons.Testers.Activated:Connect(function()
		pulseButton(tabButtons.Testers)
		setActiveTab("Testers")
	end)

	tabButtons.Audit.Activated:Connect(function()
		pulseButton(tabButtons.Audit)
		setActiveTab("Audit")
	end)

	tabButtons.Rewards.Activated:Connect(function()
		pulseButton(tabButtons.Rewards)
		rewardsDetailMode = "Overview"
		setActiveTab("Rewards")
	end)

	local function clearRosterList(roster)
		for _, child in ipairs(roster.List:GetChildren()) do
			if child ~= roster.Layout and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	local function getRosterStatus(entry)
		if entry.IsActiveAdmin == true then
			return "Active Admin", COLORS.Green
		elseif entry.IsOnline == true then
			return "Online", COLORS.Blue
		end
		return "Offline", COLORS.Faint
	end

	local function getRosterRoleText(entry, fallbackRole)
		local roles = {}
		if entry.IsSuperAdmin == true then
			table.insert(roles, "SuperAdmin")
		end
		if entry.IsConfiguredAdmin == true then
			table.insert(roles, "Admin")
		end
		if entry.IsTester == true then
			table.insert(roles, "Tester")
		end
		if #roles > 0 then
			return table.concat(roles, " + ")
		end
		return fallbackRole
	end

	local function makeRosterEmpty(roster, text)
		local empty = create("Frame", {
			BackgroundColor3 = COLORS.PanelSoft,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -4, 0, 72),
			Parent = roster.List,
		})
		addCorner(empty, 12)
		addStroke(empty, roster.AccentColor, 1, 0.45)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = text,
			TextColor3 = COLORS.Muted,
			TextSize = 13,
			TextWrapped = true,
			Size = UDim2.new(1, -24, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			Parent = empty,
		})
	end

	local function normalizeActionSpecs(actionSpec)
		if typeof(actionSpec) ~= "table" then
			return {}
		end
		if actionSpec.Label ~= nil then
			return { actionSpec }
		end

		local actions = {}
		for _, spec in ipairs(actionSpec) do
			if typeof(spec) == "table" and spec.Label ~= nil then
				table.insert(actions, spec)
			end
		end
		return actions
	end

	local function makeRosterRow(roster, entry, index, fallbackRole, actionSpec)
		local userId = math.floor(tonumber(entry.UserId) or 0)
		local username = cleanSingleLine(entry.Username, 60)
		local displayName = cleanSingleLine(entry.DisplayName, 60)
		if displayName == "" then
			displayName = username ~= "" and username or ("User " .. tostring(userId))
		end
		if username == "" then
			username = displayName
		end

		local statusText, statusColor = getRosterStatus(entry)
		local roleText = getRosterRoleText(entry, fallbackRole)
		local reason = cleanSingleLine(entry.AdminStatusReason, 80)
		local testerSource = cleanSingleLine(entry.TesterSource, 40)
		if testerSource ~= "" then
			reason = "Tester source: " .. testerSource
		end
		local actionSpecs = normalizeActionSpecs(actionSpec)
		local hasAction = #actionSpecs > 0

		local row = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(8, 18, 38),
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1, -4, 0, if hasAction then 124 else 82),
			Parent = roster.List,
		})
		addCorner(row, 14)
		addStroke(
			row,
			entry.IsActiveAdmin and COLORS.Green or roster.AccentColor,
			entry.IsActiveAdmin and 2 or 1,
			entry.IsActiveAdmin and 0.05 or 0.38
		)

		local avatar = create("ImageLabel", {
			BackgroundColor3 = COLORS.PanelRaised,
			BorderSizePixel = 0,
			Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId),
			Position = UDim2.fromOffset(12, 13),
			Size = UDim2.fromOffset(56, 56),
			Parent = row,
		})
		addCorner(avatar, 14)

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = FONT,
			Text = displayName,
			TextColor3 = COLORS.Text,
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(80, 10),
			Size = UDim2.new(1, if hasAction then -260 else -230, 0, 22),
			Parent = row,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = ("@%s  |  %d"):format(username, userId),
			TextColor3 = COLORS.Muted,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(80, 34),
			Size = UDim2.new(1, if hasAction then -258 else -224, 0, 18),
			Parent = row,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = reason,
			TextColor3 = COLORS.Faint,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(80, 54),
			Size = UDim2.new(1, if hasAction then -258 else -224, 0, 16),
			Parent = row,
		})

		local rolePill = create("TextLabel", {
			BackgroundColor3 = COLORS.PanelRaised,
			BorderSizePixel = 0,
			Font = FONT,
			Text = roleText,
			TextColor3 = roster.AccentColor,
			TextSize = if #roleText > 16 then 8 else 10,
			Position = UDim2.new(1, -138, 0, 13),
			Size = UDim2.fromOffset(124, 24),
			Parent = row,
		})
		addCorner(rolePill, 12)

		local statusPill = create("TextLabel", {
			BackgroundColor3 = Color3.fromRGB(6, 15, 31),
			BorderSizePixel = 0,
			Font = FONT,
			Text = statusText,
			TextColor3 = statusColor,
			TextSize = 10,
			Position = UDim2.new(1, -138, 0, 45),
			Size = UDim2.fromOffset(124, 24),
			Parent = row,
		})
		addCorner(statusPill, 12)
		addStroke(statusPill, statusColor, 1, 0.35)

		if hasAction then
			local actionsFrame = create("Frame", {
				Name = "Actions",
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				Position = UDim2.fromOffset(80, 78),
				Size = UDim2.new(1, -96, 0, 34),
				Parent = row,
			})
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = actionsFrame,
			})

			for actionIndex, spec in ipairs(actionSpecs) do
				local labelText = cleanSingleLine(spec.Label, 24)
				local actionButton = create("TextButton", {
					Name = tostring(spec.Action or "AdminConsoleAction"),
					AutoButtonColor = spec.Enabled ~= false,
					BackgroundColor3 = spec.Dangerous == true and COLORS.RedDark or COLORS.Gold,
					BorderSizePixel = 0,
					Font = FONT,
					LayoutOrder = actionIndex,
					Text = labelText,
					TextColor3 = spec.Dangerous == true and COLORS.Text or Color3.fromRGB(31, 24, 10),
					TextSize = 11,
					Size = UDim2.fromOffset(math.max(92, math.min(132, (#labelText * 7) + 28)), 26),
					Parent = actionsFrame,
				})
				addCorner(actionButton, 10)
				addStroke(actionButton, spec.Dangerous == true and COLORS.Red or COLORS.GoldDark, 1, 0.2)

				actionButton.Activated:Connect(function()
					if spec.Enabled == false or testerRoleLoading then
						return
					end
					pulseButton(actionButton)
					if requestConsoleAction then
						requestConsoleAction(spec)
					elseif requestTesterRoleChange then
						requestTesterRoleChange(tostring(spec.Action or ""), tostring(spec.Target or userId))
					end
				end)
			end
		end
	end

	local function addAction(actions, label, actionName, target, dangerous, reason)
		table.insert(actions, {
			Label = label,
			Action = actionName,
			Target = tostring(target or ""),
			Dangerous = dangerous == true,
			Reason = reason,
		})
	end

	local function buildConsoleActions(entry)
		local actions = {}
		local target = tostring(entry.UserId or "")
		if entry.CanGrantTester == true or entry.CanAddTester == true then
			addAction(actions, "Set Tester", "SetTester", target, false)
		end
		if entry.CanRemoveTester == true then
			addAction(actions, "Remove Tester", "RemoveTester", target, true)
		end
		if entry.CanGrantAdmin == true then
			addAction(actions, "Set Admin", "SetAdmin", target, true)
		end
		if entry.CanRemoveAdmin == true then
			addAction(actions, "Remove Admin", "RemoveAdmin", target, true)
		end
		if entry.CanGrantSuperAdmin == true then
			addAction(actions, "Set Super", "SetSuperAdmin", target, true)
		end
		if entry.CanRemoveSuperAdmin == true then
			addAction(actions, "Remove Super", "RemoveSuperAdmin", target, true)
		end
		if entry.CanKick == true then
			addAction(actions, "Kick", "Kick", target, true, "Removed from the server by an admin.")
		end
		return actions
	end

	local function makeAuditRow(roster, entry, index)
		local actionName = cleanSingleLine(entry.Action, 40)
		local result = cleanSingleLine(entry.Result, 24)
		local actorName = cleanSingleLine(entry.ActorName, 80)
		local targetName = cleanSingleLine(entry.TargetName, 80)
		local reason = cleanSingleLine(entry.Reason, 160)
		local targetUserId = math.floor(tonumber(entry.TargetUserId) or 0)
		local timeText = os.date("!%H:%M:%S", math.floor(tonumber(entry.Time) or os.time()))
		local resultColor = if result == "success" then COLORS.Green elseif result == "rejected" then COLORS.Gold else COLORS.Red
		local row = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(8, 18, 38),
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1, -4, 0, 74),
			Parent = roster.List,
		})
		addCorner(row, 14)
		addStroke(row, resultColor, 1, 0.35)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = FONT,
			Text = ("%s  |  %s"):format(actionName ~= "" and actionName or "Action", string.upper(result ~= "" and result or "unknown")),
			TextColor3 = resultColor,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -160, 0, 20),
			Parent = row,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = ("%s -> %s%s"):format(
				actorName ~= "" and actorName or "Unknown",
				targetName ~= "" and targetName or "No target",
				targetUserId > 0 and (" (" .. tostring(targetUserId) .. ")") or ""
			),
			TextColor3 = COLORS.Muted,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(14, 30),
			Size = UDim2.new(1, -28, 0, 18),
			Parent = row,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = reason,
			TextColor3 = COLORS.Faint,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(14, 50),
			Size = UDim2.new(1, -28, 0, 16),
			Parent = row,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			Text = timeText,
			TextColor3 = COLORS.Faint,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(1, -130, 0, 10),
			Size = UDim2.fromOffset(116, 18),
			Parent = row,
		})
	end

	renderRoster = function(payload)
		clearRosterList(superAdminRoster)
		clearRosterList(adminRoster)
		clearRosterList(allPlayersRoster)
		clearRosterList(testerRoster)
		clearRosterList(auditRoster)

		local function setRosterPanels(adminsVisible, allPlayersVisible, testersVisible, auditVisible, showTesterAdd)
			superAdminRoster.Panel.Visible = adminsVisible
			adminRoster.Panel.Visible = adminsVisible
			allPlayersRoster.Panel.Visible = allPlayersVisible
			testerAddBar.Visible = showTesterAdd
			testerRoster.Panel.Visible = testersVisible
			auditRoster.Panel.Visible = auditVisible

			if testersVisible then
				testerRoster.Panel.Position = if showTesterAdd then UDim2.fromOffset(0, 134) else UDim2.fromOffset(0, 66)
				testerRoster.Panel.Size = if showTesterAdd then UDim2.new(1, 0, 1, -134) else UDim2.new(1, 0, 1, -66)
			end
		end

		if typeof(payload) ~= "table" or payload.Success == false then
			local message = if typeof(payload) == "table" then cleanSingleLine(payload.Message, 120) else ""
			if message == "" then
				message = "Roster unavailable."
			end
			rosterTitleLabel.Text = if currentTab == "Testers"
				then "Testers"
				elseif currentTab == "Audit" then "Audit Log"
				elseif currentTab == "AllPlayers" then "All Players"
				else "Admin Roster"
			setRosterPanels(currentTab == "Admins", currentTab == "AllPlayers", currentTab == "Testers", currentTab == "Audit", false)

			local targetRoster = if currentTab == "Testers"
				then testerRoster
				elseif currentTab == "Audit" then auditRoster
				elseif currentTab == "AllPlayers" then allPlayersRoster
				else superAdminRoster
			targetRoster.CountLabel.Text = "0 listed"
			makeRosterEmpty(targetRoster, message)
			if currentTab == "Admins" then
				adminRoster.CountLabel.Text = "0 listed"
				makeRosterEmpty(adminRoster, message)
			end
			return
		end

		local viewer = if typeof(payload.Viewer) == "table" then payload.Viewer else {}
		local viewerIsSuperAdmin = viewer.IsSuperAdmin == true
		local superAdmins = if typeof(payload.SuperAdmins) == "table" then payload.SuperAdmins else {}
		local admins = if typeof(payload.Admins) == "table" then payload.Admins else {}
		local allPlayers = if typeof(payload.AllPlayers) == "table" then payload.AllPlayers else {}
		local testers = if typeof(payload.Testers) == "table" then payload.Testers else {}
		local auditEntries = if typeof(payload.AuditLog) == "table" then payload.AuditLog else {}

		if currentTab == "AllPlayers" then
			rosterTitleLabel.Text = "Players"
			setRosterPanels(false, true, false, false, false)
			allPlayersRoster.CountLabel.Text = ("%d online"):format(#allPlayers)
			if #allPlayers == 0 then
				makeRosterEmpty(allPlayersRoster, "No players are currently in this server.")
			else
				for index, entry in ipairs(allPlayers) do
					makeRosterRow(allPlayersRoster, entry, index, "Player", buildConsoleActions(entry))
				end
			end
			return
		end

		if currentTab == "Testers" then
			rosterTitleLabel.Text = "Testers"
			setRosterPanels(false, false, true, false, viewerIsSuperAdmin)
			testerRoster.CountLabel.Text = ("%d listed"):format(#testers)
			if #testers == 0 then
				makeRosterEmpty(testerRoster, "No testers are currently configured.")
			else
				for index, entry in ipairs(testers) do
					makeRosterRow(testerRoster, entry, index, "Tester", buildConsoleActions(entry))
				end
			end
			return
		end

		if currentTab == "Audit" then
			rosterTitleLabel.Text = "Audit Log"
			setRosterPanels(false, false, false, true, false)
			auditRoster.CountLabel.Text = ("%d recent"):format(#auditEntries)
			if #auditEntries == 0 then
				makeRosterEmpty(auditRoster, "No admin console actions have been logged in this server yet.")
			else
				for index, entry in ipairs(auditEntries) do
					makeAuditRow(auditRoster, entry, index)
				end
			end
			return
		end

		rosterTitleLabel.Text = "Staff Roles"
		setRosterPanels(true, false, false, false, false)
		superAdminRoster.CountLabel.Text = ("%d listed"):format(#superAdmins)
		adminRoster.CountLabel.Text = ("%d listed"):format(#admins)

		if #superAdmins == 0 then
			makeRosterEmpty(superAdminRoster, "No SuperAdmins listed.")
		else
			for index, entry in ipairs(superAdmins) do
				makeRosterRow(superAdminRoster, entry, index, "SuperAdmin", buildConsoleActions(entry))
			end
		end

		if #admins == 0 then
			makeRosterEmpty(adminRoster, "No Admins listed.")
		else
			for index, entry in ipairs(admins) do
				makeRosterRow(adminRoster, entry, index, "Admin", buildConsoleActions(entry))
			end
		end
	end

	requestRoster = function()
		if rosterLoading then
			return
		end

		if not adminRosterFunction:IsA("RemoteFunction") then
			rosterUpdatedLabel.Text = "Roster remote unavailable."
			renderRoster({
				Success = false,
				Message = "Roster remote unavailable.",
			})
			return
		end

		rosterLoading = true
		rosterUpdatedLabel.Text = "Loading roster..."
		setButtonStyle(rosterRefreshButton, true, false)

		task.spawn(function()
			local ok, payload = pcall(function()
				return adminRosterFunction:InvokeServer()
			end)

			rosterLoading = false
			if not gui.Parent then
				return
			end

			if ok and typeof(payload) == "table" and payload.Success ~= false then
				lastRosterRefresh = os.clock()
				lastRosterPayload = payload
				rosterUpdatedLabel.Text = "Updated now"
				renderRoster(payload)
			else
				local message = "Unable to load roster."
				if ok and typeof(payload) == "table" then
					message = cleanSingleLine(payload.Message, 120)
				end
				if message == "" then
					message = "Unable to load roster."
				end
				rosterUpdatedLabel.Text = message
				lastRosterPayload = {
					Success = false,
					Message = message,
				}
				renderRoster({
					Success = false,
					Message = message,
				})
			end

			setButtonStyle(rosterRefreshButton, false, false)
		end)
	end

	local function queueRosterRefresh(reason)
		if rosterRefreshQueued or currentTab == "Commands" or currentTab == "Rewards" or not gui.Enabled then
			return
		end

		rosterRefreshQueued = true
		rosterUpdatedLabel.Text = cleanSingleLine(reason or "Roster changed.", 120)
		task.delay(0.2, function()
			rosterRefreshQueued = false
			if gui.Parent and gui.Enabled and currentTab ~= "Commands" and currentTab ~= "Rewards" and requestRoster then
				requestRoster()
			end
		end)
	end

	requestConsoleAction = function(actionSpec, confirmed)
		if testerRoleLoading then
			return
		end

		if typeof(actionSpec) ~= "table" then
			return
		end

		local action = cleanSingleLine(actionSpec.Action, 32)
		local target = cleanSingleLine(actionSpec.Target or actionSpec.TargetUserId, 80)
		if target == "" then
			rosterUpdatedLabel.Text = "Enter a UserId or username."
			return
		end

		if actionSpec.Dangerous == true and confirmed ~= true then
			local label = cleanSingleLine(actionSpec.Label, 40)
			showConfirm(
				label ~= "" and label or "Confirm Action",
				("Confirm %s for %s. This is server-authoritative and will be audited."):format(label ~= "" and label or action, target),
				function()
					requestConsoleAction(actionSpec, true)
				end
			)
			return
		end

		testerRoleLoading = true
		rosterUpdatedLabel.Text = "Sending admin console action..."

		task.spawn(function()
			local requestPayload = {
				Action = action,
				Target = target,
				Confirmed = confirmed == true,
				Reason = cleanSingleLine(actionSpec.Reason, 180),
			}
			local targetUserId = tonumber(target)
			if targetUserId then
				requestPayload.TargetUserId = math.floor(targetUserId)
			end

			local ok, resultPayload = pcall(function()
				if adminConsoleActionFunction:IsA("RemoteFunction") then
					return adminConsoleActionFunction:InvokeServer(requestPayload)
				end
				if adminTesterRoleFunction:IsA("RemoteFunction") and (action == "AddTester" or action == "SetTester" or action == "RemoveTester") then
					return adminTesterRoleFunction:InvokeServer(action == "RemoveTester" and "RemoveTester" or "AddTester", target)
				end
				return {
					Success = false,
					Message = "Admin console remote unavailable.",
				}
			end)

			testerRoleLoading = false
			if not gui.Parent then
				return
			end

			local message = "Admin console action failed."
			if ok and typeof(resultPayload) == "table" then
				message = cleanSingleLine(resultPayload.Message, 140)
				if message == "" then
					message = if resultPayload.Success == false then "Admin console action failed." else "Admin console action completed."
				end
				if resultPayload.Success ~= false and typeof(resultPayload.Roster) == "table" then
					lastRosterRefresh = os.clock()
					lastRosterPayload = resultPayload.Roster
					if action == "AddTester" or action == "SetTester" then
						testerAddBox.Text = ""
					end
					renderRoster(resultPayload.Roster)
				elseif resultPayload.Success ~= false then
					requestRoster()
				end
			end

			rosterUpdatedLabel.Text = message
		end)
	end

	requestTesterRoleChange = function(action, target)
		local normalizedAction = cleanSingleLine(action, 24)
		requestConsoleAction({
			Action = normalizedAction == "RemoveTester" and "RemoveTester" or "SetTester",
			Label = normalizedAction == "RemoveTester" and "Remove Tester" or "Set Tester",
			Target = target,
			Dangerous = normalizedAction == "RemoveTester",
		})
	end

	rosterRefreshButton.Activated:Connect(function()
		pulseButton(rosterRefreshButton)
		requestRoster()
	end)

	rewardsRefreshButton.Activated:Connect(function()
		pulseButton(rewardsRefreshButton)
		requestRewards()
	end)

	rewardsBackButton.Activated:Connect(function()
		pulseButton(rewardsBackButton)
		setRewardsDetailMode("Overview")
	end)

	testerAddButton.Activated:Connect(function()
		pulseButton(testerAddButton)
		if requestTesterRoleChange then
			requestTesterRoleChange("AddTester", testerAddBox.Text)
		end
	end)

	if adminRosterUpdatedEvent:IsA("RemoteEvent") then
		adminRosterUpdatedEvent.OnClientEvent:Connect(function(payload)
			local reason = "Roster changed."
			if typeof(payload) == "table" and typeof(payload.Reason) == "string" then
				reason = "Roster changed: " .. cleanSingleLine(payload.Reason, 80)
			end
			queueRosterRefresh(reason)
		end)
	end

	if adminCommandFeedbackEvent:IsA("RemoteEvent") then
		adminCommandFeedbackEvent.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then
				setStatus("Server confirmed admin action.", COLORS.Green)
				return
			end

			local status = tostring(payload.Status or payload.status or "success")
			local message = cleanSingleLine(payload.Message or payload.message or "", 180)
			if typeof(payload.IsAdmin) == "boolean" then
				isAdmin = payload.IsAdmin or payload.IsSuperAdmin == true
				if not isAdmin then
					gui.Enabled = false
					dim.Visible = false
				end
				if updateAdminLauncherVisibility then
					updateAdminLauncherVisibility()
				end
			end

			if message == "" then
				local commandName = cleanSingleLine(payload.DisplayName or payload.CommandName or payload.commandName or "Admin command", 60)
				local detail = cleanSingleLine(payload.Detail or payload.detail or "", 120)
				message = if detail ~= "" then commandName .. " confirmed: " .. detail else commandName .. " confirmed."
			end

			setStatus(message, getFeedbackColor(status))
		end)
	end

	local function valuesFromInputs()
		local values = {}
		for key, box in pairs(inputBoxes) do
			values[key] = box.Text
		end
		return values
	end

	local function currentPreview(confirm)
		if not selectedCommand then
			return ""
		end
		return selectedCommand.build(valuesFromInputs(), confirm)
	end

	local function updateRunButton()
		if not selectedCommand then
			runButton.Text = "Run Command"
			setButtonStyle(runButton, true, false)
			return
		end

		local now = os.clock()
		local preview = currentPreview(false)
		previewLabel.Text = preview

		if selectedCommand.dangerous then
			setButtonStyle(runButton, true, true)
			if selectedCommand.confirmOnly then
				runButton.Text = "Send Confirm"
			elseif pendingDanger
				and pendingDanger.commandId == selectedCommand.id
				and pendingDanger.baseCommand == preview
				and pendingDanger.expiresAt > now then
				runButton.Text = ("Send Confirm (%ds)"):format(math.max(0, math.ceil(pendingDanger.expiresAt - now)))
			else
				runButton.Text = "Requires Confirm"
			end
		else
			setButtonStyle(runButton, true, false)
			runButton.Text = selectedCommand.panelAction and "Run Action" or "Run Command"
		end
	end

	local function makeInfoBlock(title, body, accentColor)
		local block = create("Frame", {
			BackgroundColor3 = COLORS.PanelSoft,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -2, 0, 78),
		})
		addCorner(block, 12)
		addStroke(block, accentColor or COLORS.BorderSoft, 1, 0.35)
		addPadding(block, 14, 10, 14, 10)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = FONT,
			Text = title,
			TextColor3 = accentColor or COLORS.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 18),
			Parent = block,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = body,
			TextColor3 = COLORS.Muted,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 1, -22),
			Parent = block,
		})
		return block
	end

	local function clearDetails()
		for _, child in ipairs(detailsScroll:GetChildren()) do
			if child ~= detailsLayout and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
		inputBoxes = {}
	end

	local function renderDetails()
		clearDetails()
		if not selectedCommand then
			makeInfoBlock("No command selected", "Use search or categories to find an admin command.", COLORS.Gold).Parent = detailsScroll
			updateRunButton()
			return
		end

		local heading = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -2, 0, 56),
			Parent = detailsScroll,
		})
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = selectedCommand.name,
			TextColor3 = selectedCommand.dangerous and COLORS.Red or COLORS.Text,
			TextSize = 23,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -150, 0, 32),
			Parent = heading,
		})
		local pill = create("TextLabel", {
			BackgroundColor3 = selectedCommand.dangerous and COLORS.RedDark or COLORS.PanelRaised,
			BorderSizePixel = 0,
			Font = FONT,
			Text = selectedCommand.category,
			TextColor3 = selectedCommand.dangerous and COLORS.Text or COLORS.Gold,
			TextSize = 11,
			Position = UDim2.new(1, -142, 0, 4),
			Size = UDim2.fromOffset(142, 26),
			Parent = heading,
		})
		addCorner(pill, 13)
		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY_FONT,
			Text = selectedCommand.syntax,
			TextColor3 = COLORS.Muted,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 0, 20),
			Parent = heading,
		})

		makeInfoBlock("Description", selectedCommand.description or "", COLORS.Blue).Parent = detailsScroll
		makeInfoBlock("Example", selectedCommand.example or selectedCommand.syntax or "", COLORS.Gold).Parent = detailsScroll

		if selectedCommand.dangerous then
			makeInfoBlock(
				"Dangerous command",
				"This keeps the existing two-step server confirmation. Send the first command, then send confirm within 20 seconds.",
				COLORS.Red
			).Parent = detailsScroll
		end

		local inputs = selectedCommand.inputs or {}
		if #inputs > 0 then
			local inputHeader = create("TextLabel", {
				BackgroundTransparency = 1,
				Font = FONT,
				Text = "Required Inputs",
				TextColor3 = COLORS.Text,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -2, 0, 24),
				Parent = detailsScroll,
			})
			inputHeader.LayoutOrder = 20

			for _, input in ipairs(inputs) do
				local field = create("Frame", {
					BackgroundColor3 = Color3.fromRGB(7, 17, 36),
					BorderSizePixel = 0,
					Size = UDim2.new(1, -2, 0, 62),
					Parent = detailsScroll,
				})
				addCorner(field, 12)
				addStroke(field, COLORS.BorderSoft, 1, 0.25)
				create("TextLabel", {
					BackgroundTransparency = 1,
					Font = FONT,
					Text = input.label,
					TextColor3 = COLORS.Muted,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(14, 7),
					Size = UDim2.new(1, -28, 0, 18),
					Parent = field,
				})
				local box = create("TextBox", {
					BackgroundTransparency = 1,
					ClearTextOnFocus = false,
					Font = BODY_FONT,
					PlaceholderColor3 = COLORS.Faint,
					PlaceholderText = input.placeholder or "",
					Text = input.default or "",
					TextColor3 = COLORS.Text,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(14, 28),
					Size = UDim2.new(1, -28, 0, 26),
					Parent = field,
				})
				inputBoxes[input.key] = box
				box:GetPropertyChangedSignal("Text"):Connect(updateRunButton)
			end
		else
			makeInfoBlock("Required Inputs", "No inputs required.", COLORS.Green).Parent = detailsScroll
		end

		updateRunButton()
	end

	local function matchesCommand(command)
		if currentCategory ~= "All" and command.category ~= currentCategory then
			return false
		end
		local query = normalizeText(searchBox.Text)
		if query == "" then
			return true
		end
		return string.find(command.searchText, query, 1, true) ~= nil
	end

	local function renderCategoryButtons()
		for _, child in ipairs(categoryScroll:GetChildren()) do
			if child ~= categoryLayout then
				child:Destroy()
			end
		end
		categoryButtons = {}

		for index, category in ipairs(CATEGORIES) do
			local active = category == currentCategory
			local button = create("TextButton", {
				Name = category,
				AutoButtonColor = true,
				BackgroundColor3 = active and COLORS.Gold or COLORS.PanelRaised,
				BorderSizePixel = 0,
				Font = FONT,
				LayoutOrder = index,
				Text = category,
				TextColor3 = active and Color3.fromRGB(31, 24, 10) or COLORS.Text,
				TextSize = 12,
				Size = UDim2.fromOffset(math.max(82, (#category * 7) + 30), 34),
				Parent = categoryScroll,
			})
			addCorner(button, 17)
			addStroke(button, active and COLORS.GoldDark or COLORS.BorderSoft, 1, active and 0 or 0.25)
			categoryButtons[category] = button
			button.Activated:Connect(function()
				currentCategory = category
				pulseButton(button)
				renderCategoryButtons()
				if renderCommandList then
					renderCommandList()
				end
			end)
		end
	end

	renderCommandList = function()
		for _, child in ipairs(commandList:GetChildren()) do
			if child ~= commandLayout then
				child:Destroy()
			end
		end
		commandCards = {}

		local firstVisible = nil
		local selectedVisible = false
		local order = 0

		for _, command in ipairs(COMMANDS) do
			if matchesCommand(command) then
				order += 1
				firstVisible = firstVisible or command
				if command == selectedCommand then
					selectedVisible = true
				end

				local selected = command == selectedCommand
				local card = create("TextButton", {
					Name = command.id,
					AutoButtonColor = true,
					BackgroundColor3 = selected and COLORS.PanelRaised or Color3.fromRGB(8, 18, 38),
					BorderSizePixel = 0,
					LayoutOrder = order,
					Text = "",
					Size = UDim2.new(1, -6, 0, 82),
					Parent = commandList,
				})
				addCorner(card, 14)
				addStroke(card, command.dangerous and COLORS.Red or (selected and COLORS.Gold or COLORS.BorderSoft), selected and 2 or 1, selected and 0 or 0.25)

				local marker = create("TextLabel", {
					BackgroundColor3 = command.dangerous and COLORS.RedDark or COLORS.PanelRaised,
					BorderSizePixel = 0,
					Font = FONT,
					Text = command.marker or "*",
					TextColor3 = command.dangerous and COLORS.Text or COLORS.Gold,
					TextSize = 12,
					Position = UDim2.fromOffset(12, 14),
					Size = UDim2.fromOffset(42, 42),
					Parent = card,
				})
				addCorner(marker, 12)

				create("TextLabel", {
					BackgroundTransparency = 1,
					Font = FONT,
					Text = command.name,
					TextColor3 = command.dangerous and COLORS.Red or COLORS.Text,
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.fromOffset(64, 10),
					Size = UDim2.new(1, -154, 0, 22),
					Parent = card,
				})
				create("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.Code,
					Text = makeCommandText(command),
					TextColor3 = COLORS.Muted,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd,
					Position = UDim2.fromOffset(64, 34),
					Size = UDim2.new(1, -82, 0, 18),
					Parent = card,
				})
				local tag = create("TextLabel", {
					BackgroundColor3 = command.dangerous and COLORS.RedDark or Color3.fromRGB(14, 34, 63),
					BorderSizePixel = 0,
					Font = FONT,
					Text = command.category,
					TextColor3 = command.dangerous and COLORS.Text or COLORS.Blue,
					TextSize = 10,
					Position = UDim2.fromOffset(64, 56),
					Size = UDim2.fromOffset(132, 18),
					Parent = card,
				})
				addCorner(tag, 9)

				card.Activated:Connect(function()
					selectedCommand = command
					pendingDanger = nil
					pulseButton(card)
					renderCommandList()
					renderDetails()
				end)
				commandCards[command] = card
			end
		end

		if not selectedVisible then
			selectedCommand = firstVisible
			renderDetails()
		else
			updateRunButton()
		end
	end

	local function executePanelAction(command, values)
		if command.panelAction == "announcement" then
			local message = cleanSingleLine(values.message, 200)
			local duration = math.clamp(math.floor(numberValue(values, "duration", 10) or 10), 2, 30)
			requestEvent:FireServer(message, duration)
			return true
		elseif command.panelAction == "serverLuck" then
			local multiplier = math.floor(numberValue(values, "multiplier", 1) or 1)
			local seconds = math.clamp(math.floor(numberValue(values, "seconds", 600) or 600), 1, 86400)
			luckRequestEvent:FireServer(multiplier, seconds)
			return true
		elseif command.panelAction == "mainEvent" then
			local eventName = cleanSingleLine(values.eventName, 60)
			local seconds = math.clamp(math.floor(numberValue(values, "seconds", 600) or 600), 1, 86400)
			mainEventRequestEvent:FireServer(eventName, seconds)
			return true
		end
		return false
	end

	local function runSelected()
		if not selectedCommand then
			return
		end

		local values = valuesFromInputs()
		local preview = selectedCommand.build(values, false)
		pulseButton(runButton)

		-- Panel-only actions use their existing server remotes; each server
		-- handler validates AdminPermissions again before doing any work.
		if selectedCommand.panelAction then
			if executePanelAction(selectedCommand, values) then
				setStatus("Waiting for server confirmation...", COLORS.Muted)
			end
			return
		end

		-- Slash commands are sent as final command text. The server remote
		-- reuses the chat command parser and permission checks, so the client
		-- never becomes the source of authority.
		if selectedCommand.dangerous and not selectedCommand.confirmOnly then
			local now = os.clock()
			if pendingDanger
				and pendingDanger.commandId == selectedCommand.id
				and pendingDanger.baseCommand == preview
				and pendingDanger.expiresAt > now then
				adminCommandRequestEvent:FireServer(selectedCommand.build(values, true))
				setStatus("Confirm sent. Waiting for server confirmation...", COLORS.Muted)
				pendingDanger = nil
			else
				adminCommandRequestEvent:FireServer(preview)
				pendingDanger = {
					commandId = selectedCommand.id,
					baseCommand = preview,
					expiresAt = now + 20,
				}
				setStatus("First step sent. Confirm within 20 seconds.", COLORS.Gold)
			end
			updateRunButton()
			return
		end

		adminCommandRequestEvent:FireServer(preview)
		setStatus("Waiting for server confirmation...", COLORS.Muted)
	end

	runButton.Activated:Connect(runSelected)
	closeButton.Activated:Connect(function()
		gui.Enabled = false
		dim.Visible = false
	end)

	local function updateCanvas()
		local viewport = outerScroll.AbsoluteSize
		local scale = getDashboardScale(viewport)
		local scaledPanelWidth = math.floor(PANEL_WIDTH * scale)
		local scaledPanelHeight = math.floor(PANEL_HEIGHT * scale)

		mainScale.Scale = scale
		shadowScale.Scale = scale
		outerScroll.ScrollBarThickness = scale < 1 and 4 or 8

		local canvasX = math.max(viewport.X, scaledPanelWidth + PANEL_PADDING * 2)
		local canvasY = math.max(viewport.Y, scaledPanelHeight + PANEL_PADDING * 2)
		outerScroll.CanvasSize = UDim2.fromOffset(canvasX, canvasY)

		local panelX = math.floor((canvasX - scaledPanelWidth) * 0.5)
		local panelY = math.floor((canvasY - scaledPanelHeight) * 0.5)
		main.Position = UDim2.fromOffset(panelX, panelY)
		shadow.Position = UDim2.fromOffset(panelX + math.floor(10 * scale), panelY + math.floor(12 * scale))
	end

	outerScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateCanvas)
	end
	task.defer(updateCanvas)

	commandLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		commandList.CanvasSize = UDim2.fromOffset(0, commandLayout.AbsoluteContentSize.Y + 12)
	end)
	detailsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		detailsScroll.CanvasSize = UDim2.fromOffset(0, detailsLayout.AbsoluteContentSize.Y + 12)
	end)
	categoryLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		categoryScroll.CanvasSize = UDim2.fromOffset(categoryLayout.AbsoluteContentSize.X + 10, 0)
	end)

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		pendingDanger = nil
		renderCommandList()
	end)

	task.spawn(function()
		while gui.Parent do
			if pendingDanger and pendingDanger.expiresAt <= os.clock() then
				pendingDanger = nil
				if selectedCommand and selectedCommand.dangerous then
					setStatus("Confirmation window expired.", COLORS.Gold)
				end
			end
			if gui.Enabled then
				updateRunButton()
			end
			task.wait(0.25)
		end
	end)

	renderCategoryButtons()
	renderCommandList()
	renderDetails()
	setActiveTab("Commands")

	return gui
end

local dashboardGui = nil
if isAdmin then
	local ok, result = pcall(buildDashboard)
	if ok then
		dashboardGui = result
	else
		warnThrottled("dashboard_build_failed", "Admin dashboard failed to build: " .. tostring(result))
	end
end

local function setDashboardOpen(open)
	if not isAdmin then
		warnThrottled("admin_toggle_denied", "Admin panel blocked: AdminStatusRequest denied access for this player.")
		return false
	end
	if not dashboardGui then
		warnThrottled("admin_toggle_missing_dashboard", "Admin panel blocked: dashboard was not built; check admin remotes and startup warnings.")
		return false
	end

	dashboardGui.Enabled = open == true
	local dim = dashboardGui:FindFirstChild("Dim")
	if dim and dim:IsA("GuiObject") then
		dim.Visible = open == true
	end
	return true
end

local function toggleDashboard()
	if not dashboardGui then
		setDashboardOpen(true)
		return
	end
	setDashboardOpen(not dashboardGui.Enabled)
end

local adminLauncherGui = nil
local adminLauncherButton = nil
local adminLauncherViewportConnections = {}

local function applyAdminLauncherLayout()
	if not adminLauncherButton then
		return
	end

	local stack = HudLayout.getMobileRightStack(Responsive.getHudLayoutMode())
	if stack then
		adminLauncherButton.AnchorPoint = stack.admin.anchorPoint
		adminLauncherButton.Position = stack.admin.position
		adminLauncherButton.Size = stack.admin.size
		return
	end

	adminLauncherButton.AnchorPoint = Vector2.new(1, 0)
	adminLauncherButton.Position = UDim2.new(1, -16, 0, 96)
	adminLauncherButton.Size = UDim2.fromOffset(132, 40)
end

local function disconnectAdminLauncherViewportConnections()
	for _, connection in ipairs(adminLauncherViewportConnections) do
		connection:Disconnect()
	end
	table.clear(adminLauncherViewportConnections)
end

local function bindAdminLauncherViewportUpdates()
	disconnectAdminLauncherViewportConnections()

	local camera = workspace.CurrentCamera
	if camera then
		adminLauncherViewportConnections[#adminLauncherViewportConnections + 1] =
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyAdminLauncherLayout)
	end

	adminLauncherViewportConnections[#adminLauncherViewportConnections + 1] =
		workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindAdminLauncherViewportUpdates()
			applyAdminLauncherLayout()
		end)
end

updateAdminLauncherVisibility = function()
	if adminLauncherGui then
		adminLauncherGui.Enabled = isAdmin == true and dashboardGui ~= nil
		applyAdminLauncherLayout()
	end
end

local function createAdminLauncher()
	if not isAdmin or not dashboardGui then
		return
	end

	local existing = playerGui:FindFirstChild("GrandLineRushAdminLauncher")
	if existing then
		existing:Destroy()
	end

	adminLauncherGui = create("ScreenGui", {
		Name = "GrandLineRushAdminLauncher",
		DisplayOrder = 119,
		Enabled = isAdmin == true,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})

	local button = create("TextButton", {
		Name = "OpenAdminCommands",
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.PanelRaised,
		BorderSizePixel = 0,
		Font = FONT,
		Position = UDim2.new(1, -16, 0, 96),
		Size = UDim2.fromOffset(132, 40),
		Text = "Admin  P",
		TextColor3 = COLORS.Text,
		TextSize = 14,
		ZIndex = 20,
		Parent = adminLauncherGui,
	})
	addCorner(button, 12)
	addStroke(button, COLORS.Gold, 1, 0.18)

	adminLauncherButton = button
	applyAdminLauncherLayout()
	bindAdminLauncherViewportUpdates()

	button.Activated:Connect(toggleDashboard)
end

createAdminLauncher()
updateAdminLauncherVisibility()

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode ~= Enum.KeyCode.P then
		return
	end
	toggleDashboard()
end)

local function makeParticle(layer: GuiObject, worldPos: Vector2)
	local p = Instance.new("Frame")
	p.BorderSizePixel = 0
	p.BackgroundColor3 = Color3.fromHSV(math.random(), 0.85, 1)
	p.BackgroundTransparency = 0
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Size = UDim2.fromOffset(math.random(3, 6), math.random(3, 6))
	p.Position = UDim2.fromOffset(worldPos.X - layer.AbsolutePosition.X, worldPos.Y - layer.AbsolutePosition.Y)
	p.Rotation = math.random(-40, 40)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = p

	p.Parent = layer

	local dx = math.random(-18, 18)
	local dy = math.random(-32, -10)

	local t = TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = p.Position + UDim2.fromOffset(dx, dy),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		Rotation = p.Rotation + math.random(-30, 30),
	})

	t:Play()
	t.Completed:Connect(function()
		p:Destroy()
	end)
end

local function getTextEndWorldPos(lbl: TextLabel)
	local tb = lbl.TextBounds
	local startX = lbl.AbsolutePosition.X
	if lbl.TextXAlignment == Enum.TextXAlignment.Center then
		startX += (lbl.AbsoluteSize.X - tb.X) * 0.5
	elseif lbl.TextXAlignment == Enum.TextXAlignment.Right then
		startX += (lbl.AbsoluteSize.X - tb.X)
	end
	local x = startX + tb.X
	local y = lbl.AbsolutePosition.Y + lbl.AbsoluteSize.Y * 0.62
	return Vector2.new(x, y)
end

local function typewrite(textLabel: TextLabel, shadowLabel: TextLabel, fullText: string, layer: GuiObject)
	local origPos = textLabel.Position
	local origShadow = shadowLabel.Position

	textLabel.Text = ""
	shadowLabel.Text = ""

	for i = 1, #fullText do
		local sub = fullText:sub(1, i)
		textLabel.Text = sub
		shadowLabel.Text = sub

		RunService.RenderStepped:Wait()

		local jitter = UDim2.fromOffset(math.random(-2, 2), math.random(-1, 1))
		textLabel.Position = origPos + jitter
		shadowLabel.Position = origShadow + jitter

		makeParticle(layer, getTextEndWorldPos(textLabel))

		task.wait(0.018 + math.random() * 0.012)
	end

	textLabel.Position = origPos
	shadowLabel.Position = origShadow
end

local function showAnnouncement(payload)
	if type(payload) ~= "table" then return end

	local message = tostring(payload.message or "")
	local duration = tonumber(payload.duration) or 10
	duration = math.clamp(duration, 2, 30)

	local adminName = tostring(payload.adminName or "Admin")
	local adminUserId = tonumber(payload.adminUserId) or 0

	local frame = template:Clone()
	frame.Visible = true
	frame.Name = "Announcement"
	frame.Parent = template.Parent
	frame.LayoutOrder = -math.floor(os.clock() * 1000)

	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
	end
	uiScale.Scale = 0

	local textLB = frame:WaitForChild("TextLB")
	local shadow = textLB:WaitForChild("Shadow")
	local pfp = frame:WaitForChild("PFP")

	textLB.TextTransparency = 0
	shadow.TextTransparency = 0
	pfp.ImageTransparency = 1

	local particleLayer = frame:FindFirstChild("ParticleLayer")
	if not particleLayer then
		particleLayer = Instance.new("Frame")
		particleLayer.Name = "ParticleLayer"
		particleLayer.BackgroundTransparency = 1
		particleLayer.BorderSizePixel = 0
		particleLayer.Size = UDim2.fromScale(1, 1)
		particleLayer.Position = UDim2.fromScale(0, 0)
		particleLayer.ZIndex = 9999
		particleLayer.ClipsDescendants = false
		particleLayer.Parent = frame
	end

	pfp.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(adminUserId)

	TweenService:Create(uiScale, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(pfp, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 0 }):Play()

	local fullText = adminName .. " : " .. message

	task.spawn(function()
		typewrite(textLB, shadow, fullText, particleLayer)
		task.wait(duration)

		local out1 = TweenService:Create(uiScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		local out2 = TweenService:Create(textLB, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		local out3 = TweenService:Create(shadow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		local out4 = TweenService:Create(pfp, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 })

		out1:Play()
		out2:Play()
		out3:Play()
		out4:Play()

		out1.Completed:Wait()
		frame:Destroy()
	end)
end

local broadcastConnected = false
local function bindBroadcastEvent()
	if broadcastConnected then
		return
	end

	if not (broadcastEvent and broadcastEvent:IsA("RemoteEvent")) then
		broadcastEvent = ReplicatedStorage:FindFirstChild("AdminAnnouncementBroadcast")
	end
	if not (broadcastEvent and broadcastEvent:IsA("RemoteEvent")) then
		warnThrottled("broadcast_remote_missing", "AdminAnnouncementBroadcast is unavailable; admin announcements cannot display yet.")
		return
	end

	broadcastConnected = true
	broadcastEvent.OnClientEvent:Connect(showAnnouncement)
end

bindBroadcastEvent()
ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "AdminAnnouncementBroadcast" then
		task.defer(bindBroadcastEvent)
	end
end)
