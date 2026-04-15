local Theme = {}

Theme.Palette = {
	Ink = Color3.fromRGB(30, 42, 56),
	InkSoft = Color3.fromRGB(36, 52, 71),
	Board = Color3.fromRGB(28, 41, 56),
	BoardSoft = Color3.fromRGB(42, 60, 80),
	Panel = Color3.fromRGB(44, 62, 80),
	PanelSoft = Color3.fromRGB(55, 75, 96),
	Text = Color3.fromRGB(230, 230, 230),
	Muted = Color3.fromRGB(184, 193, 204),
	MutedSoft = Color3.fromRGB(122, 134, 150),
	Shadow = Color3.fromRGB(12, 18, 25),
	Gold = Color3.fromRGB(212, 175, 55),
	GoldSoft = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	Cyan = Color3.fromRGB(126, 209, 255),
	Emerald = Color3.fromRGB(129, 232, 168),
	Rose = Color3.fromRGB(255, 132, 150),
	Violet = Color3.fromRGB(179, 153, 255),
	Orange = Color3.fromRGB(255, 169, 98),
	Border = Color3.fromRGB(212, 175, 55),
	BorderSoft = Color3.fromRGB(140, 107, 31),
	ButtonInactive = Color3.fromRGB(42, 58, 77),
	ButtonActive = Color3.fromRGB(58, 47, 18),
	CloseFill = Color3.fromRGB(186, 86, 100),
	CloseStroke = Color3.fromRGB(140, 107, 31),
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
}

Theme.SurfaceThemes = {
	Gold = {
		fill = Color3.fromRGB(51, 40, 22),
		fillAlt = Color3.fromRGB(36, 29, 18),
		accent = Color3.fromRGB(212, 175, 55),
		accentSoft = Color3.fromRGB(242, 209, 107),
		stroke = Color3.fromRGB(242, 209, 107),
		glow = Color3.fromRGB(212, 175, 55),
	},
	Crimson = {
		fill = Color3.fromRGB(71, 34, 40),
		fillAlt = Color3.fromRGB(42, 23, 28),
		accent = Color3.fromRGB(228, 118, 128),
		accentSoft = Color3.fromRGB(244, 161, 148),
		stroke = Color3.fromRGB(255, 183, 168),
		glow = Color3.fromRGB(228, 118, 128),
	},
	Emerald = {
		fill = Color3.fromRGB(36, 67, 52),
		fillAlt = Color3.fromRGB(27, 46, 37),
		accent = Color3.fromRGB(123, 222, 161),
		accentSoft = Color3.fromRGB(160, 240, 193),
		stroke = Color3.fromRGB(186, 252, 214),
		glow = Color3.fromRGB(123, 222, 161),
	},
	Cyan = {
		fill = Color3.fromRGB(32, 57, 77),
		fillAlt = Color3.fromRGB(25, 44, 60),
		accent = Color3.fromRGB(126, 209, 255),
		accentSoft = Color3.fromRGB(177, 228, 255),
		stroke = Color3.fromRGB(206, 241, 255),
		glow = Color3.fromRGB(126, 209, 255),
	},
	Violet = {
		fill = Color3.fromRGB(54, 47, 83),
		fillAlt = Color3.fromRGB(39, 33, 62),
		accent = Color3.fromRGB(186, 168, 255),
		accentSoft = Color3.fromRGB(217, 205, 255),
		stroke = Color3.fromRGB(229, 220, 255),
		glow = Color3.fromRGB(186, 168, 255),
	},
	Orange = {
		fill = Color3.fromRGB(77, 49, 29),
		fillAlt = Color3.fromRGB(51, 34, 23),
		accent = Color3.fromRGB(244, 177, 110),
		accentSoft = Color3.fromRGB(255, 206, 149),
		stroke = Color3.fromRGB(255, 223, 183),
		glow = Color3.fromRGB(244, 177, 110),
	},
	Slate = {
		fill = Color3.fromRGB(47, 62, 79),
		fillAlt = Color3.fromRGB(34, 45, 60),
		accent = Color3.fromRGB(188, 205, 223),
		accentSoft = Color3.fromRGB(217, 227, 237),
		stroke = Color3.fromRGB(230, 236, 242),
		glow = Color3.fromRGB(188, 205, 223),
	},
}

Theme.BadgeThemes = {
	Limited = {
		fill = Color3.fromRGB(64, 33, 38),
		fillAlt = Color3.fromRGB(47, 24, 30),
		text = Color3.fromRGB(236, 203, 210),
		stroke = Color3.fromRGB(207, 136, 149),
	},
	["Best Value"] = {
		fill = Color3.fromRGB(59, 48, 27),
		fillAlt = Color3.fromRGB(45, 37, 21),
		text = Color3.fromRGB(242, 226, 167),
		stroke = Color3.fromRGB(212, 175, 55),
	},
	Popular = {
		fill = Color3.fromRGB(35, 61, 61),
		fillAlt = Color3.fromRGB(29, 47, 47),
		text = Color3.fromRGB(190, 224, 220),
		stroke = Color3.fromRGB(126, 209, 255),
	},
	New = {
		fill = Color3.fromRGB(49, 49, 76),
		fillAlt = Color3.fromRGB(39, 38, 61),
		text = Color3.fromRGB(226, 222, 242),
		stroke = Color3.fromRGB(188, 205, 223),
	},
	Default = {
		fill = Color3.fromRGB(44, 62, 80),
		fillAlt = Color3.fromRGB(34, 49, 66),
		text = Color3.fromRGB(230, 230, 230),
		stroke = Color3.fromRGB(140, 107, 31),
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

return Theme
