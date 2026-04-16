local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local label1 = script.Parent
local valueTwo = label1:FindFirstChild("ValueTwo")

local sh = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shorten"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local character = script:FindFirstAncestorOfClass("Model")

local player = character and Players:GetPlayerFromCharacter(character)
while not player do
	task.wait()
	character = script:FindFirstAncestorOfClass("Model")
	player = character and Players:GetPlayerFromCharacter(character)
end

local coins = CurrencyUtil.waitForPrimaryValueObject(player, 10)
if not coins then
	error("Primary currency value object was not found for nametag value")
end

local function setMoneyText(num)
	num = math.floor(num)
	local txt = sh.roundNumber(num) .. CurrencyUtil.getCompactSuffix()

	if label1:IsA("TextLabel") or label1:IsA("TextButton") then
		label1.Text = txt
	end

	if valueTwo then
		if valueTwo:IsA("TextLabel") or valueTwo:IsA("TextButton") then
			valueTwo.Text = txt
		elseif valueTwo:IsA("StringValue") then
			valueTwo.Value = txt
		end
	end
end

local anim = Instance.new("NumberValue")
anim.Value = coins.Value

anim.Changed:Connect(function(v)
	setMoneyText(v)
end)

local currentTween

local function animateTo(newValue)
	if currentTween then
		currentTween:Cancel()
	end

	local duration = (newValue >= anim.Value) and 0.4 or 1

	currentTween = TweenService:Create(
		anim,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = newValue }
	)

	currentTween:Play()
end

coins:GetPropertyChangedSignal("Value"):Connect(function()
	animateTo(coins.Value)
end)

setMoneyText(coins.Value)
