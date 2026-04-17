local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
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

	host.AnchorPoint = Vector2.new(1, 0)
	host.AutomaticSize = Enum.AutomaticSize.None
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.ClipsDescendants = false
	host.Position = UDim2.new(1, -18, 0, 122)
	host.Size = UDim2.fromOffset(360, 140)
	host.Visible = true
	host.ZIndex = 260

	return host
end

local function render()
	hideLegacyBoosts()

	local host = ensureHost()
	if host then
		root:render(ReactRoblox.createPortal(React.createElement(HudBoostTimer, {
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

playerGui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "HUD" or descendant.Name == "LButtons" or descendant.Name == "Boosts" then
		task.defer(scheduleRender)
	end
end)

playerGui.DescendantRemoving:Connect(function(descendant)
	if descendant.Name == "HUD" or descendant.Name == "LButtons" or descendant.Name == "Boosts" then
		task.defer(scheduleRender)
	end
end)

scheduleRender()

script.Destroying:Connect(function()
	destroyed = true
	root:unmount()
end)
