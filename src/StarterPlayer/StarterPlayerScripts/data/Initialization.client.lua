local Start = tick()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Player = Players.LocalPlayer
local REMOTES_FOLDER_NAME = "Remotes"
local LOAD_TELEMETRY_REMOTE_NAME = "GTRLoadTelemetry"
local SLOW_LOAD_THRESHOLD_SECONDS = 12

local function getDuration(): number
	return math.max(0, tick() - Start)
end

local function sanitizeLogValue(value)
	return (tostring(value):gsub("%s+", "_"))
end

local function gtrLoadLog(status: string, reason: string, extras: {[string]: any}?, useWarn: boolean?)
	local fields = {
		"[GTR_LOAD]",
		"player=" .. sanitizeLogValue(Player.Name),
		"userId=" .. tostring(Player.UserId),
		"status=" .. sanitizeLogValue(status),
		string.format("duration=%.2f", getDuration()),
		"reason=" .. sanitizeLogValue(reason),
	}

	if extras then
		for key, value in pairs(extras) do
			fields[#fields + 1] = sanitizeLogValue(key) .. "=" .. sanitizeLogValue(value)
		end
	end

	local message = table.concat(fields, " ")
	if useWarn then
		warn(message)
	else
		print(message)
	end
end

local function getDeviceInputType(): string
	local ok, inputType = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and inputType then
		return tostring(inputType.Name)
	end
	if UserInputService.TouchEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled then
		return "Gamepad"
	end
	if UserInputService.KeyboardEnabled then
		return "Keyboard"
	end
	return "unknown"
end

local function submitDataInitTelemetry(errorMessage: string)
	local payload = {
		UserId = Player.UserId,
		JoinTimestamp = os.time(),
		LoadDuration = getDuration(),
		CloseReason = "data_init_error",
		TimedOut = false,
		OverlayRecovery = false,
		CameraRecovery = false,
		MissingMilestones = "StartupDataRequestSent",
		DeviceInputType = getDeviceInputType(),
		BootstrapError = false,
		DataInitError = true,
		SlowThresholdSeconds = SLOW_LOAD_THRESHOLD_SECONDS,
		Error = tostring(errorMessage):sub(1, 180),
	}

	task.spawn(function()
		local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
			or ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 5)
		if not remotes then
			return
		end

		local remote = remotes:FindFirstChild(LOAD_TELEMETRY_REMOTE_NAME)
			or remotes:WaitForChild(LOAD_TELEMETRY_REMOTE_NAME, 5)
		if remote and remote:IsA("RemoteEvent") then
			pcall(function()
				remote:FireServer(payload)
			end)
		end
	end)
end

local function markDataRequestSent()
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local startupStateScript = modules and modules:FindFirstChild("StartupState")
	if startupStateScript and startupStateScript:IsA("ModuleScript") then
		local ok, StartupState = pcall(require, startupStateScript)
		if ok and typeof(StartupState) == "table" and StartupState.MarkDataRequestSent then
			if StartupState.MarkDataRequestSent(Player) then
				return
			end
		end
	end

	local playerGui = Player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute("StartupDataRequestSent", true)
		return
	end

	task.spawn(function()
		playerGui = Player:WaitForChild("PlayerGui", 2)
		if playerGui then
			playerGui:SetAttribute("StartupDataRequestSent", true)
		end
	end)
end

local function runDataInitialization()
	local DataScript = require(script.Parent.Client_Data)
	DataScript.New("PlayerDataStore")
	markDataRequestSent()

	local ready = DataScript.WaitUntilReady(30)
	if ready then
		DataScript:GetData()
		print("Client {RP} took " .. (tick() - Start) .. "s to load!")
	else
		warn(string.format(
			"[ClientData] Timed out waiting for PlayerDataStore for %s(%d) after %.1fs; continuing startup.",
			Player.Name,
			Player.UserId,
			tick() - Start
		))
	end
end

local ok, err = xpcall(runDataInitialization, debug.traceback)
markDataRequestSent()
if not ok then
	local message = tostring(err)
	gtrLoadLog("milestone_recovered", "data_init_error", {
		error = message:sub(1, 180),
	}, true)
	submitDataInitTelemetry(message)
end
