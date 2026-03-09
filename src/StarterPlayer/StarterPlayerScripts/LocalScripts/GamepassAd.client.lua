local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("HUD")
local ad = hud:WaitForChild("GamepassesAd")

local cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gamepasses"))

local icon = ad:WaitForChild("Icon")
local info = ad:WaitForChild("Info")
local pName = ad:WaitForChild("PName")
local pShadow = pName:WaitForChild("Shadow")
local priceLabel = ad:WaitForChild("Price")
local spinImage = ad:WaitForChild("ImageLabel")
local timeBar = ad:WaitForChild("Time")
local clickLabel = ad:WaitForChild("TextButton")

local uiScale = ad:FindFirstChildOfClass("UIScale")
if not uiScale then
	uiScale = Instance.new("UIScale")
	uiScale.Parent = ad
end

local items = {}
for name, data in pairs(cfg) do
	if typeof(data) == "table" and data.ID then
		table.insert(items, {
			Name = tostring(name),
			Data = data,
			Type = tostring(data.TYPE or "Gamepass"),
		})
	end
end

local priceCache = {}
local function getPrice(itemType, id)
	local key = itemType .. ":" .. tostring(id)
	if priceCache[key] ~= nil then
		return priceCache[key]
	end

	local infoType = Enum.InfoType.GamePass
	if itemType == "Product" then
		infoType = Enum.InfoType.Product
	end

	local price = 0
	local ok, result = pcall(function()
		return MarketplaceService:GetProductInfo(id, infoType)
	end)
	if ok and typeof(result) == "table" then
		price = tonumber(result.PriceInRobux or result.Price or 0) or 0
	end

	priceCache[key] = price
	return price
end

local ownedCache = {}
local function ownsGamepass(gamePassId)
	if ownedCache[gamePassId] ~= nil then
		return ownedCache[gamePassId]
	end

	local owned = false
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)
	if ok then
		owned = result and true or false
	end

	ownedCache[gamePassId] = owned
	return owned
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, gamePassId, wasPurchased)
	if plr == player and wasPurchased then
		ownedCache[gamePassId] = true
	end
end)

local function pickAvailable()
	local available = {}
	for _, item in ipairs(items) do
		if item.Type == "Product" then
			table.insert(available, item)
		else
			if not ownsGamepass(item.Data.ID) then
				table.insert(available, item)
			end
		end
	end
	if #available == 0 then
		return nil
	end
	return available[Random.new():NextInteger(1, #available)]
end

ad.Visible = false
uiScale.Scale = 0
ad.Position = UDim2.new(2, 0, 0.5, 0)

spinImage.Rotation = 0
TweenService:Create(
	spinImage,
	TweenInfo.new(16, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	{ Rotation = 360 }
):Play()

local activeTweens = {}
local function cancelTweens()
	for _, tw in ipairs(activeTweens) do
		pcall(function()
			tw:Cancel()
		end)
	end
	table.clear(activeTweens)
end

local rng = Random.new()
local adToken = 0
local currentItemType = nil
local currentItemId = nil
local promptDebounce = false

local function promptPurchase()
	if promptDebounce then return end
	if not currentItemId or not currentItemType then return end
	if not ad.Visible then return end

	promptDebounce = true
	pcall(function()
		if currentItemType == "Product" then
			MarketplaceService:PromptProductPurchase(player, currentItemId)
		else
			MarketplaceService:PromptGamePassPurchase(player, currentItemId)
		end
	end)
	task.delay(0.6, function()
		promptDebounce = false
	end)
end

clickLabel.MouseButton1Click:Connect(promptPurchase)

local function playAd(item)
	adToken += 1
	local token = adToken

	cancelTweens()

	local data = item.Data
	currentItemType = item.Type
	currentItemId = data.ID

	local price = getPrice(item.Type, data.ID)

	icon.Image = data.Icon or ""
	info.Text = data.Description or ""
	pName.Text = item.Name
	pShadow.Text = item.Name
	priceLabel.Text = "" .. tostring(price)

	ad.Visible = true
	uiScale.Scale = 0
	ad.Position = UDim2.new(2, 0, 0.5, 0)

	timeBar.Size = UDim2.new(1, 0, 1, 0)
	local timeTween = TweenService:Create(
		timeBar,
		TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 0, 1, 0) }
	)
	table.insert(activeTweens, timeTween)

	local inScale = TweenService:Create(
		uiScale,
		TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	local inPos = TweenService:Create(
		ad,
		TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.996, 0, 0.5, 0) }
	)
	table.insert(activeTweens, inScale)
	table.insert(activeTweens, inPos)

	inScale:Play()
	inPos:Play()
	timeTween:Play()

	task.wait(10)
	if token ~= adToken then return end

	cancelTweens()

	local outScale = TweenService:Create(
		uiScale,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 0 }
	)
	local outPos = TweenService:Create(
		ad,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(2, 0, 0.5, 0) }
	)
	table.insert(activeTweens, outScale)
	table.insert(activeTweens, outPos)

	outScale:Play()
	outPos:Play()

	task.wait(0.36)
	if token ~= adToken then return end

	ad.Visible = false
end

task.spawn(function()
	if #items == 0 then
		return
	end

	while true do
		task.wait(rng:NextNumber(5, 8))
		local pick = pickAvailable()
		if pick then
			playAd(pick)
		end
	end
end)
