local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player.PlayerGui

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local Brainrots = require(Configs:WaitForChild("Brainrots"))
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))
local MoneyLib = require(Modules:WaitForChild("Shorten"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local IndexConfig = require(Configs:WaitForChild("Index"))

local claimRemote = ReplicatedStorage:WaitForChild("ClaimIndexReward")

local frames = playerGui:WaitForChild("Frames")
local indexFrame = frames:WaitForChild("Index")

local inventory = player:WaitForChild("Inventory")

local buttonsFrame = indexFrame:WaitForChild("Buttons")

local indexScroll = indexFrame:WaitForChild("Index")
local rewardsScroll = indexFrame:WaitForChild("Rewards")

local indexCollected = indexScroll:WaitForChild("Collected")
local rewardsCollected = rewardsScroll:WaitForChild("Collected")

local inexFrame = indexScroll:FindFirstChild("Index") or indexScroll
local brainrotTemplate = inexFrame:WaitForChild("Template")
brainrotTemplate.Visible = false

local topBar = indexFrame:WaitForChild("TopBar")
local topFrame = topBar:WaitForChild("Frame")
local topRewardsBtn = topFrame:WaitForChild("Rewards")
local topIndexBtn = topFrame:WaitForChild("Index")

local hud = playerGui:WaitForChild(`HUD`)

local IndexBadge = nil
local IndexText = nil

local rewardsTemplate = rewardsScroll:WaitForChild("Template")
rewardsTemplate.Visible = false

for _, child in ipairs(rewardsScroll:GetChildren()) do
	if child ~= rewardsTemplate and child:IsA("Frame") and child.Name ~= "///" then
		child:Destroy()
	end
end

local function setTab(showIndex)
	indexScroll.Visible = showIndex
	rewardsScroll.Visible = not showIndex
end

if topRewardsBtn:IsA("GuiButton") then
	topRewardsBtn.MouseButton1Click:Connect(function()
		setTab(false)
	end)
end

if topIndexBtn:IsA("GuiButton") then
	topIndexBtn.MouseButton1Click:Connect(function()
		setTab(true)
	end)
end

if hud then 
	local lbuttons = hud:WaitForChild(`LButtons`)
	local IndexButton = lbuttons:WaitForChild(`Index`)
	
	IndexBadge = IndexButton and IndexButton:WaitForChild(`Not`, true)
	IndexText = IndexBadge:WaitForChild(`TextLB`)
end

local function UpdateIndexBadge(ToClaim)
	if not IndexBadge then
		return
	end
	
	if ToClaim and ToClaim > 0 then
		IndexBadge.Visible = true
		if IndexText then
			IndexText.Text = tostring(ToClaim)
		end
	else
		IndexBadge.Visible = false
	end
end


local supportedVariants = { "Normal", "Golden", "Diamond" }

local baseBrainrotList = {}
for name, data in pairs(Brainrots) do
	if type(data) == "table" and not data.IsVariant and not data.Variant then
		table.insert(baseBrainrotList, { Name = name, Data = data, Income = tonumber(data.Income) or 0 })
	end
end

table.sort(baseBrainrotList, function(a, b)
	return a.Income < b.Income
end)

local function getVariantInfo(variantKey)
	if variantKey == "Normal" or not variantKey then
		return (VariantCfg.Versions or {}).Normal or { Prefix = "", IncomeMult = 1 }
	end
	return (VariantCfg.Versions or {})[variantKey]
end

local function getVariantColor(variantKey)
	local v = getVariantInfo(variantKey)
	local c = v and v.BgColor
	if typeof(c) == "Color3" then
		return c
	end
	return nil
end

local function getVariantItemId(variantKey, baseName)
	local v = getVariantInfo(variantKey)
	if not v or variantKey == "Normal" then
		return baseName
	end
	local prefix = tostring(v.Prefix or (variantKey .. " "))
	return prefix .. baseName
end

local function getVariantDisplayData(variantKey, baseName, baseData)
	local itemId = getVariantItemId(variantKey, baseName)
	local cfg = Brainrots[itemId]

	if cfg and type(cfg) == "table" then
		return itemId, cfg
	end

	local v = getVariantInfo(variantKey)
	local mult = tonumber(v and v.IncomeMult) or 1

	local render = tostring(baseData.Render or "")
	local goldenRender = tostring(baseData.GoldenRender or baseData.Render or "")
	local diamondRender = tostring(baseData.DiamondRender or baseData.Render or "")

	if variantKey == "Golden" then
		render = goldenRender
	elseif variantKey == "Diamond" then
		render = diamondRender
	end

	local out = {}
	for k, val in pairs(baseData) do
		out[k] = val
	end
	out.Render = render
	out.GoldenRender = goldenRender
	out.DiamondRender = diamondRender
	out.Income = math.floor((tonumber(baseData.Income) or 0) * mult + 0.5)

	return itemId, out
end

local allItemIds = {}
for _, item in ipairs(baseBrainrotList) do
	for _, vKey in ipairs(supportedVariants) do
		table.insert(allItemIds, getVariantItemId(vKey, item.Name))
	end
end

local totalBrainrots = #allItemIds

local function hasBrainrot(itemId)
	return inventory:FindFirstChild(itemId) ~= nil
end

local clonesById = {}
local currentVariant = "Normal"

local function setLocked(gui, data)
	local bname = gui:FindFirstChild("BName", true)
	local price = gui:FindFirstChild("Price", true)
	local rarity = gui:FindFirstChild("RarityText", true)
	local icon = gui:FindFirstChild("Icon", true)

	if bname and bname:IsA("TextLabel") then bname.Text = "???" end
	if price and price:IsA("TextLabel") then price.Text = "???" end
	if rarity and rarity:IsA("TextLabel") then rarity.Text = "???" end
	if icon and icon:IsA("ImageLabel") then
		icon.Image = tostring(data.Render or "")
		icon.ImageColor3 = Color3.new(0, 0, 0)
	end
end

local function setUnlocked(gui, displayName, data)
	local bname = gui:FindFirstChild("BName", true)
	local price = gui:FindFirstChild("Price", true)
	local rarity = gui:FindFirstChild("RarityText", true)
	local icon = gui:FindFirstChild("Icon", true)

	if bname and bname:IsA("TextLabel") then bname.Text = displayName end
	if price and price:IsA("TextLabel") then
		local income = tonumber(data.Income) or 0
		price.Text = MoneyLib.roundNumber(income) .. CurrencyUtil.getPerSecondSuffix()
	end
	if rarity and rarity:IsA("TextLabel") then rarity.Text = tostring(data.Rarity or "") end
	if icon and icon:IsA("ImageLabel") then
		icon.Image = tostring(data.Render or "")
		icon.ImageColor3 = Color3.new(1, 1, 1)
	end
end

local function refreshBrainrotLocks()
	for itemId, entry in pairs(clonesById) do
		if hasBrainrot(itemId) then
			setUnlocked(entry.Gui, entry.DisplayName, entry.Data)
		else
			setLocked(entry.Gui, entry.Data)
		end
	end
end

local function countCollectedGlobal()
	local c = 0
	for _, itemId in ipairs(allItemIds) do
		if inventory:FindFirstChild(itemId) then
			c += 1
		end
	end
	return c
end

local function updateCollectedTexts()
	local collected = countCollectedGlobal()
	local text = "Collected : " .. tostring(collected) .. "/" .. tostring(totalBrainrots)

	if indexCollected:IsA("TextLabel") or indexCollected:IsA("TextButton") then
		indexCollected.Text = text
	else
		local tl = indexCollected:FindFirstChildWhichIsA("TextLabel", true)
		if tl then tl.Text = text end
	end

	if rewardsCollected:IsA("TextLabel") or rewardsCollected:IsA("TextButton") then
		rewardsCollected.Text = text
	else
		local tl2 = rewardsCollected:FindFirstChildWhichIsA("TextLabel", true)
		if tl2 then tl2.Text = text end
	end
end

local questKeys = {}
for k in pairs(IndexConfig) do
	if typeof(k) == "number" then
		table.insert(questKeys, k)
	end
end
table.sort(questKeys, function(a, b) return a < b end)

local indexRewardsFolder = player:FindFirstChild("IndexRewards")

local function isClaimed(questId)
	if not indexRewardsFolder then
		indexRewardsFolder = player:FindFirstChild("IndexRewards")
	end
	if not indexRewardsFolder then
		return false
	end
	local v = indexRewardsFolder:FindFirstChild(tostring(questId))
	if v and v:IsA("BoolValue") then
		return v.Value == true
	end
	return false
end

local questUIs = {}

local function setClaimText(questGui, text)
	local claim = questGui:FindFirstChild("Claim", true)
	if not claim then return end

	local t = nil
	local main = claim:FindFirstChild("Main", true)
	if main then
		t = main:FindFirstChild("Textl", true)
	end
	if not t then
		t = claim:FindFirstChild("Textl", true)
	end

	if t and (t:IsA("TextLabel") or t:IsA("TextButton")) then
		t.Text = text

 		local shadow = t:FindFirstChild("Shadow")
		if shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton")) then
			shadow.Text = text
		end
	end
end


local function setClaimEnabled(questGui, enabled)
	local claim = questGui:FindFirstChild("Claim", true)
	if not claim then return end
	if claim:IsA("GuiButton") then
		claim.Active = enabled
		claim.AutoButtonColor = enabled
	end
end

for _, questId in ipairs(questKeys) do
	local cfg = IndexConfig[questId]
	local questGui = rewardsTemplate:Clone()
	questGui.Name = "Quest_" .. tostring(questId)
	questGui.Parent = rewardsScroll
	questGui.Visible = true
	questGui.LayoutOrder = questId

	local icon = questGui:FindFirstChild("Icon", true)
	if icon and icon:IsA("ImageLabel") then
		icon.Image = tostring(cfg.Icon or "")
	end

	local bg = questGui:FindFirstChild("Bg", true)
	if bg and bg:IsA("Frame") and typeof(cfg.BgColor) == "Color3" then
		bg.BackgroundColor3 = cfg.BgColor
	elseif questGui:IsA("Frame") and typeof(cfg.BgColor) == "Color3" then
		questGui.BackgroundColor3 = cfg.BgColor
	end

	local gifts = questGui:FindFirstChild("Gifts", true)
	if gifts then
		local giftTemplate = gifts:FindFirstChild("Template")
		if giftTemplate then
			giftTemplate.Visible = false
			for _, ch in ipairs(gifts:GetChildren()) do
				if ch ~= giftTemplate and ch:IsA("GuiObject") then
					ch:Destroy()
				end
			end

			local rewardOrder = 0
			for _, reward in pairs(cfg.Rewards or {}) do
				rewardOrder += 1
				local rGui = giftTemplate:Clone()
				rGui.Parent = gifts
				rGui.Visible = true
				rGui.LayoutOrder = rewardOrder

				local rRender = rGui:FindFirstChild("Render", true)
				if rRender and rRender:IsA("ImageLabel") then
					rRender.Image = tostring(reward.Icon or "")
				end

				local rAmount = rGui:FindFirstChild("Amount", true)
				if rAmount and (rAmount:IsA("TextLabel") or rAmount:IsA("TextButton")) then
					rAmount.Text = "x" .. tostring(reward.Amount or "")
				end
			end
		end
	end

	local claimBtn = questGui:FindFirstChild("Claim", true)
	if claimBtn and claimBtn:IsA("GuiButton") then
		claimBtn.MouseButton1Click:Connect(function()
			claimRemote:FireServer(questId)
		end)
	end

	questUIs[questId] = questGui
end

local function updateQuestTexts()
	local collected = countCollectedGlobal()
	for questId, questGui in pairs(questUIs) do
		local howMuch = questGui:FindFirstChild("HowMuch", true)
		if howMuch and (howMuch:IsA("TextLabel") or howMuch:IsA("TextButton")) then
			howMuch.Text = "Collect " .. tostring(questId) .. " Brainrots"
			local shadow = howMuch:FindFirstChild("Shadow")
			if shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton")) then
				shadow.Text = howMuch.Text
			end
		end

		if isClaimed(questId) then
			setClaimText(questGui, "Claimed")
			setClaimEnabled(questGui, false)
		else
			setClaimText(questGui, "Claim")
			setClaimEnabled(questGui, collected >= questId)
		end
	end
	
	local ToClaim = 0
	for questId, _ in pairs(questUIs) do
		if (not isClaimed(questId)) and collected >= questId then
			ToClaim +=1
		end
	end
	UpdateIndexBadge(ToClaim)
end

local function hookIndexRewardsFolder()
	indexRewardsFolder = player:FindFirstChild("IndexRewards")
	if not indexRewardsFolder then return end
	for _, ch in ipairs(indexRewardsFolder:GetChildren()) do
		if ch:IsA("BoolValue") then
			ch:GetPropertyChangedSignal("Value"):Connect(function()
				updateQuestTexts()
			end)
		end
	end
	indexRewardsFolder.ChildAdded:Connect(function(ch)
		if ch:IsA("BoolValue") then
			ch:GetPropertyChangedSignal("Value"):Connect(function()
				updateQuestTexts()
			end)
			updateQuestTexts()
		end
	end)
end

player.ChildAdded:Connect(function(ch)
	if ch.Name == "IndexRewards" then
		hookIndexRewardsFolder()
		updateQuestTexts()
	end
end)

local function clearIndexClones()
	for _, child in ipairs(inexFrame:GetChildren()) do
		if child ~= brainrotTemplate and child:IsA("GuiObject") and child.Name:match("^Brainrot_") then
			child:Destroy()
		end
	end
end

local function applyVariantColor(gui, variantKey)
	local col = getVariantColor(variantKey)
	if not col then
		return
	end
	if gui and gui:IsA("GuiObject") then
		gui.BackgroundColor3 = col
	end
end

local function buildIndexForVariant(variantKey)
	currentVariant = variantKey or "Normal"
	clonesById = {}

	clearIndexClones()

	for i, item in ipairs(baseBrainrotList) do
		local baseName = item.Name
		local baseData = item.Data

		local itemId, variantData = getVariantDisplayData(currentVariant, baseName, baseData)

		local gui = brainrotTemplate:Clone()
		gui.Name = "Brainrot_" .. tostring(i)
		gui.Parent = inexFrame
		gui.Visible = true
		gui.LayoutOrder = i

		applyVariantColor(gui, currentVariant)

		clonesById[itemId] = { Gui = gui, Data = variantData, DisplayName = baseName }
	end

	refreshBrainrotLocks()
	updateCollectedTexts()
	updateQuestTexts()
end

local function setVariant(variantKey)
	if currentVariant == variantKey then
		return
	end
	buildIndexForVariant(variantKey)
end

local function isSupportedVariantButton(name)
	if name == "Normal" then return true end
	if name == "Golden" then return true end
	if name == "Diamond" then return true end
	return false
end

for _, b in ipairs(buttonsFrame:GetChildren()) do
	if b:IsA("GuiButton") and isSupportedVariantButton(b.Name) then
		b.MouseButton1Click:Connect(function()
			setVariant(b.Name)
		end)
	end
end

inventory.ChildAdded:Connect(function()
	refreshBrainrotLocks()
	updateCollectedTexts()
	updateQuestTexts()
end)

inventory.ChildRemoved:Connect(function()
	refreshBrainrotLocks()
	updateCollectedTexts()
	updateQuestTexts()
end)

hookIndexRewardsFolder()
setTab(true)
buildIndexForVariant("Normal")
