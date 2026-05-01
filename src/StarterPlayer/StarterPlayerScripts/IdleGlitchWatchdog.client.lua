local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local WATCHDOG_ENABLED = true
local LOG_PREFIX = "[IDLE WATCH]"
local LOG_THROTTLE_SECONDS = 2
local ANIMATION_BURST_WINDOW_SECONDS = 5
local FRAME_HITCH_SECONDS = 0.12

if not WATCHDOG_ENABLED then
	return
end

local player = Players.LocalPlayer
local startedAt = os.clock()
local lastLogByKey = {}
local currentHumanoid = nil

local function formatPath(instance)
	if not instance then
		return "<nil>"
	end

	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)

	return ok and fullName or tostring(instance)
end

local function getPlayerIdleState()
	if not currentHumanoid or not currentHumanoid.Parent then
		return "unknown"
	end

	if currentHumanoid.MoveDirection.Magnitude > 0.05 then
		return "moving"
	end

	local character = currentHumanoid.Parent
	if character and character:FindFirstChildWhichIsA("Tool") then
		return "tool_equipped"
	end

	return "idle"
end

local function emit(key, message, ...)
	local now = os.clock()
	local last = lastLogByKey[key]
	if last and (now - last) < LOG_THROTTLE_SECONDS then
		return
	end

	lastLogByKey[key] = now
	local ok, formatted = pcall(string.format, message, ...)
	if not ok then
		formatted = tostring(message)
	end

	print(string.format(
		"%s t=%.3f playerState=%s %s",
		LOG_PREFIX,
		now - startedAt,
		getPlayerIdleState(),
		formatted
	))
end

local function bindCharacter(character)
	currentHumanoid = nil
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		local ok, waited = pcall(function()
			return character:WaitForChild("Humanoid", 5)
		end)
		if ok and waited and waited:IsA("Humanoid") then
			humanoid = waited
		end
	end

	currentHumanoid = humanoid
end

if player.Character then
	task.defer(bindCharacter, player.Character)
end
player.CharacterAdded:Connect(bindCharacter)

local watchedCamera = nil
local cameraFovConnection = nil
local lastCameraFov = nil

local function bindCamera(camera)
	if cameraFovConnection then
		cameraFovConnection:Disconnect()
		cameraFovConnection = nil
	end

	watchedCamera = camera
	lastCameraFov = camera and camera.FieldOfView or nil

	if not camera then
		return
	end

	cameraFovConnection = camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
		local newFov = camera.FieldOfView
		local oldFov = lastCameraFov or newFov
		if math.abs(newFov - oldFov) >= 0.05 then
			emit(
				"cameraFov",
				"cameraFovChanged old=%.2f new=%.2f camera=%s",
				oldFov,
				newFov,
				formatPath(camera)
			)
		end
		lastCameraFov = newFov
	end)
end

bindCamera(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera(Workspace.CurrentCamera)
	emit("cameraChanged", "currentCameraChanged camera=%s", formatPath(Workspace.CurrentCamera))
end)

local blurConnection = nil
local watchedBlur = nil
local lastBlurSize = nil

local function bindBlur(blur)
	if blurConnection then
		blurConnection:Disconnect()
		blurConnection = nil
	end

	watchedBlur = blur
	lastBlurSize = blur and blur.Size or nil

	if not (blur and blur:IsA("BlurEffect")) then
		return
	end

	blurConnection = blur:GetPropertyChangedSignal("Size"):Connect(function()
		local newSize = blur.Size
		local oldSize = lastBlurSize or newSize
		if math.abs(newSize - oldSize) >= 0.05 then
			emit(
				"blurSize",
				"blurSizeChanged old=%.2f new=%.2f blur=%s",
				oldSize,
				newSize,
				formatPath(blur)
			)
		end
		lastBlurSize = newSize
	end)
end

bindBlur(Lighting:FindFirstChild("BlurUI"))
Lighting.ChildAdded:Connect(function(child)
	if child.Name == "BlurUI" and child:IsA("BlurEffect") then
		bindBlur(child)
		emit("blurCreated", "blurCreated blur=%s size=%.2f", formatPath(child), child.Size)
	end
end)
Lighting.ChildRemoved:Connect(function(child)
	if child == watchedBlur then
		emit("blurRemoved", "blurRemoved blur=%s", formatPath(child))
		bindBlur(nil)
	end
end)

