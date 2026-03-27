local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local Point = require(ReplicatedStorage:WaitForChild("Point"))

local remote = ReplicatedStorage:FindFirstChild("TutorialrrrrFinished")

local player = Players.LocalPlayer
local refs = MapResolver.WaitForRefs({ "MapRoot" }, nil, {
	warn = true,
	context = "BrrBrrPatapimDialog",
})
local npc = refs.MapRoot:WaitForChild("Lobby"):WaitForChild("Brr Brr Patapim")
local npcPrompt = npc:WaitForChild("ProximityPrompt")

local dialogObject = DialogModule.new("OpenFishingShop", npc, npcPrompt)
dialogObject:addDialog("Do You Want To Open Speed Upgrades?", { "Yea", "Nope" })

local function openFrame(frameName)
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local openUi = playerGui:FindFirstChild("OpenUI")
	local openModule = openUi and openUi:FindFirstChild("Open_UI")
	if openModule then
		local ok, controller = pcall(require, openModule)
		if ok and controller and controller.OpenFrame then
			controller:OpenFrame(frameName)
			return
		end
	end

	local frames = playerGui:FindFirstChild("Frames")
	local frame = frames and frames:FindFirstChild(frameName)
	if frame and frame:IsA("Frame") then
		frame.Visible = true
	end
end

local FALLBACK_FIRST_POS = UDim2.new(0.566, 0, 0.431, 0)
local FALLBACK_FIRST_SIZE = UDim2.new(0.164, 0, 0.093, 0)

local FALLBACK_SECOND_POS = UDim2.new(0.632, 0, 0.285, 0)
local FALLBACK_SECOND_SIZE = UDim2.new(0.056, 0, 0.093, 0)
local STEP2_SPOTLIGHT_Y_OFFSET = 60
local STEP3_SPOTLIGHT_Y_OFFSET = 60

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
local buyClickConn
local xConn
local spotlightConn

local function disconnectPoint()
	if buyConn then
		buyConn:Disconnect()
		buyConn = nil
	end
	if buyClickConn then
		buyClickConn:Disconnect()
		buyClickConn = nil
	end
	if xConn then
		xConn:Disconnect()
		xConn = nil
	end
	if spotlightConn then
		spotlightConn:Disconnect()
		spotlightConn = nil
	end
end

local function getButtons()
	local pg = player:WaitForChild("PlayerGui")
	local frames = pg:WaitForChild("Frames")
	local speedUpgrade = frames:WaitForChild("SpeedUpgrade")
	local main = speedUpgrade:WaitForChild("Main")
	local topBar = speedUpgrade:WaitForChild("TopBar")
	local x = topBar:WaitForChild("X")

	local function isGuiActuallyVisible(guiObject)
		if not (guiObject and guiObject:IsA("GuiObject")) then
			return false
		end
		local current = guiObject
		while current and current ~= speedUpgrade do
			if current:IsA("GuiObject") and current.Visible == false then
				return false
			end
			current = current.Parent
		end
		return speedUpgrade.Visible == true
	end

	local preferredSlot = main:FindFirstChild("1")
	if preferredSlot and preferredSlot:IsA("GuiObject") then
		local preferredBuy = preferredSlot:FindFirstChild("Buy", true)
		if preferredBuy and preferredBuy:IsA("GuiButton") and isGuiActuallyVisible(preferredBuy) then
			return preferredBuy, x, speedUpgrade
		end
	end

	local bestBuy = nil
	local bestOrder = math.huge

	for _, child in ipairs(main:GetChildren()) do
		if child:IsA("GuiObject") then
			local buy = child:FindFirstChild("Buy", true)
			if buy and buy:IsA("GuiButton") and isGuiActuallyVisible(buy) then
				local order = child.LayoutOrder
				if typeof(order) ~= "number" then
					order = tonumber(child.Name) or math.huge
				end
				if order < bestOrder then
					bestOrder = order
					bestBuy = buy
				end
			end
		end
	end

	if not bestBuy then
		local slot1 = main:FindFirstChild("1")
		if slot1 then
			local fallbackBuy = slot1:FindFirstChild("Buy", true)
			if fallbackBuy and fallbackBuy:IsA("GuiButton") then
				bestBuy = fallbackBuy
			end
		end
	end

	return bestBuy, x, speedUpgrade
end

local function getViewportSize()
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector2.new(1920, 1080)
	end

	local size = camera.ViewportSize
	if size.X <= 0 or size.Y <= 0 then
		return Vector2.new(1920, 1080)
	end

	return Vector2.new(size.X, size.Y)
end

