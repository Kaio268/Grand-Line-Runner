local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RNG = Random.new()

local ChestOpenResultFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestOpenResultFormatter"))
local DevilFruitAssets = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Assets")
)

local Colors = {
	Color3.fromRGB(0, 34, 255),
	Color3.fromRGB(170, 255, 0),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(0, 255, 170),
	Color3.fromRGB(255, 170, 0),
	Color3.fromRGB(255, 0, 255),
	Color3.fromRGB(255, 0, 0),
	Color3.fromRGB(255, 255, 0)
}

local PopUpModule = {}
PopUpModule.activeReward = nil

local POPUP_TWEEN_IN_TIME = 0.5
local POPUP_TWEEN_OUT_TIME = 0.25
local REWARD_TWEEN_IN_TIME = 0.5
local REWARD_DISPLAY_TIME = 1
local REWARD_TWEEN_OUT_TIME = 0.25
local REWARD_ROTATION_SPEED = 60
local NOTIFY_TWEEN_IN_TIME = 0.5
local NOTIFY_DISPLAY_TIME = 2
local NOTIFY_TWEEN_OUT_TIME = 0.25

local EASING_STYLE_IN = Enum.EasingStyle.Back
local EASING_DIRECTION_IN = Enum.EasingDirection.Out
local EASING_STYLE_OUT = Enum.EasingStyle.Quad
local EASING_DIRECTION_OUT = Enum.EasingDirection.In

local activePopups = {}

local PopUpEvent = ReplicatedStorage:FindFirstChild("PopUpEvent")
if not PopUpEvent then
	PopUpEvent = Instance.new("RemoteEvent")
	PopUpEvent.Name = "PopUpEvent"
	PopUpEvent.Parent = ReplicatedStorage
end

local function playSound(name)
	local soundTemplate = SoundService:FindFirstChild(name)
	if soundTemplate then
		local soundClone = soundTemplate:Clone()
		soundClone.Parent = SoundService
		soundClone:Play()
		soundClone.Ended:Connect(function() soundClone:Destroy() end)
	end
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	for baseText, data in pairs(activePopups) do
		if not data.removalInProgress and now >= data.expirationTime then
			data.removalInProgress = true
			local popup = data.popup
			local uiScale = popup:FindFirstChildOfClass("UIScale")
			local tweenInfo = TweenInfo.new(0.25, EASING_STYLE_OUT, EASING_DIRECTION_OUT)
			if uiScale then
				TweenService:Create(uiScale, tweenInfo, {Scale = 0}):Play()
			end
			TweenService:Create(popup, tweenInfo, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
			data.outTween = true
			task.delay(0.25, function()
				if popup and popup.Parent then popup:Destroy() end
				activePopups[baseText] = nil
			end)
		end
	end
end)


function PopUpModule:Local_SendPopUp(text, textColor, strokeColor, duration, isError)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local animations = playerGui:WaitForChild("Animations")
	local popUpsFolder = animations:WaitForChild("PopUps")
	local template = popUpsFolder:WaitForChild("Template")

	if activePopups[text] then
			local data = activePopups[text]
			local popup = data.popup
			if data.removalInProgress then
				if data.outTween then
					data.outTween:Cancel()
				end
				popup.TextTransparency, popup.TextStrokeTransparency = 0, 0
				local uiScale = popup:FindFirstChildOfClass("UIScale")
			if uiScale then uiScale.Scale = 1 end
			data.removalInProgress = false
		end
		data.count = data.count + 1
		popup.Text = text .. (data.count > 1 and " (x" .. data.count .. ")" or "")
		popup.TextColor3, popup.TextStrokeColor3 = textColor, strokeColor
		data.expirationTime = tick() + duration
		playSound(isError and "Error" or "Success")
		return
	end

	local newPopup = template:Clone()
	newPopup.Name = "PopUp_" .. os.time() .. "_" .. math.random(1, 1000)
	newPopup.Parent = popUpsFolder
	newPopup.Visible = true
	newPopup.Text = text
	newPopup.TextColor3, newPopup.TextStrokeColor3 = textColor, strokeColor
	newPopup.TextTransparency, newPopup.TextStrokeTransparency = 0, 0
	local uiScale = newPopup:FindFirstChildOfClass("UIScale")
	if uiScale then uiScale.Scale = 0 end
	playSound(isError and "Error" or "Success")
	if uiScale then
		TweenService:Create(uiScale, TweenInfo.new(POPUP_TWEEN_IN_TIME, EASING_STYLE_IN, EASING_DIRECTION_IN), {Scale = 1}):Play()
	end

	activePopups[text] = {
		popup = newPopup,
		count = 1,
		expirationTime = tick() + duration,
		removalInProgress = false,
		outTween = nil
	}
end

