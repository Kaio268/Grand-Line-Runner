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
	if not stats then return nil end
	local v = stats:FindFirstChild("PlotUpgrade")
	if v and v:IsA("NumberValue") then
		return v
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

local function applyPlotUpgrade(plot, upgrade)
	upgrade = PlotUpgradeConfig.ClampLevel(upgrade)

	local hidden = getHiddenFolder(plot)
	local map = plot:FindFirstChild("Map")
	local stands = plot:FindFirstChild("Stands")

	if map then
		local floor2, where2 = findFloor(map, hidden, "Floor2")
		local floor3, where3 = findFloor(map, hidden, "Floor3")

		if floor2 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgrade, "Floor2") then
				if where2 == "hidden" then moveTo(floor2, map) end
			else
				if where2 == "map" then moveTo(floor2, hidden) end
			end
		end

		if floor3 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgrade, "Floor3") then
				if where3 == "hidden" then moveTo(floor3, map) end
			else
				if where3 == "map" then moveTo(floor3, hidden) end
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
				end
			end
		end

		for _, child in ipairs(hidden:GetChildren()) do
			local standName = child.Name
			if tonumber(standName) then
				setStandSlotAttributes(child, upgrade)
				if PlotUpgradeConfig.IsStandVisible(upgrade, standName) then
					moveTo(child, stands)
				end
			end
		end

		for _, child in ipairs(stands:GetChildren()) do
			if tonumber(child.Name) then
				setStandSlotAttributes(child, upgrade)
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
	for _, m in ipairs(PlotsFolder:GetChildren()) do
		if m:IsA("Model") then
			local slot = m:FindFirstChild("Slot")
			if slot and slot:IsA("ObjectValue") and slot.Value == posPart then
				return m
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
	for _, m in ipairs(PlotsFolder:GetChildren()) do
		if m:IsA("Model") then
			local owner = m:GetAttribute("OwnerUserId")
			if owner == nil then
				return m
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
	local pp = plot.PrimaryPart
	if pp then
		return pp
	end
	for _, d in ipairs(plot:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function teleportToCFrame(plr, cf)
	local function doTp(char)
		local hrp = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 10)
		if not hrp then return end
		char:PivotTo(cf)
	end
	if plr.Character then
		doTp(plr.Character)
	else
		plr.CharacterAdded:Wait()
		if plr.Character then
			doTp(plr.Character)
		end
	end
end

local function teleportToPart(plr, part)
	if not part or not part:IsA("BasePart") then return end
	teleportToCFrame(plr, part.CFrame + Vector3.new(0, 3, 0))
end

local function teleportToPlot(plr, plot)
	if not plot then return end
	local spawnPart = getSpawnPart(plot)
	if not spawnPart then return end
	teleportToPart(plr, spawnPart)
end

local function standHasPlacedBrainrot(stand)
	return stand and stand:FindFirstChild("PlacedBrainrot") ~= nil
end

local function syncStandButtonGuiParent(plr, stand, button, sg)
	if not (plr and stand and button and sg) then
		return
	end

	local playerGui = plr:FindFirstChild("PlayerGui")
	if playerGui and standHasPlacedBrainrot(stand) then
		sg.Parent = playerGui
		return
	end

	sg.Parent = button
end

local function SetUpButton(plr, stand)
	local button = stand:WaitForChild("LevelUp", 5)
	if not button then return end
	local sg = button:FindFirstChildOfClass("SurfaceGui")
	if not sg then return end

	sg.Adornee = button
	sg.ResetOnSpawn = false
	sg.Name = stand.Name

	syncStandButtonGuiParent(plr, stand, button, sg)

	local addedConn = stand.ChildAdded:Connect(function(child)
		if not child:IsA("Model") then return end
		syncStandButtonGuiParent(plr, stand, button, sg)
	end)

	local removedConn = stand.ChildRemoved:Connect(function(child)
		if not child:IsA("Model") then return end
		syncStandButtonGuiParent(plr, stand, button, sg)
	end)

	return addedConn, removedConn
end

local function HandleStands(plr, plot)
	local standsFolder = plot:WaitForChild("Stands", 10)
	if not standsFolder then return end

	connsByPlayer[plr] = connsByPlayer[plr] or {}

	for _, v in ipairs(standsFolder:GetChildren()) do
		if v:IsA("Model") then
			local addedConn, removedConn = SetUpButton(plr, v)
			if addedConn then
				table.insert(connsByPlayer[plr], addedConn)
			end
			if removedConn then
				table.insert(connsByPlayer[plr], removedConn)
			end
		end
	end

	local standsAddedConn = standsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			local addedConn, removedConn = SetUpButton(plr, child)
			if addedConn then
				table.insert(connsByPlayer[plr], addedConn)
			end
			if removedConn then
				table.insert(connsByPlayer[plr], removedConn)
			end
		end
	end)

	table.insert(connsByPlayer[plr], standsAddedConn)
end

local function disconnectPlayerConns(plr)
	local t = connsByPlayer[plr]
	if not t then return end
	for _, c in ipairs(t) do
		pcall(function()
			if typeof(c) == "RBXScriptConnection" then
				c:Disconnect()
			end
		end)
	end
	connsByPlayer[plr] = nil
