local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local Responsive = require(UiFolder:WaitForChild("Responsive"))

local SettingsConfig = require(Modules:WaitForChild("Configs"):WaitForChild("Settings"))
local UpdateSettingRemote = ReplicatedStorage:WaitForChild("UpdateSetting")

local e = React.createElement

local SPEED_SETTING_NAME = "Speed"
local SPEED_AUTO_MAX_SETTING_NAME = "SpeedAutoMax"
local SPEED_ICON_ASSET = "rbxassetid://108512951338844"
local BUTTON_NAME = "SpeedModifier"

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactSpeedModifierRoot"
rootContainer.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)

local destroyed = false
local renderQueued = false
local expanded = false
local settingFolder = nil
local settingOverrides = {}
local cleanupConnections = {}
local settingConnections = {}
local buttonConnections = {}
local scheduleRender

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

local function roundNumber(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function clampNumber(value, minimum, maximum)
	local numeric = tonumber(value) or minimum
	return math.clamp(numeric, minimum, maximum)
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
	end

	return getFromPath(player, config and config.Path or nil)
end

local function getEarnedSpeedMax()
	local hidden = player:FindFirstChild("HiddenLeaderstats")
	local speed = hidden and hidden:FindFirstChild("Speed")
	if speed and (speed:IsA("NumberValue") or speed:IsA("IntValue")) then
		return math.max(1, roundNumber(speed.Value))
	end

	return 1
end

local function getSliderBounds(config)
	local minimum = 1
	local maximum = getEarnedSpeedMax()
	if typeof(config) == "table" then
		minimum = tonumber(config.Min) or minimum
	end

	minimum = roundNumber(minimum)
	maximum = math.max(minimum, roundNumber(maximum))
	return minimum, maximum
end

local function clampSpeedValue(config, value)
	local minimum, maximum = getSliderBounds(config)
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

local function readSpeedValue()
	local config = SettingsConfig[SPEED_SETTING_NAME]
	if typeof(config) ~= "table" then
		return 1
	end

	if readSpeedAutoMax(config) then
		local _, maximum = getSliderBounds(config)
		return maximum
	end

	local instance = resolveSettingInstance(SPEED_SETTING_NAME, config)
	if instance and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
		return clampSpeedValue(config, instance.Value)
	end

	if typeof(settingOverrides[SPEED_SETTING_NAME]) == "number" then
		return clampSpeedValue(config, settingOverrides[SPEED_SETTING_NAME])
	end

	return clampSpeedValue(config, config.Start or 1)
end

local function applySpeedValue(nextValue)
	local config = SettingsConfig[SPEED_SETTING_NAME]
	if typeof(config) ~= "table" then
		return 1
	end

	local clamped = clampSpeedValue(config, nextValue)
	local instance = resolveSettingInstance(SPEED_SETTING_NAME, config)
	if instance and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
		instance.Value = clamped
	else
		settingOverrides[SPEED_SETTING_NAME] = clamped
	end

	local _, maximum = getSliderBounds(config)
	local autoMax = clamped >= maximum
	local autoInstance = getFromPath(player, config.AutoMaxPath or "Settings.SpeedAutoMax")
	if autoInstance and autoInstance:IsA("BoolValue") then
		autoInstance.Value = autoMax
	else
		settingOverrides[SPEED_AUTO_MAX_SETTING_NAME] = autoMax
	end

	return clamped
end

local function fireSpeedValue(nextValue)
	local config = SettingsConfig[SPEED_SETTING_NAME]
	if typeof(config) ~= "table" then
		return
	end

	UpdateSettingRemote:FireServer(SPEED_SETTING_NAME, config.Path or "", nextValue)
end

local function getHud()
	return playerGui:FindFirstChild("HUD")
end

local function ensureHost()
	local hud = getHud()
	if not hud then
		return nil
	end

	local host = hud:FindFirstChild("ReactSpeedModifierLayer")
	if not (host and host:IsA("Frame")) then
		host = Instance.new("Frame")
		host.Name = "ReactSpeedModifierLayer"
		host.Parent = hud
	end

	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.ClipsDescendants = false
	host.Position = UDim2.fromScale(0, 0)
	host.Size = UDim2.fromScale(1, 1)
	host.ZIndex = 135
	return host
end

local function findSpeedButton()
	local hud = getHud()
	local buttons = hud and hud:FindFirstChild("LButtons")
	local button = buttons and buttons:FindFirstChild(BUTTON_NAME)
	if button and button:IsA("GuiButton") then
		return button
	end

	return nil
end

local function getPanelPosition(button, host)
	if not (button and host) then
		return UDim2.fromOffset(12, 320)
	end

	local compact = Responsive.isCompact()
	local hostPosition = host.AbsolutePosition
	local buttonPosition = button.AbsolutePosition
	local buttonSize = button.AbsoluteSize
	local x = buttonPosition.X + buttonSize.X + 10 - hostPosition.X
	local y = buttonPosition.Y - hostPosition.Y

	if compact then
		x = buttonPosition.X - hostPosition.X
		y = buttonPosition.Y + buttonSize.Y + 8 - hostPosition.Y
	end

	return UDim2.fromOffset(math.max(4, x), math.max(4, y))
end

local function SpeedPanel(props)
	if not props.visible then
		return nil
	end

	local trackRef = React.useRef(nil)
	local displayValue, setDisplayValue = React.useState(props.value)
	local displayValueRef = React.useRef(props.value)
	local draggingRef = React.useRef(false)
	local inputChangedRef = React.useRef(nil)
	local inputEndedRef = React.useRef(nil)
	local renderSteppedRef = React.useRef(nil)

	local compact = Responsive.isCompact()
	local minValue = roundNumber(props.min or 1)
	local maxValue = math.max(minValue, roundNumber(props.max or minValue))
	local sliderRange = math.max(0, maxValue - minValue)
	local progress = if sliderRange > 0 then math.clamp((displayValue - minValue) / sliderRange, 0, 1) else 1
	local width = compact and 218 or 294
	local height = compact and 84 or 92

	local function disconnectDrag()
		if inputChangedRef.current then
			inputChangedRef.current:Disconnect()
			inputChangedRef.current = nil
		end
		if inputEndedRef.current then
			inputEndedRef.current:Disconnect()
			inputEndedRef.current = nil
		end
		if renderSteppedRef.current then
			renderSteppedRef.current:Disconnect()
			renderSteppedRef.current = nil
		end
	end

	local function preview(nextValue)
		local clamped = props.clampValue(nextValue)
		displayValueRef.current = clamped
		setDisplayValue(clamped)
		props.onPreview(clamped)
	end

	local function commit(nextValue)
		local clamped = props.clampValue(nextValue)
		displayValueRef.current = clamped
		setDisplayValue(clamped)
		props.onCommit(clamped)
	end

	local function valueFromScreenX(screenX)
		local track = trackRef.current
		if not track then
			return displayValueRef.current
		end

		local trackWidth = track.AbsoluteSize.X
		if trackWidth <= 0 then
			return displayValueRef.current
		end

		local normalized = math.clamp((screenX - track.AbsolutePosition.X) / trackWidth, 0, 1)
		return minValue + (normalized * sliderRange)
	end

	local function endDrag()
		if not draggingRef.current then
			return
		end

		draggingRef.current = false
		disconnectDrag()
		commit(displayValueRef.current)
	end

	local function startDrag(screenX)
		draggingRef.current = true
		preview(valueFromScreenX(screenX))
		disconnectDrag()

		inputChangedRef.current = UserInputService.InputChanged:Connect(function(input)
			if not draggingRef.current then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				preview(valueFromScreenX(input.Position.X))
			end
		end)

		inputEndedRef.current = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				endDrag()
			end
		end)

		renderSteppedRef.current = RunService.RenderStepped:Connect(function()
			if draggingRef.current then
				preview(valueFromScreenX(UserInputService:GetMouseLocation().X))
			end
		end)
	end

	local function beginDrag(_, input)
		local inputType = input and input.UserInputType
		if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end

		startDrag(input.Position.X)
	end

	React.useEffect(function()
		if not draggingRef.current then
			local synced = props.clampValue(props.value)
			displayValueRef.current = synced
			setDisplayValue(synced)
		end
		return nil
	end, { props.value, minValue, maxValue })

	React.useEffect(function()
		return function()
			draggingRef.current = false
			disconnectDrag()
		end
	end, {})

	local function nudge(delta)
		commit(displayValueRef.current + delta)
	end

	return e("Frame", {
		BackgroundColor3 = Color3.fromRGB(11, 24, 40),
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Position = props.position,
		Size = UDim2.fromOffset(width, height),
		ZIndex = 136,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(242, 209, 107),
			Thickness = 1.5,
			Transparency = 0.08,
		}),
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(23, 44, 70)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 16, 29)),
			}),
			Rotation = 90,
		}),
		Icon = e("ImageLabel", {
			BackgroundTransparency = 1,
			Image = SPEED_ICON_ASSET,
			Position = UDim2.fromOffset(10, 10),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(compact and 32 or 40, compact and 32 or 40),
			ZIndex = 138,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(compact and 50 or 60, 10),
			Size = UDim2.new(1, compact and -96 or -118, 0, compact and 18 or 22),
			Text = "Speed Changer",
			TextColor3 = Color3.fromRGB(247, 249, 255),
			TextSize = compact and 14 or 18,
			TextStrokeColor3 = Color3.fromRGB(5, 10, 18),
			TextStrokeTransparency = 0.25,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 138,
		}),
		MaxLabel = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(compact and 50 or 60, compact and 28 or 34),
			Size = UDim2.new(1, compact and -96 or -118, 0, 16),
			Text = "Max " .. tostring(maxValue),
			TextColor3 = Color3.fromRGB(242, 209, 107),
			TextSize = compact and 10 or 12,
			TextStrokeColor3 = Color3.fromRGB(5, 10, 18),
			TextStrokeTransparency = 0.35,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 138,
		}),
		Value = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.new(1, -10, 0, compact and 13 or 16),
			Size = UDim2.fromOffset(compact and 38 or 46, 24),
			Text = tostring(displayValue),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			TextStrokeColor3 = Color3.fromRGB(6, 10, 18),
			TextStrokeTransparency = 0.2,
			ZIndex = 138,
		}, {
			Constraint = e("UITextSizeConstraint", {
				MaxTextSize = compact and 18 or 22,
				MinTextSize = 9,
			}),
		}),
		Minus = e("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(27, 46, 68),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromOffset(10, compact and 56 or 62),
			Size = UDim2.fromOffset(compact and 24 or 28, compact and 22 or 24),
			Text = "-",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = compact and 18 or 20,
			ZIndex = 138,
			[React.Event.Activated] = function()
				nudge(-1)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),
		}),
		Plus = e("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(212, 175, 55),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.new(1, -10, 0, compact and 56 or 62),
			Size = UDim2.fromOffset(compact and 24 or 28, compact and 22 or 24),
			Text = "+",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextSize = compact and 18 or 20,
			TextStrokeColor3 = Color3.fromRGB(6, 10, 18),
			TextStrokeTransparency = 0.35,
			ZIndex = 138,
			[React.Event.Activated] = function()
				nudge(1)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),
		}),
		Track = e("TextButton", {
			ref = trackRef,
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(compact and 42 or 48, compact and 56 or 62),
			Size = UDim2.new(1, compact and -84 or -96, 0, compact and 22 or 24),
			Text = "",
			ZIndex = 138,
			[React.Event.InputBegan] = beginDrag,
		}, {
			Bar = e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Color3.fromRGB(8, 16, 29),
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(1, 0, 0, 8),
				ZIndex = 139,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Fill = e("Frame", {
					BackgroundColor3 = Color3.fromRGB(212, 175, 55),
					BorderSizePixel = 0,
					Size = UDim2.fromScale(progress, 1),
					ZIndex = 140,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
				}),
			}),
			Knob = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(242, 209, 107),
				BorderSizePixel = 0,
				Position = UDim2.new(progress, 0, 0.5, 0),
				Size = UDim2.fromOffset(compact and 18 or 20, compact and 18 or 20),
				ZIndex = 141,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(255, 255, 255),
					Thickness = 1,
					Transparency = 0.1,
				}),
			}),
		}),
	})
