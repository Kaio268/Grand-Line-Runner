local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ADMIN_USER_IDS = {
	1103783585,
	2442286217,
	780333260,
}

local adminSet = {}
for _, id in ipairs(ADMIN_USER_IDS) do
	adminSet[id] = true
end

local player = Players.LocalPlayer
local isAdmin = adminSet[player.UserId] == true

local function safeWait(parent, name)
	local obj = parent:WaitForChild(name, 15)
	if not obj then
		error(("Brak %s w %s"):format(name, parent:GetFullName()))
	end
	return obj
end

local requestEvent = safeWait(ReplicatedStorage, "AdminAnnouncementRequest")
local broadcastEvent = safeWait(ReplicatedStorage, "AdminAnnouncementBroadcast")
local luckRequestEvent = safeWait(ReplicatedStorage, "AdminLuckRequest")
local luckAppliedEvent = safeWait(ReplicatedStorage, "AdminLuckApplied")
local mainEventRequestEvent = safeWait(ReplicatedStorage, "AdminMainEventRequest")
local mainEventAppliedEvent = safeWait(ReplicatedStorage, "AdminMainEventApplied")

local playerGui = safeWait(player, "PlayerGui")
local framesFolder = safeWait(playerGui, "Frames")
local hud = safeWait(playerGui, "HUD")
local adminInfo = safeWait(hud, "AdminInfo")
local template = safeWait(adminInfo, "AnnTemplate")

template.Visible = false

local controller
do
	local openUi = playerGui:FindFirstChild("OpenUI")
	local openModule = openUi and openUi:FindFirstChild("Open_UI")
	if openModule then
		local ok, mod = pcall(require, openModule)
		if ok then
			controller = mod
		end
	end
end

local adminPanel = framesFolder:FindFirstChild("AdminPanel")
local selectedLuckValue = nil
local selectedMainEventName = nil

local function setSelectedByDescendants(buttons, chosen)
	for _, b in ipairs(buttons) do
		for _, d in ipairs(b:GetDescendants()) do
			if d.Name == "SELECTED" then
				if d:IsA("GuiObject") then
					d.Visible = false
				end
			end
		end
	end
	for _, d in ipairs(chosen:GetDescendants()) do
		if d.Name == "SELECTED" then
			if d:IsA("GuiObject") then
				d.Visible = true
			end
		end
	end
end

local function pulseButton(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = btn
	end
	scale.Scale = 1
	TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.12 }):Play()
	task.delay(0.12, function()
		if scale and scale.Parent then
			TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
end

if adminPanel and adminPanel:IsA("Frame") then
	if not isAdmin then
		adminPanel.Visible = false
	else
		local events = safeWait(adminPanel, "Events")

		local announcements = safeWait(events, "Announcements")
		local msgBox = safeWait(announcements, "TextBox")
		local timeBox = safeWait(announcements, "time")
		local sendBtn = safeWait(events, "SendAnnouncement")

		local luckFrame = safeWait(events, "Luck")
		local luckButtonsFolder = safeWait(luckFrame, "Buttons")
		local luckTimeBox = safeWait(luckFrame, "Time")
		local startLuckBtn = safeWait(events, "Startluck")

		local mainEventsFrame = safeWait(events, "MainEvents")
		local mainScroll = safeWait(mainEventsFrame, "ScrollingFrame")
		local mainTimeBox = safeWait(mainEventsFrame, "Time")
		local startEventBtn = safeWait(events, "StartEvent")

		local luckButtons = {}
		for _, b in ipairs(luckButtonsFolder:GetChildren()) do
			if b:IsA("GuiButton") then
				table.insert(luckButtons, b)
				b.Activated:Connect(function()
					local v = tonumber(tostring(b.Name):match("%d+"))
					if not v then return end
					selectedLuckValue = v
					setSelectedByDescendants(luckButtons, b)
					pulseButton(b)
				end)
			end
		end

		selectedLuckValue = nil
		if #luckButtons > 0 then
			for _, b in ipairs(luckButtons) do
				local v = tonumber(tostring(b.Name):match("%d+"))
				if v then
					selectedLuckValue = v
					setSelectedByDescendants(luckButtons, b)
					break
				end
			end
		end

		local mainButtons = {}
		for _, d in ipairs(mainScroll:GetDescendants()) do
			if d:IsA("TextButton") then
				table.insert(mainButtons, d)
				d.Activated:Connect(function()
					selectedMainEventName = tostring(d.Name)
					setSelectedByDescendants(mainButtons, d)
					pulseButton(d)
				end)
			end
		end

		selectedMainEventName = nil
		if #mainButtons > 0 then
			selectedMainEventName = tostring(mainButtons[1].Name)
			setSelectedByDescendants(mainButtons, mainButtons[1])
		end

		local cooldown = false

		local function send()
			if cooldown then return end

			local msg = tostring(msgBox.Text or "")
			msg = msg:gsub("\r", ""):gsub("\n", " ")
			msg = msg:match("^%s*(.-)%s*$") or ""
			if msg == "" then return end
			msg = msg:sub(1, 200)

			local duration = tonumber(timeBox.Text) or 10
			duration = math.clamp(duration, 2, 30)

			cooldown = true
			requestEvent:FireServer(msg, duration)
			task.delay(0.35, function()
				cooldown = false
			end)
		end

		if sendBtn:IsA("GuiButton") then
			sendBtn.Activated:Connect(send)
		end

		if startLuckBtn:IsA("GuiButton") then
			startLuckBtn.Activated:Connect(function()
				if not selectedLuckValue then return end
				local t = tonumber(luckTimeBox.Text) or 10
				t = math.clamp(math.floor(t), 1, 86400)
				luckRequestEvent:FireServer(selectedLuckValue, t)
			end)
		end

		if startEventBtn:IsA("GuiButton") then
			startEventBtn.Activated:Connect(function()
				if not selectedMainEventName then return end
				local t = tonumber(mainTimeBox.Text) or 10
				t = math.clamp(math.floor(t), 1, 86400)
				mainEventRequestEvent:FireServer(selectedMainEventName, t)
			end)
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.LeftAlt then return end
	if not isAdmin then return end

	local panel = framesFolder:FindFirstChild("AdminPanel")
	if not panel or not panel:IsA("Frame") then return end

	if controller and controller.ToggleFrame then
		controller:ToggleFrame(panel)
	else
		panel.Visible = not panel.Visible
	end
end)

