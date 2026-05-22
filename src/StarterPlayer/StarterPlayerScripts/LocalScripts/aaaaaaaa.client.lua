
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

local ShipVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ShipVisuals"))

local function resolveWorkspacePath(pathSegments)
	local current = workspace
	for _, segment in ipairs(pathSegments or {}) do
		current = current and current:WaitForChild(segment, 30)
		if not current then
			return nil
		end
	end
	return current
end

local function getActiveShipsFolder()
	local shipSystem = resolveWorkspacePath(ShipVisuals.ShipSystemPath)
	return shipSystem and shipSystem:WaitForChild(ShipVisuals.ActiveShipsName, 30) or nil
end

local ActiveShips = getActiveShipsFolder()

local function getHomeIndicatorPart(shipModel)
	local homeConfig = ShipVisuals.RuntimePoints and ShipVisuals.RuntimePoints.Home
	local configuredName = homeConfig and tostring(homeConfig.Name or "") or ""

	if configuredName ~= "" then
		local home = shipModel:FindFirstChild(configuredName, true)
		if home then
			return home
		end
	end

	return shipModel:FindFirstChild("HOME", true) or shipModel:FindFirstChild("Home", true)
end

local function setIndicatorVisible(shipModel, state)
	local home = getHomeIndicatorPart(shipModel)
	if not home then return end

	local billboard = home:FindFirstChild("BillboardGui")
	if not billboard then return end

	local display = billboard:FindFirstChild("PlayerDisplay") or billboard:FindFirstChild("ImageLabel")
	if not display or not display:IsA("GuiObject") then return end

	display.Visible = state
end

local function isMyShip(shipModel)
	local ownerId = shipModel:GetAttribute(ShipVisuals.Attributes.OwnerUserId)
	if ownerId ~= nil then
		return ownerId == localPlayer.UserId
	end

	return shipModel.Name == localPlayer.Name
end

local function updateAllShips()
	if not ActiveShips then
		return
	end

	for _, ship in ipairs(ActiveShips:GetChildren()) do
		if ship:IsA("Model") then
			setIndicatorVisible(ship, isMyShip(ship))
		end
	end
end

local function watchShip(ship)
	if not ship:IsA("Model") then return end

	task.defer(function()
		setIndicatorVisible(ship, isMyShip(ship))
	end)

	ship:GetAttributeChangedSignal(ShipVisuals.Attributes.OwnerUserId):Connect(function()
		setIndicatorVisible(ship, isMyShip(ship))
	end)

	ship.DescendantAdded:Connect(function(desc)
		if
			desc.Name == "HOME"
			or desc.Name == "Home"
			or desc.Name == "BillboardGui"
			or desc.Name == "PlayerDisplay"
			or desc.Name == "PlayerIcon"
			or desc.Name == "PlayerName"
		then
			setIndicatorVisible(ship, isMyShip(ship))
		end
	end)
end

if ActiveShips then
	for _, ship in ipairs(ActiveShips:GetChildren()) do
		watchShip(ship)
	end

	ActiveShips.ChildAdded:Connect(function(ship)
		watchShip(ship)
		updateAllShips()
	end)

	ActiveShips.ChildRemoved:Connect(function()
		updateAllShips()
	end)
end

task.defer(updateAllShips)