end

local function render()
	if destroyed then
		return
	end

	local host = ensureHost()
	local button = findSpeedButton()
	if not host or not button then
		root:render(nil)
		return
	end

	local config = SettingsConfig[SPEED_SETTING_NAME]
	local minimum, maximum = getSliderBounds(config)
	root:render(ReactRoblox.createPortal(e(SpeedPanel, {
		visible = expanded,
		position = getPanelPosition(button, host),
		value = readSpeedValue(),
		min = minimum,
		max = maximum,
		clampValue = function(value)
			return clampSpeedValue(config, value)
		end,
		onPreview = function(value)
			applySpeedValue(value)
		end,
		onCommit = function(value)
			local clamped = applySpeedValue(value)
			fireSpeedValue(clamped)
			scheduleRender()
		end,
	}), host))
end

scheduleRender = function()
	if destroyed or renderQueued then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		render()
	end)
end

local function bindSpeedButton()
	disconnectAll(buttonConnections)
	local button = findSpeedButton()
	if not button then
		return
	end

	trackConnection(button.Activated, function()
		expanded = not expanded
		scheduleRender()
	end, buttonConnections)
end

local function bindSettingFolder(folder)
	disconnectAll(settingConnections)
	settingFolder = folder
	if not folder then
		return
	end

	local function watchInstance(instance)
		if instance:IsA("ValueBase") then
			trackConnection(instance:GetPropertyChangedSignal("Value"), scheduleRender, settingConnections)
		end
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		watchInstance(descendant)
	end

	trackConnection(folder.DescendantAdded, function(descendant)
		watchInstance(descendant)
		scheduleRender()
	end, settingConnections)

	trackConnection(folder.DescendantRemoving, scheduleRender, settingConnections)
