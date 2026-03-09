-- DialogModule.lua
local DialogModule = {}
DialogModule.__index = DialogModule

local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local collectionService = game:GetService("CollectionService")

local TICK_SOUND = script.sounds.tick
local DIALOG_RESPONSES_UI = game.Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("dialog"):WaitForChild("dialogResponses")

-- Ustawienia animacji
local SHOW_TWEEN = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TEXT_TWEEN  = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local LIST_HEIGHT_SCALE = 0.35 -- wysokość elementu na liście (poza hoverem)

-- Constructor
function DialogModule.new(npcName, npc, prompt, animation)
	local self = setmetatable({}, DialogModule)
	self.npcName = npcName
	self.npc = npc
	self.dialogs = {} -- Array to store dialog options
	self.responses = {} -- Array to store response options
	self.dialogOption = 1
	self.npcGui = self.npc.PrimaryPart:WaitForChild("gui")
	self.active = false
	self.talking = false
	self.prompt = prompt

	-- Przygotuj 9 slotów odpowiedzi na bazie template
	local template = DIALOG_RESPONSES_UI:FindFirstChild("template")
	if template then
		for i = 1, 9 do
			local newResponseButton = template:Clone()
			newResponseButton.Parent = DIALOG_RESPONSES_UI
			newResponseButton.Name = tostring(i)
			newResponseButton.Visible = false
			-- Szablon ma mieć pełny rozmiar (1,0,1,0), ale elementy startują niższe
			newResponseButton.Size = UDim2.new(1, 0, 1, 0)
		end
		template:Destroy()
	end

	-- Sygnał zwrotu odpowiedzi
	local eventSignal = Instance.new("BindableEvent")
	self.responded = eventSignal.Event -- Expose the event to connect to
	self.fireResponded = eventSignal -- Keep a reference to the BindableEvent

	-- tween variables
	self.animNameText = tweenService:Create(self.npcGui.name, TweenInfo.new(.3), { TextTransparency = 1 })
	self.animNameStroke = tweenService:Create(self.npcGui.name.UIStroke, TweenInfo.new(.3), { Transparency = 1 })
	self.animDialogText = tweenService:Create(self.npcGui.dialog, TweenInfo.new(.3), { TextTransparency = 1 })
	self.animDialogStroke = tweenService:Create(self.npcGui.dialog.UIStroke, TweenInfo.new(.3), { Transparency = 1 })

	-- animate (opcjonalna animacja NPC)
	if animation ~= nil then
		local newAnimation = Instance.new("Animation")
		newAnimation.AnimationId = animation
		local newAnimLoaded = npc:WaitForChild("Humanoid"):LoadAnimation(newAnimation)
		newAnimLoaded:Play()
	end

	-- Connections
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
			if self.talking then return end
			self.npcGui.AlwaysOnTop = false
		end)
	end

	self.connections = { heartbeatConnection, shownConnection, hiddenConnection }

	return self
end

-- Add dialog to the NPC
function DialogModule:addDialog(dialogText, responseOptions)
	table.insert(self.dialogs, { text = dialogText, responses = responseOptions })
end

-- Sort dialogs alphabetically or by custom function
function DialogModule:sortDialogs(sortFunc)
	table.sort(self.dialogs, sortFunc or function(a, b) return a.text < b.text end)
end