local function makeParticle(layer: GuiObject, worldPos: Vector2)
	local p = Instance.new("Frame")
	p.BorderSizePixel = 0
	p.BackgroundColor3 = Color3.fromHSV(math.random(), 0.85, 1)
	p.BackgroundTransparency = 0
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Size = UDim2.fromOffset(math.random(3, 6), math.random(3, 6))
	p.Position = UDim2.fromOffset(worldPos.X - layer.AbsolutePosition.X, worldPos.Y - layer.AbsolutePosition.Y)
	p.Rotation = math.random(-40, 40)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = p

	p.Parent = layer

	local dx = math.random(-18, 18)
	local dy = math.random(-32, -10)

	local t = TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = p.Position + UDim2.fromOffset(dx, dy),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		Rotation = p.Rotation + math.random(-30, 30)
	})

	t:Play()
	t.Completed:Connect(function()
		p:Destroy()
	end)
end

local function getTextEndWorldPos(lbl: TextLabel)
	local tb = lbl.TextBounds
	local startX = lbl.AbsolutePosition.X
	if lbl.TextXAlignment == Enum.TextXAlignment.Center then
		startX += (lbl.AbsoluteSize.X - tb.X) * 0.5
	elseif lbl.TextXAlignment == Enum.TextXAlignment.Right then
		startX += (lbl.AbsoluteSize.X - tb.X)
	end
	local x = startX + tb.X
	local y = lbl.AbsolutePosition.Y + lbl.AbsoluteSize.Y * 0.62
	return Vector2.new(x, y)
end

local function typewrite(textLabel: TextLabel, shadowLabel: TextLabel, fullText: string, layer: GuiObject)
	local origPos = textLabel.Position
	local origShadow = shadowLabel.Position

	textLabel.Text = ""
	shadowLabel.Text = ""

	for i = 1, #fullText do
		local sub = fullText:sub(1, i)
		textLabel.Text = sub
		shadowLabel.Text = sub

		RunService.RenderStepped:Wait()

		local jitter = UDim2.fromOffset(math.random(-2, 2), math.random(-1, 1))
		textLabel.Position = origPos + jitter
		shadowLabel.Position = origShadow + jitter

		makeParticle(layer, getTextEndWorldPos(textLabel))

		task.wait(0.018 + math.random() * 0.012)
	end

	textLabel.Position = origPos
	shadowLabel.Position = origShadow
end

local function showAnnouncement(payload)
	if type(payload) ~= "table" then return end

	local message = tostring(payload.message or "")
	local duration = tonumber(payload.duration) or 10
	duration = math.clamp(duration, 2, 30)

	local adminName = tostring(payload.adminName or "Admin")
	local adminUserId = tonumber(payload.adminUserId) or 0

	local frame = template:Clone()
	frame.Visible = true
	frame.Name = "Announcement"
	frame.Parent = template.Parent
	frame.LayoutOrder = -math.floor(os.clock() * 1000)

	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
	end
	uiScale.Scale = 0

	local textLB = frame:WaitForChild("TextLB")
	local shadow = textLB:WaitForChild("Shadow")
	local pfp = frame:WaitForChild("PFP")

	textLB.TextTransparency = 0
	shadow.TextTransparency = 0
	pfp.ImageTransparency = 1

	local particleLayer = frame:FindFirstChild("ParticleLayer")
	if not particleLayer then
		particleLayer = Instance.new("Frame")
		particleLayer.Name = "ParticleLayer"
		particleLayer.BackgroundTransparency = 1
		particleLayer.BorderSizePixel = 0
		particleLayer.Size = UDim2.fromScale(1, 1)
		particleLayer.Position = UDim2.fromScale(0, 0)
		particleLayer.ZIndex = 9999
		particleLayer.ClipsDescendants = false
		particleLayer.Parent = frame
	end

	pfp.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(adminUserId)

	TweenService:Create(uiScale, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(pfp, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 0 }):Play()

	local fullText = adminName .. " : " .. message

	task.spawn(function()
		typewrite(textLB, shadow, fullText, particleLayer)
		task.wait(duration)

		local out1 = TweenService:Create(uiScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		local out2 = TweenService:Create(textLB, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		local out3 = TweenService:Create(shadow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		local out4 = TweenService:Create(pfp, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { ImageTransparency = 1 })

		out1:Play()
		out2:Play()
		out3:Play()
		out4:Play()

		out1.Completed:Wait()
		frame:Destroy()
	end)
end

broadcastEvent.OnClientEvent:Connect(showAnnouncement)

luckAppliedEvent.OnClientEvent:Connect(function()
end)

mainEventAppliedEvent.OnClientEvent:Connect(function()
end)