end

local function bindEarnedSpeedValue()
	local hidden = player:FindFirstChild("HiddenLeaderstats") or player:WaitForChild("HiddenLeaderstats", 5)
	local speed = hidden and (hidden:FindFirstChild("Speed") or hidden:WaitForChild("Speed", 5))
	if speed and (speed:IsA("NumberValue") or speed:IsA("IntValue")) then
		trackConnection(speed:GetPropertyChangedSignal("Value"), scheduleRender, cleanupConnections)
	end
end

trackConnection(player.ChildAdded, function(child)
	if child.Name == "Settings" then
		bindSettingFolder(child)
		scheduleRender()
	end
end, cleanupConnections)

trackConnection(player.ChildRemoved, function(child)
	if child == settingFolder then
		bindSettingFolder(nil)
		scheduleRender()
	end
end, cleanupConnections)

trackConnection(playerGui.ChildAdded, function(child)
	if child.Name == "HUD" then
		task.defer(function()
			bindSpeedButton()
			scheduleRender()
		end)
	end
end, cleanupConnections)

trackConnection(playerGui.DescendantAdded, function(descendant)
	if descendant.Name == BUTTON_NAME then
		task.defer(function()
			bindSpeedButton()
			scheduleRender()
		end)
	end
end, cleanupConnections)

trackConnection(playerGui.DescendantRemoving, function(descendant)
	if descendant.Name == BUTTON_NAME then
		task.defer(function()
			bindSpeedButton()
			scheduleRender()
		end)
	end
end, cleanupConnections)

trackConnection(Workspace:GetPropertyChangedSignal("CurrentCamera"), scheduleRender, cleanupConnections)
if Workspace.CurrentCamera then
	trackConnection(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), scheduleRender, cleanupConnections)
end

bindSettingFolder(player:FindFirstChild("Settings") or player:WaitForChild("Settings", 5))
bindEarnedSpeedValue()
bindSpeedButton()
render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll(cleanupConnections)
	disconnectAll(settingConnections)
	disconnectAll(buttonConnections)
	root:unmount()
end)
