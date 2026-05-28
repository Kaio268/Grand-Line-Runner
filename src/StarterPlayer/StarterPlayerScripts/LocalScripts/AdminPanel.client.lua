local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Responsive = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Responsive"))

local function safeWait(parent, name)
	local obj = parent:WaitForChild(name, 15)
	if not obj then
		error(("Missing %s in %s"):format(name, parent:GetFullName()))
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

local adminStatusFunction = safeWait(ReplicatedStorage, "AdminStatusRequest")
local isAdmin = false
if adminStatusFunction:IsA("RemoteFunction") then
	local ok, result = pcall(function()
		return adminStatusFunction:InvokeServer()
	end)
	isAdmin = ok and result == true
end

local broadcastEvent = safeWait(ReplicatedStorage, "AdminAnnouncementBroadcast")

local playerGui = safeWait(player, "PlayerGui")
local framesFolder = playerGui:FindFirstChild("Frames")
local hud = safeWait(playerGui, "HUD")
local adminInfo = safeWait(hud, "AdminInfo")
local template = safeWait(adminInfo, "AnnTemplate")

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
	"Inventory",
	"Gifts",
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

local function buildDashboard()
	local requestEvent = safeWait(ReplicatedStorage, "AdminAnnouncementRequest")
	local luckRequestEvent = safeWait(ReplicatedStorage, "AdminLuckRequest")
	local mainEventRequestEvent = safeWait(ReplicatedStorage, "AdminMainEventRequest")
	local adminCommandRequestEvent = safeWait(ReplicatedStorage, "AdminCommandRequest")
	local adminCommandFeedbackEvent = safeWait(ReplicatedStorage, "AdminCommandFeedback")
	local adminRosterFunction = safeWait(ReplicatedStorage, "AdminRosterRequest")
	local adminTesterRoleFunction = safeWait(ReplicatedStorage, "AdminTesterRoleRequest")
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
		Size = UDim2.new(1, -650, 0, 32),
		Parent = header,
	})

	create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = "Organized command dashboard",
		TextColor3 = COLORS.Muted,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(73, 42),
		Size = UDim2.new(1, -650, 0, 22),
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
		Position = UDim2.new(1, -558, 0, 18),
		Size = UDim2.fromOffset(482, 38),
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
		Text = "Admins",
		TextColor3 = COLORS.Text,
		TextSize = 11,
		Size = UDim2.fromOffset(88, 30),
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
		Text = "All Players",
		TextColor3 = COLORS.Text,
		TextSize = 11,
		Size = UDim2.fromOffset(126, 30),
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
		Size = UDim2.fromOffset(96, 30),
		Parent = tabBar,
	})
	addCorner(tabButtons.Testers, 10)

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
	local renderCommandList
	local renderRoster
	local requestRoster
	local requestTesterRoleChange

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

	local function updateTabButtons()
		for tabName, button in pairs(tabButtons) do
			setButtonStyle(button, tabName == currentTab, false)
		end
	end

	setActiveTab = function(tabName)
		if tabName == "Admins" or tabName == "AllPlayers" or tabName == "Testers" then
			currentTab = tabName
		else
			currentTab = "Commands"
		end
		commandView.Visible = currentTab == "Commands"
		rosterView.Visible = currentTab ~= "Commands"
		updateTabButtons()

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
		local hasAction = typeof(actionSpec) == "table" and actionSpec.Label ~= nil

		local row = create("Frame", {
			BackgroundColor3 = Color3.fromRGB(8, 18, 38),
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1, -4, 0, if hasAction then 96 else 82),
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
			local actionButton = create("TextButton", {
				Name = tostring(actionSpec.Action or "TesterRoleAction"),
				AutoButtonColor = actionSpec.Enabled ~= false,
				BackgroundColor3 = actionSpec.Dangerous == true and COLORS.RedDark or COLORS.Gold,
				BorderSizePixel = 0,
				Font = FONT,
				Text = cleanSingleLine(actionSpec.Label, 24),
				TextColor3 = actionSpec.Dangerous == true and COLORS.Text or Color3.fromRGB(31, 24, 10),
				TextSize = 11,
				Position = UDim2.new(1, -138, 0, 69),
				Size = UDim2.fromOffset(124, 22),
				Parent = row,
			})
			addCorner(actionButton, 10)
			addStroke(actionButton, actionSpec.Dangerous == true and COLORS.Red or COLORS.GoldDark, 1, 0.2)

			actionButton.Activated:Connect(function()
				if actionSpec.Enabled == false or testerRoleLoading then
					return
				end
				pulseButton(actionButton)
				if requestTesterRoleChange then
					requestTesterRoleChange(tostring(actionSpec.Action or ""), tostring(actionSpec.Target or userId))
				end
			end)
		end
	end

	renderRoster = function(payload)
		clearRosterList(superAdminRoster)
		clearRosterList(adminRoster)
		clearRosterList(allPlayersRoster)
		clearRosterList(testerRoster)

		local function setRosterPanels(adminsVisible, allPlayersVisible, testersVisible, showTesterAdd)
			superAdminRoster.Panel.Visible = adminsVisible
			adminRoster.Panel.Visible = adminsVisible
			allPlayersRoster.Panel.Visible = allPlayersVisible
			testerAddBar.Visible = showTesterAdd
			testerRoster.Panel.Visible = testersVisible

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
				elseif currentTab == "AllPlayers" then "All Players"
				else "Admin Roster"
			setRosterPanels(currentTab == "Admins", currentTab == "AllPlayers", currentTab == "Testers", false)

			local targetRoster = if currentTab == "Testers"
				then testerRoster
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

		if currentTab == "AllPlayers" then
			rosterTitleLabel.Text = "All Players"
			setRosterPanels(false, true, false, false)
			allPlayersRoster.CountLabel.Text = ("%d online"):format(#allPlayers)
			if #allPlayers == 0 then
				makeRosterEmpty(allPlayersRoster, "No players are currently in this server.")
			else
				for index, entry in ipairs(allPlayers) do
					local actionSpec = nil
					if viewerIsSuperAdmin and entry.CanAddTester == true then
						actionSpec = {
							Label = "Add Tester",
							Action = "AddTester",
							Target = tostring(entry.UserId),
							Dangerous = false,
						}
					elseif viewerIsSuperAdmin and entry.CanRemoveTester == true then
						actionSpec = {
							Label = "Remove Tester",
							Action = "RemoveTester",
							Target = tostring(entry.UserId),
							Dangerous = true,
						}
					end
					makeRosterRow(allPlayersRoster, entry, index, "Player", actionSpec)
				end
			end
			return
		end

		if currentTab == "Testers" then
			rosterTitleLabel.Text = "Testers"
			setRosterPanels(false, false, true, viewerIsSuperAdmin)
			testerRoster.CountLabel.Text = ("%d listed"):format(#testers)
			if #testers == 0 then
				makeRosterEmpty(testerRoster, "No testers are currently configured.")
			else
				for index, entry in ipairs(testers) do
					local actionSpec = nil
					if viewerIsSuperAdmin and entry.CanRemoveTester == true then
						actionSpec = {
							Label = "Remove Tester",
							Action = "RemoveTester",
							Target = tostring(entry.UserId),
							Dangerous = true,
						}
					end
					makeRosterRow(testerRoster, entry, index, "Tester", actionSpec)
				end
			end
			return
		end

		rosterTitleLabel.Text = "Admin Roster"
		setRosterPanels(true, false, false, false)
		superAdminRoster.CountLabel.Text = ("%d listed"):format(#superAdmins)
		adminRoster.CountLabel.Text = ("%d listed"):format(#admins)

		if #superAdmins == 0 then
			makeRosterEmpty(superAdminRoster, "No SuperAdmins listed.")
		else
			for index, entry in ipairs(superAdmins) do
				makeRosterRow(superAdminRoster, entry, index, "SuperAdmin")
			end
		end

		if #admins == 0 then
			makeRosterEmpty(adminRoster, "No Admins listed.")
		else
			for index, entry in ipairs(admins) do
				makeRosterRow(adminRoster, entry, index, "Admin")
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
		if rosterRefreshQueued or currentTab == "Commands" or not gui.Enabled then
			return
		end

		rosterRefreshQueued = true
		rosterUpdatedLabel.Text = cleanSingleLine(reason or "Roster changed.", 120)
		task.delay(0.2, function()
			rosterRefreshQueued = false
			if gui.Parent and gui.Enabled and currentTab ~= "Commands" and requestRoster then
				requestRoster()
			end
		end)
	end

	requestTesterRoleChange = function(action, target)
		if testerRoleLoading then
			return
		end

		action = cleanSingleLine(action, 24)
		target = cleanSingleLine(target, 80)
		if target == "" then
			rosterUpdatedLabel.Text = "Enter a UserId or username."
			return
		end

		if not adminTesterRoleFunction:IsA("RemoteFunction") then
			rosterUpdatedLabel.Text = "Tester role remote unavailable."
			return
		end

		testerRoleLoading = true
		rosterUpdatedLabel.Text = "Updating tester role..."

		task.spawn(function()
			local ok, payload = pcall(function()
				return adminTesterRoleFunction:InvokeServer(action, target)
			end)

			testerRoleLoading = false
			if not gui.Parent then
				return
			end

			local message = "Tester role update failed."
			if ok and typeof(payload) == "table" then
				message = cleanSingleLine(payload.Message, 120)
				if message == "" then
					message = if payload.Success == false then "Tester role update failed." else "Tester role updated."
				end
				if payload.Success ~= false and typeof(payload.Roster) == "table" then
					lastRosterRefresh = os.clock()
					lastRosterPayload = payload.Roster
					if action == "AddTester" then
						testerAddBox.Text = ""
					end
					renderRoster(payload.Roster)
				elseif payload.Success ~= false then
					requestRoster()
				end
			end

			rosterUpdatedLabel.Text = message
		end)
	end

	rosterRefreshButton.Activated:Connect(function()
		pulseButton(rosterRefreshButton)
		requestRoster()
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
				isAdmin = payload.IsAdmin
				if not isAdmin then
					gui.Enabled = false
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
	dashboardGui = buildDashboard()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode ~= Enum.KeyCode.P then
		return
	end
	if not isAdmin or not dashboardGui then
		return
	end

	dashboardGui.Enabled = not dashboardGui.Enabled
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

broadcastEvent.OnClientEvent:Connect(showAnnouncement)
