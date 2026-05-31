-- DialogModule.lua
local DialogModule = {}
DialogModule.__index = DialogModule

local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")
local collectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReactNpcDialogService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReactNpcDialogService"))

local TICK_SOUND = script.sounds.tick
local turnProximityPromptsOn
local DEFAULT_IDLE_STUDS_OFFSET = Vector3.new(0, 6, 0)
local DEFAULT_TALKING_STUDS_OFFSET = Vector3.new(0, 6, 0)
local DEFAULT_IDLE_BOB_AMPLITUDE = 1 / 6

local function getVector3Attribute(instance, attributeName, fallback)
	local value = instance:GetAttribute(attributeName)
	return if typeof(value) == "Vector3" then value else fallback
end

local function getNumberAttribute(instance, attributeName, fallback)
	local value = tonumber(instance:GetAttribute(attributeName))
	if value == nil then
		return fallback
	end
	return value
end

function DialogModule.new(npcName, npc, prompt, animation)
	local self = setmetatable({}, DialogModule)
	self.npcName = npcName
	self.npc = npc
	self.dialogs = {}
	self.responses = {}
	self.dialogOption = 1
	self.npcGui = self.npc.PrimaryPart:WaitForChild("gui")
	self.idleStudsOffset = getVector3Attribute(self.npcGui, "DialogIdleStudsOffset", DEFAULT_IDLE_STUDS_OFFSET)
	self.talkingStudsOffset = getVector3Attribute(
		self.npcGui,
		"DialogTalkingStudsOffset",
		DEFAULT_TALKING_STUDS_OFFSET
	)
	self.idleBobAmplitude = getNumberAttribute(self.npcGui, "DialogIdleBobAmplitude", DEFAULT_IDLE_BOB_AMPLITUDE)
	self.suppressNameLabel = self.npcGui:GetAttribute("DialogSuppressNameLabel") == true
	self.active = false
	self.talking = false
	self.prompt = prompt

	local eventSignal = Instance.new("BindableEvent")
	self.responded = eventSignal.Event
	self.fireResponded = eventSignal

	self.animNameText = tweenService:Create(self.npcGui.name, TweenInfo.new(0.3), { TextTransparency = 1 })
	self.animNameStroke = tweenService:Create(self.npcGui.name.UIStroke, TweenInfo.new(0.3), { Transparency = 1 })
	self.animDialogText = tweenService:Create(self.npcGui.dialog, TweenInfo.new(0.3), { TextTransparency = 1 })
	self.animDialogStroke = tweenService:Create(self.npcGui.dialog.UIStroke, TweenInfo.new(0.3), { Transparency = 1 })

	if self.suppressNameLabel then
		self.npcGui.name.TextTransparency = 1
		self.npcGui.name.UIStroke.Transparency = 1
		self.npcGui.name.Visible = false
	end

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
			self.npcGui.StudsOffset = self.talkingStudsOffset
		else
			self.npcGui.StudsOffset = self.idleStudsOffset
				+ Vector3.new(0, math.sin(frameCount / 25) * self.idleBobAmplitude, 0)
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

		self.active = true
		ReactNpcDialogService.Open({
			title = self.npcName,
			message = dialog.text,
			responses = dialog.responses,
			onRespond = function(responseNum)
				if not self.active then
					return
				end
				self.active = false
				self.fireResponded:Fire(responseNum, dialogNum)
				TICK_SOUND:Play()
			end,
		})

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
				break
			end
			task.wait()
		end
	end)
end

function DialogModule:showGui()
	turnProximityPromptsOn(false)

	if self.suppressNameLabel then
		self.animNameText:Cancel()
		self.animNameStroke:Cancel()
		self.npcGui.name.TextTransparency = 1
		self.npcGui.name.UIStroke.Transparency = 1
		self.npcGui.name.Visible = false
	else
		self.animNameText:Play()
		self.animNameStroke:Play()
	end

	self.animDialogText:Cancel()
	self.animDialogStroke:Cancel()

	self.npcGui.dialog.TextTransparency = 0
	self.npcGui.dialog.UIStroke.Transparency = 0

	if not self.suppressNameLabel then
		coroutine.wrap(function()
			task.wait(0.3)
			if self.npcGui.name.TextTransparency ~= 1 then
				return
			end
			self.npcGui.name.Visible = false
		end)()
	end
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

	ReactNpcDialogService.Close()

	local dialogObject = self.npcGui.dialog
	if exitQuip then
		dialogObject.TextTransparency = 0
		dialogObject.UIStroke.Transparency = 0
		self.npcGui.name.TextTransparency = 1
		self.npcGui.name.UIStroke.Transparency = 1
		if self.suppressNameLabel then
			self.npcGui.name.Visible = false
		end

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

		if self.suppressNameLabel then
			self.animNameText:Cancel()
			self.animNameStroke:Cancel()
			self.npcGui.name.TextTransparency = 1
			self.npcGui.name.UIStroke.Transparency = 1
			self.npcGui.name.Visible = false
		else
			if self.npcGui.name.TextTransparency ~= 1 then
				self.animNameText:Cancel()
				self.animNameStroke:Cancel()
			end
			self.npcGui.name.TextTransparency = 0
			self.npcGui.name.UIStroke.Transparency = 0
			self.npcGui.name.Visible = true
		end

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

turnProximityPromptsOn = function(yes)
	for _, prompt in collectionService:GetTagged("NPCprompt") do
		if prompt:IsA("ProximityPrompt") then
			prompt.Enabled = yes
		end
	end
end

return DialogModule
