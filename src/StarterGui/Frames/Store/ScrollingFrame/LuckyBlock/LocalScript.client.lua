local gui = script.Parent

local function findRequiredDescendant(root, name)
	local found = root:FindFirstChild(name, true)
	if found then
		return found
	end
	warn(("LuckyBlock UI is missing descendant '%s' under %s"):format(name, root:GetFullName()))
	return nil
end

local frame = gui
local level = findRequiredDescendant(frame, "Level")
if not level then
	return
end

local levelShadow = findRequiredDescendant(level, "Shadow")
if not levelShadow then
	return
end

local timer = findRequiredDescendant(gui, "Timer")
local buyButton = findRequiredDescendant(gui, "Button")
if not timer or not buyButton then
	return
end

local buyFrame = findRequiredDescendant(buyButton, "Frame")
local priceLabel = buyFrame and findRequiredDescendant(buyFrame, "Price")
local priceShadow = priceLabel and findRequiredDescendant(priceLabel, "Shadow")

level.RichText = true
levelShadow.RichText = true

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer

local serverLuck = workspace:WaitForChild("ServerLuck")
local luckTimer = workspace:WaitForChild("ServerLuckTimer")

local Products = {
	[2] = { id = 3515409012 },
	[4] = { id = 3515409311 },
	[8] = { id = 3515410147 },
	[16] = { id = 3515410559 },
}

local priceCache = {}

local function getPrice(productId)
	local cached = priceCache[productId]
	if cached then
		return cached
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	local price = 0
	if ok and info then
		price = info.PriceInRobux or 0
	end
	priceCache[productId] = price
	return price
end

local function formatTime(sec)
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%02d:%02d", m, s)
end

local function setLevelText(mult)
	if mult < 8 then
		local nextMult = mult * 2
		local txt = string.format('x%d -> <font color="#ff6b3a">x%d</font>', mult, nextMult)
		level.Text = txt
		levelShadow.Text = txt
	else
		local txt = string.format("x%d", mult)
		level.Text = txt
		levelShadow.Text = txt
	end
end

local function refresh()
	local mult = serverLuck.Value
	setLevelText(mult)

	if mult < 8 then
		local product = Products[mult * 2]
		if product and priceLabel and priceShadow then
			local priceText = " " .. getPrice(product.id)
			priceLabel.Text = priceText
			priceShadow.Text = priceText
		end
		buyButton.AutoButtonColor = true
		buyButton.Active = true
	else
		if priceLabel then
			priceLabel.Text = "Maxed"
		end
		if priceShadow then
			priceShadow.Text = "Maxed"
		end
		buyButton.AutoButtonColor = false
		buyButton.Active = false
	end

	timer.Text = formatTime(luckTimer.Value)
end

buyButton.MouseButton1Click:Connect(function()
	local mult = serverLuck.Value
	if mult >= 8 then
		return
	end
	local product = Products[mult * 2]
	if product then
		MarketplaceService:PromptProductPurchase(player, product.id)
	end
end)

serverLuck:GetPropertyChangedSignal("Value"):Connect(refresh)

luckTimer:GetPropertyChangedSignal("Value"):Connect(function()
	timer.Text = formatTime(luckTimer.Value)
end)

refresh()
