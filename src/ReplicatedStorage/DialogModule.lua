-- DialogModule.lua
local DialogModule = {}
DialogModule.__index = DialogModule

local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")

local TICK_SOUND = script.sounds.tick

local SHOW_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TEXT_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local LIST_HEIGHT_SCALE = 0.35

local function getDialogResponsesUI(player)
	local resolvedPlayer = player
	if runService:IsClient() then
		resolvedPlayer = players.LocalPlayer
	end
	if not resolvedPlayer then
		return nil
	end

	local playerGui = resolvedPlayer:FindFirstChild("PlayerGui") or resolvedPlayer:WaitForChild("PlayerGui", 5)
	if not playerGui then
		return nil
	end

	local dialogGui = playerGui:FindFirstChild("dialog") or playerGui:WaitForChild("dialog", 5)
	if not dialogGui then
		return nil
	end

	return dialogGui:FindFirstChild("dialogResponses") or dialogGui:WaitForChild("dialogResponses", 5)
end

local function ensureResponseButtons(player)
	local responsesUi = getDialogResponsesUI(player)
	if not responsesUi then
		return nil
	end

	local template = responsesUi:FindFirstChild("template")
	if template then
		for i = 1, 9 do
			local newResponseButton = template:Clone()
			newResponseButton.Parent = responsesUi
			newResponseButton.Name = tostring(i)
			newResponseButton.Visible = false
			newResponseButton.Size = UDim2.new(1, 0, 1, 0)
		end
		template:Destroy()
	end

	return responsesUi
end

function DialogModule.new(npcName, npc, prompt, animation)
	local self = setmetatable({}, DialogModule)
	self.npcName = npcName
	self.npc = npc
	self.dialogs = {}
	self.responses = {}
	self.dialogOption = 1
	self.npcGui = self.npc.PrimaryPart:WaitForChild("gui")
	self.active = false
	self.talking = false
	self.prompt = prompt

	ensureResponseButtons()

	local eventSignal = Instance.new("BindableEvent")
	self.responded = eventSignal.Event
	self.fireResponded = eventSignal

	self.animNameText = tweenService:Create(self.npcGui.name, TweenInfo.new(0.3), { TextTransparency = 1 })
	self.animNameStroke = tweenService:Create(self.npcGui.name.UIStroke, TweenInfo.new(0.3), { Transparency = 1 })
	self.animDialogText = tweenService:Create(self.npcGui.dialog, TweenInfo.new(0.3), { TextTransparency = 1 })
	self.animDialogStroke = tweenService:Create(self.npcGui.dialog.UIStroke, TweenInfo.new(0.3), { Transparency = 1 })

	if animation ~= nil then
		local newAnimation = Instance.new("Animation")
		newAnimation.AnimationId = animation
		local newAnimLoaded = npc:WaitForChild("Humanoid"):LoadAnimation(newAnimation)
		newAnimLoaded:Play()
	end

	local frameCount = 0
	local heartbeatConnection = runService.Heartbeat:Connect(function()
		frameCount += 1
		if self.talking then
			self.npcGui.StudsOffset = Vector3.new(0, 6, 0)
		else
			self.npcGui.StudsOffset = Vector3.new(0, math.sin(frameCount / 25) / 6 + 6, 0)
		end
	end)

	local shownConnection = nil
	local hiddenConnection = nil
	if self.prompt then
		shownConnection = self.prompt.PromptShown:Connect(function()
			self.npcGui.AlwaysOnTop = true
		end)
		hiddenConnection = self.prompt.PromptHidden:Connect(function()
			if self.talking then
				return
			end
			self.npcGui.AlwaysOnTop = false
		end)
	end

	self.connections = { heartbeatConnection, shownConnection, hiddenConnection }

	return self
end

function DialogModule:addDialog(dialogText, responseOptions)
	table.insert(self.dialogs, { text = dialogText, responses = responseOptions })
end

function DialogModule:sortDialogs(sortFunc)
	table.sort(self.dialogs, sortFunc or function(a, b)
		return a.text < b.text
	end)
end

