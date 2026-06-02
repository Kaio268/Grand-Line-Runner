local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientEffectVisuals = {}
ClientEffectVisuals.__index = ClientEffectVisuals

local SharedFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared")
local DevilFruitConfig = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits")
)
local AnimationResolver = require(SharedFolder:WaitForChild("AnimationResolver"))

local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local DEFAULT_MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_MERA_FRUIT_NAME = assert(DevilFruitConfig.GetDisplayName("Inferno"), "Missing Inferno fruit config")
local DEFAULT_FIRE_BURST_ABILITY = "FireBurst"
local DEFAULT_BOMU_FRUIT_NAME = assert(DevilFruitConfig.GetDisplayName("Blast"), "Missing Blast fruit config")
local DEFAULT_BOMU_DETONATION_ABILITY = "LandMine"
local DEFAULT_PHOENIX_FRUIT_NAME = assert(DevilFruitConfig.GetDisplayName("Phoenix"), "Missing Phoenix fruit config")
local DEFAULT_PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local DEFAULT_PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local DEFAULT_PHOENIX_REBIRTH_ABILITY = "PhoenixRebirth"
local DEFAULT_GOMU_FRUIT_NAME = assert(DevilFruitConfig.GetDisplayName("Elastic"), "Missing Elastic fruit config")
local DEFAULT_RUBBER_LAUNCH_ABILITY = "RubberLaunch"
local DEFAULT_PHOENIX_EFFECT_COLOR = Color3.fromRGB(108, 255, 214)
local DEFAULT_PHOENIX_EFFECT_ACCENT_COLOR = Color3.fromRGB(255, 188, 113)
local PHOENIX_SHIELD_HIT_COLOR = Color3.fromRGB(255, 48, 72)
local PHOENIX_SHIELD_HIT_ACCENT_COLOR = Color3.fromRGB(255, 169, 103)
local FLAT_RING_ROTATION = CFrame.Angles(0, 0, math.rad(90))
local DEFAULT_PHOENIX_SHIELD_RADIUS = 18
local PHOENIX_SHIELD_AUTHORED_REFERENCE_RADIUS = 13
local PHOENIX_WING_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local PHOENIX_WING_ASSET_FRUIT_KEY = "Phoenix"
local PHOENIX_BODY_TEMPLATE_FOLDER_NAME = "Phoenix Body Template"
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
local PHOENIX_AUTHORED_VFX_DEFAULT_OFFSETS = {
	FlyFX = CFrame.new(0.165275574, -1.16604078, 1.30423737),
	ShieldFX = CFrame.new(0.165275574, 0.272972107, 0.601654053),
	-- ReviveFX is centered on the phoenix torso/root reference.
	ReviveFX = CFrame.new(),
}
local PHOENIX_ANIMATION_KEYS = {
	FlightStart = "Phoenix.PhoenixFlightStart",
	FlightLoop = "Phoenix.PhoenixFlightLoop",
	FlightIdle = "Phoenix.PhoenixFlightIdle",
	FlightEnd = "Phoenix.PhoenixFlightEnd",
	Shield = "Phoenix.PhoenixFlameShield",
	Rebirth = "Phoenix.PhoenixRevive",
}
local PHOENIX_FLIGHT_AUDIO_CUES = {
	LiftOff = "LiftOff",
	AirImpact = "AirImpact",
	SustainAnimation = "SustainAnimation",
	Deactivate = "Deactivate",
}
local PHOENIX_SHIELD_AUDIO_CUES = {
	Activate = "Activate",
	Deactivate = "Deactivate",
}
local PHOENIX_REBIRTH_AUDIO_CUES = {
	Revive = "Revive",
}
local PHOENIX_FLIGHT_DEFAULT_AUDIO_MARKERS = {
	LiftOff = { "LiftOff" },
	AirImpact = { "AirImpact" },
	Deactivate = { "Deactivate", "FlightEnd" },
}
local PHOENIX_ANIMATION_LENGTHS = {
	["Phoenix.PhoenixFlightStart"] = 3.1666667,
	["Phoenix.PhoenixFlightLoop"] = 5.2,
	["Phoenix.PhoenixFlightIdle"] = 1,
	["Phoenix.PhoenixFlightEnd"] = 1.2,
	["Phoenix.PhoenixFlameShield"] = 1.6666667,
	["Phoenix.PhoenixRevive"] = 2.4,
}
local PHOENIX_FLIGHT_START_TRACK_GROUP = "PhoenixFlightStart"
local PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP = "PhoenixFlightSustain"
local PHOENIX_FLIGHT_SUSTAIN_HEIGHT_TOLERANCE = 3
local PHOENIX_FLIGHT_SUSTAIN_FALLBACK_GRACE = 0.75
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