local function waitForAbsoluteBounds(guiObject, timeoutSeconds)
	local timeoutAt = os.clock() + (timeoutSeconds or 1.25)
	while guiObject and guiObject.Parent and os.clock() < timeoutAt do
		local size = guiObject.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			return guiObject.AbsolutePosition, size
		end
		task.wait()
	end

	return nil, nil
end

local function waitForGuiReady(guiObject, frame, timeoutSeconds)
	local timeoutAt = os.clock() + (timeoutSeconds or 2)
	while os.clock() < timeoutAt do
		if tutorialDisabled or finishedSent then
			return false
		end
		if guiObject and guiObject.Parent and frame and frame.Visible then
			local size = guiObject.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				return true
			end
		end
		task.wait()
	end
	return false
end

local function makePointRect(guiObject, paddingX, paddingY, offsetX, offsetY)
	if not guiObject or not guiObject:IsA("GuiObject") then
		return nil, nil
	end

	local absolutePosition, absoluteSize = waitForAbsoluteBounds(guiObject, 1.25)
	if not absolutePosition or not absoluteSize then
		return nil, nil
	end

	local viewport = getViewportSize()
	local padX = math.max(0, tonumber(paddingX) or 0)
	local padY = math.max(0, tonumber(paddingY) or 0)
	local offX = tonumber(offsetX) or 0
	local offY = tonumber(offsetY) or 0

	local widthPx = absoluteSize.X + (padX * 2)
	local heightPx = absoluteSize.Y + (padY * 2)

	local centerX = absolutePosition.X + (absoluteSize.X * 0.5) + offX
	local centerY = absolutePosition.Y + (absoluteSize.Y * 0.5) + offY

	local size = UDim2.new(widthPx / viewport.X, 0, heightPx / viewport.Y, 0)
	local position = UDim2.new(centerX / viewport.X, 0, centerY / viewport.Y, 0)
	return size, position
end

local function makePointRectNow(guiObject, paddingX, paddingY, offsetX, offsetY)
	if not guiObject or not guiObject:IsA("GuiObject") then
		return nil, nil
	end

	local absoluteSize = guiObject.AbsoluteSize
	if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
		return nil, nil
	end

	local absolutePosition = guiObject.AbsolutePosition
	local viewport = getViewportSize()
	local padX = math.max(0, tonumber(paddingX) or 0)
	local padY = math.max(0, tonumber(paddingY) or 0)
	local offX = tonumber(offsetX) or 0
	local offY = tonumber(offsetY) or 0

	local widthPx = absoluteSize.X + (padX * 2)
	local heightPx = absoluteSize.Y + (padY * 2)

	local centerX = absolutePosition.X + (absoluteSize.X * 0.5) + offX
	local centerY = absolutePosition.Y + (absoluteSize.Y * 0.5) + offY

	local size = UDim2.new(widthPx / viewport.X, 0, heightPx / viewport.Y, 0)
	local position = UDim2.new(centerX / viewport.X, 0, centerY / viewport.Y, 0)
	return size, position
end

local function pointAtGui(guiObject, paddingX, paddingY, fallbackSize, fallbackPosition, offsetX, offsetY)
	local size, position = makePointRect(guiObject, paddingX, paddingY, offsetX, offsetY)
	if not size or not position then
		size = fallbackSize
		position = fallbackPosition
	end

	Point.Set(size, position, {
		posMode = "center",
	})
end

local function pointAtGuiNow(guiObject, paddingX, paddingY, fallbackSize, fallbackPosition, offsetX, offsetY)
	local size, position = makePointRectNow(guiObject, paddingX, paddingY, offsetX, offsetY)
	if not size or not position then
		size = fallbackSize
		position = fallbackPosition
	end

	Point.Set(size, position, {
		posMode = "center",
	})
end

local function startSpotlightFollow(guiObject, paddingX, paddingY, fallbackSize, fallbackPosition, offsetX, offsetY)
	if spotlightConn then
		spotlightConn:Disconnect()
		spotlightConn = nil
	end

	pointAtGui(guiObject, paddingX, paddingY, fallbackSize, fallbackPosition, offsetX, offsetY)

	spotlightConn = RunService.RenderStepped:Connect(function()
		if tutorialDisabled or finishedSent then
			return
		end
		local size, position = makePointRectNow(guiObject, paddingX, paddingY, offsetX, offsetY)
		if not size or not position then
			size = fallbackSize
			position = fallbackPosition
		end
		if Point.Update then
			Point.Update(size, position, {
				posMode = "center",
			})
		else
			Point.Set(size, position, {
				posMode = "center",
				duration = 0,
			})
		end
	end)
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
	return MapResolver.WaitForRefs({ "SpawnFolder" }, nil, {
		warn = true,
		context = "BrrBrrPatapimDialog.SpawnFolder",
	}).SpawnFolder
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

