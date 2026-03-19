local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))

local PlotSystem = workspace:WaitForChild("PlotSystem")
local Template = PlotSystem:WaitForChild("Plot")
local Positions = PlotSystem:WaitForChild("Positions")
local PlotsFolder = PlotSystem:WaitForChild("Plots")

local HiddenRoot = ServerStorage:FindFirstChild("HiddenPlots")
if not HiddenRoot then
	HiddenRoot = Instance.new("Folder")
	HiddenRoot.Name = "HiddenPlots"
	HiddenRoot.Parent = ServerStorage
end

local connsByPlayer = {}
local plotCommandFunction = ShipRuntimeSignals.GetPlotCommandFunction()

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

local function getOwnedPlot(player)
	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			local ownerId = plot:GetAttribute("OwnerUserId")
			local ownerName = plot:GetAttribute("OwnerName")
			if ownerId == player.UserId or plot.Name == player.Name or ownerName == player.Name then
				return plot
			end
		end
	end

	return nil
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

local function applyPlotUpgrade(plot, upgradeLevel)
	upgradeLevel = PlotUpgradeConfig.ClampLevel(upgradeLevel)

	local hidden = getHiddenFolder(plot)
	local map = plot:FindFirstChild("Map")
	local stands = plot:FindFirstChild("Stands")

	if map then
		local floor2, where2 = findFloor(map, hidden, "Floor2")
		local floor3, where3 = findFloor(map, hidden, "Floor3")

		if floor2 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgradeLevel, "Floor2") then
				if where2 == "hidden" then
					moveTo(floor2, map)
				end
			else
				if where2 == "map" then
					moveTo(floor2, hidden)
				end
			end
		end

		if floor3 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgradeLevel, "Floor3") then
				if where3 == "hidden" then
					moveTo(floor3, map)
				end
			else
				if where3 == "map" then
					moveTo(floor3, hidden)
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
				end
			end
		end

		for _, child in ipairs(hidden:GetChildren()) do
			local standName = child.Name
			if tonumber(standName) then
				setStandSlotAttributes(child, upgradeLevel)
				if PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName) then
					moveTo(child, stands)
				end
			end
		end

		for _, child in ipairs(stands:GetChildren()) do
			if tonumber(child.Name) then
				setStandSlotAttributes(child, upgradeLevel)
			end
		end
	end
end

local function hidePlotDefaults(plot)
	applyPlotUpgrade(plot, 0)
end

local function getBottomOffsetFromPivot(model)
	local pivot = model:GetPivot()
	local bbCF, bbSize = model:GetBoundingBox()
	local bbLocal = pivot:ToObjectSpace(bbCF)
	local bottomLocalY = bbLocal.Position.Y - (bbSize.Y / 2)
	return bottomLocalY
end

local function placePlotAtPos(model, posPart)
	local _, yaw, _ = posPart.CFrame:ToOrientation()
	local topY = posPart.Position.Y + (posPart.Size.Y / 2)
	local bottomOffset = getBottomOffsetFromPivot(model)
	local pivotY = topY - bottomOffset
	local pivotPos = Vector3.new(posPart.Position.X, pivotY, posPart.Position.Z)
	model:PivotTo(CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0))
end

local function createPlotForPos(posPart)
	local clone = Template:Clone()
	clone.Name = "Plot"
	local slot = Instance.new("ObjectValue")
	slot.Name = "Slot"
	slot.Value = posPart
	slot.Parent = clone
	clone.Parent = PlotsFolder
	placePlotAtPos(clone, posPart)
	hidePlotDefaults(clone)
	return clone
end

local function findPlotBySlot(posPart)
	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			local slot = plot:FindFirstChild("Slot")
			if slot and slot:IsA("ObjectValue") and slot.Value == posPart then
				return plot
			end
		end
	end
	return nil
end

