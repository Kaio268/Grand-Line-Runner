local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))

local PlotSystem = workspace:WaitForChild("PlotSystem")
local PlotsFolder = PlotSystem:WaitForChild("Plots")

local HiddenRoot = ServerStorage:FindFirstChild("HiddenPlots")
if not HiddenRoot then
	HiddenRoot = Instance.new("Folder")
	HiddenRoot.Name = "HiddenPlots"
	HiddenRoot.Parent = ServerStorage
end

local function getPlayerStats(player)
	return player:FindFirstChild("HiddenLeaderstats")
end

local function getUpgradeValue(player)
	local stats = getPlayerStats(player)
	if not stats then
		return nil
	end

	local valueObject = stats:FindFirstChild("PlotUpgrade")
	if valueObject and valueObject:IsA("NumberValue") then
		return valueObject
	end

	return nil
end

local function getPlot(player)
	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			local ownerId = plot:GetAttribute("OwnerUserId")
			if ownerId == player.UserId then
				return plot
			end
		end
	end

	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") and plot.Name == player.Name then
			return plot
		end
	end

	return nil
end

local function ensurePlotGuid(plot)
	local id = plot:GetAttribute("PlotGuid")
	if not id then
		id = HttpService:GenerateGUID(false)
		plot:SetAttribute("PlotGuid", id)
	end
	return id
end

local function getHiddenFolder(plot)
	local id = ensurePlotGuid(plot)
	local folder = HiddenRoot:FindFirstChild(id)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = id
		folder.Parent = HiddenRoot
	end
	return folder
end

local function moveTo(inst, parent)
	if inst and parent and inst.Parent ~= parent then
		inst.Parent = parent
	end
end

local function findFloor(map, hidden, floorName)
	if map then
		local floor = map:FindFirstChild(floorName, true)
		if floor then
			return floor, "map"
		end
	end

	if hidden then
		local floor = hidden:FindFirstChild(floorName)
		if floor then
			return floor, "hidden"
		end
	end

	return nil, nil
end

local function setStandSlotAttributes(standModel, upgradeLevel)
	if not standModel or not standModel:IsA("Model") then
		return
	end

	local standName = standModel.Name
	local isVisible = PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName)
	local isUsable = PlotUpgradeConfig.IsStandUsable(upgradeLevel, standName)
	local bonusInfo = PlotUpgradeConfig.GetSlotBonusInfo(upgradeLevel, standName)
	local unlockLevel = PlotUpgradeConfig.GetStandUnlockLevel(standName)
	local bonusPercent = 0

	if bonusInfo then
		bonusPercent = math.max(0, math.floor((((tonumber(bonusInfo.Multiplier) or 1) - 1) * 100) + 0.5))
	end

	standModel:SetAttribute("ShipSlotVisible", isVisible)
	standModel:SetAttribute("ShipSlotUsable", isUsable)
	standModel:SetAttribute("ShipSlotLocked", isVisible and not isUsable)
	standModel:SetAttribute("ShipSlotRole", bonusInfo and tostring(bonusInfo.Label or "") or "")
	standModel:SetAttribute("ShipSlotBonusPercent", bonusPercent)
	standModel:SetAttribute("ShipSlotUnlockLevel", unlockLevel)
end

local function applyUpgrade(player, upgradeLevel)
	upgradeLevel = PlotUpgradeConfig.ClampLevel(upgradeLevel)

	local plot = getPlot(player)
	if not plot then
		return false
	end

	local hidden = getHiddenFolder(plot)
	local map = plot:FindFirstChild("Map")
	local stands = plot:FindFirstChild("Stands")
	local didChange = false

	if map then
		local floor2, where2 = findFloor(map, hidden, "Floor2")
		local floor3, where3 = findFloor(map, hidden, "Floor3")

		if floor2 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgradeLevel, "Floor2") then
				if where2 == "hidden" then
					moveTo(floor2, map)
					didChange = true
				end
			else
				if where2 == "map" then
					moveTo(floor2, hidden)
					didChange = true
				end
			end
		end

		if floor3 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgradeLevel, "Floor3") then
				if where3 == "hidden" then
					moveTo(floor3, map)
					didChange = true
				end
			else
				if where3 == "map" then
					moveTo(floor3, hidden)
					didChange = true
				end
			end
		end
	end

	if stands then
		for _, child in ipairs(stands:GetChildren()) do
			local standName = child.Name
			if tonumber(standName) then
				setStandSlotAttributes(child, upgradeLevel)
				if not PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName) then
					moveTo(child, hidden)
					didChange = true
				end
			end
		end

		for _, child in ipairs(hidden:GetChildren()) do
			local standName = child.Name
			if tonumber(standName) then
				setStandSlotAttributes(child, upgradeLevel)
				if PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName) then
					moveTo(child, stands)
					didChange = true
				end
			end
		end

		for _, child in ipairs(stands:GetChildren()) do
			if tonumber(child.Name) then
				setStandSlotAttributes(child, upgradeLevel)
			end
		end
	end

	return didChange
end

local function waitForPlot(player, timeout)
	local startTime = os.clock()
	while player.Parent do
		if getPlot(player) then
			return true
		end
		if timeout and (os.clock() - startTime) >= timeout then
			return false
		end
		task.wait(0.2)
	end
	return false
end

local function setupPlayer(player)
	local upgradeValue
	while player.Parent and not upgradeValue do
		upgradeValue = getUpgradeValue(player)
		if not upgradeValue then
			task.wait(0.2)
		end
	end
	if not player.Parent or not upgradeValue then
		return
	end

	waitForPlot(player, 20)

	local pending = false
	local function scheduleApply()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if player.Parent and upgradeValue.Parent then
				applyUpgrade(player, upgradeValue.Value)
			end
		end)
	end

	scheduleApply()

	local upgradeConn = upgradeValue:GetPropertyChangedSignal("Value"):Connect(function()
		scheduleApply()
	end)

	local plotConn
	local function hookPlot()
		local plot = getPlot(player)
		if not plot then
			return
		end
		if plotConn then
			plotConn:Disconnect()
		end
		plotConn = plot.DescendantAdded:Connect(function(inst)
			local name = inst.Name
			if name == "Map" or name == "Stands" or name == "Floor2" or name == "Floor3" or tonumber(name) then
				scheduleApply()
			end
		end)
	end

	hookPlot()

	task.spawn(function()
		while player.Parent and upgradeValue.Parent do
			if getPlot(player) then
				hookPlot()
				scheduleApply()
				break
			end
			task.wait(0.5)
		end
	end)

	player.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if upgradeConn then
				upgradeConn:Disconnect()
			end
			if plotConn then
				plotConn:Disconnect()
			end
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end
