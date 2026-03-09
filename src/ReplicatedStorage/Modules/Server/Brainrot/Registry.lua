local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = {}

Registry._Built = false
Registry._BrainrotsConfig = nil
Registry._VariantCfg = nil
Registry._BrainrotFolder = nil

local function getModelFromFolder(folder, modelName)
	if not folder then
		return nil
	end
	local m = folder:FindFirstChild(tostring(modelName))
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

local function cloneShallow(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	return c
end

function Registry.MakeVariantId(baseId, variantKey)
	if not Registry._VariantCfg then
		return tostring(baseId)
	end
	if variantKey == "Normal" or not variantKey then
		return tostring(baseId)
	end

	local v = (Registry._VariantCfg.Versions or {})[variantKey]
	local prefix = (v and v.Prefix) or (tostring(variantKey) .. " ")
	return prefix .. tostring(baseId)
end

function Registry.GetInfoById(id)
	if not Registry._BrainrotsConfig then
		return nil
	end
	return Registry._BrainrotsConfig[tostring(id)]
end

function Registry.GetOrBuildVariantInfo(baseId, variantKey)
	local baseIdStr = tostring(baseId)
	if variantKey == "Normal" or not variantKey then
		return Registry.GetInfoById(baseIdStr)
	end

	local finalId = Registry.MakeVariantId(baseIdStr, variantKey)
	local cfgInfo = Registry.GetInfoById(finalId)
	if cfgInfo then
		return cfgInfo
	end

	local baseInfo = Registry.GetInfoById(baseIdStr)
	if not baseInfo then
		return nil
	end

	local v = (Registry._VariantCfg and Registry._VariantCfg.Versions or {})[variantKey]
	local mult = tonumber(v and v.IncomeMult) or 1

	local info = cloneShallow(baseInfo)
	info.IsVariant = true
	info.BaseId = baseIdStr
	info.Variant = variantKey
	info.DisplayName = finalId
	info.Income = math.floor((tonumber(baseInfo.Income) or 0) * mult + 0.5)

	return info
end

function Registry.GetTemplateStrict(baseId, variantKey)
	if not Registry._BrainrotFolder then
		return nil
	end

	local baseIdStr = tostring(baseId)

	if variantKey == "Normal" or not variantKey then
		return getModelFromFolder(Registry._BrainrotFolder, baseIdStr)
	end

	local v = (Registry._VariantCfg and Registry._VariantCfg.Versions or {})[variantKey]
	local folderName = v and v.Folder
	if not folderName then
		return nil
	end

	local variantFolder = Registry._BrainrotFolder:FindFirstChild(folderName)
	if not variantFolder or not variantFolder:IsA("Folder") then
		return nil
	end

	return getModelFromFolder(variantFolder, baseIdStr)
end

function Registry.GetTemplateWithFallback(baseId, variantKey)
	local strict = Registry.GetTemplateStrict(baseId, variantKey)
	if strict then
		return strict, variantKey
	end
	local normal = Registry.GetTemplateStrict(baseId, "Normal")
	return normal, "Normal"
end

function Registry.RollVariant(rng)
	if not Registry._VariantCfg then
		return "Normal"
	end

	local order = Registry._VariantCfg.Order or { "Normal" }
	local versions = Registry._VariantCfg.Versions or {}

	local total = 0
	for _, k in ipairs(order) do
		local ch = tonumber((versions[k] or {}).Chance) or 0
		if ch > 0 then
			total += ch
		end
	end

	if total <= 0 then
		return "Normal"
	end

	local r = (rng and rng:NextNumber() or math.random()) * total
	local acc = 0

	for _, k in ipairs(order) do
		local ch = tonumber((versions[k] or {}).Chance) or 0
		if ch > 0 then
			acc += ch
			if r <= acc then
				return k
			end
		end
	end

	return order[#order] or "Normal"
end

function Registry.Build()
	local configs = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs")
	local brainrotsConfig = require(configs:WaitForChild("Brainrots"))
	local spawnPartsCfg = require(configs:WaitForChild("SpawnParts"))
	local variantCfg = require(configs:WaitForChild("BrainrotVariants"))

	local brainrotFolder = ReplicatedStorage:WaitForChild("BrainrotFolder")
	local rarityTier = spawnPartsCfg.RarityTier or {}

	Registry._BrainrotsConfig = brainrotsConfig
	Registry._VariantCfg = variantCfg
	Registry._BrainrotFolder = brainrotFolder
	Registry._Built = true

	local maxTier = 1
	for _, v in pairs(rarityTier) do
		if typeof(v) == "number" and v > maxTier then
			maxTier = v
		end
	end

	local entries = {}
	local globalMaxFoot = 4

	for id, info in pairs(brainrotsConfig) do
		if type(info) == "table" and not info.IsVariant and not info.Variant then
			local template = getModelFromFolder(brainrotFolder, id)
			if template then
				local rarity = tostring(info.Rarity or "Common")
				local tier = tonumber(rarityTier[rarity]) or 1

				local sz = template:GetExtentsSize()
				local foot = math.max(sz.X, sz.Z)
				globalMaxFoot = math.max(globalMaxFoot, foot)

				for _, vKey in ipairs(variantCfg.Order or {}) do
					if vKey ~= "Normal" then
						local vT = Registry.GetTemplateStrict(id, vKey)
						if vT then
							local vsz = vT:GetExtentsSize()
							local vfoot = math.max(vsz.X, vsz.Z)
							globalMaxFoot = math.max(globalMaxFoot, vfoot)
						end
					end
				end

				table.insert(entries, {
					Id = id,
					Info = info,
					Template = template,
					Rarity = rarity,
					Tier = tier,
					Foot = foot,
				})
			end
		end
	end

	return entries, maxTier, globalMaxFoot
end

return Registry
