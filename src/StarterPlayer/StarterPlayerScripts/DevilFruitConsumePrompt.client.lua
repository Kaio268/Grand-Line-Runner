local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local packages = ReplicatedStorage:WaitForChild("Packages")
local modules = ReplicatedStorage:WaitForChild("Modules")
local uiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(packages:WaitForChild("React"))
local ReactRoblox = require(packages:WaitForChild("ReactRoblox"))
local DevilFruitConfig = require(modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local EatAnimationClient = require(modules:WaitForChild("DevilFruits"):WaitForChild("EatAnimationClient"))
local DevilFruitRuntimeBootstrap = require(
	modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitRuntimeBootstrap")
)
local PopUpModule = require(modules:WaitForChild("PopUpModule"))
local UiModalState = require(modules:WaitForChild("UiModalState"))
local ConsumePromptScreen = require(uiFolder:WaitForChild("DevilFruit"):WaitForChild("ConsumePromptScreen"))

local promptRemote = remotes:WaitForChild("DevilFruitConsumePrompt")
local responseRemote = remotes:WaitForChild("DevilFruitConsumeResponse")
local requestRemote = remotes:WaitForChild("DevilFruitConsumeRequest")
local resultRemote = remotes:WaitForChild("DevilFruitConsumeResult")

local TOOL_ATTR_KIND = "InventoryItemKind"
local TOOL_ATTR_FRUIT_KEY = "FruitKey"
local INVENTORY_MENU_OPEN_ATTRIBUTE = "InventoryMenuOpen"
local GAMEPLAY_MODAL_OPEN_ATTRIBUTE = UiModalState.GetAttributeName()
local MODAL_STATE_KEY = "DevilFruitConsumePrompt"
local CONSUME_PROMPT_DEBUG = true
local EQUIP_TO_PROMPT_DELAY = 0.2
local REQUEST_COOLDOWN = 0.35

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactDevilFruitConsumePromptRoot"

local root = ReactRoblox.createRoot(rootContainer)
local pendingPayload
local lastRequestAt = 0
local destroyed = false
local renderQueued = false
local toolActivationConnections = {}
local toolEquippedAt = setmetatable({}, { __mode = "k" })
local toolEnabledBeforeMenuBlock = setmetatable({}, { __mode = "k" })

local function consumePromptDebug(message, ...)
	if CONSUME_PROMPT_DEBUG ~= true then
		return
	end

	local ok, formatted = pcall(string.format, "[FruitConsumeDebug][PromptClient] " .. tostring(message), ...)
	print(ok and formatted or ("[FruitConsumeDebug][PromptClient] " .. tostring(message)))
end

local function logPostConsumeRuntimeState(expectedFruitName)
	task.delay(0.75, function()
		local fruitFolder = player:FindFirstChild("DevilFruit")
		local equippedValue = fruitFolder and fruitFolder:FindFirstChild("Equipped")
		local equippedValueText = equippedValue and equippedValue:IsA("StringValue") and equippedValue.Value or "<nil>"

		consumePromptDebug(
			"post consume runtime expected=%s attr=%s value=%s bootstrapStarted=%s runtimeStarted=%s hudVisible=%s abilityCount=%s remotesReady=%s gameplayModalOpen=%s lastRemoteError=%s",
			tostring(expectedFruitName),
			tostring(player:GetAttribute("EquippedDevilFruit")),
			tostring(equippedValueText),
			tostring(DevilFruitRuntimeBootstrap.IsStarted()),
			tostring(player:GetAttribute("DevilFruitClientRuntimeStarted")),
			tostring(player:GetAttribute("DevilFruitClientHudVisible")),
			tostring(player:GetAttribute("DevilFruitClientAbilityCount")),
			tostring(player:GetAttribute("DevilFruitClientRemotesReady")),
			tostring(playerGui:GetAttribute(GAMEPLAY_MODAL_OPEN_ATTRIBUTE)),
			tostring(player:GetAttribute("DevilFruitClientLastRemoteError"))
		)
	end)
end

local function shouldRequireReplaceWarning(currentFruitName, nextFruitKey)
	local currentName = tostring(currentFruitName or "")
	if currentName == "" or currentName == "None" or currentName == DevilFruitConfig.None then
		return false
	end

	local resolvedCurrent = DevilFruitConfig.ResolveFruitName(currentName)
	local resolvedNext = DevilFruitConfig.ResolveFruitName(nextFruitKey)
	if resolvedCurrent ~= nil and resolvedNext ~= nil and resolvedCurrent == resolvedNext then
		return false
	end

	return resolvedCurrent ~= nil
end

local function playEatAnimation(fruitKey)
	EatAnimationClient.Play(player, fruitKey)
end

local function isDevilFruitTool(tool)
	return tool
		and tool:IsA("Tool")
		and tool:GetAttribute(TOOL_ATTR_KIND) == "DevilFruit"
		and typeof(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)) == "string"