function PopUpModule:Local_ShowReward(rewardTable)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local animations = playerGui:WaitForChild("Animations")
	local rewardsContainer = animations:WaitForChild("Rewards")
	local template = rewardsContainer:WaitForChild("Reward")

	-- Zmienne do zarządzania globalnym timerem usuwania
	local globalRemoveTime = 0
	local removalScheduled = false

	local function updateScale()
		local count = 0
		for _, r in ipairs(rewardsContainer:GetChildren()) do
			if r:IsA("Frame") and r.Name:match("^Reward_") then
				count = count + 1
			end
		end
		local targetScale = (count > 6 and 6 / count or 1)
		for _, r in ipairs(rewardsContainer:GetChildren()) do
			if r:IsA("Frame") and r.Name:match("^Reward_") then
				local uiScale = r:FindFirstChildOfClass("UIScale")
				if uiScale then
					TweenService:Create(uiScale, TweenInfo.new(0.25, EASING_STYLE_IN, EASING_DIRECTION_IN), {Scale = targetScale}):Play()
				end
			end
		end
	end

	-- Funkcja, która czeka do momentu globalRemoveTime, a następnie usuwa wszystkie rewardy jednocześnie
	local function scheduleRemoval()
		if not removalScheduled then
			removalScheduled = true
			coroutine.wrap(function()
				-- Czekamy aż minie wyznaczony czas (każde dodanie rewardu aktualizuje globalRemoveTime)
				while tick() < globalRemoveTime do
					task.wait(0.1)
				end
				-- Ustawiamy tween-out i usuwamy wszystkie rewardy jednocześnie
				local rewardsToRemove = {}
				for _, r in ipairs(rewardsContainer:GetChildren()) do
					if r:IsA("Frame") and r.Name:match("^Reward_") then
						table.insert(rewardsToRemove, r)
					end
				end
				for _, r in ipairs(rewardsToRemove) do
					local uiScale = r:FindFirstChildOfClass("UIScale")
					if uiScale then
						local tweenOut = TweenService:Create(uiScale, TweenInfo.new(REWARD_TWEEN_OUT_TIME, EASING_STYLE_OUT, EASING_DIRECTION_OUT), {Scale = 0})
						tweenOut:Play()
						tweenOut.Completed:Connect(function()
							r:Destroy()
							updateScale()
						end)
					else
						r:Destroy()
						updateScale()
					end
				end
				removalScheduled = false
			end)()
		end
	end

	for _, rewardData in pairs(rewardTable) do
		local newReward = template:Clone()
		newReward.Name = "Reward_" .. os.time() .. "_" .. math.random(1, 1000)
		newReward.Parent = rewardsContainer
		newReward.Visible = true

		if newReward:FindFirstChild("RewardName") then
			newReward.RewardName.Text = rewardData[1]
		end
		if newReward:FindFirstChild("Icon") then
			newReward.Icon.Image = rewardData[2]
		end

		local uiScale = newReward:FindFirstChildOfClass("UIScale")
		if uiScale then
			uiScale.Scale = 0
		end

		local sunBurst = newReward:FindFirstChild("SunBurst")
		if sunBurst then
			local lastTime = tick()
			coroutine.wrap(function()
				while newReward and newReward.Parent do
					local now = tick()
					sunBurst.Rotation = (sunBurst.Rotation + (now - lastTime) * REWARD_ROTATION_SPEED) % 360
					lastTime = now
					RunService.RenderStepped:Wait()
				end
			end)()
		end

		-- Ustalamy skalę w zależności od liczby rewardów
		local count = 0
		for _, child in ipairs(rewardsContainer:GetChildren()) do
			if child:IsA("Frame") and child.Name:match("^Reward_") then
				count = count + 1
			end
		end
		local targetScale = (count > 6 and 6 / count or 1)
		if uiScale then
			TweenService:Create(uiScale, TweenInfo.new(REWARD_TWEEN_IN_TIME, EASING_STYLE_IN, EASING_DIRECTION_IN), {Scale = targetScale}):Play()
		end

		playSound("Reward")

		-- Aktualizacja globalnego timera: przy każdym nowym rewardzie od nowa ustalamy czas wygaśnięcia
		globalRemoveTime = tick() + REWARD_TWEEN_IN_TIME + REWARD_DISPLAY_TIME
		scheduleRemoval()
		updateScale()
	end
end

local maxNotifications = 4
local notifyQueue      = {}
local activeCount      = 0
local isProcessing     = false

local function trySpawnNext()
	if isProcessing or activeCount >= maxNotifications or #notifyQueue == 0 then
		return
	end

	isProcessing = true
	local args     = table.remove(notifyQueue, 1)
	local Name     = args.Name
	local Amount   = args.Amount
	local Icon     = args.Icon
	local Duration = args.Duration

	local player       = Players.LocalPlayer
	local playerGui    = player:WaitForChild("PlayerGui")
	local animations   = playerGui:WaitForChild("Animations")
	local notifyFolder = animations:WaitForChild("Notify")
	local template     = notifyFolder:WaitForChild("Template")

	local newNotify = template:Clone()
	newNotify.Name    = "Notify_" .. os.time() .. "_" .. math.random(1, 1000)
	newNotify.Parent  = notifyFolder
	newNotify.Visible = true
	newNotify.Icon:SetAttribute("Info", Name)
	newNotify.Icon:SetAttribute("Rarity", "Common")

	if newNotify:FindFirstChild("Value") then
		newNotify.Value.Text = Name .. " (x" .. tostring(Amount) .. ")"
	end
	if newNotify:FindFirstChild("Icon") then
		newNotify.Icon.Image = Icon
	end

	local uiScale = newNotify:FindFirstChildOfClass("UIScale")
	if uiScale then
		uiScale.Scale = 0
		local tweenIn = TweenService:Create(
			uiScale,
			TweenInfo.new(NOTIFY_TWEEN_IN_TIME, EASING_STYLE_IN, EASING_DIRECTION_IN),
			{ Scale = 1 }
		)
		tweenIn:Play()
		task.delay(0.2, function()
			isProcessing = false
			trySpawnNext()
		end)
	else
		isProcessing = false
		trySpawnNext()
	end

	playSound("Notify")
	activeCount = activeCount + 1

	task.delay(Duration, function()
		if uiScale then
			local tweenOut = TweenService:Create(
				uiScale,
				TweenInfo.new(NOTIFY_TWEEN_OUT_TIME, EASING_STYLE_OUT, EASING_DIRECTION_OUT),
				{ Scale = 0 }
			)
			tweenOut:Play()
			tweenOut.Completed:Connect(function()
				newNotify:Destroy()
				activeCount = activeCount - 1
				trySpawnNext()
			end)
		else
			newNotify:Destroy()
			activeCount = activeCount - 1
			trySpawnNext()
		end
	end)
end

function PopUpModule:Local_ShowNotify(Name, Amount, Icon, Duration)
	table.insert(notifyQueue, { Name = Name, Amount = Amount, Icon = Icon, Duration = Duration })
	trySpawnNext()
end

