local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local SpeedUpgradeTutorialBridge = require(Modules:WaitForChild("SpeedUpgradeTutorialBridge"))
local SpeedUpgrade = require(Modules:WaitForChild("Configs"):WaitForChild("SpeedUpgrade"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local Shorten = require(Modules:WaitForChild("Shorten"))

local BuySpeedUpgradeRemote = ReplicatedStorage:WaitForChild("BuySpeedUpgrade")

local GUI_NAME = "UpgradeGui"
local DIAGNOSTICS_ATTRIBUTE = "SpeedUpgradeDiagnosticsEnabled"
local GENERATED_CARD_ATTRIBUTE = "GeneratedSpeedUpgradeCard"
local GENERATED_TEMPLATE_ATTRIBUTE = "GeneratedSpeedUpgradeCardTemplate"
local GENERATED_CONTAINER_ATTRIBUTE = "GeneratedSpeedUpgradeListContainer"
local MIN_DISPLAY_ORDER = 220
local CONTENT_FRAME_NAME = "Content"
local LIST_NAME = "UpgradeList"

local gui = playerGui:FindFirstChild(GUI_NAME)
local cardsContainer = nil
local cardTemplate = nil
local closeButton = nil
local firstBuyButton = nil
local moneyValue = nil
local speedValue = nil
local lastFeedback = ""
local lastFeedbackKey = nil
local destroyed = false
local renderQueued = false
local connections = {}
local renderConnections = {}
local closeButtonConnection = nil
local generatedCardCount = 0
local lastContainerPath = "nil"
local lastRenderedSummary = {}
local scheduleRender

local function debugLog(...)
	if ReplicatedStorage:GetAttribute(DIAGNOSTICS_ATTRIBUTE) == true then
		print("[SpeedUpgradeScreenGui]", ...)
	end
end

local function track(connection)
	if connection then
		connections[#connections + 1] = connection
	end
	return connection
end

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, connection in ipairs(renderConnections) do
		connection:Disconnect()
	end
	table.clear(renderConnections)
	if closeButtonConnection then
		closeButtonConnection:Disconnect()
		closeButtonConnection = nil
	end
end

local function disconnectRenderConnections()
	for _, connection in ipairs(renderConnections) do
		connection:Disconnect()
	end
	table.clear(renderConnections)
end

local function trackRender(connection)
	if connection then
		renderConnections[#renderConnections + 1] = connection
	end
	return connection
end

local function getFullName(instance)
	if not instance then
		return "nil"
	end
	local ok, result = pcall(function()
		return instance:GetFullName()
	end)
	return ok and result or tostring(instance)
end

local function isGuiObject(instance)
	return instance and instance:IsA("GuiObject")
end

local function lowerName(instance)
	return string.lower(tostring(instance and instance.Name or ""))
end

local function nameContains(instance, token)
	return string.find(lowerName(instance), string.lower(token), 1, true) ~= nil
end

local function findDescendant(root, predicate)
	if not root then
		return nil
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if predicate(descendant) then
			return descendant
		end
	end
	return nil
end

local function getGuiDepth(instance, ancestor)
	local depth = 0
	local current = instance
	while current and current ~= ancestor do
		depth += 1
		current = current.Parent
	end
	return depth
end

local function findButton(root, names)
	for _, name in ipairs(names) do
		local exact = findDescendant(root, function(descendant)
			return descendant:IsA("GuiButton") and descendant.Name == name
		end)
		if exact then
			return exact
		end
	end

	for _, name in ipairs(names) do
		local fuzzy = findDescendant(root, function(descendant)
			return descendant:IsA("GuiButton") and nameContains(descendant, name)
		end)
		if fuzzy then
			return fuzzy
		end
	end

	return nil
end

local function findTextObject(root, names)
	for _, name in ipairs(names) do
		local exact = findDescendant(root, function(descendant)
			return (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Name == name
		end)
		if exact then
			return exact
		end
	end

	for _, name in ipairs(names) do
		local fuzzy = findDescendant(root, function(descendant)
			return (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and nameContains(descendant, name)
		end)
		if fuzzy then
			return fuzzy
		end
	end

	return nil
end

local function setText(root, names, text)
	local target = findTextObject(root, names)
	if target then
		target.Text = text
	end
	return target
end

local function getCurrentSpeed()
	if speedValue and speedValue.Parent and speedValue:IsA("ValueBase") then
		return math.max(1, tonumber(speedValue.Value) or 1), true
	end
	return 1, false
end

local function getCurrentBeli()
	if moneyValue and moneyValue.Parent and moneyValue:IsA("ValueBase") then
		return math.max(0, tonumber(moneyValue.Value) or 0), true
	end

	local latestMoney = CurrencyUtil.findPrimaryValueObject(player)
	if latestMoney and latestMoney:IsA("ValueBase") then
		moneyValue = latestMoney
		return math.max(0, tonumber(latestMoney.Value) or 0), true
	end

	return 0, false
end

local function formatBeli(amount)
	return Shorten.roundNumber(math.max(0, tonumber(amount) or 0)) .. CurrencyUtil.getCompactSuffix()
end

local function collectUpgradeEntries()
	local entries = {}
	for key, config in pairs(SpeedUpgrade) do
		if typeof(key) == "number" and typeof(config) == "table" then
			entries[#entries + 1] = {
				key = key,
				config = config,
				addSpeed = math.max(0, tonumber(config.AddSpeed) or 0),
			}
		end
	end

	table.sort(entries, function(a, b)
		if a.addSpeed == b.addSpeed then
			return a.key < b.key
		end
		return a.addSpeed < b.addSpeed
	end)

	return entries
end

local function getPanelScore(frame)
	if not (frame and frame:IsA("Frame")) then
		return -math.huge
	end

	local name = lowerName(frame)
	local score = 0
	if name == "mainpanel" or name == "main_panel" then
		score += 10000
	elseif name == "main" or name == "panel" or name == "card" then
		score += 5000
	elseif nameContains(frame, "panel") or nameContains(frame, "card") or nameContains(frame, "upgrade") then
		score += 2000
	end

	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			local text = string.upper(tostring(descendant.Text or ""))
			if text == "UPGRADE" then
				score += 7000
			elseif string.find(text, "UPGRADE", 1, true) then
				score += 2500
			end
		end
	end

	local size = frame.AbsoluteSize
	local area = size.X * size.Y
	if area > 0 then
		score += math.min(area / 100, 2500)
	end
	if frame.Visible then
		score += 1000
	end
	score -= getGuiDepth(frame, gui) * 25

	return score
end

local function findMainPanel(root)
	if not root then
		return nil
	end

	for _, candidateName in ipairs({ "MainPanel", "Main", "Panel", "Card" }) do
		local candidate = root:FindFirstChild(candidateName, true)
		if candidate and candidate:IsA("Frame") then
			return candidate
		end
	end

	local best = nil
	local bestScore = -math.huge
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Frame") then
			local score = getPanelScore(descendant)
			if score > bestScore then
				best = descendant
				bestScore = score
			end
		end
	end
	return best
end

local function ensureContentFrame(panel)
	if not panel then
		return nil
	end

	local existing = panel:FindFirstChild(CONTENT_FRAME_NAME)
	if existing and existing:IsA("Frame") then
		return existing
	end

	local frame = Instance.new("Frame")
	frame.Name = CONTENT_FRAME_NAME
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Position = UDim2.fromScale(0.06, 0.22)
	frame.Size = UDim2.fromScale(0.88, 0.68)
	frame.ZIndex = math.max(panel.ZIndex + 1, 10)
	frame.Parent = panel

	return frame
end

local function ensureListContainer(content)
	if not content then
		return nil
	end

	local existing = content:FindFirstChild(LIST_NAME)
	if existing and existing:IsA("ScrollingFrame") then
		return existing
	end

	local wrongClass = content:FindFirstChild(LIST_NAME)
	if wrongClass then
		wrongClass:Destroy()
	end

	local container = Instance.new("ScrollingFrame")
	container.Name = LIST_NAME
	container:SetAttribute(GENERATED_CONTAINER_ATTRIBUTE, true)
	container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.CanvasSize = UDim2.new()
	container.ClipsDescendants = true
	container.Position = UDim2.fromScale(0, 0)
	container.ScrollBarImageColor3 = Color3.fromRGB(242, 184, 47)
	container.ScrollBarThickness = 5
	container.Size = UDim2.fromScale(1, 1)
	container.ZIndex = math.max(content.ZIndex + 1, 11)
	container.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent = container

	return container
end

local function ensureCardsContainer()
	if cardsContainer and cardsContainer.Parent then
		return cardsContainer
	end
	if not gui then
		return nil
	end

	local panel = findMainPanel(gui)
	if not panel then
		return nil
	end

	local content = ensureContentFrame(panel)
	cardsContainer = ensureListContainer(content)
	return cardsContainer
end

local function findAuthoredTemplate(container)
	if not container then
		return nil
	end

	local existingGenerated = container:FindFirstChild("GeneratedSpeedUpgradeCardTemplate")
	if existingGenerated and isGuiObject(existingGenerated) then
		return existingGenerated
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if
			isGuiObject(descendant)
			and not descendant:GetAttribute(GENERATED_CARD_ATTRIBUTE)
			and (
				descendant:GetAttribute(GENERATED_TEMPLATE_ATTRIBUTE) == true
				or nameContains(descendant, "template")
				or nameContains(descendant, "card")
				or nameContains(descendant, "row")
				or nameContains(descendant, "option")
			)
		then
			return descendant
		end
	end

	return nil
end

local function createDefaultTemplate(container)
	local template = Instance.new("Frame")
	template.Name = "GeneratedSpeedUpgradeCardTemplate"
	template:SetAttribute(GENERATED_TEMPLATE_ATTRIBUTE, true)
	template.BackgroundColor3 = Color3.fromRGB(11, 24, 32)
	template.BackgroundTransparency = 0.08
	template.BorderSizePixel = 0
	template.Size = UDim2.new(1, -18, 0, 72)
	template.Visible = false
	template.ZIndex = math.max(container.ZIndex + 1, 12)
	template.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = template

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(242, 184, 47)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
	stroke.Parent = template

	local title = Instance.new("TextLabel")
	title.Name = "UpgradeTitle"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Position = UDim2.fromOffset(14, 7)
	title.Size = UDim2.new(0.38, 0, 0, 22)
	title.TextColor3 = Color3.fromRGB(255, 238, 176)
	title.TextSize = 19
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = template.ZIndex + 1
	title.Parent = template

	local current = Instance.new("TextLabel")
	current.Name = "CurrentSpeed"
	current.BackgroundTransparency = 1
	current.Font = Enum.Font.GothamMedium
	current.Position = UDim2.fromOffset(14, 38)
	current.Size = UDim2.new(0.24, 0, 0, 18)
	current.TextColor3 = Color3.fromRGB(219, 229, 226)
	current.TextSize = 13
	current.TextXAlignment = Enum.TextXAlignment.Left
	current.ZIndex = template.ZIndex + 1
	current.Parent = template

	local after = Instance.new("TextLabel")
	after.Name = "AfterSpeed"
	after.BackgroundTransparency = 1
	after.Font = Enum.Font.GothamMedium
	after.Position = UDim2.new(0.27, 0, 0, 38)
	after.Size = UDim2.new(0.24, 0, 0, 18)
	after.TextColor3 = Color3.fromRGB(219, 229, 226)
	after.TextSize = 13
	after.TextXAlignment = Enum.TextXAlignment.Left
	after.ZIndex = template.ZIndex + 1
	after.Parent = template

	local cost = Instance.new("TextLabel")
	cost.Name = "Cost"
	cost.BackgroundTransparency = 1
	cost.Font = Enum.Font.GothamBold
	cost.Position = UDim2.new(0.52, 0, 0, 11)
	cost.Size = UDim2.new(0.22, 0, 0, 24)
	cost.TextColor3 = Color3.fromRGB(255, 215, 83)
	cost.TextSize = 16
	cost.TextXAlignment = Enum.TextXAlignment.Left
	cost.ZIndex = template.ZIndex + 1
	cost.Parent = template

	local feedback = Instance.new("TextLabel")
	feedback.Name = "Feedback"
	feedback.BackgroundTransparency = 1
	feedback.Font = Enum.Font.GothamMedium
	feedback.Position = UDim2.new(0.52, 0, 0, 40)
	feedback.Size = UDim2.new(0.22, 0, 0, 16)
	feedback.TextColor3 = Color3.fromRGB(190, 207, 204)
	feedback.TextSize = 12
	feedback.TextXAlignment = Enum.TextXAlignment.Left
	feedback.ZIndex = template.ZIndex + 1
	feedback.Parent = template

	local buy = Instance.new("TextButton")
	buy.Name = "BuyButton"
	buy.AutoButtonColor = true
	buy.BackgroundColor3 = Color3.fromRGB(242, 184, 47)
	buy.BorderSizePixel = 0
	buy.Font = Enum.Font.GothamBold
	buy.Position = UDim2.new(1, -122, 0.5, -16)
	buy.Size = UDim2.fromOffset(104, 32)
	buy.Text = "BUY"
	buy.TextColor3 = Color3.fromRGB(16, 21, 22)
	buy.TextSize = 14
	buy.ZIndex = template.ZIndex + 2
	buy.Parent = template

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0, 8)
	buyCorner.Parent = buy

	return template
end

local function ensureCardTemplate(container)
	if cardTemplate and cardTemplate.Parent then
		return cardTemplate
	end

	cardTemplate = findAuthoredTemplate(container)
	if not cardTemplate then
		cardTemplate = createDefaultTemplate(container)
	end
	cardTemplate.Visible = false
	return cardTemplate
end

local function clearGeneratedCards(container)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:GetAttribute(GENERATED_CARD_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function destroyIfSpeedUpgradeAdapter(instance)
	if not instance then
		return
	end
	if instance.Name == "ReactSpeedUpgradeBackdrop" or instance.Name == "ReactSpeedUpgradeHost" then
		debugLog("destroyLegacyAdapter", getFullName(instance))
		instance:Destroy()
		return
	end
	if instance.Name == "SpeedUpgrade" and instance:GetAttribute("ReactFrameModalAdapterFrame") == true then
		debugLog("destroyLegacyAdapter", getFullName(instance))
		instance:Destroy()
	end
end

local function suppressLegacyReactSpeedUpgrade()
	local reactLayer = playerGui:FindFirstChild("ReactModalLayer")
	if reactLayer then
		for _, child in ipairs(reactLayer:GetChildren()) do
			destroyIfSpeedUpgradeAdapter(child)
		end
	end

	local frames = playerGui:FindFirstChild("Frames")
	if frames then
		for _, child in ipairs(frames:GetChildren()) do
			destroyIfSpeedUpgradeAdapter(child)
		end
	end
end

local function configureCardVisual(card, affordable)
	if card:IsA("GuiObject") then
		card.Visible = true
		card.Active = true
	end

	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if affordable then Color3.fromRGB(242, 184, 47) else Color3.fromRGB(128, 139, 141)
		stroke.Transparency = if affordable then 0.15 else 0.4
	end
end

local function populateCard(card, entry, currentSpeed, speedReady, currentBeli, beliReady)
	local addSpeed = entry.addSpeed
	local cost = SpeedUpgrade.ComputeCost(entry.config, currentSpeed)
	local affordable = beliReady and currentBeli >= cost
	local title = string.format("+%s Speed", Shorten.roundNumber(addSpeed))
	local currentText = if speedReady then "Current Speed: " .. Shorten.roundNumber(currentSpeed) else "Current Speed: loading..."
	local afterText = if speedReady
		then "After: " .. Shorten.roundNumber(currentSpeed + addSpeed)
		else "After: +" .. Shorten.roundNumber(addSpeed)
	local costText = "Cost: " .. formatBeli(cost)
	local feedbackText = if not beliReady
		then "Beli loading..."
		elseif affordable then "Ready to buy"
		else "Need " .. formatBeli(cost - currentBeli)

	if lastFeedback ~= "" and lastFeedbackKey == entry.key then
		feedbackText = lastFeedback
	end

	card.Name = "GeneratedSpeedUpgradeCard_" .. tostring(addSpeed)
	card:SetAttribute(GENERATED_CARD_ATTRIBUTE, true)
	card:SetAttribute("SpeedUpgradeConfigKey", entry.key)
	card:SetAttribute("SpeedUpgradeAddSpeed", addSpeed)
	card:SetAttribute("SpeedUpgradeCost", cost)
	card.LayoutOrder = entry.key

	setText(card, { "UpgradeTitle", "Title", "Name", "SpeedName" }, title)
	setText(card, { "CurrentSpeed", "Current", "CurrentLabel" }, currentText)
	setText(card, { "AfterSpeed", "NextSpeed", "After", "Result" }, afterText)
	setText(card, { "Cost", "Price", "Beli", "CostLabel" }, costText)
	setText(card, { "Feedback", "Status", "Message", "State" }, feedbackText)

	local buyButton = findButton(card, { "BuyButton", "Buy", "PurchaseButton", "Purchase" })
	if buyButton then
		buyButton.Active = affordable
		buyButton.AutoButtonColor = affordable
		buyButton.BackgroundColor3 = if affordable then Color3.fromRGB(242, 184, 47) else Color3.fromRGB(73, 82, 86)
		buyButton.TextColor3 = if affordable then Color3.fromRGB(16, 21, 22) else Color3.fromRGB(210, 218, 217)
		buyButton.Text = if affordable then "BUY" else "NEED BELI"
		trackRender(buyButton.Activated:Connect(function()
			local latestBeli = getCurrentBeli()
			if latestBeli < cost then
				lastFeedbackKey = entry.key
				lastFeedback = "Need " .. formatBeli(cost - latestBeli)
				debugLog("blockedPurchase", title, "cost", cost, "beli", latestBeli)
				scheduleRender()
				return
			end

			lastFeedbackKey = entry.key
			lastFeedback = "Purchase sent"
			debugLog("firePurchase", "key", entry.key, "title", title, "cost", cost)
			BuySpeedUpgradeRemote:FireServer(tostring(entry.key))
		end))
	end

	configureCardVisual(card, affordable)

	return {
		title = title,
		cost = cost,
		key = entry.key,
		button = buyButton,
	}
end

local function publishTutorialRefs()
	if gui and closeButton and firstBuyButton then
		SpeedUpgradeTutorialBridge.SetRefs({
			buyButton = firstBuyButton,
			closeButton = closeButton,
			root = gui,
		})
	end
end

local function rebuildCards()
	if destroyed or not gui then
		return
	end

	local container = ensureCardsContainer()
	if not container then
		warn("[SpeedUpgradeScreenGui] Could not locate or create a card container inside UpgradeGui.")
		return
	end

	local template = ensureCardTemplate(container)
	disconnectRenderConnections()
	clearGeneratedCards(container)

	local currentSpeed, speedReady = getCurrentSpeed()
	local currentBeli, beliReady = getCurrentBeli()
	local entries = collectUpgradeEntries()
	generatedCardCount = 0
	firstBuyButton = nil
	lastContainerPath = getFullName(container)
	lastRenderedSummary = {}

	if #entries ~= 3 then
		warn(string.format("[SpeedUpgradeScreenGui] Expected 3 numeric SpeedUpgrade entries, found %d.", #entries))
	end

	for index, entry in ipairs(entries) do
		local card = template:Clone()
		card.Parent = container
		card.LayoutOrder = index
		local summary = populateCard(card, entry, currentSpeed, speedReady, currentBeli, beliReady)
		generatedCardCount += 1
		lastRenderedSummary[#lastRenderedSummary + 1] = summary
		debugLog("card", "index", index, "key", summary.key, "title", summary.title, "cost", summary.cost)
		if firstBuyButton == nil then
			firstBuyButton = summary.button
		end
		debugLog("cardMetrics", getFullName(card), "pos", tostring(card.AbsolutePosition), "size", tostring(card.AbsoluteSize), "visible", tostring(card.Visible), "z", card.ZIndex)
	end

	publishTutorialRefs()
	debugLog(
		"rebuild",
		"entries",
		#entries,
		"cards",
		generatedCardCount,
		"container",
		lastContainerPath,
		"speed",
		currentSpeed,
		"speedReady",
		speedReady,
		"beli",
		currentBeli,
		"beliReady",
		beliReady
	)
	debugLog("containerMetrics", lastContainerPath, "pos", tostring(container.AbsolutePosition), "size", tostring(container.AbsoluteSize), "visible", tostring(container.Visible), "z", container.ZIndex)
end

scheduleRender = function()
	if renderQueued or destroyed then
		return
	end
	renderQueued = true
	task.defer(function()
		renderQueued = false
		rebuildCards()
	end)
end

local function findCloseButton()
	if not gui then
		return nil
	end
	return findButton(gui, { "CloseButton", "Close", "Exit", "X" })
end

local function bindCloseButton()
	if closeButtonConnection then
		closeButtonConnection:Disconnect()
		closeButtonConnection = nil
	end
	closeButton = findCloseButton()
	if closeButton then
		closeButtonConnection = closeButton.Activated:Connect(function()
			ReactModalRegistry.Close("SpeedUpgrade")
		end)
	end
	publishTutorialRefs()
end

local function bindMoneyValue()
	local nextMoney = CurrencyUtil.findPrimaryValueObject(player)
	if nextMoney == moneyValue then
		return
	end
	moneyValue = nextMoney
	if moneyValue and moneyValue:IsA("ValueBase") then
		track(moneyValue:GetPropertyChangedSignal("Value"):Connect(scheduleRender))
		debugLog("moneyBound", getFullName(moneyValue), moneyValue.Value)
	end
	scheduleRender()
end

local function bindSpeedValue()
	local hiddenStats = player:FindFirstChild("HiddenLeaderstats")
	local nextSpeed = hiddenStats and hiddenStats:FindFirstChild("Speed")
	if nextSpeed == speedValue then
		return
	end
	speedValue = nextSpeed
	if speedValue and speedValue:IsA("ValueBase") then
		track(speedValue:GetPropertyChangedSignal("Value"):Connect(scheduleRender))
		debugLog("speedBound", getFullName(speedValue), speedValue.Value)
	end
	scheduleRender()
end

local function setGuiOpen(isOpen)
	if not gui then
		gui = playerGui:FindFirstChild(GUI_NAME) or playerGui:WaitForChild(GUI_NAME, 2)
	end
	if not gui or not gui:IsA("ScreenGui") then
		warn("[SpeedUpgradeScreenGui] PlayerGui.UpgradeGui was not found; authored speed upgrade UI cannot open.")
		return
	end

	suppressLegacyReactSpeedUpgrade()
	gui.DisplayOrder = math.max(gui.DisplayOrder, MIN_DISPLAY_ORDER)
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Enabled = isOpen == true
	gui:SetAttribute("ReactSpeedUpgradeSuperseded", nil)

	if gui.Enabled then
		bindMoneyValue()
		bindSpeedValue()
		bindCloseButton()
		scheduleRender()
	else
		SpeedUpgradeTutorialBridge.ClearRefs()
	end
end

local function isGuiVisible()
	return gui ~= nil and gui.Parent ~= nil and gui:IsA("ScreenGui") and gui.Enabled == true
end

local unregisterModal = ReactModalRegistry.Register("SpeedUpgrade", {
	toggle = function()
		setGuiOpen(not isGuiVisible())
	end,
	open = function()
		setGuiOpen(true)
	end,
	close = function()
		setGuiOpen(false)
	end,
	isVisible = isGuiVisible,
}, {
	priority = 20,
})

local function bindGui(nextGui)
	if not (nextGui and nextGui:IsA("ScreenGui")) then
		return
	end

	gui = nextGui
	gui.Enabled = false
	gui.DisplayOrder = math.max(gui.DisplayOrder, MIN_DISPLAY_ORDER)
	bindCloseButton()
	bindMoneyValue()
	bindSpeedValue()
	scheduleRender()
	debugLog("guiBound", getFullName(gui))
end

bindGui(gui)

track(playerGui.ChildAdded:Connect(function(child)
	if child.Name == GUI_NAME and child:IsA("ScreenGui") then
		bindGui(child)
	end
end))

track(player.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then
		track(child.ChildAdded:Connect(bindMoneyValue))
		bindMoneyValue()
	elseif child.Name == "HiddenLeaderstats" then
		track(child.ChildAdded:Connect(bindSpeedValue))
		bindSpeedValue()
	end
end))

local existingLeaderstats = player:FindFirstChild("leaderstats")
if existingLeaderstats then
	track(existingLeaderstats.ChildAdded:Connect(bindMoneyValue))
end

local existingHiddenStats = player:FindFirstChild("HiddenLeaderstats")
if existingHiddenStats then
	track(existingHiddenStats.ChildAdded:Connect(bindSpeedValue))
end

script.Destroying:Connect(function()
	destroyed = true
	unregisterModal()
	SpeedUpgradeTutorialBridge.ClearRefs()
	disconnectAll()
end)