end

local function isPromptOpen()
	return pendingPayload ~= nil
end

local function isGameplayModalOpen()
	return playerGui:GetAttribute(GAMEPLAY_MODAL_OPEN_ATTRIBUTE) == true
end

local function isInventoryMenuOpen()
	local isOtherGameplayModalOpen = isGameplayModalOpen() and not isPromptOpen()
	return isOtherGameplayModalOpen or player:GetAttribute(INVENTORY_MENU_OPEN_ATTRIBUTE) == true
end

local function setPromptPayload(payload)
	pendingPayload = payload
	UiModalState.SetOpen(MODAL_STATE_KEY, payload ~= nil)
end

local function getPromptBody()
	if not pendingPayload then
		return ""
	end

	if pendingPayload.Step == 2 and pendingPayload.RequiresReplaceWarning then
		return string.format("This will replace your %s.", pendingPayload.CurrentFruitName)
	end

	return "Are you sure you want to eat this fruit?"
end

local function getConfirmText()
	if pendingPayload and pendingPayload.Step == 2 and pendingPayload.RequiresReplaceWarning then
		return "Replace"
	end

	return "Eat"
end

local function render()
	root:render(ReactRoblox.createPortal(React.createElement(ConsumePromptScreen, {
		body = getPromptBody(),
		cancelText = "Cancel",
		confirmText = getConfirmText(),
		onCancel = function()
			if pendingPayload then
				responseRemote:FireServer(false, pendingPayload.FruitKey)
			end
			setPromptPayload(nil)
			render()
		end,
		onConfirm = function()
			if not pendingPayload then
				return
			end

			if pendingPayload.Step == 1 and pendingPayload.RequiresReplaceWarning then
				pendingPayload.Step = 2
				render()
				return
			end

			local confirmedPayload = pendingPayload
			setPromptPayload(nil)
			render()
			responseRemote:FireServer(true, confirmedPayload.FruitKey)
			task.spawn(playEatAnimation, confirmedPayload.FruitKey)
		end,
		title = pendingPayload and pendingPayload.DisplayName or "Devil Fruit",
		visible = pendingPayload ~= nil,
	}), playerGui))
end

local function scheduleRender()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			render()
		end
	end)
end

local function setToolInteractionBlocked(tool, isBlocked)
	if not isDevilFruitTool(tool) then
		return
	end

	if isBlocked then
		if toolEnabledBeforeMenuBlock[tool] == nil then
			toolEnabledBeforeMenuBlock[tool] = tool.Enabled
		end
		tool.Enabled = false
		consumePromptDebug(
			"tool block tool=%s fruit=%s enabledNow=%s previousEnabled=%s parent=%s",
			tool.Name,
			tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
			tostring(tool.Enabled),
			tostring(toolEnabledBeforeMenuBlock[tool]),
			tostring(tool.Parent and tool.Parent:GetFullName() or "nil")
		)
		return
	end

	local previousEnabled = toolEnabledBeforeMenuBlock[tool]
	if previousEnabled ~= nil then
		tool.Enabled = previousEnabled
		toolEnabledBeforeMenuBlock[tool] = nil
		consumePromptDebug(
			"tool unblock tool=%s fruit=%s enabledNow=%s parent=%s",
			tool.Name,
			tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
			tostring(tool.Enabled),
			tostring(tool.Parent and tool.Parent:GetFullName() or "nil")
		)
	end
end

local function syncFruitToolInteractionState()
	local isBlocked = isInventoryMenuOpen()
	consumePromptDebug(
		"sync interaction menuOpen=%s gameplayModalOpen=%s promptOpen=%s",
		tostring(isBlocked),
		tostring(isGameplayModalOpen()),
		tostring(isPromptOpen())
	)
	if isBlocked and isPromptOpen() then
		setPromptPayload(nil)
		scheduleRender()
		consumePromptDebug("hide prompt because inventory menu is open")
	end

	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			setToolInteractionBlocked(child, isBlocked)
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			setToolInteractionBlocked(child, isBlocked)
		end
	end
end

local function markToolEquipped(tool)
	if isDevilFruitTool(tool) then
		toolEquippedAt[tool] = os.clock()
	end
end

