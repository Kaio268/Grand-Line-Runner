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

function HazardUtils.GetHazardInfo(instance)
	local current = instance

	while current and current ~= workspace do
		local hazardClass = getHazardClassFromInstance(current)
		if hazardClass then
			return current, hazardClass
		end

		current = current.Parent
	end

	return nil, nil
end

function HazardUtils.IsMinorHazard(instance)
	local _, hazardClass = HazardUtils.GetHazardInfo(instance)
	return hazardClass == "minor"
end

function HazardUtils.IsMajorHazard(instance)
	local _, hazardClass = HazardUtils.GetHazardInfo(instance)
	return hazardClass == "major"
end

return HazardUtils
