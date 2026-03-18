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
	if not stats then return nil end
	local v = stats:FindFirstChild("PlotUpgrade")
	if v and v:IsA("NumberValue") then
		return v
	end
	return nil
end

local function getPlot(player)
	for _, m in ipairs(PlotsFolder:GetChildren()) do
		if m:IsA("Model") then
			local ownerId = m:GetAttribute("OwnerUserId")
			if ownerId == player.UserId then
				return m
			end
		end
	end
	for _, m in ipairs(PlotsFolder:GetChildren()) do
		if m:IsA("Model") and m.Name == player.Name then
			return m
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
	local f = HiddenRoot:FindFirstChild(id)
	if not f then
		f = Instance.new("Folder")
		f.Name = id
		f.Parent = HiddenRoot
	end
	return f
end

local function moveTo(inst, parent)
	if inst and parent and inst.Parent ~= parent then
		inst.Parent = parent
	end
end

local function findFloor(map, hidden, floorName)
	if map then
		local f = map:FindFirstChild(floorName, true)
		if f then return f, "map" end
	end
	if hidden then
		local f = hidden:FindFirstChild(floorName)
		if f then return f, "hidden" end
	end
	return nil, nil
end

local function setStandSlotAttributes(standModel, upgrade)
	if not standModel or not standModel:IsA("Model") then
		return
	end

	local standName = standModel.Name
	local isVisible = PlotUpgradeConfig.IsStandVisible(upgrade, standName)
	local isUsable = PlotUpgradeConfig.IsStandUsable(upgrade, standName)
	local bonusInfo = PlotUpgradeConfig.GetSlotBonusInfo(upgrade, standName)
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

local function applyUpgrade(player, upgrade)
	upgrade = PlotUpgradeConfig.ClampLevel(upgrade)

	local plot = getPlot(player)
	if not plot then return false end

	local hidden = getHiddenFolder(plot)
	local map = plot:FindFirstChild("Map")
	local stands = plot:FindFirstChild("Stands")

	local did = false

	if map then
		local floor2, where2 = findFloor(map, hidden, "Floor2")
		local floor3, where3 = findFloor(map, hidden, "Floor3")

		if floor2 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgrade, "Floor2") then
				if where2 == "hidden" then moveTo(floor2, map) did = true end
			else
				if where2 == "map" then moveTo(floor2, hidden) did = true end
			end
		end

		if floor3 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgrade, "Floor3") then
				if where3 == "hidden" then moveTo(floor3, map) did = true end
			else
				if where3 == "map" then moveTo(floor3, hidden) did = true end
			end
		end
	end

	if stands then
		for _, child in ipairs(stands:GetChildren()) do
			local standName = child.Name
			if tonumber(standName) then
				setStandSlotAttributes(child, upgrade)
				if not PlotUpgradeConfig.IsStandVisible(upgrade, standName) then
					moveTo(child, hidden)
					did = true
				end
			end
		end

		for _, child in ipairs(hidden:GetChildren()) do
			local standName = child.Name
			if tonumber(standName) then
				setStandSlotAttributes(child, upgrade)
				if PlotUpgradeConfig.IsStandVisible(upgrade, standName) then
					moveTo(child, stands)
					did = true
				end
			end
		end

		for _, child in ipairs(stands:GetChildren()) do
			if tonumber(child.Name) then
				setStandSlotAttributes(child, upgrade)
			end
		end
	end

	return did
end

local function waitForPlot(player, timeout)
	local t0 = os.clock()
	while player.Parent do
		if getPlot(player) then return true end
		if timeout and (os.clock() - t0) >= timeout then return false end
		task.wait(0.2)
	end
	return false
end

local function setupPlayer(player)
	local up
	while player.Parent and not up do
		up = getUpgradeValue(player)
		if not up then task.wait(0.2) end
	end
	if not player.Parent or not up then return end

	waitForPlot(player, 20)

	local pending = false
	local function scheduleApply()
		if pending then return end
		pending = true
		task.defer(function()
			pending = false
			if player.Parent and up.Parent then
				applyUpgrade(player, up.Value)
			end
		end)
	end

	scheduleApply()

	local upConn = up:GetPropertyChangedSignal("Value"):Connect(function()
		scheduleApply()
	end)

	local plotConn
	local function hookPlot()
		local plot = getPlot(player)
		if not plot then return end
		if plotConn then plotConn:Disconnect() end
		plotConn = plot.DescendantAdded:Connect(function(inst)
			local n = inst.Name
			if n == "Map" or n == "Stands" or n == "Floor2" or n == "Floor3" or tonumber(n) then
				scheduleApply()
			end
		end)
	end

	hookPlot()

	local retryConn
	retryConn = task.spawn(function()
		while player.Parent and up.Parent do
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
			if upConn then upConn:Disconnect() end
			if plotConn then plotConn:Disconnect() end
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, p)
end
