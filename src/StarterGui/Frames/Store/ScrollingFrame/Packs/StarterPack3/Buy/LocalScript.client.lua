local MS = game:GetService(`MarketplaceService`)
local player = game:GetService(`Players`).LocalPlayer

local ProductId = 3509346182

local PackName = "Best Starter Pack"

local priceCache = {}

local function getPrice(gamePassId)
	if priceCache[gamePassId] ~= nil then
		return priceCache[gamePassId]
	end

	local price = 0
	local ok, result = pcall(function()
		return MS:GetProductInfo(gamePassId, Enum.InfoType.Product)
	end)
	if ok and typeof(result) == "table" then
		price = tonumber(result.PriceInRobux or result.Price or 0) or 0
	end

	priceCache[gamePassId] = price
	return price
end

local function refreshPrice()
	script.Parent.Frame.TextLabel.Text = "" .. getPrice(ProductId)
	script.Parent.Frame.TextLabel.Shadow.Text = "" .. getPrice(ProductId)

end

script.Parent.MouseButton1Click:Connect(function()
	MS:PromptProductPurchase(player, ProductId)
	refreshPrice()
end)

refreshPrice()
