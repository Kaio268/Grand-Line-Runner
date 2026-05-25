local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local PLAYER_GUI_TIMEOUT_SECONDS = 5
local MIN_DISPLAY_SECONDS = 2.5
local CRITICAL_PRELOAD_TIMEOUT_SECONDS = 8
local MAX_LOADING_SCREEN_SECONDS = 15
local EMERGENCY_WATCHDOG_SECONDS = 30
local REACT_HYDRATION_TIMEOUT_SECONDS = 5
local REACT_RENDER_THROTTLE_SECONDS = 0.08

local LOADING_SCREEN_ACTIVE_ATTRIBUTE = "LoadingScreenActive"
local LOADING_SCREEN_COMPLETE_ATTRIBUTE = "LoadingScreenComplete"
local STARTUP_LOADING_STARTED_AT_ATTRIBUTE = "StartupLoadingStartedAt"
local STARTUP_SHELL_READY_ATTRIBUTE = "StartupShellReady"
local STARTUP_DATA_REQUEST_SENT_ATTRIBUTE = "StartupDataRequestSent"
local STARTUP_HUD_READY_ATTRIBUTE = "StartupHudReady"
local STARTUP_CHARACTER_OBSERVED_ATTRIBUTE = "StartupCharacterObserved"
local STARTUP_CRITICAL_ASSETS_READY_ATTRIBUTE = "StartupCriticalAssetsReady"
local STARTUP_CRITICAL_ASSETS_TIMED_OUT_ATTRIBUTE = "StartupCriticalAssetsTimedOut"
local STARTUP_LOADING_TIMED_OUT_ATTRIBUTE = "StartupLoadingTimedOut"
local STARTUP_BACKGROUND_PRELOAD_COMPLETE_ATTRIBUTE = "StartupBackgroundPreloadComplete"

local FALLBACK_DISPLAY_ORDER = 10000
local SOURCE_TEMPLATE_STYLE_MARKER = "UseLoadingScreenDefaultStyle"
local BACKGROUND_IMAGE_ASSET = "rbxassetid://124045609313388"
local LOGO_IMAGE_ASSET = "rbxassetid://71230597644796"

local LOADING_TEXT_DOT_INTERVAL = 0.72
local LOADING_BREATHE_TIME = 1
local STATUS_MESSAGE_INTERVAL = 3
local TIP_MESSAGE_INTERVAL = 5.5
local MESSAGE_FADE_TIME = 0.28
local GRADIENT_ROTATION_TIME = 26

local HUD_ICON_ASSET_IDS = {
	"rbxassetid://108512951338844",
	"rbxassetid://76300573750363",
}

local CRITICAL_ASSET_IDS = {
	BACKGROUND_IMAGE_ASSET,
	LOGO_IMAGE_ASSET,
	HUD_ICON_ASSET_IDS[1],
	HUD_ICON_ASSET_IDS[2],
}

local STATUS_MESSAGES = {
	"Charting the next tide",
	"Preparing your crew",
	"Hoisting the colors",
	"Checking the harbor routes",
	"Priming Devil Fruit powers",
	"Stacking treasure chests",
	"Scouting deeper corridors",
}

local TIP_MESSAGES = {
	"Tip: Push deeper for better rewards, but extract before the run turns against you.",
	"Tip: Upgrade your ship to sail farther and unlock tougher routes.",
	"Tip: A stronger crew turns risky corridors into richer runs.",
	"Tip: Devil Fruit powers can change the rhythm of a run when timing matters.",
	"Tip: Chest progression rewards players who balance speed, safety, and greed.",
	"Tip: Corridor depth raises the stakes, the danger, and the payout.",
	"Tip: Skillful movement keeps your treasure safe when the tide turns.",
}

local PRELOADABLE_CLASSES = {
	Animation = true,
	Beam = true,
	Decal = true,
	FileMesh = true,
	ImageButton = true,
	ImageLabel = true,
	MaterialVariant = true,
	MeshPart = true,
	ParticleEmitter = true,
	Shirt = true,
	ShirtGraphic = true,
	Sky = true,
	Sound = true,
	SpecialMesh = true,
	SurfaceAppearance = true,
	Texture = true,
	Trail = true,
	VideoFrame = true,
	WrapLayer = true,
	WrapTarget = true,
}

local BACKGROUND_PRELOAD_BATCHES = {
	{
		Name = "hud_icons",
		AssetIds = HUD_ICON_ASSET_IDS,
		Limit = 8,
	},
	{
		Name = "react_ui",
		Paths = {
			{ "UI" },
		},
		Limit = 80,
	},
	{
		Name = "crew_preview_images",
		Paths = {
			{ "Modules", "Crew", "CrewPreviewImages" },
		},
		Limit = 50,
	},
	{
		Name = "sounds",
		Paths = {
			{ "Sounds" },
		},
		Limit = 24,
	},
	{
		Name = "particles",
		Paths = {
			{ "Particles" },
		},
		Limit = 40,
	},
	{
		Name = "first_assets",
		Paths = {
			{ "Assets" },
		},
		Limit = 60,
	},
}

