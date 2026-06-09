local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local BiomeAreas = require(Modules:WaitForChild("Configs"):WaitForChild("BiomeAreas"))
local LavaWaves = require(Modules:WaitForChild("Configs"):WaitForChild("LavaWaves"))
local WaveHazardVisuals = require(Modules:WaitForChild("WaveHazardVisuals"))
local HudLayout = require(UiFolder:WaitForChild("HudLayout"))
local WaveProgressBar = require(UiFolder:WaitForChild("WaveProgressBar"))

local function getWaveLayout()
	return HudLayout.getWaveProgress(HudLayout.getMode())
end

local function getWaveBarHeight()
	return getWaveLayout().barHeight
end

local function getPlayerMarkerSize()
	return getWaveLayout().markerSize
end

local function getWaveMarkerSize()
	return getWaveLayout().markerSize
end

local function buildDefaultSections()
	local sections = {}
	local biomeCount = #BiomeAreas.Biomes
	local widthScale = if biomeCount > 0 then 1 / biomeCount else 1

	for index, biome in ipairs(BiomeAreas.Biomes) do
		sections[index] = {
			color = biome.ProgressColor,
			label = BiomeAreas.GetDisplayName(biome),
			widthScale = widthScale,
			isImpact = index == biomeCount,
		}
	end

	return sections
end

local DEFAULT_SECTIONS = buildDefaultSections()

local PLAYER_MARKER_PADDING = 0
local WAVE_MARKER_PADDING = 0
local WAVE_MARKER_MERGE_ALPHA = 0.018
local MARKER_UPDATE_INTERVAL = 0.125
local SCREEN_GUI_NAME = "ReactWaveProgressBar"
local ROOT_FRAME_NAME = "Root"
local PLAYER_MARKERS_FOLDER_NAME = "PlayerMarkers"
local WAVE_MARKERS_FOLDER_NAME = "WaveMarkers"

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
local shellRenderQueued = false
local destroyed = false
local legacyProgressBarHidden = false
local markerUpdateAccumulator = MARKER_UPDATE_INTERVAL
local lastShellKey = nil
local playerMarkersFolder = nil
local waveMarkersFolder = nil
local playerMarkerRecords = {}
local waveMarkerRecords = {}

local function clearMarkerRecords(records)
	for key, record in pairs(records) do
		if record.Root then
			record.Root:Destroy()
		end
		records[key] = nil
	end
end

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

local function getPredictedWavePosition(hazard)
	if not hazard then
		return nil
	end

	local startCFrame = hazard:GetAttribute("WaveStartCFrame")
	local endCFrame = hazard:GetAttribute("WaveEndCFrame")
	if typeof(startCFrame) ~= "CFrame" or typeof(endCFrame) ~= "CFrame" then
		return nil
	end

	local activeSeconds = tonumber(hazard:GetAttribute("WaveActiveSeconds")) or 0
	local stateServerTime = tonumber(hazard:GetAttribute("WaveStateServerTime"))
	if hazard:GetAttribute("Frozen") ~= true and stateServerTime then
		activeSeconds += math.max(0, workspace:GetServerTimeNow() - stateServerTime)
	end

	local currentCFrame = WaveHazardVisuals.ComputeTimelineCFrame(
		startCFrame,
		endCFrame,
		activeSeconds,
		hazard:GetAttribute("WaveServerSpeed") or hazard:GetAttribute("Speed"),
		hazard:GetAttribute("WaveDistance"),
		hazard:GetAttribute("WaveLateralDirection"),
		hazard:GetAttribute("WaveInitialLateralOffset"),
		hazard:GetAttribute("WaveLateralVelocity"),
		hazard:GetAttribute("WaveMaxDrift")
	)

	return currentCFrame and currentCFrame.Position or nil
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

local function isWaveHazard(hazard)
	if not hazard then
		return false
	end

	if LavaWaves[hazard.Name] then
		return true
	end

	local hazardType = hazard:GetAttribute("HazardType")
	if typeof(hazardType) == "string" then
		return string.lower(hazardType) == "wave"
	end

	return false
end

local function shouldMergeWaveMarker(existingMarkers, alpha, image)
	for _, markerInfo in ipairs(existingMarkers) do
		if markerInfo.image == image and math.abs((tonumber(markerInfo.alpha) or 0) - alpha) <= WAVE_MARKER_MERGE_ALPHA then
			return true
		end
	end

	return false
end

local function hideLegacyProgressBar()
	if legacyProgressBarHidden then
		return
	end

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

	progressBar:SetAttribute("ReactWaveProgressHidden", true)
	legacyProgressBarHidden = true
end

local function getShellKey()
	local layout = getWaveLayout()
	return table.concat({
		tostring(layout.compact == true),
		tostring(layout.barHeight),
		tostring(layout.markerSize),
		tostring(layout.rootWidth),
		tostring(layout.maxWidth),
		tostring(layout.minWidth),
		tostring(layout.topOffset),
	}, "|")
end

