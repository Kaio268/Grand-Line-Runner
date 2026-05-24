local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ChestVisuals = require(Modules:WaitForChild("GrandLineRushChestVisuals"))
local RewardOverheadBillboard = require(script.Parent:WaitForChild("RewardOverheadBillboard"))

local e = React.createElement

local PANEL_FILL = Color3.fromRGB(17, 26, 39)
local PANEL_FILL_SOFT = Color3.fromRGB(29, 43, 61)

local function blendColor(baseColor, accentColor, alpha)
	return baseColor:Lerp(accentColor, math.clamp(alpha or 0, 0, 1))
end

local function ChestOverheadBillboard(props)
	local entry = props.entry or {}
	local tierName = tostring(entry.tier or "Wooden")
	local tierLabel = ChestVisuals.GetTierLabel(tierName)
	local displayName = tostring(entry.displayName or tierLabel .. " Chest")
	local typeLabel = tostring(entry.typeLabel or "Chest")
	local helperText = tostring(entry.helperText or "Extract to open")
	local woodColor, metalColor = ChestVisuals.GetTierColors(tierName)

	return e(RewardOverheadBillboard, {
		adornee = entry.adornee,
		offsetY = tonumber(entry.offsetY) or 4.6,
		maxDistance = 58,
		title = displayName,
		typeLabel = typeLabel,
		metaLabel = tierLabel,
		helperText = helperText,
		remaining = tonumber(entry.remaining),
		totalSeconds = tonumber(entry.despawnSeconds),
		accentColor = metalColor,
		metaColor = metalColor,
		panelFill = PANEL_FILL,
		panelStart = blendColor(PANEL_FILL_SOFT, metalColor, 0.2),
		panelEnd = blendColor(PANEL_FILL, woodColor, 0.12),
	})
end

return ChestOverheadBillboard