local function getViewportSize()
	local camera = Workspace.CurrentCamera or watchedCamera
	if camera then
		return camera.ViewportSize
	end

	return Vector2.zero
end

local importantGuiNames = {
	Gifts = true,
	Inventory = true,
	Shop = true,
	Index = true,
	Quest = true,
	Settings = true,
	Backdrop = true,
	Overlay = true,
	BackgroundOverlay = true,
	ReactStoreBackdrop = true,
	ReactIndexBackdrop = true,
	ReactQuestBackdrop = true,
}

local function isImportantGuiObject(guiObject)
	if not guiObject:IsA("GuiObject") then
		return false
	end

	if importantGuiNames[guiObject.Name] then
		return true
	end

	local loweredName = string.lower(guiObject.Name)
	if string.find(loweredName, "overlay", 1, true) or string.find(loweredName, "backdrop", 1, true) then
		return true
	end

	local viewportSize = getViewportSize()
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return false
	end

	local absoluteSize = guiObject.AbsoluteSize
	return absoluteSize.X >= viewportSize.X * 0.75 and absoluteSize.Y >= viewportSize.Y * 0.65
end

local watchedGuiObjects = {}
local watchedScreenGuis = {}

local function watchGuiObject(guiObject)
	if watchedGuiObjects[guiObject] or not guiObject:IsA("GuiObject") then
		return
	end

	watchedGuiObjects[guiObject] = true
	local lastVisible = guiObject.Visible

	guiObject:GetPropertyChangedSignal("Visible"):Connect(function()
		local visible = guiObject.Visible
		if visible == lastVisible then
			return
		end

		lastVisible = visible
		if visible or isImportantGuiObject(guiObject) then
			emit(
				"uiVisible:" .. formatPath(guiObject),
				"uiVisibleChanged visible=%s gui=%s absSize=%s absPos=%s",
				tostring(visible),
				formatPath(guiObject),
				tostring(guiObject.AbsoluteSize),
				tostring(guiObject.AbsolutePosition)
			)
		end
	end)
end

local function watchScreenGui(screenGui)
	if watchedScreenGuis[screenGui] or not screenGui:IsA("ScreenGui") then
		return
	end

	watchedScreenGuis[screenGui] = true
	local lastEnabled = screenGui.Enabled

	screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		local enabled = screenGui.Enabled
		if enabled == lastEnabled then
			return
		end

		lastEnabled = enabled
		emit(
			"screenGuiEnabled:" .. formatPath(screenGui),
			"screenGuiEnabledChanged enabled=%s gui=%s displayOrder=%s",
			tostring(enabled),
			formatPath(screenGui),
			tostring(screenGui.DisplayOrder)
		)
	end)
end

local function watchUiInstance(instance)
	if instance:IsA("ScreenGui") then
		watchScreenGui(instance)
	elseif instance:IsA("GuiObject") then
		watchGuiObject(instance)
	end
end

local playerGui = player:WaitForChild("PlayerGui")
for _, instance in ipairs(playerGui:GetDescendants()) do
	watchUiInstance(instance)
end
playerGui.DescendantAdded:Connect(function(instance)
	task.defer(function()
		watchUiInstance(instance)
		if instance:IsA("GuiObject") and instance.Visible and isImportantGuiObject(instance) then
			emit(
				"uiAdded:" .. formatPath(instance),
				"importantUiAdded visible=true gui=%s absSize=%s",
				formatPath(instance),
				tostring(instance.AbsoluteSize)
			)
		end
	end)
end)

local hazardContainers = {}

local function countParts(root)
	local count = 0
	if root:IsA("BasePart") then
		return 1
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end

	return count
end

local function isHazardContainer(instance)
	return instance:IsA("Folder") and (instance.Name == "Hazards" or instance.Name == "ClientWaves")
end

local function isLikelyHazardRoot(instance)
	if not instance:IsA("Model") and not instance:IsA("BasePart") then
		return false
	end

	if instance:GetAttribute("HazardType") ~= nil or instance:GetAttribute("HazardClass") ~= nil then
		return true
	end

	return instance.Name == "WaveTemplate" or instance.Name == "HAHAH"