local acknowledgeGui
local acknowledgeOverlay
local acknowledgePanel
local acknowledgeAccent
local acknowledgeTitle
local acknowledgeBody
local acknowledgeButton
local acknowledgeButtonLabel
local acknowledgeBackground
local acknowledgePreviewCard
local acknowledgePreviewViewport
local acknowledgePreviewFallback

local DEVIL_FRUIT_ACK_THEME = {
	FruitBackgroundImage = "rbxassetid://134053886107384",
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	HeaderBg = Color3.fromRGB(16, 35, 59),
	SectionBg = Color3.fromRGB(27, 46, 68),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
}

local ACK_PREVIEW_WIDTH = 220
local ACK_BODY_BOTTOM_PADDING = 62

local function ensureAckCorner(instance, radius)
	local corner = instance:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = instance
	end
	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function ensureAckStroke(instance, color, transparency, thickness)
	local stroke = instance:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = instance
	end
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	return stroke
end

local function ensureAckGradient(instance, topColor, bottomColor)
	local gradient = instance:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = instance
	end
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	})
	return gradient
end

local function bindClaimButtonStyle(button)
	local function apply(fill, text, top, bottom)
		button.BackgroundColor3 = fill
		local label = button:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.TextColor3 = text
		else
			button.TextColor3 = text
		end
		ensureAckGradient(button, top, bottom)
	end

	button.AutoButtonColor = false
	button.MouseEnter:Connect(function()
		apply(
			DEVIL_FRUIT_ACK_THEME.GoldBase,
			DEVIL_FRUIT_ACK_THEME.PrimaryBg,
			DEVIL_FRUIT_ACK_THEME.GoldHighlight,
			DEVIL_FRUIT_ACK_THEME.GoldBase
		)
	end)

	button.MouseLeave:Connect(function()
		apply(
			DEVIL_FRUIT_ACK_THEME.SectionBg,
			DEVIL_FRUIT_ACK_THEME.GoldHighlight,
			DEVIL_FRUIT_ACK_THEME.SecondaryBg,
			DEVIL_FRUIT_ACK_THEME.PrimaryBg
		)
	end)

	apply(
		DEVIL_FRUIT_ACK_THEME.SectionBg,
		DEVIL_FRUIT_ACK_THEME.GoldHighlight,
		DEVIL_FRUIT_ACK_THEME.SecondaryBg,
		DEVIL_FRUIT_ACK_THEME.PrimaryBg
	)
end

