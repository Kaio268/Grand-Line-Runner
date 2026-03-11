local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local Point = require(ReplicatedStorage:WaitForChild("Point"))

local remote = ReplicatedStorage:FindFirstChild("TutorialrrrrFinished")

local player = Players.LocalPlayer
local npc = workspace:WaitForChild("Map"):WaitForChild("MainMap"):WaitForChild("Brr Brr Patapim")
local npcPrompt = npc:WaitForChild("ProximityPrompt")

local dialogObject = DialogModule.new("OpenFishingShop", npc, npcPrompt)
dialogObject:addDialog("Do You Want To Open Speed Upgrades?", {"Yea", "Nope"})

local open = require(player.PlayerGui:WaitForChild("OpenUI"):WaitForChild("Open_UI"))

local FIRST_POS = UDim2.new(0.566, 0, 0.431, 0)
local FIRST_SIZE = UDim2.new(0.164, 0, 0.093, 0)

local SECOND_POS = UDim2.new(0.632, 0, 0.285, 0)
local SECOND_SIZE = UDim2.new(0.056, 0, 0.093, 0)

local tutorialValue
local tutorialDisabled = false
local finishedSent = false

local function getTutorialValue()
	local hls = player:FindFirstChild("HiddenLeaderstats") or player:WaitForChild("HiddenLeaderstats")
	return hls:WaitForChild("Tutorial")
end

local tutGui
local tutRefs = { step = nil, stepWave = nil, info = nil, infoWave = nil }

local function setTutorialGuiVisible(vis)
	pcall(function()
		local pg = player:WaitForChild("PlayerGui")
		local hud = pg:WaitForChild("HUD")
		tutGui = hud:WaitForChild("Tutorial")
		tutGui.Visible = vis
	end)
end

local function setAnyText(obj, txt)
	if not obj then
		return
	end
	if obj:IsA("TextLabel") or obj:IsA("TextButton") then
		obj.Text = txt
		return
	end
	if obj:IsA("Frame") then
		local t = obj:FindFirstChildWhichIsA("TextLabel", true) or obj:FindFirstChildWhichIsA("TextButton", true)
		if t then
			t.Text = txt
		end
	end
end

local function ensureTutorialRefs()
	if tutRefs.step and tutRefs.step.Parent then
		return true
	end
	local ok = pcall(function()
		local pg = player:WaitForChild("PlayerGui")
		local hud = pg:WaitForChild("HUD")
		local tut = hud:WaitForChild("Tutorial")
		local stepObj = tut:WaitForChild("Step")
		local infoObj = tut:WaitForChild("Info")
		tutRefs.step = stepObj
		tutRefs.info = infoObj
		tutRefs.stepWave = stepObj:FindFirstChild("Wave")
		tutRefs.infoWave = infoObj:FindFirstChild("Wave")
	end)
	return ok and tutRefs.step ~= nil
end

local function setTutorial(stepNum, infoText)
	if tutorialDisabled then
		setTutorialGuiVisible(false)
		return
	end

	setTutorialGuiVisible(stepNum > 0)

	if not ensureTutorialRefs() then
		return
	end

	if stepNum <= 0 then
		setAnyText(tutRefs.step, "")
		setAnyText(tutRefs.stepWave, "")
		setAnyText(tutRefs.info, "")
		setAnyText(tutRefs.infoWave, "")
		return
	end

	local stepText = "Step " .. tostring(stepNum)
	setAnyText(tutRefs.step, stepText)
	setAnyText(tutRefs.stepWave, stepText)
	setAnyText(tutRefs.info, infoText or "")
	setAnyText(tutRefs.infoWave, infoText or "")
end

local function inventoryHasAnyFolder()
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		return false
	end
	for _, c in ipairs(inv:GetChildren()) do
		if c:IsA("Folder") then
			return true
		end
	end
	return false
end

local promptQueue = {}

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeredPlayer)
	if triggeredPlayer and triggeredPlayer ~= player then
		return
	end
	table.insert(promptQueue, prompt)
end)

local function popPrompt()
	if #promptQueue > 0 then
		return table.remove(promptQueue, 1)
	end
end

local function clearPromptQueue()
	table.clear(promptQueue)
end

local buyConn
local xConn

