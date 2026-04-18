local SoundService = game:GetService("SoundService")

local SettingsAudioController = {}

local MUSIC_GROUP_NAME = "GLRSettingsMusic"
local EFFECTS_GROUP_NAME = "GLRSettingsSoundEffects"
local BASE_VOLUME_ATTRIBUTE = "BaseVolume"
local CREATED_GROUP_ATTRIBUTE = "SettingsAudioCreatedGroup"

local MUSIC_SETTING_NAMES = {
	Music = true,
}

local EFFECT_SETTING_NAMES = {
	SoundEffects = true,
	Sounds = true,
	Souynds = true,
	sounds = true,
}

local musicGroup = nil
local effectsGroup = nil
local currentMusicValue = 100
local currentEffectsValue = 100
local started = false
local debugEnabled = false
local routedDebugCount = 0
local lastApplyLogValue = {}

local trackedSounds = setmetatable({}, { __mode = "k" })
local routedSounds = setmetatable({}, { __mode = "k" })
local originalSoundGroups = setmetatable({}, { __mode = "k" })
local soundCategories = setmetatable({}, { __mode = "k" })
local connections = {}

local function debugAudio(message, ...)
	if not debugEnabled then
		return
	end

	print(string.format("[SETTINGS][AUDIO] " .. message, ...))
end

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

local function normalizeSettingName(settingName)
	if MUSIC_SETTING_NAMES[settingName] then
		return "Music"
	end
	if EFFECT_SETTING_NAMES[settingName] then
		return "SoundEffects"
	end
	return nil
end

local function soundGroupVolume(value)
	return clampNumber(value, 0, 100) / 100
end

local function safeFullName(instance)
	if typeof(instance) ~= "Instance" then
		return "<nil>"
	end

	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)
	return ok and fullName or instance.Name
end

local function findSoundGroup(names)
	for _, name in ipairs(names) do
		local instance = SoundService:FindFirstChild(name)
		if instance and instance:IsA("SoundGroup") then
			return instance
		end
	end
	return nil
end

local function createSoundGroup(name, kind)
	local group = Instance.new("SoundGroup")
	group.Name = name
	group:SetAttribute(CREATED_GROUP_ATTRIBUTE, kind)
	group.Parent = SoundService
	return group
end

local function ensureSoundGroups()
	if not (musicGroup and musicGroup.Parent) then
		musicGroup = findSoundGroup({
			"BGMUSIC",
			"Music",
			"BackgroundMusic",
			"MusicGroup",
			MUSIC_GROUP_NAME,
		}) or createSoundGroup(MUSIC_GROUP_NAME, "Music")
	end

	if not (effectsGroup and effectsGroup.Parent) then
		effectsGroup = findSoundGroup({
			"SoundEffects",
			"Sounds",
			"SFX",
			"Effects",
			EFFECTS_GROUP_NAME,
		}) or createSoundGroup(EFFECTS_GROUP_NAME, "SoundEffects")
	end

	musicGroup.Volume = soundGroupVolume(currentMusicValue)
	effectsGroup.Volume = soundGroupVolume(currentEffectsValue)
	return musicGroup, effectsGroup
end

local function nameLooksLikeMusic(name)
	local lowered = string.lower(tostring(name or ""))
	return lowered == "bgm"
		or lowered == "bgmusic"
		or lowered == "backgroundmusic"
		or string.find(lowered, "music", 1, true) ~= nil
		or string.find(lowered, "theme", 1, true) ~= nil
		or string.find(lowered, "ambient", 1, true) ~= nil
end

local function getMusicRoot()
	return SoundService:FindFirstChild("BGMUSIC")
		or SoundService:FindFirstChild("Music")
		or SoundService:FindFirstChild("BackgroundMusic")
end

local function rememberOriginalSoundGroup(sound)
	if originalSoundGroups[sound] ~= nil then
		local originalGroup = originalSoundGroups[sound]
		return originalGroup ~= false and originalGroup or nil
	end

	local originalGroup = sound.SoundGroup
	originalSoundGroups[sound] = originalGroup or false
	return originalGroup
end

local function isMusicSound(sound)
	local musicRoot = getMusicRoot()
	if musicRoot then
		if sound == musicRoot or sound:IsDescendantOf(musicRoot) then
			return true
		end
	end

	local originalGroup = rememberOriginalSoundGroup(sound)
	if originalGroup and originalGroup:IsA("SoundGroup") then
		if musicRoot and (originalGroup == musicRoot or originalGroup:IsDescendantOf(musicRoot)) then
			return true
		end
		if nameLooksLikeMusic(originalGroup.Name) then
			return true
		end
	end

	if nameLooksLikeMusic(sound.Name) then
		return true
	end

	local ancestor = sound.Parent
	while ancestor and ancestor ~= game do
		if nameLooksLikeMusic(ancestor.Name) then
			return true
		end
		ancestor = ancestor.Parent
	end

	return false
end

local function getSoundCategory(sound)
	local category = soundCategories[sound]
	if category then
		return category
	end

	category = if isMusicSound(sound) then "Music" else "SoundEffects"
	soundCategories[sound] = category
	return category
end

