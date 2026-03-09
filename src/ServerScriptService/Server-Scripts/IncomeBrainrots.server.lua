local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")

local STEAL_PRODUCT_ID = 3512126073
local MAX_INCOME_ON_JOIN = 1e16

local StandUpgradeCost = require(ServerScriptService.Modules.StandsUpgrades)
local StandUpgradeMults = require(ServerScriptService.Modules.StandsMultiply)

local shorten = require(ReplicatedStorage.Modules.Shorten)

local stealProductByRarity = {
	Common = 3512126073,
	Uncommon = 3512126073,
	Rare = 3512126073,
	Epic = 3512126073,

	Legendary = 3512126373,
	Mythic = 3512127278,
	Godly = 3512127790,
	Secret = 3512128038,
	Omega = 3512128716,
}

local rarityPriority = { "Omega", "Secret", "Godly", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }

local function normalizeRarity(r)
	r = tostring(r or "")
	if r == "" then
		return "Common"
	end
	local lower = string.lower(r)
	for _, key in ipairs(rarityPriority) do
		if string.find(lower, string.lower(key), 1, true) then
			return key
		end
	end
	return "Common"
end




local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local MoneyCollectedRE = Remotes:FindFirstChild("StandMoneyCollected")
if not MoneyCollectedRE then
	MoneyCollectedRE = Instance.new("RemoteEvent")
	MoneyCollectedRE.Name = "StandMoneyCollected"
	MoneyCollectedRE.Parent = Remotes
end

local dmMod = script.Parent.Parent.Data.DataManager
local DataManager = dmMod and require(dmMod) or nil

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local BrainrotsConfig = require(Configs:WaitForChild("Brainrots"))
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))
local BrainrotFolder = ReplicatedStorage:WaitForChild("BrainrotFolder")

local PlotSystem = workspace:WaitForChild("PlotSystem")
local PlotsFolder = PlotSystem:WaitForChild("Plots")

local function resetHugeIncomeOnJoin(player)
	if not DataManager then
		return
	end

	local ok, incomeBrainrots = pcall(function()
		return DataManager:GetValue(player, "IncomeBrainrots")
	end)

	if not ok or typeof(incomeBrainrots) ~= "table" then
		return
	end

	local changed = false

	for standName, standData in pairs(incomeBrainrots) do
		if typeof(standData) == "table" then
			local income = standData.IncomeToCollect
			if typeof(income) == "number" and income >= MAX_INCOME_ON_JOIN then
				standData.IncomeToCollect = 0
				changed = true
			end
		end
	end

	if changed then
		pcall(function()
			DataManager:SetValue(player, "IncomeBrainrots", incomeBrainrots)
		end)
	end
end