local function getNearestBrainrotTarget(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil, nil, nil
	end

	local origin = hrp.Position
	local container = getSpawnContainer()
	local mapRoot = refs and refs.MapRoot

	local bestModel = nil
	local bestPrompt = nil
	local bestPart = nil
	local bestDist = math.huge

	local roots = {}

	local brainrotsWorld = mapRoot and mapRoot:FindFirstChild("BrainrotsWorld")
	local droppedFolder = brainrotsWorld and brainrotsWorld:FindFirstChild("Dropped")
	if droppedFolder then
		table.insert(roots, droppedFolder)
	end

	if container and container:IsDescendantOf(workspace) then
		local spawnBrainrotsFolder = container:FindFirstChild("Brainrots")
		if spawnBrainrotsFolder then
			table.insert(roots, spawnBrainrotsFolder)
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Instance") then
				local brainrots = child:FindFirstChild("Brainrots")
				if brainrots then
					table.insert(roots, brainrots)
				end
			end
		end
	end

	local function considerPrompt(prompt)
		if not (prompt and prompt:IsA("ProximityPrompt")) then
			return
		end
		if prompt.Enabled ~= true or not prompt:IsDescendantOf(workspace) then
			return
		end
		if tostring(prompt.ObjectText or "") ~= "Hold to Get" then
			return
		end

		local promptParent = prompt.Parent
		if promptParent and promptParent:IsA("Attachment") then
			promptParent = promptParent.Parent
		end
		if not (promptParent and promptParent:IsA("BasePart")) then
			return
		end

		local model = prompt:FindFirstAncestorOfClass("Model")
		if not (model and model:IsDescendantOf(workspace)) then
			return
		end

		local targetPart = promptParent
		local dist = (targetPart.Position - origin).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestModel = model
			bestPrompt = prompt
			bestPart = targetPart
		end
	end

	for _, root in ipairs(roots) do
		if root and root:IsDescendantOf(workspace) then
			for _, prompt in ipairs(root:GetDescendants()) do
				considerPrompt(prompt)
			end
		end
	end

	return bestModel, bestPrompt, bestPart
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

			local model, nearestPrompt, targetPart = getNearestBrainrotTarget(character)
			if not model or not targetPart then
				hideBeam()
				currentBrainrotModel = nil
				currentBrainrotPrompt = nil
				task.wait(0.2)
			else
				currentBrainrotModel = model
				currentBrainrotPrompt = nearestPrompt or getModelPrompt(model)
				setTargetPart(targetPart)
				local prompt = popPrompt()
				if prompt then
					if
						(currentBrainrotPrompt and prompt == currentBrainrotPrompt)
						or (currentBrainrotModel and prompt:IsDescendantOf(currentBrainrotModel))
					then
						beamStage = "WAIT_FOR_FOLDER"
						clearPromptQueue()
					end
				end
				task.wait(0.08)
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
	local buyButton, xButton, speedUpgradeFrame = getButtons()
	waitForGuiReady(buyButton, speedUpgradeFrame, 2.5)
	startSpotlightFollow(buyButton, 2, 2, FALLBACK_FIRST_SIZE, FALLBACK_FIRST_POS, 0, STEP2_SPOTLIGHT_Y_OFFSET)

	local hidden = player:FindFirstChild("HiddenLeaderstats") or player:WaitForChild("HiddenLeaderstats")
	local speedValue = hidden:FindFirstChild("Speed") or hidden:WaitForChild("Speed")
	local speedStart = (speedValue and (speedValue:IsA("NumberValue") or speedValue:IsA("IntValue")))
			and speedValue.Value
		or nil
	local didAdvanceToStep3 = false

	local function advanceToStep3()
		if didAdvanceToStep3 or tutorialDisabled or finishedSent then
			return
		end
		didAdvanceToStep3 = true
		setTutorial(3, "Good! Now click X to close the menu.")
		waitForGuiReady(xButton, speedUpgradeFrame, 1.5)
		startSpotlightFollow(xButton, 6, 6, FALLBACK_SECOND_SIZE, FALLBACK_SECOND_POS, 0, STEP3_SPOTLIGHT_Y_OFFSET)
	end

	task.spawn(function()
		if speedValue then
			buyConn = speedValue:GetPropertyChangedSignal("Value"):Connect(function()
				if speedStart == nil then
					advanceToStep3()
					return
				end
				if speedValue.Value > speedStart then
					advanceToStep3()
				end
			end)
		end

		if buyButton then
			buyClickConn = buyButton.Activated:Connect(advanceToStep3)
		end

		xConn = xButton.Activated:Connect(function()
			if tutorialDisabled or finishedSent or not didAdvanceToStep3 then
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
		openFrame("SpeedUpgrade")

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
