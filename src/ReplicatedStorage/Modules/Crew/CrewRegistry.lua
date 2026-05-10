local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrewCatalog = require(script.Parent:WaitForChild("CrewCatalog"))
local CrewResolver = require(script.Parent:WaitForChild("CrewResolver"))

local CrewRegistry = {}

CrewRegistry._Built = false

function CrewRegistry.MakeVariantId(baseId, variantKey)
	return CrewCatalog.MakeVariantId(baseId, variantKey)
end

function CrewRegistry.GetInfoById(id)
	return CrewCatalog.GetInfoById(id)
end

function CrewRegistry.GetOrBuildVariantInfo(baseId, variantKey)
	return CrewCatalog.GetOrBuildVariantInfo(baseId, variantKey)
end

function CrewRegistry.GetTemplateStrict(baseId, variantKey)
	local template = CrewResolver.GetTemplateStrict(baseId, variantKey)
	return template
end

function CrewRegistry.GetTemplateWithFallback(baseId, variantKey)
	local template, usedVariant = CrewResolver.GetTemplateWithFallback(baseId, variantKey)
	return template, usedVariant
end

function CrewRegistry.RollVariant(rng)
	local variantCfg = CrewCatalog.GetVariantConfig()
	if not variantCfg then
		return "Normal"
	end

	local order = variantCfg.Order or { "Normal" }
	local versions = variantCfg.Versions or {}

	local total = 0
	for _, key in ipairs(order) do
		local chance = tonumber((versions[key] or {}).Chance) or 0
		if chance > 0 then
			total += chance
		end
	end

	if total <= 0 then
		return "Normal"
	end

	local roll = (rng and rng:NextNumber() or math.random()) * total
	local accumulated = 0
	for _, key in ipairs(order) do
		local chance = tonumber((versions[key] or {}).Chance) or 0
		if chance > 0 then
			accumulated += chance
			if roll <= accumulated then
				return key
			end
		end
	end

	return order[#order] or "Normal"
end

function CrewRegistry.Build()
	local configs = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs")
	local spawnPartsCfg = require(configs:WaitForChild("SpawnParts"))
	local variantCfg = CrewCatalog.GetVariantConfig()
	local rarityTier = spawnPartsCfg.RarityTier or {}

	local maxTier = 1
	for _, value in pairs(rarityTier) do
		if typeof(value) == "number" and value > maxTier then
			maxTier = value
		end
	end

	local entries = {}
	local globalMaxFoot = 4

	for _, crewMember in ipairs(CrewCatalog.GetBaseEntries()) do
		local id = crewMember.Id
		local info = crewMember.Info
		local template = CrewRegistry.GetTemplateStrict(id, "Normal")
		if template then
			local rarity = tostring(info.Rarity or "Common")
			local tier = tonumber(rarityTier[rarity]) or 1
			local size = template:GetExtentsSize()
			local foot = math.max(size.X, size.Z)
			globalMaxFoot = math.max(globalMaxFoot, foot)

			for _, variantKey in ipairs(variantCfg.Order or {}) do
				if variantKey ~= "Normal" then
					local variantTemplate = CrewRegistry.GetTemplateStrict(id, variantKey)
					if variantTemplate then
						local variantSize = variantTemplate:GetExtentsSize()
						globalMaxFoot = math.max(globalMaxFoot, math.max(variantSize.X, variantSize.Z))
					end
				end
			end

			entries[#entries + 1] = {
				Id = id,
				Info = info,
				Template = template,
				Rarity = rarity,
				Tier = tier,
				Foot = foot,
			}
		end
	end

	CrewRegistry._Built = true
	return entries, maxTier, globalMaxFoot
end

return CrewRegistry
