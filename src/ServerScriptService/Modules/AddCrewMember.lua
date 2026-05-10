local Module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewRegistry = require(Modules:WaitForChild("Crew"):WaitForChild("CrewRegistry"))
local BrainrotsCfg = CrewCatalog.GetLegacyConfig()
local VariantCfg = CrewCatalog.GetVariantConfig()
local CrewInstanceService = require(script.Parent:WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(script.Parent:WaitForChild("CrewQuickSlotService"))

local function validName(name)
	if type(name) ~= "string" then return nil end
	if #name < 1 or #name > 80 then return nil end
	if name:find("%.") then return nil end
	return name
end

local function getVariantAndBaseName(fullName)
	fullName = tostring(fullName)

	for _, vKey in ipairs(VariantCfg.Order or {}) do
		if vKey ~= "Normal" then
			local v = (VariantCfg.Versions or {})[vKey]
			local prefix = tostring(v and v.Prefix or (vKey .. " "))
			if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
				local baseName = fullName:sub(#prefix + 1)
				return vKey, baseName
			end
		end
	end

	return "Normal", fullName
end

local function findModelFor(variantKey, baseName)
	local model = CrewRegistry.GetTemplateWithFallback(baseName, variantKey)
	return model and model:IsA("Model") and model or nil
end

function Module:AddCrewMember(plr, crewMemberName, amount, options)
	if typeof(plr) ~= "Instance" or not plr:IsA("Player") then
		return false
	end

	crewMemberName = validName(crewMemberName)
	if not crewMemberName then
		return false
	end

	local n = tonumber(amount)
	if not n then
		return false
	end

	n = math.floor(n)
	if n <= 0 then
		return n == 0
	end

	local variantKey, baseName = getVariantAndBaseName(crewMemberName)

	local model = findModelFor(variantKey, baseName)
	if not model then
		return false
	end

	local info = CrewCatalog.GetInfoById(crewMemberName) or CrewCatalog.GetInfoById(baseName)
	if not info then
		return false
	end

	if BrainrotsCfg[baseName] then
		local baseInfo = BrainrotsCfg[baseName]
		baseInfo.GoldenRender = baseInfo.GoldenRender or baseInfo.Render
		baseInfo.DiamondRender = baseInfo.DiamondRender or baseInfo.Render
	end

	options = if typeof(options) == "table" then options else {}

	local baseInfo = CrewCatalog.GetInfoById(baseName) or BrainrotsCfg[baseName] or info
	local render = info.Render or ""
	local goldenRender = (baseInfo and (baseInfo.GoldenRender or baseInfo.Render)) or render
	local diamondRender = (baseInfo and (baseInfo.DiamondRender or baseInfo.Render)) or render
	local bypassQuickSlotCapacity = options.TutorialReward == true or options._QuickSlotCapacityReserved == true

	if not bypassQuickSlotCapacity and not CrewQuickSlotService.CanGainOrNotify(plr, n, "AddCrewMember:" .. crewMemberName) then
		return false
	end

	if CrewInstanceService.IsInventoryWriteAuthorityEnabled() == true then
		local status = CrewInstanceService.ValidateInventoryMirrors(plr)
		if status == nil or status.Passed ~= true then
			return false
		end
	end

	CrewInstanceService.EnsureInventoryMetadata(plr, crewMemberName, {
		StorageName = crewMemberName,
		BaseName = baseName,
		Variant = variantKey,
		Rarity = tostring(info.Rarity or "Common"),
		Income = tonumber(info.Income) or 0,
		Render = render,
		GoldenRender = goldenRender,
		DiamondRender = diamondRender,
	})
	local createdIds = CrewInstanceService.CreateInstances(plr, crewMemberName, n, {
		BaseName = baseName,
		Variant = variantKey,
		Rarity = tostring(info.Rarity or "Common"),
		Income = tonumber(info.Income) or 0,
		Render = render,
		GoldenRender = goldenRender,
		DiamondRender = diamondRender,
		Level = 1,
		CurrentXP = 0,
		TutorialReward = options.TutorialReward == true,
		TutorialToken = tostring(options.TutorialToken or ""),
		_QuickSlotCapacityReserved = true,
	})
	if #createdIds ~= n then
		return false
	end

	return true
end

return Module
