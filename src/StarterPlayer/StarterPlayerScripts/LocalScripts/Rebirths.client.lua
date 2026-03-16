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
local speedValue = hiddenStats:WaitForChild("Speed")

local frames = player:WaitForChild("PlayerGui"):WaitForChild("Frames")
local main = frames:WaitForChild("Rebirth"):WaitForChild("Main")

local rebirthButton = main:WaitForChild("Rebirth")

local moneyUI = main:WaitForChild("Money")
local moneyText = moneyUI:WaitForChild("Value")
local moneyBar = moneyUI:WaitForChild("Bar")

local speedUI = main:WaitForChild("Speed")
local speedText = speedUI:WaitForChild("Value")
local speedBar = speedUI:WaitForChild("Bar")

local youGet = main:WaitForChild("YouGet")
local template = youGet:WaitForChild("Template")
template.Visible = false

local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local currentIndex = nil
local clickDebounce = false
local notIndicator = nil

local function tweenBar(bar, pct)
	pct = math.clamp(pct, 0, 1)
	TweenService:Create(bar, tweenInfo, {Size = UDim2.new(pct, 0, 1, 0)}):Play()
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
	local speedNeeded = tonumber(config.SpeedNeeded) or 0
	return moneyValue.Value >= price and speedValue.Value >= speedNeeded
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
		speedText.Text = "MAX"
		clearYouGet()
		tweenBar(moneyBar, 1)
		tweenBar(speedBar, 1)
		refreshNot(nil)
		return
	end

	moneyText.Text = tostring(config.Price) .. CurrencyUtil.getCompactSuffix()
	speedText.Text = tostring(speedValue.Value) .. "/" .. tostring(config.SpeedNeeded)

	tweenBar(moneyBar, (config.Price and config.Price > 0) and (moneyValue.Value / config.Price) or 0)
	tweenBar(speedBar, (config.SpeedNeeded and config.SpeedNeeded > 0) and (speedValue.Value / config.SpeedNeeded) or 0)

	refreshNot(config)
end

local function update()
	local nextIndex = rebirthsValue.Value + 1
	local config = Rebirths[nextIndex]

	if currentIndex ~= nextIndex then
		currentIndex = nextIndex
		rebuildGetting(config)
	end

	applyUI(config)
end

rebirthsValue:GetPropertyChangedSignal("Value"):Connect(update)
moneyValue:GetPropertyChangedSignal("Value"):Connect(update)
speedValue:GetPropertyChangedSignal("Value"):Connect(update)

rebirthButton.MouseButton1Click:Connect(function()
	if clickDebounce then return end
	clickDebounce = true
	RebirthRemote:FireServer()
	task.delay(0.35, function()
		clickDebounce = false
	end)
end)

update()
