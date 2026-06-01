local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local GameSounds = {}
local soundIdStates = {}

local SettingsAudioController = nil
if RunService:IsClient() then
	local modules = ReplicatedStorage:WaitForChild("Modules")
	local ok, controller = pcall(function()
		return require(modules:WaitForChild("SettingsAudioController"))
	end)
	if ok then
		SettingsAudioController = controller
	end
end

GameSounds.Ids = {
	Mogu = {
		BurrowStart = "rbxassetid://76047926674112",
		BurrowEnd = "rbxassetid://125695644220520",
		BurrowLoop = "rbxassetid://87985599354437",
	},
	UI = {
		Click = "rbxassetid://97452802678885",
		Hover = "rbxassetid://86950430462158",
	},
	Hazards = {
		Wave = "rbxassetid://131039529372547",
		Debuff = "rbxassetid://124797032347737",
		Trap = "rbxassetid://112689184290021",
		CannonExplosion = "rbxassetid://75467187901827",
	},
}

local function normalizeSoundId(soundId)
	if typeof(soundId) == "number" then
		return "rbxassetid://" .. tostring(soundId)
	end
	if typeof(soundId) ~= "string" or soundId == "" then
		return nil
	end
	if string.find(soundId, "rbxassetid://", 1, true) == 1 then
		return soundId
	end
	return "rbxassetid://" .. soundId
end

local function trackSound(sound)
	if SettingsAudioController and typeof(SettingsAudioController.TrackSound) == "function" then
		SettingsAudioController.TrackSound(sound)
	end
end

local function getFetchStatusName(soundId)
	local ok, status = pcall(function()
		return ContentProvider:GetAssetFetchStatus(soundId)
	end)
	if not ok or typeof(status) ~= "EnumItem" then
		return nil
	end
	return status.Name
end

local function updateSoundIdStateFromFetchStatus(soundId)
	local statusName = getFetchStatusName(soundId)
	if statusName == "Success" then
		soundIdStates[soundId] = "loaded"
	elseif statusName == "Failure" or statusName == "TimedOut" then
		soundIdStates[soundId] = "failed"
	end
	return soundIdStates[soundId]
end

local function shouldSkipSoundId(soundId, options)
	local state = soundIdStates[soundId] or updateSoundIdStateFromFetchStatus(soundId)
	if state == "failed" then
		return true
	end
	if state == "loading" and not (options and options.AllowDuplicateWhileLoading == true) then
		return true
	end
	return false
end

local function watchSoundLoadState(sound, soundId)
	if not sound or not soundId then
		return
	end

	if sound.IsLoaded then
		soundIdStates[soundId] = "loaded"
		return
	end

	if soundIdStates[soundId] ~= "loaded" then
		soundIdStates[soundId] = "loading"
	end

	local connections = {}
	local function disconnect()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	local function refresh()
		if sound.IsLoaded then
			soundIdStates[soundId] = "loaded"
			disconnect()
			return
		end

		local state = updateSoundIdStateFromFetchStatus(soundId)
		if state == "failed" then
			disconnect()
			if sound.Parent then
				sound:Destroy()
			end
		end
	end

	table.insert(connections, sound:GetPropertyChangedSignal("IsLoaded"):Connect(refresh))
	local ok, signal = pcall(function()
		return ContentProvider:GetAssetFetchStatusChangedSignal(soundId)
	end)
	if ok and signal then
		table.insert(connections, signal:Connect(refresh))
	end

	task.delay(8, function()
		if soundIdStates[soundId] == "loading" and sound.Parent and not sound.IsLoaded then
			updateSoundIdStateFromFetchStatus(soundId)
		end
		if soundIdStates[soundId] ~= "loading" or not sound.Parent then
			disconnect()
		end
	end)
end

local function configureSound(sound, soundId, options)
	options = if typeof(options) == "table" then options else {}
	sound.Name = tostring(options.Name or "GLRSound")
	sound.SoundId = normalizeSoundId(soundId) or ""
	sound.Volume = math.max(0, tonumber(options.Volume) or 1)
	sound.PlaybackSpeed = math.max(0.01, tonumber(options.PlaybackSpeed) or 1)
	sound.Looped = options.Looped == true
	sound.RollOffMaxDistance = math.max(0, tonumber(options.RollOffMaxDistance) or 110)
	sound.RollOffMinDistance = math.max(0, tonumber(options.RollOffMinDistance) or 8)
	sound.RollOffMode = options.RollOffMode or Enum.RollOffMode.InverseTapered
	return sound
end

function GameSounds.CreateSound(soundId, options)
	local normalizedSoundId = normalizeSoundId(soundId)
	if not normalizedSoundId then
		return nil
	end
	if shouldSkipSoundId(normalizedSoundId, options) then
		return nil
	end

	local sound = Instance.new("Sound")
	configureSound(sound, normalizedSoundId, options)
	watchSoundLoadState(sound, normalizedSoundId)
	return sound
end

function GameSounds.Play2D(soundId, options)
	local sound = GameSounds.CreateSound(soundId, options)
	if not sound then
		return nil
	end

	sound.Parent = SoundService
	trackSound(sound)
	sound:Play()
	sound.Ended:Connect(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	Debris:AddItem(sound, math.max(2, tonumber(options and options.Lifetime) or 6))
	return sound
end

function GameSounds.PlayOnInstance(soundId, parent, options)
	if typeof(parent) ~= "Instance" then
		return GameSounds.Play2D(soundId, options)
	end

	local sound = GameSounds.CreateSound(soundId, options)
	if not sound then
		return nil
	end

	sound.Parent = parent
	trackSound(sound)
	sound:Play()
	if sound.Looped ~= true then
		sound.Ended:Connect(function()
			if sound.Parent then
				sound:Destroy()
			end
		end)
		Debris:AddItem(sound, math.max(2, tonumber(options and options.Lifetime) or 6))
	end
	return sound
end

function GameSounds.PlayAtPosition(soundId, position, options)
	if typeof(position) ~= "Vector3" then
		return GameSounds.Play2D(soundId, options)
	end

	options = if typeof(options) == "table" then options else {}
	local anchor = Instance.new("Part")
	anchor.Name = tostring(options.AnchorName or "GLRSoundAnchor")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Parent = options.Parent or Workspace

	local sound = GameSounds.CreateSound(soundId, options)
	if not sound then
		anchor:Destroy()
		return nil
	end

	sound.Parent = anchor
	trackSound(sound)
	sound:Play()
	if sound.Looped ~= true then
		sound.Ended:Connect(function()
			if anchor.Parent then
				anchor:Destroy()
			end
		end)
		Debris:AddItem(anchor, math.max(2, tonumber(options.Lifetime) or 6))
	end
	return sound, anchor
end

return GameSounds