local function ensurePlotsExist()
	for _, child in ipairs(Positions:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "Pos" then
			if not findPlotBySlot(child) then
				createPlotForPos(child)
			end
		end
	end
end

local function getFreePlot()
	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			local owner = plot:GetAttribute("OwnerUserId")
			if owner == nil then
				return plot
			end
		end
	end
	return nil
end

local function getSpawnPart(plot)
	local spawn = plot:FindFirstChild("SpawnLocation", true)
	if spawn and spawn:IsA("BasePart") then
		return spawn
	end

	local primaryPart = plot.PrimaryPart
	if primaryPart then
		return primaryPart
	end

	for _, descendant in ipairs(plot:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function teleportToCFrame(player, cf)
	local function doTeleport(character)
		local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
		if not hrp then
			return
		end
		character:PivotTo(cf)
	end

	if player.Character then
		doTeleport(player.Character)
	else
		player.CharacterAdded:Wait()
		if player.Character then
			doTeleport(player.Character)
		end
	end
end

local function teleportToPart(player, part)
	if not part or not part:IsA("BasePart") then
		return
	end
	teleportToCFrame(player, part.CFrame + Vector3.new(0, 3, 0))
end

local function teleportToPlot(player, plot)
	if not plot then
		return
	end
	local spawnPart = getSpawnPart(plot)
	if not spawnPart then
		return
	end
	teleportToPart(player, spawnPart)
end

local function standHasPlacedBrainrot(stand)
	return stand and stand:FindFirstChild("PlacedBrainrot") ~= nil
end

local function syncStandButtonGuiParent(player, stand, button, surfaceGui)
	if not (player and stand and button and surfaceGui) then
		return
	end

	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui and standHasPlacedBrainrot(stand) then
		surfaceGui.Parent = playerGui
		return
	end

	surfaceGui.Parent = button
end

local function setUpButton(player, stand)
	local button = stand:WaitForChild("LevelUp", 5)
	if not button then
		return
	end

	local surfaceGui = button:FindFirstChildOfClass("SurfaceGui")
	if not surfaceGui then
		return
	end

	surfaceGui.Adornee = button
	surfaceGui.ResetOnSpawn = false
	surfaceGui.Name = stand.Name

	syncStandButtonGuiParent(player, stand, button, surfaceGui)

	local addedConn = stand.ChildAdded:Connect(function(child)
		if not child:IsA("Model") then
			return
		end
		syncStandButtonGuiParent(player, stand, button, surfaceGui)
	end)

	local removedConn = stand.ChildRemoved:Connect(function(child)
		if not child:IsA("Model") then
			return
		end
		syncStandButtonGuiParent(player, stand, button, surfaceGui)
	end)

	return addedConn, removedConn
end

local function handleStands(player, plot)
	local standsFolder = plot:WaitForChild("Stands", 10)
	if not standsFolder then
		return
	end

	connsByPlayer[player] = connsByPlayer[player] or {}

	for _, stand in ipairs(standsFolder:GetChildren()) do
		if stand:IsA("Model") then
			local addedConn, removedConn = setUpButton(player, stand)
			if addedConn then
				table.insert(connsByPlayer[player], addedConn)
			end
			if removedConn then
				table.insert(connsByPlayer[player], removedConn)
			end
		end
	end

	local standsAddedConn = standsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			local addedConn, removedConn = setUpButton(player, child)
			if addedConn then
				table.insert(connsByPlayer[player], addedConn)
			end
			if removedConn then
				table.insert(connsByPlayer[player], removedConn)
			end
		end
	end)

	table.insert(connsByPlayer[player], standsAddedConn)
end

local function disconnectPlayerConns(player)
	local connections = connsByPlayer[player]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		pcall(function()
			if typeof(connection) == "RBXScriptConnection" then
				connection:Disconnect()
			end
		end)
	end

	connsByPlayer[player] = nil
end

local function clearPlayerStandSurfaceGuis(player)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("SurfaceGui") and tonumber(child.Name) then
			child:Destroy()
		end
	end
end

local function setupUpgradeSync(player, plot)
	disconnectPlayerConns(player)
	connsByPlayer[player] = {}

	local pending = false
	local function scheduleApply(value)
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if player.Parent and plot.Parent then
				applyPlotUpgrade(plot, value)
			end
		end)
	end

	task.spawn(function()
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

		scheduleApply(upgradeValue.Value)

		table.insert(connsByPlayer[player], upgradeValue:GetPropertyChangedSignal("Value"):Connect(function()
			scheduleApply(upgradeValue.Value)
		end))

		table.insert(connsByPlayer[player], plot.DescendantAdded:Connect(function(inst)
			local name = inst.Name
			if name == "Map" or name == "Stands" or name == "Floor2" or name == "Floor3" or tonumber(name) then
				scheduleApply(upgradeValue.Value)
			end
		end))
	end)