local function removeDefaultLoadingScreen()
	pcall(function()
		ReplicatedFirst:RemoveDefaultLoadingScreen()
	end)
end

local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", PLAYER_GUI_TIMEOUT_SECONDS)
if not playerGui then
	warn(string.format(
		"[LoadingScreen] PlayerGui was not available for %s(%d) after %.1fs; keeping the Roblox default loading screen.",
		player.Name,
		player.UserId,
		PLAYER_GUI_TIMEOUT_SECONDS
	))
	return
end

local function setStartupAttribute(attributeName: string, value: any)
	if playerGui and playerGui.Parent then
		playerGui:SetAttribute(attributeName, value)
	end
end

local function isStartupAttributeTrue(attributeName: string): boolean
	return playerGui:GetAttribute(attributeName) == true
end

setStartupAttribute(LOADING_SCREEN_ACTIVE_ATTRIBUTE, true)
setStartupAttribute(LOADING_SCREEN_COMPLETE_ATTRIBUTE, false)
setStartupAttribute(STARTUP_LOADING_STARTED_AT_ATTRIBUTE, os.clock())

local function isAlive(inst: Instance?): boolean
	return inst ~= nil and inst.Parent ~= nil and inst:IsDescendantOf(game)
end

local function ensureChild(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

local function ensureUIScale(guiObject: Instance): UIScale
	local existing = guiObject:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = guiObject
	return scale
end

local function ensureCorner(parent: Instance, radius: number)
	local corner = parent:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function ensureStroke(parent: Instance, color: Color3, thickness: number, transparency: number)
	local stroke = parent:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.Parent = parent
	return stroke
end

local function ensureGradient(parent: Instance, name: string, color: ColorSequence, transparency: NumberSequence?, rotation: number?)
	local gradient = parent:FindFirstChild(name)
	if not gradient or not gradient:IsA("UIGradient") then
		if gradient then
			gradient:Destroy()
		end
		gradient = Instance.new("UIGradient")
		gradient.Name = name
		gradient.Parent = parent
	end

	gradient.Color = color
	gradient.Rotation = rotation or 0
	if transparency then
		gradient.Transparency = transparency
	end
	return gradient
end

local function ensureTextConstraint(label: TextLabel, minSize: number, maxSize: number)
	label.TextScaled = true
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
	return constraint
end

local function styleLoadingTextLabel(label: TextLabel, text: string, maxTextSize: number, position: UDim2, size: UDim2)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextColor3 = Color3.fromRGB(248, 246, 238)
	label.TextSize = maxTextSize
	label.TextStrokeColor3 = Color3.fromRGB(24, 14, 10)
	label.TextStrokeTransparency = 0.3
	label.TextWrapped = true
	label.ZIndex = 8
	ensureTextConstraint(label, 12, maxTextSize)
end

local function applyDefaultLoadingScreenStyle(screenGui: ScreenGui, root: GuiObject)
	screenGui.DisplayOrder = math.max(screenGui.DisplayOrder, FALLBACK_DISPLAY_ORDER)
	screenGui.Enabled = true
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	root.BackgroundColor3 = Color3.fromRGB(10, 9, 13)
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Position = UDim2.fromScale(0, 0)
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 1

	local background = ensureChild(root, "ImageLabel", "Background") :: ImageLabel
	background.BackgroundTransparency = 1
	background.BorderSizePixel = 0
	background.Image = BACKGROUND_IMAGE_ASSET
	background.ImageColor3 = Color3.fromRGB(255, 238, 218)
	background.ImageTransparency = 0
	background.Position = UDim2.fromScale(0, 0)
	background.ScaleType = Enum.ScaleType.Crop
	background.Size = UDim2.fromScale(1, 1)
	background.ZIndex = 1

	local gradientHost = ensureChild(root, "Frame", "Gradinet") :: Frame
	gradientHost.BackgroundTransparency = 1
	gradientHost.BorderSizePixel = 0
	gradientHost.Position = UDim2.fromScale(0, 0)
	gradientHost.Size = UDim2.fromScale(1, 1)
	gradientHost.ZIndex = 2

	local warmBloom = ensureChild(gradientHost, "Frame", "WarmBloom") :: Frame
	warmBloom.AnchorPoint = Vector2.new(0.5, 0.5)
	warmBloom.BackgroundColor3 = Color3.fromRGB(255, 178, 72)
	warmBloom.BackgroundTransparency = 0.78
	warmBloom.BorderSizePixel = 0
	warmBloom.Position = UDim2.fromScale(0.62, 0.34)
	warmBloom.Rotation = -8
	warmBloom.Size = UDim2.fromScale(0.72, 0.58)
	warmBloom.ZIndex = 2
	ensureCorner(warmBloom, 36)
	ensureGradient(warmBloom, "WarmBloomGradient", ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 122)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 133, 54)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(43, 116, 190)),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.92),
		NumberSequenceKeypoint.new(0.45, 0.26),
		NumberSequenceKeypoint.new(1, 0.96),
	}), 18)

	local lowerShade = ensureChild(root, "Frame", "Vignette") :: Frame
	lowerShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	lowerShade.BackgroundTransparency = 0.06
	lowerShade.BorderSizePixel = 0
	lowerShade.Position = UDim2.fromScale(0, 0)
	lowerShade.Size = UDim2.fromScale(1, 1)
	lowerShade.ZIndex = 3
	ensureGradient(lowerShade, "VignetteGradient", ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.34, 0.72),
		NumberSequenceKeypoint.new(0.62, 0.64),
		NumberSequenceKeypoint.new(1, 0.08),
	}), 90)

	local cinematicShade = ensureChild(root, "Frame", "CinematicShade") :: Frame
	cinematicShade.BackgroundColor3 = Color3.fromRGB(12, 8, 10)
	cinematicShade.BackgroundTransparency = 0.42
	cinematicShade.BorderSizePixel = 0
	cinematicShade.Position = UDim2.fromScale(0, 0)
	cinematicShade.Size = UDim2.fromScale(1, 1)
	cinematicShade.ZIndex = 4
	ensureGradient(cinematicShade, "CinematicGradient", ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 10, 22)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 6, 7)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42),
		NumberSequenceKeypoint.new(0.52, 0.8),
		NumberSequenceKeypoint.new(1, 0.24),
	}), 90)

	local loading = ensureChild(root, "TextLabel", "Loading") :: TextLabel
	styleLoadingTextLabel(loading, "Loading...", 34, UDim2.fromScale(0.5, 0.64), UDim2.fromScale(0.5, 0.055))
	loading.Font = Enum.Font.GothamBlack

	local status = ensureChild(root, "TextLabel", "TextLabel") :: TextLabel
	styleLoadingTextLabel(status, STATUS_MESSAGES[1], 24, UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.7, 0.045))
	status.TextColor3 = Color3.fromRGB(255, 214, 95)

	local bar = ensureChild(root, "Frame", "Bar") :: Frame
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.BackgroundColor3 = Color3.fromRGB(19, 15, 18)
	bar.BackgroundTransparency = 0.12
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromScale(0.5, 0.77)
	bar.Size = UDim2.new(0.54, 0, 0, 18)
	bar.ZIndex = 8
	ensureCorner(bar, 9)
	ensureStroke(bar, Color3.fromRGB(255, 190, 65), 1.6, 0.18)
	local barConstraint = bar:FindFirstChildOfClass("UISizeConstraint") or Instance.new("UISizeConstraint")
	barConstraint.MaxSize = Vector2.new(760, 18)
	barConstraint.MinSize = Vector2.new(260, 12)
	barConstraint.Parent = bar

	local main = ensureChild(bar, "Frame", "Main") :: Frame
	main.BackgroundColor3 = Color3.fromRGB(255, 191, 58)
	main.BorderSizePixel = 0
	main.Position = UDim2.fromScale(0, 0)
	main.Size = UDim2.fromScale(0, 1)
	main.ZIndex = 9
	ensureCorner(main, 9)
	ensureGradient(main, "MainGradient", ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 217, 91)),
		ColorSequenceKeypoint.new(0.56, Color3.fromRGB(255, 174, 47)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(83, 198, 111)),
	}), nil, 0)

	local tip = ensureChild(root, "TextLabel", "Tip") :: TextLabel
	styleLoadingTextLabel(tip, TIP_MESSAGES[1], 22, UDim2.fromScale(0.5, 0.86), UDim2.fromScale(0.76, 0.055))
	tip.Font = Enum.Font.GothamMedium
	tip.TextColor3 = Color3.fromRGB(250, 245, 230)
	tip.TextStrokeTransparency = 0.45