end

local function clearPlayerStandSurfaceGuis(plr)
	local playerGui = plr:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("SurfaceGui") and tonumber(child.Name) then
			child:Destroy()
		end
	end
end

local function setupUpgradeSync(plr, plot)
	disconnectPlayerConns(plr)
	connsByPlayer[plr] = {}

	local pending = false
	local function scheduleApply(value)
		if pending then return end
		pending = true
		task.defer(function()
			pending = false
			if plr.Parent and plot.Parent then
				applyPlotUpgrade(plot, value)
			end
		end)
	end

	task.spawn(function()
		local up
		while plr.Parent and not up do
			up = getUpgradeValue(plr)
			if not up then task.wait(0.2) end
		end
		if not plr.Parent or not up then return end

		scheduleApply(up.Value)

		table.insert(connsByPlayer[plr], up:GetPropertyChangedSignal("Value"):Connect(function()
			scheduleApply(up.Value)
		end))

		table.insert(connsByPlayer[plr], plot.DescendantAdded:Connect(function(inst)
			local n = inst.Name
			if n == "Map" or n == "Stands" or n == "Floor2" or n == "Floor3" or tonumber(n) then
				scheduleApply(up.Value)
			end
		end))
	end)
end

local function claimPlot(plr, plot)
	if not plot then
		return nil
	end

	plot:SetAttribute("OwnerUserId", plr.UserId)
	plot:SetAttribute("OwnerName", plr.Name)
	plot.Name = plr.Name

	local upgradeValue = getUpgradeValue(plr)
	applyPlotUpgrade(plot, upgradeValue and upgradeValue.Value or 0)
	clearPlayerStandSurfaceGuis(plr)

	local surfaceGui = plr.PlayerGui and (plr.PlayerGui:FindFirstChild("SurfaceGui") or plr.PlayerGui:WaitForChild("SurfaceGui", 5))
	if surfaceGui and plot:FindFirstChild("SlotsUpgrades") and plot.SlotsUpgrades:FindFirstChild("MainPart") then
		surfaceGui.Adornee = plot.SlotsUpgrades.MainPart
	end

	local sign = plot:FindFirstChild("Sign", true)
	if sign then
		local pd = sign:FindFirstChild("PlayerDisplay", true)
		if pd then
			local sg = pd:FindFirstChildOfClass("SurfaceGui")
			if sg then
				local pn = sg:FindFirstChild("PlayerName", true)
				if pn and pn:IsA("TextLabel") then
					pn.Text = plr.Name .. "'s"
				end
				local pi = sg:FindFirstChild("PlayerIcon", true)
				if pi and pi:IsA("ImageLabel") then
					pi.Image = "rbxthumb://type=AvatarHeadShot&id=" .. plr.UserId .. "&w=150&h=150"
				end
			end
		end
	end

	teleportToPlot(plr, plot)
	setupUpgradeSync(plr, plot)
	HandleStands(plr, plot)
	return plot
end

local function assignPlot(plr)
	ensurePlotsExist()
	return claimPlot(plr, getFreePlot())
end

local function respawnFreshPlot(oldPlot)
	local guid = oldPlot:GetAttribute("PlotGuid")
	local slot = oldPlot:FindFirstChild("Slot")
	local posPart = slot and slot.Value

	oldPlot:Destroy()

	if guid then
		local hf = HiddenRoot:FindFirstChild(guid)
		if hf then
			hf:Destroy()
		end
	end

	if posPart and posPart.Parent then
		local newPlot = createPlotForPos(posPart)
		newPlot:SetAttribute("OwnerUserId", nil)
		newPlot:SetAttribute("OwnerName", nil)
		newPlot.Name = "Plot"

		local sign = newPlot:FindFirstChild("Sign", true)
		if sign then
			local pd = sign:FindFirstChild("PlayerDisplay", true)
			if pd then
				local sg = pd:FindFirstChildOfClass("SurfaceGui")
				if sg then
					local pn = sg:FindFirstChild("PlayerName", true)
					if pn and pn:IsA("TextLabel") then
						pn.Text = "Free"
					end
					local pi = sg:FindFirstChild("PlayerIcon", true)
					if pi and pi:IsA("ImageLabel") then
						pi.Image = ""
					end
				end
			end
		end

		hidePlotDefaults(newPlot)
		return newPlot
	end

	return nil
end

local function resetPlayerPlot(plr)
	disconnectPlayerConns(plr)
	clearPlayerStandSurfaceGuis(plr)

	local existingPlot = getOwnedPlot(plr)
	local resetPlot = existingPlot and respawnFreshPlot(existingPlot) or nil
	if not resetPlot then
		ensurePlotsExist()
		resetPlot = getFreePlot()
	end

	return claimPlot(plr, resetPlot)
end

ensurePlotsExist()

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

Players.PlayerAdded:Connect(function(plr)
	assignPlot(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	disconnectPlayerConns(plr)
	local plot = getOwnedPlot(plr)
	if plot then
		respawnFreshPlot(plot)
	end
end)
