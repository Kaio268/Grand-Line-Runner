local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruits = Modules:WaitForChild("DevilFruits")
local AnimationLoadDiagnostics = require(DevilFruits:WaitForChild("AnimationLoadDiagnostics"))

local HoroGhostAnimateController = {}

local SOURCE_LABEL = "ServerScriptService.Modules.DevilFruits.Horo.Server.HoroGhostAnimateController"
local ANIMATION_FOLDER_NAME = "HoroGhostAnimateAnimations"
local CONTROLLER_ATTRIBUTE = "HoroGhostAnimateController"
local IDLE_ANIMATION_ID = "rbxassetid://78722993869675"
local WALK_ANIMATION_ID = "rbxassetid://126056183957340"
local TRANSITION_TIME = 0.1
local MIN_WALK_SPEED = 0.75
local MIN_MOVE_DIRECTION = 0.03
local REFERENCE_WALK_SPEED = 14.5

local function getRootPart(ghostModel, rootPart)
	if rootPart and rootPart:IsA("BasePart") and rootPart:IsDescendantOf(ghostModel) then
		return rootPart
	end

	local namedRoot = ghostModel:FindFirstChild("HumanoidRootPart")
	if namedRoot and namedRoot:IsA("BasePart") then
		return namedRoot
	end

	if ghostModel.PrimaryPart and ghostModel.PrimaryPart:IsA("BasePart") then
		return ghostModel.PrimaryPart
	end

	return ghostModel:FindFirstChildWhichIsA("BasePart", true)
end

local function ensureAnimator(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")
	if animator and animator:IsA("Animator") then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function createAnimation(folder, name, animationId)
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId
	animation.Parent = folder
	return animation
end

local function loadTrack(animator, animation, priority)
	local track = AnimationLoadDiagnostics.LoadTrack(animator, animation, SOURCE_LABEL)
	if not track then
		return nil
	end

	track.Priority = priority
	track.Looped = true
	return track
end

local function stopAndDestroyTrack(track, fadeTime)
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return
	end

	pcall(function()
		track:Stop(math.max(0, tonumber(fadeTime) or 0))
	end)
	pcall(function()
		track:Destroy()
	end)
end

local function clearExistingTracks(animator)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		stopAndDestroyTrack(track, 0)
	end
end

local function getPlanarSpeed(rootPart)
	if not rootPart or not rootPart.Parent then
		return 0
	end

	local velocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function resolveLocomotion(state)
	local humanoid = state.Humanoid
	local rootPart = state.RootPart
	if not state.GhostModel.Parent or not humanoid.Parent or humanoid.Health <= 0 or not rootPart.Parent then
		return nil, 1
	end

	local planarSpeed = getPlanarSpeed(rootPart)
	if planarSpeed > MIN_WALK_SPEED or humanoid.MoveDirection.Magnitude > MIN_MOVE_DIRECTION then
		return "Walk", math.clamp(planarSpeed / REFERENCE_WALK_SPEED, 0.65, 2.5)
	end

	return "Idle", 1
end

local function playTrack(state, key, speed)
	if state.CurrentKey == key then
		local currentTrack = state.CurrentTrack
		if currentTrack and currentTrack.IsPlaying then
			pcall(function()
				currentTrack:AdjustSpeed(speed)
			end)
		elseif currentTrack then
			pcall(function()
				currentTrack:Play(TRANSITION_TIME, 1, speed)
			end)
		end
		return
	end

	if state.CurrentTrack then
		pcall(function()
			state.CurrentTrack:Stop(TRANSITION_TIME)
		end)
	end
	state.CurrentKey = nil
	state.CurrentTrack = nil

	local nextTrack = state.Tracks[key]
	if not nextTrack then
		return
	end

	local played = pcall(function()
		nextTrack:Play(TRANSITION_TIME, 1, speed)
	end)
	if played then
		state.CurrentKey = key
		state.CurrentTrack = nextTrack
	end
end

local function stopState(state, reason)
	if type(state) ~= "table" or state.Stopped then
		return
	end

	state.Stopped = true
	state.StopReason = tostring(reason or "stopped")
	if typeof(state.HeartbeatConnection) == "RBXScriptConnection" then
		state.HeartbeatConnection:Disconnect()
	end
	if typeof(state.DiedConnection) == "RBXScriptConnection" then
		state.DiedConnection:Disconnect()
	end
	if typeof(state.AncestryConnection) == "RBXScriptConnection" then
		state.AncestryConnection:Disconnect()
	end

	stopAndDestroyTrack(state.Tracks and state.Tracks.Idle, TRANSITION_TIME)
	stopAndDestroyTrack(state.Tracks and state.Tracks.Walk, TRANSITION_TIME)

	if state.GhostModel and state.GhostModel.Parent then
		state.GhostModel:SetAttribute(CONTROLLER_ATTRIBUTE, nil)
	end
	if state.AnimationFolder and state.AnimationFolder.Parent then
		state.AnimationFolder:Destroy()
	end
end

function HoroGhostAnimateController.Start(ghostModel, humanoid, rootPart)
	if typeof(ghostModel) ~= "Instance" or not ghostModel:IsA("Model") then
		return nil
	end
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then
		return nil
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return nil
	end

	local resolvedRootPart = getRootPart(ghostModel, rootPart)
	if not resolvedRootPart then
		return nil
	end

	local animator = ensureAnimator(humanoid)
	clearExistingTracks(animator)

	local animationFolder = Instance.new("Folder")
	animationFolder.Name = ANIMATION_FOLDER_NAME
	animationFolder.Parent = ghostModel

	local idleAnimation = createAnimation(animationFolder, "Idle", IDLE_ANIMATION_ID)
	local walkAnimation = createAnimation(animationFolder, "Walk", WALK_ANIMATION_ID)
	local idleTrack = loadTrack(animator, idleAnimation, Enum.AnimationPriority.Core)
	local walkTrack = loadTrack(animator, walkAnimation, Enum.AnimationPriority.Core)
	if not idleTrack and not walkTrack then
		animationFolder:Destroy()
		return nil
	end

	local state = {
		GhostModel = ghostModel,
		Humanoid = humanoid,
		RootPart = resolvedRootPart,
		AnimationFolder = animationFolder,
		Tracks = {
			Idle = idleTrack,
			Walk = walkTrack,
		},
		CurrentKey = nil,
		CurrentTrack = nil,
		Stopped = false,
	}

	function state:Step()
		local key, speed = resolveLocomotion(self)
		if not key then
			stopState(self, "invalid_ghost")
			return
		end

		if not self.Tracks[key] then
			key = if key == "Walk" then "Idle" else nil
		end
		if key then
			playTrack(self, key, speed)
		end
	end

	function state:Stop(reason)
		stopState(self, reason)
	end

	ghostModel:SetAttribute(CONTROLLER_ATTRIBUTE, true)
	state.DiedConnection = humanoid.Died:Connect(function()
		stopState(state, "humanoid_died")
	end)
	state.AncestryConnection = ghostModel.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			stopState(state, "ghost_removed")
		end
	end)
	state.HeartbeatConnection = RunService.Heartbeat:Connect(function()
		if state.Stopped then
			return
		end
		state:Step()
	end)

	state:Step()
	return state
end

function HoroGhostAnimateController.Stop(state, reason)
	stopState(state, reason)
end

return HoroGhostAnimateController