-- Display the dialog when proximity prompt is triggered
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

	tweenService:Create(
		workspace.CurrentCamera,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = 65 }
	):Play()

	task.spawn(function()
		self.talking = true

		-- NPC dialog (zostawiam jak było, ale bez ingerencji w RichText tutaj)
		local dialogObject = self.npcGui.dialog
		dialogObject.Visible = true
		dialogObject.Text = ""
		local currenttext = ""
		local skip = false
		local arrow = 0

		for _, letter in string.split(dialog.text, "") do
			currenttext = currenttext .. letter
			if letter == "<" then skip = true end
			if letter == ">" then skip = false arrow += 1 continue end
			if arrow == 2 then arrow = 0 end
			if skip then continue end
			dialogObject.Text = currenttext .. (arrow == 1 and "</font>" or "")
			TICK_SOUND:Play()
			task.wait(0.02)
		end

		dialogObject.Text = dialog.text
		self.talking = false

		-- keybindy 1-9
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

		local uiResponses = DIALOG_RESPONSES_UI
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

			-- Twoje sloty z template:
			local slot1 = option:FindFirstChild("Slot")
			local slot2 = option:FindFirstChild("Slot"):FindFirstChild(`2`)

			-- tekst odpowiedzi (u Ciebie było option.text)
			local textLabel = option:FindFirstChild("text") or option:FindFirstChild("Text") or option:FindFirstChild("Response")

			-- Ustawienia: tylko zwykły tekst
			setPlainText(slot1, tostring(i))
			setPlainText(slot2, tostring(i))
			setPlainText(textLabel, tostring(response))

			-- start: niższa wysokość listy
			option.Size = UDim2.new(1, 0, 1, 0)
			option.Visible = true

			-- pokaż (możesz dać animację z 0 -> LIST_HEIGHT_SCALE)
			option.Size = UDim2.new(1, 0, 0, 0)
			tweenService:Create(option, SHOW_TWEEN, { Size = UDim2.new(1, 0, 1, 0) }):Play()

			-- hover: powiększ do pełnej wysokości
			local enterCon = option.MouseEnter:Connect(function()
				tweenService:Create(option, HOVER_TWEEN, { Size = UDim2.new(1, 0, 1, 0) }):Play()
			end)

			local leaveCon = option.MouseLeave:Connect(function()
				tweenService:Create(option, HOVER_TWEEN, { Size = UDim2.new(1, 0, 1, 0) }):Play()
			end)

			local chooseCon = option.MouseButton1Down:Connect(function()
				if not self.active then return end
				self.active = false
				responseNum = i
				self.fireResponded:Fire(i, dialogNum)
				TICK_SOUND:Play()
			end)

			local numberpressCon = userInputService.InputBegan:Connect(function(input, gameProcessed)
				if gameProcessed then return end
				if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

				local numberinput = table.find(keyboardInputs, input.KeyCode)
				if numberinput ~= nil and numberinput == i then
					if not self.active then return end
					self.active = false
					responseNum = i
					self.fireResponded:Fire(i, dialogNum)
					TICK_SOUND:Play()
				end
			end)

			coroutine.wrap(function()
				repeat task.wait() until responseNum ~= nil
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
			if char == nil or not char.PrimaryPart then break end
			if not self.npc or not self.npc:FindFirstChild("UpperTorso") then break end

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
		if self.npcGui.name.TextTransparency ~= 1 then return end -- check if already chose an option
		self.npcGui.name.Visible = false
	end)()
end

function DialogModule:hideGui(exitQuip, notActuallyAnExitQuip)
	self.active = false
	self.talking = true
	notActuallyAnExitQuip = notActuallyAnExitQuip or false
	turnProximityPromptsOn(not notActuallyAnExitQuip)

	self.talking = false

	if notActuallyAnExitQuip then
		tweenService:Create(
			game.Workspace.CurrentCamera,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = 65 }
		):Play()
	else
		tweenService:Create(
			game.Workspace.CurrentCamera,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = 70 }
		):Play()
	end

	-- hide player response options
	for _, option in DIALOG_RESPONSES_UI:GetChildren() do
		if option:IsA("GuiButton") then
			option.Visible = false
			-- Zresetuj wysokość do listy na wszelki wypadek
			option.Size = UDim2.new(1, 0, 1, 0)
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
			if dialogObject.Text ~= currenttext and skip == 0 then warn("other dialog happening") break end
			currenttext = currenttext .. letter
			if letter == "<" then skip = true end
			if letter == ">" then skip = false arrow += 1 continue end
			if arrow == 2 then arrow = 0 end
			if skip then continue end
			dialogObject.Text = currenttext .. (arrow == 1 and "</font>" or "")
			TICK_SOUND:Play()
			task.wait(0.02)
		end

		dialogObject.Text = exitQuip
		if notActuallyAnExitQuip then return end
	end

	task.spawn(function()
		if exitQuip then
			wait(2)
			if dialogObject.Text ~= exitQuip then return end
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
