local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
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
local characterSpawnConnsByPlayer = {}
local plotCommandFunction = ShipRuntimeSignals.GetPlotCommandFunction()
local getSpawnPart
local DEBUG_TRACE = RunService:IsStudio()

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function plotTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[PLOT TRACE] " .. message, ...))
end

local function mapTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[MAP TRACE] " .. message, ...))
end

local function playerTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[PLAYER TRACE] " .. message, ...))
end

local function spawnTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[SPAWN TRACE] " .. message, ...))
end

local function ownershipTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[OWNERSHIP TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function saveTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[SAVE TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function assignTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[ASSIGN TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function getPlotCount()
	local count = 0
	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			count += 1
		end
	end
	return count
end

local function logAllPlotsForAssignment(context)
	if not DEBUG_TRACE then
		return
	end

	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			local ownerUserId = plot:GetAttribute("OwnerUserId")
			local ownerName = plot:GetAttribute("OwnerName")
			local slot = plot:FindFirstChild("Slot")
			local posPart = slot and slot:IsA("ObjectValue") and slot.Value or nil
			assignTrace(
				"context=%s plot=%s ownerUserId=%s ownerUserIdType=%s ownerName=%s plotName=%s slot=%s slotPos=%s",
				tostring(context),
				formatInstancePath(plot),
				tostring(ownerUserId),
				typeof(ownerUserId),
				tostring(ownerName),
				tostring(plot.Name),
				formatInstancePath(posPart),
				formatVector3(posPart and posPart.Position or nil)
			)
		end
	end
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

local function getRebirthValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	local valueObject = leaderstats:FindFirstChild("Rebirths")
	if valueObject and valueObject:IsA("NumberValue") then
		return valueObject
	end

	return nil
end

local function getRebirthCount(player)
	local rebirthValue = getRebirthValue(player)
	if rebirthValue then
		return math.max(0, math.floor(tonumber(rebirthValue.Value) or 0))
	end

	return 0
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
			local matchedByUserId = ownerId == player.UserId
			local matchedByPlotName = plot.Name == player.Name
			local matchedByOwnerName = ownerName == player.Name
			ownershipTrace(
				"getOwnedPlot player=%s userId=%s plot=%s ownerUserId=%s ownerName=%s plotName=%s matchedByUserId=%s matchedByPlotName=%s matchedByOwnerName=%s",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(plot),
				tostring(ownerId),
				tostring(ownerName),
				tostring(plot.Name),
				tostring(matchedByUserId),
				tostring(matchedByPlotName),
				tostring(matchedByOwnerName)
			)
			if matchedByUserId or matchedByPlotName or matchedByOwnerName then
				return plot
			end
		end
	end

	return nil
end

local function setStandSlotAttributes(standModel, upgradeLevel, rebirthCount)
	if not standModel or not standModel:IsA("Model") then
		return
	end

	local standName = standModel.Name
	local isVisible = PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName, rebirthCount)
	local isUsable = PlotUpgradeConfig.IsStandUsable(upgradeLevel, standName, rebirthCount)
	local bonusInfo = PlotUpgradeConfig.GetSlotBonusInfo(upgradeLevel, standName, rebirthCount)
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

local function applyPlotUpgrade(plot, upgradeLevel, rebirthCount)
	upgradeLevel = PlotUpgradeConfig.ClampLevel(upgradeLevel)
	rebirthCount = math.max(0, math.floor(tonumber(rebirthCount) or 0))

	local hidden = getHiddenFolder(plot)
	local map = plot:FindFirstChild("Map")
	local stands = plot:FindFirstChild("Stands")

	if map then
		local floor2, where2 = findFloor(map, hidden, "Floor2")
		local floor3, where3 = findFloor(map, hidden, "Floor3")

		if floor2 then
			if PlotUpgradeConfig.IsFloorUnlocked(upgradeLevel, "Floor2", rebirthCount) then
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
			if PlotUpgradeConfig.IsFloorUnlocked(upgradeLevel, "Floor3", rebirthCount) then
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
				setStandSlotAttributes(child, upgradeLevel, rebirthCount)
				if not PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName, rebirthCount) then
					moveTo(child, hidden)
				end
			end
		end

		for _, child in ipairs(hidden:GetChildren()) do
			local standName = child.Name
			if tonumber(standName) then
				setStandSlotAttributes(child, upgradeLevel, rebirthCount)
				if PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName, rebirthCount) then
					moveTo(child, stands)
				end
			end
		end

		for _, child in ipairs(stands:GetChildren()) do
			if tonumber(child.Name) then
				setStandSlotAttributes(child, upgradeLevel, rebirthCount)
			end
		end
	end
