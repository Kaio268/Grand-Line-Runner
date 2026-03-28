local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")
local EatAnimationClient = require(modules:WaitForChild("DevilFruits"):WaitForChild("EatAnimationClient"))
local promptRemote = remotes:WaitForChild("DevilFruitConsumePrompt")
local responseRemote = remotes:WaitForChild("DevilFruitConsumeResponse")

local screenGui
local panel
local titleLabel
local bodyLabel
local confirmButton
local cancelButton
local pendingPayload

local function playEatAnimation(fruitKey)
	EatAnimationClient.Play(player, fruitKey)
end

local function ensurePromptGui()
	if screenGui and screenGui.Parent then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DevilFruitConsumePrompt"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 50
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 220)
	panel.BackgroundColor3 = Color3.fromRGB(20, 18, 16)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 147, 54)
	stroke.Transparency = 0.2
	stroke.Thickness = 1.5
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 18)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, 0, 0, 28)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "Eat Devil Fruit"
	titleLabel.TextColor3 = Color3.fromRGB(255, 241, 229)
	titleLabel.TextSize = 22
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = panel

	bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Position = UDim2.new(0, 0, 0, 42)
	bodyLabel.Size = UDim2.new(1, 0, 0, 92)
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.Text = ""
	bodyLabel.TextColor3 = Color3.fromRGB(232, 223, 216)
	bodyLabel.TextSize = 18
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.Parent = panel

	confirmButton = Instance.new("TextButton")
	confirmButton.Name = "Confirm"
	confirmButton.AnchorPoint = Vector2.new(0, 1)
	confirmButton.Position = UDim2.new(0, 0, 1, 0)
	confirmButton.Size = UDim2.fromOffset(180, 44)
	confirmButton.BackgroundColor3 = Color3.fromRGB(255, 138, 44)
	confirmButton.BorderSizePixel = 0
	confirmButton.Font = Enum.Font.GothamBold
	confirmButton.Text = "Eat"
	confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmButton.TextSize = 18
	confirmButton.Parent = panel

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 10)
	confirmCorner.Parent = confirmButton

	cancelButton = Instance.new("TextButton")
	cancelButton.Name = "Cancel"
	cancelButton.AnchorPoint = Vector2.new(1, 1)
	cancelButton.Position = UDim2.new(1, 0, 1, 0)
	cancelButton.Size = UDim2.fromOffset(180, 44)
	cancelButton.BackgroundColor3 = Color3.fromRGB(46, 42, 39)
	cancelButton.BorderSizePixel = 0
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.Text = "Cancel"
	cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	cancelButton.TextSize = 18
	cancelButton.Parent = panel

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 10)
	cancelCorner.Parent = cancelButton

	cancelButton.MouseButton1Click:Connect(function()
		panel.Visible = false
		if pendingPayload then
			responseRemote:FireServer(false, pendingPayload.FruitKey)
		end
		pendingPayload = nil
	end)

	confirmButton.MouseButton1Click:Connect(function()
		if not pendingPayload then
			return
		end

		if pendingPayload.Step == 1 and pendingPayload.RequiresReplaceWarning then
			pendingPayload.Step = 2
			bodyLabel.Text = string.format("This will replace your %s.", pendingPayload.CurrentFruitName)
			confirmButton.Text = "Replace"
			cancelButton.Text = "Cancel"
			return
		end

		panel.Visible = false
		local confirmedPayload = pendingPayload
		pendingPayload = nil

		playEatAnimation(confirmedPayload.FruitKey)
		responseRemote:FireServer(true, confirmedPayload.FruitKey)
	end)
end

promptRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	ensurePromptGui()

	local currentFruitName = tostring(payload.CurrentFruitName or "")
	pendingPayload = {
		FruitKey = payload.FruitKey,
		CurrentFruitName = currentFruitName,
		RequiresReplaceWarning = currentFruitName ~= "",
		Step = 1,
	}

	titleLabel.Text = tostring(payload.FruitName or payload.FruitKey or "Devil Fruit")
	bodyLabel.Text = "Are you sure you want to eat this fruit?"
	confirmButton.Text = "Eat"
	cancelButton.Text = "Cancel"
	panel.Visible = true
end)
