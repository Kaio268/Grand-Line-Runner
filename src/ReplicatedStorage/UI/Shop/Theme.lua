local Theme = {}

Theme.Palette = {
	Ink = Color3.fromRGB(5, 14, 28),
	InkSoft = Color3.fromRGB(10, 24, 45),
	Board = Color3.fromRGB(11, 22, 41),
	BoardSoft = Color3.fromRGB(18, 35, 62),
	Panel = Color3.fromRGB(13, 28, 48),
	PanelSoft = Color3.fromRGB(21, 40, 71),
	Text = Color3.fromRGB(243, 246, 255),
	Muted = Color3.fromRGB(154, 176, 208),
	MutedSoft = Color3.fromRGB(111, 132, 164),
	Shadow = Color3.fromRGB(2, 6, 12),
	Gold = Color3.fromRGB(255, 207, 93),
	GoldSoft = Color3.fromRGB(255, 170, 72),
	Cyan = Color3.fromRGB(111, 233, 255),
	Emerald = Color3.fromRGB(108, 236, 176),
	Rose = Color3.fromRGB(255, 118, 148),
	Violet = Color3.fromRGB(171, 139, 255),
	Orange = Color3.fromRGB(255, 153, 74),
}

Theme.Fonts = {
	Display = Enum.Font.FredokaOne,
	Label = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	BodyStrong = Enum.Font.GothamBold,
	BodyRegular = Enum.Font.Gotham,
}

Theme.Assets = {
	RobuxIcon = "rbxasset://textures/ui/common/robux_small.png",
}

Theme.SurfaceThemes = {
	Gold = {
		fill = Color3.fromRGB(80, 45, 23),
		fillAlt = Color3.fromRGB(39, 20, 13),
		accent = Color3.fromRGB(255, 198, 85),
		accentSoft = Color3.fromRGB(255, 141, 71),
		stroke = Color3.fromRGB(255, 221, 131),
		glow = Color3.fromRGB(255, 173, 63),
	},
	Crimson = {
		fill = Color3.fromRGB(86, 22, 34),
		fillAlt = Color3.fromRGB(41, 12, 19),
		accent = Color3.fromRGB(255, 108, 126),
		accentSoft = Color3.fromRGB(255, 160, 101),
		stroke = Color3.fromRGB(255, 148, 171),
		glow = Color3.fromRGB(255, 92, 110),
	},
	Emerald = {
		fill = Color3.fromRGB(17, 70, 55),
		fillAlt = Color3.fromRGB(10, 33, 28),
		accent = Color3.fromRGB(116, 245, 183),
		accentSoft = Color3.fromRGB(61, 210, 175),
		stroke = Color3.fromRGB(144, 255, 212),
		glow = Color3.fromRGB(71, 229, 166),
	},
	Cyan = {
		fill = Color3.fromRGB(18, 58, 84),
		fillAlt = Color3.fromRGB(8, 27, 45),
		accent = Color3.fromRGB(119, 230, 255),
		accentSoft = Color3.fromRGB(68, 176, 255),
		stroke = Color3.fromRGB(163, 240, 255),
		glow = Color3.fromRGB(65, 177, 255),
	},
	Violet = {
		fill = Color3.fromRGB(53, 31, 97),
		fillAlt = Color3.fromRGB(23, 14, 45),
		accent = Color3.fromRGB(188, 153, 255),
		accentSoft = Color3.fromRGB(126, 113, 255),
		stroke = Color3.fromRGB(210, 188, 255),
		glow = Color3.fromRGB(149, 125, 255),
	},
	Orange = {
		fill = Color3.fromRGB(87, 41, 16),
		fillAlt = Color3.fromRGB(45, 19, 11),
		accent = Color3.fromRGB(255, 162, 83),
		accentSoft = Color3.fromRGB(255, 110, 63),
		stroke = Color3.fromRGB(255, 193, 131),
		glow = Color3.fromRGB(255, 123, 66),
	},
	Slate = {
		fill = Color3.fromRGB(43, 52, 78),
		fillAlt = Color3.fromRGB(17, 22, 37),
		accent = Color3.fromRGB(186, 205, 255),
		accentSoft = Color3.fromRGB(126, 148, 207),
		stroke = Color3.fromRGB(214, 226, 255),
		glow = Color3.fromRGB(130, 154, 225),
	},
}

Theme.BadgeThemes = {
	Limited = {
		fill = Color3.fromRGB(92, 17, 29),
		fillAlt = Color3.fromRGB(53, 12, 18),
		text = Color3.fromRGB(255, 194, 204),
		stroke = Color3.fromRGB(255, 112, 136),
	},
	["Best Value"] = {
		fill = Color3.fromRGB(84, 54, 10),
		fillAlt = Color3.fromRGB(48, 30, 8),
		text = Color3.fromRGB(255, 232, 164),
		stroke = Color3.fromRGB(255, 194, 88),
	},
	Popular = {
		fill = Color3.fromRGB(10, 63, 62),
		fillAlt = Color3.fromRGB(8, 38, 40),
		text = Color3.fromRGB(183, 255, 238),
		stroke = Color3.fromRGB(92, 237, 212),
	},
	New = {
		fill = Color3.fromRGB(32, 31, 92),
		fillAlt = Color3.fromRGB(15, 16, 48),
		text = Color3.fromRGB(220, 209, 255),
		stroke = Color3.fromRGB(159, 144, 255),
	},
	Default = {
		fill = Color3.fromRGB(37, 53, 80),
		fillAlt = Color3.fromRGB(20, 29, 47),
		text = Color3.fromRGB(210, 225, 255),
		stroke = Color3.fromRGB(122, 154, 203),
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