local function normalizeAcknowledgementBody(lines)
	if typeof(lines) == "string" then
		return tostring(lines)
	end

	if typeof(lines) ~= "table" then
		return ""
	end

	local formatted = {}
	for _, entry in ipairs(lines) do
		local text = tostring(entry or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if text ~= "" then
			formatted[#formatted + 1] = "• " .. text
		end
	end

	return table.concat(formatted, "\n")
end

local function clearAcknowledgePreviewViewport()
	if not acknowledgePreviewViewport then
		return
	end

	for _, child in ipairs(acknowledgePreviewViewport:GetChildren()) do
		child:Destroy()
	end
	acknowledgePreviewViewport.CurrentCamera = nil
end

local function setPreviewPartDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function getPreviewBoundingInfo(previewModel)
	if previewModel:IsA("BasePart") then
		return previewModel.CFrame, previewModel.Size
	end

	local ok, cf, size = pcall(function()
		return previewModel:GetBoundingBox()
	end)
	if ok then
		return cf, size
	end

	local part = previewModel:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.CFrame, part.Size
	end

	return CFrame.new(), Vector3.new(1, 1, 1)
end

local function showFruitPreview(fruitKey)
	if not acknowledgePreviewCard or not acknowledgePreviewViewport then
		return false
	end

	clearAcknowledgePreviewViewport()

	if typeof(fruitKey) ~= "string" or fruitKey == "" then
		acknowledgePreviewCard.Visible = false
		return false
	end

	local previewModel = DevilFruitAssets.ClonePreviewWorldModel(fruitKey)
	if not previewModel then
		if acknowledgePreviewFallback then
			acknowledgePreviewFallback.Visible = true
		end
		acknowledgePreviewCard.Visible = true
		return true
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = acknowledgePreviewViewport
	previewModel.Parent = worldModel

	pcall(function()
		if previewModel:IsA("Model") or previewModel:IsA("WorldModel") then
			previewModel:PivotTo(CFrame.Angles(math.rad(-10), math.rad(24), 0))
		elseif previewModel:IsA("BasePart") then
			previewModel.CFrame = CFrame.Angles(math.rad(-10), math.rad(24), 0)
		end
	end)

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			setPreviewPartDefaults(descendant)
		end
	end

	local boxCF, boxSize = getPreviewBoundingInfo(previewModel)
	local maxSize = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(
		boxCF.Position + Vector3.new(maxSize * 0.9, maxSize * 0.4, maxSize * 1.8),
		boxCF.Position
	)
	camera.Parent = acknowledgePreviewViewport
	acknowledgePreviewViewport.CurrentCamera = camera

	if acknowledgePreviewFallback then
		acknowledgePreviewFallback.Visible = false
	end

	acknowledgePreviewCard.Visible = true
	return true
end

local function ensureAcknowledgeGui()
	if acknowledgeGui and acknowledgeGui.Parent then
		local panel = acknowledgeGui:FindFirstChild("Panel")
		local topBar = panel and panel:FindFirstChild("TopBar")
		local content = panel and panel:FindFirstChild("Content")
		local button = content and content:FindFirstChild("Okay")
		local buttonLabel = button and button:FindFirstChild("Label")
		local previewCard = content and content:FindFirstChild("PreviewCard")
		if panel and topBar and content and button and buttonLabel and previewCard then
			return
		end

		acknowledgeGui:Destroy()
		acknowledgeGui = nil
		acknowledgeOverlay = nil
		acknowledgePanel = nil
		acknowledgeAccent = nil
		acknowledgeTitle = nil
		acknowledgeBody = nil
		acknowledgeButton = nil
		acknowledgeButtonLabel = nil
		acknowledgeBackground = nil
		acknowledgePreviewCard = nil
		acknowledgePreviewViewport = nil
		acknowledgePreviewFallback = nil
	end

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	acknowledgeGui = Instance.new("ScreenGui")
	acknowledgeGui.Name = "PersistentPopupPrompt"
	acknowledgeGui.ResetOnSpawn = false
	acknowledgeGui.IgnoreGuiInset = true
	acknowledgeGui.DisplayOrder = 75
	acknowledgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	acknowledgeGui.Enabled = false
	acknowledgeGui.Parent = playerGui

	acknowledgeOverlay = Instance.new("Frame")
	acknowledgeOverlay.Name = "Overlay"
	acknowledgeOverlay.Active = true
	acknowledgeOverlay.BackgroundColor3 = DEVIL_FRUIT_ACK_THEME.MenuOverlay
	acknowledgeOverlay.BackgroundTransparency = 0.38
	acknowledgeOverlay.BorderSizePixel = 0
	acknowledgeOverlay.Size = UDim2.fromScale(1, 1)
	acknowledgeOverlay.ZIndex = 74
	acknowledgeOverlay.Parent = acknowledgeGui

	acknowledgePanel = Instance.new("Frame")
	acknowledgePanel.Name = "Panel"
	acknowledgePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	acknowledgePanel.Position = UDim2.fromScale(0.5, 0.5)
	acknowledgePanel.Size = UDim2.fromOffset(620, 370)
	acknowledgePanel.BackgroundColor3 = DEVIL_FRUIT_ACK_THEME.PrimaryBg
	acknowledgePanel.BackgroundTransparency = 1
	acknowledgePanel.BorderSizePixel = 0
	acknowledgePanel.ClipsDescendants = true
	acknowledgePanel.ZIndex = 80
	acknowledgePanel.Parent = acknowledgeGui

	ensureAckCorner(acknowledgePanel, 16)
	local panelStroke = ensureAckStroke(acknowledgePanel, DEVIL_FRUIT_ACK_THEME.GoldHighlight, 0, 2.2)
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	acknowledgeBackground = Instance.new("ImageLabel")
	acknowledgeBackground.Name = "BackgroundImage"
	acknowledgeBackground.BackgroundTransparency = 1
	acknowledgeBackground.BorderSizePixel = 0
	acknowledgeBackground.Image = DEVIL_FRUIT_ACK_THEME.FruitBackgroundImage
	acknowledgeBackground.ScaleType = Enum.ScaleType.Stretch
	acknowledgeBackground.Size = UDim2.fromScale(1, 1)
	acknowledgeBackground.ZIndex = 79
	acknowledgeBackground.Parent = acknowledgePanel
	ensureAckCorner(acknowledgeBackground, 16)

	local panelOverlay = Instance.new("Frame")
	panelOverlay.Name = "BackgroundOverlay"
	panelOverlay.BackgroundColor3 = DEVIL_FRUIT_ACK_THEME.MenuOverlay
	panelOverlay.BackgroundTransparency = 0.45
	panelOverlay.BorderSizePixel = 0
	panelOverlay.Size = UDim2.fromScale(1, 1)
	panelOverlay.ZIndex = 79
	panelOverlay.Parent = acknowledgePanel
	ensureAckCorner(panelOverlay, 16)

	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundColor3 = DEVIL_FRUIT_ACK_THEME.HeaderBg
	topBar.BackgroundTransparency = 0.24
	topBar.BorderSizePixel = 0
	topBar.Position = UDim2.fromOffset(14, 12)
	topBar.Size = UDim2.new(1, -28, 0, 84)
	topBar.ZIndex = 81
	topBar.Parent = acknowledgePanel
	ensureAckCorner(topBar, 10)
	local topStroke = ensureAckStroke(topBar, DEVIL_FRUIT_ACK_THEME.GoldHighlight, 0, 1.5)
	topStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ensureAckGradient(topBar, DEVIL_FRUIT_ACK_THEME.SecondaryBg, DEVIL_FRUIT_ACK_THEME.PrimaryBg)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(20, 104)
	content.Size = UDim2.new(1, -40, 1, -122)
	content.ZIndex = 81
	content.Parent = acknowledgePanel

	acknowledgeAccent = Instance.new("TextLabel")
	acknowledgeAccent.Name = "Accent"
	acknowledgeAccent.BackgroundTransparency = 1
	acknowledgeAccent.Position = UDim2.fromOffset(16, 10)
	acknowledgeAccent.Size = UDim2.new(1, -32, 0, 20)
	acknowledgeAccent.Font = Enum.Font.GothamBold
	acknowledgeAccent.Text = "UPGRADE COMPLETE"
	acknowledgeAccent.TextColor3 = DEVIL_FRUIT_ACK_THEME.GoldHighlight
	acknowledgeAccent.TextSize = 14
	acknowledgeAccent.TextXAlignment = Enum.TextXAlignment.Left
	acknowledgeAccent.ZIndex = 82
	acknowledgeAccent.Parent = topBar

	acknowledgeTitle = Instance.new("TextLabel")
	acknowledgeTitle.Name = "Title"
	acknowledgeTitle.BackgroundTransparency = 1
	acknowledgeTitle.Position = UDim2.fromOffset(16, 28)
	acknowledgeTitle.Size = UDim2.new(1, -32, 0, 48)
	acknowledgeTitle.Font = Enum.Font.GothamBold
	acknowledgeTitle.Text = "Update"
	acknowledgeTitle.TextColor3 = DEVIL_FRUIT_ACK_THEME.TextMain
	acknowledgeTitle.TextSize = 24
	acknowledgeTitle.TextScaled = false
	acknowledgeTitle.TextWrapped = false
	acknowledgeTitle.TextTruncate = Enum.TextTruncate.AtEnd
	acknowledgeTitle.TextXAlignment = Enum.TextXAlignment.Left
	acknowledgeTitle.ZIndex = 82
	acknowledgeTitle.Parent = topBar

	acknowledgeBody = Instance.new("TextLabel")
	acknowledgeBody.Name = "Body"
	acknowledgeBody.BackgroundTransparency = 1
	acknowledgeBody.Position = UDim2.fromOffset(0, 0)
	acknowledgeBody.Size = UDim2.new(1, -ACK_PREVIEW_WIDTH - 16, 1, -ACK_BODY_BOTTOM_PADDING)
	acknowledgeBody.Font = Enum.Font.Gotham
	acknowledgeBody.Text = ""
	acknowledgeBody.TextColor3 = DEVIL_FRUIT_ACK_THEME.TextSecondary
	acknowledgeBody.TextSize = 18
	acknowledgeBody.TextScaled = false
	acknowledgeBody.TextWrapped = true
	acknowledgeBody.TextXAlignment = Enum.TextXAlignment.Left
	acknowledgeBody.TextYAlignment = Enum.TextYAlignment.Top
	acknowledgeBody.ZIndex = 82
	acknowledgeBody.Parent = content

	acknowledgePreviewCard = Instance.new("Frame")
	acknowledgePreviewCard.Name = "PreviewCard"
	acknowledgePreviewCard.AnchorPoint = Vector2.new(1, 0)
	acknowledgePreviewCard.Position = UDim2.fromScale(1, 0)
	acknowledgePreviewCard.Size = UDim2.new(0, ACK_PREVIEW_WIDTH, 1, -ACK_BODY_BOTTOM_PADDING)
	acknowledgePreviewCard.BackgroundColor3 = DEVIL_FRUIT_ACK_THEME.SectionBg
	acknowledgePreviewCard.BackgroundTransparency = 0.25
	acknowledgePreviewCard.BorderSizePixel = 0
	acknowledgePreviewCard.Visible = false
	acknowledgePreviewCard.ZIndex = 82
	acknowledgePreviewCard.Parent = content
	ensureAckCorner(acknowledgePreviewCard, 12)
	local previewStroke = ensureAckStroke(acknowledgePreviewCard, DEVIL_FRUIT_ACK_THEME.GoldHighlight, 0, 1.25)
	previewStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	acknowledgePreviewViewport = Instance.new("ViewportFrame")
	acknowledgePreviewViewport.Name = "Viewport"
	acknowledgePreviewViewport.BackgroundTransparency = 1
	acknowledgePreviewViewport.BorderSizePixel = 0
	acknowledgePreviewViewport.Position = UDim2.fromOffset(8, 8)
	acknowledgePreviewViewport.Size = UDim2.new(1, -16, 1, -16)
	acknowledgePreviewViewport.Ambient = Color3.fromRGB(206, 196, 186)
	acknowledgePreviewViewport.LightColor = Color3.fromRGB(255, 252, 246)
	acknowledgePreviewViewport.LightDirection = Vector3.new(-1, -1, -1)
	acknowledgePreviewViewport.ZIndex = 83
	acknowledgePreviewViewport.Parent = acknowledgePreviewCard

	acknowledgePreviewFallback = Instance.new("TextLabel")
	acknowledgePreviewFallback.Name = "Fallback"
	acknowledgePreviewFallback.BackgroundTransparency = 1
	acknowledgePreviewFallback.Size = UDim2.fromScale(1, 1)
	acknowledgePreviewFallback.Font = Enum.Font.Gotham
	acknowledgePreviewFallback.Text = "Preview unavailable"
	acknowledgePreviewFallback.TextColor3 = DEVIL_FRUIT_ACK_THEME.TextSecondary
	acknowledgePreviewFallback.TextSize = 14
	acknowledgePreviewFallback.TextWrapped = true
	acknowledgePreviewFallback.ZIndex = 84
	acknowledgePreviewFallback.Parent = acknowledgePreviewCard

	acknowledgeButton = Instance.new("TextButton")
	acknowledgeButton.Name = "Okay"
	acknowledgeButton.AnchorPoint = Vector2.new(0.5, 1)
	acknowledgeButton.Position = UDim2.new(0.5, 0, 1, -2)
	acknowledgeButton.Size = UDim2.fromOffset(190, 46)
	acknowledgeButton.BackgroundColor3 = DEVIL_FRUIT_ACK_THEME.SectionBg
	acknowledgeButton.BorderSizePixel = 0
	acknowledgeButton.Font = Enum.Font.GothamBold
	acknowledgeButton.Text = ""
	acknowledgeButton.TextColor3 = DEVIL_FRUIT_ACK_THEME.GoldHighlight
	acknowledgeButton.TextSize = 18
	acknowledgeButton.ZIndex = 82
	acknowledgeButton.Parent = content

	acknowledgeButtonLabel = Instance.new("TextLabel")
	acknowledgeButtonLabel.Name = "Label"
	acknowledgeButtonLabel.BackgroundTransparency = 1
	acknowledgeButtonLabel.Size = UDim2.fromScale(1, 1)
	acknowledgeButtonLabel.Font = Enum.Font.GothamBold
	acknowledgeButtonLabel.Text = "Close"
	acknowledgeButtonLabel.TextColor3 = DEVIL_FRUIT_ACK_THEME.GoldHighlight
	acknowledgeButtonLabel.TextSize = 28
	acknowledgeButtonLabel.ZIndex = 84
	acknowledgeButtonLabel.Parent = acknowledgeButton

	ensureAckCorner(acknowledgeButton, 12)
	local buttonStroke = ensureAckStroke(acknowledgeButton, DEVIL_FRUIT_ACK_THEME.GoldHighlight, 0, 1.4)
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bindClaimButtonStyle(acknowledgeButton)

	acknowledgeButton.MouseButton1Click:Connect(function()
		if acknowledgeGui then
			acknowledgeGui.Enabled = false
		end
	end)
end

function PopUpModule:Local_ShowAcknowledgement(options)
	options = options or {}
	ensureAcknowledgeGui()

	local title = tostring(options.Title or options.title or "Notice")
	local accentText = tostring(options.AccentText or options.accentText or "UPDATE")
	local buttonText = tostring(options.ButtonText or options.buttonText or "Okay")
	local bodyMode = tostring(options.BodyMode or options.bodyMode or "")
	local bodyRawText = options.BodyRawText or options.bodyRawText
	local bodyText = if typeof(bodyRawText) == "string" and bodyRawText ~= ""
		then tostring(bodyRawText)
		else normalizeAcknowledgementBody(options.Lines or options.lines or options.Body or options.body)
	local previewFruitKey = options.PreviewFruitKey or options.previewFruitKey

	if bodyText == "" then
		bodyText = "No details available."
	end

	acknowledgeAccent.Text = accentText
	acknowledgeAccent.TextColor3 = options.AccentColor or DEVIL_FRUIT_ACK_THEME.GoldHighlight
	acknowledgeTitle.Text = title
	acknowledgeTitle.TextColor3 = options.TitleColor or DEVIL_FRUIT_ACK_THEME.TextMain
	acknowledgeBody.Text = bodyText
	acknowledgeBody.TextColor3 = options.BodyColor or DEVIL_FRUIT_ACK_THEME.TextSecondary
	if bodyMode == "FruitFocus" then
		acknowledgeBody.Font = Enum.Font.GothamBold
		acknowledgeBody.TextSize = 34
		acknowledgeBody.TextWrapped = true
		acknowledgeBody.TextXAlignment = Enum.TextXAlignment.Center
		acknowledgeBody.TextYAlignment = Enum.TextYAlignment.Center
	else
		acknowledgeBody.Font = Enum.Font.Gotham
		acknowledgeBody.TextSize = 18
		acknowledgeBody.TextWrapped = true
		acknowledgeBody.TextXAlignment = Enum.TextXAlignment.Left
		acknowledgeBody.TextYAlignment = Enum.TextYAlignment.Top
	end
	acknowledgeButton.Text = ""
	if acknowledgeButtonLabel then
		acknowledgeButtonLabel.Text = buttonText
		acknowledgeButtonLabel.TextColor3 = DEVIL_FRUIT_ACK_THEME.GoldHighlight
	end
	acknowledgeButton.BackgroundColor3 = DEVIL_FRUIT_ACK_THEME.SectionBg
	acknowledgeButton.TextColor3 = DEVIL_FRUIT_ACK_THEME.GoldHighlight
	if acknowledgeBackground then
		acknowledgeBackground.Image = tostring(options.BackgroundImage or DEVIL_FRUIT_ACK_THEME.FruitBackgroundImage)
	end
	local hasPreview = showFruitPreview(previewFruitKey)
	if hasPreview then
		acknowledgeBody.Size = UDim2.new(1, -ACK_PREVIEW_WIDTH - 16, 1, -ACK_BODY_BOTTOM_PADDING)
	elseif acknowledgePreviewCard then
		acknowledgePreviewCard.Visible = false
		acknowledgeBody.Size = UDim2.new(1, 0, 1, -ACK_BODY_BOTTOM_PADDING)
	end

	acknowledgeGui.Enabled = true
	playSound("Reward")
end

function PopUpModule:Local_ShowChestOpenResult(openResult)
	local acknowledgement = ChestOpenResultFormatter.BuildAcknowledgementOptions(openResult)
	self:Local_ShowAcknowledgement(acknowledgement)

	local confettiCount = ChestOpenResultFormatter.GetCelebrationCount(openResult)
	if confettiCount > 0 then
		self:Local_SpawnConfetti(confettiCount)
	end
end

local isPromptActive = false
local function playBuyAnimation(mainGui)
	local buyAnimation = mainGui:WaitForChild("BuyAnimation")
	buyAnimation.Visible = true
	buyAnimation.Transparency = 1

	local circle = buyAnimation:WaitForChild("Loading")
	circle.ImageTransparency = 1

	local tweenInfoShow = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(buyAnimation, tweenInfoShow, {Transparency = 0.5}):Play()
	TweenService:Create(circle, tweenInfoShow, {ImageTransparency = 0}):Play()

	circle.Rotation = 0
	local rotationTween = TweenService:Create(
		circle,
		TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{Rotation = 360}
	)
	rotationTween:Play()

	local moneyLabels = {}
	for _, child in ipairs(buyAnimation:GetDescendants()) do
		if child:IsA("ImageLabel") and child.Name == "Money" then
			table.insert(moneyLabels, child)
			child:SetAttribute("OriginalSize", child.Size)
			child.ImageTransparency = 1
		end
	end

	local moneyTweenActive = true
	local function startMoneyTween(label)
		if not moneyTweenActive then return end
		local orig = label:GetAttribute("OriginalSize")
		if not orig then return end

		local multiplier = math.random(105, 110) / 100
		local newSize = UDim2.new(
			orig.X.Scale * multiplier,
			orig.X.Offset * multiplier,
			orig.Y.Scale * multiplier,
			orig.Y.Offset * multiplier
		)

		local tweenBig = TweenService:Create(
			label,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = newSize, ImageTransparency = 0}
		)
		local tweenSmall = TweenService:Create(
			label,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = orig, ImageTransparency = 0}
		)

		tweenBig.Completed:Connect(function()
			tweenSmall:Play()
		end)
		tweenSmall.Completed:Connect(function()
			if moneyTweenActive then
				startMoneyTween(label)
			end
		end)

		tweenBig:Play()
	end

	for _, label in ipairs(moneyLabels) do
		startMoneyTween(label)
	end

	local function cleanup(callback)
		moneyTweenActive = false
		rotationTween:Cancel()

		local tweenHide = TweenService:Create(
			buyAnimation,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Transparency = 1}
		)
		local tweenCircleHide = TweenService:Create(
			circle,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ImageTransparency = 1}
		)

		tweenHide:Play()
		tweenCircleHide:Play()

		for _, label in ipairs(moneyLabels) do
			local orig = label:GetAttribute("OriginalSize")
			if orig then
				TweenService:Create(
					label,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{Size = orig, ImageTransparency = 1}
				):Play()
			end
		end

		tweenHide.Completed:Connect(function()
			buyAnimation.Visible = false
			callback()
		end)
	end

	return { buyAnimation = buyAnimation, cleanup = cleanup }
