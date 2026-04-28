local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientEffectVisuals = {}
ClientEffectVisuals.__index = ClientEffectVisuals

local SharedFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared")
local AnimationResolver = require(SharedFolder:WaitForChild("AnimationResolver"))

local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local DEFAULT_MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_MERA_FRUIT_NAME = "Mera Mera no Mi"
local DEFAULT_FIRE_BURST_ABILITY = "FireBurst"
local DEFAULT_BOMU_FRUIT_NAME = "Bomu Bomu no Mi"
local DEFAULT_BOMU_DETONATION_ABILITY = "LandMine"
local DEFAULT_PHOENIX_FRUIT_NAME = "Tori Tori no Mi"
local DEFAULT_PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local DEFAULT_PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local DEFAULT_PHOENIX_REBIRTH_ABILITY = "PhoenixRebirth"
local DEFAULT_GOMU_FRUIT_NAME = "Gomu Gomu no Mi"
local DEFAULT_RUBBER_LAUNCH_ABILITY = "RubberLaunch"
local DEFAULT_PHOENIX_EFFECT_COLOR = Color3.fromRGB(108, 255, 214)
local DEFAULT_PHOENIX_EFFECT_ACCENT_COLOR = Color3.fromRGB(255, 188, 113)
local PHOENIX_SHIELD_HIT_COLOR = Color3.fromRGB(255, 48, 72)
local PHOENIX_SHIELD_HIT_ACCENT_COLOR = Color3.fromRGB(255, 169, 103)
local FLAT_RING_ROTATION = CFrame.Angles(0, 0, math.rad(90))
local DEFAULT_PHOENIX_SHIELD_RADIUS = 18
local PHOENIX_SHIELD_AUTHORED_REFERENCE_RADIUS = 13
local PHOENIX_WING_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local PHOENIX_WING_ASSET_FRUIT_KEY = "Tori"
local PHOENIX_WING_ASSET_FOLDER_NAMES = { "VFX", "Visuals", "CharacterModels" }
local PHOENIX_WING_ASSET_NAMES = { "PhoenixMan", "Phoenix Man", "Phoenix man", "Phoenix man (1)" }
local PHOENIX_AUTHORED_FLIGHT_FX_NAME = "FlyFX"
local PHOENIX_AUTHORED_SHIELD_FX_NAME = "ShieldFX"
local PHOENIX_AUTHORED_REVIVE_FX_NAME = "ReviveFX"
local PHOENIX_AUTHORED_VFX_FADE_OUT = 0.35
local PHOENIX_AUTHORED_REVIVE_FX_ACTIVE_TIME = 0.12
local PHOENIX_AUTHORED_REVIVE_FX_CLEANUP_BUFFER = 0.45
local PHOENIX_AUTHORED_VFX_MOVE_FOLDERS = {
	FlyFX = { "Phoenix Flight" },
	ShieldFX = { "Phoenix Flame Shield" },
	ReviveFX = { "Phoenix Revive" },
}
local PHOENIX_AUTHORED_VFX_REFERENCE_FIRST = {
	ShieldFX = true,
}
local PHOENIX_AUTHORED_VFX_DEFAULT_OFFSETS = {
	FlyFX = CFrame.new(0.165275574, -1.16604078, 1.30423737),
	ShieldFX = CFrame.new(0.165275574, 0.272972107, 0.601654053),
	-- Workspace.Phoenix Man.ReviveFX is centered on the rig torso/root.
	ReviveFX = CFrame.new(),
}
local PHOENIX_ANIMATION_KEYS = {
	FlightStart = "Tori.PhoenixFlightStart",
	FlightLoop = "Tori.PhoenixFlightLoop",
	FlightIdle = "Tori.PhoenixFlightIdle",
	FlightEnd = "Tori.PhoenixFlightEnd",
	Shield = "Tori.PhoenixFlameShield",
	Rebirth = "Tori.PhoenixRevive",
}
local PHOENIX_ANIMATION_LENGTHS = {
	["Tori.PhoenixFlightStart"] = 3.1666667,
	["Tori.PhoenixFlightLoop"] = 5.2,
	["Tori.PhoenixFlightIdle"] = 1,
	["Tori.PhoenixFlightEnd"] = 1.2,
	["Tori.PhoenixFlameShield"] = 1.6666667,
	["Tori.PhoenixRevive"] = 2.4,
}
local PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP = "PhoenixFlightSustain"
local PHOENIX_FLIGHT_IDLE_SPEED_THRESHOLD = 2.5
local PHOENIX_FLIGHT_MOVE_SPEED_THRESHOLD = 5
local PHOENIX_REFERENCE_PART_NAMES = { "Torso", "UpperTorso", "HumanoidRootPart" }
local PHOENIX_FLIGHT_TRAIL_PART_NAMES = { "Tail1", "tail", "Torso", "UpperTorso", "HumanoidRootPart" }
local PHOENIX_LEFT_LEG_REFERENCE_PART_NAMES = { "Left Leg", "LeftLowerLeg", "LeftFoot", "LeftUpperLeg" }
local PHOENIX_RIGHT_LEG_REFERENCE_PART_NAMES = { "Right Leg", "RightLowerLeg", "RightFoot", "RightUpperLeg" }
local PHOENIX_FEATURE_MODEL_SPECS = {
	{
		ModelName = "tori wings",
		SourcePartNames = PHOENIX_REFERENCE_PART_NAMES,
		TargetPartNames = PHOENIX_REFERENCE_PART_NAMES,
	},
	{
		ModelName = "tori left leg",
		SourcePartNames = PHOENIX_LEFT_LEG_REFERENCE_PART_NAMES,
		TargetPartNames = PHOENIX_LEFT_LEG_REFERENCE_PART_NAMES,
	},
	{
		ModelName = "tori right leg",
		SourcePartNames = PHOENIX_RIGHT_LEG_REFERENCE_PART_NAMES,
		TargetPartNames = PHOENIX_RIGHT_LEG_REFERENCE_PART_NAMES,
	},
}
local PHOENIX_CHARACTER_CONCEALED_PART_NAMES = {
	leftarm = true,
	rightarm = true,
	leftleg = true,
	rightleg = true,
	leftupperarm = true,
	leftlowerarm = true,
	lefthand = true,
	rightupperarm = true,
	rightlowerarm = true,
	righthand = true,
	leftupperleg = true,
	leftlowerleg = true,
	leftfoot = true,
	rightupperleg = true,
	rightlowerleg = true,
	rightfoot = true,
}
local PHOENIX_WING_MIN_DURATION = 0.1
local PHOENIX_WING_FALLBACK_DURATION = 0.75
local PHOENIX_FEATURE_ROOT_PART_NAME = "RootPart"
local PHOENIX_ANIMATION_FADE_TIME = 0.08
local PHOENIX_ANIMATION_STOP_FADE_TIME = 0.12
local PHOENIX_FLIGHT_LOOP_FALLBACK_DELAY = 0.42
local PHOENIX_FLIGHT_STARTUP_FALLBACK_DURATION = 0.85
local PHOENIX_FLIGHT_TRAIL_DIRECTION_MIN_SPEED = 1.5