local function getVariantAndBaseName(fullName)
	fullName = tostring(fullName)

	for _, vKey in ipairs(VariantCfg.Order or {}) do
		if vKey ~= "Normal" then
			local v = (VariantCfg.Versions or {})[vKey]
			local prefix = tostring((v and v.Prefix) or (vKey .. " "))
			if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
				local baseName = fullName:sub(#prefix + 1)
				return vKey, baseName, v
			end
		end
	end

	return "Normal", fullName, (VariantCfg.Versions or {}).Normal
end

local function findTemplateForName(brainrotName)
	local variantKey, baseName, v = getVariantAndBaseName(brainrotName)

	if variantKey ~= "Normal" then
		local folderName = (v and v.Folder) or variantKey
		local variantFolder = BrainrotFolder:FindFirstChild(folderName)
		if variantFolder and variantFolder:IsA("Folder") then
			local t = variantFolder:FindFirstChild(baseName)
			if t and t:IsA("Model") then
				return t
			end
			local t2 = variantFolder:FindFirstChild(brainrotName)
			if t2 and t2:IsA("Model") then
				return t2
			end
		end
	end

	local direct = BrainrotFolder:FindFirstChild(brainrotName)
	if direct and direct:IsA("Model") then
		return direct
	end

	local base = BrainrotFolder:FindFirstChild(baseName)
	if base and base:IsA("Model") then
		return base
	end

	return nil
end

local function ensurePrimaryPart(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local pp = model:FindFirstChildWhichIsA("BasePart", true)
	if pp then
		pcall(function()
			model.PrimaryPart = pp
		end)
	end
	return model.PrimaryPart or pp
end

local function anchorModel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function tryPlayIdle(model, animId)
	animId = tonumber(animId)
	if not animId or animId == 0 then
		return
	end
	local controller = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not controller then
		return
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	pcall(function()
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)
end

local function getStandCollectMultiplier(player, standName)
	local folder = player:FindFirstChild("StandsLevels")
	local lvObj = folder and folder:FindFirstChild(standName)
	local lvl = lvObj and tonumber(lvObj.Value) or 1
	if lvl < 1 then lvl = 1 end

	local mult = tonumber(StandUpgradeMults[tostring(lvl)]) or 1
	if mult <= 0 then mult = 1 end
	return mult
end

 
local function getEquippedToolName(player)
	local char = player.Character
	if not char then
		return nil
	end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			return c.Name
		end
	end
	return nil
end

local function getInventoryQuantity(player, itemName)
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		return 0
	end
	local item = inv:FindFirstChild(itemName)
	if not item then
		return 0
	end
	local q = item:FindFirstChild("Quantity")
	if not q or not q:IsA("NumberValue") then
		return 0
	end
	return q.Value
end

local function dmGet(player, path)
	if not DataManager then
		return nil
	end
	local ok, v = pcall(function()
		return DataManager:GetValue(player, path)
	end)
	if ok then
		return v
	end
	return nil
end

local function dmSet(player, path, value)
	if not DataManager then
		return
	end
	pcall(function()
		DataManager:SetValue(player, path, value)
	end)
end

local function dmAdjust(player, path, delta)
	if not DataManager then
		return
	end
	if typeof(DataManager.AdjustValue) == "function" then
		pcall(function()
			DataManager:AdjustValue(player, path, delta)
		end)
		return
	end
	if delta > 0 and typeof(DataManager.AddValue) == "function" then
		pcall(function()
			DataManager:AddValue(player, path, delta)
		end)
	elseif delta < 0 and typeof(DataManager.SubValue) == "function" then
		pcall(function()
			DataManager:SubValue(player, path, -delta)
		end)
	end
end

local function dmEnsureStandFolder(player, standName)
	if not DataManager then
		return false
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if typeof(standName) ~= "string" or standName == "" then
		return false
	end

	local brainrotPath = "IncomeBrainrots." .. standName .. ".BrainrotName"
	local incomePath = "IncomeBrainrots." .. standName .. ".IncomeToCollect"

	local okName, nameVal = pcall(function()
		return DataManager:GetValue(player, brainrotPath)
	end)
	if not okName then
		return false
	end

	if nameVal == nil then
		pcall(function()
			local incomeBrainrots = DataManager:GetValue(player, "IncomeBrainrots")
			if typeof(incomeBrainrots) ~= "table" then
				incomeBrainrots = {}
			end

			if typeof(incomeBrainrots[standName]) ~= "table" then
				incomeBrainrots[standName] = {
					IncomeToCollect = 0,
					BrainrotName = "",
				}
			else
				if typeof(incomeBrainrots[standName].IncomeToCollect) ~= "number" then
					incomeBrainrots[standName].IncomeToCollect = 0
				end
				if typeof(incomeBrainrots[standName].BrainrotName) ~= "string" then
					incomeBrainrots[standName].BrainrotName = ""
				end
			end

			DataManager:SetValue(player, "IncomeBrainrots", incomeBrainrots)
		end)

		pcall(function()
			local lv = DataManager:GetValue(player, "StandsLevels")
			if typeof(lv) ~= "table" then
				lv = {}
			end
			if typeof(lv[standName]) ~= "number" or lv[standName] < 1 then
				lv[standName] = 1
			end
			DataManager:SetValue(player, "StandsLevels", lv)
		end)
	else
		if typeof(nameVal) ~= "string" then
			pcall(function()
				DataManager:SetValue(player, brainrotPath, "")
			end)
		end

		local okIncome, incVal = pcall(function()
			return DataManager:GetValue(player, incomePath)
		end)
		if not okIncome then
			return false
		end
		if incVal == nil or typeof(incVal) ~= "number" then
			pcall(function()
				DataManager:SetValue(player, incomePath, 0)
			end)
		end
	end

	pcall(function()
		if typeof(DataManager.UpdateData) == "function" then
			DataManager:UpdateData(player)
		end
	end)

	return true
end


local function getPlayerStandBrainrotName(player, standName)
	dmEnsureStandFolder(player, standName)
	local v = dmGet(player, "IncomeBrainrots." .. standName .. ".BrainrotName")
	if typeof(v) ~= "string" then
		return ""
	end
	return v
end

local function getPlayerStandIncome(player, standName)
	dmEnsureStandFolder(player, standName)
	local v = dmGet(player, "IncomeBrainrots." .. standName .. ".IncomeToCollect")
	if typeof(v) ~= "number" then
		return 0
	end
	return v
end

local function ensureInventoryLevelValue(player, brainrotName, level)
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		inv = Instance.new("Folder")
		inv.Name = "Inventory"
		inv.Parent = player
	end

	local item = inv:FindFirstChild(brainrotName)
	if not item then
		item = Instance.new("Folder")
		item.Name = brainrotName
		item.Parent = inv
	end

	local lv = item:FindFirstChild("Level")
	if not lv then
		lv = Instance.new("NumberValue")
		lv.Name = "Level"
		lv.Parent = item
	end
	lv.Value = level
end

local function findBrainrotInfoByName(brainrotName)
	if BrainrotsConfig[brainrotName] then
		return BrainrotsConfig[brainrotName], brainrotName
	end
	for id, info in pairs(BrainrotsConfig) do
		if tostring(info.Render or "") == tostring(brainrotName) then
			return info, tostring(id)
		end
	end
	for id, info in pairs(BrainrotsConfig) do
		local n = tostring(info.Name or info.DisplayName or "")
		if n ~= "" and n == tostring(brainrotName) then
			return info, tostring(id)
		end
	end
	return nil, nil
end

local function getStealProductIdForBrainrot(brainrotName)
	local info = findBrainrotInfoByName(brainrotName)
	local rarity = info and info.Rarity or "Common"
	local fixed = normalizeRarity(rarity)
	return stealProductByRarity[fixed] or 3512126073
end


local function updateStandPromptTexts(player, standModel)
	if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
		return
	end

	local handle = standModel:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end

	local standName = standModel.Name
	local brainrotName = ""

	if player and player:IsA("Player") then
		brainrotName = getPlayerStandBrainrotName(player, standName)
	end

	if brainrotName ~= "" then
		local info = findBrainrotInfoByName(brainrotName)
		local displayName = info and tostring(info.Name or info.DisplayName or brainrotName) or tostring(brainrotName)
		prompt.ObjectText = displayName
		prompt.ActionText = "Pick Up"
	else
		prompt.ObjectText = tostring(standName)
		prompt.ActionText = "Place Here"
	end
end

local function findHoverGui(primaryPart)
	local h = primaryPart:FindFirstChild("BrainrotHover", true)
	if h and h:IsA("BillboardGui") then
		return h
	end
	h = primaryPart:FindFirstChild("BrainortHover", true)
	if h and h:IsA("BillboardGui") then
		return h
	end
	return nil
end

local function getBrainrotLevel(player, brainrotName)
	local path = "Inventory." .. brainrotName .. ".Level"
	local v = dmGet(player, path)
	if typeof(v) ~= "number" then
		dmAdjust(player, path, 1)
		v = 1
	elseif v < 1 then
		dmAdjust(player, path, 1 - v)
		v = 1
	end
	ensureInventoryLevelValue(player, brainrotName, v)
	return v
end

local function getBaseIncome(brainrotName)
	local info = findBrainrotInfoByName(brainrotName)
	local base = info and (tonumber(info.Income) or 0) or 0
	return base
end

local function getIncomeWithLevel(player, brainrotName)
	local base = getBaseIncome(brainrotName)
	if base <= 0 then
		return 0
	end
	local lvl = getBrainrotLevel(player, brainrotName)
	local mult =1
	return base * mult
end

local function getStandIncomeDisplay(player, standName)
	local base = getPlayerStandIncome(player, standName)
	if base <= 0 then
		return 0
	end
	return base * getStandCollectMultiplier(player, standName)
end

local function getPlayerMoney(player)
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if m and m:IsA("NumberValue") then
		return m.Value
	end
	local v = dmGet(player, "leaderstats.Money")
	if typeof(v) == "number" then
		return v
	end
	return 0
end

local RaritiesFolder = ReplicatedStorage:WaitForChild("Rarities")
local BrainrotHoverTemplate = RaritiesFolder:WaitForChild("BrainrotHover")

local function ensureBrainrotHover(model)
	local primary = ensurePrimaryPart(model)
	if not primary then
		return nil
	end

	local existing = findHoverGui(primary)
	if existing then
		existing.Enabled = true
		return existing
	end

	if not BrainrotHoverTemplate or not BrainrotHoverTemplate:IsA("BillboardGui") then
		return nil
	end

	local clone = BrainrotHoverTemplate:Clone()
	clone.Name = "BrainrotHover"
	clone.Enabled = true
	clone.Adornee = primary
	clone.Parent = primary
	return clone
end

local function getTextTarget(root, name)
	local obj = root:FindFirstChild(name, true)
	if not obj then
		return nil
	end
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		return obj
	end
	return obj:FindFirstChildWhichIsA("TextLabel", true) or obj:FindFirstChildWhichIsA("TextButton", true) or obj:FindFirstChildWhichIsA("TextBox", true)
end

local function buildHoverRefsNoTime(model)
	local primary = ensurePrimaryPart(model)
	if not primary then
		return nil
	end
	local hover = findHoverGui(primary)
	if not hover then
		return nil
	end
	hover.Enabled = true
	local income = getTextTarget(hover, "Income")
	local nameT = getTextTarget(hover, "Name")
	local rarityT = getTextTarget(hover, "Rarity")

	local timeLeftContainer = hover:FindFirstChild("TimeLeft", true)
	local timeT
	local timeImg
	if timeLeftContainer then
		timeT = getTextTarget(timeLeftContainer, "TextL")
		if not timeT then
			timeT = timeLeftContainer:FindFirstChildWhichIsA("TextLabel", true) or timeLeftContainer:FindFirstChildWhichIsA("TextButton", true) or timeLeftContainer:FindFirstChildWhichIsA("TextBox", true)
		end
		timeImg = timeLeftContainer:FindFirstChild("ImageLabel", true) or timeLeftContainer:FindFirstChildWhichIsA("ImageLabel", true)
	end
	if not timeT then
		timeT = getTextTarget(hover, "TextL") or getTextTarget(hover, "TimeLeft")
	end

	if timeT then timeT.Visible = false end
	if timeImg then timeImg.Visible = false end

	return {
		Income = income,
		Name = nameT,
		Rarity = rarityT,
		Gui = hover,
	}
end

local ReplicatedStorage2 = game:GetService("ReplicatedStorage")
local RarityTexts = ReplicatedStorage2:WaitForChild("Rarities"):WaitForChild("Texts")

local function clearRarityLabel(label)
	if label:IsA("TextLabel") then
		label.Text = ""
	end
	for _, child in ipairs(label:GetChildren()) do
		child:Destroy()
	end
end

local VariantOrder = { "Normal", "Golden", "Diamond" }
local VariantPrefix = {
	Normal = "",
	Golden = "Golden ",
	Diamond = "Diamond ",
}

local function startsWith(s, pref)
	return s:sub(1, #pref) == pref
end

local function detectVariant(text)
	text = tostring(text or "")
	for _, v in ipairs(VariantOrder) do
		if v ~= "Normal" then
			local pref = tostring(VariantPrefix[v] or (v .. " "))
			if pref ~= "" and startsWith(text, pref) then
				return v
			end
			local alt = v .. " "
			if startsWith(text, alt) then
				return v
			end
		end
	end
	return "Normal"
end

local function stripVariantPrefix(text, variantKey)
	text = tostring(text or "")
	if not variantKey or variantKey == "Normal" then
		return text
	end
	local pref = tostring(VariantPrefix[variantKey] or (variantKey .. " "))
	if pref ~= "" and startsWith(text, pref) then
		local out = text:sub(#pref + 1)
		if out ~= "" then
			return out
		end
	end
	local alt = variantKey .. " "
	if startsWith(text, alt) then
		local out = text:sub(#alt + 1)
		if out ~= "" then
			return out
		end
	end
	return text
end

local function applyVariantLabel(hoverGui, variantKey, enabled)
	if not hoverGui then
		return
	end
	for _, d in ipairs(hoverGui:GetDescendants()) do
		if d:IsA("GuiObject") then
			for _, v in ipairs(VariantOrder) do
				if d.Name == v then
					d.Visible = enabled and (v == variantKey)
				end
			end
		end
	end
end

local function applyRarityFromStorage(rarityLabel, rarityName)
	if not rarityLabel or rarityName == "" then
		return
	end

	clearRarityLabel(rarityLabel)

	local template = RarityTexts:FindFirstChild(rarityName)
	if not template then
		for _, obj in ipairs(RarityTexts:GetChildren()) do
			if obj:IsA("TextLabel") and obj.Name == rarityName then
				template = obj
				break
			end
		end
	end

	if not template or not template:IsA("TextLabel") then
		if rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarityName
		end
		return
	end
	rarityLabel.Text = tostring(rarityName)

	for _, child in ipairs(template:GetChildren()) do
		child:Clone().Parent = rarityLabel
	end
end

local function setHoverTextsNoTime(refs, player, brainrotName)
	if not refs then
		return
	end

	local info = findBrainrotInfoByName(brainrotName)
	local rawName = info and tostring(info.Name or info.DisplayName or brainrotName) or tostring(brainrotName)
	local rawRarity = info and tostring(info.Rarity or "") or ""

	local variantKey = detectVariant(brainrotName)
	if variantKey == "Normal" then
		variantKey = detectVariant(rawName)
	end
	if variantKey == "Normal" then
		variantKey = detectVariant(rawRarity)
	end

	local displayName = stripVariantPrefix(rawName, variantKey)
	local displayRarity = stripVariantPrefix(rawRarity, variantKey)

	local income = 0
	if player and player:IsA("Player") then
		income = getIncomeWithLevel(player, brainrotName)
	else
		income = info and (tonumber(info.Income) or 0) or 0
	end

	if refs.Income then
		refs.Income.Text = shorten.roundNumber(math.floor(income)) .. "$/s"
	end
	if refs.Name then
		refs.Name.Text = displayName
	end
	if refs.Rarity then
		applyRarityFromStorage(refs.Rarity, displayRarity)
	end
	if refs.Gui then
		refs.Gui.Enabled = true
		applyVariantLabel(refs.Gui, variantKey, true)
	end
end

local function clearStandVisual(standModel)
	local existing = standModel:FindFirstChild("PlacedBrainrot")
	if existing and existing:IsA("Model") then
		existing:Destroy()
	end
end

local function placeModelBottomOnHandleLeft(model, handle)
	local boxCF, boxSize = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(boxCF)
	local up = handle.CFrame.UpVector
	local surface = handle.Position + up * (handle.Size.Y / 2)
	local rot = (handle.CFrame - handle.Position) * CFrame.Angles(0, math.rad(90), 0)
	local desiredBox = CFrame.new(surface + up * (boxSize.Y / 2)) * rot
	local pivotTarget = desiredBox * offset:Inverse()
	model:PivotTo(pivotTarget)
end

local function spawnStandBrainrot(player, standModel, handle, brainrotName)
	clearStandVisual(standModel)

	local template = findTemplateForName(brainrotName)
	if not template or not template:IsA("Model") then
		return
	end

	local clone = template:Clone()
	clone.Name = "PlacedBrainrot"
	clone.Parent = standModel

	ensurePrimaryPart(clone)
	anchorModel(clone)
	placeModelBottomOnHandleLeft(clone, handle)

	ensureBrainrotHover(clone)

	local info = findBrainrotInfoByName(brainrotName)
	if info then
		tryPlayIdle(clone, info.IdleAnim)
	end

	local refs = buildHoverRefsNoTime(clone)
	setHoverTextsNoTime(refs, player, brainrotName)
end

local function getMoneyLabel(standModel)
	local claim = standModel:FindFirstChild("Claim", true)
	if not claim then
		return nil
	end
	local zone = claim:FindFirstChild("Zone", true)
	if not zone then
		return nil
	end
	local bb = zone:FindFirstChildWhichIsA("BillboardGui", true) or zone:FindFirstChild("BillboardGui", true)
	if not bb then
		return nil
	end
	return getTextTarget(bb, "Money")
end

local function setMoneyText(standModel, amount)
	local money = getMoneyLabel(standModel)
	if money then
		money.Text = shorten.roundNumber(math.floor(amount)) .. "$"
	end
end

local function getHitBoxPart(standModel)
	local claim = standModel:FindFirstChild("Claim", true)
	if not claim then
		return nil
	end
	local zone = claim:FindFirstChild("HitBox", true)
	if zone and zone:IsA("BasePart") then
		return zone
	end
	return nil
end

local function findPlotForPlayer(player)
	for _, m in ipairs(PlotsFolder:GetChildren()) do
		if m:IsA("Model") then
			local owner = m:GetAttribute("OwnerUserId")
			if owner == player.UserId then
				return m
			end
		end
	end
	return nil
end

local function waitForPlot(player, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 15) do
		local plot = findPlotForPlayer(player)
		if plot then
			return plot
		end
		task.wait(0.25)
	end
	return nil
end

local function getStandsFolder(plot)
	local stands = plot:FindFirstChild("Stands", true)
	if stands and stands:IsA("Folder") then
		return stands
	end
	return nil
end

local function getLevelUpPart(standModel)
	local p = standModel:FindFirstChild("LevelUp", true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function getLevelUpGuiRoot(standModel)
	local part = getLevelUpPart(standModel)
	if not part then
		return nil, nil, nil
	end
	local sg = part:FindFirstChildWhichIsA("SurfaceGui", true) or part:FindFirstChild("SurfaceGui")
	if not sg or not sg:IsA("SurfaceGui") then
		return part, nil, nil
	end
	local root = sg:FindFirstChild("LevelUp")
	if root and root:IsA("GuiObject") then
		return part, sg, root
	end
	return part, sg, nil
end

local function setLevelUpVisible(standModel, visible)
	local part, sg, root = getLevelUpGuiRoot(standModel)
	if sg then
		sg.Enabled = visible
	end
	if root then
		root.Visible = visible
	end
	local cd = part and part:FindFirstChildOfClass("ClickDetector")
	if cd then
		cd.MaxActivationDistance = visible and 15 or 0
	end
end

local function getLevelUpRefs(standModel)
	local part, sg, root = getLevelUpGuiRoot(standModel)
	if not part or not sg then
		return nil
	end
	local container = root or sg
	local main = container:FindFirstChild("Main", true) or container
	local price = getTextTarget(main, "Price")
	local upg = getTextTarget(main, "Upgarde") or getTextTarget(main, "Upgrade")
	return {
		Part = part,
		SurfaceGui = sg,
		Root = root,
		Main = main,
		Price = price,
		Upgrade = upg,
	}
end

local function ensureLevelUpClickDetector(standModel)
	local part = getLevelUpPart(standModel)
	if not part then
		return nil
	end
	local cd = part:FindFirstChildOfClass("ClickDetector")
	if not cd then
		cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 15
		cd.Parent = part
	end
	return cd
end

local function updateStandHover(player, standModel, brainrotName)
	local placed = standModel:FindFirstChild("PlacedBrainrot")
	if placed and placed:IsA("Model") then
		ensureBrainrotHover(placed)
		local refs = buildHoverRefsNoTime(placed)
		setHoverTextsNoTime(refs, player, brainrotName)
	end
end

local function getStandLevelValue(player, standName)
	local folder = player:FindFirstChild("StandsLevels")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "StandsLevels"
		folder.Parent = player
	end

	local v = folder:FindFirstChild(standName)
	if not v or not v:IsA("NumberValue") then
		if v then v:Destroy() end
		v = Instance.new("NumberValue")
		v.Name = standName
		v.Value = 1
		v.Parent = folder
	end

	if v.Value < 1 then v.Value = 1 end
	return v
end

local function getStandLevel(player, standName)
	return getStandLevelValue(player, standName).Value
end

local function getUpgradeCost(player, standName)
	local cur = getStandLevel(player, standName)
	local nextLvl = cur + 1
	local mult = tonumber(StandUpgradeMults[tostring(nextLvl)]) or -1
	if mult <= 0 then return 0 end

	local base = tonumber(StandUpgradeCost[tostring(nextLvl)]) or tonumber(StandUpgradeCost[tostring(standName)]) or 0
	if base <= 0 then
		base = tonumber(StandUpgradeCost[tostring(nextLvl)]) or 0
	end
	if base <= 0 then return 0 end

	return math.floor(base * mult)
end

local function updateLevelUpUI(player, standModel)
	local refs = getLevelUpRefs(standModel)
	if not refs then return end

	local standName = standModel.Name
	local brainrotName = getPlayerStandBrainrotName(player, standName)

	if brainrotName == "" then
		setLevelUpVisible(standModel, false)
		if refs.Price then refs.Price.Text = "" end
		if refs.Upgrade then refs.Upgrade.Text = "" end
		return
	end

	local standsLevels = player:WaitForChild("StandsLevels")
	local lvObj = standsLevels:WaitForChild(standName)

	local currentLevel = tonumber(lvObj.Value) or 1
	if currentLevel < 1 then currentLevel = 1 end
	lvObj.Value = currentLevel

	local upgrades = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("StandsUpgrades"))
	local nextLevel = currentLevel + 1
	local cost = tonumber((upgrades or {})[tostring(nextLevel)]) or 0

	if cost <= 0 then
		setLevelUpVisible(standModel, false)
		if refs.Price then refs.Price.Text = "" end
		if refs.Upgrade then refs.Upgrade.Text = "" end
		return
	end

	setLevelUpVisible(standModel, true)
	if refs.Price then refs.Price.Text = "$" .. shorten.roundNumber(math.floor(cost)) end
	if refs.Upgrade then refs.Upgrade.Text = "Upgrade Level " .. tostring(nextLevel) end
end

local promptBound = {}
local zoneBound = {}
local levelUpBound = {}
local playerStandList = {}
local touchDebounce = {}
local stealPromptDebounce = {}

local function bindZoneCollect(player, plot, standModel)
	local zone = getHitBoxPart(standModel)
	if not zone then
		return
	end
	if zoneBound[zone] then
		return
	end
	zoneBound[zone] = true

	zone.Touched:Connect(function(hit)
		if not hit or hit.Name ~= "HumanoidRootPart" then
			return
		end

		local char = hit.Parent
		if not char then
			return
		end

		local plr = Players:GetPlayerFromCharacter(char)
		if not plr or plr ~= player then
			return
		end

		local owner = plot:GetAttribute("OwnerUserId")
		if owner ~= plr.UserId then
			return
		end

		touchDebounce[plr] = touchDebounce[plr] or {}
		local now = os.clock()
		local last = touchDebounce[plr][zone]
		if last and (now - last) < 0.35 then
			return
		end
		touchDebounce[plr][zone] = now

		local standName = standModel.Name

		if not dmEnsureStandFolder(plr, standName) then
			return
		end

		local baseToCollect = getPlayerStandIncome(plr, standName)
		if baseToCollect <= 0 then
			setMoneyText(standModel, 0)
			return
		end

		dmSet(plr, "IncomeBrainrots." .. standName .. ".IncomeToCollect", 0)

		local mult = getStandCollectMultiplier(plr, standName)
		local collected = math.floor(baseToCollect * mult)

		DataManager:AddValue(plr, "leaderstats.Money", collected)
		DataManager:AddValue(plr, "TotalStats.TotalMoney", collected)

		if MoneyCollectedRE then
			MoneyCollectedRE:FireClient(plr, standModel, collected)
		end

		setMoneyText(standModel, 0)
	end)
end


local function bindLevelUp(player, plot, standModel)
	local cd = ensureLevelUpClickDetector(standModel)
	if not cd then
		return
	end
	if levelUpBound[cd] then
		return
	end
	levelUpBound[cd] = true

	cd.MouseClick:Connect(function(plr)
		if plr ~= player then
			return
		end
		if plot:GetAttribute("OwnerUserId") ~= plr.UserId then
			return
		end

		local standName = standModel.Name
		local brainrotName = getPlayerStandBrainrotName(plr, standName)
		if brainrotName == "" then
			return
		end

		local cost = getUpgradeCost(plr, standName)
		if cost <= 0 then
			return
		end

		local money = getPlayerMoney(plr)
		if money < cost then
			return
		end

		dmAdjust(plr, "leaderstats.Money", -cost)
		dmAdjust(plr, "Inventory." .. brainrotName .. ".Level", 1)

		local newLvl = getBrainrotLevel(plr, brainrotName)
		ensureInventoryLevelValue(plr, brainrotName, newLvl)

		local stands = playerStandList[plr]
		if stands then
			for i = 1, #stands do
				local sm = stands[i]
				if sm and sm.Parent then
					local bn = getPlayerStandBrainrotName(plr, sm.Name)
					if bn == brainrotName then
						updateLevelUpUI(plr, sm)
						updateStandHover(plr, sm, bn)
					end
				end
			end
		end
	end)

	updateLevelUpUI(player, standModel)
end

local function bindStandPrompt(player, plot, standModel)
	local handle = standModel:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end

	if promptBound[prompt] then
		return
	end
	promptBound[prompt] = true

	dmEnsureStandFolder(player, standModel.Name)
	setMoneyText(standModel, getStandIncomeDisplay(player, standModel.Name))
	bindZoneCollect(player, plot, standModel)
	bindLevelUp(player, plot, standModel)
	updateStandPromptTexts(player, standModel)

	prompt.Triggered:Connect(function(plr)
		if not plr or not plr:IsA("Player") then
			return
		end

		local ownerUserId = plot:GetAttribute("OwnerUserId")
		if ownerUserId ~= player.UserId then
			return
		end

		local standName = standModel.Name

		if plr.UserId ~= ownerUserId then
			local brainrotToSteal = getPlayerStandBrainrotName(player, standName)
			if brainrotToSteal == "" then
				return
			end

			local now = os.clock()
			local last = stealPromptDebounce[plr]
			if last and (now - last) < 1 then
				return
			end
			stealPromptDebounce[plr] = now

			local productId = getStealProductIdForBrainrot(brainrotToSteal)

			plr:SetAttribute("StealOwnerUserId", ownerUserId)
			plr:SetAttribute("StealStandName", standName)
			plr:SetAttribute("StealBrainrotName", brainrotToSteal)
			plr:SetAttribute("StealProductId", productId)
			plr:SetAttribute("StealTime", os.time())

			MarketplaceService:PromptProductPurchase(plr, productId)
			return
		end


		dmEnsureStandFolder(plr, standName)

		local current = getPlayerStandBrainrotName(plr, standName)
		if current ~= "" then
			dmSet(plr, "IncomeBrainrots." .. standName .. ".BrainrotName", "")
			dmAdjust(plr, "Inventory." .. current .. ".Quantity", 1)
			clearStandVisual(standModel)
			setMoneyText(standModel, getStandIncomeDisplay(plr, standName))
			updateLevelUpUI(plr, standModel)
			updateStandPromptTexts(plr, standModel)
			return
		end

		local toolName = getEquippedToolName(plr)
		if not toolName or toolName == "" then
			return
		end

		local qty = getInventoryQuantity(plr, toolName)
		if qty < 1 then
			return
		end

		getBrainrotLevel(plr, toolName)

		dmAdjust(plr, "Inventory." .. toolName .. ".Quantity", -1)
		dmSet(plr, "IncomeBrainrots." .. standName .. ".BrainrotName", toolName)

		spawnStandBrainrot(plr, standModel, handle, toolName)
		setMoneyText(standModel, getStandIncomeDisplay(plr, standName))
		updateLevelUpUI(plr, standModel)
		updateStandPromptTexts(plr, standModel)
	end)
end

local function registerStand(player, plot, standModel)
	local list = playerStandList[player]
	if not list then
		list = {}
		playerStandList[player] = list
	end

	for i = 1, #list do
		if list[i] == standModel then
			bindStandPrompt(player, plot, standModel)
			return
		end
	end

	table.insert(list, standModel)

	bindStandPrompt(player, plot, standModel)

	local handle = standModel:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		local name = getPlayerStandBrainrotName(player, standModel.Name)
		if name ~= "" then
			getBrainrotLevel(player, name)
			spawnStandBrainrot(player, standModel, handle, name)
			updateStandHover(player, standModel, name)
		else
			clearStandVisual(standModel)
		end
	end

	setMoneyText(standModel, getStandIncomeDisplay(player, standModel.Name))
	updateLevelUpUI(player, standModel)
end


local plotScanBound = {} 

local function waitForStandsFolder(plot, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 20) do
		local stands = plot:FindFirstChild("Stands", true)
		if stands and stands:IsA("Folder") then
			return stands
		end
		task.wait(0.25)
	end
	return nil
end

local function scanAndBindPlot(player, plot)
	if not player or not player.Parent then
		return
	end
	if not plot or not plot.Parent then
		return
	end

	if plotScanBound[plot] then
		return
	end
	plotScanBound[plot] = true

	local stands = waitForStandsFolder(plot, 25)
	if not stands then
		plotScanBound[plot] = nil
		return
	end

	for _, m in ipairs(stands:GetDescendants()) do
		if m:IsA("Model") then
			local handle = m:FindFirstChild("Handle", true)
			local prompt = handle and handle:IsA("BasePart") and handle:FindFirstChildOfClass("ProximityPrompt") or nil
			if prompt then
				registerStand(player, plot, m)
			end
		end
	end

	stands.DescendantAdded:Connect(function(inst)
		if not player.Parent then
			return
		end

		if inst:IsA("ProximityPrompt") then
			local h = inst.Parent
			if h and h:IsA("BasePart") and h.Name == "Handle" then
				local sm = h:FindFirstAncestorOfClass("Model")
				if sm then
					registerStand(player, plot, sm)
				end
			end
		end
	end)
end


Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		resetHugeIncomeOnJoin(player)

		local plot = waitForPlot(player, 25)
		if not plot then
			return
		end
		scanAndBindPlot(player, plot)
	end)
end)


Players.PlayerRemoving:Connect(function(player)
	playerStandList[player] = nil
end)

for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		local plot = waitForPlot(p, 5)
		if plot then
			scanAndBindPlot(p, plot)
			resetHugeIncomeOnJoin(p)
		end
	end)
end
  
task.spawn(function()
	while true do
		task.wait(1)

		for plr, stands in pairs(playerStandList) do
			if not plr.Parent then
				playerStandList[plr] = nil
			else
				for i = 1, #stands do
					local standModel = stands[i]
					if standModel and standModel.Parent then
						local standName = standModel.Name
						dmEnsureStandFolder(plr, standName)

						local brainrotName = getPlayerStandBrainrotName(plr, standName)
						if brainrotName ~= "" then
							local inc = getIncomeWithLevel(plr, brainrotName)
							if inc ~= 0 then
								dmAdjust(plr, "IncomeBrainrots." .. standName .. ".IncomeToCollect", inc)
							end
						end

						setMoneyText(standModel, getStandIncomeDisplay(plr, standName))
						updateLevelUpUI(plr, standModel)
						updateStandPromptTexts(plr, standModel)
					end
				end
			end
		end
	end
end)