local function getBaseVolume(sound)
	local baseVolume = sound:GetAttribute(BASE_VOLUME_ATTRIBUTE)
	if typeof(baseVolume) == "number" then
		return baseVolume
	end

	baseVolume = sound.Volume
	sound:SetAttribute(BASE_VOLUME_ATTRIBUTE, baseVolume)
	return baseVolume
end

local function routeSound(sound)
	if typeof(sound) ~= "Instance" or not sound:IsA("Sound") or sound.Parent == nil then
		trackedSounds[sound] = nil
		routedSounds[sound] = nil
		originalSoundGroups[sound] = nil
		soundCategories[sound] = nil
		return
	end

	local targetMusicGroup, targetEffectsGroup = ensureSoundGroups()
	local category = getSoundCategory(sound)
	local targetGroup = if category == "Music" then targetMusicGroup else targetEffectsGroup
	local baseVolume = getBaseVolume(sound)

	trackedSounds[sound] = true
	if sound.SoundGroup ~= targetGroup then
		sound.SoundGroup = targetGroup
	end

	if not routedSounds[sound] then
		sound.Volume = baseVolume
		routedSounds[sound] = true
		if debugEnabled and routedDebugCount < 40 then
			routedDebugCount += 1
			debugAudio(
				"routeSound path=%s category=%s group=%s baseVolume=%.3f",
				safeFullName(sound),
				category,
				targetGroup.Name,
				baseVolume
			)
		end
	end
end

local function getStats()
	local musicCount = 0
	local effectsCount = 0

	for sound in pairs(trackedSounds) do
		if typeof(sound) == "Instance" and sound:IsA("Sound") and sound.Parent ~= nil then
			if getSoundCategory(sound) == "Music" then
				musicCount += 1
			else
				effectsCount += 1
			end
		else
			trackedSounds[sound] = nil
		end
	end

	local targetMusicGroup, targetEffectsGroup = ensureSoundGroups()
	return {
		musicValue = currentMusicValue,
		effectsValue = currentEffectsValue,
		musicSounds = musicCount,
		effectSounds = effectsCount,
		musicGroup = targetMusicGroup,
		effectsGroup = targetEffectsGroup,
	}
end

local function routeAllSounds()
	ensureSoundGroups()
	for _, descendant in ipairs(game:GetDescendants()) do
		if descendant:IsA("Sound") then
			routeSound(descendant)
		end
	end

	for sound in pairs(trackedSounds) do
		routeSound(sound)
	end

	local stats = getStats()
	debugAudio(
		"routeAll musicGroup=%s musicVolume=%.2f effectsGroup=%s effectsVolume=%.2f musicSounds=%d effectSounds=%d",
		stats.musicGroup.Name,
		stats.musicGroup.Volume,
		stats.effectsGroup.Name,
		stats.effectsGroup.Volume,
		stats.musicSounds,
		stats.effectSounds
	)
	return stats
end

local function clearCategoriesAndRouteAll()
	table.clear(soundCategories)
	task.defer(routeAllSounds)
end

function SettingsAudioController.SetDebug(enabled)
	debugEnabled = enabled == true
end

function SettingsAudioController.Start()
	if started then
		return getStats()
	end

	started = true
	debugAudio("start")
	local stats = routeAllSounds()

	table.insert(connections, game.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			routeSound(descendant)
		elseif descendant:IsA("SoundGroup") or nameLooksLikeMusic(descendant.Name) then
			clearCategoriesAndRouteAll()
		end
	end))

	table.insert(connections, game.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("Sound") then
			trackedSounds[descendant] = nil
			routedSounds[descendant] = nil
			originalSoundGroups[descendant] = nil
			soundCategories[descendant] = nil
		elseif descendant:IsA("SoundGroup") or nameLooksLikeMusic(descendant.Name) then
			clearCategoriesAndRouteAll()
		end
	end))

	return stats
end

function SettingsAudioController.Apply(settingName, value)
	local normalizedSettingName = normalizeSettingName(settingName)
	if not normalizedSettingName then
		return nil
	end

	local clamped = math.floor(clampNumber(value, 0, 100) + 0.5)
	if normalizedSettingName == "Music" then
		currentMusicValue = clamped
	else
		currentEffectsValue = clamped
	end

	if not started then
		SettingsAudioController.Start()
	end

	ensureSoundGroups()
	local stats = getStats()
	local lastLoggedValue = lastApplyLogValue[normalizedSettingName]
	if
		lastLoggedValue == nil
		or clamped == 0
		or clamped == 100
		or math.abs(clamped - lastLoggedValue) >= 10
	then
		lastApplyLogValue[normalizedSettingName] = clamped
		debugAudio(
			"applySetting name=%s value=%d musicGroup=%s musicVolume=%.2f effectsGroup=%s effectsVolume=%.2f musicSounds=%d effectSounds=%d",
			normalizedSettingName,
			clamped,
			stats.musicGroup.Name,
			stats.musicGroup.Volume,
			stats.effectsGroup.Name,
			stats.effectsGroup.Volume,
			stats.musicSounds,
			stats.effectSounds
		)
	end

	return stats
end

function SettingsAudioController.TrackSound(sound)
	if not started then
		SettingsAudioController.Start()
	end
	routeSound(sound)
	return getStats()
end

function SettingsAudioController.GetStats()
	return getStats()
end

function SettingsAudioController.Destroy()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	started = false
end

return SettingsAudioController