local function disconnectPoint()
	if buyConn then
		buyConn:Disconnect()
		buyConn = nil
	end
	if xConn then
		xConn:Disconnect()
		xConn = nil
	end
end

local function getButtons()
	local pg = player:WaitForChild("PlayerGui")
	local frames = pg:WaitForChild("Frames")
	local speedUpgrade = frames:WaitForChild("SpeedUpgrade")
	local main = speedUpgrade:WaitForChild("Main")
	local slot1 = main:WaitForChild("1")
	local buy = slot1:WaitForChild("Buy")
	local topBar = speedUpgrade:WaitForChild("TopBar")
	local x = topBar:WaitForChild("X")
	return buy, x
end

local function isAlive(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

local function aliveInWorkspace(inst)
	return inst and inst.Parent ~= nil and inst:IsDescendantOf(workspace)
end

local beam
local a0
local a1
local diedConn

local function cleanupBeam()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if a0 then
		a0:Destroy()
		a0 = nil
	end
	if a1 then
		a1:Destroy()
		a1 = nil
	end
end

local function hideBeam()
	if beam then
		beam.Enabled = false
		beam.Attachment1 = nil
	end
	if a1 then
		a1:Destroy()
		a1 = nil
	end
end

local function setTargetPart(part)
	if not beam then
		return
	end

	if a1 then
		a1:Destroy()
		a1 = nil
	end

	if part and part:IsA("BasePart") then
		a1 = Instance.new("Attachment")
		a1.Name = "TutorialAttachment1"
		a1.Parent = part
		beam.Attachment1 = a1
		beam.Enabled = true
	else
		beam.Attachment1 = nil
		beam.Enabled = false
	end
end

local function ensureBeam(character)
	if diedConn then
		diedConn:Disconnect()
		diedConn = nil
	end

	cleanupBeam()

	local hrp = character:WaitForChild("HumanoidRootPart")

	a0 = Instance.new("Attachment")
	a0.Name = "TutorialAttachment0"
	a0.Parent = hrp

	beam = ReplicatedStorage:WaitForChild("Beam"):Clone()
	beam.Name = "TutorialBeam"
	beam.Attachment0 = a0
	beam.Parent = hrp

	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		diedConn = hum.Died:Connect(function()
			hideBeam()
		end)
	end
end

local function getSpawnContainer()
	local map = workspace:WaitForChild("Map")
	return map:WaitForChild("SpawnPart")
end

local function modelHasPrompt(model)
	return model and model:IsA("Model") and model:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
end

local function getModelPrompt(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	return model:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function getModelTargetPart(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	local pr = getModelPrompt(model)
	if pr then
		local p = pr.Parent
		if p and p:IsA("Attachment") then
			p = p.Parent
		end
		if p and p:IsA("BasePart") then
			return p
		end
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getNearestModel(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local origin = hrp.Position
	local container = getSpawnContainer()

	local bestModel = nil
	local bestDist = math.huge
	local seen = {}

	local function considerModel(model)
		if seen[model] then
			return
		end
		seen[model] = true
		if not modelHasPrompt(model) then
			return
		end

		local pos
		local ok, pivot = pcall(function()
			return model:GetPivot()
		end)

		if ok and pivot then
			pos = pivot.Position
		else
			local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			if pp then
				pos = pp.Position
			end
		end

		if not pos then
			return
		end

		local dist = (pos - origin).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestModel = model
		end
	end

	for _, obj in ipairs(container:GetChildren()) do
		if obj:IsA("Model") then
			considerModel(obj)
		end
		for _, desc in ipairs(obj:GetDescendants()) do
			if desc:IsA("Model") then
				considerModel(desc)
			end
		end
	end

	return bestModel
end

local function getBrrMesh()
	return npc:WaitForChild("Mesh")
end

local function findPlayerPlot()
	local ps = workspace:FindFirstChild("PlotSystem")
	if not ps then
		return nil
	end
	local plots = ps:FindFirstChild("Plots")
	if not plots then
		return nil
	end

	for _, plot in ipairs(plots:GetChildren()) do
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

local function getStand1Handle()
	local plot = findPlayerPlot()
	if not plot then
		return nil, nil
	end

	local stands = plot:FindFirstChild("Stands")
	if not stands then
		return nil, nil
	end

	local stand1 = stands:FindFirstChild("1")
	if not stand1 then
		return nil, nil
	end

	local handle = stand1:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return nil, nil
	end

	local pr = handle:FindFirstChildWhichIsA("ProximityPrompt", true)
	return handle, pr
end

local beamActive = false
local beamStage = "OFF"
local currentBrainrotModel
local currentBrainrotPrompt

local function stopAllTutorialSystems()
	beamActive = false
	beamStage = "OFF"
	currentBrainrotModel = nil
	currentBrainrotPrompt = nil

	clearPromptQueue()

	Point.Hide()
	disconnectPoint()

	hideBeam()
	cleanupBeam()

	setTutorial(0, "")
	setTutorialGuiVisible(false)
end

local function completeTutorial()
	if finishedSent then
		return
	end
	finishedSent = true

	beamActive = false
	beamStage = "OFF"
	clearPromptQueue()
	Point.Hide()
	disconnectPoint()
	hideBeam()
	cleanupBeam()

	setTutorial(6, "Thank you for completing the tutorial! Enjoy the game!")
	task.delay(3, function()
		setTutorial(0, "")
		setTutorialGuiVisible(false)
		if remote then
			remote:FireServer()
		end
	end)
end

local function startInitialBeamToBrr()
	if tutorialDisabled or finishedSent then
		return
	end

	beamActive = true
	beamStage = "TO_BRR"

	setTutorial(1, "Follow the beam to Brr Brr Patapim and hold E to interact.")

	local character = player.Character or player.CharacterAdded:Wait()
	ensureBeam(character)
	setTargetPart(getBrrMesh())
end

local function startPlotStandStep()
	if tutorialDisabled or finishedSent then
		return
	end

	beamActive = true
	beamStage = "PLOT_STAND"

	setTutorial(5, "Go to your Stand, equip the Brainrot you collected, and place it on the Stand.")
end

local function resetAfterRespawn()
	if tutorialDisabled or finishedSent or not beamActive then
		return
	end

	local character = player.Character
	if character then
		ensureBeam(character)
	end

	if beamStage == "TO_BRR" then
		setTutorial(1, "Follow the beam to Brr Brr Patapim and hold E to interact.")
	elseif beamStage == "BRAINROT" or beamStage == "WAIT_FOR_FOLDER" then
		setTutorial(4, "Follow the beam to the nearest Brainrot and hold E to collect it.")
	elseif beamStage == "PLOT_STAND" then
		setTutorial(5, "Go to your Stand, equip the Brainrot you collected, and place it on the Stand.")
	end
end

player.CharacterAdded:Connect(function()
	task.defer(resetAfterRespawn)
end)

local function runBeamLoop(character)
	while beamActive and character.Parent and isAlive(character) do
		if tutorialDisabled then
			stopAllTutorialSystems()
			return
		end

		if beamStage == "TO_BRR" then
			setTargetPart(getBrrMesh())
			task.wait(0.2)
		elseif beamStage == "BRAINROT" then
			setTutorial(4, "Follow the beam to the nearest Brainrot and hold E to collect it.")

			local model = getNearestModel(character)
			if not model then
				hideBeam()
				task.wait(0.2)
			else
				currentBrainrotModel = model
				currentBrainrotPrompt = getModelPrompt(model)
				local targetPart = getModelTargetPart(model)
				setTargetPart(targetPart)

				while beamActive and beamStage == "BRAINROT" and character.Parent and isAlive(character) do
					if not aliveInWorkspace(currentBrainrotModel) then
						hideBeam()
						clearPromptQueue()
						currentBrainrotModel = nil
						currentBrainrotPrompt = nil
						break
					end

					if currentBrainrotPrompt and not aliveInWorkspace(currentBrainrotPrompt) then
						hideBeam()
						clearPromptQueue()
						currentBrainrotModel = nil
						currentBrainrotPrompt = nil
						break
					end

					if targetPart and not aliveInWorkspace(targetPart) then
						hideBeam()
						clearPromptQueue()
						currentBrainrotModel = nil
						currentBrainrotPrompt = nil
						break
					end

					local prompt = popPrompt()
					if prompt then
						if (currentBrainrotPrompt and prompt == currentBrainrotPrompt)
							or (currentBrainrotModel and prompt:IsDescendantOf(currentBrainrotModel)) then
							beamStage = "WAIT_FOR_FOLDER"
							clearPromptQueue()
							break
						end
					else
						task.wait(0.1)
					end
				end
			end
		elseif beamStage == "WAIT_FOR_FOLDER" then
			if inventoryHasAnyFolder() then
				startPlotStandStep()
			else
				task.wait(0.15)
			end
		elseif beamStage == "PLOT_STAND" then
			local handle, handlePrompt = getStand1Handle()

			if not handle then
				hideBeam()
				task.wait(0.25)
			else
				setTargetPart(handle)

				while beamActive and beamStage == "PLOT_STAND" and character.Parent and isAlive(character) do
					if not aliveInWorkspace(handle) then
						hideBeam()
						clearPromptQueue()
						break
					end

					local prompt = popPrompt()
					if prompt then
						if (handlePrompt and prompt == handlePrompt) or prompt:IsDescendantOf(handle) then
							completeTutorial()
							return
						end
					else
						task.wait(0.1)
					end
				end
			end
		else
			hideBeam()
			task.wait(0.2)
		end

		task.wait(0.03)
	end

	hideBeam()
	clearPromptQueue()
end

task.spawn(function()
	while player.Parent do
		if tutorialDisabled then
			stopAllTutorialSystems()
			task.wait(0.5)
			continue
		end

		if not beamActive then
			task.wait(0.2)
			continue
		end

		local character = player.Character or player.CharacterAdded:Wait()
		if not character then
			task.wait(0.1)
			continue
		end

		if not beam then
			ensureBeam(character)
		end

		if not character.Parent or not isAlive(character) then
			task.wait(0.2)
			continue
		end

		runBeamLoop(character)
		task.wait(0.12)
	end
end)

local function startSpeedUpgradeTutorial()
	if tutorialDisabled or finishedSent then
		return
	end

	disconnectPoint()

	setTutorial(2, "Click the highlighted button to buy a Speed Upgrade.")
	Point.Set(FIRST_SIZE, FIRST_POS)

	task.spawn(function()
		local buyButton, xButton = getButtons()

		buyConn = buyButton.Activated:Connect(function()
			if tutorialDisabled or finishedSent then
				return
			end
			setTutorial(3, "Good! Now click X to close the menu.")
			Point.Set(SECOND_SIZE, SECOND_POS)
		end)

		xConn = xButton.Activated:Connect(function()
			if tutorialDisabled or finishedSent then
				return
			end

			Point.Hide()
			disconnectPoint()

			setTutorial(4, "Follow the beam to the nearest Brainrot and hold E to collect it.")
			beamActive = true
			beamStage = "BRAINROT"

			local character = player.Character
			if character then
				ensureBeam(character)
			end
		end)
	end)
end

npcPrompt.Triggered:Connect(function(triggeringPlayer)
	dialogObject:triggerDialog(triggeringPlayer, 1)
end)

dialogObject.responded:Connect(function(responseNum, dialogNum)
	if dialogNum ~= 1 then
		return
	end

	if responseNum == 1 then
		dialogObject:hideGui("Okay!!")
		open:OpenFrame("SpeedUpgrade")

		if tutorialDisabled or finishedSent then
			setTutorialGuiVisible(false)
			Point.Hide()
			disconnectPoint()
			return
		end

		beamActive = false
		beamStage = "OFF"
		hideBeam()

		task.defer(startSpeedUpgradeTutorial)
	elseif responseNum == 2 then
		dialogObject:hideGui("Alr, bye!")

		if tutorialDisabled or finishedSent then
			setTutorialGuiVisible(false)
			return
		end

		task.defer(startInitialBeamToBrr)
	end
end)

task.spawn(function()
	tutorialValue = getTutorialValue()

	if tutorialValue.Value == true then
		tutorialDisabled = true
		stopAllTutorialSystems()
		setTutorialGuiVisible(false)
		return
	end

	tutorialValue.Changed:Connect(function()
		if tutorialValue.Value == true then
			tutorialDisabled = true
			stopAllTutorialSystems()
			setTutorialGuiVisible(false)
		end
	end)

	startInitialBeamToBrr()
end)