end

local function createFallbackLoadingScreen(): (ScreenGui, GuiObject)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LoadingScreen"

	local root = Instance.new("Frame")
	root.Name = "LoadingScreen"
	root.Parent = screenGui

	applyDefaultLoadingScreenStyle(screenGui, root)
	screenGui.Parent = playerGui
	return screenGui, root
end

local function findLoadingTemplate(): Instance?
	return script:FindFirstChild("LoadingScreen") or ReplicatedFirst:FindFirstChild("LoadingScreen")
end

local function mountLoadingScreen(): (ScreenGui, GuiObject)
	local old = playerGui:FindFirstChild("LoadingScreen")
	if old then
		old:Destroy()
	end

	local template = findLoadingTemplate()
	if template and template:IsA("ScreenGui") then
		local cloned = template:Clone()
		cloned.Name = "LoadingScreen"
		cloned.DisplayOrder = math.max(cloned.DisplayOrder, FALLBACK_DISPLAY_ORDER)
		cloned.Enabled = true
		cloned.IgnoreGuiInset = true
		cloned.ResetOnSpawn = false
		cloned.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

		local root = cloned:FindFirstChild("LoadingScreen")
		if root and root:IsA("GuiObject") then
			if cloned:FindFirstChild(SOURCE_TEMPLATE_STYLE_MARKER) then
				applyDefaultLoadingScreenStyle(cloned, root)
			end
			cloned.Parent = playerGui
			return cloned, root
		end

		warn("[LoadingScreen] LoadingScreen template had no GuiObject root named LoadingScreen; using source fallback shell.")
		cloned:Destroy()
	elseif template then
		warn(string.format(
			"[LoadingScreen] LoadingScreen template was %s instead of ScreenGui; using source fallback shell.",
			template.ClassName
		))
	else
		warn("[LoadingScreen] LoadingScreen template was not found in ReplicatedFirst; using source fallback shell.")
	end

	return createFallbackLoadingScreen()
