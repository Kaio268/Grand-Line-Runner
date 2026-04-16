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
	local stats = player:FindFirstChild("HiddenLeaderstats")
	if not stats then
		stats = player:WaitForChild("HiddenLeaderstats", 4)
	end
	if not stats then
		return nil
	end

	local valueObject = stats:FindFirstChild("PlotUpgrade") or stats:WaitForChild("PlotUpgrade", 4)
	if valueObject and valueObject:IsA("NumberValue") then
		return valueObject
	end

	return nil
end

local upVal = getUpgradeValueObject()

local function getRebirthValueObject()
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = player:WaitForChild("leaderstats", 4)
	end
	if not leaderstats then
		return nil
	end

	local valueObject = leaderstats:FindFirstChild("Rebirths") or leaderstats:WaitForChild("Rebirths", 4)
	if valueObject and valueObject:IsA("NumberValue") then
		return valueObject
	end

	return nil
end

local rebirthVal = getRebirthValueObject()

local function getCurrentRebirths()
	return rebirthVal and math.max(0, tonumber(rebirthVal.Value) or 0) or 0
end

local function formatRequirementText(requirement)
	if typeof(requirement) ~= "table" then
		return "MAXED"
	end

	local lines = {
		string.format("%s%s", short.roundNumber(math.max(0, tonumber(requirement.Doubloons) or 0)), CurrencyUtil.getCompactSuffix()),
	}

	local materialParts = {}
	for _, materialKey in ipairs(cfg.MaterialOrder) do
		local amount = cfg.GetMaterialCost(requirement, materialKey)
		if amount > 0 then
			materialParts[#materialParts + 1] = string.format(
				"%s x%s",
				tostring(cfg.MaterialDisplayNames[materialKey] or materialKey),
				short.roundNumber(amount)
			)
		end
	end

	if #materialParts > 0 then
		lines[#lines + 1] = table.concat(materialParts, " | ")
	end

	local requiredRebirths = math.max(0, math.floor(tonumber(requirement.Rebirths) or 0))
	if requiredRebirths > 0 then
		lines[#lines + 1] = string.format("Rebirths %d / %d", getCurrentRebirths(), requiredRebirths)
	end

	return table.concat(lines, "\n")
end

local clickButton
if upgradeRoot:IsA("GuiButton") then
	clickButton = upgradeRoot
else
	clickButton = upgradeRoot:FindFirstChildWhichIsA("GuiButton", true)
end

local defaultButtonColor = clickButton and clickButton.BackgroundColor3
local defaultButtonText = clickButton and clickButton:IsA("TextButton") and clickButton.Text or nil

local function setButtonEnabled(enabled)
	if not clickButton then
		return
	end

	clickButton.Active = enabled
	clickButton.Selectable = enabled

	if clickButton:IsA("GuiButton") then
		clickButton.AutoButtonColor = enabled
	end

	if defaultButtonColor then
		if enabled then
			clickButton.BackgroundColor3 = defaultButtonColor
		else
			clickButton.BackgroundColor3 = Color3.fromRGB(82, 82, 82)
		end
	end

	if clickButton:IsA("TextButton") and defaultButtonText ~= nil then
		clickButton.Text = enabled and defaultButtonText or "MAXED"
	end
end

local function updateUI()
	local currentLevel = cfg.ClampLevel((upVal and upVal.Value) or 0)

	if info:IsA("TextLabel") then
		info.TextWrapped = true
	end
	if textL:IsA("TextLabel") then
		textL.TextWrapped = true
	end

	if cfg.IsMaxLevel(currentLevel) then
		info.Text = string.format("Ship Lv %d / %d\nFully Upgraded", currentLevel, cfg.MaxLevel)
		textL.Text = "MAXED"
		setButtonEnabled(false)
		return
	end

	local nextLevel = cfg.GetNextLevel(currentLevel) or currentLevel
	local requirement = cfg.GetRequirementForLevel(currentLevel)
	local requiredRebirths = math.max(0, math.floor(tonumber(requirement and requirement.Rebirths) or 0))
	info.Text = string.format(
		"Ship Lv %d / %d -> %d\n%s",
		currentLevel,
		cfg.MaxLevel,
		nextLevel,
		cfg.GetNextUnlockDescription(currentLevel)
	)
	if requiredRebirths > 0 then
		info.Text ..= string.format("\nRebirths %d / %d", getCurrentRebirths(), requiredRebirths)
	end
	textL.Text = formatRequirementText(requirement)
	setButtonEnabled(true)
end

updateUI()
if upVal then
	upVal:GetPropertyChangedSignal("Value"):Connect(updateUI)
end
if rebirthVal then
	rebirthVal:GetPropertyChangedSignal("Value"):Connect(updateUI)
end

if clickButton then
	clickButton.Activated:Connect(function()
		local currentLevel = cfg.ClampLevel((upVal and upVal.Value) or 0)
		if cfg.IsMaxLevel(currentLevel) then
			updateUI()
			return
		end

		remote:FireServer()
	end)
end
