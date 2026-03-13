local CollectionService = game:GetService("CollectionService")

local HazardUtils = {}

local function hasTruthyAttribute(instance, attributeName)
	local value = instance:GetAttribute(attributeName)

	if value == true then
		return true
	end

	if typeof(value) == "string" then
		local lowered = string.lower(value)
		return lowered == "true" or lowered == "1" or lowered == "yes"
	end

	return false
end

local function getHazardClassFromInstance(instance)
	local hazardClass = instance:GetAttribute("HazardClass")
	if typeof(hazardClass) == "string" and hazardClass ~= "" then
		return string.lower(hazardClass)
	end

	if CollectionService:HasTag(instance, "MajorHazard") or hasTruthyAttribute(instance, "MajorHazard") then
		return "major"
	end

	if CollectionService:HasTag(instance, "MinorHazard") or hasTruthyAttribute(instance, "MinorHazard") then
		return "minor"
	end

	return nil
end

local function getHazardTypeFromInstance(instance)
	local hazardType = instance:GetAttribute("HazardType")
	if typeof(hazardType) == "string" and hazardType ~= "" then
		return string.lower(hazardType)
	end

	if CollectionService:HasTag(instance, "WaveHazard") or hasTruthyAttribute(instance, "WaveHazard") then
		return "wave"
	end

	return nil
end

local function canFreezeInstance(instance)
	if CollectionService:HasTag(instance, "FreezableHazard")
		or hasTruthyAttribute(instance, "CanFreeze")
		or hasTruthyAttribute(instance, "Freezable") then
		return true
	end

	local canFreeze = instance:GetAttribute("CanFreeze")
	return canFreeze == true
end

local function getFreezeBehaviorFromInstance(instance)
	local freezeBehavior = instance:GetAttribute("FreezeBehavior")
	if typeof(freezeBehavior) == "string" and freezeBehavior ~= "" then
		return string.lower(freezeBehavior)
	end

	if CollectionService:HasTag(instance, "PauseOnFreeze") or hasTruthyAttribute(instance, "PauseOnFreeze") then
		return "pause"
	end

	if CollectionService:HasTag(instance, "SuppressOnFreeze") or hasTruthyAttribute(instance, "SuppressOnFreeze") then
		return "suppress"
	end

	return nil
end

function HazardUtils.GetHazardInfo(instance)
	local current = instance

	while current and current ~= workspace do
		local hazardClass = getHazardClassFromInstance(current)
		local hazardType = getHazardTypeFromInstance(current)
		local canFreeze = canFreezeInstance(current)
		local freezeBehavior = getFreezeBehaviorFromInstance(current)
		if hazardClass or hazardType or canFreeze or freezeBehavior then
			return current, hazardClass, hazardType, canFreeze, freezeBehavior
		end

		current = current.Parent
	end

	return nil, nil, nil, false, nil
end

function HazardUtils.IsMinorHazard(instance)
	local _, hazardClass = HazardUtils.GetHazardInfo(instance)
	return hazardClass == "minor"
end

function HazardUtils.IsMajorHazard(instance)
	local _, hazardClass = HazardUtils.GetHazardInfo(instance)
	return hazardClass == "major"
end

function HazardUtils.CanFreeze(instance)
	local _, _, _, canFreeze = HazardUtils.GetHazardInfo(instance)
	return canFreeze == true
end

function HazardUtils.GetHazardType(instance)
	local _, _, hazardType = HazardUtils.GetHazardInfo(instance)
	return hazardType
end

return HazardUtils