local function resolvePlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function resolvePlayerHumanoid(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function resolvePlayerBodyPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("HumanoidRootPart")
end

local function resolveColor(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function createPulse(name, position, color, initialSize, finalSize, duration)
	local pulse = Instance.new("Part")
	pulse.Name = name
	pulse.Shape = Enum.PartType.Ball
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanTouch = false
	pulse.CanQuery = false
	pulse.Material = Enum.Material.Neon
	pulse.Color = color
	pulse.Transparency = 0.18
	pulse.Size = Vector3.new(initialSize, initialSize, initialSize)
	pulse.CFrame = CFrame.new(position)
	pulse.Parent = Workspace

	local tween = TweenService:Create(pulse, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(finalSize, finalSize, finalSize),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if pulse.Parent then
			pulse:Destroy()
		end
	end)
end

local function getOrCreateWingEffectsFolder()
	local folder = Workspace:FindFirstChild(PHOENIX_WING_EFFECTS_FOLDER_NAME)
	if folder then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = PHOENIX_WING_EFFECTS_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function resolvePhoenixAssetInContainer(container)
	if not container then
		return nil
	end

	for _, assetName in ipairs(PHOENIX_WING_ASSET_NAMES) do
		local direct = container:FindFirstChild(assetName)
		if direct then
			return direct
		end
	end

	for _, assetName in ipairs(PHOENIX_WING_ASSET_NAMES) do
		local descendant = container:FindFirstChild(assetName, true)
		if descendant then
			return descendant
		end
	end

	for _, child in ipairs(container:GetChildren()) do
		if string.find(string.lower(child.Name), "phoenix", 1, true) then
			return child
		end
	end

	local children = container:GetChildren()
	return if #children == 1 then children[1] else nil
end

local function appendUniqueInstance(target, seen, instance)
	if typeof(instance) ~= "Instance" or seen[instance] then
		return
	end

	seen[instance] = true
	target[#target + 1] = instance
end

local function appendPhoenixModelCandidatesFromContainer(target, seen, container)
	if not container then
		return
	end

	for _, assetName in ipairs(PHOENIX_WING_ASSET_NAMES) do
		appendUniqueInstance(target, seen, container:FindFirstChild(assetName))
	end

	appendUniqueInstance(target, seen, resolvePhoenixAssetInContainer(container))
	appendUniqueInstance(target, seen, container)
end

local function getPhoenixAssetRootCandidates()
	local roots = {}
	local seen = {}
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		local vfxFolder = assetsFolder:FindFirstChild("VFX")
		local toriVfxFolder = vfxFolder and vfxFolder:FindFirstChild(PHOENIX_WING_ASSET_FRUIT_KEY)
		appendPhoenixModelCandidatesFromContainer(roots, seen, toriVfxFolder)

		local characterModelsFolder = assetsFolder:FindFirstChild("CharacterModels")
		local toriCharacterFolder = characterModelsFolder and characterModelsFolder:FindFirstChild(PHOENIX_WING_ASSET_FRUIT_KEY)
		appendPhoenixModelCandidatesFromContainer(roots, seen, toriCharacterFolder)
	end

	local modulesFolder = ReplicatedStorage:FindFirstChild("Modules")
	local devilFruitsFolder = modulesFolder and modulesFolder:FindFirstChild("DevilFruits")
	local toriFolder = devilFruitsFolder and devilFruitsFolder:FindFirstChild(PHOENIX_WING_ASSET_FRUIT_KEY)
	local moduleAssetsFolder = toriFolder and toriFolder:FindFirstChild("Assets")
	if moduleAssetsFolder then
		for _, folderName in ipairs(PHOENIX_WING_ASSET_FOLDER_NAMES) do
			appendPhoenixModelCandidatesFromContainer(roots, seen, moduleAssetsFolder:FindFirstChild(folderName))
		end

		appendPhoenixModelCandidatesFromContainer(roots, seen, moduleAssetsFolder)
	end

	if RunService:IsStudio() then
		for _, assetName in ipairs(PHOENIX_WING_ASSET_NAMES) do
			appendUniqueInstance(roots, seen, Workspace:FindFirstChild(assetName))
		end
	end

	return roots
end

local function getPhoenixWingAssetRoot()
	for _, assetRoot in ipairs(getPhoenixAssetRootCandidates()) do
		if assetRoot:FindFirstChild("tori wings", true) then
			return assetRoot
		end
	end

	return nil
end

local function findNamedBasePart(root, partName)
	if root:IsA("BasePart") and root.Name == partName then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == partName then
			return descendant
		end
	end

	return nil
end

local function findReferencePart(assetRoot, partNames)
	for _, partName in ipairs(partNames or PHOENIX_REFERENCE_PART_NAMES) do
		local part = findNamedBasePart(assetRoot, partName)
		if part then
			return part
		end
	end

	return nil
end

local function resolvePlayerPartByNames(targetPlayer, partNames)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	for _, partName in ipairs(partNames) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	return nil
end

local function canUseAsFollowTarget(instance)
	return typeof(instance) == "Instance"
		and (
			instance:IsA("BasePart")
			or instance:IsA("Attachment")
			or instance:IsA("Bone")
			or instance:IsA("Model")
		)
end

local function getFollowTargetCFrame(instance)
	if not canUseAsFollowTarget(instance) then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	if instance:IsA("Attachment") or instance:IsA("Bone") then
		return instance.WorldCFrame
	end

	return instance:GetPivot()
end

local function getFollowTargetPosition(instance)
	local cframe = getFollowTargetCFrame(instance)
	return cframe and cframe.Position or nil
end

local function getPlanarDirectionOrNil(vector, minMagnitude)
	if typeof(vector) ~= "Vector3" then
		return nil
	end

	local planarVector = Vector3.new(vector.X, 0, vector.Z)
	if planarVector.Magnitude <= (minMagnitude or DEFAULT_MIN_DIRECTION_MAGNITUDE) then
		return nil
	end

	return planarVector.Unit
end

local function getPhoenixFlightTrailDirection(rootPart, fallbackCFrame, lastDirection)
	if typeof(rootPart) == "Instance" and rootPart:IsA("BasePart") then
		local velocityDirection =
			getPlanarDirectionOrNil(rootPart.AssemblyLinearVelocity, PHOENIX_FLIGHT_TRAIL_DIRECTION_MIN_SPEED)
		if velocityDirection then
			return velocityDirection
		end

		local rootDirection = getPlanarDirectionOrNil(rootPart.CFrame.LookVector, DEFAULT_MIN_DIRECTION_MAGNITUDE)
		if rootDirection then
			return rootDirection
		end
	end

	if typeof(fallbackCFrame) == "CFrame" then
		local fallbackDirection = getPlanarDirectionOrNil(fallbackCFrame.LookVector, DEFAULT_MIN_DIRECTION_MAGNITUDE)
		if fallbackDirection then
			return fallbackDirection
		end
	end

	if typeof(lastDirection) == "Vector3" and lastDirection.Magnitude > DEFAULT_MIN_DIRECTION_MAGNITUDE then
		return lastDirection.Unit
	end

	return DEFAULT_DIRECTION
end

local function getMovementOrientedFollowCFrame(target, rootPart, lastDirection)
	local targetPosition = getFollowTargetPosition(target) or getFollowTargetPosition(rootPart)
	if not targetPosition then
		return nil, lastDirection
	end

	local fallbackCFrame = getFollowTargetCFrame(target) or getFollowTargetCFrame(rootPart)
	local direction = getPhoenixFlightTrailDirection(rootPart, fallbackCFrame, lastDirection)
	return CFrame.lookAt(targetPosition, targetPosition + direction, Vector3.yAxis), direction
end

local function findFollowTargetByNames(root, targetNames)
	if not root or type(targetNames) ~= "table" then
		return nil
	end

	for _, targetName in ipairs(targetNames) do
		if typeof(targetName) == "string" and targetName ~= "" then
			if root.Name == targetName and canUseAsFollowTarget(root) then
				return root
			end

			for _, descendant in ipairs(root:GetDescendants()) do
				if descendant.Name == targetName and canUseAsFollowTarget(descendant) then
					return descendant
				end
			end
		end
	end

	return nil
end

local function resolvePhoenixFollowTarget(targetPlayer, state, targetNames)
	if type(targetNames) ~= "table" then
		return nil
	end

	if state then
		for _, featureState in ipairs(state.Features or {}) do
			local target = findFollowTargetByNames(featureState.Model, targetNames)
			if target then
				return target
			end
		end

		local target = findFollowTargetByNames(state.Container, targetNames)
		if target then
			return target
		end
	end

	if targetPlayer and targetPlayer:IsA("Player") then
		return findFollowTargetByNames(targetPlayer.Character, targetNames)
	end

	return nil
end

local function resolvePartNameList(value, fallback)
	if typeof(value) == "string" and value ~= "" then
		return { value }
	end

	if type(value) == "table" then
		local partNames = {}
		for _, partName in ipairs(value) do
			if typeof(partName) == "string" and partName ~= "" then
				partNames[#partNames + 1] = partName
			end
		end

		if #partNames > 0 then
			return partNames
		end
	end

	return fallback
end

local function resolveCFrameValue(value, fallback)
	if typeof(value) == "CFrame" then
		return value
	end

	if typeof(value) == "Vector3" then
		return CFrame.new(value)
	end

	return fallback
end

local function findFirstBasePart(root)
	if root:IsA("BasePart") then
		return root
	end

	return root:FindFirstChildWhichIsA("BasePart", true)
end

local function findNamedModel(root, modelName)
	local direct = root:FindFirstChild(modelName, true)
	if direct and direct:IsA("Model") then
		return direct
	end

	local normalizedName = string.lower(modelName)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Model") and string.lower(descendant.Name) == normalizedName then
			return descendant
		end
	end

	return nil
end

local function normalizeInstanceName(name)
	return string.lower(string.gsub(name, "%s+", ""))
end

local function configurePhoenixDisplayClone(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant.Name == PHOENIX_FEATURE_ROOT_PART_NAME
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = false
		elseif descendant:IsA("AnimationController") then
			if not descendant:FindFirstChildOfClass("Animator") then
				local animator = Instance.new("Animator")
				animator.Parent = descendant
			end
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("SurfaceAppearance") then
			descendant.AlphaMode = Enum.AlphaMode.Transparency
		end
	end
end

local function applyPhoenixExtremityConceal(targetPlayer)
	local character = targetPlayer.Character
	if not character then
		return {}
	end

	local entries = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		local normalizedName = normalizeInstanceName(descendant.Name)
		if descendant:IsA("BasePart") and PHOENIX_CHARACTER_CONCEALED_PART_NAMES[normalizedName] then
			entries[#entries + 1] = {
				Part = descendant,
				OriginalLocalTransparencyModifier = descendant.LocalTransparencyModifier,
			}
			descendant.LocalTransparencyModifier = 1
		end
	end

	return entries
end

local function refreshPhoenixExtremityConceal(targetPlayer, state)
	if not targetPlayer or not state then
		return
	end

	local character = targetPlayer.Character
	if not character then
		return
	end

	state.ExtremityConcealEntries = state.ExtremityConcealEntries or {}
	local concealedParts = {}
	for _, entry in ipairs(state.ExtremityConcealEntries) do
		local part = entry.Part
		if part and part.Parent then
			concealedParts[part] = true
			part.LocalTransparencyModifier = 1
		end
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		local normalizedName = normalizeInstanceName(descendant.Name)
		if
			descendant:IsA("BasePart")
			and PHOENIX_CHARACTER_CONCEALED_PART_NAMES[normalizedName]
			and not concealedParts[descendant]
		then
			state.ExtremityConcealEntries[#state.ExtremityConcealEntries + 1] = {
				Part = descendant,
				OriginalLocalTransparencyModifier = descendant.LocalTransparencyModifier,
			}
			descendant.LocalTransparencyModifier = 1
		end
	end
end

local function restorePhoenixExtremityConceal(entries)
	for _, entry in ipairs(entries or {}) do
		local part = entry.Part
		if part and part.Parent then
			part.LocalTransparencyModifier = entry.OriginalLocalTransparencyModifier
		end
	end
end

local function resolveDisplayRigPivotCFrame(pivotToRoot, rootCFrame)
	return rootCFrame * pivotToRoot:Inverse()
end

local function getOrCreateAnimationControllerAnimator(model)
	if not model then
		return nil
	end

	local animationController = model:FindFirstChildOfClass("AnimationController")
		or model:FindFirstChildWhichIsA("AnimationController", true)
	if not animationController then
		animationController = Instance.new("AnimationController")
		animationController.Name = "AnimationController"
		animationController.Parent = model
	end

	local animator = animationController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animationController
	end

	return animator
end

local function getOrCreateHumanoidAnimator(humanoid)
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return animator
end

local function stopAnimationEntry(entry, fadeTime)
	if not entry then
		return
	end

	local track = entry.Track
	if track then
		pcall(function()
			if track.IsPlaying then
				track:Stop(fadeTime or entry.StopFadeTime or PHOENIX_ANIMATION_STOP_FADE_TIME)
			end
		end)

		task.delay((fadeTime or entry.StopFadeTime or PHOENIX_ANIMATION_STOP_FADE_TIME) + 0.05, function()
			pcall(function()
				track:Destroy()
			end)
		end)
	end

	local animation = entry.Animation
	if animation and animation.Parent then
		animation:Destroy()
	end
end

local function stopAnimationEntriesByGroup(state, trackGroup, fadeTime)
	if not state or typeof(trackGroup) ~= "string" or trackGroup == "" then
		return
	end

	local remainingEntries = {}
	for _, entry in ipairs(state.AnimationTracks or {}) do
		if entry.TrackGroup == trackGroup then
			stopAnimationEntry(entry, fadeTime)
		else
			remainingEntries[#remainingEntries + 1] = entry
		end
	end

	state.AnimationTracks = remainingEntries
end

local function cleanupPhoenixWingState(state, fadeTime)
	if not state or state.CleanedUp then
		return
	end

	state.CleanedUp = true
	for _, entry in ipairs(state.AnimationTracks or {}) do
		stopAnimationEntry(entry, fadeTime)
	end
	state.AnimationTracks = {}

	for _, instance in ipairs(state.RuntimeVfxInstances or {}) do
		if instance and instance.Parent then
			instance:Destroy()
		end
	end
	state.RuntimeVfxInstances = {}

	if state.Container and state.Container.Parent then
		state.Container:Destroy()
	end

	restorePhoenixExtremityConceal(state.ExtremityConcealEntries)
end

local function rememberPhoenixRuntimeVfx(state, instance)
	if not state or not instance then
		return instance
	end

	state.RuntimeVfxInstances = state.RuntimeVfxInstances or {}
	state.RuntimeVfxInstances[#state.RuntimeVfxInstances + 1] = instance
	return instance
end

local function eachSelfAndDescendants(root, callback)
	if not root then
		return
	end

	callback(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		callback(descendant)
	end
end

local function getPivotCFrame(instance)
	if not instance then
		return nil
	end
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	local part = findFirstBasePart(instance)
	return part and part.CFrame or nil
end

local function scaleNumberSequence(sequence, scale)
	if typeof(sequence) ~= "NumberSequence" or typeof(scale) ~= "number" then
		return sequence
	end

	local scaledKeypoints = {}
	for index, keypoint in ipairs(sequence.Keypoints) do
		scaledKeypoints[index] = NumberSequenceKeypoint.new(
			keypoint.Time,
			keypoint.Value * scale,
			keypoint.Envelope * scale
		)
	end

	return NumberSequence.new(scaledKeypoints)
end

local function scaleNumberRange(range, scale)
	if typeof(range) ~= "NumberRange" or typeof(scale) ~= "number" then
		return range
	end

	return NumberRange.new(range.Min * scale, range.Max * scale)
end

local function scaleBasePartAroundPosition(part, originPosition, scale)
	local rotation = part.CFrame - part.Position
	local scaledPosition = originPosition + ((part.Position - originPosition) * scale)
	part.Size *= scale
	part.CFrame = CFrame.new(scaledPosition) * rotation
end

local function scalePhoenixAuthoredVfxClone(root, scale)
	local numericScale = tonumber(scale)
	if not numericScale or numericScale <= 0 or math.abs(numericScale - 1) <= 0.001 then
		return
	end

	local pivot = getPivotCFrame(root)
	local originPosition = pivot and pivot.Position or nil
	if not originPosition then
		return
	end

	eachSelfAndDescendants(root, function(instance)
		if instance:IsA("BasePart") then
			scaleBasePartAroundPosition(instance, originPosition, numericScale)
		elseif instance:IsA("Attachment") then
			instance.Position *= numericScale
		elseif instance:IsA("ParticleEmitter") then
			instance.Size = scaleNumberSequence(instance.Size, numericScale)
			instance.Speed = scaleNumberRange(instance.Speed, numericScale)
			instance.Acceleration *= numericScale
			instance.Drag *= numericScale
		elseif instance:IsA("Beam") then
			instance.Width0 *= numericScale
			instance.Width1 *= numericScale
			instance.CurveSize0 *= numericScale
			instance.CurveSize1 *= numericScale
		elseif instance:IsA("Trail") then
			instance.WidthScale = scaleNumberSequence(instance.WidthScale, numericScale)
		elseif instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
			instance.Range *= numericScale
		elseif instance:IsA("Smoke") then
			instance.Size *= numericScale
			instance.RiseVelocity *= numericScale
		elseif instance:IsA("Fire") then
			instance.Size *= numericScale
			instance.Heat *= numericScale
		elseif instance:IsA("SpecialMesh") then
			instance.Scale *= numericScale
		end
	end)
end

local function resolvePhoenixAssetRootForTemplate(template, root)
	if root and findReferencePart(root, PHOENIX_REFERENCE_PART_NAMES) then
		return root
	end

	local current = template and template.Parent or nil
	while current and current ~= ReplicatedStorage and current ~= Workspace do
		if findReferencePart(current, PHOENIX_REFERENCE_PART_NAMES) then
			return current
		end
		current = current.Parent
	end

	return root
end

local function getStandardToriVfxRoot()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assetsFolder and assetsFolder:FindFirstChild("VFX")
	return vfxFolder and vfxFolder:FindFirstChild(PHOENIX_WING_ASSET_FRUIT_KEY) or nil
end

local function findPhoenixMoveFolderVfxTemplate(assetName)
	local toriVfxRoot = getStandardToriVfxRoot()
	if not toriVfxRoot then
		return nil, nil
	end

	for _, moveFolderName in ipairs(PHOENIX_AUTHORED_VFX_MOVE_FOLDERS[assetName] or {}) do
		local moveRoot = toriVfxRoot:FindFirstChild(moveFolderName)
		if not moveRoot then
			continue
		end

		local direct = moveRoot:FindFirstChild(assetName)
		if direct then
			return direct, moveRoot
		end

		local descendant = moveRoot:FindFirstChild(assetName, true)
		if descendant then
			return descendant, moveRoot
		end
	end

	return nil, nil
end

local function findPhoenixReferenceVfxTemplate(assetName)
	for _, root in ipairs(getPhoenixAssetRootCandidates()) do
		local direct = root:FindFirstChild(assetName)
		if direct then
			return direct, resolvePhoenixAssetRootForTemplate(direct, root)
		end

		for _, phoenixAssetName in ipairs(PHOENIX_WING_ASSET_NAMES) do
			local phoenixModel = root:FindFirstChild(phoenixAssetName)
			local child = phoenixModel and phoenixModel:FindFirstChild(assetName)
			if child then
				return child, resolvePhoenixAssetRootForTemplate(child, phoenixModel)
			end
		end

		local descendant = root:FindFirstChild(assetName, true)
		if descendant then
			return descendant, resolvePhoenixAssetRootForTemplate(descendant, root)
		end
	end

	return nil, nil
end

local function findPhoenixAuthoredVfxTemplate(assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		return nil, nil
	end

	if PHOENIX_AUTHORED_VFX_REFERENCE_FIRST[assetName] then
		local referenceTemplate, referenceRoot = findPhoenixReferenceVfxTemplate(assetName)
		if referenceTemplate then
			return referenceTemplate, referenceRoot
		end
	end

	local moveTemplate, moveRoot = findPhoenixMoveFolderVfxTemplate(assetName)
	if moveTemplate then
		return moveTemplate, moveRoot
	end

	return findPhoenixReferenceVfxTemplate(assetName)
end

local function configurePhoenixAuthoredVfxClone(root, options)
	options = options or {}
	local anchored = options.Anchored ~= false
	eachSelfAndDescendants(root, function(instance)
		if instance:IsA("BasePart") then
			instance.Anchored = anchored
			instance.CanCollide = false
			instance.CanTouch = false
			instance.CanQuery = false
			instance.Massless = true
			instance.CastShadow = false
		elseif instance:IsA("Script") or instance:IsA("LocalScript") or instance:IsA("ModuleScript") then
			instance:Destroy()
		end
	end)
end

local function createPhoenixAuthoredVfxClone(template, options)
	local clone = template:Clone()
	if clone:IsA("Model") or clone:IsA("BasePart") then
		configurePhoenixAuthoredVfxClone(clone, options)
		return clone
	end

	local wrapper = Instance.new("Model")
	wrapper.Name = clone.Name

	if clone:IsA("Attachment") or clone:IsA("ParticleEmitter") or clone:IsA("Trail") or clone:IsA("Beam") then
		local anchor = Instance.new("Part")
		anchor.Name = clone.Name .. "Anchor"
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.25, 0.25, 0.25)
		anchor.Parent = wrapper
		clone.Parent = anchor
	else
		clone.Parent = wrapper
		if not findFirstBasePart(wrapper) then
			local anchor = Instance.new("Part")
			anchor.Name = clone.Name .. "Anchor"
			anchor.Transparency = 1
			anchor.Size = Vector3.new(0.25, 0.25, 0.25)
			anchor.Parent = wrapper
		end
	end

	configurePhoenixAuthoredVfxClone(wrapper, options)
	return wrapper
end

local function setPhoenixAuthoredVfxEnabled(root, enabled)
	eachSelfAndDescendants(root, function(instance)
		if
			instance:IsA("ParticleEmitter")
			or instance:IsA("Trail")
			or instance:IsA("Beam")
			or instance:IsA("Fire")
			or instance:IsA("Smoke")
			or instance:IsA("Sparkles")
			or instance:IsA("PointLight")
			or instance:IsA("SpotLight")
			or instance:IsA("SurfaceLight")
		then
			instance.Enabled = enabled
		end
	end)
end

local function emitPhoenixAuthoredVfx(root, defaultEmitCount)
	eachSelfAndDescendants(root, function(instance)
		if not instance:IsA("ParticleEmitter") then
			return
		end

		local emitCount = tonumber(instance:GetAttribute("EmitCount"))
			or tonumber(instance:GetAttribute("BurstCount"))
			or defaultEmitCount
			or math.max(1, math.floor((tonumber(instance.Rate) or 0) * 0.35))
		emitCount = math.max(1, math.floor(tonumber(emitCount) or tonumber(defaultEmitCount) or 12))
		pcall(function()
			instance:Emit(emitCount)
		end)
	end)
end

local function setPhoenixAuthoredParticlesLockedToPart(root, lockedToPart)
	eachSelfAndDescendants(root, function(instance)
		if instance:IsA("ParticleEmitter") then
			instance.LockedToPart = lockedToPart == true
		end
	end)
end

local function pivotPhoenixAuthoredVfx(root, cframe)
	if not root or typeof(cframe) ~= "CFrame" then
		return
	end

	if root:IsA("Model") then
		root:PivotTo(cframe)
	elseif root:IsA("BasePart") then
		root.CFrame = cframe
	else
		local part = findFirstBasePart(root)
		if part then
			part.CFrame = cframe
		end
	end
end

local function mountPhoenixAuthoredVfxClone(root, targetPart, targetCFrame)
	if not root or not targetPart or not targetPart:IsA("BasePart") then
		return false
	end

	pivotPhoenixAuthoredVfx(root, targetCFrame)

	local mountedPartCount = 0
	eachSelfAndDescendants(root, function(instance)
		if not instance:IsA("BasePart") then
			return
		end

		instance.Anchored = false
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.Massless = true

		local weld = Instance.new("WeldConstraint")
		weld.Name = "PhoenixVfxMount"
		weld.Part0 = instance
		weld.Part1 = targetPart
		weld.Parent = instance
		mountedPartCount = mountedPartCount + 1
	end)

	return mountedPartCount > 0
end

local function getPhoenixAuthoredVfxOffset(assetName, template, assetRoot)
	local templatePivot = getPivotCFrame(template)
	local referencePart = assetRoot and findReferencePart(assetRoot, PHOENIX_REFERENCE_PART_NAMES)
	if templatePivot and referencePart then
		return referencePart.CFrame:ToObjectSpace(templatePivot)
	end

	return PHOENIX_AUTHORED_VFX_DEFAULT_OFFSETS[assetName] or CFrame.identity
end

function ClientEffectVisuals.new(config)
	config = config or {}

	return setmetatable({
		GetLocalRootPart = type(config.GetLocalRootPart) == "function" and config.GetLocalRootPart or function()
			return nil
		end,
		GetPlayerRootPart = type(config.GetPlayerRootPart) == "function" and config.GetPlayerRootPart or resolvePlayerRootPart,
		MinDirectionMagnitude = math.max(DEFAULT_MIN_DIRECTION_MAGNITUDE, tonumber(config.MinDirectionMagnitude) or DEFAULT_MIN_DIRECTION_MAGNITUDE),
		MeraFruitName = tostring(config.MeraFruitName or DEFAULT_MERA_FRUIT_NAME),
		FireBurstAbility = tostring(config.FireBurstAbility or DEFAULT_FIRE_BURST_ABILITY),
		BomuFruitName = tostring(config.BomuFruitName or DEFAULT_BOMU_FRUIT_NAME),
		BomuDetonationAbility = tostring(config.BomuDetonationAbility or DEFAULT_BOMU_DETONATION_ABILITY),
		PhoenixFruitName = tostring(config.PhoenixFruitName or DEFAULT_PHOENIX_FRUIT_NAME),
		PhoenixFlightAbility = tostring(config.PhoenixFlightAbility or DEFAULT_PHOENIX_FLIGHT_ABILITY),
		PhoenixShieldAbility = tostring(config.PhoenixShieldAbility or DEFAULT_PHOENIX_SHIELD_ABILITY),
		PhoenixRebirthAbility = tostring(config.PhoenixRebirthAbility or DEFAULT_PHOENIX_REBIRTH_ABILITY),
		PhoenixEffectColor = resolveColor(config.PhoenixEffectColor, DEFAULT_PHOENIX_EFFECT_COLOR),
		PhoenixEffectAccentColor = resolveColor(config.PhoenixEffectAccentColor, DEFAULT_PHOENIX_EFFECT_ACCENT_COLOR),
		GomuFruitName = tostring(config.GomuFruitName or DEFAULT_GOMU_FRUIT_NAME),
		RubberLaunchAbility = tostring(config.RubberLaunchAbility or DEFAULT_RUBBER_LAUNCH_ABILITY),
		PhoenixWingEffects = setmetatable({}, { __mode = "k" }),
		PhoenixAnimationDefinitions = {},
	}, ClientEffectVisuals)
end

function ClientEffectVisuals:GetPhoenixAnimationDefinition(animationKey)
	self.PhoenixAnimationDefinitions = self.PhoenixAnimationDefinitions or {}
	local cachedDefinition = self.PhoenixAnimationDefinitions[animationKey]
	if cachedDefinition ~= nil then
		return cachedDefinition or nil
	end

	local animation, descriptor = AnimationResolver.GetAnimation(animationKey, {
		Context = "ToriVfx",
	})
	if not animation then
		self.PhoenixAnimationDefinitions[animationKey] = false
		return nil
	end

	local definition = {
		Animation = animation,
		AnimationId = descriptor and descriptor.AnimationId or animation.AnimationId,
		Length = (descriptor and descriptor.Length) or PHOENIX_ANIMATION_LENGTHS[animationKey],
	}
	self.PhoenixAnimationDefinitions[animationKey] = definition
	return definition
end

function ClientEffectVisuals:PlayPhoenixAnimationOnAnimator(state, animator, animationKey, options)
	if not state or not animator then
		return nil
	end

	local definition = self:GetPhoenixAnimationDefinition(animationKey)
	if not definition then
		return nil
	end

	options = options or {}
	local ok, track = pcall(function()
		return animator:LoadAnimation(definition.Animation)
	end)
	if not ok or not track then
		return nil
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = options.Looped == true

	local entry = {
		Track = track,
		AnimationKey = animationKey,
		TrackGroup = options.TrackGroup,
		StopFadeTime = math.max(0, tonumber(options.StopFadeTime) or PHOENIX_ANIMATION_STOP_FADE_TIME),
	}
	state.AnimationTracks = state.AnimationTracks or {}
	state.AnimationTracks[#state.AnimationTracks + 1] = entry

	track:Play(
		math.max(0, tonumber(options.FadeTime) or PHOENIX_ANIMATION_FADE_TIME),
		tonumber(options.Weight) or 1,
		math.max(0.01, tonumber(options.PlaybackSpeed) or 1)
	)

	local timePosition = math.max(0, tonumber(options.TimePosition) or 0)
	if timePosition > 0 then
		pcall(function()
			local maxTimePosition = math.max(0, (definition.Length or track.Length or timePosition) - 0.05)
			track.TimePosition = math.min(timePosition, maxTimePosition)
		end)
	end

	return entry, definition.Length
end

function ClientEffectVisuals:PlayPhoenixAnimation(state, targetPlayer, animationKey, options)
	if not state or typeof(animationKey) ~= "string" or animationKey == "" then
		return nil
	end

	local longestLength = nil
	for _, featureState in ipairs(state.Features or {}) do
		local animator = getOrCreateAnimationControllerAnimator(featureState.Model)
		local _, length = self:PlayPhoenixAnimationOnAnimator(state, animator, animationKey, options)
		if length then
			longestLength = math.max(longestLength or 0, length)
		end
	end

	if not options or options.PlayCharacter ~= false then
		local humanoid = resolvePlayerHumanoid(targetPlayer)
		local animator = getOrCreateHumanoidAnimator(humanoid)
		local _, length = self:PlayPhoenixAnimationOnAnimator(state, animator, animationKey, options)
		if length then
			longestLength = math.max(longestLength or 0, length)
		end
	end

	return longestLength
end

local function getPlanarSpeed(part)
	if not part or not part:IsA("BasePart") then
		return 0
	end

	local velocity = part.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function resolvePhoenixFlightSustainAnimationKey(rootPart, currentAnimationKey)
	local planarSpeed = getPlanarSpeed(rootPart)
	if currentAnimationKey == PHOENIX_ANIMATION_KEYS.FlightIdle then
		if planarSpeed >= PHOENIX_FLIGHT_MOVE_SPEED_THRESHOLD then
			return PHOENIX_ANIMATION_KEYS.FlightLoop
		end

		return PHOENIX_ANIMATION_KEYS.FlightIdle
	end

	if planarSpeed <= PHOENIX_FLIGHT_IDLE_SPEED_THRESHOLD then
		return PHOENIX_ANIMATION_KEYS.FlightIdle
	end

	return PHOENIX_ANIMATION_KEYS.FlightLoop
end

local function isPhoenixFlightMovementActive(rootPart, wasActive)
	local planarSpeed = getPlanarSpeed(rootPart)
	if wasActive then
		return planarSpeed > PHOENIX_FLIGHT_IDLE_SPEED_THRESHOLD
	end

	return planarSpeed >= PHOENIX_FLIGHT_MOVE_SPEED_THRESHOLD
end

function ClientEffectVisuals:SetPhoenixFlightSustainAnimation(state, targetPlayer, animationKey)
	if not state or state.CleanedUp or state.PhoenixFlightSustainAnimationKey == animationKey then
		return
	end

	stopAnimationEntriesByGroup(state, PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP, 0.12)
	local length = self:PlayPhoenixAnimation(state, targetPlayer, animationKey, {
		Looped = true,
		FadeTime = 0.12,
		StopFadeTime = 0.12,
		TrackGroup = PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP,
	})
	state.PhoenixFlightSustainAnimationKey = if length then animationKey else nil
end

function ClientEffectVisuals:GetPhoenixWingModelTemplate()
	if self.PhoenixWingModelTemplate then
		return self.PhoenixWingModelTemplate
	end

	local assetRoot = getPhoenixWingAssetRoot()
	if not assetRoot then
		return nil
	end

	local featureModels = {}
	for _, spec in ipairs(PHOENIX_FEATURE_MODEL_SPECS) do
		local featureModel = findNamedModel(assetRoot, spec.ModelName)
		local referencePart = findReferencePart(assetRoot, spec.SourcePartNames)
		if featureModel and referencePart and findFirstBasePart(featureModel) then
			featureModels[#featureModels + 1] = {
				Model = featureModel,
				ReferenceCFrame = referencePart.CFrame,
				TargetPartNames = spec.TargetPartNames,
			}
		end
	end

	if #featureModels == 0 then
		return nil
	end

	self.PhoenixWingModelTemplate = {
		AssetRoot = assetRoot,
		Models = featureModels,
	}
	return self.PhoenixWingModelTemplate
end

function ClientEffectVisuals:PlayPhoenixAuthoredVfx(state, targetPlayer, assetName, duration, options)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	if not rootPart then
		return nil
	end

	duration = math.max(0.05, tonumber(duration) or PHOENIX_WING_FALLBACK_DURATION)
	local endTime = os.clock() + duration
	options = options or {}
	local targetPartNames = resolvePartNameList(options.TargetPartNames, nil)
	local orientToMovement = options.OrientToMovement == true
	local enableWhileMoving = options.EnableWhileMoving == true
	local mountToTarget = options.MountToTarget == true
	local lockParticlesToPart = options.LockParticlesToPart == true or mountToTarget
	local burstOnly = options.BurstOnly == true
	local burstActiveTime = math.max(0.03, tonumber(options.BurstActiveTime) or 0.1)
	local visualScale = math.max(0.001, tonumber(options.Scale) or 1)
	local mountedTargetPart = nil
	if mountToTarget then
		mountedTargetPart = resolvePlayerPartByNames(targetPlayer, targetPartNames or PHOENIX_REFERENCE_PART_NAMES) or rootPart
		if not mountedTargetPart then
			return nil
		end
	end

	if state and not burstOnly then
		state.AuthoredVfx = state.AuthoredVfx or {}
		local existingEntry = state.AuthoredVfx[assetName]
		if existingEntry and existingEntry.Clone and existingEntry.Clone.Parent then
			if math.abs((tonumber(existingEntry.Scale) or 1) - visualScale) > 0.001 then
				existingEntry.Clone:Destroy()
				state.AuthoredVfx[assetName] = nil
			else
				existingEntry.EndTime = math.max(existingEntry.EndTime or 0, endTime)
				if lockParticlesToPart then
					setPhoenixAuthoredParticlesLockedToPart(existingEntry.Clone, true)
				end
				if enableWhileMoving then
					local shouldEnable = isPhoenixFlightMovementActive(rootPart, existingEntry.VfxActive)
					existingEntry.VfxActive = shouldEnable
					setPhoenixAuthoredVfxEnabled(existingEntry.Clone, shouldEnable)
					if shouldEnable then
						emitPhoenixAuthoredVfx(existingEntry.Clone, options.EmitCount or 12)
					end
				else
					existingEntry.VfxActive = true
					setPhoenixAuthoredVfxEnabled(existingEntry.Clone, true)
				end
				return existingEntry.Clone
			end
		end
	end

	local template, assetRoot = findPhoenixAuthoredVfxTemplate(assetName)
	if not template then
		return nil
	end

	local clone = createPhoenixAuthoredVfxClone(template, {
		Anchored = not mountToTarget,
	})
	scalePhoenixAuthoredVfxClone(clone, visualScale)
	clone.Name = "Phoenix" .. assetName
	if enableWhileMoving then
		setPhoenixAuthoredVfxEnabled(clone, false)
	end
	if lockParticlesToPart then
		setPhoenixAuthoredParticlesLockedToPart(clone, true)
	end

	local offset = resolveCFrameValue(options.Offset, getPhoenixAuthoredVfxOffset(assetName, template, assetRoot))
	if mountToTarget then
		clone.Parent = mountedTargetPart
		if not mountPhoenixAuthoredVfxClone(clone, mountedTargetPart, mountedTargetPart.CFrame * offset) then
			clone:Destroy()
			return nil
		end
	else
		clone.Parent = getOrCreateWingEffectsFolder()
	end

	local entry = {
		Clone = clone,
		EndTime = endTime,
		Scale = visualScale,
		VfxActive = false,
		BurstOnly = burstOnly,
		BurstStarted = false,
	}
	if state and not burstOnly then
		state.AuthoredVfx[assetName] = entry
	end
	if state then
		rememberPhoenixRuntimeVfx(state, clone)
	end

	local function updatePosition()
		local target = targetPartNames and resolvePhoenixFollowTarget(targetPlayer, state, targetPartNames) or nil
		local currentRootPart = self.GetPlayerRootPart(targetPlayer)
		local followCFrame
		if orientToMovement then
			followCFrame, entry.LastDirection = getMovementOrientedFollowCFrame(target, currentRootPart, entry.LastDirection)
		else
			followCFrame = getFollowTargetCFrame(target) or getFollowTargetCFrame(currentRootPart)
		end
		if not followCFrame then
			return false
		end

		pivotPhoenixAuthoredVfx(clone, followCFrame * offset)
		return true
	end

	local function setVfxActive(isActive)
		if isActive and entry.BurstOnly and entry.BurstStarted then
			return
		end
		if entry.VfxActive == isActive then
			return
		end

		entry.VfxActive = isActive
		setPhoenixAuthoredVfxEnabled(clone, isActive)
		if isActive then
			entry.BurstStarted = true
			emitPhoenixAuthoredVfx(clone, options.EmitCount or 12)
			if entry.BurstOnly then
				local burstToken = {}
				entry.BurstToken = burstToken
				task.delay(burstActiveTime, function()
					if entry.BurstToken ~= burstToken or not clone.Parent then
						return
					end

					setVfxActive(false)
				end)
			end
		end
	end

	local function updateMovementGate()
		if not enableWhileMoving then
			setVfxActive(true)
			return
		end

		local currentRootPart = self.GetPlayerRootPart(targetPlayer)
		setVfxActive(isPhoenixFlightMovementActive(currentRootPart, entry.VfxActive))
	end

	if not mountToTarget then
		updatePosition()
	end
	updateMovementGate()

	task.spawn(function()
		while clone.Parent and os.clock() < (entry.EndTime or endTime) do
			if state and state.CleanedUp then
				break
			end
			if mountToTarget and not mountedTargetPart.Parent then
				break
			end
			if not mountToTarget and options.Follow ~= false and not updatePosition() then
				break
			end
			updateMovementGate()

			RunService.Heartbeat:Wait()
		end

		if state and state.AuthoredVfx and state.AuthoredVfx[assetName] == entry then
			state.AuthoredVfx[assetName] = nil
		end

		if clone.Parent then
			setPhoenixAuthoredVfxEnabled(clone, false)
			local fadeOutDuration = math.max(0, tonumber(options.FadeOutDuration) or PHOENIX_AUTHORED_VFX_FADE_OUT)
			if fadeOutDuration <= 0 then
				clone:Destroy()
			else
				task.delay(fadeOutDuration, function()
					if clone.Parent then
						clone:Destroy()
					end
				end)
			end
		end
	end)

	return clone
end

function ClientEffectVisuals:PlayPhoenixFlightAnimation(state, targetPlayer, duration, options)
	options = options or {}
	if state then
		state.PhoenixFlightSustainAnimationKey = nil
		stopAnimationEntriesByGroup(state, PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP, 0.08)
	end

	local startupLength = self:PlayPhoenixAnimation(state, targetPlayer, PHOENIX_ANIMATION_KEYS.FlightStart, {
		Looped = false,
		FadeTime = 0.04,
		StopFadeTime = 0.08,
	}) or PHOENIX_FLIGHT_LOOP_FALLBACK_DELAY
	local requestedLoopDelay = tonumber(options.LoopDelay)
	local defaultLoopDelay = math.max(PHOENIX_FLIGHT_LOOP_FALLBACK_DELAY, startupLength)
	local loopDelay = if requestedLoopDelay and requestedLoopDelay >= 0 then requestedLoopDelay else defaultLoopDelay
	loopDelay = math.min(loopDelay, math.max(PHOENIX_WING_MIN_DURATION, duration))
	if state then
		state.FlightTrailDelay = loopDelay
	end

	task.delay(loopDelay, function()
		if not self.PhoenixWingEffects or self.PhoenixWingEffects[targetPlayer] ~= state or state.CleanedUp then
			return
		end
		if not state.Container or not state.Container.Parent then
			return
		end

		while self.PhoenixWingEffects
			and self.PhoenixWingEffects[targetPlayer] == state
			and not state.CleanedUp
			and not state.FlightEndPlayed
			and state.Container
			and state.Container.Parent
		do
			local rootPart = self.GetPlayerRootPart(targetPlayer)
			local animationKey = resolvePhoenixFlightSustainAnimationKey(rootPart, state.PhoenixFlightSustainAnimationKey)
			self:SetPhoenixFlightSustainAnimation(state, targetPlayer, animationKey)
			task.wait(0.1)
		end
	end)

	return loopDelay
end

function ClientEffectVisuals:CreatePhoenixWingEffect(targetPlayer, duration, options)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	options = options or {}
	duration = math.max(PHOENIX_WING_MIN_DURATION, tonumber(duration) or PHOENIX_WING_FALLBACK_DURATION)
	local endTime = os.clock() + duration
	self.PhoenixWingEffects = self.PhoenixWingEffects or setmetatable({}, { __mode = "k" })
	local state = self.PhoenixWingEffects and self.PhoenixWingEffects[targetPlayer]

	if not state then
		local targetBodyPart = resolvePlayerBodyPart(targetPlayer)
		if not targetBodyPart then
			return
		end

		local wingTemplate = self:GetPhoenixWingModelTemplate()
		if not wingTemplate then
			return
		end

		local container = Instance.new("Model")
		container.Name = "PhoenixDisplay"
		container.Parent = getOrCreateWingEffectsFolder()

		local featureStates = {}
		for _, featureTemplate in ipairs(wingTemplate.Models) do
			local targetPart = resolvePlayerPartByNames(targetPlayer, featureTemplate.TargetPartNames) or targetBodyPart
			local feature = featureTemplate.Model:Clone()
			configurePhoenixDisplayClone(feature)
			feature.Parent = container
			local pivotToReference = feature:GetPivot():ToObjectSpace(featureTemplate.ReferenceCFrame)
			feature:PivotTo(resolveDisplayRigPivotCFrame(pivotToReference, targetPart.CFrame))

			featureStates[#featureStates + 1] = {
				Model = feature,
				PivotToReference = pivotToReference,
				TargetPartNames = featureTemplate.TargetPartNames,
			}
		end

		if #featureStates == 0 then
			container:Destroy()
			return
		end

		state = {
			Container = container,
			EndTime = endTime,
			ExtremityConcealEntries = applyPhoenixExtremityConceal(targetPlayer),
			Features = featureStates,
			AnimationTracks = {},
			PlayFlightEndOnExpire = options.Mode == "Flight",
			FlightEndPlayed = false,
		}

		self.PhoenixWingEffects[targetPlayer] = state

		task.spawn(function()
			while container.Parent and not state.CleanedUp do
				if os.clock() >= state.EndTime then
					if state.PlayFlightEndOnExpire and not state.FlightEndPlayed then
						self:StopPhoenixFlightEffect(targetPlayer)
						if os.clock() >= (state.EndTime or 0) then
							break
						end
					else
						break
					end
				else
					refreshPhoenixExtremityConceal(targetPlayer, state)

					local hasCurrentTarget = false
					for _, featureState in ipairs(state.Features) do
						local currentTargetPart = resolvePlayerPartByNames(targetPlayer, featureState.TargetPartNames)
							or resolvePlayerBodyPart(targetPlayer)
						if currentTargetPart and featureState.Model.Parent then
							featureState.Model:PivotTo(
								resolveDisplayRigPivotCFrame(featureState.PivotToReference, currentTargetPart.CFrame)
							)
							hasCurrentTarget = true
						end
					end

					if not hasCurrentTarget then
						break
					end
				end

				RunService.Heartbeat:Wait()
			end

			cleanupPhoenixWingState(state)
			if self.PhoenixWingEffects and self.PhoenixWingEffects[targetPlayer] == state then
				self.PhoenixWingEffects[targetPlayer] = nil
			end
		end)
	end

	state.EndTime = math.max(state.EndTime, endTime)

	if options.Mode ~= nil and options.Mode ~= "Flight" then
		state.PlayFlightEndOnExpire = false
		state.FlightEndPlayed = true
		state.PhoenixFlightSustainAnimationKey = nil
		stopAnimationEntriesByGroup(state, PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP, 0.08)
	end

	if options.Mode == "Flight" then
		state.PlayFlightEndOnExpire = true
		state.FlightEndPlayed = false
		state.FlightTrailDelay = self:PlayPhoenixFlightAnimation(state, targetPlayer, duration, {
			LoopDelay = options.FlightTrailDelay,
		}) or 0
	elseif typeof(options.AnimationKey) == "string" then
		local shouldPlayAnimation = true
		if options.PlayAnimationOnce == true then
			state.PlayedAnimationKeys = state.PlayedAnimationKeys or {}
			shouldPlayAnimation = state.PlayedAnimationKeys[options.AnimationKey] ~= true
			state.PlayedAnimationKeys[options.AnimationKey] = true
		end

		if shouldPlayAnimation then
			self:PlayPhoenixAnimation(state, targetPlayer, options.AnimationKey, {
				Looped = options.Looped == true,
				FadeTime = options.FadeTime,
				StopFadeTime = options.StopFadeTime,
				PlaybackSpeed = options.PlaybackSpeed,
				PlayCharacter = options.PlayCharacter,
				TimePosition = options.TimePosition,
			})
		end
	end

	return state
end

function ClientEffectVisuals:StopPhoenixFlightEffect(targetPlayer)
	if not self.PhoenixWingEffects then
		return
	end

	local state = self.PhoenixWingEffects[targetPlayer]
	if not state or state.CleanedUp then
		return
	end
	if state.FlightEndPlayed then
		return
	end

	state.FlightEndPlayed = true
	state.PlayFlightEndOnExpire = false

	for _, entry in ipairs(state.AnimationTracks or {}) do
		stopAnimationEntry(entry, 0.08)
	end
	state.AnimationTracks = {}
	state.PhoenixFlightSustainAnimationKey = nil

	local endLength = self:PlayPhoenixAnimation(state, targetPlayer, PHOENIX_ANIMATION_KEYS.FlightEnd, {
		Looped = false,
		FadeTime = 0.04,
		StopFadeTime = 0.08,
	}) or 0.25
	state.EndTime = os.clock() + math.max(0.15, math.min(endLength, 1.2))
end

function ClientEffectVisuals:StopPhoenixWingEffect(targetPlayer, fadeTime)
	if not self.PhoenixWingEffects then
		return
	end

	local state = self.PhoenixWingEffects[targetPlayer]
	if not state then
		return
	end

	cleanupPhoenixWingState(state, fadeTime)
	self.PhoenixWingEffects[targetPlayer] = nil
end

function ClientEffectVisuals:CreateMeraFlameDashEffectVisual(startPosition, endPosition, direction, isPredicted)
	if typeof(startPosition) ~= "Vector3" then
		return
	end

	local resolvedDirection = typeof(direction) == "Vector3" and direction or DEFAULT_DIRECTION
	if resolvedDirection.Magnitude <= self.MinDirectionMagnitude then
		resolvedDirection = DEFAULT_DIRECTION
	else
		resolvedDirection = resolvedDirection.Unit
	end

	local origin = startPosition + Vector3.new(0, 1.1, 0)
	local destination = typeof(endPosition) == "Vector3" and (endPosition + Vector3.new(0, 1.1, 0))
		or (origin + (resolvedDirection * 14))
	local segment = destination - origin
	local segmentLength = segment.Magnitude
	local primaryColor = isPredicted and Color3.fromRGB(255, 185, 92) or Color3.fromRGB(255, 137, 56)
	local accentColor = Color3.fromRGB(255, 232, 180)

	createPulse("MeraDashPulseStart", origin, primaryColor, 2.2, 6.2, 0.24)
	createPulse("MeraDashPulseEnd", destination, accentColor, 1.6, 4.4, 0.22)

	if segmentLength > 0.2 then
		local streak = Instance.new("Part")
		streak.Name = "MeraDashStreak"
		streak.Anchored = true
		streak.CanCollide = false
		streak.CanTouch = false
		streak.CanQuery = false
		streak.Material = Enum.Material.Neon
		streak.Color = primaryColor
		streak.Transparency = 0.12
		streak.Size = Vector3.new(1.15, 1.15, segmentLength)
		streak.CFrame = CFrame.lookAt(origin:Lerp(destination, 0.5), destination)
		streak.Parent = Workspace

		local aura = Instance.new("Part")
		aura.Name = "MeraDashAura"
		aura.Anchored = true
		aura.CanCollide = false
		aura.CanTouch = false
		aura.CanQuery = false
		aura.Material = Enum.Material.Neon
		aura.Color = accentColor
		aura.Transparency = 0.72
		aura.Size = Vector3.new(2.2, 2.2, segmentLength * 1.04)
		aura.CFrame = streak.CFrame
		aura.Parent = Workspace

		local streakTween = TweenService:Create(streak, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.2, 0.2, segmentLength * 1.1),
		})
		local auraTween = TweenService:Create(aura, TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(3.6, 3.6, segmentLength * 1.12),
		})

		streakTween:Play()
		auraTween:Play()
		streakTween.Completed:Connect(function()
			if streak.Parent then
				streak:Destroy()
			end
		end)
		auraTween.Completed:Connect(function()
			if aura.Parent then
				aura:Destroy()
			end
		end)
	end

	for sampleIndex = 1, 6 do
		local alpha = sampleIndex / 7
		local samplePosition = origin:Lerp(destination, alpha)
		task.delay((sampleIndex - 1) * 0.02, function()
			createPulse("MeraDashTrail", samplePosition, primaryColor, 0.8, 2.1, 0.18)
		end)
	end
end

function ClientEffectVisuals:CreateFallbackBurstEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.MeraFruitName or abilityName ~= self.FireBurstAbility then
		return
	end

	payload = payload or {}

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	local radius = tonumber(payload.Radius) or 10

	local ring = Instance.new("Part")
	ring.Name = "MeraFireBurstRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 136, 32)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(rootPart.Position) * FLAT_RING_ROTATION
	ring.Parent = Workspace

	local tween = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, radius * 2.6, radius * 2.6),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

function ClientEffectVisuals:GetEffectOriginPosition(targetPlayer, payload)
	if typeof(payload) == "table" and typeof(payload.OriginPosition) == "Vector3" then
		return payload.OriginPosition
	end

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	return rootPart and rootPart.Position or nil
end

function ClientEffectVisuals:CreateBomuDetonationEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.BomuFruitName or abilityName ~= self.BomuDetonationAbility then
		return
	end

	if payload and payload.Action ~= "Detonated" then
		return
	end

	local originPosition = self:GetEffectOriginPosition(targetPlayer, payload)
	if not originPosition then
		return
	end

	local radius = math.max(1, tonumber(payload and payload.Radius) or 8)
	local blastDiameter = radius * 2
	local initialDiameter = math.max(1.5, blastDiameter * 0.2)

	local flash = Instance.new("Part")
	flash.Name = "BomuDetonationFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 225, 153)
	flash.Transparency = 0.12
	flash.Size = Vector3.new(initialDiameter, initialDiameter, initialDiameter)
	flash.CFrame = CFrame.new(originPosition)
	flash.Parent = Workspace

	local ring = Instance.new("Part")
	ring.Name = "BomuDetonationRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 171, 82)
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.25, math.max(0.5, initialDiameter), math.max(0.5, initialDiameter))
	ring.CFrame = CFrame.new(originPosition) * FLAT_RING_ROTATION
	ring.Parent = Workspace

	local flashTween = TweenService:Create(flash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(blastDiameter, blastDiameter, blastDiameter),
	})
	local ringTween = TweenService:Create(ring, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.25, blastDiameter, blastDiameter),
	})

	flashTween:Play()
	ringTween:Play()

	flashTween.Completed:Connect(function()
		if flash.Parent then
			flash:Destroy()
		end
	end)

	ringTween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

local function estimatePhoenixFlightHeightDelay(payload)
	payload = payload or {}
	local initialLift = math.max(0, tonumber(payload.InitialLift) or 10)
	local maxRiseHeight = math.max(initialLift, tonumber(payload.MaxRiseHeight) or initialLift)
	local verticalSpeed = math.max(1, tonumber(payload.VerticalSpeed) or 52)
	local takeoffDuration = math.max(0, tonumber(payload.TakeoffDuration) or 0)
	return math.max(takeoffDuration, maxRiseHeight / verticalSpeed)
end

function ClientEffectVisuals:CreatePhoenixRebirthEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.PhoenixFruitName or abilityName ~= self.PhoenixRebirthAbility then
		return
	end

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	payload = payload or {}
	local animationKey = if typeof(payload.AnimationKey) == "string" and payload.AnimationKey ~= ""
		then payload.AnimationKey
		else PHOENIX_ANIMATION_KEYS.Rebirth
	local duration = math.max(
		PHOENIX_WING_MIN_DURATION,
		tonumber(payload.Duration) or PHOENIX_ANIMATION_LENGTHS[animationKey] or PHOENIX_ANIMATION_LENGTHS[PHOENIX_ANIMATION_KEYS.Rebirth]
	)
	local triggeredAt = tonumber(payload.TriggeredAt)
	local elapsed = triggeredAt and math.max(0, Workspace:GetServerTimeNow() - triggeredAt) or 0
	if elapsed >= duration + 0.25 then
		return
	end

	local remainingDuration = math.max(PHOENIX_WING_MIN_DURATION, duration - elapsed)
	local reviveDelay = math.max(0, tonumber(payload.ReviveDelay) or 0)
	if triggeredAt and tonumber(payload.ReviveAt) then
		reviveDelay = math.max(0, tonumber(payload.ReviveAt) - triggeredAt)
	end

	local state = self:CreatePhoenixWingEffect(targetPlayer, remainingDuration + 0.2, {
		Mode = "Rebirth",
		AnimationKey = animationKey,
		Looped = false,
		FadeTime = 0.04,
		StopFadeTime = 0.16,
		TimePosition = elapsed,
	})

	local function getPulsePosition()
		local currentRootPart = self.GetPlayerRootPart(targetPlayer)
		return currentRootPart and (currentRootPart.Position + Vector3.new(0, 1.35, 0)) or nil
	end

	local function playPulse(name, color, initialSize, finalSize, pulseDuration)
		if state and state.CleanedUp then
			return
		end

		local position = getPulsePosition()
		if position then
			createPulse(name, position, color, initialSize, finalSize, pulseDuration)
		end
	end

	if elapsed <= 0.2 then
		playPulse("PhoenixRebirthIgnite", self.PhoenixEffectColor, 2.4, 7.5, 0.35)
	end

	local remainingReviveDelay = math.max(0, reviveDelay - elapsed)
	if remainingReviveDelay <= remainingDuration + 0.2 then
		task.delay(remainingReviveDelay, function()
			local playedAuthoredReviveVfx = false
			if state and not state.CleanedUp then
				-- ReviveFX is authored as a short burst on the Phoenix rig torso in the Workspace reference.
				playedAuthoredReviveVfx = self:PlayPhoenixAuthoredVfx(
					state,
					targetPlayer,
					PHOENIX_AUTHORED_REVIVE_FX_NAME,
					math.max(0.2, remainingDuration - remainingReviveDelay + PHOENIX_AUTHORED_REVIVE_FX_CLEANUP_BUFFER),
					{
						BurstOnly = true,
						BurstActiveTime = PHOENIX_AUTHORED_REVIVE_FX_ACTIVE_TIME,
						EmitCount = 12,
						TargetPartNames = PHOENIX_REFERENCE_PART_NAMES,
						MountToTarget = true,
						LockParticlesToPart = true,
						FadeOutDuration = 0,
					}
				) ~= nil
			end

			if not playedAuthoredReviveVfx then
				playPulse("PhoenixRebirthRevive", self.PhoenixEffectAccentColor, 4, 12, 0.48)
				task.delay(0.08, function()
					playPulse("PhoenixRebirthAfterglow", self.PhoenixEffectColor, 2.6, 8.5, 0.42)
				end)
			end
		end)
	end
end

function ClientEffectVisuals:CreatePhoenixFlightEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.PhoenixFruitName or abilityName ~= self.PhoenixFlightAbility then
		return
	end

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	payload = payload or {}
	local duration = math.max(PHOENIX_WING_MIN_DURATION, tonumber(payload.Duration) or 4.5)
	local startupDuration = math.max(
		0,
		tonumber(payload.StartupDuration) or PHOENIX_FLIGHT_STARTUP_FALLBACK_DURATION
	)
	local heightDelay = estimatePhoenixFlightHeightDelay(payload)
	local visualDuration = duration + startupDuration + heightDelay
	local trailPartNames = resolvePartNameList(payload.TrailPartNames, PHOENIX_FLIGHT_TRAIL_PART_NAMES)
	local trailOffset = resolveCFrameValue(
		payload.TrailOffset,
		PHOENIX_AUTHORED_VFX_DEFAULT_OFFSETS[PHOENIX_AUTHORED_FLIGHT_FX_NAME]
	)
	local state = self:CreatePhoenixWingEffect(targetPlayer, visualDuration, {
		Mode = "Flight",
		FlightTrailDelay = startupDuration + heightDelay,
	})
	if not state then
		return
	end

	local function playFlightTrail()
		if not self.PhoenixWingEffects or self.PhoenixWingEffects[targetPlayer] ~= state or state.CleanedUp then
			return
		end
		if not state.Container or not state.Container.Parent then
			return
		end

		local remainingDuration = (state.EndTime or os.clock()) - os.clock()
		if remainingDuration <= 0 then
			return
		end

		self:PlayPhoenixAuthoredVfx(state, targetPlayer, PHOENIX_AUTHORED_FLIGHT_FX_NAME, remainingDuration, {
			EmitCount = 16,
			TargetPartNames = trailPartNames,
			Offset = trailOffset,
			OrientToMovement = true,
			EnableWhileMoving = true,
		})
	end

	local trailDelay = math.max(0, tonumber(state.FlightTrailDelay) or 0)
	if trailDelay <= 0 then
		playFlightTrail()
	else
		task.delay(trailDelay, playFlightTrail)
	end
end

function ClientEffectVisuals:CreatePhoenixShieldEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.PhoenixFruitName or abilityName ~= self.PhoenixShieldAbility then
		return
	end

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	payload = payload or {}

	local duration = math.max(0.1, tonumber(payload.Duration) or 5)
	local radius = math.max(1, tonumber(payload.Radius) or DEFAULT_PHOENIX_SHIELD_RADIUS)
	local state = self:CreatePhoenixWingEffect(targetPlayer, duration, {
		AnimationKey = PHOENIX_ANIMATION_KEYS.Shield,
		Looped = false,
		FadeTime = 0.06,
		StopFadeTime = 0.1,
		PlayAnimationOnce = true,
	})
	self:PlayPhoenixAuthoredVfx(state, targetPlayer, PHOENIX_AUTHORED_SHIELD_FX_NAME, duration, {
		EmitCount = 20,
		TargetPartNames = PHOENIX_REFERENCE_PART_NAMES,
		MountToTarget = true,
		LockParticlesToPart = true,
		FadeOutDuration = 0,
		Scale = radius / PHOENIX_SHIELD_AUTHORED_REFERENCE_RADIUS,
	})
end

function ClientEffectVisuals:CreatePhoenixShieldHitEffect(targetPlayer, fruitName, abilityName, payload)
	if fruitName ~= self.PhoenixFruitName or abilityName ~= self.PhoenixShieldAbility then
		return
	end

	payload = payload or {}

	local rootPart = self.GetPlayerRootPart(targetPlayer)
	local hitPosition = typeof(payload.HitPosition) == "Vector3" and payload.HitPosition or nil
	if not hitPosition then
		if not rootPart then
			return
		end

		hitPosition = rootPart.Position + Vector3.new(0, 1.5, 0)
	end

	local radius = math.max(1, tonumber(payload.Radius) or DEFAULT_PHOENIX_SHIELD_RADIUS)
	local rippleDiameter = math.clamp(radius * 0.55, 3.5, 8)

	createPulse("PhoenixShieldHitFlash", hitPosition, PHOENIX_SHIELD_HIT_ACCENT_COLOR, 1.5, rippleDiameter, 0.2)

	local ripple = Instance.new("Part")
	ripple.Name = "PhoenixShieldHitRipple"
	ripple.Shape = Enum.PartType.Cylinder
	ripple.Anchored = true
	ripple.CanCollide = false
	ripple.CanTouch = false
	ripple.CanQuery = false
	ripple.Material = Enum.Material.Neon
	ripple.Color = PHOENIX_SHIELD_HIT_COLOR
	ripple.Transparency = 0.08
	ripple.Size = Vector3.new(0.2, 1.8, 1.8)
	ripple.CFrame = CFrame.new(hitPosition) * FLAT_RING_ROTATION
	ripple.Parent = Workspace

	local rippleTween = TweenService:Create(ripple, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, rippleDiameter, rippleDiameter),
	})

	rippleTween:Play()
	rippleTween.Completed:Connect(function()
		if ripple.Parent then
			ripple:Destroy()
		end
	end)

	if rootPart then
		local shieldFlash = Instance.new("Part")
		shieldFlash.Name = "PhoenixShieldHitShell"
		shieldFlash.Shape = Enum.PartType.Ball
		shieldFlash.Anchored = true
		shieldFlash.CanCollide = false
		shieldFlash.CanTouch = false
		shieldFlash.CanQuery = false
		shieldFlash.Material = Enum.Material.ForceField
		shieldFlash.Color = PHOENIX_SHIELD_HIT_COLOR
		shieldFlash.Transparency = 0.45
		shieldFlash.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		shieldFlash.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 1.5, 0))
		shieldFlash.Parent = Workspace

		local shellTween = TweenService:Create(shieldFlash, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(radius * 2.12, radius * 2.12, radius * 2.12),
		})

		shellTween:Play()
		shellTween.Completed:Connect(function()
			if shieldFlash.Parent then
				shieldFlash:Destroy()
			end
		end)
	end
end

function ClientEffectVisuals:CreateRubberLaunchEffect(_targetPlayer, fruitName, abilityName, _payload)
	if fruitName ~= self.GomuFruitName or abilityName ~= self.RubberLaunchAbility then
		return
	end

	return
end

return ClientEffectVisuals