local function resolveMarkerFolders()
	local screenGui = playerGui:FindFirstChild(SCREEN_GUI_NAME)
	local rootFrame = screenGui and screenGui:FindFirstChild(ROOT_FRAME_NAME)
	playerMarkersFolder = rootFrame and rootFrame:FindFirstChild(PLAYER_MARKERS_FOLDER_NAME) or nil
	waveMarkersFolder = rootFrame and rootFrame:FindFirstChild(WAVE_MARKERS_FOLDER_NAME) or nil
	return playerMarkersFolder ~= nil and waveMarkersFolder ~= nil
end

local function renderShell(force)
	hideLegacyProgressBar()

	local shellKey = getShellKey()
	if force ~= true and shellKey == lastShellKey and resolveMarkerFolders() then
		return true
	end

	lastShellKey = shellKey
	clearMarkerRecords(playerMarkerRecords)
	clearMarkerRecords(waveMarkerRecords)
	playerMarkersFolder = nil
	waveMarkersFolder = nil
	root:render(ReactRoblox.createPortal(React.createElement(WaveProgressBar, {
		barHeight = getWaveBarHeight(),
		compact = getWaveLayout().compact == true,
		players = {},
		waves = {},
		sections = DEFAULT_SECTIONS,
		displayOrder = 118,
		layout = getWaveLayout(),
	}), playerGui))

	return resolveMarkerFolders()
end

local function scheduleShellRender(force)
	if shellRenderQueued or destroyed then
		return
	end

	shellRenderQueued = true
	task.defer(function()
		shellRenderQueued = false
		if not destroyed then
			renderShell(force)
		end
	end)
end

local function addCircle(parent, color, transparency, strokeColor, strokeTransparency, zIndex)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = zIndex
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = strokeColor
	stroke.Transparency = strokeTransparency
	stroke.Thickness = 1.5
	stroke.Parent = frame

	return frame, stroke
end

local function createPlayerMarker(key)
	local frame = Instance.new("Frame")
	frame.Name = "Player_" .. key
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromScale(0, 0.5)
	frame.Size = UDim2.fromOffset(getPlayerMarkerSize(), getPlayerMarkerSize())
	frame.ZIndex = 8

	local backdrop, stroke = addCircle(
		frame,
		Color3.fromRGB(21, 27, 41),
		0,
		Color3.fromRGB(223, 236, 255),
		0.08,
		8
	)

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.ZIndex = 8
	image.Parent = backdrop

	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(1, 0)
	imageCorner.Parent = image

	local skull = Instance.new("TextLabel")
	skull.Name = "Skull"
	skull.AnchorPoint = Vector2.new(0.5, 0.5)
	skull.BackgroundTransparency = 1
	skull.Font = Enum.Font.GothamBlack
	skull.Position = UDim2.fromScale(0.5, 0.5)
	skull.Size = UDim2.fromScale(1, 1)
	skull.Text = "X"
	skull.TextColor3 = Color3.fromRGB(255, 244, 244)
	skull.TextSize = 18
	skull.TextStrokeColor3 = Color3.fromRGB(62, 18, 18)
	skull.TextStrokeTransparency = 0.2
	skull.Visible = false
	skull.ZIndex = 9
	skull.Parent = backdrop

	return {
		Root = frame,
		Backdrop = backdrop,
		Stroke = stroke,
		Image = image,
		Skull = skull,
		Dead = false,
		ImageId = "",
		Size = 0,
	}
end

local function createWaveMarker(key)
	local frame = Instance.new("Frame")
	frame.Name = "Wave_" .. key
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromScale(0, 0.5)
	frame.Size = UDim2.fromOffset(getWaveMarkerSize(), getWaveMarkerSize())
	frame.ZIndex = 9

	local icon, stroke = addCircle(
		frame,
		Color3.fromRGB(20, 24, 34),
		0.05,
		Color3.fromRGB(255, 196, 150),
		0.25,
		9
	)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.BackgroundTransparency = 1
	image.ImageColor3 = Color3.new(1, 1, 1)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.ScaleType = Enum.ScaleType.Fit
	image.Size = UDim2.fromScale(0.72, 0.72)
	image.ZIndex = 10
	image.Parent = icon

	return {
		Root = frame,
		Stroke = stroke,
		Image = image,
		ImageId = "",
		Size = 0,
	}
end

local function setMarkerSize(record, size)
	size = math.max(1, tonumber(size) or 1)
	if record.Size == size then
		return
	end

	record.Size = size
	record.Root.Size = UDim2.fromOffset(size, size)
end

local function updatePlayerMarker(record, markerInfo)
	local userId = tonumber(markerInfo.userId) or 0
	local image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
	if record.ImageId ~= image then
		record.ImageId = image
		record.Image.Image = image
	end

	local dead = markerInfo.isDead == true
	if record.Dead ~= dead then
		record.Dead = dead
		record.Backdrop.BackgroundColor3 = dead and Color3.fromRGB(72, 41, 49) or Color3.fromRGB(21, 27, 41)
		record.Stroke.Color = dead and Color3.fromRGB(255, 128, 128) or Color3.fromRGB(223, 236, 255)
		record.Skull.Visible = dead
	end

	setMarkerSize(record, markerInfo.size)
	record.Root.Position = UDim2.fromScale(tonumber(markerInfo.alpha) or 0, 0.5)
