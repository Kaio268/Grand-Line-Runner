local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local Point = require(ReplicatedStorage:WaitForChild("Point"))
local SpawnPartsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SpawnParts"))
local BrainrotsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))

local VariantPrefixes = { "Golden ", "Diamond " }
do
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotVariants"))
	end)
	if ok and typeof(cfg) == "table" and typeof(cfg.Versions) == "table" then
		local prefixes = {}
		for _, variantData in pairs(cfg.Versions) do
			if typeof(variantData) == "table" and typeof(variantData.Prefix) == "string" and variantData.Prefix ~= "" then
				prefixes[variantData.Prefix] = true
			end
		end
		VariantPrefixes = {}
		for prefix in pairs(prefixes) do
			table.insert(VariantPrefixes, prefix)
		end
	end
end

local KnownBrainrotNames = {}
for brainrotName in pairs(BrainrotsConfig) do
	KnownBrainrotNames[tostring(brainrotName)] = true
end

local function stripVariantPrefix(name)
	local raw = tostring(name or "")
	for _, prefix in ipairs(VariantPrefixes) do
		if string.sub(raw, 1, #prefix) == prefix then
			return string.sub(raw, #prefix + 1)
		end
	end
	return raw
end

local function isLikelyBrainrotModelName(name)
	local raw = tostring(name or "")
	if raw == "" then
		return false
	end
	if KnownBrainrotNames[raw] then
		return true
	end
	local stripped = stripVariantPrefix(raw)
	return KnownBrainrotNames[stripped] == true
end

local TUTORIAL_DEBUG = true
local debugLastAt = {}

local function getInstancePath(inst)
	if not inst then
		return "nil"
	end
	local ok, path = pcall(function()
		return inst:GetFullName()
	end)
	if ok and path then
		return path
	end
	return tostring(inst)
end

local function debugTutorial(key, message, throttleSeconds)
	if not TUTORIAL_DEBUG then
		return
	end

	local keyName = tostring(key or "GEN")
	local interval = tonumber(throttleSeconds) or 0
	local now = os.clock()
	local last = debugLastAt[keyName] or 0
	if interval > 0 and (now - last) < interval then
		return
	end
	debugLastAt[keyName] = now
	print(string.format("[TUTORIAL][%s][%.2f] %s", keyName, now, tostring(message)))
end

local lastBrainrotModelSweepAt = 0
local lastBrainrotModelSweepResult = nil

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

local function hasCarriedBrainrot()
	local carried = player:GetAttribute("CarriedBrainrot")
	return typeof(carried) == "string" and carried ~= ""
end

local function hasBrainrotTool(container)
	if not container then
		return false
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and isLikelyBrainrotModelName(child.Name) then
			return true
		end
	end
	return false
end

local function hasCollectedBrainrotForTutorial()
	if hasCarriedBrainrot() or inventoryHasAnyFolder() then
		return true
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if hasBrainrotTool(backpack) then
		return true
	end

	local character = player.Character
	if hasBrainrotTool(character) then
		return true
	end

	return false
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
	local debugInfo = {
		roots = 0,
		promptCandidates = 0,
		modelCandidates = 0,
		partCandidates = 0,
		hoverCandidates = 0,
		source = "none",
	}

	local roots = {}
	local validRarityParts = {}
	for rarityName in pairs((SpawnPartsConfig and SpawnPartsConfig.RarityTier) or {}) do
		validRarityParts[tostring(rarityName)] = true
	end

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

	-- Newer biome layouts can store active brainrots under Biomes/*/*/Brainrots.
	local biomesRoot = mapRoot and mapRoot:FindFirstChild("Biomes")
	if biomesRoot then
		for _, descendant in ipairs(biomesRoot:GetDescendants()) do
			if
				(descendant:IsA("Folder") and descendant.Name == "Brainrots")
				or (descendant:IsA("BasePart") and validRarityParts[descendant.Name])
			then
				table.insert(roots, descendant)
			end
		end
	end

	local function considerPrompt(prompt, source)
		if not (prompt and prompt:IsA("ProximityPrompt")) then
			return
		end
		debugInfo.promptCandidates += 1
		if not prompt:IsDescendantOf(workspace) then
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
			debugInfo.source = source or "prompt"
		end
	end

	local function considerModel(model, source)
		if not (model and model:IsA("Model") and model:IsDescendantOf(workspace)) then
			return
		end
		debugInfo.modelCandidates += 1

		local targetPart = getModelTargetPart(model)
		if not targetPart then
			return
		end

		local prompt = getModelPrompt(model)
		local dist = (targetPart.Position - origin).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestModel = model
			bestPrompt = prompt
			bestPart = targetPart
			debugInfo.source = source or "model"
		end
	end

	local function considerPart(part, source)
		if not (part and part:IsA("BasePart") and part:IsDescendantOf(workspace)) then
			return
		end
		debugInfo.partCandidates += 1

		local model = part:FindFirstAncestorOfClass("Model")
		local prompt = model and getModelPrompt(model) or part:FindFirstChildWhichIsA("ProximityPrompt")
		local dist = (part.Position - origin).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestModel = model
			bestPrompt = prompt
			bestPart = part
			debugInfo.source = source or "part"
		end
	end

	local function considerVisualBrainrotModel(model, source)
		if not (model and model:IsA("Model") and model:IsDescendantOf(workspace)) then
			return
		end
		debugInfo.hoverCandidates += 1

		local hover = model:FindFirstChild("BrainrotHover", true) or model:FindFirstChild("BrainortHover", true)
		if not hover then
			return
		end

		local part = getModelTargetPart(model)
		if not part then
			return
		end

		local prompt = getModelPrompt(model)
		local dist = (part.Position - origin).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestModel = model
			bestPrompt = prompt
			bestPart = part
			debugInfo.source = source or "hover"
		end
	end

	for _, root in ipairs(roots) do
		if root and root:IsDescendantOf(workspace) then
			debugInfo.roots += 1
			for _, prompt in ipairs(root:GetDescendants()) do
				considerPrompt(prompt, "root_prompt")
			end
		end
	end

	-- Fallback 1: some brainrots may be present without usable prompt filters.
	if not bestModel then
		for _, root in ipairs(roots) do
			if root and root:IsDescendantOf(workspace) then
				for _, candidate in ipairs(root:GetDescendants()) do
					if candidate:IsA("Model") and (modelHasPrompt(candidate) or candidate:FindFirstChildWhichIsA("BasePart", true)) then
						considerModel(candidate, "root_model")
					elseif candidate:IsA("BasePart") then
						considerPart(candidate, "root_part")
					end
				end
			end
		end
	end

	-- Fallback 2: global prompt scan near spawn area in case folder layout changed.
	if not bestModel then
		for _, prompt in ipairs(workspace:GetDescendants()) do
			if prompt:IsA("ProximityPrompt") then
				local action = string.lower(tostring(prompt.ActionText or ""))
				local objectText = string.lower(tostring(prompt.ObjectText or ""))
				local likelyCollectPrompt = string.find(action, "collect", 1, true)
					or string.find(action, "get", 1, true)
					or string.find(objectText, "collect", 1, true)
					or string.find(objectText, "get", 1, true)
				if likelyCollectPrompt then
					considerPrompt(prompt, "global_collect_prompt")
				end
			end
		end
	end

	-- Fallback 3: nearest visible brainrot model marker.
	if not bestModel then
		local now = os.clock()
		if now - lastBrainrotModelSweepAt >= 0.45 then
			lastBrainrotModelSweepAt = now
			lastBrainrotModelSweepResult = nil
			if mapRoot then
				for _, candidate in ipairs(mapRoot:GetDescendants()) do
					if candidate:IsA("Model") then
						if isLikelyBrainrotModelName(candidate.Name) then
							considerModel(candidate, "map_name_match")
						end
						if not bestModel then
							considerVisualBrainrotModel(candidate, "map_visual_hover")
						end
					end
					if bestModel then
						lastBrainrotModelSweepResult = {
							model = bestModel,
							prompt = bestPrompt,
							part = bestPart,
						}
					end
				end
			end
		elseif lastBrainrotModelSweepResult then
			local cached = lastBrainrotModelSweepResult
			if
				cached.model
				and cached.part
				and cached.model:IsDescendantOf(workspace)
				and cached.part:IsDescendantOf(workspace)
			then
				bestModel = cached.model
				bestPrompt = cached.prompt
				bestPart = cached.part
			end
		end
	end

	-- Fallback 4: nearest non-player humanoid model in map area.
	if not bestModel and mapRoot then
		for _, candidate in ipairs(mapRoot:GetDescendants()) do
			if candidate:IsA("Model") and candidate ~= character then
				local humanoid = candidate:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local nameLower = string.lower(candidate.Name)
					if
						not string.find(nameLower, "chest", 1, true)
						and not string.find(nameLower, "stand", 1, true)
						and not string.find(nameLower, "plot", 1, true)
					then
						considerModel(candidate, "map_non_player_humanoid")
					end
				end
			end
		end
	end

	-- Fallback 5: scan every "Brainrots" folder in workspace directly.
	if not bestModel then
		for _, folder in ipairs(workspace:GetDescendants()) do
			if folder:IsA("Folder") and folder.Name == "Brainrots" then
				for _, candidate in ipairs(folder:GetChildren()) do
					if candidate:IsA("Model") then
						considerModel(candidate, "workspace_brainrots_folder_model")
					elseif candidate:IsA("BasePart") then
						considerPart(candidate, "workspace_brainrots_folder_part")
					end
				end
			end
		end
	end

	-- Fallback 6: nearest visible brainrot hover adornee.
	if not bestModel then
		for _, gui in ipairs(workspace:GetDescendants()) do
			if gui:IsA("BillboardGui") and (gui.Name == "BrainrotHover" or gui.Name == "BrainortHover") then
				local adornee = gui.Adornee
				if adornee and adornee:IsA("BasePart") then
					considerPart(adornee, "brainrot_hover_adornee")
				end
			end
		end
	end

	-- Fallback 7: nearest non-player prompt in world to ensure beam visibility.
	if not bestPart then
		local characterModel = character
		for _, prompt in ipairs(workspace:GetDescendants()) do
			if prompt:IsA("ProximityPrompt") then
				local p = prompt.Parent
				if p and p:IsA("Attachment") then
					p = p.Parent
				end
				if p and p:IsA("BasePart") then
					local ownerModel = p:FindFirstAncestorOfClass("Model")
					if ownerModel and ownerModel ~= characterModel and ownerModel ~= npc then
						local ownerLower = string.lower(ownerModel.Name)
						local shouldSkip = string.find(ownerLower, "sell", 1, true)
							or string.find(ownerLower, "upgrade", 1, true)
							or string.find(ownerLower, "stand", 1, true)
							or string.find(ownerLower, "plot", 1, true)
						if not shouldSkip then
							considerPrompt(prompt, "global_non_player_prompt")
						end
					end
				end
			end
		end
	end

	debugInfo.bestDist = bestDist
	return bestModel, bestPrompt, bestPart, debugInfo
end

local function getFallbackSpawnTargetPart(character)
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end

	local origin = hrp.Position
	local bestPart = nil
	local bestDist = math.huge
	local validRarityParts = {}
	for rarityName in pairs((SpawnPartsConfig and SpawnPartsConfig.RarityTier) or {}) do
		validRarityParts[tostring(rarityName)] = true
	end

	local function considerPart(part)
		if not (part and part:IsA("BasePart") and part:IsDescendantOf(workspace)) then
			return
		end
		local dist = (part.Position - origin).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestPart = part
		end
	end

	local spawnFolder = getSpawnContainer()
	if spawnFolder and spawnFolder:IsDescendantOf(workspace) then
		for _, descendant in ipairs(spawnFolder:GetDescendants()) do
			if descendant:IsA("BasePart") and validRarityParts[descendant.Name] then
				considerPart(descendant)
			end
		end
	end

	local biomesRoot = refs and refs.MapRoot and refs.MapRoot:FindFirstChild("Biomes")
	if biomesRoot then
		for _, descendant in ipairs(biomesRoot:GetDescendants()) do
			if descendant:IsA("BasePart") and validRarityParts[descendant.Name] then
				considerPart(descendant)
			end
		end
	end

	return bestPart
end

local function getBrrMesh()
	local mesh = npc:FindFirstChild("Mesh")
	if mesh then
		return mesh
	end

	mesh = npc:WaitForChild("Mesh", 2)
	if mesh then
		return mesh
	end

	return npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart", true)
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
	debugTutorial("STAGE", "Entered TO_BRR", 0)

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
	debugTutorial("STAGE", "Entered PLOT_STAND", 0)

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
			debugTutorial("BEAM_TO_BRR", "target=" .. getInstancePath(getBrrMesh()), 1.5)
			task.wait(0.2)
		elseif beamStage == "BRAINROT" then
			setTutorial(4, "Follow the beam to the nearest Brainrot and hold E to collect it.")

			local model, nearestPrompt, targetPart, debugInfo = getNearestBrainrotTarget(character)

			-- Keep aiming at whichever brainrot is currently closest and active.
			if model and targetPart then
				currentBrainrotModel = model
				currentBrainrotPrompt = nearestPrompt or getModelPrompt(model)
				setTargetPart(targetPart)
				debugTutorial(
					"STEP4_TARGET",
					string.format(
						"source=%s model=%s part=%s prompt=%s dist=%.2f",
						tostring(debugInfo and debugInfo.source or "unknown"),
						getInstancePath(model),
						getInstancePath(targetPart),
						getInstancePath(currentBrainrotPrompt),
						tonumber(debugInfo and debugInfo.bestDist) or -1
					),
					0.4
				)
			elseif currentBrainrotModel and aliveInWorkspace(currentBrainrotModel) then
				local fallbackPart = getModelTargetPart(currentBrainrotModel)
				if fallbackPart then
					setTargetPart(fallbackPart)
					debugTutorial(
						"STEP4_TARGET",
						"using cached model target=" .. getInstancePath(fallbackPart),
						0.4
					)
				else
					hideBeam()
					debugTutorial("STEP4_HIDE", "cached model had no valid part; hiding beam", 0.8)
				end
			else
				currentBrainrotModel = nil
				currentBrainrotPrompt = nil
				local fallbackPart = getFallbackSpawnTargetPart(character)
				if fallbackPart then
					setTargetPart(fallbackPart)
					debugTutorial(
						"STEP4_FALLBACK",
						"using spawn fallback part=" .. getInstancePath(fallbackPart),
						0.7
					)
				else
					hideBeam()
					debugTutorial(
						"STEP4_NOT_FOUND",
						string.format(
							"no brainrot target found (roots=%s prompts=%s models=%s parts=%s hovers=%s)",
							tostring(debugInfo and debugInfo.roots or 0),
							tostring(debugInfo and debugInfo.promptCandidates or 0),
							tostring(debugInfo and debugInfo.modelCandidates or 0),
							tostring(debugInfo and debugInfo.partCandidates or 0),
							tostring(debugInfo and debugInfo.hoverCandidates or 0)
						),
						0.7
					)
				end
			end

			-- Advance only when collection is confirmed.
			local prompt = popPrompt()
			if prompt then
				if
					(currentBrainrotPrompt and prompt == currentBrainrotPrompt)
					or (currentBrainrotModel and prompt:IsDescendantOf(currentBrainrotModel))
				then
					debugTutorial("STEP4_PROGRESS", "brainrot prompt triggered, advancing to stand step", 0)
					clearPromptQueue()
					startPlotStandStep()
					task.wait(0.08)
					continue
				end
			end

			if hasCollectedBrainrotForTutorial() then
				debugTutorial("STEP4_PROGRESS", "carried/inventory detected, advancing to stand step", 0)
				clearPromptQueue()
				startPlotStandStep()
				task.wait(0.08)
				continue
			end
			debugTutorial("STEP4_WAIT", "no collected brainrot detected yet", 1.2)

			task.wait(0.08)
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
			debugTutorial("STAGE", "Entered BRAINROT from Step 3 close", 0)

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
