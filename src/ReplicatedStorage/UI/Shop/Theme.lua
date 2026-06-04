local Theme = {}

-- Retheme: black panels + gold accents to match the SELL / QUEST / GIFTS / INDEX menus.
Theme.Palette = {
	Ink = Color3.fromRGB(8, 8, 9),
	InkSoft = Color3.fromRGB(16, 16, 19),
	Board = Color3.fromRGB(10, 10, 12),
	BoardSoft = Color3.fromRGB(18, 18, 21),
	Panel = Color3.fromRGB(20, 20, 24),
	PanelSoft = Color3.fromRGB(28, 28, 33),
	Text = Color3.fromRGB(235, 235, 235),
	Muted = Color3.fromRGB(190, 194, 202),
	MutedSoft = Color3.fromRGB(140, 142, 150),
	Shadow = Color3.fromRGB(0, 0, 0),
	Gold = Color3.fromRGB(228, 190, 78),
	GoldSoft = Color3.fromRGB(255, 224, 120),
	GoldShadow = Color3.fromRGB(150, 112, 42),
	Cyan = Color3.fromRGB(126, 209, 255),
	Emerald = Color3.fromRGB(129, 232, 168),
	Rose = Color3.fromRGB(255, 132, 150),
	Violet = Color3.fromRGB(179, 153, 255),
	Orange = Color3.fromRGB(255, 169, 98),
	Border = Color3.fromRGB(255, 224, 120),
	BorderSoft = Color3.fromRGB(150, 112, 42),
	ButtonInactive = Color3.fromRGB(20, 20, 24),
	ButtonActive = Color3.fromRGB(58, 47, 18),
	TabFill = Color3.fromRGB(20, 20, 24),
	TabFillHover = Color3.fromRGB(30, 30, 35),
	CloseFill = Color3.fromRGB(200, 0, 9),
	CloseStroke = Color3.fromRGB(150, 112, 42),
}

Theme.Fonts = {
	Display = Enum.Font.GothamBold,
	Label = Enum.Font.GothamBold,
	Body = Enum.Font.Gotham,
	BodyStrong = Enum.Font.GothamBold,
	BodyRegular = Enum.Font.Gotham,
}

Theme.Assets = {
	RobuxIcon = "rbxasset://textures/ui/common/robux_small.png",
	ShopBackground = "rbxassetid://105877304453866",
	BeliIcon = "rbxassetid://76300573750363",
	SpeedBoostIcon = "rbxassetid://96331945137652",
	BeliBoostIcon = "rbxassetid://123727379614328",
	LuckBoostIcon = "rbxassetid://99305009492305",
	StoreIcon = "rbxassetid://87636652264235",
	IndexIcon = "rbxassetid://77322372470208",
	SettingsIcon = "rbxassetid://125384263224347",
	QuestIcon = "rbxassetid://78184151901761",
	RebirthIcon = "rbxassetid://116163404622119",
}

-- All surfaces share a black card fill now; each keeps its accent colour for variety
-- (matches the INDEX cards: black panel, coloured accent/stroke).
local CARD_FILL = Color3.fromRGB(12, 12, 14)
local CARD_FILL_ALT = Color3.fromRGB(8, 8, 9)
Theme.SurfaceThemes = {
	Gold = {
		fill = CARD_FILL,
		fillAlt = CARD_FILL_ALT,
		accent = Color3.fromRGB(228, 190, 78),
		accentSoft = Color3.fromRGB(255, 224, 120),
		stroke = Color3.fromRGB(255, 224, 120),
		glow = Color3.fromRGB(228, 190, 78),
	},
	Crimson = {
		fill = CARD_FILL,
		fillAlt = CARD_FILL_ALT,
		accent = Color3.fromRGB(228, 118, 128),
		accentSoft = Color3.fromRGB(244, 161, 148),
		stroke = Color3.fromRGB(255, 183, 168),
		glow = Color3.fromRGB(228, 118, 128),
	},
	Emerald = {
		fill = CARD_FILL,
		fillAlt = CARD_FILL_ALT,
		accent = Color3.fromRGB(123, 222, 161),
		accentSoft = Color3.fromRGB(160, 240, 193),
		stroke = Color3.fromRGB(186, 252, 214),
		glow = Color3.fromRGB(123, 222, 161),
	},
	Cyan = {
		fill = CARD_FILL,
		fillAlt = CARD_FILL_ALT,
		accent = Color3.fromRGB(126, 209, 255),
		accentSoft = Color3.fromRGB(177, 228, 255),
		stroke = Color3.fromRGB(206, 241, 255),
		glow = Color3.fromRGB(126, 209, 255),
	},
	Violet = {
		fill = CARD_FILL,
		fillAlt = CARD_FILL_ALT,
		accent = Color3.fromRGB(186, 168, 255),
		accentSoft = Color3.fromRGB(217, 205, 255),
		stroke = Color3.fromRGB(229, 220, 255),
		glow = Color3.fromRGB(186, 168, 255),
	},
	Orange = {
		fill = CARD_FILL,
		fillAlt = CARD_FILL_ALT,
		accent = Color3.fromRGB(244, 177, 110),
		accentSoft = Color3.fromRGB(255, 206, 149),
		stroke = Color3.fromRGB(255, 223, 183),
		glow = Color3.fromRGB(244, 177, 110),
	},
	Slate = {
		fill = CARD_FILL,
		fillAlt = CARD_FILL_ALT,
		accent = Color3.fromRGB(188, 205, 223),
		accentSoft = Color3.fromRGB(217, 227, 237),
		stroke = Color3.fromRGB(230, 236, 242),
		glow = Color3.fromRGB(188, 205, 223),
	},
}

