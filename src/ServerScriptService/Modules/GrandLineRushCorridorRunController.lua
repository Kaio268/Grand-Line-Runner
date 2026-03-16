local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local SliceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))

local Controller = {}

local started = false
local rewardObjectsByUserId = {}
local extractionTouchDebounce = {}

local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local INFO_COLOR = Color3.fromRGB(119, 217, 255)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local function sendPopup(player, text, color, isError)
	if not player or player.Parent ~= Players then
		return
	end

	PopUpModule:Server_SendPopUp(player, text, color or INFO_COLOR, STROKE_COLOR, 3, isError == true)
end

local function buildResponseMessage(response, fallbackMessage)
	if response and type(response.message) == "string" and response.message ~= "" then
		return response.message
	end

	return fallbackMessage
end

local function getWaveParts()
	local map = Workspace:FindFirstChild("Map")
	local waveFolder = map and map:FindFirstChild("WaveFolder")
	local startPart = waveFolder and waveFolder:FindFirstChild("Start")
	local endPart = waveFolder and waveFolder:FindFirstChild("End")
	if not (startPart and startPart:IsA("BasePart") and endPart and endPart:IsA("BasePart")) then
		return nil
	end

	return waveFolder, startPart, endPart
end

local function waitForWaveParts(timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 10)
	while os.clock() <= deadline do
		local waveFolder, startPart, endPart = getWaveParts()
		if waveFolder and startPart and endPart then
			return waveFolder, startPart, endPart
		end
		task.wait(0.2)
	end

	return getWaveParts()
end

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getOrCreatePart(parent, name)
	local part = parent:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part
	end

	if part then
		part:Destroy()
	end

	part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = true
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function configurePrompt(prompt, actionText, objectText)
	local worldConfig = Economy.VerticalSlice.WorldRun
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = tonumber(worldConfig.PromptHoldDuration) or 0.25
	prompt.MaxActivationDistance = tonumber(worldConfig.PromptMaxDistance) or 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.ClickablePrompt = true
end

local function getOrCreatePrompt(parent, name, actionText, objectText)
	local prompt = parent:FindFirstChild(name)
	if prompt and prompt:IsA("ProximityPrompt") then
		configurePrompt(prompt, actionText, objectText)
		return prompt
	end

	if prompt then
		prompt:Destroy()
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	configurePrompt(prompt, actionText, objectText)
	prompt.Parent = parent
	return prompt
end

local function getLaneDirections(startPart, endPart)
	local forward = startPart.Position - endPart.Position
	if forward.Magnitude < 0.001 then
		forward = endPart.CFrame.LookVector
	end
	forward = forward.Unit

	local side = forward:Cross(Vector3.yAxis)
	if side.Magnitude < 0.001 then
		side = endPart.CFrame.RightVector
	end
	side = side.Unit

	return forward, side
end

local function getLaneOffset(userId)
	local worldConfig = Economy.VerticalSlice.WorldRun
	local spacing = tonumber(worldConfig.RewardLaneSpacing) or 5
	local maxOffset = tonumber(worldConfig.RewardMaxLaneOffset) or 10
	local slot = (tonumber(userId) or 0) % 5
	local centered = slot - 2
	return math.clamp(centered * spacing, -maxOffset, maxOffset)
end

local function getRewardCFrame(player, rewardState, startPart, endPart)
	local worldConfig = Economy.VerticalSlice.WorldRun
	local alphaByBand = worldConfig.RewardAlphaByDepthBand or {}
	local depthBand = rewardState and rewardState.DepthBand or Economy.VerticalSlice.DefaultDepthBand
	local alpha = tonumber(alphaByBand[depthBand]) or tonumber(alphaByBand[Economy.VerticalSlice.DefaultDepthBand]) or 0.5
	alpha = math.clamp(alpha, 0, 1)

	local basePosition = endPart.Position:Lerp(startPart.Position, alpha)
	local _, side = getLaneDirections(startPart, endPart)
	local heightOffset = tonumber(worldConfig.RewardHeightOffset) or 3.5
	local laneOffset = getLaneOffset(player.UserId)
	local position = basePosition + (side * laneOffset) + Vector3.new(0, heightOffset, 0)

	return CFrame.new(position)