end

local function hidePlotDefaults(plot)
	applyPlotUpgrade(plot, 0, 0)
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

	local spawnPart = getSpawnPart(clone)
	plotTrace(
		"createPlotForPos pos=%s posPath=%s plot=%s plotPivot=%s spawn=%s spawnPos=%s",
		tostring(posPart.Name),
		formatInstancePath(posPart),
		formatInstancePath(clone),
		formatVector3(clone:GetPivot().Position),
		formatInstancePath(spawnPart),
		formatVector3(spawnPart and spawnPart.Position or nil)
	)

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
	assignTrace(
		"ensurePlotsExist begin positionsFolder=%s existingPlotCount=%s",
		formatInstancePath(Positions),
		tostring(getPlotCount())
	)

	for _, child in ipairs(Positions:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "Pos" then
			local existingPlot = findPlotBySlot(child)
			plotTrace(
				"ensurePlotsExist posPath=%s pos=%s existingPlot=%s",
				formatInstancePath(child),
				formatVector3(child.Position),
				formatInstancePath(existingPlot)
			)

			if not existingPlot then
				createPlotForPos(child)
			end
		end
	end

	assignTrace(
		"ensurePlotsExist end plotCount=%s",
		tostring(getPlotCount())
	)
end

local function getFreePlot()
	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			local owner = plot:GetAttribute("OwnerUserId")
			local ownerName = plot:GetAttribute("OwnerName")
			local slot = plot:FindFirstChild("Slot")
			local posPart = slot and slot:IsA("ObjectValue") and slot.Value or nil
			ownershipTrace(
				"getFreePlot candidate plot=%s ownerUserId=%s ownerName=%s plotName=%s slot=%s slotPos=%s isFree=%s",
				formatInstancePath(plot),
				tostring(owner),
				tostring(ownerName),
				tostring(plot.Name),
				formatInstancePath(posPart),
				formatVector3(posPart and posPart.Position or nil),
				tostring(owner == nil)
			)
			if owner == nil then
				return plot
			end
		end
	end
	return nil
end

getSpawnPart = function(plot)
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

local function getSpawnCFrameFromPart(part)
	if not part or not part:IsA("BasePart") then
		return nil
	end

	return part.CFrame + Vector3.new(0, 3, 0)
end

local function teleportToCFrame(player, cf, context, targetCharacter)
	context = tostring(context or "teleport")

	local function doTeleport(character)
		local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
		if not hrp then
			playerTrace(
				"teleportSkipped player=%s context=%s character=%s reason=missing_hrp target=%s",
				player.Name,
				context,
				formatInstancePath(character),
				formatVector3(cf.Position)
			)
			return
		end

		local beforePosition = hrp.Position
		playerTrace(
			"teleportBefore player=%s context=%s character=%s hrp=%s from=%s target=%s",
			player.Name,
			context,
			formatInstancePath(character),
			formatInstancePath(hrp),
			formatVector3(beforePosition),
			formatVector3(cf.Position)
		)
		character:PivotTo(cf)

		playerTrace(
			"teleportAfterImmediate player=%s context=%s character=%s hrp=%s pos=%s",
			player.Name,
			context,
			formatInstancePath(character),
			formatInstancePath(hrp),
			formatVector3(hrp.Position)
		)

		task.defer(function()
			if player.Parent and character.Parent and hrp.Parent then
				playerTrace(
					"teleportAfterDeferred player=%s context=%s character=%s hrp=%s pos=%s",
					player.Name,
					context,
					formatInstancePath(character),
					formatInstancePath(hrp),
					formatVector3(hrp.Position)
				)
			end
		end)
	end

	if targetCharacter then
		doTeleport(targetCharacter)
	elseif player.Character then
		doTeleport(player.Character)
	else
		player.CharacterAdded:Wait()
		if player.Character then
			doTeleport(player.Character)
		end
	end
end

local function teleportToPart(player, part, context, targetCharacter)
	if not part or not part:IsA("BasePart") then
		return false
	end

	local targetCFrame = getSpawnCFrameFromPart(part)
	if not targetCFrame then
		return false
	end

	teleportToCFrame(player, targetCFrame, context or "teleportToPart", targetCharacter)
	return true
end

local function teleportToPlot(player, plot, context, targetCharacter)
	if not plot then
		return false
	end
	local spawnPart = getSpawnPart(plot)
	if not spawnPart then
		plotTrace(
			"teleportToPlot player=%s context=%s plot=%s spawn=<nil>",
			player.Name,
			tostring(context or "teleportToPlot"),
			formatInstancePath(plot)
		)
		return false
	end

	local slot = plot:FindFirstChild("Slot")
	local posPart = slot and slot:IsA("ObjectValue") and slot.Value or nil
	plotTrace(
		"teleportToPlot player=%s context=%s plot=%s slot=%s slotPos=%s spawn=%s spawnPos=%s",
		player.Name,
		tostring(context or "teleportToPlot"),
		formatInstancePath(plot),
		formatInstancePath(posPart),
		formatVector3(posPart and posPart.Position or nil),
		formatInstancePath(spawnPart),
		formatVector3(spawnPart.Position)
	)
	return teleportToPart(player, spawnPart, context or "teleportToPlot", targetCharacter)
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
	local latestLevel = 0
	local latestRebirths = 0

	local function scheduleApply()
		if pending then
			return
		end
		pending = true
		task.defer(function()
			pending = false
			if player.Parent and plot.Parent then
				applyPlotUpgrade(plot, latestLevel, latestRebirths)
			end
		end)
	end

	task.spawn(function()
		local upgradeValue
		local rebirthValue
		while player.Parent and not upgradeValue do
			upgradeValue = getUpgradeValue(player)
			if not upgradeValue then
				task.wait(0.2)
			end
		end

		while player.Parent and not rebirthValue do
			rebirthValue = getRebirthValue(player)
			if not rebirthValue then
				task.wait(0.2)
			end
		end

		if not player.Parent or not upgradeValue then
			saveTrace(
				"setupUpgradeSync aborted player=%s userId=%s plot=%s reason=missing_upgrade_value rebirthValue=%s",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(plot),
				tostring(rebirthValue ~= nil)
			)
			return
		end

		saveTrace(
			"setupUpgradeSync ready player=%s userId=%s plot=%s upgradePath=%s upgrade=%s rebirthPath=%s rebirth=%s",
			player.Name,
			tostring(player.UserId),
			formatInstancePath(plot),
			formatInstancePath(upgradeValue),
			tostring(upgradeValue.Value),
			formatInstancePath(rebirthValue),
			tostring(rebirthValue and rebirthValue.Value or 0)
		)

		local function applyCurrent()
			latestLevel = upgradeValue.Value
			latestRebirths = rebirthValue and rebirthValue.Value or 0
			saveTrace(
				"setupUpgradeSync apply player=%s userId=%s plot=%s upgrade=%s rebirths=%s",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(plot),
				tostring(latestLevel),
				tostring(latestRebirths)
			)
			scheduleApply()
		end

		applyCurrent()

		table.insert(connsByPlayer[player], upgradeValue:GetPropertyChangedSignal("Value"):Connect(function()
			applyCurrent()
		end))

		if rebirthValue then
			table.insert(connsByPlayer[player], rebirthValue:GetPropertyChangedSignal("Value"):Connect(function()
				applyCurrent()
			end))
		end

		table.insert(connsByPlayer[player], plot.DescendantAdded:Connect(function(inst)
			local name = inst.Name
			if name == "Map" or name == "Stands" or name == "Floor2" or name == "Floor3" or tonumber(name) then
				applyCurrent()
			end
		end))
	end)
end

local function claimPlot(player, plot)
	if not plot then
		ownershipTrace("claimPlot player=%s userId=%s plot=<nil> reason=no_plot", player.Name, tostring(player.UserId))
		return nil
	end

	local previousOwnerUserId = plot:GetAttribute("OwnerUserId")
	local previousOwnerName = plot:GetAttribute("OwnerName")
	local previousPlotName = plot.Name
	ownershipTrace(
		"claimPlot before player=%s userId=%s plot=%s previousOwnerUserId=%s previousOwnerUserIdType=%s previousOwnerName=%s previousPlotName=%s",
		player.Name,
		tostring(player.UserId),
		formatInstancePath(plot),
		tostring(previousOwnerUserId),
		typeof(previousOwnerUserId),
		tostring(previousOwnerName),
		tostring(previousPlotName)
	)

	plot:SetAttribute("OwnerUserId", player.UserId)
	plot:SetAttribute("OwnerName", player.Name)
	plot.Name = player.Name

	local upgradeValue = getUpgradeValue(player)
	applyPlotUpgrade(plot, upgradeValue and upgradeValue.Value or 0, getRebirthCount(player))
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

	local slot = plot:FindFirstChild("Slot")
	local posPart = slot and slot:IsA("ObjectValue") and slot.Value or nil
	local spawnPart = getSpawnPart(plot)
	local assignedOwnerUserId = plot:GetAttribute("OwnerUserId")
	local assignedOwnerName = plot:GetAttribute("OwnerName")
	ownershipTrace(
		"claimPlot after player=%s userId=%s plot=%s ownerUserId=%s ownerUserIdType=%s ownerMatchesPlayer=%s ownerName=%s plotName=%s slot=%s slotPos=%s spawn=%s spawnPos=%s",
		player.Name,
		tostring(player.UserId),
		formatInstancePath(plot),
		tostring(assignedOwnerUserId),
		typeof(assignedOwnerUserId),
		tostring(assignedOwnerUserId == player.UserId),
		tostring(assignedOwnerName),
		tostring(plot.Name),
		formatInstancePath(posPart),
		formatVector3(posPart and posPart.Position or nil),
		formatInstancePath(spawnPart),
		formatVector3(spawnPart and spawnPart.Position or nil)
	)
	plotTrace(
		"claimPlot player=%s plot=%s plotPivot=%s slot=%s slotPos=%s spawn=%s spawnPos=%s",
		player.Name,
		formatInstancePath(plot),
		formatVector3(plot:GetPivot().Position),
		formatInstancePath(posPart),
		formatVector3(posPart and posPart.Position or nil),
		formatInstancePath(spawnPart),
		formatVector3(spawnPart and spawnPart.Position or nil)
	)

	teleportToPlot(player, plot)
	setupUpgradeSync(player, plot)
	handleStands(player, plot)
	return plot
end

local function assignPlot(player)
	assignTrace(
		"assign_plot_begin player=%s userId=%s plotCountBeforeEnsure=%s",
		player.Name,
		tostring(player.UserId),
		tostring(getPlotCount())
	)

	ensurePlotsExist()
	assignTrace(
		"assign_plot_after_ensure player=%s userId=%s plotCountAfterEnsure=%s",
		player.Name,
		tostring(player.UserId),
		tostring(getPlotCount())
	)
	logAllPlotsForAssignment("assign_before_selection")

	local existingPlot = getOwnedPlot(player)
	local freePlot = getFreePlot()
	ownershipTrace(
		"assignPlot player=%s userId=%s existingOwnedPlot=%s existingOwnedPlotPivot=%s freePlot=%s freePlotPivot=%s",
		player.Name,
		tostring(player.UserId),
		formatInstancePath(existingPlot),
		formatVector3(existingPlot and existingPlot:GetPivot().Position or nil),
		formatInstancePath(freePlot),
		formatVector3(freePlot and freePlot:GetPivot().Position or nil)
	)

	if not freePlot then
		assignTrace(
			"assign_plot_skipped player=%s userId=%s reason=no_free_plot_found existingOwnedPlot=%s",
			player.Name,
			tostring(player.UserId),
			formatInstancePath(existingPlot)
		)
		return claimPlot(player, freePlot)
	end

	assignTrace(
		"assign_plot_free_plot_found player=%s userId=%s freePlot=%s freePlotPivot=%s",
		player.Name,
		tostring(player.UserId),
		formatInstancePath(freePlot),
		formatVector3(freePlot:GetPivot().Position)
	)

	local claimedPlot = claimPlot(player, freePlot)
	assignTrace(
		"assign_plot_end player=%s userId=%s claimedPlot=%s claimedOwnerUserId=%s claimedOwnerUserIdType=%s",
		player.Name,
		tostring(player.UserId),
		formatInstancePath(claimedPlot),
		tostring(claimedPlot and claimedPlot:GetAttribute("OwnerUserId")),
		typeof(claimedPlot and claimedPlot:GetAttribute("OwnerUserId"))
	)
	logAllPlotsForAssignment("assign_after_claim")
	return claimedPlot
end

local function respawnFreshPlot(oldPlot)
	local guid = oldPlot:GetAttribute("PlotGuid")
	local slot = oldPlot:FindFirstChild("Slot")
	local posPart = slot and slot.Value

	assignTrace(
		"respawnFreshPlot oldPlot=%s oldOwnerUserId=%s oldOwnerUserIdType=%s oldOwnerName=%s slot=%s slotPos=%s",
		formatInstancePath(oldPlot),
		tostring(oldPlot:GetAttribute("OwnerUserId")),
		typeof(oldPlot:GetAttribute("OwnerUserId")),
		tostring(oldPlot:GetAttribute("OwnerName")),
		formatInstancePath(posPart),
		formatVector3(posPart and posPart.Position or nil)
	)

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
		assignTrace(
			"respawnFreshPlot newPlot=%s ownerUserId=%s ownerUserIdType=%s ownerName=%s",
			formatInstancePath(newPlot),
			tostring(newPlot:GetAttribute("OwnerUserId")),
			typeof(newPlot:GetAttribute("OwnerUserId")),
			tostring(newPlot:GetAttribute("OwnerName"))
		)

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
assignTrace(
	"script_init ensurePlotsExist_done plotCount=%s existingPlayers=%s",
	tostring(getPlotCount()),
	tostring(#Players:GetPlayers())
)
if DEBUG_TRACE and #Players:GetPlayers() > 0 then
	for _, existingPlayer in ipairs(Players:GetPlayers()) do
		assignTrace(
			"script_init existing_player player=%s userId=%s reason=no_existing_player_bootstrap_in_plot_server",
			existingPlayer.Name,
			tostring(existingPlayer.UserId)
		)
	end
end

local canAttachPlayerAdded = true
do
	local ok, err = xpcall(function()
		local refs = MapResolver.GetRefs()
		mapTrace(
			"PlotServer requestedMap=%s activeMap=%s mapPath=%s plotSystem=%s positions=%s plotsFolder=%s template=%s",
			tostring(refs.RequestedMapName),
			tostring(refs.ActiveMapName),
			formatInstancePath(refs.MapRoot),
			formatInstancePath(PlotSystem),
			formatInstancePath(Positions),
			formatInstancePath(PlotsFolder),
			formatInstancePath(Template)
		)
	end, debug.traceback)

	if not ok then
		canAttachPlayerAdded = false
		assignTrace("connection_blocked reason=%s", tostring(err))
	end
end

assignTrace("connecting PlayerAdded")
assignTrace(
	"player_added_connect_before_attach plotCount=%s existingPlayers=%s canAttach=%s",
	tostring(getPlotCount()),
	tostring(#Players:GetPlayers()),
	tostring(canAttachPlayerAdded)
)

local function ensurePlayerPlotAssigned(player, source)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		assignTrace("%s_assign_skipped player=<invalid> reason=invalid_player", tostring(source))
		return nil
	end

	local existingPlot = getOwnedPlot(player)
	local existingOwnerUserId = existingPlot and existingPlot:GetAttribute("OwnerUserId") or nil
	if existingPlot and existingOwnerUserId == player.UserId then
		assignTrace(
			"%s_assign_skipped player=%s userId=%s reason=already_assigned plot=%s ownerUserId=%s",
			tostring(source),
			player.Name,
			tostring(player.UserId),
			formatInstancePath(existingPlot),
			tostring(existingOwnerUserId)
		)
		return existingPlot
	end

	assignTrace("%s_assign_begin player=%s userId=%s", tostring(source), player.Name, tostring(player.UserId))
	local assignedPlot = assignPlot(player)
	assignTrace(
		"%s_assign_end player=%s userId=%s plot=%s ownerUserId=%s",
		tostring(source),
		player.Name,
		tostring(player.UserId),
		formatInstancePath(assignedPlot),
		tostring(assignedPlot and assignedPlot:GetAttribute("OwnerUserId"))
	)
	return assignedPlot
end

local function disconnectCharacterSpawnConn(player)
	local connection = characterSpawnConnsByPlayer[player]
	if not connection then
		return
	end

	pcall(function()
		connection:Disconnect()
	end)
	characterSpawnConnsByPlayer[player] = nil
end

local function handleCharacterSpawnAtPlot(player, character, source)
	source = tostring(source or "character_added")

	local hrp = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	local initialPosition = hrp and hrp.Position or nil
	playerTrace(
		"characterAdded player=%s userId=%s source=%s character=%s hrp=%s pos=%s",
		player.Name,
		tostring(player.UserId),
		source,
		formatInstancePath(character),
		formatInstancePath(hrp),
		formatVector3(initialPosition)
	)
	spawnTrace(
		"characterAdded player=%s userId=%s source=%s character=%s initialPos=%s",
		player.Name,
		tostring(player.UserId),
		source,
		formatInstancePath(character),
		formatVector3(initialPosition)
	)

	local ownedPlot = getOwnedPlot(player)
	if not ownedPlot then
		spawnTrace(
			"ownedPlotMissing player=%s userId=%s source=%s action=wait_for_existing_assignment",
			player.Name,
			tostring(player.UserId),
			source
		)

		local deadline = os.clock() + 5
		while player.Parent and character.Parent and os.clock() <= deadline and not ownedPlot do
			task.wait(0.25)
			ownedPlot = getOwnedPlot(player)
		end
	end

	if not ownedPlot then
		spawnTrace(
			"ownedPlotNotFound player=%s userId=%s source=%s action=ensure_assignment",
			player.Name,
			tostring(player.UserId),
			source
		)
		ownedPlot = ensurePlayerPlotAssigned(player, source .. "_spawn")
	end

	local spawnPart = ownedPlot and getSpawnPart(ownedPlot) or nil
	local targetCFrame = getSpawnCFrameFromPart(spawnPart)
	local fallbackReason = nil
	if not ownedPlot then
		fallbackReason = "no_valid_plot"
	elseif not spawnPart then
		fallbackReason = "plot_missing_spawn"
	elseif not targetCFrame then
		fallbackReason = "invalid_spawn_cframe"
	end

	plotTrace(
		"characterSpawnResolve player=%s userId=%s source=%s ownedPlot=%s spawn=%s spawnPos=%s fallbackUsed=%s",
		player.Name,
		tostring(player.UserId),
		source,
		formatInstancePath(ownedPlot),
		formatInstancePath(spawnPart),
		formatVector3(spawnPart and spawnPart.Position or nil),
		tostring(fallbackReason ~= nil)
	)

	if targetCFrame then
		spawnTrace(
			"spawnSelected player=%s userId=%s source=%s ownedPlotFound=true fallbackUsed=false plot=%s spawn=%s chosenSpawnLocation=%s",
			player.Name,
			tostring(player.UserId),
			source,
			formatInstancePath(ownedPlot),
			formatInstancePath(spawnPart),
			formatVector3(targetCFrame.Position)
		)
		teleportToCFrame(player, targetCFrame, "plot_spawn:" .. source, character)

		task.defer(function()
			local liveHrp = character.Parent and (character:FindFirstChild("HumanoidRootPart") or hrp) or nil
			spawnTrace(
				"spawnFinal player=%s userId=%s source=%s fallbackUsed=false finalCharacterPosition=%s",
				player.Name,
				tostring(player.UserId),
				source,
				formatVector3(liveHrp and liveHrp.Position or nil)
			)
		end)

		return true
	end

	spawnTrace(
		"spawnFallback player=%s userId=%s source=%s ownedPlotFound=%s fallbackUsed=true reason=%s chosenSpawnLocation=%s",
		player.Name,
		tostring(player.UserId),
		source,
		tostring(ownedPlot ~= nil),
		tostring(fallbackReason or "unknown"),
		formatVector3(initialPosition)
	)

	task.defer(function()
		local liveHrp = character.Parent and (character:FindFirstChild("HumanoidRootPart") or hrp) or nil
		spawnTrace(
			"spawnFinal player=%s userId=%s source=%s fallbackUsed=true finalCharacterPosition=%s",
			player.Name,
			tostring(player.UserId),
			source,
			formatVector3(liveHrp and liveHrp.Position or nil)
		)
	end)

	return false
end

local function attachCharacterSpawnHandler(player, source)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	if characterSpawnConnsByPlayer[player] then
		return
	end

	spawnTrace(
		"attachCharacterSpawnHandler player=%s userId=%s source=%s existingCharacter=%s",
		player.Name,
		tostring(player.UserId),
		tostring(source),
		tostring(player.Character ~= nil)
	)

	characterSpawnConnsByPlayer[player] = player.CharacterAdded:Connect(function(character)
		local ok, err = xpcall(function()
			handleCharacterSpawnAtPlot(player, character, "CharacterAdded")
		end, debug.traceback)

		if not ok then
			spawnTrace(
				"characterSpawnError player=%s userId=%s source=%s error=%s",
				player.Name,
				tostring(player.UserId),
				"CharacterAdded",
				tostring(err)
			)
		end
	end)

	if player.Character then
		task.spawn(function()
			local ok, err = xpcall(function()
				handleCharacterSpawnAtPlot(player, player.Character, tostring(source) .. "_existing_character")
			end, debug.traceback)

			if not ok then
				spawnTrace(
					"characterSpawnError player=%s userId=%s source=%s error=%s",
					player.Name,
					tostring(player.UserId),
					tostring(source) .. "_existing_character",
					tostring(err)
				)
			end
		end)
	end
end

local playerAddedConnection = nil
if canAttachPlayerAdded then
	playerAddedConnection = Players.PlayerAdded:Connect(function(player)
		assignTrace("PlayerAdded fired player=%s userId=%s", player.Name, tostring(player.UserId))

		local ok, err = pcall(function()
			assignTrace("PlayerAdded first_line player=%s userId=%s", player.Name, tostring(player.UserId))
			plotTrace("PlayerAdded player=%s", player.Name)
			playerTrace("playerJoined player=%s userId=%s", player.Name, tostring(player.UserId))
			spawnTrace("playerJoined player=%s userId=%s", player.Name, tostring(player.UserId))
			ownershipTrace("PlayerAdded player=%s userId=%s event=player_added", player.Name, tostring(player.UserId))
			attachCharacterSpawnHandler(player, "PlayerAdded")
			ownershipTrace("PlayerAdded player=%s userId=%s event=assign_plot_begin", player.Name, tostring(player.UserId))
			assignTrace("PlayerAdded before assignPlot player=%s userId=%s", player.Name, tostring(player.UserId))
			local assignedPlot = ensurePlayerPlotAssigned(player, "player_added")
			assignTrace(
				"PlayerAdded after assignPlot player=%s userId=%s plot=%s ownerUserId=%s",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(assignedPlot),
				tostring(assignedPlot and assignedPlot:GetAttribute("OwnerUserId"))
			)
			ownershipTrace("PlayerAdded player=%s userId=%s event=assign_plot_end", player.Name, tostring(player.UserId))
			if not assignedPlot then
				assignTrace(
					"PlayerAdded assignment_skipped player=%s userId=%s reason=assignPlot_returned_nil",
					player.Name,
					tostring(player.UserId)
				)
				return
			end

			assignTrace(
				"PlayerAdded assignment_complete player=%s userId=%s plot=%s ownerUserId=%s",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(assignedPlot),
				tostring(assignedPlot:GetAttribute("OwnerUserId"))
			)
		end)

		if not ok then
			assignTrace(
				"player_added_error player=%s userId=%s err=%s",
				player and player.Name or "<nil>",
				tostring(player and player.UserId or "nil"),
				tostring(err)
			)
		end
	end)
	assignTrace("PlayerAdded connected")
else
	assignTrace("connection_blocked reason=player_added_not_attached")
end

assignTrace(
	"player_added_connect_after_attach connected=%s existingPlayers=%s",
	tostring(playerAddedConnection ~= nil),
	tostring(#Players:GetPlayers())
)

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	assignTrace("bootstrap_existing_player player=%s userId=%s", existingPlayer.Name, tostring(existingPlayer.UserId))
	attachCharacterSpawnHandler(existingPlayer, "bootstrap")
	ensurePlayerPlotAssigned(existingPlayer, "bootstrap")
end

Players.PlayerRemoving:Connect(function(player)
	disconnectCharacterSpawnConn(player)
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
