local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local remote = ReplicatedStorage.Remotes:WaitForChild("PlotUpgradeRemote")
local cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local ui = script.Parent
local info = ui:WaitForChild("Info")
local upgradeRoot = ui:WaitForChild("Upgrade")
local textL = upgradeRoot:WaitForChild("Main"):WaitForChild("TextL")

local short = require(ReplicatedStorage.Modules.Shorten)
local function getUpgradeValueObject()
	local stats = player:FindFirstChild("HiddenLeadderstats") or player:FindFirstChild("HiddenLeaderstats")
	if not stats then
		stats = player:WaitForChild("HiddenLeadderstats", 4) or player:WaitForChild("HiddenLeaderstats", 4)
	end
	if not stats then return nil end

	local v = stats:FindFirstChild("PlotUpgrade") or stats:WaitForChild("PlotUpgrade", 4)
	if v and v:IsA("NumberValue") then
		return v
	end
	return nil
end

local upVal = getUpgradeValueObject()

local function priceFor(upgrade: number)
	local starter = tonumber(cfg.StarterPrice) or 0
	local mult = tonumber(cfg.PriceMult) or 1
	local p = starter * (mult ^ math.max(0, upgrade))
	if p < 0 then p = 0 end
	return math.floor(p + 0.5)
end

local function updateUI()
	local cur = (upVal and upVal.Value) or 0
	info.Text = tostring(cur) .. " -> " .. tostring(cur + 1)
	textL.Text = short.roundNumber(priceFor(cur)) .. CurrencyUtil.getCompactSuffix()
end

updateUI()
if upVal then
	upVal:GetPropertyChangedSignal("Value"):Connect(updateUI)
end

local clickButton
if upgradeRoot:IsA("GuiButton") then
	clickButton = upgradeRoot
else
	clickButton = upgradeRoot:FindFirstChildWhichIsA("GuiButton", true)
end

if clickButton then
	clickButton.Activated:Connect(function()
		remote:FireServer()
		print(3211)
	end)
end
