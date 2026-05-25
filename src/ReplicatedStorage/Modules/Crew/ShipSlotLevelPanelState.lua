local ShipSlotLevelPanelState = {}

local Attributes = {
	CurrentLevel = "ShipSlotLevelPanelCurrentLevel",
	CurrentXP = "ShipSlotLevelPanelCurrentXP",
	FoodCount = "ShipSlotLevelPanelFoodCount",
	HasFood = "ShipSlotLevelPanelHasFood",
	HasState = "ShipSlotLevelPanelHasState",
	IsMaxLevel = "ShipSlotLevelPanelIsMaxLevel",
	MaxLevel = "ShipSlotLevelPanelMaxLevel",
	NextLevelXP = "ShipSlotLevelPanelNextLevelXP",
	UpgradeCostText = "ShipSlotLevelPanelUpgradeCostText",
}

ShipSlotLevelPanelState.Attributes = Attributes
ShipSlotLevelPanelState.AttributeList = {
	Attributes.HasState,
	Attributes.CurrentLevel,
	Attributes.CurrentXP,
	Attributes.NextLevelXP,
	Attributes.MaxLevel,
	Attributes.HasFood,
	Attributes.FoodCount,
	Attributes.IsMaxLevel,
	Attributes.UpgradeCostText,
}

local function isSurfaceGui(instance)
	return typeof(instance) == "Instance" and instance:IsA("SurfaceGui")
end

local function setAttributeIfChanged(instance, attributeName, value)
	if instance:GetAttribute(attributeName) == value then
		return
	end

	instance:SetAttribute(attributeName, value)
end