function DialogModule:triggerDialog(player, questionNumber)
	self:showGui()

	if #self.dialogs == 0 then
		warn("No dialogs available for NPC: " .. self.npcName)
		return
	end

	local dialogNum = questionNumber or self.dialogOption
	local dialog = self.dialogs[dialogNum]
	if not dialog then
		warn(("Dialog %s does not exist for NPC: %s"):format(tostring(dialogNum), self.npcName))
		return
	end

	local currentCamera = workspace.CurrentCamera
	if currentCamera then
		tweenService:Create(
			currentCamera,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = 65 }
		):Play()
	end

	task.spawn(function()
		self.talking = true

		local dialogObject = self.npcGui.dialog
		dialogObject.Visible = true
		dialogObject.Text = ""
		local currenttext = ""
		local skip = false
		local arrow = 0

		for _, letter in string.split(dialog.text, "") do
			currenttext = currenttext .. letter
			if letter == "<" then
				skip = true
			end
			if letter == ">" then
				skip = false
				arrow += 1
				continue
			end
			if arrow == 2 then
				arrow = 0
			end
			if skip then
				continue
			end
			dialogObject.Text = currenttext .. (arrow == 1 and "</font>" or "")
			TICK_SOUND:Play()
			task.wait(0.02)
		end

		dialogObject.Text = dialog.text
		self.talking = false

		local keyboardInputs = {
			Enum.KeyCode.One,
			Enum.KeyCode.Two,
			Enum.KeyCode.Three,
			Enum.KeyCode.Four,
			Enum.KeyCode.Five,
			Enum.KeyCode.Six,
			Enum.KeyCode.Seven,
			Enum.KeyCode.Eight,
			Enum.KeyCode.Nine,
		}

		local uiResponses = ensureResponseButtons(player)
		if not uiResponses then
			warn(("Dialog responses UI is unavailable for NPC: %s"):format(tostring(self.npcName)))
			self:hideGui("...")
			return
		end

		local responseNum = nil

		local function setPlainText(guiObj, txt)
			if guiObj and (guiObj:IsA("TextLabel") or guiObj:IsA("TextButton")) then
				guiObj.RichText = false
				guiObj.Text = txt
			end
		end

		for i, response in ipairs(dialog.responses) do
			local option = uiResponses:FindFirstChild(tostring(i))
			if not option then
				warn(("Missing response button '%d' in dialogResponses"):format(i))
				continue
			end

			local slot1 = option:FindFirstChild("Slot")
			local slot2 = slot1 and slot1:FindFirstChild("2")
			local textLabel = option:FindFirstChild("text") or option:FindFirstChild("Text") or option:FindFirstChild("Response")

			setPlainText(slot1, tostring(i))
			setPlainText(slot2, tostring(i))
			setPlainText(textLabel, tostring(response))

			option.Size = UDim2.new(1, 0, 1, 0)
			option.Visible = true
			option.Size = UDim2.new(1, 0, 0, 0)
			tweenService:Create(option, SHOW_TWEEN, { Size = UDim2.new(1, 0, 1, 0) }):Play()

			local enterCon = option.MouseEnter:Connect(function()
				tweenService:Create(option, HOVER_TWEEN, { Size = UDim2.new(1, 0, 1, 0) }):Play()
			end)

			local leaveCon = option.MouseLeave:Connect(function()
				tweenService:Create(option, HOVER_TWEEN, { Size = UDim2.new(1, 0, 1, 0) }):Play()
			end)

			local chooseCon = option.MouseButton1Down:Connect(function()
				if not self.active then
					return
				end
				self.active = false
				responseNum = i
				self.fireResponded:Fire(i, dialogNum)
				TICK_SOUND:Play()
			end)

			local numberpressCon = userInputService.InputBegan:Connect(function(input, gameProcessed)
				if gameProcessed then
					return
				end
				if input.UserInputType ~= Enum.UserInputType.Keyboard then
					return
				end

				local numberinput = table.find(keyboardInputs, input.KeyCode)
				if numberinput ~= nil and numberinput == i then
					if not self.active then
						return
					end
					self.active = false
					responseNum = i
					self.fireResponded:Fire(i, dialogNum)
					TICK_SOUND:Play()
				end
			end)

			coroutine.wrap(function()
				repeat
					task.wait()
				until responseNum ~= nil
				enterCon:Disconnect()
				leaveCon:Disconnect()
				chooseCon:Disconnect()
				numberpressCon:Disconnect()
				if option then
					option.Visible = false
					option.Size = UDim2.new(1, 0, LIST_HEIGHT_SCALE, 0)
				end
			end)()

			task.wait(0.2)
		end

		self.active = true

		local range = 10
		while self.active do
			local char = player.Character
			if char == nil or not char.PrimaryPart then
				break
			end
			if not self.npc or not self.npc:FindFirstChild("UpperTorso") then
				break
			end

			local distance = (char.PrimaryPart.Position - self.npc.UpperTorso.Position).Magnitude
			if distance > range then
				self:hideGui()
				responseNum = 0
				break
			end
			task.wait()
		end
	end)
