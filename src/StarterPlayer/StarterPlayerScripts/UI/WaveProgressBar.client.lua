local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local LavaWaves = require(Modules:WaitForChild("Configs"):WaitForChild("LavaWaves"))
local WaveProgressBar = require(UiFolder:WaitForChild("WaveProgressBar"))

local DEFAULT_SECTIONS = {
	{ label = "Biome 1", widthScale = 1 / 8 },
	{ label = "Biome 2", widthScale = 1 / 8 },
	{ label = "Biome 3", widthScale = 1 / 8 },
	{ label = "Biome 4", widthScale = 1 / 8 },
	{ label = "Biome 5", widthScale = 1 / 8 },
	{ label = "Biome 6", widthScale = 1 / 8 },
	{ label = "Biome 7", widthScale = 1 / 8 },
	{ label = "Biome 8", widthScale = 1 / 8, isImpact = true },
}

local PLAYER_MARKER_PADDING = 0
local WAVE_MARKER_PADDING = 0

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactWaveProgressRoot"

local root = ReactRoblox.createRoot(rootContainer)

local cleanupConnections = {}
local orderedPlayers = {}
local hazardFolder = nil
local waveStart = nil
local waveEnd = nil
local pathStart = Vector3.zero
local pathAxis = Vector3.zAxis
local pathLength = 1
local renderQueued = false
local destroyed = false

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)
end

local function track(signal, callback)
	local connection = signal:Connect(callback)
	cleanupConnections[#cleanupConnections + 1] = connection
	return connection
end

local function getDefaultWaveIcon()
	for _, waveInfo in pairs(LavaWaves) do
		if typeof(waveInfo) == "table" then
			local image = tostring(waveInfo.IMAGE or waveInfo.Image or "")
			if image ~= "" then
				return image
			end
		end
	end
	return ""
end

local DEFAULT_WAVE_ICON = getDefaultWaveIcon()

local function getWorldPosition(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Model") then
		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok and typeof(pivot) == "CFrame" then
			return pivot.Position
		end

		local primary = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			return primary.Position
		end
	end

	return nil
end

local function updatePath()
	local startPos = waveStart and getWorldPosition(waveStart)
	local endPos = waveEnd and getWorldPosition(waveEnd)
	if not startPos or not endPos then
		return
	end

	pathStart = startPos
	local pathVector = endPos - startPos
	local magnitude = pathVector.Magnitude
	if magnitude > 1e-5 then
		pathAxis = pathVector.Unit
		pathLength = magnitude
	else
		pathAxis = Vector3.zAxis
		pathLength = 1
	end
end

local function alphaFromWorldPos(worldPos, padding)
	local projection = (worldPos - pathStart):Dot(pathAxis)
	local progress = math.clamp(projection / math.max(pathLength, 1), 0, 1)
	progress = 1 - progress
	local pad = math.clamp(tonumber(padding) or 0, 0, 0.2)
	return pad + progress * (1 - (pad * 2))
end

local function getHazardImage(hazard)
	if not hazard then
		return DEFAULT_WAVE_ICON
	end

	local explicit = hazard:GetAttribute("HudImage")
	if typeof(explicit) == "string" and explicit ~= "" then
		return explicit
	end

	local variant = hazard:GetAttribute("Variant")
	if typeof(variant) == "string" and variant ~= "" then
		local info = LavaWaves[variant]
		if typeof(info) == "table" then
			local image = tostring(info.IMAGE or info.Image or "")
			if image ~= "" then
				return image
			end
		end
	end

	return DEFAULT_WAVE_ICON
end

local function hideLegacyProgressBar()
	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return
	end

	local progressBar = hud:FindFirstChild("ProgressBar")
	if not progressBar or not progressBar:IsA("GuiObject") then
		return
	end

	progressBar.Visible = false
	progressBar.BackgroundTransparency = 1

	for _, descendant in ipairs(progressBar:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.Visible = false
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				descendant.TextTransparency = 1
				descendant.TextStrokeTransparency = 1
			end
		elseif descendant:IsA("UIStroke") or descendant:IsA("UIGradient") then
			descendant.Enabled = false
		end
	end
end

local function render()
	hideLegacyProgressBar()

	local playerMarkers = {}
	for _, info in ipairs(orderedPlayers) do
		local listedPlayer = Players:GetPlayerByUserId(tonumber(info.UserId) or 0)
		local character = listedPlayer and listedPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local alpha = 0

		if rootPart then
			alpha = alphaFromWorldPos(rootPart.Position, PLAYER_MARKER_PADDING)
		end

		playerMarkers[#playerMarkers + 1] = {
			alpha = alpha,
			userId = tonumber(info.UserId) or 0,
			isDead = humanoid ~= nil and humanoid.Health <= 0,
		}
	end

	local waveMarkers = {}
	if hazardFolder and hazardFolder.Parent then
		for _, hazard in ipairs(hazardFolder:GetChildren()) do
			local worldPos = getWorldPosition(hazard)
			if worldPos then
				waveMarkers[#waveMarkers + 1] = {
					alpha = alphaFromWorldPos(worldPos, WAVE_MARKER_PADDING),
					image = getHazardImage(hazard),
				}
			end
		end
	end

	root:render(ReactRoblox.createPortal(React.createElement(WaveProgressBar, {
		players = playerMarkers,
		waves = waveMarkers,
		sections = DEFAULT_SECTIONS,
		displayOrder = 118,
	}), playerGui))
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

local function bindHazardFolderSignals()
	if not hazardFolder then
		return
	end

	track(hazardFolder.ChildAdded, scheduleRender)
	track(hazardFolder.ChildRemoved, scheduleRender)
end

local function resolveWaveRefs()
	local refs = MapResolver.WaitForRefs(
		{ "WaveFolder", "WaveStart", "WaveEnd" },
		nil,
		{
			warn = true,
			context = "ReactWaveProgressBar",
		}
	)

	waveStart = refs.WaveStart
	waveEnd = refs.WaveEnd
	local waveFolder = refs.WaveFolder
	hazardFolder = waveFolder and waveFolder:FindFirstChild("Hazards")
		or waveFolder and waveFolder:FindFirstChild("ClientWaves")

	updatePath()
end

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes")
local progressBarSync = remotesFolder:FindFirstChild("ProgressBarSync") or remotesFolder:WaitForChild("ProgressBarSync")

track(progressBarSync.OnClientEvent, function(_, payload)
	orderedPlayers = typeof(payload) == "table" and payload or {}
	scheduleRender()
end)

track(Players.PlayerAdded, scheduleRender)
track(Players.PlayerRemoving, scheduleRender)
track(playerGui.DescendantAdded, function(descendant)
	if descendant.Name == "HUD" or descendant.Name == "ProgressBar" then
		task.defer(scheduleRender)
	end
end)

resolveWaveRefs()
bindHazardFolderSignals()

if waveStart then
	track(waveStart:GetPropertyChangedSignal("Position"), function()
		updatePath()
		scheduleRender()
	end)
end

if waveEnd then
	track(waveEnd:GetPropertyChangedSignal("Position"), function()
		updatePath()
		scheduleRender()
	end)
end

track(RunService.RenderStepped, function()
	scheduleRender()
end)

progressBarSync:FireServer("Request")
scheduleRender()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	root:unmount()
end)