local function requestConsumeForTool(tool, source)
	if not isDevilFruitTool(tool) then
		consumePromptDebug("request blocked source=%s reason=not_fruit_tool", tostring(source))
		return
	end

	if isPromptOpen() then
		consumePromptDebug("request blocked source=%s tool=%s reason=prompt_open", tostring(source), tool.Name)
		return
	end

	if isInventoryMenuOpen() then
		consumePromptDebug("request blocked source=%s tool=%s reason=inventory_open", tostring(source), tool.Name)
		return
	end

	local now = os.clock()
	local equippedAt = toolEquippedAt[tool]
	if typeof(equippedAt) == "number" and (now - equippedAt) < EQUIP_TO_PROMPT_DELAY then
		consumePromptDebug(
			"request blocked source=%s tool=%s reason=equip_delay elapsed=%.3f",
			tostring(source),
			tool.Name,
			now - equippedAt
		)
		return
	end

	if now - lastRequestAt < REQUEST_COOLDOWN then
		consumePromptDebug(
			"request blocked source=%s tool=%s reason=cooldown elapsed=%.3f",
			tostring(source),
			tool.Name,
			now - lastRequestAt
		)
		return
	end

	lastRequestAt = now
	requestRemote:FireServer(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY), source)
end

local function bindFruitTool(tool)
	if not isDevilFruitTool(tool) or toolActivationConnections[tool] then
		return
	end

	setToolInteractionBlocked(tool, isInventoryMenuOpen())
	toolActivationConnections[tool] = tool.Activated:Connect(function()
		requestConsumeForTool(tool, "tool_activated")
	end)
end

local function getEquippedFruitTool()
	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if isDevilFruitTool(child) then
			return child
		end
	end

	return nil
end

local function bindCharacter(character)
	for _, child in ipairs(character:GetChildren()) do
		markToolEquipped(child)
		bindFruitTool(child)
	end

	character.ChildAdded:Connect(function(child)
		markToolEquipped(child)
		bindFruitTool(child)
	end)
end

promptRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.Hide == true or payload.Show == false then
		setPromptPayload(nil)
		scheduleRender()
		return
	end

	if isInventoryMenuOpen() then
		setPromptPayload(nil)
		scheduleRender()
		return
	end

	local currentFruitName = tostring(payload.CurrentFruitName or "")
	local nextFruitKey = tostring(payload.FruitKey or "")
	setPromptPayload({
		CurrentFruitName = currentFruitName,
		DisplayName = tostring(payload.FruitName or payload.FruitKey or "Devil Fruit"),
		FruitKey = payload.FruitKey,
		RequiresReplaceWarning = shouldRequireReplaceWarning(currentFruitName, nextFruitKey),
		Step = 1,
	})
	scheduleRender()
end)

resultRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.Success ~= true then
		consumePromptDebug("consume result success=false reason=%s", tostring(payload.Reason or "unknown"))
		return
	end

	local equippedFruitName = tostring(payload.EquippedFruitName or "")
	if equippedFruitName == "" or equippedFruitName == DevilFruitConfig.None then
		return
	end

	-- The server is authoritative; these local mirrors let every fruit-side consumer
	-- react immediately even if replicated instances arrive a frame later.
	player:SetAttribute("EquippedDevilFruit", equippedFruitName)

	local fruitFolder = player:FindFirstChild("DevilFruit")
	local equippedValue = fruitFolder and fruitFolder:FindFirstChild("Equipped")
	if equippedValue and equippedValue:IsA("StringValue") then
		equippedValue.Value = equippedFruitName
	end

	DevilFruitRuntimeBootstrap.Start()
	consumePromptDebug("consume result success=true equipped=%s", equippedFruitName)
	logPostConsumeRuntimeState(equippedFruitName)
	PopUpModule:Local_SendPopUp(
		"Fruit ready: " .. equippedFruitName,
		Color3.fromRGB(242, 209, 107),
		Color3.fromRGB(10, 18, 28),
		3,
		false
	)
end)

if player.Character then
	bindCharacter(player.Character)
end

player.CharacterAdded:Connect(bindCharacter)
player:GetAttributeChangedSignal(INVENTORY_MENU_OPEN_ATTRIBUTE):Connect(syncFruitToolInteractionState)
playerGui:GetAttributeChangedSignal(GAMEPLAY_MODAL_OPEN_ATTRIBUTE):Connect(syncFruitToolInteractionState)
player.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		syncFruitToolInteractionState()
		child.ChildAdded:Connect(syncFruitToolInteractionState)
	end
end)

syncFruitToolInteractionState()
render()
DevilFruitRuntimeBootstrap.Start()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch
	then
		return
	end

	if isInventoryMenuOpen() then
		return
	end

	local tool = getEquippedFruitTool()
	if tool then
		requestConsumeForTool(tool, "equipped_input")
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	UiModalState.SetOpen(MODAL_STATE_KEY, false)
	for _, connection in pairs(toolActivationConnections) do
		connection:Disconnect()
	end
	table.clear(toolActivationConnections)
	root:unmount()
end)