local function getPhoenixWingAssetRoot()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assetsFolder and assetsFolder:FindFirstChild("VFX")
	local phoenixVfxRoot = vfxFolder
		and (vfxFolder:FindFirstChild(PHOENIX_WING_ASSET_FRUIT_KEY) or vfxFolder:FindFirstChild("Tori"))
	local bodyTemplate = phoenixVfxRoot and phoenixVfxRoot:FindFirstChild(PHOENIX_BODY_TEMPLATE_FOLDER_NAME)
	if bodyTemplate and bodyTemplate:FindFirstChild("tori wings", true) then
		return bodyTemplate
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

	for _, connection in ipairs(entry.Connections or {}) do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
	end
	entry.Connections = {}

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

	local cleanupHandler = state.OnCleanup
	state.OnCleanup = nil
	if typeof(cleanupHandler) == "function" then
		local ok, err = pcall(cleanupHandler, fadeTime)
		if not ok then
			warn("[ClientEffectVisuals] Phoenix wing cleanup handler failed: " .. tostring(err))
		end
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

local function getStandardPhoenixVfxRoot()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assetsFolder and assetsFolder:FindFirstChild("VFX")
	if not vfxFolder then
		return nil
	end

	return vfxFolder:FindFirstChild(PHOENIX_WING_ASSET_FRUIT_KEY) or vfxFolder:FindFirstChild("Tori")
end

local function findPhoenixMoveFolderVfxTemplate(assetName)
	local phoenixVfxRoot = getStandardPhoenixVfxRoot()
	if not phoenixVfxRoot then
		return nil, nil
	end

	for _, moveFolderName in ipairs(PHOENIX_AUTHORED_VFX_MOVE_FOLDERS[assetName] or {}) do
		local moveRoot = phoenixVfxRoot:FindFirstChild(moveFolderName)
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

local function findPhoenixAuthoredVfxTemplate(assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		return nil, nil
	end

	return findPhoenixMoveFolderVfxTemplate(assetName)
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
		PhoenixFlightAudioHandler = config.PhoenixFlightAudioHandler,
		PhoenixShieldAudioHandler = config.PhoenixShieldAudioHandler,
		PhoenixRebirthAudioHandler = config.PhoenixRebirthAudioHandler,
		PhoenixWingEffects = setmetatable({}, { __mode = "k" }),
		PhoenixAnimationDefinitions = {},
	}, ClientEffectVisuals)
end

function ClientEffectVisuals:SetPhoenixFlightAudioHandler(handler)
	self.PhoenixFlightAudioHandler = handler
end

function ClientEffectVisuals:SetPhoenixShieldAudioHandler(handler)
	self.PhoenixShieldAudioHandler = handler
end

function ClientEffectVisuals:SetPhoenixRebirthAudioHandler(handler)
	self.PhoenixRebirthAudioHandler = handler
end

