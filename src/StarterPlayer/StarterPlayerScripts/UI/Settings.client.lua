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

local SettingsConfig = require(Modules:WaitForChild("Configs"):WaitForChild("Settings"))
local SettingsScreen = require(UiFolder:WaitForChild("Settings"):WaitForChild("SettingsScreen"))

local UpdateSettingRemote = ReplicatedStorage:WaitForChild("UpdateSetting")

local e = React.createElement

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactSettingsRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Settings",
	hostName = "ReactSettingsHost",
	backdropName = nil,
	modalStateKey = nil,
	minSize = Vector2.new(760, 540),
	maxSize = Vector2.new(1240, 760),
	createFrameIfMissing = true,
})

local SETTING_ORDER = {
	"Music",
	"SoundEffects",
}

local ICONS = {
	Music = "rbxassetid://125384263224347",
	SoundEffects = "rbxassetid://131189007512696",
	HidePopUps = "rbxassetid://77322372470208",
	LowGraphic = "rbxassetid://131189007512696",
}

local DISPLAY_LABELS = {
	SoundEffects = "Sounds",
}

local SETTING_ALIASES = {
	SoundEffects = { "Sounds", "Souynds", "sounds" },
	HidePopUps = { "HidePopUps", "Hide Pop Ups", "Hide Popups", "HidePopups" },
	LowGraphic = { "LowGraphic", "Low Graphic", "LowGraphics", "Low Graphics" },
}

local destroyed = false
local renderQueued = false
local sliderPreviewActive = false
local settingFolder = nil
local settingOverrides = {}
local cleanupConnections = {}
local settingConnections = {}

local scheduleRender

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

local function readSettingValue(settingName, config)
	local instance = resolveSettingInstance(settingName, config)
	local settingType = tostring(config and config.Type or "")

	if settingType == "Slider" then
		if instance and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
			return math.floor(clampNumber(instance.Value, 0, 100) + 0.5)
		end
		if typeof(settingOverrides[settingName]) == "number" then
			return math.floor(clampNumber(settingOverrides[settingName], 0, 100) + 0.5)
		end
		return math.floor(clampNumber(config and config.Start or 100, 0, 100) + 0.5)
	end

	if instance and instance:IsA("BoolValue") then
		return instance.Value == true
	end
	if typeof(settingOverrides[settingName]) == "boolean" then
		return settingOverrides[settingName]
	end

	return config and config.Start == true
end

local function applyLocalSetting(settingName, config, nextValue)
	local settingType = tostring(config and config.Type or "")
	local instance = resolveSettingInstance(settingName, config)

	if settingType == "Slider" then
		local clamped = math.floor(clampNumber(nextValue, 0, 100) + 0.5)
		if instance and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
			instance.Value = clamped
		else
			settingOverrides[settingName] = clamped
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

	UpdateSettingRemote:FireServer(settingName, config and config.Path or "", nextValue)
end

local function buildItems()
	local items = {}
	for _, settingName in ipairs(SETTING_ORDER) do
		local config = SettingsConfig[settingName]
		if typeof(config) == "table" then
			items[#items + 1] = {
				id = settingName,
				label = DISPLAY_LABELS[settingName] or settingName,
				type = tostring(config.Type or "Switch"),
				value = readSettingValue(settingName, config),
				icon = ICONS[settingName],
			}
		end
	end
	return items
end

local function bindSettingFolder(folder)
	disconnectAll(settingConnections)
	settingFolder = folder

	if not folder then
		return
	end

	local function watchInstance(instance)
		if instance:IsA("ValueBase") then
			trackConnection(instance:GetPropertyChangedSignal("Value"), function()
				if sliderPreviewActive and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
					return
				end
				task.defer(scheduleRender)
			end, settingConnections)
		end
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		watchInstance(descendant)
	end

	trackConnection(folder.DescendantAdded, function(descendant)
		watchInstance(descendant)
		task.defer(scheduleRender)
	end, settingConnections)

	trackConnection(folder.DescendantRemoving, function()
		task.defer(scheduleRender)
	end, settingConnections)
end

local function prepareFrame()
	local frame = modalAdapter:GetFrame()
	if not frame then
		return
	end

	frame.Size = UDim2.fromScale(0.47, 0.66)
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

trackConnection(player.ChildAdded, function(child)
	if child.Name == "Settings" then
		bindSettingFolder(child)
		task.defer(scheduleRender)
	end
end, cleanupConnections)

trackConnection(player.ChildRemoved, function(child)
	if child == settingFolder then
		bindSettingFolder(nil)
		task.defer(scheduleRender)
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

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll(cleanupConnections)
	disconnectAll(settingConnections)
	modalAdapter:Destroy()
	root:unmount()
end)
