local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local purchaseEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CometMerchantPurchase")

local gui = player:WaitForChild("PlayerGui")
local frames = gui:WaitForChild("Frames")
local cmGui = frames:WaitForChild("CometMerchant")
local main = cmGui:WaitForChild("Main")
local template = main:WaitForChild("Template")

template.Visible = false

local clones = {}
local itemConnections = {}

local function setTextPair(label, text)
	if not label then return end
	if label:IsA("TextLabel") or label:IsA("TextButton") then
		label.Text = text
		local shadow = label:FindFirstChild("Shadow")
		if shadow and (shadow:IsA("TextLabel") or shadow:IsA("TextButton")) then
			shadow.Text = text
		end
	end
end

local function clearUI()
	for _, c in ipairs(itemConnections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(itemConnections)

	for _, v in ipairs(clones) do
		if v and v.Parent then
			v:Destroy()
		end
	end
	table.clear(clones)
end

local function buildUI()
	clearUI()

	local merchant = player:FindFirstChild("CometMerchant")
	if not merchant then return end

	local offers = {}
	for _, inst in ipairs(merchant:GetChildren()) do
		if inst:IsA("NumberValue") and inst:GetAttribute("IsOffer") == true then
			table.insert(offers, inst)
		end
	end

	table.sort(offers, function(a, b)
		return (tonumber(a:GetAttribute("OfferIndex")) or 0) < (tonumber(b:GetAttribute("OfferIndex")) or 0)
	end)

	for i = 1, math.min(3, #offers) do
		local stockValue = offers[i]

		local fullPath = tostring(stockValue:GetAttribute("FullPath") or stockValue.Name)
		local amount = tonumber(stockValue:GetAttribute("Amount")) or 0
		local price = tonumber(stockValue:GetAttribute("Price")) or 0
		local icon = tostring(stockValue:GetAttribute("Icon") or "")
		local display_name = tostring(stockValue:GetAttribute("Display_name") or "")
		local DESC = tostring(stockValue:GetAttribute("Desc") or "")

		local clone = template:Clone()
		clone.Visible = true
		clone.Name = "Offer_" .. tostring(i)
		clone.Parent = template.Parent
		if clone:IsA("GuiObject") then
			clone.LayoutOrder = i
		end

		local tName = clone:FindFirstChild("TName", true)
		setTextPair(tName, "+" .. display_name)

		local left = clone:FindFirstChild("Left", true)
		setTextPair(left, "x" .. tostring(stockValue.Value) .. " Stock")

		local iconObj = clone:FindFirstChild("Icon", true)
		if iconObj and iconObj:IsA("ImageLabel") then
			iconObj.Image = icon
		end

		local textL = clone:FindFirstChild("TextL", true)
		setTextPair(textL, tostring(price))
		
		local textLXD = clone:FindFirstChild("Info", true)
		setTextPair(textLXD, tostring(DESC))

		local buyRoot = clone:FindFirstChild("Buy", true)
		local buyButton

		if buyRoot and buyRoot:IsA("GuiButton") then
			buyButton = buyRoot
		elseif buyRoot then
			buyButton = buyRoot:FindFirstChildWhichIsA("GuiButton", true)
		end

		if buyButton then
			table.insert(itemConnections, buyButton.MouseButton1Click:Connect(function()
				if stockValue.Value <= 0 then
					return
				end
				purchaseEvent:FireServer(fullPath)
				print(fullPath)
			end))
		end

		table.insert(itemConnections, stockValue:GetPropertyChangedSignal("Value"):Connect(function()
			setTextPair(left, "x" .. tostring(stockValue.Value) .. " Stock")
		end))

		table.insert(itemConnections, stockValue:GetAttributeChangedSignal("IsOffer"):Connect(function()
			buildUI()
		end))

		table.insert(itemConnections, stockValue:GetAttributeChangedSignal("OfferIndex"):Connect(function()
			buildUI()
		end))

		clones[i] = clone
	end
end

local function hookMerchantSignals()
	local merchant = player:WaitForChild("CometMerchant")

	merchant.ChildAdded:Connect(function(child)
		if child:IsA("NumberValue") then
			buildUI()
		end
	end)

	merchant.ChildRemoved:Connect(function()
		buildUI()
	end)
end

hookMerchantSignals()
buildUI()
