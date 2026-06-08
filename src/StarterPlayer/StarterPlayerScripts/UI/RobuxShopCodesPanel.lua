local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local ShopFolder = ReplicatedStorage:WaitForChild("UI"):WaitForChild("Shop")
local PurchaseAdapter = require(ShopFolder:WaitForChild("PurchaseAdapter"))

local RobuxShopCodesPanel = {}

local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local GOLD = Color3.fromRGB(228, 190, 78)
local GOLD_SOFT = Color3.fromRGB(255, 223, 128)
local CARD = Color3.fromRGB(8, 8, 9)
local INK = Color3.fromRGB(15, 15, 18)
local DISABLED = Color3.fromRGB(45, 45, 50)
local TXT = Color3.fromRGB(235, 235, 235)
local GREYTEXT = Color3.fromRGB(150, 150, 155)
local STROKE = Color3.fromRGB(60, 60, 66)
local HOVER = Color3.fromRGB(26, 26, 30)
local PANEL_NAME = "CodesPanel"

local boundGuis = setmetatable({}, { __mode = "k" })

local function setProps(instance, props)
	for key, value in pairs(props) do
		instance[key] = value
	end
	return instance
end

local function create(className, props, parent)
	local instance = Instance.new(className)
	setProps(instance, props)
	instance.Parent = parent
	return instance
end

local function addCorner(parent, radius)
	create("UICorner", {
		CornerRadius = UDim.new(0, radius),
	}, parent)
end

local function addStroke(parent, color, thickness, transparency)
	create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
	}, parent)
end

local function setButtonVisual(button, label, enabled)
	button.Active = enabled
	button.BackgroundColor3 = if enabled then GOLD else DISABLED
	label.TextColor3 = if enabled then Color3.new(1, 1, 1) else GREYTEXT

	local gradient = button:FindFirstChildWhichIsA("UIGradient")
	if gradient then
		gradient.Enabled = enabled
	end
end

local function getStatusText(adapter)
	local state = adapter:getCodeRedeemState()
	return tostring(state.message or ""), state.isPending == true
end

local function buildCodesPanel(content, adapter)
	local panel = content:FindFirstChild(PANEL_NAME)
	if panel and not panel:IsA("Frame") then
		panel:Destroy()
		panel = nil
	end
	if panel then
		return panel
	end

	panel = create("Frame", {
		Name = PANEL_NAME,
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = 900,
		Size = UDim2.new(1, 0, 0, 164),
		ZIndex = 6,
	}, content)
	addCorner(panel, 16)
	addStroke(panel, STROKE, 1.6, 0)

	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(16, 16, 19), Color3.fromRGB(7, 7, 8)),
	}, panel)

	local title = create("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FREDOKA,
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.new(1, -36, 0, 30),
		Text = "Redeem Codes",
		TextColor3 = TXT,
		TextSize = 24,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, panel)

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(18, 48),
		Size = UDim2.new(1, -36, 0, 22),
		Text = "Enter a launch or update code to claim rewards.",
		TextColor3 = GREYTEXT,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, panel)

	local input = create("TextBox", {
		Name = "CodeInput",
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamBold,
		PlaceholderText = "Enter code",
		Position = UDim2.fromOffset(18, 82),
		Size = UDim2.new(1, -190, 0, 42),
		Text = "",
		TextColor3 = TXT,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, panel)
	addCorner(input, 10)
	addStroke(input, STROKE, 1.1, 0.1)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, input)

	local button = create("TextButton", {
		Name = "RedeemButton",
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = false,
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -18, 0, 82),
		Size = UDim2.fromOffset(148, 42),
		Text = "",
		ZIndex = 7,
	}, panel)
	addCorner(button, 10)
	addStroke(button, Color3.new(0, 0, 0), 1.4, 0)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(GOLD_SOFT, GOLD),
	}, button)

	local buttonLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FREDOKA,
		Size = UDim2.fromScale(1, 1),
		Text = "Redeem",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 16,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.25,
		TextWrapped = true,
		ZIndex = 8,
	}, button)

	local helper = create("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(18, 132),
		Size = UDim2.new(1, -36, 0, 18),
		Text = "Codes can expire, so redeem them while they are active.",
		TextColor3 = GREYTEXT,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
	}, panel)

	local function refresh()
		local message, pending = getStatusText(adapter)
		helper.Text = if message ~= "" then message else "Codes can expire, so redeem them while they are active."
		buttonLabel.Text = if pending then "Redeeming..." else "Redeem"
		input.TextEditable = not pending
		input.TextTransparency = if pending then 0.24 else 0
		setButtonVisual(button, buttonLabel, not pending)
	end

	local function submit()
		local _, pending = getStatusText(adapter)
		if pending then
			return
		end

		local submittedText = input.Text
		task.spawn(function()
			local success = adapter:redeemCode(submittedText)
			if success then
				input.Text = ""
			end
			refresh()
		end)
	end

	button.Activated:Connect(submit)
	button.MouseEnter:Connect(function()
		local _, pending = getStatusText(adapter)
		if not pending then
			button.BackgroundColor3 = HOVER
		end
	end)
	button.MouseLeave:Connect(function()
		local _, pending = getStatusText(adapter)
		button.BackgroundColor3 = if pending then DISABLED else GOLD
	end)
	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)

	local function updateLayout()
		local narrow = content.AbsoluteSize.X < 560
		panel.Size = UDim2.new(1, 0, 0, if narrow then 208 else 164)
		title.TextSize = if narrow then 22 else 24
		if narrow then
			input.Position = UDim2.fromOffset(18, 84)
			input.Size = UDim2.new(1, -36, 0, 40)
			button.AnchorPoint = Vector2.new(0, 0)
			button.Position = UDim2.fromOffset(18, 132)
			button.Size = UDim2.new(1, -36, 0, 40)
			helper.Position = UDim2.fromOffset(18, 180)
		else
			input.Position = UDim2.fromOffset(18, 82)
			input.Size = UDim2.new(1, -190, 0, 42)
			button.AnchorPoint = Vector2.new(1, 0)
			button.Position = UDim2.new(1, -18, 0, 82)
			button.Size = UDim2.fromOffset(148, 42)
			helper.Position = UDim2.fromOffset(18, 132)
		end
	end

	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
	adapter:subscribe(refresh)
	updateLayout()
	refresh()

	return panel
end

function RobuxShopCodesPanel.BindGui(gui)
	if boundGuis[gui] then
		return
	end
	if not (gui and gui:IsA("ScreenGui")) then
		return
	end
	boundGuis[gui] = true

	task.spawn(function()
		local card = gui:WaitForChild("ShopCard", 10)
		local content = card and card:WaitForChild("Content", 10)
		if not (content and content:IsA("ScrollingFrame")) then
			warn("[RobuxShopCodesPanel] RobuxShopGui content not found.")
			return
		end

		local adapter = PurchaseAdapter.new(player)
		local panel = buildCodesPanel(content, adapter)
		if panel then
			print("[RobuxShopCodesPanel] Codes panel bound to " .. panel:GetFullName())
		end

		gui.Destroying:Connect(function()
			adapter:destroy()
			boundGuis[gui] = nil
		end)
	end)
end

return RobuxShopCodesPanel
