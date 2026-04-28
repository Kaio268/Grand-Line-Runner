local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

local function ensureUIScale(guiObject: Instance): UIScale
	local existing = guiObject:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local s = Instance.new("UIScale")
	s.Scale = 1
	s.Parent = guiObject
	return s
end

local function isAlive(inst: Instance?): boolean
	return inst ~= nil and inst.Parent ~= nil and inst:IsDescendantOf(game)
end

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local template = script:FindFirstChild("LoadingScreen") or ReplicatedFirst:WaitForChild("LoadingScreen")

local old = playerGui:FindFirstChild("LoadingScreen")
if old then
	old:Destroy()
end

local screenGui = (template :: ScreenGui):Clone()
screenGui.Name = "LoadingScreen"
screenGui.ResetOnSpawn = false
screenGui.Enabled = true
screenGui.Parent = playerGui

local root = screenGui:WaitForChild("LoadingScreen")
local rootScale = ensureUIScale(root)

local ICON_FLOAT_AMPLITUDE_PX = 10
local ICON_FLOAT_SPEED = 1.25
local ICON_NOISE_AMPLITUDE_PX = 3.5
local ICON_NOISE_SPEED = 0.75
local ICON_SCALE_BASE = 1.0
local ICON_SCALE_VARIATION = 0.03

local GRADIENT_ROTATION_TIME = 22

local FANTASY_SCALE_MIN = 0.96
local FANTASY_SCALE_MAX = 1.06
local FANTASY_SCALE_TIME = 1.8

local LOADING_TEXT_DOT_INTERVAL = 0.75
local LOADING_BREATHE_MIN = 0.985
local LOADING_BREATHE_MAX = 1.02
local LOADING_BREATHE_TIME = 0.9

local RANDOM_LABEL_INTERVAL = 3.0
local RANDOM_LABEL_FADE_TIME = 0.35
local RANDOM_LABEL_BUMP_SCALE = 1.035

local MIN_LOADING_TIME = 10

local RANDOM_MESSAGES = {
	"[Click To Spawn Brainrot]",
	"[Generating Fun...]",
	"[Warming Up The Server Hamsters]",
	"[Spawning Pixels]",
	"[Loading Chaos Module]",
	"[Preparing Your Spawn Point]",
	"[Optimizing Vibes]",
}

local barMain: GuiObject? = nil
local barMainY: UDim? = nil

do
	local bar = root:FindFirstChild("Bar")
	if bar then
		local main = bar:FindFirstChild("Main")
		if main and main:IsA("GuiObject") then
			barMain = main
			barMainY = (main :: GuiObject).Size.Y
		main.Size = UDim2.new(0, 0, (barMainY :: UDim).Scale, (barMainY :: UDim).Offset)
		end
	end
end

local function setBarProgress(p: number)
	if not barMain or not barMainY or not isAlive(barMain) then
		return
	end
	p = math.clamp(p, 0, 1)
	local y = barMainY :: UDim
	TweenService:Create(barMain :: GuiObject, TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = UDim2.new(p, 0, y.Scale, y.Offset),
	}):Play()
end

do
	local icon = root:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		local iconGui = icon :: GuiObject
		local iconScale = ensureUIScale(iconGui)
		local basePos = iconGui.Position
		local baseSize = iconGui.Size
		RunService.RenderStepped:Connect(function()
			if not isAlive(iconGui) then
				return
			end
			local t = os.clock()
			local sine = math.sin(t * math.pi * 2 * ICON_FLOAT_SPEED)
			local n = math.noise(t * ICON_NOISE_SPEED, 0, 0)
			local yOffset = (sine * ICON_FLOAT_AMPLITUDE_PX) + (n * ICON_NOISE_AMPLITUDE_PX)
			iconGui.Position = UDim2.new(basePos.X.Scale, basePos.X.Offset, basePos.Y.Scale, basePos.Y.Offset + yOffset)
			local breathe = (math.sin(t * math.pi * 2 * (ICON_FLOAT_SPEED * 0.5)) + 1) * 0.5
			local scale = ICON_SCALE_BASE + (breathe - 0.5) * 2 * ICON_SCALE_VARIATION
			iconScale.Scale = scale
			local sizeWiggle = (n * 1.0)
			iconGui.Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset + sizeWiggle, baseSize.Y.Scale, baseSize.Y.Offset + sizeWiggle)
		end)
	end
end