end

local screenGui, root = mountLoadingScreen()
removeDefaultLoadingScreen()
local rootScale = ensureUIScale(root)
local statusLabel: TextLabel? = nil
local tipLabel: TextLabel? = nil
local statusOverride: string? = nil
local barMain: GuiObject? = nil
local barMainY: UDim? = nil

local loadingState = {
	backgroundImage = BACKGROUND_IMAGE_ASSET,
	logoImage = LOGO_IMAGE_ASSET,
	phase = "Starting",
	progress = 0,
	statusMessage = STATUS_MESSAGES[1],
	timedOut = false,
	tip = TIP_MESSAGES[1],
}

local reactContext = nil
local reactHydrationFailed = false
local fallbackVisualsHidden = false
local lastReactRenderAt = 0

local function setFallbackVisualsVisible(visible: boolean)
	if root and root:IsA("GuiObject") and isAlive(root) then
		root.Visible = visible
	end
	fallbackVisualsHidden = not visible
end

local function renderReactLoading(force: boolean?)
	if not reactContext or not isAlive(screenGui) then
		return
	end

	local now = os.clock()
	if not force and now - lastReactRenderAt < REACT_RENDER_THROTTLE_SECONDS then
		return
	end
	lastReactRenderAt = now

	local ok, err = pcall(function()
		local React = reactContext.React
		local ReactRoblox = reactContext.ReactRoblox
		reactContext.Root:render(ReactRoblox.createPortal(React.createElement(reactContext.Component, {
			backgroundImage = loadingState.backgroundImage,
			logoImage = loadingState.logoImage,
			phase = loadingState.phase,
			progress = loadingState.progress,
			statusMessage = loadingState.statusMessage,
			timedOut = loadingState.timedOut,
			tip = loadingState.tip,
		}), screenGui))
	end)

	if not ok then
		reactHydrationFailed = true
		if fallbackVisualsHidden then
			setFallbackVisualsVisible(true)
		end
		warn(string.format("[LoadingScreen] React loading screen render failed; continuing with fallback shell: %s", tostring(err)))
		if reactContext then
			pcall(function()
				reactContext.Root:unmount()
			end)
			if reactContext.Container then
				reactContext.Container:Destroy()
			end
			reactContext = nil
		end
	elseif not fallbackVisualsHidden then
		setFallbackVisualsVisible(false)
	end
end

local function setLoadingState(patch: {[string]: any}, forceReact: boolean?)
	for key, value in pairs(patch) do
		loadingState[key] = value
	end
	renderReactLoading(forceReact)
end

local function waitForChildBounded(parent: Instance, childName: string, timeoutSeconds: number): Instance?
	local existing = parent:FindFirstChild(childName)
	if existing then
		return existing
	end

	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline and isAlive(screenGui) do
		existing = parent:FindFirstChild(childName)
		if existing then
			return existing
		end
		task.wait(0.05)
	end

	return nil
end