local function nonNegativeInteger(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function optionalNonNegativeInteger(value)
	if value == nil then
		return nil
	end

	return nonNegativeInteger(value)
end

local function positiveInteger(value, fallback)
	return math.max(1, math.floor(tonumber(value) or fallback or 1))
end

local function cleanText(value)
	local text = tostring(value or "")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return text
end

local function normalizeState(state)
	if typeof(state) ~= "table" then
		return nil
	end

	local currentLevel = positiveInteger(state.CurrentLevel or state.Level, 1)
	local maxLevel = positiveInteger(state.MaxLevel, currentLevel)
	local isMaxLevel = state.IsMaxLevel == true or currentLevel >= maxLevel
	local foodCount = optionalNonNegativeInteger(state.FoodCount)
	local upgradeCostText = cleanText(state.UpgradeCostText)

	return {
		CurrentLevel = currentLevel,
		CurrentXP = nonNegativeInteger(state.CurrentXP),
		FoodCount = foodCount,
		HasFood = state.HasFood == true,
		IsMaxLevel = isMaxLevel,
		MaxLevel = maxLevel,
		NextLevelXP = nonNegativeInteger(state.NextLevelXP),
		UpgradeCostText = upgradeCostText,
	}
end

function ShipSlotLevelPanelState.Publish(surfaceGui, state)
	if not isSurfaceGui(surfaceGui) then
		return nil
	end

	local normalized = normalizeState(state)
	if not normalized then
		ShipSlotLevelPanelState.Clear(surfaceGui)
		return nil
	end

	setAttributeIfChanged(surfaceGui, Attributes.CurrentLevel, normalized.CurrentLevel)
	setAttributeIfChanged(surfaceGui, Attributes.CurrentXP, normalized.CurrentXP)
	setAttributeIfChanged(surfaceGui, Attributes.NextLevelXP, normalized.NextLevelXP)
	setAttributeIfChanged(surfaceGui, Attributes.MaxLevel, normalized.MaxLevel)
	setAttributeIfChanged(surfaceGui, Attributes.HasFood, normalized.HasFood)
	setAttributeIfChanged(surfaceGui, Attributes.FoodCount, normalized.FoodCount)
	setAttributeIfChanged(surfaceGui, Attributes.IsMaxLevel, normalized.IsMaxLevel)
	setAttributeIfChanged(surfaceGui, Attributes.UpgradeCostText, normalized.UpgradeCostText)
	setAttributeIfChanged(surfaceGui, Attributes.HasState, true)

	return normalized
end

function ShipSlotLevelPanelState.Clear(surfaceGui)
	if not isSurfaceGui(surfaceGui) then
		return
	end

	setAttributeIfChanged(surfaceGui, Attributes.HasState, false)
	for _, attributeName in ipairs({
		Attributes.CurrentLevel,
		Attributes.CurrentXP,
		Attributes.NextLevelXP,
		Attributes.MaxLevel,
		Attributes.HasFood,
		Attributes.FoodCount,
		Attributes.IsMaxLevel,
		Attributes.UpgradeCostText,
	}) do
		if surfaceGui:GetAttribute(attributeName) ~= nil then
			surfaceGui:SetAttribute(attributeName, nil)
		end
	end
end

function ShipSlotLevelPanelState.Read(surfaceGui)
	if not isSurfaceGui(surfaceGui) or surfaceGui:GetAttribute(Attributes.HasState) ~= true then
		return nil
	end

	return normalizeState({
		CurrentLevel = surfaceGui:GetAttribute(Attributes.CurrentLevel),
		CurrentXP = surfaceGui:GetAttribute(Attributes.CurrentXP),
		FoodCount = surfaceGui:GetAttribute(Attributes.FoodCount),
		HasFood = surfaceGui:GetAttribute(Attributes.HasFood),
		IsMaxLevel = surfaceGui:GetAttribute(Attributes.IsMaxLevel),
		MaxLevel = surfaceGui:GetAttribute(Attributes.MaxLevel),
		NextLevelXP = surfaceGui:GetAttribute(Attributes.NextLevelXP),
		UpgradeCostText = surfaceGui:GetAttribute(Attributes.UpgradeCostText),
	})
end

function ShipSlotLevelPanelState.FormatLevelText(state)
	local normalized = normalizeState(state)
	if not normalized then
		return ""
	end

	return "Current Level: " .. tostring(normalized.CurrentLevel)
end

function ShipSlotLevelPanelState.FormatXPText(state)
	local normalized = normalizeState(state)
	if not normalized then
		return ""
	end

	if normalized.IsMaxLevel then
		return "Max Level"
	end

	local text = string.format("XP: %d / %d", normalized.CurrentXP, normalized.NextLevelXP)
	if normalized.HasFood then
		text ..= " | Auto-feed"
	else
		text ..= " | No Food"
	end

	return text
end

function ShipSlotLevelPanelState.FormatProgressText(state)
	return ShipSlotLevelPanelState.FormatXPText(state)
end

function ShipSlotLevelPanelState.FormatFoodText(state)
	local normalized = normalizeState(state)
	if not normalized then
		return ""
	end

	if normalized.FoodCount ~= nil then
		return "Food: " .. tostring(normalized.FoodCount)
	end

	return if normalized.HasFood then "Food: Ready" else "Food: 0"
end

function ShipSlotLevelPanelState.FormatNextLevelText(state)
	local normalized = normalizeState(state)
	if not normalized then
		return ""
	end

	if normalized.IsMaxLevel then
		return "Max Level"
	end

	return "Next Level: " .. tostring(normalized.NextLevelXP) .. " XP"
end

function ShipSlotLevelPanelState.FormatUpgradeCostText(state)
	local normalized = normalizeState(state)
	if not normalized then
		return ""
	end

	if normalized.IsMaxLevel then
		return "Maxed"
	end

	return normalized.UpgradeCostText
end

function ShipSlotLevelPanelState.GetProgressRatio(state)
	local normalized = normalizeState(state)
	if not normalized then
		return 0
	end

	if normalized.IsMaxLevel then
		return 1
	end

	if normalized.NextLevelXP <= 0 then
		return 0
	end

	return math.clamp(normalized.CurrentXP / normalized.NextLevelXP, 0, 1)
end

return ShipSlotLevelPanelState
