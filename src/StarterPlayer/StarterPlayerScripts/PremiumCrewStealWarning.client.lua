local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local warningRemote = remotes:WaitForChild("PremiumCrewStealWarning")
local confirmRemote = remotes:WaitForChild("PremiumCrewStealConfirm")

local gui = nil
local currentToken = nil

local THEME = {
	Backdrop = Color3.fromRGB(7, 10, 16),
	Panel = Color3.fromRGB(25, 30, 40),
	PanelTop = Color3.fromRGB(38, 45, 60),
	Border = Color3.fromRGB(255, 204, 73),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(210, 218, 232),
	Danger = Color3.fromRGB(255, 91, 91),
	Confirm = Color3.fromRGB(67, 212, 113),
	Cancel = Color3.fromRGB(65, 75, 92),
}

local function makeCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function makeStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function makeLabel(parent, name, textSize, font, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.Gotham
	label.TextColor3 = color or THEME.Text
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

local function makeButton(parent, name, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = THEME.Text
	button.TextSize = 18
	button.Parent = parent
	makeCorner(button, 8)
	makeStroke(button, Color3.fromRGB(255, 255, 255), 1, 0.78)
	return button
end

local function closeModal(sendDecline)
	if currentToken and sendDecline == true then
		confirmRemote:FireServer(currentToken, false)
	end
	currentToken = nil
	if gui then
		gui.Enabled = false
	end
end

local function ensureGui()
	if gui then
		return gui
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "PremiumCrewStealWarning"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 620
	gui.Enabled = false
	gui.Parent = playerGui

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = THEME.Backdrop
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Text = ""
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = THEME.Panel
	panel.BorderSizePixel = 0
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0, 340)
	panel.Parent = backdrop
	makeCorner(panel, 10)
	makeStroke(panel, THEME.Border, 2, 0)

	local widthLimit = Instance.new("UISizeConstraint")
	widthLimit.MaxSize = Vector2.new(500, 370)
	widthLimit.MinSize = Vector2.new(300, 320)
	widthLimit.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 22)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 22)
	padding.PaddingRight = UDim.new(0, 22)
	padding.Parent = panel

	local title = makeLabel(panel, "Title", 26, Enum.Font.GothamBlack, THEME.Text)
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Text = "Steal Crewmate?"
	title.TextYAlignment = Enum.TextYAlignment.Center

	local warning = makeLabel(panel, "Warning", 18, Enum.Font.GothamBold, THEME.Danger)
	warning.Position = UDim2.fromOffset(0, 48)
	warning.Size = UDim2.new(1, 0, 0, 70)
	warning.Text = "This Robux purchase will take a placed crewmate from another player's ship."

	local body = makeLabel(panel, "Body", 17, Enum.Font.Gotham, THEME.Muted)
	body.Position = UDim2.fromOffset(0, 126)
	body.Size = UDim2.new(1, 0, 0, 82)

	local price = makeLabel(panel, "Price", 22, Enum.Font.GothamBlack, THEME.Border)
	price.Position = UDim2.fromOffset(0, 216)
	price.Size = UDim2.new(1, 0, 0, 34)
	price.TextYAlignment = Enum.TextYAlignment.Center

	local confirm = makeButton(panel, "Confirm", "Continue", THEME.Confirm)
	confirm.AnchorPoint = Vector2.new(1, 1)
	confirm.Position = UDim2.fromScale(1, 1)
	confirm.Size = UDim2.fromOffset(160, 46)

	local cancel = makeButton(panel, "Cancel", "Cancel", THEME.Cancel)
	cancel.AnchorPoint = Vector2.new(1, 1)
	cancel.Position = UDim2.new(1, -172, 1, 0)
	cancel.Size = UDim2.fromOffset(130, 46)

	backdrop.MouseButton1Click:Connect(function()
		closeModal(true)
	end)

	panel.InputBegan:Connect(function()
	end)

	cancel.MouseButton1Click:Connect(function()
		closeModal(true)
	end)

	confirm.MouseButton1Click:Connect(function()
		if not currentToken then
			return
		end
		local token = currentToken
		currentToken = nil
		gui.Enabled = false
		confirmRemote:FireServer(token, true)
	end)

	return gui
end

warningRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local screen = ensureGui()
	local panel = screen.Backdrop.Panel
	currentToken = tostring(payload.Token or "")

	local shield = if typeof(payload.Shield) == "table" then payload.Shield else {}
	local shieldMode = tostring(shield.Mode or "")
	if shieldMode == "shield_on" then
		panel.Title.Text = "Raid With Shield On?"
	elseif shieldMode == "shield_off" or shieldMode == "suppressed" then
		panel.Title.Text = "Raid With Protection Off?"
	else
		panel.Title.Text = "Steal Crewmate?"
	end
	panel.Warning.Text = tostring(
		shield.Message
			or "A successful raid may affect your protection status. The server will recheck before purchase."
	)
	panel.Body.Text = string.format(
		"You are about to spend Robux to steal %s from %s's ship stand %s. The server will recheck the target after purchase.",
		tostring(payload.CrewDisplayName or "this crewmate"),
		tostring(payload.VictimName or "another player"),
		tostring(payload.StandName or "?")
	)
	panel.Price.Text = string.format("%s Robux", tostring(payload.PriceRobux or "?"))
	screen.Enabled = currentToken ~= ""
end)
