local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Gears = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local BuyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GearStore")
local RobuxRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GearStoreRobux")

local frames = playerGui:WaitForChild("Frames")
local gearStore = frames:WaitForChild("GearStore")
local scrollingFrame = gearStore:WaitForChild("ScrollingFrame")
local template = scrollingFrame:WaitForChild("Template")

local gearsFolder = player:WaitForChild("Gears")
local backpack = player:WaitForChild("Backpack")

local shorten = require(ReplicatedStorage.Modules.Shorten)

template.Visible = false

for _, child in ipairs(scrollingFrame:GetChildren()) do
	if child ~= template and child.Name ~= "UIGridLayout" and child.Name ~= "UIListLayout"  and child.Name ~= "///" then
		child:Destroy()
	end
end

local productPriceCache = {}
local items = {}

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

local function getDevProductPrice(productId)
	if typeof(productId) ~= "number" then
		return 0
	end
	if productPriceCache[productId] ~= nil then
		return productPriceCache[productId]
	end
	local price = 0
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
		price = info.PriceInRobux
	end
	productPriceCache[productId] = price
	return price
end

local function getFirstButton(root)
	if root:IsA("GuiButton") then
		return root
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiButton") then
			return d
		end
	end
	return nil
end

local function hasTool(gearName)
	if backpack:FindFirstChild(gearName) then
		return true
	end
	local char = player.Character
	if char and char:FindFirstChild(gearName) then
		return true
	end
	return false
end

local function setRobuxVisible(gearName)
	local item = items[gearName]
	if not item then
		return
	end
	local bv = gearsFolder:FindFirstChild(gearName)
	if (bv and bv:IsA("BoolValue")) or hasTool(gearName) then
		item.Robux.Visible = false
	else
		item.Robux.Visible = true
	end
end

local function setBuyState(gearName)
	local item = items[gearName]
	if not item then
		return
	end
	local buyText = item.BuyText
	local bv = gearsFolder:FindFirstChild(gearName)
	if not bv or not bv:IsA("BoolValue") then
		setText(buyText, shorten.roundNumber(item.Price) .. CurrencyUtil.getCompactSuffix())
		return
	end
	if bv.Value == true then
		setText(buyText, "Equipped")
	else
		setText(buyText, "Equip")
	end
end

local function hookBool(bv)
	if not bv:IsA("BoolValue") then
		return
	end
	if not items[bv.Name] then
		return
	end
	bv.Changed:Connect(function()
		setBuyState(bv.Name)
	end)
	setRobuxVisible(bv.Name)
	setBuyState(bv.Name)
end

local gearList = {}

for gearName, gearData in pairs(Gears) do
	local price = tonumber(gearData.Price) or 0
	table.insert(gearList, {
		Name = gearName,
		Data = gearData,
		Price = price
	})
end

table.sort(gearList, function(a, b)
	if a.Price == b.Price then
		return a.Name < b.Name
	end
	return a.Price < b.Price
end)

for index, gear in ipairs(gearList) do
	local gearName = gear.Name
	local gearData = gear.Data

	local clone = template:Clone()
	clone.Name = gearName
	clone.Visible = true
	clone.LayoutOrder = index 
	clone.Parent = scrollingFrame

	local price = tonumber(gearData.Price) or 0
	local productId = tonumber(gearData.ProductID)
	local robuxPrice = getDevProductPrice(productId)
	local icon = tostring(gearData.Icon or "")

	local buyText = clone:WaitForChild("Buy"):WaitForChild("Main"):WaitForChild("TextL")
	local robuxFrame = clone:WaitForChild("Robux")
	local robuxText = robuxFrame:WaitForChild("Main"):WaitForChild("TextL")

	setText(buyText, shorten.roundNumber(price) .. CurrencyUtil.getCompactSuffix())
	setText(robuxText, "" .. shorten.roundNumber(robuxPrice))

	local iconObj = clone:FindFirstChild("Icon")
	if iconObj and iconObj:IsA("ImageLabel") then
		iconObj.Image = icon
	elseif iconObj and iconObj:IsA("ImageButton") then
		iconObj.Image = icon
	end

	local addSpeed = clone:FindFirstChild("AddSpeed")
	if addSpeed then
		if addSpeed:IsA("TextLabel") then
			setText(addSpeed, gearName)
		else
			local t = addSpeed:FindFirstChild("TextL")
			if t and t:IsA("TextLabel") then
				setText(t, gearName)
			end
		end
		local shadow = addSpeed:FindFirstChild("Shadow")
		if shadow then
			if shadow:IsA("TextLabel") then
				setText(shadow, gearName)
			else
				local st = shadow:FindFirstChild("TextL")
				if st and st:IsA("TextLabel") then
					setText(st, gearName)
				end
			end
		end
	end

	items[gearName] = {
		Frame = clone,
		BuyText = buyText,
		Robux = robuxFrame,
		Price = price,
		ProductID = productId,
	}

	local buyButton = getFirstButton(clone:WaitForChild("Buy"))
	if buyButton then
		buyButton.Activated:Connect(function()
			BuyRemote:FireServer(gearName)
		end)
	end

	local robuxButton = getFirstButton(robuxFrame)
	if robuxButton then
		robuxButton.Activated:Connect(function()
			RobuxRemote:FireServer(gearName)
		end)
	end

	setRobuxVisible(gearName)
	setBuyState(gearName)
end

for _, child in ipairs(gearsFolder:GetChildren()) do
	hookBool(child)
end

gearsFolder.ChildAdded:Connect(function(child)
	hookBool(child)
end)

gearsFolder.ChildRemoved:Connect(function(child)
	if items[child.Name] then
		setRobuxVisible(child.Name)
		setBuyState(child.Name)
	end
end)

backpack.ChildAdded:Connect(function(inst)
	if inst:IsA("Tool") and items[inst.Name] then
		setRobuxVisible(inst.Name)
	end
end)

backpack.ChildRemoved:Connect(function(inst)
	if inst:IsA("Tool") and items[inst.Name] then
		setRobuxVisible(inst.Name)
	end
end)

player.CharacterAdded:Connect(function()
	for gearName in pairs(items) do
		setRobuxVisible(gearName)
	end
end)
