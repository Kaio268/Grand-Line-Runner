local Module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local brainrotsModels = ReplicatedStorage:WaitForChild("BrainrotFolder")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local BrainrotsCfg = require(Configs:WaitForChild("Brainrots"))
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))

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
	if variantKey == "Normal" then
		local m = brainrotsModels:FindFirstChild(baseName)
		if m and m:IsA("Model") then
			return m
		end
		return nil
	end

	local folder = brainrotsModels:FindFirstChild(variantKey)
	if folder and folder:IsA("Folder") then
		local m = folder:FindFirstChild(baseName)
		if m and m:IsA("Model") then
			return m
		end
	end

	local fallback = brainrotsModels:FindFirstChild(baseName)
	if fallback and fallback:IsA("Model") then
		return fallback
	end

	return nil
end

local function dmSet(DataManager, plr, path, value)
	if DataManager.SetValue then
		DataManager:SetValue(plr, path, value)
		return true
	end
	return false
end

function Module:AddBrainrot(plr, brainrotName, amount)
	local DataManager = require(script.Parent.Parent.Data.DataManager)

	if typeof(plr) ~= "Instance" or not plr:IsA("Player") then
		return false
	end

	brainrotName = validName(brainrotName)
	if not brainrotName then
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

	local variantKey, baseName = getVariantAndBaseName(brainrotName)

	local model = findModelFor(variantKey, baseName)
	if not model then
		return false
	end

	local info = BrainrotsCfg[brainrotName] or BrainrotsCfg[baseName]
	if not info then
		return false
	end

	if BrainrotsCfg[baseName] then
		local baseInfo = BrainrotsCfg[baseName]
		baseInfo.GoldenRender = baseInfo.GoldenRender or baseInfo.Render
		baseInfo.DiamondRender = baseInfo.DiamondRender or baseInfo.Render
	end

	local basePath = "Inventory." .. brainrotName

	DataManager:AdjustValue(plr, basePath .. ".Equipped", 0)
	DataManager:AdjustValue(plr, basePath .. ".Quantity", n)

	local baseInfo = BrainrotsCfg[baseName] or info
	local render = info.Render or ""
	local goldenRender = (baseInfo and (baseInfo.GoldenRender or baseInfo.Render)) or render
	local diamondRender = (baseInfo and (baseInfo.DiamondRender or baseInfo.Render)) or render

	dmSet(DataManager, plr, basePath .. ".Variant", variantKey)
	dmSet(DataManager, plr, basePath .. ".BaseName", baseName)
	dmSet(DataManager, plr, basePath .. ".Render", render)
	dmSet(DataManager, plr, basePath .. ".GoldenRender", goldenRender)
	dmSet(DataManager, plr, basePath .. ".DiamondRender", diamondRender)

	if DataManager.SetValue then
		DataManager:SetValue(plr, basePath .. ".Income", tonumber(info.Income) or 0)
		DataManager:SetValue(plr, basePath .. ".Rarity", tostring(info.Rarity or "Common"))
	end

	return true
end

return Module
