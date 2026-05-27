local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ReactFrameModalAdapter = require(Modules:WaitForChild("ReactFrameModalAdapter"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local Responsive = require(UiFolder:WaitForChild("Responsive"))

local SettingsConfig = require(Modules:WaitForChild("Configs"):WaitForChild("Settings"))
local PremiumCrewStealConfig = require(Modules:WaitForChild("Configs"):WaitForChild("PremiumCrewStealConfig"))
local SettingsAudioController = require(Modules:WaitForChild("SettingsAudioController"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local SettingsScreen = require(UiFolder:WaitForChild("Settings"):WaitForChild("SettingsScreen"))

local UpdateSettingRemote = ReplicatedStorage:WaitForChild("UpdateSetting")

local e = React.createElement
local SPEED_SETTING_NAME = "Speed"
local SPEED_AUTO_MAX_SETTING_NAME = "SpeedAutoMax"
local PREMIUM_STEAL_PROTECTION_SETTING_NAME = "PremiumStealProtection"
local SPEED_ICON_ASSET = "rbxassetid://108512951338844"
local RAID_SHIELD_CONFIG = PremiumCrewStealConfig.RaidShield or {}
local RAID_SHIELD_REMOTES = RAID_SHIELD_CONFIG.Remotes or {}
local RAID_SHIELD_ATTRIBUTES = RAID_SHIELD_CONFIG.Attributes or {}

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactSettingsRoot"

local SETTINGS_FRAME_SIZE = UDim2.fromScale(0.47, 0.66)

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Settings",
	hostName = "ReactSettingsHost",
	backdropName = "ReactSettingsBackdrop",
	backdropActive = false,
	modalStateKey = "SettingsModal",
	minSize = Vector2.new(760, 540),
	maxSize = Vector2.new(1240, 760),
	frameSize = SETTINGS_FRAME_SIZE,
	createFrameIfMissing = true,
	standalone = true,
})

local SETTING_ORDER = {
	"Music",
	"SoundEffects",
	SPEED_SETTING_NAME,
	PREMIUM_STEAL_PROTECTION_SETTING_NAME,
}

local ICONS = {
	Music = "rbxassetid://125384263224347",
	SoundEffects = "rbxassetid://131189007512696",
	Speed = SPEED_ICON_ASSET,
	PremiumStealProtection = "rbxassetid://125384263224347",
	HidePopUps = "rbxassetid://77322372470208",
	LowGraphic = "rbxassetid://131189007512696",
}

local DISPLAY_LABELS = {
	SoundEffects = "Sounds",
	PremiumStealProtection = "Steal Protection",
}

local SETTING_ALIASES = {
	SoundEffects = { "Sounds", "Souynds", "sounds" },
	HidePopUps = { "HidePopUps", "Hide Pop Ups", "Hide Popups", "HidePopups" },
	LowGraphic = { "LowGraphic", "Low Graphic", "LowGraphics", "Low Graphics" },
}

local DEBUG_SETTINGS_AUDIO = false

local destroyed = false
local renderQueued = false
local sliderPreviewActive = false
local settingFolder = nil
local settingOverrides = {}
local raidShieldState = nil
local raidShieldStateRemote = nil
local raidShieldSetEnabledRemote = nil
local cleanupConnections = {}
local settingConnections = {}
local scheduleRender
local syncAudioFromSettings

local unregisterModal = ReactModalRegistry.Register("Settings", {
	toggle = function()
		modalAdapter:Toggle()
		if scheduleRender then
			scheduleRender()
		end
	end,
	open = function()
		if not modalAdapter:IsVisible() then
			modalAdapter:Toggle()
		end
		if scheduleRender then
			scheduleRender()
		end
	end,
	close = function()
		modalAdapter:Close()
	end,
	isVisible = function()
		return modalAdapter:IsVisible()
	end,
})

local function debugAudio(message, ...)
	if not DEBUG_SETTINGS_AUDIO then
		return
	end

	print(string.format("[SETTINGS][AUDIO] " .. message, ...))
end

SettingsAudioController.SetDebug(DEBUG_SETTINGS_AUDIO)

local function clampNumber(value, minimum, maximum)
	local numeric = tonumber(value) or minimum
	if numeric < minimum then
		return minimum
	end
	if numeric > maximum then
		return maximum
	end
	return numeric
end

local function roundNumber(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function formatDuration(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

local function showShieldMessage(message, isError)
	PopUpModule:Local_SendPopUp(
		tostring(message or "Protection could not be updated."),
		if isError then Color3.fromRGB(255, 104, 104) else Color3.fromRGB(111, 255, 136),
		Color3.fromRGB(0, 0, 0),
		3,
		isError == true
	)
end

local function isAudioSetting(settingName)
	return settingName == "Music" or settingName == "SoundEffects"
end

local function disconnectAll(bucket)
	for _, connection in ipairs(bucket) do
		connection:Disconnect()
	end
	table.clear(bucket)
end

local function trackConnection(signal, callback, bucket)
	local connection = signal:Connect(callback)
	table.insert(bucket, connection)
	return connection
end

local function applyAudioSetting(settingName, value)
	SettingsAudioController.Apply(settingName, value)
end

local function getFromPath(startRoot, path)
	if typeof(startRoot) ~= "Instance" then
		return nil
	end

	local current = startRoot
	for segment in string.gmatch(tostring(path or ""), "[^%.]+") do
		current = current and current:FindFirstChild(segment) or nil
		if not current then
			return nil
		end
	end

	return current
end

local function resolveSettingInstance(settingName, config)
	local folder = settingFolder or player:FindFirstChild("Settings")
	if folder then
		local direct = folder:FindFirstChild(settingName)
		if direct then
			return direct
		end

		local aliases = SETTING_ALIASES[settingName]
		if aliases then
			for _, aliasName in ipairs(aliases) do
				local aliasValue = folder:FindFirstChild(aliasName)
				if aliasValue then
					return aliasValue
				end
			end
		end
	end

	local path = config and config.Path or nil
	local byPath = getFromPath(player, path)
	if byPath then
		return byPath
	end

	if type(path) == "string" then
		local settingsPath = string.match(path, "^Settings%.(.+)$")
		local aliases = SETTING_ALIASES[settingName]
		if settingsPath and aliases then
			for _, aliasName in ipairs(aliases) do
				local aliasPath = "Settings." .. aliasName
				local aliasInstance = getFromPath(player, aliasPath)
				if aliasInstance then
					return aliasInstance
				end
			end
		end
	end

	if type(path) == "string" and string.sub(path, -6) == "Sounds" then
		local altPath = string.sub(path, 1, #path - 6) .. "Souynds"
		return getFromPath(player, altPath)
	end

	return nil
end

local function readNumberAttribute(attributeName)
	return math.max(0, math.floor(tonumber(player:GetAttribute(attributeName)) or 0))
end

local function readStringAttribute(attributeName)
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "string" then
		return value
	end
	return ""
end

local function updateRaidShieldState(nextState)
	if typeof(nextState) ~= "table" then
		return
	end
	raidShieldState = table.clone(nextState)
	raidShieldState.ReceivedAtClock = os.clock()
	if typeof(raidShieldState.ServerTime) ~= "number" then
		raidShieldState.ServerTime = os.time()
	end
end

local function readRaidShieldStateFromAttributes()
	return {
		ServerTime = os.time(),
		ReceivedAtClock = os.clock(),
		Enabled = player:GetAttribute(RAID_SHIELD_ATTRIBUTES.Enabled or "RaidShieldEnabled") == true,
		IsActive = player:GetAttribute(RAID_SHIELD_ATTRIBUTES.Active or "RaidShieldActive") == true,
		CanEnable = player:GetAttribute(RAID_SHIELD_ATTRIBUTES.CanEnable or "RaidShieldCanEnable") == true,
		ActiveUntil = readNumberAttribute(RAID_SHIELD_ATTRIBUTES.ActiveUntil or "RaidShieldActiveUntil"),
		RemainingSeconds = readNumberAttribute(RAID_SHIELD_ATTRIBUTES.RemainingSeconds or "RaidShieldRemainingSeconds"),
		SuppressionUntil = readNumberAttribute(RAID_SHIELD_ATTRIBUTES.SuppressionUntil or "RaidShieldSuppressionUntil"),
		SuppressionRemainingSeconds = readNumberAttribute(RAID_SHIELD_ATTRIBUTES.SuppressionRemainingSeconds or "RaidShieldSuppressionRemainingSeconds"),
		DisabledReason = readStringAttribute(RAID_SHIELD_ATTRIBUTES.DisabledReason or "RaidShieldDisabledReason"),
		Source = readStringAttribute(RAID_SHIELD_ATTRIBUTES.Source or "RaidShieldSource"),
		SuppressionDurationSeconds = math.max(0, math.floor(tonumber(RAID_SHIELD_CONFIG.SuppressionSeconds) or 300)),
	}
end

local function getRaidShieldNow()
	local state = raidShieldState
	if typeof(state) == "table" and typeof(state.ServerTime) == "number" and typeof(state.ReceivedAtClock) == "number" then
		return state.ServerTime + (os.clock() - state.ReceivedAtClock)
	end
	return os.time()
end

local function getLiveRaidShieldState()
	local state = raidShieldState
	if typeof(state) ~= "table" then
		updateRaidShieldState(readRaidShieldStateFromAttributes())
		state = raidShieldState
	end
	state = if typeof(state) == "table" then table.clone(state) else readRaidShieldStateFromAttributes()

	local currentTime = getRaidShieldNow()
	state.RemainingSeconds = math.max(0, math.ceil((tonumber(state.ActiveUntil) or 0) - currentTime))
	state.SuppressionRemainingSeconds = math.max(0, math.ceil((tonumber(state.SuppressionUntil) or 0) - currentTime))
	state.CanEnable = state.RemainingSeconds > 0 and state.SuppressionRemainingSeconds <= 0
	state.IsActive = state.Enabled == true and state.CanEnable == true
	if state.RemainingSeconds <= 0 then
		state.DisabledReason = "shield_expired"
	elseif state.SuppressionRemainingSeconds > 0 then
		state.DisabledReason = "raid_suppression"
	elseif state.Enabled ~= true then
		state.DisabledReason = "manual_disabled"
	end
	return state
end

local function getRaidShieldStatusText(state)
	if state.SuppressionRemainingSeconds > 0 then
		return "Disabled: available in " .. formatDuration(state.SuppressionRemainingSeconds)
	elseif state.IsActive then
		return "Protected: " .. formatDuration(state.RemainingSeconds) .. " left"
	elseif state.RemainingSeconds > 0 then
		return "Off: " .. formatDuration(state.RemainingSeconds) .. " left"
	end
	return "Expired"
end

local function hasRaidShieldCountdown()
	local state = getLiveRaidShieldState()
	return state.RemainingSeconds > 0 or state.SuppressionRemainingSeconds > 0
end

local function getEarnedSpeedMax()
	local hidden = player:FindFirstChild("HiddenLeaderstats")
	local speed = hidden and hidden:FindFirstChild("Speed")
	if speed and (speed:IsA("NumberValue") or speed:IsA("IntValue")) then
		return math.max(1, roundNumber(speed.Value))
	end

	return 1
end

local function getSpeedHudIcon()
	local hud = playerGui:FindFirstChild("HUD")
	local counters = hud and hud:FindFirstChild("Counters")
	local speedCounter = counters and counters:FindFirstChild("Speed")
	local icon = speedCounter and speedCounter:FindFirstChildWhichIsA("ImageLabel", true)
	if icon and icon.Image ~= "" then
		return icon.Image
	end

	return SPEED_ICON_ASSET
end

local function getSettingIcon(settingName)
	if settingName == SPEED_SETTING_NAME then
		return getSpeedHudIcon()
	end

	return ICONS[settingName]
end

local function getSliderBounds(settingName, config)
	local minimum = tonumber(config and config.Min)
	local maximum = tonumber(config and config.Max)

	if settingName == SPEED_SETTING_NAME then
		minimum = 1
		maximum = getEarnedSpeedMax()
	else
		minimum = if minimum ~= nil then minimum else 0
		maximum = if maximum ~= nil then maximum else 100
	end

	minimum = roundNumber(minimum)
	maximum = math.max(minimum, roundNumber(maximum))
	return minimum, maximum
end

local function clampSliderValue(settingName, config, value)
	local minimum, maximum = getSliderBounds(settingName, config)
	return roundNumber(clampNumber(value, minimum, maximum))
end

local function readSpeedAutoMax(config)
	local autoInstance = getFromPath(player, config and config.AutoMaxPath or "Settings.SpeedAutoMax")
	if autoInstance and autoInstance:IsA("BoolValue") then
		return autoInstance.Value == true
	end

	local override = settingOverrides[SPEED_AUTO_MAX_SETTING_NAME]
	if typeof(override) == "boolean" then
		return override
	end

	return true
end

local function describeSettingInstance(instance)
	if typeof(instance) ~= "Instance" then
		return "<nil>"
	end

	return string.format("%s (%s)", instance:GetFullName(), instance.ClassName)
end

local function readSettingValue(settingName, config)
	local instance = resolveSettingInstance(settingName, config)
	local settingType = tostring(config and config.Type or "")

	if settingType == "Slider" then
		if sliderPreviewActive and typeof(settingOverrides[settingName]) == "number" then
			return clampSliderValue(settingName, config, settingOverrides[settingName])
		end
		if settingName == SPEED_SETTING_NAME and readSpeedAutoMax(config) then
			local _, maximum = getSliderBounds(settingName, config)
			return maximum
		end
		if instance and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
			return clampSliderValue(settingName, config, instance.Value)
		end
		if typeof(settingOverrides[settingName]) == "number" then
			return clampSliderValue(settingName, config, settingOverrides[settingName])
		end
		return clampSliderValue(settingName, config, config and config.Start or 100)
	end

	if instance and instance:IsA("BoolValue") then
		return instance.Value == true
	end
	if typeof(settingOverrides[settingName]) == "boolean" then
		return settingOverrides[settingName]
	end

	return config and config.Start == true
end

syncAudioFromSettings = function()
	for _, settingName in ipairs(SETTING_ORDER) do
		local config = SettingsConfig[settingName]
		if typeof(config) == "table" and tostring(config.Type or "") == "Slider" and isAudioSetting(settingName) then
			local value = readSettingValue(settingName, config)
			debugAudio("syncFromSettings name=%s value=%s", tostring(settingName), tostring(value))
			applyAudioSetting(settingName, value)
		end
	end
end

local function applyLocalSetting(settingName, config, nextValue)
	local settingType = tostring(config and config.Type or "")
	local instance = resolveSettingInstance(settingName, config)

	if settingType == "Slider" then
		local clamped = clampSliderValue(settingName, config, nextValue)
		if not sliderPreviewActive then
			debugAudio(
				"localSetting name=%s value=%d instance=%s",
				tostring(settingName),
				clamped,
				describeSettingInstance(instance)
			)
		end
		if instance and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
			instance.Value = clamped
		else
			settingOverrides[settingName] = clamped
		end
		if settingName == SPEED_SETTING_NAME then
			local _, maximum = getSliderBounds(settingName, config)
			local autoMax = clamped >= maximum
			local autoInstance = getFromPath(player, config and config.AutoMaxPath or "Settings.SpeedAutoMax")
			if autoInstance and autoInstance:IsA("BoolValue") then
				autoInstance.Value = autoMax
			else
				settingOverrides[SPEED_AUTO_MAX_SETTING_NAME] = autoMax
			end
		elseif isAudioSetting(settingName) then
			applyAudioSetting(settingName, clamped)
		end
		return clamped
	end

	local toggled = nextValue == true
	if instance and instance:IsA("BoolValue") then
		instance.Value = toggled
	else
		settingOverrides[settingName] = toggled
	end
	return toggled
end

local function fireSetting(settingName, config, nextValue)
	if not UpdateSettingRemote then
		return
	end

	debugAudio(
		"fireServer name=%s path=%s value=%s",
		tostring(settingName),
		tostring(config and config.Path or ""),
		tostring(nextValue)
	)
	UpdateSettingRemote:FireServer(settingName, config and config.Path or "", nextValue)
end

local function buildItems()
	local items = {}
	for _, settingName in ipairs(SETTING_ORDER) do
		local config = SettingsConfig[settingName]
		if typeof(config) == "table" then
			local raidShield = if settingName == PREMIUM_STEAL_PROTECTION_SETTING_NAME then getLiveRaidShieldState() else nil
			local minimum, maximum = getSliderBounds(settingName, config)
			items[#items + 1] = {
				id = settingName,
				label = DISPLAY_LABELS[settingName] or settingName,
				type = tostring(config.Type or "Switch"),
				value = if raidShield then raidShield.IsActive == true else readSettingValue(settingName, config),
				min = minimum,
				max = maximum,
				step = tonumber(config.Step) or 1,
				rangeText = if settingName == SPEED_SETTING_NAME then "Max " .. tostring(maximum) else nil,
				statusText = if raidShield then getRaidShieldStatusText(raidShield) else nil,
				disabledReason = if raidShield then raidShield.DisabledReason else nil,
				icon = getSettingIcon(settingName),
			}
		end
	end
	return items
end

local function bindSettingFolder(folder)
	disconnectAll(settingConnections)
	settingFolder = folder

	if not folder then
		debugAudio("bindSettingFolder folder=<nil>")
		return
	end

	debugAudio("bindSettingFolder folder=%s descendants=%d", folder:GetFullName(), #folder:GetDescendants())

	local function watchInstance(instance)
		if instance:IsA("ValueBase") then
			trackConnection(instance:GetPropertyChangedSignal("Value"), function()
				if sliderPreviewActive and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
					return
				end
				task.defer(function()
					syncAudioFromSettings()
					scheduleRender()
				end)
			end, settingConnections)
		end
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		watchInstance(descendant)
	end

	trackConnection(folder.DescendantAdded, function(descendant)
		watchInstance(descendant)
		task.defer(function()
			syncAudioFromSettings()
			scheduleRender()
		end)
	end, settingConnections)

	trackConnection(folder.DescendantRemoving, function()
		task.defer(function()
			syncAudioFromSettings()
			scheduleRender()
		end)
	end, settingConnections)
end

local function bindEarnedSpeedValue()
	local hidden = player:FindFirstChild("HiddenLeaderstats") or player:WaitForChild("HiddenLeaderstats", 5)
	local speed = hidden and (hidden:FindFirstChild("Speed") or hidden:WaitForChild("Speed", 5))
	if not (speed and (speed:IsA("NumberValue") or speed:IsA("IntValue"))) then
		return
	end

	trackConnection(speed:GetPropertyChangedSignal("Value"), function()
		task.defer(scheduleRender)
	end, cleanupConnections)
end

local function requestRaidShieldToggle(nextValue)
	if not (raidShieldSetEnabledRemote and raidShieldSetEnabledRemote:IsA("RemoteFunction")) then
		showShieldMessage("Protection service is starting. Try again soon.", true)
		scheduleRender()
		return
	end

	local ok, response = pcall(function()
		return raidShieldSetEnabledRemote:InvokeServer(nextValue == true)
	end)
	if not ok then
		showShieldMessage("Protection could not be updated. Try again soon.", true)
		scheduleRender()
		return
	end
	if typeof(response) == "table" and typeof(response.State) == "table" then
		updateRaidShieldState(response.State)
	end
	if typeof(response) == "table" and response.Ok ~= true then
		showShieldMessage(response.Message or "Protection could not be updated.", true)
	end
	scheduleRender()
end

local function bindRaidShieldState()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
	if remotes then
		raidShieldStateRemote = remotes:FindFirstChild(tostring(RAID_SHIELD_REMOTES.StateName or "RaidShieldState"))
			or remotes:WaitForChild(tostring(RAID_SHIELD_REMOTES.StateName or "RaidShieldState"), 10)
		raidShieldSetEnabledRemote = remotes:FindFirstChild(tostring(RAID_SHIELD_REMOTES.SetEnabledName or "RaidShieldSetEnabled"))
			or remotes:WaitForChild(tostring(RAID_SHIELD_REMOTES.SetEnabledName or "RaidShieldSetEnabled"), 10)
	end

	updateRaidShieldState(readRaidShieldStateFromAttributes())
	if raidShieldStateRemote and raidShieldStateRemote:IsA("RemoteEvent") then
		trackConnection(raidShieldStateRemote.OnClientEvent, function(nextState)
			updateRaidShieldState(nextState)
			task.defer(scheduleRender)
		end, cleanupConnections)
	end

	local attributeNames = {
		RAID_SHIELD_ATTRIBUTES.Enabled or "RaidShieldEnabled",
		RAID_SHIELD_ATTRIBUTES.Active or "RaidShieldActive",
		RAID_SHIELD_ATTRIBUTES.ActiveUntil or "RaidShieldActiveUntil",
		RAID_SHIELD_ATTRIBUTES.RemainingSeconds or "RaidShieldRemainingSeconds",
		RAID_SHIELD_ATTRIBUTES.SuppressionUntil or "RaidShieldSuppressionUntil",
		RAID_SHIELD_ATTRIBUTES.SuppressionRemainingSeconds or "RaidShieldSuppressionRemainingSeconds",
		RAID_SHIELD_ATTRIBUTES.CanEnable or "RaidShieldCanEnable",
		RAID_SHIELD_ATTRIBUTES.DisabledReason or "RaidShieldDisabledReason",
	}
	for _, attributeName in ipairs(attributeNames) do
		trackConnection(player:GetAttributeChangedSignal(attributeName), function()
			updateRaidShieldState(readRaidShieldStateFromAttributes())
			task.defer(scheduleRender)
		end, cleanupConnections)
	end
end

local function prepareFrame()
	local frame = modalAdapter:GetFrame()
	if not frame then
		return
	end

	local mobile = Responsive.isMobile()
	if frame.Visible ~= true and not mobile then
		frame.Size = SETTINGS_FRAME_SIZE
	end
	frame.BackgroundTransparency = 1
	frame.ZIndex = 120

	local host = frame:FindFirstChild("ReactSettingsHost")
	if host and host:IsA("GuiObject") then
		host.ZIndex = 140
	end
end

local function render()
	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end

	prepareFrame()

	root:render(ReactRoblox.createPortal(e(SettingsScreen, {
		items = buildItems(),
		onClose = function()
			sliderPreviewActive = false
			modalAdapter:Close()
		end,
		onSliderPreview = function(settingName, nextValue)
			local config = SettingsConfig[settingName]
			if typeof(config) ~= "table" then
				return
			end
			sliderPreviewActive = true
			local value = applyLocalSetting(settingName, config, nextValue)
			settingOverrides[settingName] = value
		end,
		onSliderCommit = function(settingName, nextValue)
			local config = SettingsConfig[settingName]
			if typeof(config) ~= "table" then
				return
			end
			sliderPreviewActive = false
			local value = applyLocalSetting(settingName, config, nextValue)
			fireSetting(settingName, config, value)
			scheduleRender()
		end,
		onSwitchToggle = function(settingName, nextValue)
			local config = SettingsConfig[settingName]
			if typeof(config) ~= "table" then
				return
			end
			if settingName == PREMIUM_STEAL_PROTECTION_SETTING_NAME then
				requestRaidShieldToggle(nextValue)
				return
			end
			local value = applyLocalSetting(settingName, config, nextValue)
			fireSetting(settingName, config, value)
			scheduleRender()
		end,
	}), host))

	modalAdapter:SyncOverlayState()
end

scheduleRender = function()
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

modalAdapter:SetScheduleRender(scheduleRender)
modalAdapter:BindFramesFolderTracking()

bindSettingFolder(player:FindFirstChild("Settings") or player:WaitForChild("Settings", 5))
bindEarnedSpeedValue()
bindRaidShieldState()
SettingsAudioController.Start()
syncAudioFromSettings()

trackConnection(player.ChildAdded, function(child)
	if child.Name == "Settings" then
		bindSettingFolder(child)
		task.defer(function()
			syncAudioFromSettings()
			scheduleRender()
		end)
	end
end, cleanupConnections)

trackConnection(player.ChildRemoved, function(child)
	if child == settingFolder then
		bindSettingFolder(nil)
		task.defer(function()
			syncAudioFromSettings()
			scheduleRender()
		end)
	end
end, cleanupConnections)

trackConnection(playerGui.ChildAdded, function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		modalAdapter:HandlePlayerGuiChildAdded(child)
		task.defer(scheduleRender)
	end
end, cleanupConnections)

trackConnection(playerGui.ChildRemoved, function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		modalAdapter:HandlePlayerGuiChildRemoved(child)
		task.defer(scheduleRender)
	end
end, cleanupConnections)

render()

task.spawn(function()
	while not destroyed do
		task.wait(1)
		if not destroyed and modalAdapter:IsVisible() and hasRaidShieldCountdown() then
			scheduleRender()
		end
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll(cleanupConnections)
	disconnectAll(settingConnections)
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