end

local function buildRewardKey(rewardState)
	if not rewardState then
		return "none"
	end

	if rewardState.RewardType == "Chest" then
		return string.format("Chest:%s:%s", tostring(rewardState.Tier), tostring(rewardState.DepthBand))
	end

	return string.format("Crew:%s:%s:%s", tostring(rewardState.Rarity), tostring(rewardState.CrewName), tostring(rewardState.DepthBand))
end

local function destroyRewardObject(userId)
	local object = rewardObjectsByUserId[userId]
	if object and object.Parent then
		object:Destroy()
	end
	rewardObjectsByUserId[userId] = nil
end

local function addRewardBillboard(part, rewardState, player)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RewardBillboard"
	billboard.Size = UDim2.fromOffset(180, 54)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Text = tostring(rewardState.DisplayName or "Major Reward")
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0
	title.Parent = billboard

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 28)
	subtitle.Size = UDim2.new(1, 0, 0, 22)
	subtitle.Text = string.format("%s's reward", player.DisplayName)
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextColor3 = Color3.fromRGB(224, 236, 255)
	subtitle.TextStrokeTransparency = 0.15
	subtitle.Parent = billboard
end

local function createRewardObject(player, rewardState, rewardFolder, startPart, endPart)
	local rewardKey = buildRewardKey(rewardState)
	local existing = rewardObjectsByUserId[player.UserId]
	if existing and existing.Parent and existing:GetAttribute("RewardKey") == rewardKey then
		existing.CFrame = getRewardCFrame(player, rewardState, startPart, endPart)
		return
	end

	destroyRewardObject(player.UserId)

	local part = Instance.new("Part")
	part.Name = string.format("RunReward_%d", player.UserId)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Shape = if rewardState.RewardType == "Chest" then Enum.PartType.Block else Enum.PartType.Ball
	part.Size = if rewardState.RewardType == "Chest" then Vector3.new(3, 3, 3) else Vector3.new(3.25, 3.25, 3.25)
	part.Color = if rewardState.RewardType == "Chest" then Color3.fromRGB(214, 155, 74) else Color3.fromRGB(91, 143, 255)
	part.CFrame = getRewardCFrame(player, rewardState, startPart, endPart)
	part:SetAttribute("OwnerUserId", player.UserId)
	part:SetAttribute("RewardKey", rewardKey)
	part:SetAttribute("RewardType", rewardState.RewardType)
	part.Parent = rewardFolder

	local highlight = Instance.new("Highlight")
	highlight.FillColor = part.Color
	highlight.FillTransparency = 0.35
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.Parent = part

	addRewardBillboard(part, rewardState, player)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpPrompt"
	configurePrompt(prompt, "Pick Up Reward", tostring(rewardState.DisplayName or "Major Reward"))
	prompt.Parent = part

	prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer ~= player then
			return
		end

		local response = SliceService.ClaimSpawnedReward(player)
		if response.ok then
			sendPopup(player, buildResponseMessage(response, "Reward picked up. Bring it back to extract."), SUCCESS_COLOR, false)
		else
			sendPopup(player, buildResponseMessage(response, "Could not pick up reward."), ERROR_COLOR, true)
		end
	end)

	rewardObjectsByUserId[player.UserId] = part
end

local function syncPlayerRewardObject(player, state, rewardFolder, startPart, endPart)
	local runState = state and state.Run or {}
	local spawnedReward = runState.SpawnedReward
	if runState.InRun == true and spawnedReward ~= nil then
		createRewardObject(player, spawnedReward, rewardFolder, startPart, endPart)
		return
	end

	destroyRewardObject(player.UserId)
end