do
	local gradientContainer = root:FindFirstChild("Gradinet")
	if gradientContainer then
		for _, d in ipairs(gradientContainer:GetDescendants()) do
			if d:IsA("UIGradient") then
				local g = d :: UIGradient
				local startRot = g.Rotation
				local info = TweenInfo.new(GRADIENT_ROTATION_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false, 0)
				TweenService:Create(g, info, { Rotation = startRot + 360 }):Play()
			end
		end
	end
end

do
	local fantasy = root:FindFirstChild("FantasyLabIcon")
	if fantasy then
		local fantasyScale = fantasy:FindFirstChildOfClass("UIScale")
		if not fantasyScale then
			local maybe = fantasy:FindFirstChild("UIScale")
			if maybe and maybe:IsA("UIScale") then
				fantasyScale = maybe
			end
		end
		if fantasyScale and fantasyScale:IsA("UIScale") then
			local s = fantasyScale :: UIScale
			local info = TweenInfo.new(FANTASY_SCALE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0)
			s.Scale = FANTASY_SCALE_MIN
			TweenService:Create(s, info, { Scale = FANTASY_SCALE_MAX }):Play()
		end
	end
end

do
	local loadingObj = root:FindFirstChild("Loading")
	local loadingLabel: TextLabel? = nil
	if loadingObj and loadingObj:IsA("TextLabel") then
		loadingLabel = loadingObj
	elseif loadingObj then
		local t = loadingObj:FindFirstChild("Text")
		if t and t:IsA("TextLabel") then
			loadingLabel = t
		end
	end
	if loadingLabel then
		local label = loadingLabel :: TextLabel
		label.TextTransparency = 0
		local base = (label.Text ~= "" and label.Text or "Loading")
		base = base:gsub("%.+$", "")
		if base == "" then
			base = "Loading"
		end
		local labelScale = ensureUIScale(label)
		local info = TweenInfo.new(LOADING_BREATHE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0)
		labelScale.Scale = LOADING_BREATHE_MIN
		TweenService:Create(labelScale, info, { Scale = LOADING_BREATHE_MAX }):Play()
		task.spawn(function()
			local states = { base .. ".", base .. "..", base .. "..." }
			local i = 1
			while isAlive(label) do
				label.Text = states[i]
				i += 1
				if i > #states then
					i = 1
				end
				task.wait(LOADING_TEXT_DOT_INTERVAL)
			end
		end)
	end
end