end

function DialogModule:showGui()
	turnProximityPromptsOn(false)

	self.animNameText:Play()
	self.animNameStroke:Play()

	self.animDialogText:Cancel()
	self.animDialogStroke:Cancel()

	self.npcGui.dialog.TextTransparency = 0
	self.npcGui.dialog.UIStroke.Transparency = 0

	coroutine.wrap(function()
		task.wait(0.3)
		if self.npcGui.name.TextTransparency ~= 1 then
			return
		end
		self.npcGui.name.Visible = false
	end)()
end

function DialogModule:hideGui(exitQuip, notActuallyAnExitQuip)
	self.active = false
	self.talking = true
	notActuallyAnExitQuip = notActuallyAnExitQuip or false
	turnProximityPromptsOn(not notActuallyAnExitQuip)

	self.talking = false

	local currentCamera = game.Workspace.CurrentCamera
	if currentCamera then
		tweenService:Create(
			currentCamera,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = notActuallyAnExitQuip and 65 or 70 }
		):Play()
	end

	local responsesUi = getDialogResponsesUI()
	if responsesUi then
		for _, option in responsesUi:GetChildren() do
			if option:IsA("GuiButton") then
				option.Visible = false
				option.Size = UDim2.new(1, 0, 1, 0)
			end
		end
	end

	local dialogObject = self.npcGui.dialog
	if exitQuip then
		dialogObject.TextTransparency = 0
		dialogObject.UIStroke.Transparency = 0
		self.npcGui.name.TextTransparency = 1
		self.npcGui.name.UIStroke.Transparency = 1

		local currenttext = ""
		dialogObject.Text = ""
		dialogObject.Visible = true
		local skip = false
		local arrow = 0
		for _, letter in string.split(exitQuip, "") do
			if dialogObject.Text ~= currenttext and skip == 0 then
				warn("other dialog happening")
				break
			end
			currenttext = currenttext .. letter
			if letter == "<" then
				skip = true
			end
			if letter == ">" then
				skip = false
				arrow += 1
				continue
			end
			if arrow == 2 then
				arrow = 0
			end
			if skip then
				continue
			end
			dialogObject.Text = currenttext .. (arrow == 1 and "</font>" or "")
			TICK_SOUND:Play()
			task.wait(0.02)
		end

		dialogObject.Text = exitQuip
		if notActuallyAnExitQuip then
			return
		end
	end

	task.spawn(function()
		if exitQuip then
			wait(2)
			if dialogObject.Text ~= exitQuip then
				return
			end
		end

		if self.npcGui.name.TextTransparency ~= 1 then
			self.animNameText:Cancel()
			self.animNameStroke:Cancel()
		end
		self.npcGui.name.TextTransparency = 0
		self.npcGui.name.UIStroke.Transparency = 0
		self.npcGui.name.Visible = true

		self.animDialogText:Play()
		self.animDialogStroke:Play()
		turnProximityPromptsOn(true)
	end)
end

function DialogModule:nextOption()
	self.dialogOption += 1
	if #self.dialogs < self.dialogOption then
		warn("No next dialog option for, " .. self.npcName)
		self.dialogOption -= 1
	end
	return self.dialogOption
end

function turnProximityPromptsOn(yes)
	for _, prompt in collectionService:GetTagged("NPCprompt") do
		if prompt:IsA("ProximityPrompt") then
			prompt.Enabled = yes
		end
	end
end

return DialogModule