end

local function claimPlot(player, plot)
	if not plot then
		return nil
	end

	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("OwnerName", player.Name)
	plot.Name = player.Name

	local upgradeValue = getUpgradeValue(player)
	applyPlotUpgrade(plot, upgradeValue and upgradeValue.Value or 0)
	clearPlayerStandSurfaceGuis(player)

	local surfaceGui = player.PlayerGui and (player.PlayerGui:FindFirstChild("SurfaceGui") or player.PlayerGui:WaitForChild("SurfaceGui", 5))
	if surfaceGui and plot:FindFirstChild("SlotsUpgrades") and plot.SlotsUpgrades:FindFirstChild("MainPart") then
		surfaceGui.Adornee = plot.SlotsUpgrades.MainPart
	end

	local sign = plot:FindFirstChild("Sign", true)
	if sign then
		local playerDisplay = sign:FindFirstChild("PlayerDisplay", true)
		if playerDisplay then
			local surfaceGuiObject = playerDisplay:FindFirstChildOfClass("SurfaceGui")
			if surfaceGuiObject then
				local playerNameLabel = surfaceGuiObject:FindFirstChild("PlayerName", true)
				if playerNameLabel and playerNameLabel:IsA("TextLabel") then
					playerNameLabel.Text = player.Name .. "'s"
				end

				local playerIcon = surfaceGuiObject:FindFirstChild("PlayerIcon", true)
				if playerIcon and playerIcon:IsA("ImageLabel") then
					playerIcon.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
				end
			end
		end
	end

	teleportToPlot(player, plot)
	setupUpgradeSync(player, plot)
	handleStands(player, plot)
	return plot
end

local function assignPlot(player)
	ensurePlotsExist()
	return claimPlot(player, getFreePlot())
end

local function respawnFreshPlot(oldPlot)
	local guid = oldPlot:GetAttribute("PlotGuid")
	local slot = oldPlot:FindFirstChild("Slot")
	local posPart = slot and slot.Value

	oldPlot:Destroy()

	if guid then
		local hiddenFolder = HiddenRoot:FindFirstChild(guid)
		if hiddenFolder then
			hiddenFolder:Destroy()
		end
	end

	if posPart and posPart.Parent then
		local newPlot = createPlotForPos(posPart)
		newPlot:SetAttribute("OwnerUserId", nil)
		newPlot:SetAttribute("OwnerName", nil)
		newPlot.Name = "Plot"

		local sign = newPlot:FindFirstChild("Sign", true)
		if sign then
			local playerDisplay = sign:FindFirstChild("PlayerDisplay", true)
			if playerDisplay then
				local surfaceGuiObject = playerDisplay:FindFirstChildOfClass("SurfaceGui")
				if surfaceGuiObject then
					local playerNameLabel = surfaceGuiObject:FindFirstChild("PlayerName", true)
					if playerNameLabel and playerNameLabel:IsA("TextLabel") then
						playerNameLabel.Text = "Free"
					end
					local playerIcon = surfaceGuiObject:FindFirstChild("PlayerIcon", true)
					if playerIcon and playerIcon:IsA("ImageLabel") then
						playerIcon.Image = ""
					end
				end
			end
		end

		hidePlotDefaults(newPlot)
		return newPlot
	end

	return nil
end

local function resetPlayerPlot(player)
	disconnectPlayerConns(player)
	clearPlayerStandSurfaceGuis(player)

	local existingPlot = getOwnedPlot(player)
	local resetPlot = existingPlot and respawnFreshPlot(existingPlot) or nil
	if not resetPlot then
		ensurePlotsExist()
		resetPlot = getFreePlot()
	end

	return claimPlot(player, resetPlot)
end

ensurePlotsExist()

Players.PlayerAdded:Connect(function(player)
	assignPlot(player)
end)

Players.PlayerRemoving:Connect(function(player)
	disconnectPlayerConns(player)
	local plot = getOwnedPlot(player)
	if plot then
		respawnFreshPlot(plot)
	end
end)

plotCommandFunction.OnInvoke = function(action, player)
	if action ~= "reset" then
		return false, "unsupported_action"
	end

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local plot = resetPlayerPlot(player)
	if not plot then
		return false, "plot_unavailable"
	end

	return true, plot
end