end

local function updateWaveMarker(record, markerInfo)
	local image = tostring(markerInfo.image or "")
	if record.ImageId ~= image then
		record.ImageId = image
		record.Image.Image = image
	end

	setMarkerSize(record, markerInfo.size)
	record.Root.Position = UDim2.fromScale(tonumber(markerInfo.alpha) or 0, 0.5)
end

local function collectPlayerMarkers()
	local playerMarkers = {}
	local seen = {}
	for _, info in ipairs(orderedPlayers) do
		local userId = tonumber(info.UserId) or 0
		if userId <= 0 or seen[userId] then
			continue
		end
		seen[userId] = true

		local listedPlayer = Players:GetPlayerByUserId(userId)
		local character = listedPlayer and listedPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local alpha = 0
		if rootPart then
			alpha = alphaFromWorldPos(rootPart.Position, PLAYER_MARKER_PADDING)
		end

		playerMarkers[#playerMarkers + 1] = {
			key = tostring(userId),
			alpha = alpha,
			userId = userId,
			isDead = humanoid ~= nil and humanoid.Health <= 0,
			size = getPlayerMarkerSize(),
		}
	end

	return playerMarkers
end

local function collectWaveMarkers()
	local waveMarkers = {}
	if hazardFolder and hazardFolder.Parent then
		for _, hazard in ipairs(hazardFolder:GetChildren()) do
			local worldPos = isWaveHazard(hazard) and (getPredictedWavePosition(hazard) or getWorldPosition(hazard)) or nil
			if worldPos then
				local alpha = alphaFromWorldPos(worldPos, WAVE_MARKER_PADDING)
				local image = getHazardImage(hazard)
				if shouldMergeWaveMarker(waveMarkers, alpha, image) then
					continue
				end

				waveMarkers[#waveMarkers + 1] = {
					key = tostring(#waveMarkers + 1),
					alpha = alpha,
					image = image,
					size = getWaveMarkerSize(),
				}
			end
		end
	end

	return waveMarkers
end

local function syncMarkerRecords(folder, records, markerInfos, createRecord, updateRecord)
	if not folder then
		return
	end

	local seen = {}
	for _, markerInfo in ipairs(markerInfos) do
		local key = tostring(markerInfo.key or "")
		if key == "" then
			continue
		end

		seen[key] = true
		local record = records[key]
		if not record then
			record = createRecord(key)
			record.Root.Parent = folder
			records[key] = record
		elseif record.Root.Parent ~= folder then
			record.Root.Parent = folder
		end

		updateRecord(record, markerInfo)
	end

	for key, record in pairs(records) do
		if not seen[key] then
			if record.Root then
				record.Root:Destroy()
			end
			records[key] = nil
		end
	end
end

local function updateMarkers()
	if destroyed then
		return
	end
	if not renderShell(false) then
		return
	end

	syncMarkerRecords(
		playerMarkersFolder,
		playerMarkerRecords,
		collectPlayerMarkers(),
		createPlayerMarker,
		updatePlayerMarker
	)
	syncMarkerRecords(
		waveMarkersFolder,
		waveMarkerRecords,
		collectWaveMarkers(),
		createWaveMarker,
		updateWaveMarker
	)
end

local function requestMarkerUpdate()
	markerUpdateAccumulator = MARKER_UPDATE_INTERVAL
end

local function bindHazardFolderSignals()
	if not hazardFolder then
		return
	end

	track(hazardFolder.ChildAdded, requestMarkerUpdate)
	track(hazardFolder.ChildRemoved, requestMarkerUpdate)
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
	requestMarkerUpdate()
end)

track(Players.PlayerAdded, requestMarkerUpdate)
track(Players.PlayerRemoving, requestMarkerUpdate)
track(playerGui.DescendantAdded, function(descendant)
	if descendant.Name == "HUD" or descendant.Name == "ProgressBar" then
		legacyProgressBarHidden = false
		scheduleShellRender(true)
		requestMarkerUpdate()
	end
end)

track(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
	scheduleShellRender(true)
	requestMarkerUpdate()
end)

resolveWaveRefs()
bindHazardFolderSignals()

if waveStart then
	track(waveStart:GetPropertyChangedSignal("Position"), function()
		updatePath()
		requestMarkerUpdate()
	end)
end

if waveEnd then
	track(waveEnd:GetPropertyChangedSignal("Position"), function()
		updatePath()
		requestMarkerUpdate()
	end)
end

track(RunService.Heartbeat, function(deltaTime)
	markerUpdateAccumulator += deltaTime
	if markerUpdateAccumulator >= MARKER_UPDATE_INTERVAL then
		markerUpdateAccumulator = 0
		updateMarkers()
	end
end)

progressBarSync:FireServer("Request")
scheduleShellRender(true)
requestMarkerUpdate()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	table.clear(playerMarkerRecords)
	table.clear(waveMarkerRecords)
	root:unmount()
	rootContainer:Destroy()
end)