end

function PopUpModule:Local_PromptGamepass(player, id)
	if isPromptActive then return end
	isPromptActive = true

	local playerGui = player.PlayerGui
	local mainGui = playerGui:WaitForChild("Animations")
	local animData = playBuyAnimation(mainGui)

	playSound("Prompt")

	local connection
	connection = MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, gamePassId, wasPurchased)
		print("Event PromptGamePassPurchaseFinished fired for", plr, gamePassId, wasPurchased)
		if ((typeof(plr) == "Instance" and plr == player) or (typeof(plr) == "number" and plr == player.UserId))
			and gamePassId == id then

			if wasPurchased then
				-- Gamepass został kupiony - pokazujemy spektakularną animację!

				-- Najpierw confetti
				self:Local_SpawnConfetti(50)

				-- Pobieramy elementy GamepassShow
				local gamepassShow = mainGui:WaitForChild("GamepassShow")
				local pass = gamepassShow:WaitForChild("Pass")
				local passIcon = pass:WaitForChild("Icon")
				local passName = pass:WaitForChild("PassName")
				local sunBurst = pass:WaitForChild("SunBurst")
				local uiScale = pass:FindFirstChildOfClass("UIScale")

				-- Pobieramy informacje o gamepassie
				local gamepassInfo
				local success, err = pcall(function()
					gamepassInfo = MarketplaceService:GetProductInfo(id, Enum.InfoType.GamePass)
				end)

				if success and gamepassInfo then
					passIcon.Image = "rbxassetid://" .. gamepassInfo.IconImageAssetId
					passName.Text = "You Got " .. gamepassInfo.Name .. "!"
				else
					passName.Text = "You Got New Gamepass!"
				end

				-- Przygotowujemy elementy do animacji
				gamepassShow.Visible = true
				gamepassShow.BackgroundTransparency = 1
				pass.Visible = true
				if uiScale then
					uiScale.Scale = 0
				end
				passIcon.Rotation = 0

				-- Animacja tła GamepassShow
				local bgTween = TweenService:Create(
					gamepassShow,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{BackgroundTransparency = 0.4}
				)
				bgTween:Play()

				-- Animacja powiększania Pass z bounce effect
				if uiScale then
					local scaleTween = TweenService:Create(
						uiScale,
						TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{Scale = 1.2}
					)
					scaleTween:Play()

					-- Po chwili zmniejszamy do normalnej wielkości
					scaleTween.Completed:Connect(function()
						TweenService:Create(
							uiScale,
							TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{Scale = 1}
						):Play()
					end)
				end

				-- Rotacja ikony gamepassu (360 stopni)
				local iconRotTween = TweenService:Create(
					passIcon,
					TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Rotation = 360}
				)
				iconRotTween:Play()

				-- Animacja SunBurst (ciągłe kręcenie)
				local sunBurstRotation = 0
				local lastTime = tick()
				local sunBurstConnection
				sunBurstConnection = RunService.RenderStepped:Connect(function()
					local now = tick()
					sunBurstRotation = (sunBurstRotation + (now - lastTime) * REWARD_ROTATION_SPEED * 2) % 360
					sunBurst.Rotation = sunBurstRotation
					lastTime = now
				end)

				-- Dodatkowe efekty - pulsowanie tekstu
				local textPulseTween = TweenService:Create(
					passName,
					TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{TextScaled = true}
				)
				textPulseTween:Play()

				-- Dźwięk sukcesu
				playSound("Reward")

				-- Po 2 sekundach chowamy animację
				task.delay(4, function()
					-- Zatrzymujemy animacje
					sunBurstConnection:Disconnect()
					textPulseTween:Cancel()

					-- Animacja chowania
					local hideScaleTween
					if uiScale then
						hideScaleTween = TweenService:Create(
							uiScale,
							TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In),
							{Scale = 0}
						)
						hideScaleTween:Play()
					end

					local hideBgTween = TweenService:Create(
						gamepassShow,
						TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{BackgroundTransparency = 1}
					)
					hideBgTween:Play()

					-- Rotacja ikony w drugą stronę przy chowaniu
					TweenService:Create(
						passIcon,
						TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{Rotation = -180}
					):Play()

					hideBgTween.Completed:Connect(function()
						gamepassShow.Visible = false
						pass.Visible = false
						-- Reset rotacji
						passIcon.Rotation = 0
						sunBurst.Rotation = 0
					end)
				end)

				-- Zwykły popup z podziękowaniem
				self:Local_SendPopUp(
					"Thanks for your support💝",
					Color3.new(1, 0.972549, 0.192157),
					Color3.new(0.101961, 0.101961, 0.101961),
					3,
					false
				)
			else
				-- Gamepass nie został kupiony
				self:Local_SendPopUp(
					"Remember That You Can Buy at Any Time💝",
					Color3.new(1, 0.972549, 0.192157),
					Color3.new(0.101961, 0.101961, 0.101961),
					3,
					false
				)
			end

			-- Cleanup animacji kupowania
			animData.cleanup(function()
				isPromptActive = false
				connection:Disconnect()
			end)
		end
	end)

	MarketplaceService:PromptGamePassPurchase(player, id)