function ClientEffectVisuals:GetPhoenixAnimationDefinition(animationKey)
	self.PhoenixAnimationDefinitions = self.PhoenixAnimationDefinitions or {}
	local cachedDefinition = self.PhoenixAnimationDefinitions[animationKey]
	if cachedDefinition ~= nil then
		return cachedDefinition or nil
	end

	local animation, descriptor = AnimationResolver.GetAnimation(animationKey, {
		Context = "PhoenixVfx",
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

local function appendPhoenixFlightAudioMarkerName(markerNames, seenMarkers, markerName)
	if typeof(markerName) ~= "string" or markerName == "" or seenMarkers[markerName] then
		return
	end

	seenMarkers[markerName] = true
	markerNames[#markerNames + 1] = markerName
end

local function appendPhoenixFlightAudioMarkerNames(markerNames, seenMarkers, configuredMarkers)
	if typeof(configuredMarkers) == "string" then
		appendPhoenixFlightAudioMarkerName(markerNames, seenMarkers, configuredMarkers)
		return
	end

	if type(configuredMarkers) ~= "table" then
		return
	end

	for _, markerName in ipairs(configuredMarkers) do
		appendPhoenixFlightAudioMarkerName(markerNames, seenMarkers, markerName)
	end
end

local function resolvePhoenixFlightAudioMarkerNames(audioMarkers, cueName)
	local markerNames = {}
	local seenMarkers = {}
	if type(audioMarkers) == "table" then
		appendPhoenixFlightAudioMarkerNames(markerNames, seenMarkers, audioMarkers[cueName])
	end
	appendPhoenixFlightAudioMarkerNames(markerNames, seenMarkers, PHOENIX_FLIGHT_DEFAULT_AUDIO_MARKERS[cueName])
	return markerNames
end

local function addAnimationEntryConnection(entry, connection)
	if not entry or typeof(connection) ~= "RBXScriptConnection" then
		return
	end

	entry.Connections = entry.Connections or {}
	entry.Connections[#entry.Connections + 1] = connection
end

local function isPhoenixWingStateCurrent(self, targetPlayer, state)
	return self.PhoenixWingEffects
		and self.PhoenixWingEffects[targetPlayer] == state
		and state
		and not state.CleanedUp
end

local function emitPhoenixFlightAudioCue(self, state, targetPlayer, cueName, details, playOnce)
	if not isPhoenixWingStateCurrent(self, targetPlayer, state) then
		return false
	end

	if cueName == PHOENIX_FLIGHT_AUDIO_CUES.AirImpact and state.FlightEndPlayed then
		return false
	end

	if playOnce == true then
		state.PhoenixFlightAudioCues = state.PhoenixFlightAudioCues or {}
		if state.PhoenixFlightAudioCues[cueName] then
			return false
		end
		state.PhoenixFlightAudioCues[cueName] = true
	end

	local handler = self.PhoenixFlightAudioHandler
	if typeof(handler) ~= "function" then
		return false
	end

	local cueDetails = if type(details) == "table" then table.clone(details) else {}
	cueDetails.CueName = cueName

	local ok, err = pcall(handler, targetPlayer, cueName, cueDetails)
	if not ok then
		warn("[ClientEffectVisuals] Phoenix flight audio cue failed: " .. tostring(err))
		return false
	end

	return true
end

local function emitPhoenixShieldAudioCue(self, state, targetPlayer, cueName, details, playOnce)
	if not isPhoenixWingStateCurrent(self, targetPlayer, state) or state.PhoenixShieldAudioEnabled ~= true then
		return false
	end

	if playOnce == true then
		state.PhoenixShieldAudioCues = state.PhoenixShieldAudioCues or {}
		if state.PhoenixShieldAudioCues[cueName] then
			return false
		end
		state.PhoenixShieldAudioCues[cueName] = true
	end

	local handler = self.PhoenixShieldAudioHandler
	if typeof(handler) ~= "function" then
		return false
	end

	local cueDetails = if type(details) == "table" then table.clone(details) else {}
	cueDetails.CueName = cueName

	local ok, err = pcall(handler, targetPlayer, cueName, cueDetails)
	if not ok then
		warn("[ClientEffectVisuals] Phoenix shield audio cue failed: " .. tostring(err))
		return false
	end

	return true
end

local function emitPhoenixRebirthAudioCue(self, state, targetPlayer, cueName, details, playOnce)
	if not isPhoenixWingStateCurrent(self, targetPlayer, state) or state.Mode ~= "Rebirth" then
		return false
	end

	if playOnce == true then
		state.PhoenixRebirthAudioCues = state.PhoenixRebirthAudioCues or {}
		if state.PhoenixRebirthAudioCues[cueName] then
			return false
		end
		state.PhoenixRebirthAudioCues[cueName] = true
	end

	local handler = self.PhoenixRebirthAudioHandler
	if typeof(handler) ~= "function" then
		return false
	end

	local cueDetails = if type(details) == "table" then table.clone(details) else {}
	cueDetails.CueName = cueName

	local ok, err = pcall(handler, targetPlayer, cueName, cueDetails)
	if not ok then
		warn("[ClientEffectVisuals] Phoenix rebirth audio cue failed: " .. tostring(err))
		return false
	end

	return true
end

local function connectPhoenixFlightAudioMarkerCue(
	self,
	state,
	targetPlayer,
	entry,
	trackContext,
	cueName,
	markerNames,
	details
)
	if not entry or not entry.Track or not trackContext or trackContext.Kind ~= "Character" then
		return
	end

	local track = entry.Track
	local function trigger(markerName, source)
		local cueDetails = if type(details) == "table" then table.clone(details) else {}
		cueDetails.MarkerName = markerName
		cueDetails.Source = source
		emitPhoenixFlightAudioCue(self, state, targetPlayer, cueName, cueDetails, true)
	end

	for _, markerName in ipairs(markerNames or {}) do
		local ok, connection = pcall(function()
			return track:GetMarkerReachedSignal(markerName):Connect(function()
				trigger(markerName, "marker")
			end)
		end)
		if ok then
			addAnimationEntryConnection(entry, connection)
		end
	end

	addAnimationEntryConnection(entry, track.KeyframeReached:Connect(function(keyframeName)
		for _, markerName in ipairs(markerNames or {}) do
			if keyframeName == markerName then
				trigger(markerName, "keyframe")
				return
			end
		end
	end))
end

local function schedulePhoenixFlightAudioFallback(self, state, targetPlayer, cueName, delaySeconds, details)
	local delayTime = math.max(0, tonumber(delaySeconds) or 0)
	task.delay(delayTime, function()
		local cueDetails = if type(details) == "table" then table.clone(details) else {}
		cueDetails.Source = "fallback"
		emitPhoenixFlightAudioCue(self, state, targetPlayer, cueName, cueDetails, true)
	end)
end

function ClientEffectVisuals:PlayPhoenixAnimationOnAnimator(state, animator, animationKey, options, trackContext)
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

	if typeof(options.OnTrackCreated) == "function" then
		options.OnTrackCreated(entry, trackContext or {})
	end

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
		local _, length = self:PlayPhoenixAnimationOnAnimator(state, animator, animationKey, options, {
			Kind = "Feature",
			FeatureState = featureState,
			TargetPlayer = targetPlayer,
		})
		if length then
			longestLength = math.max(longestLength or 0, length)
		end
	end

	if not options or options.PlayCharacter ~= false then
		local humanoid = resolvePlayerHumanoid(targetPlayer)
		local animator = getOrCreateHumanoidAnimator(humanoid)
		local _, length = self:PlayPhoenixAnimationOnAnimator(state, animator, animationKey, options, {
			Kind = "Character",
			TargetPlayer = targetPlayer,
		})
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

local function getPhoenixAnimationOptions(options)
	local animationOptions = type(options) == "table" and options.Animation or nil
	return if type(animationOptions) == "table" then animationOptions else nil
end

local function getPhoenixAnimationNumber(animationOptions, key, fallback, minimum)
	local numericValue = tonumber(animationOptions and animationOptions[key])
	if not numericValue then
		return fallback
	end

	if minimum ~= nil then
		return math.max(minimum, numericValue)
	end

	return numericValue
end

local function getPhoenixAnimationPlaybackSpeed(animationOptions, key, fallback)
	return getPhoenixAnimationNumber(animationOptions, key, fallback or 1, 0.01)
end

local function getPhoenixAnimationFadeTime(animationOptions, key, fallback)
	return getPhoenixAnimationNumber(animationOptions, key, fallback or 0, 0)
end

function ClientEffectVisuals:SetPhoenixFlightSustainAnimation(state, targetPlayer, animationKey, animationOptions)
	if not state or state.CleanedUp or state.PhoenixFlightSustainAnimationKey == animationKey then
		return
	end

	local stopFadeTime = getPhoenixAnimationFadeTime(animationOptions, "StopFadeTime", 0.12)
	stopAnimationEntriesByGroup(state, PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP, stopFadeTime)
	local playbackSpeed = if animationKey == PHOENIX_ANIMATION_KEYS.FlightIdle
		then getPhoenixAnimationPlaybackSpeed(animationOptions, "IdlePlaybackSpeed", 1)
		else getPhoenixAnimationPlaybackSpeed(animationOptions, "LoopPlaybackSpeed", 1)
	local length = self:PlayPhoenixAnimation(state, targetPlayer, animationKey, {
		Looped = true,
		FadeTime = getPhoenixAnimationFadeTime(animationOptions, "FadeTime", 0.12),
		StopFadeTime = stopFadeTime,
		PlaybackSpeed = playbackSpeed,
		TrackGroup = PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP,
	})
	state.PhoenixFlightSustainAnimationKey = if length then animationKey else nil
	if length then
		emitPhoenixFlightAudioCue(self, state, targetPlayer, PHOENIX_FLIGHT_AUDIO_CUES.SustainAnimation, {
			AnimationKey = animationKey,
			Source = "sustain_animation",
		}, false)
	end
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

	local function fireTransitionHandler(handlerName, warningMessage, ...)
		local handler = options[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local ok, err = pcall(handler, ...)
		if not ok then
			warn(warningMessage .. tostring(err))
		end
	end

	local function setVfxActive(isActive)
		if isActive and entry.BurstOnly and entry.BurstStarted then
			return
		end
		if entry.VfxActive == isActive then
			return
		end

		entry.VfxActive = isActive
		if isActive then
			fireTransitionHandler("OnStart", "[ClientEffectVisuals] Phoenix authored VFX start handler failed: ")
			setPhoenixAuthoredVfxEnabled(clone, true)
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
		else
			fireTransitionHandler(
				"OnStop",
				"[ClientEffectVisuals] Phoenix authored VFX stop handler failed: ",
				options.StopReason or "inactive"
			)
			setPhoenixAuthoredVfxEnabled(clone, false)
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
		local stopReason = "duration"
		while clone.Parent and os.clock() < (entry.EndTime or endTime) do
			if state and state.CleanedUp then
				stopReason = "state_cleanup"
				break
			end
			if mountToTarget and not mountedTargetPart.Parent then
				stopReason = "target_removed"
				break
			end
			if not mountToTarget and options.Follow ~= false and not updatePosition() then
				stopReason = "target_lost"
				break
			end
			updateMovementGate()

			RunService.Heartbeat:Wait()
		end

		if state and state.AuthoredVfx and state.AuthoredVfx[assetName] == entry then
			state.AuthoredVfx[assetName] = nil
		end

		if clone.Parent then
			options.StopReason = stopReason
			setVfxActive(false)
			options.StopReason = nil
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

	local animationOptions = getPhoenixAnimationOptions(options)
	local startupPlaybackSpeed = getPhoenixAnimationPlaybackSpeed(animationOptions, "StartPlaybackSpeed", 1)
	local startupFadeTime = getPhoenixAnimationFadeTime(animationOptions, "FadeTime", 0.04)
	local startupStopFadeTime = getPhoenixAnimationFadeTime(animationOptions, "StopFadeTime", 0.08)
	local audioMarkers = options.AudioMarkers
	local liftOffMarkerNames = resolvePhoenixFlightAudioMarkerNames(audioMarkers, PHOENIX_FLIGHT_AUDIO_CUES.LiftOff)
	local function connectStartupAudioCues(entry, trackContext)
		connectPhoenixFlightAudioMarkerCue(
			self,
			state,
			targetPlayer,
			entry,
			trackContext,
			PHOENIX_FLIGHT_AUDIO_CUES.LiftOff,
			liftOffMarkerNames,
			{
				AnimationKey = PHOENIX_ANIMATION_KEYS.FlightStart,
			}
		)
	end

	local startupRawLength = self:PlayPhoenixAnimation(state, targetPlayer, PHOENIX_ANIMATION_KEYS.FlightStart, {
		Looped = false,
		FadeTime = startupFadeTime,
		StopFadeTime = startupStopFadeTime,
		PlaybackSpeed = startupPlaybackSpeed,
		TrackGroup = PHOENIX_FLIGHT_START_TRACK_GROUP,
		OnTrackCreated = connectStartupAudioCues,
	})
	local startupLength = if startupRawLength then startupRawLength / startupPlaybackSpeed else PHOENIX_FLIGHT_LOOP_FALLBACK_DELAY
	local requestedLoopDelay = tonumber(options.LoopDelay)
	local defaultLoopDelay = math.max(PHOENIX_FLIGHT_LOOP_FALLBACK_DELAY, startupLength)
	local loopDelay = if requestedLoopDelay and requestedLoopDelay >= 0 then requestedLoopDelay else defaultLoopDelay
	loopDelay = math.min(loopDelay, math.max(PHOENIX_WING_MIN_DURATION, duration))
	local sustainStartHeight = tonumber(options.SustainStartHeight)
	local sustainFallbackDelay = math.max(0, tonumber(options.SustainFallbackDelay) or loopDelay)
	if state then
		state.FlightTrailDelay = loopDelay
		schedulePhoenixFlightAudioFallback(self, state, targetPlayer, PHOENIX_FLIGHT_AUDIO_CUES.LiftOff, options.LiftOffFallbackDelay, {
			AnimationKey = PHOENIX_ANIMATION_KEYS.FlightStart,
		})
	end

	task.spawn(function()
		local sustainStarted = false
		local fallbackAt = os.clock() + sustainFallbackDelay
		local function isCurrentFlightState()
			return state ~= nil
				and isPhoenixWingStateCurrent(self, targetPlayer, state)
				and not state.CleanedUp
				and not state.FlightEndPlayed
				and state.Container
				and state.Container.Parent
		end

		local function startSustain(source)
			if sustainStarted or not isCurrentFlightState() then
				return false
			end

			sustainStarted = true
			state.PhoenixFlightSustainStarted = true
			stopAnimationEntriesByGroup(state, PHOENIX_FLIGHT_START_TRACK_GROUP, startupStopFadeTime)
			emitPhoenixFlightAudioCue(self, state, targetPlayer, PHOENIX_FLIGHT_AUDIO_CUES.AirImpact, {
				AnimationKey = PHOENIX_ANIMATION_KEYS.FlightStart,
				Source = source or "height_gate",
			}, true)

			if typeof(options.OnSustainStarted) == "function" then
				local ok, err = pcall(options.OnSustainStarted, source)
				if not ok then
					warn("[ClientEffectVisuals] Phoenix flight sustain callback failed: " .. tostring(err))
				end
			end

			return true
		end

		while isCurrentFlightState() and not sustainStarted do
			local rootPart = self.GetPlayerRootPart(targetPlayer)
			local reachedHeight = rootPart
				and sustainStartHeight
				and rootPart.Position.Y >= sustainStartHeight - PHOENIX_FLIGHT_SUSTAIN_HEIGHT_TOLERANCE
			if reachedHeight then
				startSustain("height_gate")
				break
			end
			if os.clock() >= fallbackAt then
				startSustain("fallback")
				break
			end

			RunService.Heartbeat:Wait()
		end

		while isCurrentFlightState() and sustainStarted do
			local rootPart = self.GetPlayerRootPart(targetPlayer)
			local animationKey = resolvePhoenixFlightSustainAnimationKey(rootPart, state.PhoenixFlightSustainAnimationKey)
			self:SetPhoenixFlightSustainAnimation(state, targetPlayer, animationKey, animationOptions)
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
			Mode = options.Mode,
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

			if state.Mode == "Flight" then
				emitPhoenixFlightAudioCue(self, state, targetPlayer, PHOENIX_FLIGHT_AUDIO_CUES.SustainAnimation, {
					AnimationKey = nil,
					Source = "wing_effect_cleanup",
				}, false)
			end
			cleanupPhoenixWingState(state)
			if self.PhoenixWingEffects and self.PhoenixWingEffects[targetPlayer] == state then
				self.PhoenixWingEffects[targetPlayer] = nil
			end
		end)
	end

	state.EndTime = math.max(state.EndTime, endTime)
	if options.Mode ~= nil then
		state.Mode = options.Mode
	end
	if type(options.AudioMarkers) == "table" then
		state.PhoenixFlightAudioMarkers = options.AudioMarkers
	end

	if options.Mode ~= nil and options.Mode ~= "Flight" then
		state.PlayFlightEndOnExpire = false
		state.FlightEndPlayed = true
		state.PhoenixFlightSustainAnimationKey = nil
		stopAnimationEntriesByGroup(state, PHOENIX_FLIGHT_SUSTAIN_TRACK_GROUP, 0.08)
	end

	if options.Mode == "Flight" then
		state.PlayFlightEndOnExpire = true
		state.FlightEndPlayed = false
		state.PhoenixFlightAnimationOptions = getPhoenixAnimationOptions(options)
		state.PhoenixFlightSustainStartHeight = tonumber(options.SustainStartHeight)
		state.PhoenixFlightSustainFallbackDelay = tonumber(options.SustainFallbackDelay)
		state.FlightTrailDelay = self:PlayPhoenixFlightAnimation(state, targetPlayer, duration, {
			LoopDelay = options.FlightTrailDelay,
			AudioMarkers = options.AudioMarkers,
			LiftOffFallbackDelay = options.LiftOffFallbackDelay,
			AirImpactLeadTime = options.AirImpactLeadTime,
			Animation = options.Animation,
			SustainStartHeight = options.SustainStartHeight,
			SustainFallbackDelay = options.SustainFallbackDelay,
			OnSustainStarted = options.OnSustainStarted,
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
		return false
	end

	local state = self.PhoenixWingEffects[targetPlayer]
	if not state or state.CleanedUp then
		return false
	end
	if state.FlightEndPlayed then
		return false
	end

	state.FlightEndPlayed = true
	state.PlayFlightEndOnExpire = false
	emitPhoenixFlightAudioCue(self, state, targetPlayer, PHOENIX_FLIGHT_AUDIO_CUES.SustainAnimation, {
		AnimationKey = nil,
		Source = "flight_end",
	}, false)

	for _, entry in ipairs(state.AnimationTracks or {}) do
		stopAnimationEntry(entry, 0.08)
	end
	state.AnimationTracks = {}
	state.PhoenixFlightSustainAnimationKey = nil

	local deactivateMarkerNames = resolvePhoenixFlightAudioMarkerNames(
		state.PhoenixFlightAudioMarkers,
		PHOENIX_FLIGHT_AUDIO_CUES.Deactivate
	)
	local function connectEndAudioCue(entry, trackContext)
		connectPhoenixFlightAudioMarkerCue(
			self,
			state,
			targetPlayer,
			entry,
			trackContext,
			PHOENIX_FLIGHT_AUDIO_CUES.Deactivate,
			deactivateMarkerNames,
			{
				AnimationKey = PHOENIX_ANIMATION_KEYS.FlightEnd,
			}
		)
	end

	local animationOptions = state.PhoenixFlightAnimationOptions
	local endPlaybackSpeed = getPhoenixAnimationPlaybackSpeed(animationOptions, "EndPlaybackSpeed", 1)
	local endRawLength = self:PlayPhoenixAnimation(state, targetPlayer, PHOENIX_ANIMATION_KEYS.FlightEnd, {
		Looped = false,
		FadeTime = getPhoenixAnimationFadeTime(animationOptions, "FadeTime", 0.04),
		StopFadeTime = getPhoenixAnimationFadeTime(animationOptions, "StopFadeTime", 0.08),
		PlaybackSpeed = endPlaybackSpeed,
		OnTrackCreated = connectEndAudioCue,
	})
	schedulePhoenixFlightAudioFallback(self, state, targetPlayer, PHOENIX_FLIGHT_AUDIO_CUES.Deactivate, 0, {
		AnimationKey = PHOENIX_ANIMATION_KEYS.FlightEnd,
	})
	local endDuration = if endRawLength then endRawLength / endPlaybackSpeed else 0.25
	state.EndTime = os.clock() + math.max(0.15, math.min(endDuration, 1.2))
	return true
end

function ClientEffectVisuals:StopPhoenixWingEffect(targetPlayer, fadeTime)
	if not self.PhoenixWingEffects then
		return
	end

	local state = self.PhoenixWingEffects[targetPlayer]
	if not state then
		return
	end

	if state.Mode == "Flight" then
		emitPhoenixFlightAudioCue(self, state, targetPlayer, PHOENIX_FLIGHT_AUDIO_CUES.SustainAnimation, {
			AnimationKey = nil,
			Source = "wing_effect_stop",
		}, false)
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

	local reviveSoundOffset = tonumber(payload.AudioReviveSoundOffset) or 0
	local reviveSoundDelay = math.max(0, reviveDelay + reviveSoundOffset)
	local remainingReviveSoundDelay = math.max(0, reviveSoundDelay - elapsed)
	if remainingReviveSoundDelay <= remainingDuration + 0.2 then
		task.delay(remainingReviveSoundDelay, function()
			emitPhoenixRebirthAudioCue(self, state, targetPlayer, PHOENIX_REBIRTH_AUDIO_CUES.Revive, {
				AnimationKey = animationKey,
				ReviveSoundOffset = reviveSoundOffset,
				Source = "revive_sound_offset",
			}, true)
		end)
	end

	local remainingReviveDelay = math.max(0, reviveDelay - elapsed)
	if remainingReviveDelay <= remainingDuration + 0.2 then
		task.delay(remainingReviveDelay, function()
			local playedAuthoredReviveVfx = false
			if state and not state.CleanedUp then
				-- ReviveFX is authored as a short burst on the phoenix body template torso.
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
	local maxRiseHeight = tonumber(payload.MaxRiseHeight)
	local sustainStartHeight = if maxRiseHeight and maxRiseHeight > 0 then rootPart.Position.Y + maxRiseHeight else nil
	local sustainFallbackDelay = startupDuration + heightDelay + PHOENIX_FLIGHT_SUSTAIN_FALLBACK_GRACE
	local state = nil

	local function playFlightTrail()
		if not state or not self.PhoenixWingEffects or self.PhoenixWingEffects[targetPlayer] ~= state or state.CleanedUp then
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

	state = self:CreatePhoenixWingEffect(targetPlayer, visualDuration, {
		Mode = "Flight",
		FlightTrailDelay = startupDuration + heightDelay,
		AudioMarkers = type(payload.AudioMarkers) == "table" and payload.AudioMarkers or nil,
		LiftOffFallbackDelay = 0,
		AirImpactLeadTime = math.max(0, tonumber(payload.AudioAirImpactLeadTime) or 0),
		Animation = type(payload.Animation) == "table" and payload.Animation or nil,
		SustainStartHeight = sustainStartHeight,
		SustainFallbackDelay = sustainFallbackDelay,
		OnSustainStarted = playFlightTrail,
	})
	if not state then
		return
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
	local serverEndTime = tonumber(payload.EndTime)
	if serverEndTime then
		duration = math.max(0.1, serverEndTime - Workspace:GetServerTimeNow())
	end
	local radius = math.max(1, tonumber(payload.Radius) or DEFAULT_PHOENIX_SHIELD_RADIUS)
	local animationOptions = type(payload.Animation) == "table" and payload.Animation or nil
	local state = self:CreatePhoenixWingEffect(targetPlayer, duration, {
		AnimationKey = PHOENIX_ANIMATION_KEYS.Shield,
		Looped = false,
		FadeTime = getPhoenixAnimationFadeTime(animationOptions, "FadeTime", 0.06),
		StopFadeTime = getPhoenixAnimationFadeTime(animationOptions, "StopFadeTime", 0.1),
		PlaybackSpeed = getPhoenixAnimationPlaybackSpeed(animationOptions, "PlaybackSpeed", 1),
		PlayAnimationOnce = true,
	})
	if not state then
		return
	end

	local existingShieldVfx = state.AuthoredVfx and state.AuthoredVfx[PHOENIX_AUTHORED_SHIELD_FX_NAME]
	if not (existingShieldVfx and existingShieldVfx.Clone and existingShieldVfx.Clone.Parent) then
		state.PhoenixShieldAudioCues = nil
	end
	state.PhoenixShieldAudioEnabled = true
	state.OnCleanup = function(cleanupFadeTime)
		emitPhoenixShieldAudioCue(self, state, targetPlayer, PHOENIX_SHIELD_AUDIO_CUES.Deactivate, {
			PlayDeactivate = cleanupFadeTime ~= 0,
			Source = "shield_vfx_stop",
		}, true)
	end

	self:PlayPhoenixAuthoredVfx(state, targetPlayer, PHOENIX_AUTHORED_SHIELD_FX_NAME, duration, {
		EmitCount = 20,
		TargetPartNames = PHOENIX_REFERENCE_PART_NAMES,
		MountToTarget = true,
		LockParticlesToPart = true,
		FadeOutDuration = 0,
		Scale = radius / PHOENIX_SHIELD_AUTHORED_REFERENCE_RADIUS,
		OnStart = function()
			emitPhoenixShieldAudioCue(self, state, targetPlayer, PHOENIX_SHIELD_AUDIO_CUES.Activate, {
				Source = "shield_vfx_start",
			}, true)
		end,
		OnStop = function(stopReason)
			emitPhoenixShieldAudioCue(self, state, targetPlayer, PHOENIX_SHIELD_AUDIO_CUES.Deactivate, {
				PlayDeactivate = stopReason == "duration",
				Source = "shield_vfx_stop",
				StopReason = stopReason,
			}, true)
		end,
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