do
	local randomLabel = root:FindFirstChild("TextLabel")
	if randomLabel and randomLabel:IsA("TextLabel") then
		local label = randomLabel :: TextLabel
		local scale = ensureUIScale(label)
		scale.Scale = 1
		label.TextTransparency = 0
		local rng = Random.new()
		local lastIndex = -1
		local function pickIndex(): number
			if #RANDOM_MESSAGES <= 1 then
				return 1
			end
			local idx = rng:NextInteger(1, #RANDOM_MESSAGES)
			if idx == lastIndex then
				idx = (idx % #RANDOM_MESSAGES) + 1
			end
			lastIndex = idx
			return idx
		end
		if #RANDOM_MESSAGES > 0 then
			label.Text = RANDOM_MESSAGES[pickIndex()]
		end
		task.spawn(function()
			while isAlive(label) do
				task.wait(RANDOM_LABEL_INTERVAL)
				if not isAlive(label) then
					break
				end
				local outInfo = TweenInfo.new(RANDOM_LABEL_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
				local twOut = TweenService:Create(label, outInfo, { TextTransparency = 1 })
				local twOutScale = TweenService:Create(scale, outInfo, { Scale = 0.985 })
				twOut:Play()
				twOutScale:Play()
				twOut.Completed:Wait()
				if not isAlive(label) then
					break
				end
				if #RANDOM_MESSAGES > 0 then
					label.Text = RANDOM_MESSAGES[pickIndex()]
				end
				local inInfo = TweenInfo.new(RANDOM_LABEL_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
				local twIn = TweenService:Create(label, inInfo, { TextTransparency = 0 })
				local twPop = TweenService:Create(scale, inInfo, { Scale = RANDOM_LABEL_BUMP_SCALE })
				twIn:Play()
				twPop:Play()
				twIn.Completed:Wait()
				if not isAlive(label) then
					break
				end
				local settleInfo = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
				TweenService:Create(scale, settleInfo, { Scale = 1 }):Play()
			end
		end)
	end
end

local function fadeOutAndDestroy()
	if not isAlive(screenGui) then
		return
	end
	local tweens = {}
	local fadeInfo = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	local shrinkInfo = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	for _, inst in ipairs(screenGui:GetDescendants()) do
		if inst:IsA("UIStroke") then
			table.insert(tweens, TweenService:Create(inst, fadeInfo, { Transparency = 1 }))
		elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
			table.insert(tweens, TweenService:Create(inst, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 }))
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			table.insert(tweens, TweenService:Create(inst, fadeInfo, { ImageTransparency = 1, BackgroundTransparency = 1 }))
		elseif inst:IsA("Frame") or inst:IsA("ScrollingFrame") then
			table.insert(tweens, TweenService:Create(inst, fadeInfo, { BackgroundTransparency = 1 }))
		end
	end
	table.insert(tweens, TweenService:Create(rootScale, shrinkInfo, { Scale = 0.9 }))
	for _, tw in ipairs(tweens) do tw:Play() end
	task.wait(0.68)
	if isAlive(screenGui) then
		screenGui:Destroy()
	end
end

task.spawn(function()
	setBarProgress(0)

	local preloadProgress = 0
	local preloadDone = false
	local startTime = os.clock()

	task.spawn(function()
		if not game:IsLoaded() then
			preloadProgress = 0.04
			game.Loaded:Wait()
		end

		local classes = {
			Decal = true,
			Texture = true,
			ImageLabel = true,
			ImageButton = true,
			Sound = true,
			Animation = true,
			MeshPart = true,
			SpecialMesh = true,
			FileMesh = true,
			SurfaceAppearance = true,
			MaterialVariant = true,
			ParticleEmitter = true,
			Trail = true,
			Beam = true,
			Sky = true,
			VideoFrame = true,
			Shirt = true,
			Pants = true,
			ShirtGraphic = true,
			WrapLayer = true,
			WrapTarget = true,
		}

		local list = {}
		local seen = {}

		local function shouldPreload(inst: Instance): boolean
			return classes[inst.ClassName] == true
				or inst:IsA("DataModelMesh")
				or inst:IsA("Clothing")
		end

		local function addInstance(inst: Instance): boolean
			if seen[inst] or not shouldPreload(inst) then
				return false
			end

			seen[inst] = true
			list[#list + 1] = inst
			return true
		end

		local function addFrom(container: Instance?, maxAdditional: number)
			if not container then
				return
			end

			local limit = math.max(0, math.floor(maxAdditional))
			if limit <= 0 then
				return
			end

			local added = 0
			if addInstance(container) then
				added += 1
				if added >= limit then
					return
				end
			end

			for _, inst in ipairs(container:GetDescendants()) do
				if addInstance(inst) then
					added += 1
					if added >= limit then
						return
					end
				end
			end
		end

		local function findPath(rootInstance: Instance, path)
			local node: Instance? = rootInstance
			for _, name in ipairs(path) do
				node = node and node:FindFirstChild(name)
				if not node then
					return nil
				end
			end

			return node
		end

		local priorityPaths = {
			{ "Assets" },
			{ "BrainrotFolder" },
			{ "Waves" },
			{ "Gears" },
			{ "UI" },
			{ "Particles" },
			{ "Sounds" },
			{ "Modules", "DevilFruits" },
		}

		for _, path in ipairs(priorityPaths) do
			addFrom(findPath(ReplicatedStorage, path), 12000)
		end

		addFrom(workspace, 2600)
		addFrom(ReplicatedStorage, 5000)
		addFrom(Lighting, 800)
		addFrom(StarterGui, 1600)
		addFrom(StarterPlayer, 1600)
		addFrom(root, 1200)

		local total = math.max(#list, 1)
		local loaded = 0
		preloadProgress = math.max(preloadProgress, 0.08)

		local ok = pcall(function()
			ContentProvider:PreloadAsync(list, function()
				loaded += 1
				preloadProgress = math.clamp(loaded / total, 0, 1)
			end)
		end)
		if not ok then
			preloadProgress = 1
		end
		preloadProgress = 1
		preloadDone = true
	end)

	local displayed = 0
	while isAlive(screenGui) do
		local timeProgress = math.clamp((os.clock() - startTime) / MIN_LOADING_TIME, 0, 1)
		local target = math.min(preloadProgress, timeProgress)
		displayed += (target - displayed) * 0.18
		setBarProgress(displayed)
		if preloadDone and timeProgress >= 1 then
			break
		end
		task.wait(0.05)
	end

	setBarProgress(1)
	task.wait(0.25)
	fadeOutAndDestroy()
end)
