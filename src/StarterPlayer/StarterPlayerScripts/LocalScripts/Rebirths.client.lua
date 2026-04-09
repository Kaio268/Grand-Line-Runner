local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer

local Rebirths = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Rebirths"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local RebirthRemote = ReplicatedStorage:WaitForChild("RebirthRemote")

local leaderstats = player:WaitForChild("leaderstats")
local hiddenStats = player:WaitForChild("HiddenLeaderstats")

local rebirthsValue = leaderstats:WaitForChild("Rebirths")
local moneyValue = CurrencyUtil.waitForPrimaryValueObject(player, 10)
if not moneyValue then
	error("Primary currency value object was not found for rebirth UI")
end
local shipLevelValue = hiddenStats:WaitForChild("PlotUpgrade")

local frames = player:WaitForChild("PlayerGui"):WaitForChild("Frames")
local main = frames:WaitForChild("Rebirth"):WaitForChild("Main")

local rebirthButton = main:WaitForChild("Rebirth")

local function getSectionBar(section, sectionName)
	local directBar = section:FindFirstChild("Bar")
	if directBar and directBar:IsA("GuiObject") then
		return directBar
	end

	local track = section:WaitForChild("Track")
	local nestedBar = track:WaitForChild("Bar")
	if nestedBar:IsA("GuiObject") then
		return nestedBar
	end

	error(string.format("Rebirth %s bar was not found", sectionName))
end

local moneyUI = main:WaitForChild("Money")
local moneyText = moneyUI:WaitForChild("Value")
local moneyBar = getSectionBar(moneyUI, "money")

local shipUI = main:WaitForChild("Speed")
local shipText = shipUI:WaitForChild("Value")
local shipBar = getSectionBar(shipUI, "ship")

local youGet = main:WaitForChild("YouGet")
local template = youGet:WaitForChild("Template")
template.Visible = false

local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local currentIndex = nil
local clickDebounce = false
local notIndicator = nil

local function tweenBar(bar, pct)
	pct = math.clamp(pct, 0, 1)
	TweenService:Create(bar, tweenInfo, { Size = UDim2.new(pct, 0, 1, 0) }):Play()
end

local function clearYouGet()
	for _, child in ipairs(youGet:GetChildren()) do
		if child ~= template and child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function setIcon(obj, icon)
	if not obj then return end
	pcall(function()
		obj.Image = icon or ""
	end)
end

local function setAmount(obj, amount)
	if not obj then return end
	pcall(function()
		obj.Text = "x" .. tostring(amount or "")
	end)
end

local function setSectionLabel(section, text)
	for _, descendant in ipairs(section:GetDescendants()) do
		if descendant:IsA("TextLabel") and descendant.Name ~= "Value" then
			descendant.Text = text
			return
		end
	end
end

local function rebuildGetting(config)
	clearYouGet()
	if not config or not config.Getting then return end

	local keys = {}
	for k in pairs(config.Getting) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	for i, k in ipairs(keys) do
		local data = config.Getting[k]
		local clone = template:Clone()
		clone.Visible = true
		clone.LayoutOrder = i
		clone.Parent = youGet

		local render = clone:FindFirstChild("Render", true)
		local amountLbl = clone:FindFirstChild("Amount", true)

		setIcon(render, data and data.Icon)
		setAmount(amountLbl, data and data.Amount)
	end
end

local function getNotIndicator()
	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		local hud = pg:FindFirstChild("HUD")
		if hud and hud:FindFirstChild("LButtons") and hud.LButtons:FindFirstChild("Rebirth") then
			return hud.LButtons.Rebirth:FindFirstChild("Not")
		end
	end

	local hud = StarterGui:FindFirstChild("HUD")
	if hud and hud:FindFirstChild("LButtons") and hud.LButtons:FindFirstChild("Rebirth") then
		return hud.LButtons.Rebirth:FindFirstChild("Not")
	end

	return nil
end

local function canRebirth(config)
	if not config then return false end
	local price = tonumber(config.Price) or 0
	local shipLevelNeeded = tonumber(config.PlotUpgradeNeeded) or 0
	return moneyValue.Value >= price and shipLevelValue.Value >= shipLevelNeeded
end

local function refreshNot(config)
	if notIndicator == nil or notIndicator.Parent == nil then
		notIndicator = getNotIndicator()
	end
	if notIndicator then
		notIndicator.Visible = canRebirth(config)
	end
end

local function applyUI(config)
	if not config then
		moneyText.Text = "MAX"
		shipText.Text = "MAX"
		clearYouGet()
		tweenBar(moneyBar, 1)
		tweenBar(shipBar, 1)
		refreshNot(nil)
		return
	end

	local price = math.max(0, tonumber(config.Price) or 0)
	local shipLevelNeeded = math.max(0, tonumber(config.PlotUpgradeNeeded) or 0)

	setSectionLabel(moneyUI, "Doubloons")
	setSectionLabel(shipUI, "Ship Level")

	moneyText.Text = string.format("%s / %s", CurrencyUtil.formatCompact(moneyValue.Value), CurrencyUtil.formatCompact(price))
	shipText.Text = string.format("Lv %d / %d", math.max(0, shipLevelValue.Value), shipLevelNeeded)

	tweenBar(moneyBar, price > 0 and (moneyValue.Value / price) or 1)
	tweenBar(shipBar, shipLevelNeeded > 0 and (shipLevelValue.Value / shipLevelNeeded) or 1)

	refreshNot(config)
end

local function update()
	local nextIndex = rebirthsValue.Value + 1
	local config = Rebirths.GetConfig(nextIndex)

	if currentIndex ~= nextIndex then
		currentIndex = nextIndex
		rebuildGetting(config)
	end

	applyUI(config)
end

rebirthsValue:GetPropertyChangedSignal("Value"):Connect(update)
moneyValue:GetPropertyChangedSignal("Value"):Connect(update)
shipLevelValue:GetPropertyChangedSignal("Value"):Connect(update)

rebirthButton.MouseButton1Click:Connect(function()
	if clickDebounce then return end
	clickDebounce = true
	RebirthRemote:FireServer()
	task.delay(0.35, function()
		clickDebounce = false
	end)
end)

update()