Theme.BadgeThemes = {
	Limited = {
		fill = Color3.fromRGB(16, 16, 19),
		fillAlt = Color3.fromRGB(10, 10, 12),
		text = Color3.fromRGB(236, 203, 210),
		stroke = Color3.fromRGB(207, 136, 149),
	},
	["Best Value"] = {
		fill = Color3.fromRGB(16, 16, 19),
		fillAlt = Color3.fromRGB(10, 10, 12),
		text = Color3.fromRGB(255, 224, 120),
		stroke = Color3.fromRGB(228, 190, 78),
	},
	Popular = {
		fill = Color3.fromRGB(16, 16, 19),
		fillAlt = Color3.fromRGB(10, 10, 12),
		text = Color3.fromRGB(190, 224, 220),
		stroke = Color3.fromRGB(126, 209, 255),
	},
	New = {
		fill = Color3.fromRGB(16, 16, 19),
		fillAlt = Color3.fromRGB(10, 10, 12),
		text = Color3.fromRGB(226, 222, 242),
		stroke = Color3.fromRGB(188, 205, 223),
	},
	Default = {
		fill = Color3.fromRGB(16, 16, 19),
		fillAlt = Color3.fromRGB(10, 10, 12),
		text = Color3.fromRGB(235, 235, 235),
		stroke = Color3.fromRGB(150, 112, 42),
	},
}

local function formatNumber(value)
	local number = math.floor(tonumber(value) or 0)
	local formatted = tostring(math.abs(number))

	while true do
		local updated, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = updated
		if count == 0 then
			break
		end
	end

	return number < 0 and ("-" .. formatted) or formatted
end

function Theme.getSurfaceTheme(themeKey)
	return Theme.SurfaceThemes[themeKey] or Theme.SurfaceThemes.Cyan
end

function Theme.getBadgeTheme(variant)
	return Theme.BadgeThemes[variant] or Theme.BadgeThemes.Default
end

function Theme.formatPrice(value)
	if type(value) == "number" then
		return formatNumber(value)
	end

	local numeric = tonumber(value)
	if numeric ~= nil then
		return formatNumber(numeric)
	end

	return tostring(value or "--")
end

function Theme.getItemIcon(item)
	if type(item) ~= "table" then
		return Theme.Assets.StoreIcon
	end

	local explicitIcon = tostring(item.iconImage or "")
	if explicitIcon ~= "" then
		return explicitIcon
	end

	local titleLower = string.lower(tostring(item.title or ""))
	local sectionKey = string.lower(tostring(item.sectionKey or ""))

	if sectionKey == "currency" then
		return Theme.Assets.BeliIcon
	end

	if sectionKey == "boosts" or sectionKey == "boosts-chests" then
		if string.find(titleLower, "luck", 1, true) or string.find(titleLower, "drop", 1, true) then
			return Theme.Assets.LuckBoostIcon
		end
		if string.find(titleLower, "speed", 1, true) or string.find(titleLower, "xp", 1, true) then
			return Theme.Assets.SpeedBoostIcon
		end
		return Theme.Assets.BeliBoostIcon
	end

	if sectionKey == "fruit-chests" then
		return Theme.Assets.RebirthIcon
	end

	if sectionKey == "protection" or sectionKey == "crew-protection" then
		return Theme.Assets.SettingsIcon
	end

	if sectionKey == "raiding" then
		return Theme.Assets.QuestIcon
	end

	if sectionKey == "cosmetics" then
		return Theme.Assets.IndexIcon
	end

	if sectionKey == "vip" or sectionKey == "gamepasses" then
		return Theme.Assets.IndexIcon
	end

	if sectionKey == "products" then
		return Theme.Assets.SettingsIcon
	end

	if sectionKey == "utility" then
		return Theme.Assets.QuestIcon
	end

	if sectionKey == "bundles" then
		return Theme.Assets.StoreIcon
	end

	return Theme.Assets.RebirthIcon
end

return Theme
