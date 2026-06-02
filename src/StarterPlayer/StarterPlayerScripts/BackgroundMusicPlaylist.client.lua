local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local SettingsAudioController = require(Modules:WaitForChild("SettingsAudioController"))

local MUSIC_SOUND_NAMES = {
	"BGMUSIC",
	"Music",
	"BackgroundMusic",
}

local ALTERNATE_MUSIC_SOUND_ID = "rbxassetid://106866227324743"
local MUSIC_SOUND_NAME = "BGMUSIC"
local DEFAULT_VOLUME = 0.5
local START_WAIT_SECONDS = 10

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

local function findExistingMusicSound()
	for _, name in ipairs(MUSIC_SOUND_NAMES) do
		local sound = SoundService:FindFirstChild(name)
		if sound and sound:IsA("Sound") then
			return sound
		end
		if sound then
			local nestedSound = sound:FindFirstChildWhichIsA("Sound", true)
			if nestedSound then
				return nestedSound
			end
		end
	end
	return nil
end

local function getOrCreateMusicSound()
	local sound = findExistingMusicSound()
	if sound then
		return sound
	end

	sound = Instance.new("Sound")
	sound.Name = MUSIC_SOUND_NAME
	sound.Volume = DEFAULT_VOLUME
	sound.Parent = SoundService
	return sound
end

local function buildPlaylist(primarySoundId)
	local playlist = {}
	local normalizedPrimary = normalizeSoundId(primarySoundId)
	if normalizedPrimary and normalizedPrimary ~= ALTERNATE_MUSIC_SOUND_ID then
		playlist[#playlist + 1] = normalizedPrimary
	end
	playlist[#playlist + 1] = ALTERNATE_MUSIC_SOUND_ID
	return playlist
end

local musicSound = getOrCreateMusicSound()
local playlist = buildPlaylist(musicSound.SoundId)
local currentTrackIndex = 0
local changingTrack = false

musicSound.Name = MUSIC_SOUND_NAME
musicSound.Looped = false
SettingsAudioController.TrackSound(musicSound)

local function playTrack(trackIndex)
	local soundId = playlist[trackIndex]
	if not soundId then
		return
	end

	changingTrack = true
	currentTrackIndex = trackIndex
	musicSound:Stop()
	musicSound.SoundId = soundId
	musicSound.TimePosition = 0
	musicSound.Looped = false
	SettingsAudioController.TrackSound(musicSound)
	musicSound:Play()
	changingTrack = false
end

local function playNextTrack()
	if #playlist <= 0 then
		return
	end

	local nextTrackIndex = currentTrackIndex + 1
	if nextTrackIndex > #playlist then
		nextTrackIndex = 1
	end
	playTrack(nextTrackIndex)
end

musicSound.Ended:Connect(function()
	if changingTrack then
		return
	end
	playNextTrack()
end)

task.delay(START_WAIT_SECONDS, function()
	if not musicSound.Parent then
		return
	end

	if #playlist == 1 then
		playTrack(1)
		return
	end

	local currentSoundId = normalizeSoundId(musicSound.SoundId)
	for index, soundId in ipairs(playlist) do
		if soundId == currentSoundId then
			currentTrackIndex = index
			break
		end
	end

	musicSound.Looped = false
	if not musicSound.IsPlaying then
		playNextTrack()
	end
end)