local function findPlayerFromHit(hit)
	local current = hit
	while current and current ~= Workspace do
		local candidate = Players:GetPlayerFromCharacter(current)
		if candidate then
			return candidate
		end
		current = current.Parent
	end

	return nil
end

local function canTriggerExtraction(player)
	local now = os.clock()
	local lastTouch = extractionTouchDebounce[player]
	if lastTouch and (now - lastTouch) < 0.75 then
		return false
	end

	extractionTouchDebounce[player] = now
	return true
end

local function ensureInteractionParts(waveFolder, endPart)
	local controllerFolder = getOrCreateFolder(waveFolder, "GrandLineRush")

	local worldConfig = Economy.VerticalSlice.WorldRun
	local startHub = getOrCreatePart(controllerFolder, "RunHub")
	startHub.Size = worldConfig.StartHubSize
	startHub.CFrame = endPart.CFrame + Vector3.new(0, 4, 0)

	local extractionZone = getOrCreatePart(controllerFolder, "ExtractionZone")
	extractionZone.Size = worldConfig.ExtractionZoneSize
	extractionZone.CFrame = endPart.CFrame + Vector3.new(0, 4, 0)

	local rewardFolder = getOrCreateFolder(controllerFolder, "RunRewards")

	return controllerFolder, startHub, extractionZone, rewardFolder
end

function Controller.Start()
	if started then
		return
	end

	if Economy.VerticalSlice.Enabled ~= true then
		return
	end

	local worldConfig = Economy.VerticalSlice.WorldRun
	if typeof(worldConfig) ~= "table" or worldConfig.Enabled ~= true then
		return
	end

	SliceService.Start()

	local waveFolder, startPart, endPart = waitForWaveParts(15)
	if not (waveFolder and startPart and endPart) then
		warn("[GrandLineRushCorridorRunController] WaveFolder.Start/End not found; corridor integration skipped.")
		return
	end

	local _, startHub, extractionZone, rewardFolder = ensureInteractionParts(waveFolder, endPart)

	local chestPrompt = getOrCreatePrompt(startHub, "StartChestRunPrompt", "Start Chest Run", "Grand Line Rush Corridor")
	local crewPrompt = getOrCreatePrompt(startHub, "StartCrewRunPrompt", "Start Crew Run", "Grand Line Rush Corridor")

	local function startRunForPlayer(player, rewardType)
		local response = SliceService.StartRun(player, rewardType, worldConfig.StartDepthBand or Economy.VerticalSlice.DefaultDepthBand)
		if response.ok then
			sendPopup(player, buildResponseMessage(response, rewardType .. " run started."), INFO_COLOR, false)
		else
			sendPopup(player, buildResponseMessage(response, "Could not start run."), ERROR_COLOR, true)
		end
	end

	chestPrompt.Triggered:Connect(function(player)
		startRunForPlayer(player, "Chest")
	end)

	crewPrompt.Triggered:Connect(function(player)
		startRunForPlayer(player, "Crew")
	end)

	extractionZone.Touched:Connect(function(hit)
		local player = findPlayerFromHit(hit)
		if not player or not canTriggerExtraction(player) then
			return
		end

		local state = SliceService.GetState(player)
		local runState = state and state.Run or {}
		if runState.InRun ~= true or runState.CarriedReward == nil then
			return
		end

		local response = SliceService.ExtractRun(player)
		if response.ok then
			sendPopup(player, buildResponseMessage(response, "Reward extracted."), SUCCESS_COLOR, false)
		else
			sendPopup(player, buildResponseMessage(response, "Could not extract reward."), ERROR_COLOR, true)
		end
	end)

	SliceService.StateChanged:Connect(function(player, state)
		if player and player.Parent == Players then
			syncPlayerRewardObject(player, state, rewardFolder, startPart, endPart)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		destroyRewardObject(player.UserId)
		extractionTouchDebounce[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			syncPlayerRewardObject(player, SliceService.GetState(player), rewardFolder, startPart, endPart)
		end)
	end

	started = true
end

return Controller
