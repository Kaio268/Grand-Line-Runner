local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local Responsive = require(UiFolder:WaitForChild("Responsive"))
local HudLayout = require(UiFolder:WaitForChild("HudLayout"))
local HudBoostTimer = require(UiFolder:WaitForChild("Hud"):WaitForChild("HudBoostTimer"))

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactHudBoostTimerRoot"
rootContainer.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)

local destroyed = false
local renderQueued = false

local function hideLegacyBoosts()
	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return
	end

	local boosts = hud:FindFirstChild("Boosts")
	if not boosts or not boosts:IsA("GuiObject") then
		return
	end

	boosts.Visible = false
	boosts.BackgroundTransparency = 1
	boosts.Size = UDim2.fromOffset(0, 0)

	for _, descendant in ipairs(boosts:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.Visible = false
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				descendant.TextTransparency = 1
				descendant.TextStrokeTransparency = 1
			elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				descendant.ImageTransparency = 1
			end
		elseif descendant:IsA("UIStroke") or descendant:IsA("UIGradient") then
			descendant.Enabled = false
		end
	end
end

local function ensureHost()
	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return nil
	end

	local sidebar = hud:FindFirstChild("LButtons")
	if not sidebar or not sidebar:IsA("GuiObject") then
		return nil
	end

	sidebar.ClipsDescendants = false
	sidebar.Visible = true

	local legacyHost = sidebar:FindFirstChild("ReactHudBoostTimerHost")
	if legacyHost and legacyHost:IsA("Frame") then
		legacyHost:Destroy()
	end

	local host = hud:FindFirstChild("ReactHudBoostTimerHost")
	if host and not host:IsA("Frame") then
		host:Destroy()
		host = nil
	end

	if not host then
		host = Instance.new("Frame")
		host.Name = "ReactHudBoostTimerHost"
		host.Parent = hud
	end

	local mode = Responsive.getHudLayoutMode()
	local layout = HudLayout.getBoostTimer(mode)
	host.AnchorPoint = Vector2.new(1, 0)
	host.AutomaticSize = Enum.AutomaticSize.None
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.ClipsDescendants = false
	host.Position = layout.position
	host.Size = layout.size
	host.Visible = true
	host.ZIndex = 260

	return host
end

local function render()
	hideLegacyBoosts()

	local host = ensureHost()
	if host then
		root:render(ReactRoblox.createPortal(React.createElement(HudBoostTimer, {
			layoutMode = Responsive.getHudLayoutMode(),
			player = player,
		}), host))
	else
		root:render(React.createElement(React.Fragment))
	end
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

local watchedHudChildren = {
	Boosts = true,
	LButtons = true,
	ReactHudBoostTimerHost = true,
}

local hudConnections = {}
local playerGuiConnections = {}

local function disconnectHudConnections()
	for _, connection in ipairs(hudConnections) do
		connection:Disconnect()
	end
	table.clear(hudConnections)
end

local function bindHudConnections()
	disconnectHudConnections()

	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return
	end

	hudConnections[#hudConnections + 1] = hud.ChildAdded:Connect(function(child)
		if watchedHudChildren[child.Name] then
			task.defer(scheduleRender)
		end
	end)
	hudConnections[#hudConnections + 1] = hud.ChildRemoved:Connect(function(child)
		if watchedHudChildren[child.Name] then
			task.defer(scheduleRender)
		end
	end)
end

local function handlePlayerGuiChildChanged(child)
	if child.Name == "HUD" then
		bindHudConnections()
		task.defer(scheduleRender)
	end
end

playerGuiConnections[#playerGuiConnections + 1] = playerGui.ChildAdded:Connect(handlePlayerGuiChildChanged)
playerGuiConnections[#playerGuiConnections + 1] = playerGui.ChildRemoved:Connect(handlePlayerGuiChildChanged)
bindHudConnections()

local viewportConnections = {}
local function bindViewportConnections()
	for _, connection in ipairs(viewportConnections) do
		connection:Disconnect()
	end
	table.clear(viewportConnections)

	local camera = Workspace.CurrentCamera
	if camera then
		viewportConnections[#viewportConnections + 1] =
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(scheduleRender)
	end
	viewportConnections[#viewportConnections + 1] = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindViewportConnections()
		scheduleRender()
	end)
end

bindViewportConnections()
scheduleRender()

script.Destroying:Connect(function()
	destroyed = true
	for _, connection in ipairs(playerGuiConnections) do
		connection:Disconnect()
	end
	disconnectHudConnections()
	for _, connection in ipairs(viewportConnections) do
		connection:Disconnect()
	end
	root:unmount()
end)