local function startReactHydration()
	task.spawn(function()
		local startedAt = os.clock()
		local packages = waitForChildBounded(ReplicatedStorage, "Packages", REACT_HYDRATION_TIMEOUT_SECONDS)
		local uiFolder = waitForChildBounded(ReplicatedStorage, "UI", math.max(0.1, REACT_HYDRATION_TIMEOUT_SECONDS - (os.clock() - startedAt)))
		if not packages or not uiFolder then
			reactHydrationFailed = true
			warn("[LoadingScreen] React hydration skipped; ReplicatedStorage packages/UI were not ready in time.")
			return
		end

		local remaining = math.max(0.1, REACT_HYDRATION_TIMEOUT_SECONDS - (os.clock() - startedAt))
		local reactModule = waitForChildBounded(packages, "React", remaining)
		remaining = math.max(0.1, REACT_HYDRATION_TIMEOUT_SECONDS - (os.clock() - startedAt))
		local reactRobloxModule = waitForChildBounded(packages, "ReactRoblox", remaining)
		remaining = math.max(0.1, REACT_HYDRATION_TIMEOUT_SECONDS - (os.clock() - startedAt))
		local loadingFolder = waitForChildBounded(uiFolder, "Loading", remaining)
		local loadingModule = loadingFolder and waitForChildBounded(loadingFolder, "LoadingScreen", math.max(0.1, REACT_HYDRATION_TIMEOUT_SECONDS - (os.clock() - startedAt)))
		if not reactModule or not reactRobloxModule or not loadingModule then
			reactHydrationFailed = true
			warn("[LoadingScreen] React hydration skipped; loading component dependencies were not ready in time.")
			return
		end

		local okReact, React = pcall(require, reactModule)
		local okReactRoblox, ReactRoblox = pcall(require, reactRobloxModule)
		local okComponent, LoadingScreenComponent = pcall(require, loadingModule)
		if not okReact or not okReactRoblox or not okComponent then
			reactHydrationFailed = true
			warn(string.format(
				"[LoadingScreen] React hydration failed; continuing with fallback shell. React=%s ReactRoblox=%s Component=%s",
				tostring(React),
				tostring(ReactRoblox),
				tostring(LoadingScreenComponent)
			))
			return
		end

		if not isAlive(screenGui) then
			return
		end

		local rootContainer = Instance.new("Folder")
		rootContainer.Name = "ReactLoadingScreenRoot"
		rootContainer.Parent = screenGui

		reactContext = {
			React = React,
			ReactRoblox = ReactRoblox,
			Component = LoadingScreenComponent,
			Root = ReactRoblox.createRoot(rootContainer),
			Container = rootContainer,
		}
		renderReactLoading(true)
	end)
end

setStartupAttribute(STARTUP_SHELL_READY_ATTRIBUTE, true)
setStartupAttribute(STARTUP_CRITICAL_ASSETS_READY_ATTRIBUTE, false)
setStartupAttribute(STARTUP_CRITICAL_ASSETS_TIMED_OUT_ATTRIBUTE, false)
setStartupAttribute(STARTUP_LOADING_TIMED_OUT_ATTRIBUTE, false)
setStartupAttribute(STARTUP_BACKGROUND_PRELOAD_COMPLETE_ATTRIBUTE, false)
setStartupAttribute(STARTUP_CHARACTER_OBSERVED_ATTRIBUTE, player.Character ~= nil)

local characterConnection = player.CharacterAdded:Connect(function()
	setStartupAttribute(STARTUP_CHARACTER_OBSERVED_ATTRIBUTE, true)
end)

do
	local bar = root:FindFirstChild("Bar")
	if bar then
		local main = bar:FindFirstChild("Main")
		if main and main:IsA("GuiObject") then
			barMain = main
			barMainY = main.Size.Y
			main.Size = UDim2.new(0, 0, barMainY.Scale, barMainY.Offset)
		end
	end
end

local function setFallbackBarProgress(progress: number)
	if not barMain or not barMainY or not isAlive(barMain) then
		return
	end

	local clamped = math.clamp(progress, 0, 1)
	local y = barMainY :: UDim
	TweenService:Create(barMain :: GuiObject, TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = UDim2.new(clamped, 0, y.Scale, y.Offset),
	}):Play()
end

local function setDisplayedProgress(progress: number)
	local clamped = math.clamp(progress, 0, 1)
	setLoadingState({
		progress = clamped,
	})
	setFallbackBarProgress(clamped)
end

local function setStatusMessage(message: string, forceReact: boolean?)
	if statusOverride ~= nil and message ~= statusOverride then
		return
	end

	if statusLabel and isAlive(statusLabel) then
		statusLabel.Text = message
		statusLabel.TextTransparency = 0
	end
	setLoadingState({
		statusMessage = message,
	}, forceReact)
end

local function setTipMessage(message: string, forceReact: boolean?)
	if tipLabel and isAlive(tipLabel) then
		tipLabel.Text = message
		tipLabel.TextTransparency = 0
	end
	setLoadingState({
		tip = message,
	}, forceReact)
end

local function setStatusOverride(message: string)
	statusOverride = message
	setStatusMessage(message, true)
end

startReactHydration()

do
	local gradientContainer = root:FindFirstChild("Gradinet")
	if gradientContainer then
		for _, descendant in ipairs(gradientContainer:GetDescendants()) do
			if descendant:IsA("UIGradient") then
				local gradient = descendant
				local startRotation = gradient.Rotation
				TweenService:Create(gradient, TweenInfo.new(GRADIENT_ROTATION_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
					Rotation = startRotation + 360,
				}):Play()
			end
		end
	end
