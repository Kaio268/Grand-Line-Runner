local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer

local SpeedUpgrade = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("Configs")
		:WaitForChild("SpeedUpgrade")
)

local MoneyLib = require(ReplicatedStorage.Modules.Shorten)
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local function fmt(v)
	if typeof(v) == "number" then
		if MoneyLib and MoneyLib.roundNumber then
			return MoneyLib.roundNumber(v)
		end
		return tostring(v)
	end
	return tostring(v)
end

local remote = ReplicatedStorage:WaitForChild("BuySpeedUpgrade")

local gui = player:WaitForChild("PlayerGui")
local main = gui:WaitForChild("Frames"):WaitForChild("SpeedUpgrade"):WaitForChild("Main")

local hidden = player:WaitForChild("HiddenLeaderstats")
local speedValueObj = hidden:WaitForChild("Speed")

local connectedButtons = {}
local productPriceCache = {}

local function setText(inst, value)
	if not inst then return end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		local txt = tostring(value)
		inst.Text = txt
		local second = inst:FindFirstChild("2")
		if second and (second:IsA("TextLabel") or second:IsA("TextButton") or second:IsA("TextBox")) then
			second.Text = txt
		end
	end
end

local function computeCost(cfg, speedVal)
	local starter = cfg.Starter_Price or 0
	local mult = cfg.Price_Mult or 1
	local addSpeed = cfg.AddSpeed or 1

	local s = tonumber(speedVal) or 1
	if s < 1 then s = 1 end

	local level = math.max(s - 1, 0)

	local function priceForLevel(lv)
		return starter * (mult ^ lv)
	end

	local total = 0
	for i = 0, addSpeed - 1 do
		total += priceForLevel(level + i)
	end

	return math.floor(total + 0.5)
end


local function getProductPrice(productId)
	if typeof(productId) ~= "number" then return 0 end
	if productPriceCache[productId] ~= nil then
		return productPriceCache[productId]
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)

	local price = 0
	if ok and info and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
		price = info.PriceInRobux
	end

	productPriceCache[productId] = price
	return price
end

local function hookButton(btn, fn)
	if connectedButtons[btn] then return end
	connectedButtons[btn] = true
	btn.Activated:Connect(fn)
end

local function bindBuy(frameName, template)
	local buy = template:FindFirstChild("Buy")
	if not buy then return end

	if buy:IsA("GuiButton") then
		hookButton(buy, function()
			remote:FireServer(tostring(frameName))
		end)
	end

	for _, d in ipairs(buy:GetDescendants()) do
		if d:IsA("GuiButton") then
			hookButton(d, function()
				remote:FireServer(tostring(frameName))
			end)
		end
	end
end

local function bindRobux(productId, template)
	local robux = template:FindFirstChild("Robux")
	if not robux then return end
	if typeof(productId) ~= "number" then return end

	if robux:IsA("GuiButton") then
		hookButton(robux, function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end)
	end

	for _, d in ipairs(robux:GetDescendants()) do
		if d:IsA("GuiButton") then
			hookButton(d, function()
				MarketplaceService:PromptProductPurchase(player, productId)
			end)
		end
	end
end

local function updateOne(frameName, frame, cfg, speedVal)
	local template = frame:FindFirstChild("Template") or frame

	local addSpeed = cfg.AddSpeed or 0
	local addSpeedText = (addSpeed >= 0 and ("+" .. fmt(addSpeed)) or fmt(addSpeed)) .. " Speed"

	setText(template:FindFirstChild("AddSpeed"), addSpeedText)
	setText(template:FindFirstChild("Now"), fmt(speedVal))
	setText(template:FindFirstChild("After"), fmt(speedVal + addSpeed))

	local cost = computeCost(cfg, speedVal)

	local buy = template:FindFirstChild("Buy")
	local buyMain = buy and buy:FindFirstChild("Main")
	local buyTextL = buyMain and buyMain:FindFirstChild("TextL")
	setText(buyTextL, fmt(cost) .. CurrencyUtil.getCompactSuffix())

	local productId = cfg.ProductID
	local robux = template:FindFirstChild("Robux")
	local robuxMain = robux and robux:FindFirstChild("Main")
	local robuxTextL = robuxMain and robuxMain:FindFirstChild("TextL")

	local robuxPrice = getProductPrice(productId)
	setText(robuxTextL, "" .. fmt(robuxPrice))

	bindBuy(frameName, template)
	bindRobux(productId, template)
end

local function updateAll()
	local speedVal = speedValueObj.Value
	for k, cfg in pairs(SpeedUpgrade) do
		local f = main:FindFirstChild(tostring(k))
		if f then
			updateOne(k, f, cfg, speedVal)
		end
	end
end

updateAll()
speedValueObj.Changed:Connect(updateAll)