end

local function logHazardRoot(root, reason)
	if not isLikelyHazardRoot(root) then
		return
	end

	emit(
		"hazardRoot:" .. formatPath(root),
		"hazardRoot%s root=%s class=%s parts=%d descendants=%d frozen=%s activeVisual=%s",
		tostring(reason or "Changed"),
		formatPath(root),
		root.ClassName,
		countParts(root),
		#root:GetDescendants(),
		tostring(root:GetAttribute("Frozen")),
		tostring(root:GetAttribute("ActiveWaveVisualAssetName"))
	)
end

local function watchHazardContainer(container)
	if hazardContainers[container] or not isHazardContainer(container) then
		return
	end

	hazardContainers[container] = true
	emit("hazardContainer:" .. formatPath(container), "hazardContainerWatched container=%s", formatPath(container))

	for _, child in ipairs(container:GetChildren()) do
		logHazardRoot(child, "Existing")
	end

	container.ChildAdded:Connect(function(child)
		task.defer(function()
			logHazardRoot(child, "Added")
		end)
	end)

	container.ChildRemoved:Connect(function(child)
		if isLikelyHazardRoot(child) then
			emit("hazardRemoved:" .. formatPath(child), "hazardRootRemoved root=%s", formatPath(child))
		end
	end)
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	if isHazardContainer(descendant) then
		watchHazardContainer(descendant)
	end
end

Workspace.DescendantAdded:Connect(function(instance)
	if isHazardContainer(instance) then
		watchHazardContainer(instance)
	elseif instance.Name == "WaveVisual" or instance.Name == "FrozenWaveVisual" or instance.Name == "WaveHitbox" then
		emit("waveVisual:" .. formatPath(instance), "waveVisualAdded name=%s path=%s parts=%d", instance.Name, formatPath(instance), countParts(instance))
	end
end)

local animationFailureWindowStartedAt = 0
local animationFailureCount = 0
local animationFailureIds = {}

local function formatAnimationFailureIds()
	local ids = {}
	for id in pairs(animationFailureIds) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

LogService.MessageOut:Connect(function(message)
	local text = tostring(message or "")
	local lowered = string.lower(text)
	if not string.find(lowered, "failed to load animation", 1, true) then
		return
	end

	local animationId = string.match(text, "rbxassetid://(%d+)") or string.match(text, "asset%?id=(%d+)")
	if not animationId then
		animationId = "<unknown>"
	end

	local now = os.clock()
	if animationFailureWindowStartedAt <= 0 or (now - animationFailureWindowStartedAt) > ANIMATION_BURST_WINDOW_SECONDS then
		animationFailureWindowStartedAt = now
		animationFailureCount = 0
		animationFailureIds = {}
	end

	animationFailureCount += 1
	animationFailureIds[animationId] = true

	emit(
		"animationFailure:" .. animationId,
		"animationFailure id=%s countInWindow=%d idsInWindow=%s",
		animationId,
		animationFailureCount,
		formatAnimationFailureIds()
	)

	if animationFailureCount >= 3 then
		emit(
			"animationFailureBurst",
			"animationFailureBurst count=%d windowSeconds=%.1f ids=%s",
			animationFailureCount,
			ANIMATION_BURST_WINDOW_SECONDS,
			formatAnimationFailureIds()
		)
	end
end)

local lastFrameHitchLogAt = 0
RunService.RenderStepped:Connect(function(deltaTime)
	if deltaTime < FRAME_HITCH_SECONDS then
		return
	end

	local now = os.clock()
	if now - lastFrameHitchLogAt < LOG_THROTTLE_SECONDS then
		return
	end

	lastFrameHitchLogAt = now
	emit(
		"frameHitch",
		"frameHitch dt=%.3f fps=%.1f activeHazardContainers=%d",
		deltaTime,
		1 / math.max(deltaTime, 1e-6),
		(function()
			local count = 0
			for container in pairs(hazardContainers) do
				if container.Parent ~= nil then
					count += 1
				end
			end
			return count
		end)()
	)
end)

emit("watchdogStarted", "watchdogStarted")
