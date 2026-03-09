local MS = game:GetService("MarketplaceService")
local player = game:GetService("Players").LocalPlayer

local ProductId = 1667343349 

local priceCache = {}

local function getPrice(gamePassId)
	if priceCache[gamePassId] ~= nil then
		return priceCache[gamePassId]
	end

	local price = 0
	local ok, result = pcall(function()
		return MS:GetProductInfo(gamePassId, Enum.InfoType.GamePass)
	end)
	if ok and typeof(result) == "table" then
		price = tonumber(result.PriceInRobux or result.Price or 0) or 0
	end

	priceCache[gamePassId] = price
	return price
end

local passes = player:WaitForChild("Passes")
local vip = passes:WaitForChild("x2 Money")

local function refreshPrice()
	if vip.Value == true then
		script.Parent.Frame.TextLabel.Text = "Owned"
		script.Parent.Frame.TextLabel.Shadow.Text = "Owned"

	else		
		script.Parent.Frame.TextLabel.Text ="" .. getPrice(ProductId)
		script.Parent.Frame.TextLabel.Shadow.Text ="" .. getPrice(ProductId)
	end
end

vip:GetPropertyChangedSignal("Value"):Connect(refreshPrice)

script.Parent.MouseButton1Click:Connect(function()
	MS:PromptGamePassPurchase(player, ProductId)
	refreshPrice()
end)

refreshPrice()
