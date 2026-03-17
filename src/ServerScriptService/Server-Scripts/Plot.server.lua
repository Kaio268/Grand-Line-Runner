local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function computeMaxStand(upgrade)
	local addFloor2 = math.clamp(upgrade - 1, 0, 8)
	local addFloor3 = math.clamp(upgrade - 10, 0, 8)
	return 8 + addFloor2 + addFloor3
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

local function applyPlotUpgrade(plot, upgrade)
	local hidden = getHiddenFolder(plot)
	local map = plot:FindFirstChild("Map")
	local stands = plot:FindFirstChild("Stands")

	if map then
		local floor2, where2 = findFloor(map, hidden, "Floor2")
		local floor3, where3 = findFloor(map, hidden, "Floor3")

		if floor2 then
			if upgrade >= 1 then
				if where2 == "hidden" then moveTo(floor2, map) end
			else
				if where2 == "map" then moveTo(floor2, hidden) end
			end
		end

		if floor3 then
			if upgrade >= 10 then
				if where3 == "hidden" then moveTo(floor3, map) end
			else
				if where3 == "map" then moveTo(floor3, hidden) end
			end
		end
	end

	if stands then
		local maxStand = computeMaxStand(upgrade)

		for _, child in ipairs(stands:GetChildren()) do
			local n = tonumber(child.Name)
			if n and n > maxStand then
				moveTo(child, hidden)
			end
		end

		for i = 1, maxStand do
			local name = tostring(i)
			if not stands:FindFirstChild(name) then
				local h = hidden:FindFirstChild(name)
				if h then
					moveTo(h, stands)
				end
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

local function SetUpButton(plr, stand)
	local button = stand:WaitForChild("LevelUp", 5)
	if not button then return end
	local sg = button:FindFirstChildOfClass("SurfaceGui")
	if not sg then return end

	sg.Adornee = button
	sg.ResetOnSpawn = false
	sg.Name = stand.Name

	local addedConn = stand.ChildAdded:Connect(function(child)
		if not child:IsA("Model") then return end
		if plr:FindFirstChild("PlayerGui") then
			sg.Parent = plr.PlayerGui
		end
	end)

	local removedConn = stand.ChildRemoved:Connect(function(child)
		if not child:IsA("Model") then return end
		pcall(function()
			if not plr:FindFirstChild("PlayerGui") then return end
			for _, gui in plr.PlayerGui:GetChildren() do
				if gui:IsA("SurfaceGui") and gui.Adornee == button then
					gui.Parent = button
					break
				end
			end
		end)
	end)

	return addedConn, removedConn
end

local function HandleStands(plr, plot)
	local standsFolder = plot:WaitForChild("Stands", 10)
	if not standsFolder then return end

	for _, v in ipairs(standsFolder:GetChildren()) do
		if v:IsA("Model") then
			SetUpButton(plr, v)
		end
	end

	standsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			SetUpButton(plr, child)
		end
	end)
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

local function assignPlot(plr)
	ensurePlotsExist()
	local plot = getFreePlot()
	if not plot then return end

	plot:SetAttribute("OwnerUserId", plr.UserId)
	plot:SetAttribute("OwnerName", plr.Name)
	plot.Name = plr.Name
 	plr.PlayerGui:WaitForChild("SurfaceGui").Adornee =  plot.SlotsUpgrades.MainPart
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
	HandleStands(plr, plot)
	setupUpgradeSync(plr, plot)
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
	end
end

ensurePlotsExist()

Players.PlayerAdded:Connect(function(plr)
	assignPlot(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	disconnectPlayerConns(plr)
	for _, m in ipairs(PlotsFolder:GetChildren()) do
		if m:IsA("Model") then
			local ownerId = m:GetAttribute("OwnerUserId")
			local ownerName = m:GetAttribute("OwnerName")
			if ownerId == plr.UserId or m.Name == plr.Name or ownerName == plr.Name then
				respawnFreshPlot(m)
				break
			end
		end
	end
end)