end

function PopUpModule:Local_PromptProduct(player, id)
	if isPromptActive then return end
	isPromptActive = true

	local playerGui = player.PlayerGui
	local mainGui = playerGui:WaitForChild("Animations")
	local animData = playBuyAnimation(mainGui)

	playSound("Prompt")

	local connection
	connection = MarketplaceService.PromptProductPurchaseFinished:Connect(function(plr, productId, wasPurchased)
		print("Event PromptProductPurchaseFinished fired for", plr, productId, wasPurchased)
		if ((typeof(plr) == "Instance" and plr == player) or (typeof(plr) == "number" and plr == player.UserId))
			and productId == id then
			self:Local_SendPopUp(
				wasPurchased and "Thanks for your support💝" or "Remember That You Can Buy at Any Time💝",
				Color3.new(1, 0.972549, 0.192157),
				Color3.new(0.101961, 0.101961, 0.101961),
				3,
				false
			)
			animData.cleanup(function()
				isPromptActive = false
				connection:Disconnect()
			end)
		end
	end)

	MarketplaceService:PromptProductPurchase(player, id)
end


function PopUpModule:Local_Transition(totalTime)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local animations = playerGui:WaitForChild("Animations")
	local transitionFolder = animations:WaitForChild("Transition")

	local frames = {}
	for _, child in ipairs(transitionFolder:GetChildren()) do
		if child:IsA("Frame") then
			child.Visible = false
			local uiScale = child:FindFirstChildOfClass("UIScale")
			if uiScale then
				uiScale.Scale = 0
			end
			table.insert(frames, child)
		end
	end

	-- Losowe przetasowanie klatek
	for i = #frames, 2, -1 do
		local j = math.random(1, i)
		frames[i], frames[j] = frames[j], frames[i]
	end

	local n = #frames
	if n == 0 then return end

	local delayPerFrame = totalTime / n
	for i, frame in ipairs(frames) do
		frame.Visible = true
		local uiScale = frame:FindFirstChildOfClass("UIScale")
		if uiScale then
			task.delay((i + 0.5) * delayPerFrame, function()
				TweenService:Create(uiScale, TweenInfo.new(delayPerFrame, EASING_STYLE_IN, EASING_DIRECTION_IN), {Scale = 1}):Play()
			end)
		end
	end

	task.delay(totalTime + 0.5, function()
		for _, frame in ipairs(frames) do
			local uiScale = frame:FindFirstChildOfClass("UIScale")
			if uiScale then
				local tween = TweenService:Create(
					uiScale,
					TweenInfo.new(1, EASING_STYLE_OUT, EASING_DIRECTION_OUT),
					{Scale = 0}
				)
				tween:Play()
				tween.Completed:Connect(function()
					frame.Visible = false
				end)
			end
		end
	end)