end

do
	local loadingObj = root:FindFirstChild("Loading")
	if loadingObj and loadingObj:IsA("TextLabel") then
		local label = loadingObj
		local labelScale = ensureUIScale(label)
		label.TextTransparency = 0
		TweenService:Create(labelScale, TweenInfo.new(LOADING_BREATHE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Scale = 1.025,
		}):Play()

		task.spawn(function()
			local states = { "Loading.", "Loading..", "Loading..." }
			local index = 1
			while isAlive(label) do
				label.Text = states[index]
				index += 1
				if index > #states then
					index = 1
				end
				task.wait(LOADING_TEXT_DOT_INTERVAL)
			end
		end)
	end
end

do
	local randomLabel = root:FindFirstChild("TextLabel")
	if randomLabel and randomLabel:IsA("TextLabel") then
		statusLabel = randomLabel
		local scale = ensureUIScale(randomLabel)
		local rng = Random.new()
		local lastIndex = -1

		local function pickIndex(): number
			if #STATUS_MESSAGES <= 1 then
				return 1
			end

			local index = rng:NextInteger(1, #STATUS_MESSAGES)
			if index == lastIndex then
				index = (index % #STATUS_MESSAGES) + 1
			end
			lastIndex = index
			return index
		end

		setStatusMessage(STATUS_MESSAGES[pickIndex()], true)
		scale.Scale = 1

		task.spawn(function()
			while isAlive(randomLabel) do
				task.wait(STATUS_MESSAGE_INTERVAL)
				if not isAlive(randomLabel) or statusOverride ~= nil then
					continue
				end

				local outInfo = TweenInfo.new(MESSAGE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
				local twOut = TweenService:Create(randomLabel, outInfo, { TextTransparency = 1 })
				twOut:Play()
				twOut.Completed:Wait()
				if not isAlive(randomLabel) or statusOverride ~= nil then
					continue
				end

				setStatusMessage(STATUS_MESSAGES[pickIndex()], true)
				local inInfo = TweenInfo.new(MESSAGE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
				TweenService:Create(randomLabel, inInfo, { TextTransparency = 0 }):Play()
				TweenService:Create(scale, inInfo, { Scale = 1.025 }):Play()
				task.delay(MESSAGE_FADE_TIME, function()
					if isAlive(scale) then
						TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
							Scale = 1,
						}):Play()
					end
				end)
			end
		end)
	end
end

do
	local tipObj = root:FindFirstChild("Tip")
	if tipObj and tipObj:IsA("TextLabel") then
		tipLabel = tipObj
		local rng = Random.new()
		local lastIndex = -1

		local function pickIndex(): number
			if #TIP_MESSAGES <= 1 then
				return 1
			end

			local index = rng:NextInteger(1, #TIP_MESSAGES)
			if index == lastIndex then
				index = (index % #TIP_MESSAGES) + 1
			end
			lastIndex = index
			return index
		end

		setTipMessage(TIP_MESSAGES[pickIndex()], true)
		task.spawn(function()
			while isAlive(tipObj) do
				task.wait(TIP_MESSAGE_INTERVAL)
				if not isAlive(tipObj) then
					continue
				end

				local outInfo = TweenInfo.new(MESSAGE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
				local twOut = TweenService:Create(tipObj, outInfo, { TextTransparency = 1 })
				twOut:Play()
				twOut.Completed:Wait()
				if not isAlive(tipObj) then
					continue
				end

				setTipMessage(TIP_MESSAGES[pickIndex()], true)
				TweenService:Create(tipObj, outInfo, { TextTransparency = 0 }):Play()
			end
		end)
	end
end

local function shouldPreloadInstance(inst: Instance): boolean
	return PRELOADABLE_CLASSES[inst.ClassName] == true
		or inst:IsA("DataModelMesh")
		or inst:IsA("Clothing")
end

local function addPreloadItem(list: {any}, seen: {[any]: boolean}, item: any): boolean
	if item == nil then
		return false
	end

	local key = if typeof(item) == "Instance" then item else tostring(item)
	if seen[key] then
		return false
	end

	seen[key] = true
	list[#list + 1] = item
	return true
end

local function addPreloadablesFrom(container: Instance?, list: {any}, seen: {[any]: boolean}, limit: number): number
	if not container or limit <= 0 then
		return 0
	end

	local added = 0
	if shouldPreloadInstance(container) and addPreloadItem(list, seen, container) then
		added += 1
	end

	if added >= limit then
		return added
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if shouldPreloadInstance(descendant) and addPreloadItem(list, seen, descendant) then
			added += 1
			if added >= limit then
				break
			end
		end
	end

	return added
end

local function findPath(rootInstance: Instance, path: {string}): Instance?
	local node: Instance? = rootInstance
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
		if not node then
			return nil
		end
	end

	return node
end

local function collectCriticalPreloadItems(): {any}
	local list = {}
	local seen = {}

	for _, assetId in ipairs(CRITICAL_ASSET_IDS) do
		addPreloadItem(list, seen, assetId)
	end

	addPreloadablesFrom(screenGui, list, seen, 120)
	return list
end

local function collectBackgroundBatchItems(batch): {any}
	local list = {}
	local seen = {}
	local limit = math.max(0, tonumber(batch.Limit) or 0)

	for _, assetId in ipairs(batch.AssetIds or {}) do
		if limit > 0 and #list >= limit then
			break
		end
		addPreloadItem(list, seen, assetId)
	end

	for _, path in ipairs(batch.Paths or {}) do
		if limit > 0 and #list >= limit then
			break
		end

		local container = findPath(ReplicatedStorage, path)
		if container then
			local remaining = if limit > 0 then limit - #list else 0
			addPreloadablesFrom(container, list, seen, remaining)
		end
	end

	return list
end

local function preloadItems(items: {any}, onProgress: ((number) -> ())?): (boolean, string?)
	if #items <= 0 then
		if onProgress then
			onProgress(1)
		end
		return true, nil
	end

	local loaded = 0
	local total = #items
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(items, function()
			loaded = math.min(loaded + 1, total)
			if onProgress then
				onProgress(math.clamp(loaded / total, 0, 1))
			end
		end)
	end)

	if not ok then
		return false, tostring(err)
	end

	if onProgress then
		onProgress(1)
	end
	return true, nil
end

local backgroundPreloadStarted = false

local function startBackgroundPreload()
	if backgroundPreloadStarted then
		return
	end
	backgroundPreloadStarted = true

	task.spawn(function()
		for _, batch in ipairs(BACKGROUND_PRELOAD_BATCHES) do
			local items = collectBackgroundBatchItems(batch)
			if #items > 0 then
				local ok, err = preloadItems(items)
				if not ok then
					warn(string.format(
						"[LoadingScreen] Background preload batch %s failed: %s",
						tostring(batch.Name),
						tostring(err)
					))
				end
			end
			task.wait(0.2)
		end

		setStartupAttribute(STARTUP_BACKGROUND_PRELOAD_COMPLETE_ATTRIBUTE, true)
	end)
end

local function markLoadingScreenFinished()
	if characterConnection and characterConnection.Connected then
		characterConnection:Disconnect()
	end

	setStartupAttribute(LOADING_SCREEN_ACTIVE_ATTRIBUTE, false)
	setStartupAttribute(LOADING_SCREEN_COMPLETE_ATTRIBUTE, true)
end

local function fadeOutAndDestroy()
	if not isAlive(screenGui) then
		markLoadingScreenFinished()
		return
	end

	renderReactLoading(true)

	local tweens = {}
	local fadeInfo = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	local shrinkInfo = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	for _, inst in ipairs(screenGui:GetDescendants()) do
		if inst:IsA("UIStroke") then
			table.insert(tweens, TweenService:Create(inst, fadeInfo, { Transparency = 1 }))
		elseif inst:IsA("TextLabel") or inst:IsA("TextButton") then
			table.insert(tweens, TweenService:Create(inst, fadeInfo, {
				BackgroundTransparency = 1,
				TextStrokeTransparency = 1,
				TextTransparency = 1,
			}))
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			table.insert(tweens, TweenService:Create(inst, fadeInfo, {
				BackgroundTransparency = 1,
				ImageTransparency = 1,
			}))
		elseif inst:IsA("Frame") or inst:IsA("ScrollingFrame") then
			table.insert(tweens, TweenService:Create(inst, fadeInfo, { BackgroundTransparency = 1 }))
		end
	end

	table.insert(tweens, TweenService:Create(rootScale, shrinkInfo, { Scale = 0.9 }))
	for _, tween in ipairs(tweens) do
		tween:Play()
	end

	task.wait(0.68)
	if reactContext then
		pcall(function()
			reactContext.Root:unmount()
		end)
		if reactContext.Container then
			reactContext.Container:Destroy()
		end
		reactContext = nil
	end

	if isAlive(screenGui) then
		screenGui:Destroy()
	end

	markLoadingScreenFinished()
end

local function getStartupMilestoneProgress(): number
	local progress = 0
	if isStartupAttributeTrue(STARTUP_DATA_REQUEST_SENT_ATTRIBUTE) then
		progress += 0.06
	end
	if isStartupAttributeTrue(STARTUP_HUD_READY_ATTRIBUTE) then
		progress += 0.07
	end
	if isStartupAttributeTrue(STARTUP_CHARACTER_OBSERVED_ATTRIBUTE) then
		progress += 0.07
	end
	return progress
end

local function getMissingStartupMilestones(): {string}
	local missing = {}
	if not isStartupAttributeTrue(STARTUP_DATA_REQUEST_SENT_ATTRIBUTE) then
		missing[#missing + 1] = STARTUP_DATA_REQUEST_SENT_ATTRIBUTE
	end
	if not isStartupAttributeTrue(STARTUP_HUD_READY_ATTRIBUTE) then
		missing[#missing + 1] = STARTUP_HUD_READY_ATTRIBUTE
	end
	if not isStartupAttributeTrue(STARTUP_CHARACTER_OBSERVED_ATTRIBUTE) then
		missing[#missing + 1] = STARTUP_CHARACTER_OBSERVED_ATTRIBUTE
	end
	return missing
end

local function areStartupMilestonesReady(): boolean
	return #getMissingStartupMilestones() == 0
end

task.spawn(function()
	setDisplayedProgress(0)

	local criticalProgress = 0
	local criticalDone = false
	local criticalTimedOut = false
	local maxTimedOut = false
	local startTime = os.clock()

	task.spawn(function()
		local items = collectCriticalPreloadItems()
		local ok, err = preloadItems(items, function(progress)
			criticalProgress = math.clamp(progress, 0, 1)
		end)

		if not ok then
			warn(string.format("[LoadingScreen] Critical preload failed; continuing startup: %s", tostring(err)))
		end

		criticalProgress = 1
		criticalDone = true
		setStartupAttribute(STARTUP_CRITICAL_ASSETS_READY_ATTRIBUTE, true)
	end)

	local displayed = 0
	while isAlive(screenGui) do
		local elapsed = os.clock() - startTime

		if not criticalDone and not criticalTimedOut and elapsed >= CRITICAL_PRELOAD_TIMEOUT_SECONDS then
			criticalTimedOut = true
			criticalProgress = 1
			setStartupAttribute(STARTUP_CRITICAL_ASSETS_TIMED_OUT_ATTRIBUTE, true)
			setLoadingState({
				phase = "Asset timeout",
				timedOut = true,
			}, true)
			setStatusOverride("Continuing while assets finish")
			warn(string.format(
				"[LoadingScreen] Critical preload timed out for %s(%d) after %.1fs; continuing startup.",
				player.Name,
				player.UserId,
				elapsed
			))
		end

		if elapsed >= MAX_LOADING_SCREEN_SECONDS then
			maxTimedOut = true
			setStartupAttribute(STARTUP_LOADING_TIMED_OUT_ATTRIBUTE, true)
			setLoadingState({
				phase = "Startup timeout",
				timedOut = true,
			}, true)
			setStatusOverride("Continuing into game")
			warn(string.format(
				"[LoadingScreen] Startup visual cover reached %.1fs max for %s(%d); missing milestones: %s.",
				elapsed,
				player.Name,
				player.UserId,
				table.concat(getMissingStartupMilestones(), ", ")
			))
			break
		end

		if elapsed >= EMERGENCY_WATCHDOG_SECONDS then
			maxTimedOut = true
			setStartupAttribute(STARTUP_LOADING_TIMED_OUT_ATTRIBUTE, true)
			setLoadingState({
				phase = "Emergency timeout",
				timedOut = true,
			}, true)
			setStatusOverride("Continuing into game")
			warn(string.format(
				"[LoadingScreen] Emergency watchdog reached %.1fs for %s(%d); continuing.",
				elapsed,
				player.Name,
				player.UserId
			))
			break
		end

		local target = 0.15 + (criticalProgress * 0.55) + getStartupMilestoneProgress()
		if elapsed < MIN_DISPLAY_SECONDS then
			target = math.min(target, 0.15 + (elapsed / MIN_DISPLAY_SECONDS) * 0.35)
		end
		target = math.clamp(target, 0, 0.9)

		displayed += (target - displayed) * 0.2
		setLoadingState({
			phase = if criticalDone or criticalTimedOut then "Syncing startup" else "Loading critical assets",
		})
		setDisplayedProgress(displayed)

		if elapsed >= MIN_DISPLAY_SECONDS and (criticalDone or criticalTimedOut) and areStartupMilestonesReady() then
			break
		end

		task.wait(0.05)
	end

	setStatusOverride(if maxTimedOut then "Entering game" else "Ready")
	setLoadingState({
		phase = "Ready",
		progress = 1,
		timedOut = maxTimedOut,
	}, true)
	setFallbackBarProgress(1)
	task.wait(0.2)
	fadeOutAndDestroy()
	if not criticalTimedOut then
		startBackgroundPreload()
	elseif reactHydrationFailed then
		setStartupAttribute(STARTUP_BACKGROUND_PRELOAD_COMPLETE_ATTRIBUTE, false)
	end
end)
