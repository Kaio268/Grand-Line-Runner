local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ReactFrameModalAdapter = require(Modules:WaitForChild("ReactFrameModalAdapter"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local Rebirths = require(Modules:WaitForChild("Configs"):WaitForChild("Rebirths"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local RebirthScreen = require(UiFolder:WaitForChild("Rebirth"):WaitForChild("RebirthScreen"))

local RebirthRemote = ReplicatedStorage:WaitForChild("RebirthRemote")

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactRebirthRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Rebirth",
	hostName = "ReactRebirthHost",
	backdropName = "ReactRebirthBackdrop",
	backdropActive = false,
	modalStateKey = "RebirthModal",
	minSize = Vector2.new(620, 520),
	maxSize = Vector2.new(840, 700),
	frameSize = UDim2.fromScale(0.54, 0.62),
	createFrameIfMissing = true,
	standalone = true,
})

local destroyed = false
local renderQueued = false
local connections = {}
local clickDebounce = false
local scheduleRender

local unregisterModal = ReactModalRegistry.Register("Rebirth", {
	toggle = function()
		modalAdapter:Toggle()
		if scheduleRender then
			scheduleRender()
		end
	end,
	open = function()
		if not modalAdapter:IsVisible() then
			modalAdapter:Toggle()
		end
		if scheduleRender then
			scheduleRender()
		end
	end,
	close = function()
		modalAdapter:Close()
	end,
	isVisible = function()
		return modalAdapter:IsVisible()
	end,
})

local leaderstats = player:WaitForChild("leaderstats")
local hiddenStats = player:WaitForChild("HiddenLeaderstats")
local rebirthsValue = leaderstats:WaitForChild("Rebirths")
local moneyValue = CurrencyUtil.waitForPrimaryValueObject(player, 10)
local shipLevelValue = hiddenStats:WaitForChild("PlotUpgrade")

if not moneyValue then
	error("Primary currency value object was not found for React rebirth UI")
end

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function buildRewards(config)
	local rewards = {}
	for key, data in pairs((config and config.Getting) or {}) do
		rewards[#rewards + 1] = {
			key = tostring(key),
			icon = tostring(data and data.Icon or ""),
			text = string.format("x%s %s", tostring(data and data.Amount or ""), tostring(key)),
		}
	end
	table.sort(rewards, function(a, b)
		return a.key < b.key
	end)
	return rewards
end

local function buildViewModel()
	local nextIndex = rebirthsValue.Value + 1
	local config = Rebirths.GetConfig(nextIndex)
	if not config then
		return {
			isMaxed = true,
			canRebirth = false,
			moneyComplete = true,
			moneyProgress = 1,
			moneyText = "MAX",
			shipComplete = true,
			shipProgress = 1,
			shipText = "MAX",
			rewards = {},
		}
	end

	local price = math.max(0, tonumber(config.Price) or 0)
	local requiredShipLevel = math.max(0, tonumber(config.PlotUpgradeNeeded) or 0)
	local currentMoney = math.max(0, tonumber(moneyValue.Value) or 0)
	local currentShipLevel = math.max(0, tonumber(shipLevelValue.Value) or 0)

	return {
		isMaxed = false,
		canRebirth = currentMoney >= price and currentShipLevel >= requiredShipLevel,
		moneyComplete = price <= 0 or currentMoney >= price,
		moneyProgress = price > 0 and currentMoney / price or 1,
		moneyText = string.format("%s / %s", CurrencyUtil.formatCompact(currentMoney), CurrencyUtil.formatCompact(price)),
		shipComplete = requiredShipLevel <= 0 or currentShipLevel >= requiredShipLevel,
		shipProgress = requiredShipLevel > 0 and currentShipLevel / requiredShipLevel or 1,
		shipText = string.format("Lv %d / %d", currentShipLevel, requiredShipLevel),
		rewards = buildRewards(config),
	}
end

local function render()
	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end

	local viewModel = buildViewModel()
	root:render(ReactRoblox.createPortal(React.createElement(RebirthScreen, {
		canRebirth = viewModel.canRebirth,
		isMaxed = viewModel.isMaxed,
		moneyComplete = viewModel.moneyComplete,
		moneyProgress = viewModel.moneyProgress,
		moneyText = viewModel.moneyText,
		onClose = function()
			ReactModalRegistry.Close("Rebirth")
		end,
		onRebirth = function()
			if clickDebounce or not viewModel.canRebirth then
				return
			end
			clickDebounce = true
			RebirthRemote:FireServer()
			task.delay(0.35, function()
				clickDebounce = false
			end)
		end,
		rewards = viewModel.rewards,
		shipComplete = viewModel.shipComplete,
		shipProgress = viewModel.shipProgress,
		shipText = viewModel.shipText,
	}), host))
	modalAdapter:SyncOverlayState()
end

scheduleRender = function()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			render()
		end
	end)
end

connections[#connections + 1] = rebirthsValue:GetPropertyChangedSignal("Value"):Connect(scheduleRender)
connections[#connections + 1] = moneyValue:GetPropertyChangedSignal("Value"):Connect(scheduleRender)
connections[#connections + 1] = shipLevelValue:GetPropertyChangedSignal("Value"):Connect(scheduleRender)

render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