end

function PopUpModule:Local_FlashbangEffect(duration, color)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local animations = playerGui:WaitForChild("Animations")
	local flashbangTemplate = animations:WaitForChild("FlashbangEffect")

	local flashbangClone = flashbangTemplate:Clone()
	flashbangClone.Parent = animations
	flashbangClone.Visible = true
	flashbangClone.BackgroundColor3 = color
	flashbangClone.Transparency = 1

	local tweenIn = TweenService:Create(
		flashbangClone,
		TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 0}
	)
	tweenIn:Play()
	tweenIn.Completed:Connect(function()
		local tweenOut = TweenService:Create(
			flashbangClone,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Transparency = 1}
		)
		tweenOut:Play()
		tweenOut.Completed:Connect(function()
			flashbangClone:Destroy()
		end)
	end)
end

function PopUpModule:Local_SpawnConfetti(count)
	local player = Players.LocalPlayer
	local animations = player.PlayerGui:WaitForChild("Animations")
	local sizesFolder = animations:WaitForChild("Sizes")
	local container = animations:WaitForChild("Container")

	for i = 1, count do
		-- Wybieramy losowy szablon z folderu Sizes
		local sizes = sizesFolder:GetChildren()
		local template = sizes[RNG:NextInteger(1, #sizes)]
		local confetti = template:Clone()

		confetti.BackgroundColor3 = Colors[RNG:NextInteger(1, #Colors)]
		local startX = RNG:NextNumber(0, 1)
		local startY = RNG:NextNumber(-0.5, -0.1)
		confetti.Position = UDim2.new(startX, 0, startY, 0)
		confetti.Rotation = RNG:NextNumber(0, 360)
		confetti.Visible = true
		confetti.Parent = container

		local endX = startX + RNG:NextNumber(-0.05, 0.05)
		local endY = RNG:NextNumber(1, 1.2)
		local duration = RNG:NextNumber(1, 1.5)

		local tween = TweenService:Create(
			confetti,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Position = UDim2.new(endX, 0, endY, 0),
				Rotation = confetti.Rotation + RNG:NextNumber(90, 360)
			}
		)
		tween:Play()

		tween.Completed:Connect(function()
			confetti:Destroy()
		end)
	end
end


function PopUpModule:Server_SendPopUp(player, text, textColor, strokeColor, duration, isError)
	PopUpEvent:FireClient(player, "SendPopUp", text, textColor, strokeColor, duration, isError)
end

function PopUpModule:Server_spawnConfetti(player, count)
	PopUpEvent:FireClient(player, "SpawnConfetti", count)
end

function PopUpModule:Server_ShowReward(player, rewardTable)
	PopUpEvent:FireClient(player, "ShowReward", rewardTable)
end

function PopUpModule:Server_ShowNotify(player, RewardName, Amount, Icon, Duration)
	PopUpEvent:FireClient(player, "ShowNotify",RewardName , Amount, Icon, Duration)
end

function PopUpModule:Server_ShowChestOpenResult(player, openResult)
	PopUpEvent:FireClient(player, "ShowChestOpenResult", openResult)
end

function PopUpModule:Server_PromptGamepass(player, id)
	PopUpEvent:FireClient(player, "PromptGamepass", id)
end

function PopUpModule:Server_PromptProduct(player, id)
	PopUpEvent:FireClient(player, "PromptProduct", id)
end

function PopUpModule:Server_Transition(player, time)
	PopUpEvent:FireClient(player, "Transition", time)
end

if RunService:IsClient() then
	PopUpEvent.OnClientEvent:Connect(function(funcName, ...)
		local f = PopUpModule["Local_" .. funcName]
		if f then
			f(PopUpModule, ...)
		else
			warn("Brak funkcji klienckiej: " .. funcName)
		end
	end)
end

return PopUpModule
