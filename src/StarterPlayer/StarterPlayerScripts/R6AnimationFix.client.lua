local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local AnimationResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("AnimationResolver"))

local DEBUG_R6_ANIM = true
local PATCH_FLAG_ATTRIBUTE = "ReactR6AnimationPatched"

-- R6 animate patch ids. Locomotion comes from the shared animation registry.
local R6_IDS = {
	idle = { "180435571", "180435792" },
	walk = AnimationResolver.GetAssetId("Movement.R6Walk", { Context = "R6AnimationFix.Walk" }) or "rbxassetid://180426354",
	run = AnimationResolver.GetAssetId("Movement.R6Walk", { Context = "R6AnimationFix.Run" }) or "rbxassetid://180426354",
	jump = "125750702",
	fall = "180436148",
	climb = "180436334",
	swim = AnimationResolver.GetAssetId("Movement.R6Walk", { Context = "R6AnimationFix.Swim" }) or "rbxassetid://180426354",
	swimidle = AnimationResolver.GetAssetId("Movement.R6Walk", { Context = "R6AnimationFix.SwimIdle" }) or "rbxassetid://180426354",
}

local R6G_IDS = {
	walk = AnimationResolver.GetAssetId("Movement.R6GWalk", { Context = "R6AnimationFix.R6GWalk" }) or R6_IDS.walk,
	run = AnimationResolver.GetAssetId("Movement.R6GWalk", { Context = "R6AnimationFix.R6GRun" }) or R6_IDS.run,
	swim = AnimationResolver.GetAssetId("Movement.R6GWalk", { Context = "R6AnimationFix.R6GSwim" }) or R6_IDS.swim,
	swimidle = AnimationResolver.GetAssetId("Movement.R6GWalk", { Context = "R6AnimationFix.R6GSwimIdle" }) or R6_IDS.swimidle,
}

local function toAnimationId(id)
	local resolved = tostring(id or "")
	if string.match(resolved, "^rbxassetid://") then
		return resolved
	end

	return "rbxassetid://" .. resolved
end

local function debugLog(...)
	if DEBUG_R6_ANIM then
		print("[R6AnimFix]", ...)
	end
end

local function ensureAnimator(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function setAnimationId(animateScript, folderName, animationName, id)
	local folder = animateScript:FindFirstChild(folderName)
	if not folder then
		return
	end

	local animation = folder:FindFirstChild(animationName)
	if not (animation and animation:IsA("Animation")) then
		animation = Instance.new("Animation")
		animation.Name = animationName
		animation.Parent = folder
	end

	animation.AnimationId = toAnimationId(id)
end

local function patchAnimateScript(animateScript, movementIds, includeClassicR6States)
	if includeClassicR6States then
		setAnimationId(animateScript, "idle", "Animation1", R6_IDS.idle[1])
		setAnimationId(animateScript, "idle", "Animation2", R6_IDS.idle[2])
		setAnimationId(animateScript, "jump", "JumpAnim", R6_IDS.jump)
		setAnimationId(animateScript, "fall", "FallAnim", R6_IDS.fall)
		setAnimationId(animateScript, "climb", "ClimbAnim", R6_IDS.climb)
	end

	setAnimationId(animateScript, "walk", "WalkAnim", movementIds.walk)
	setAnimationId(animateScript, "run", "RunAnim", movementIds.run)
	setAnimationId(animateScript, "swim", "Swim", movementIds.swim)
	setAnimationId(animateScript, "swimidle", "SwimIdle", movementIds.swimidle)
end

local function installVelocityFallback(character, humanoid, movementIds)
	local rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then
		return
	end

	local animator = ensureAnimator(humanoid)
	local walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = toAnimationId(movementIds.walk)
	local runAnim = Instance.new("Animation")
	runAnim.AnimationId = toAnimationId(movementIds.run)

	local walkTrack = animator:LoadAnimation(walkAnim)
	local runTrack = animator:LoadAnimation(runAnim)
	walkTrack.Priority = Enum.AnimationPriority.Movement
	runTrack.Priority = Enum.AnimationPriority.Movement
	walkTrack.Looped = true
	runTrack.Looped = true
	walkAnim:Destroy()
	runAnim:Destroy()

	local function stopMovementTracks()
		if walkTrack.IsPlaying then
			walkTrack:Stop(0.12)
		end
		if runTrack.IsPlaying then
			runTrack:Stop(0.12)
		end
	end

	local function updateMotion(speedHint)
		local moveMagnitude = humanoid.MoveDirection.Magnitude
		local velocity = rootPart.AssemblyLinearVelocity
		local planarSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local speed = math.max(tonumber(speedHint) or 0, planarSpeed)
		local shouldMove = moveMagnitude > 0.03 and speed > 0.8 and humanoid.Health > 0

		if not shouldMove then
			stopMovementTracks()
			return
		end

		local speedRatio = math.clamp(speed / 16, 0.7, 2.8)
		local useRun = speed >= 18
		local playTrack = useRun and runTrack or walkTrack
		local stopTrack = useRun and walkTrack or runTrack

		if stopTrack.IsPlaying then
			stopTrack:Stop(0.08)
		end
		if not playTrack.IsPlaying then
			playTrack:Play(0.08, 1, speedRatio)
		else
			playTrack:AdjustSpeed(speedRatio)
		end
	end

	local runningConnection = humanoid.Running:Connect(function(speed)
		updateMotion(speed)
	end)

	local heartbeatConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if not character.Parent or humanoid.Health <= 0 or humanoid.Parent ~= character then
			stopMovementTracks()
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
			end
			if runningConnection then
				runningConnection:Disconnect()
			end
			return
		end

		updateMotion()
	end)

	humanoid.Died:Connect(function()
		stopMovementTracks()
		if heartbeatConnection then
			heartbeatConnection:Disconnect()
		end
		if runningConnection then
			runningConnection:Disconnect()
		end
	end)
end

local function patchCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local rigVariant = AnimationResolver.ResolveRigVariant(player, character, humanoid, {
		DefaultVariant = "Default",
	})
	local isClassicR6 = humanoid.RigType == Enum.HumanoidRigType.R6
	local isR6G = rigVariant == "R6G"
	if not isClassicR6 and not isR6G then
		return
	end

	if character:GetAttribute(PATCH_FLAG_ATTRIBUTE) == true then
		return
	end
	character:SetAttribute(PATCH_FLAG_ATTRIBUTE, true)

	local movementIds = isR6G and R6G_IDS or R6_IDS
	local patchRigName = isR6G and "R6G" or "R6"

	local animateScript = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 10)
	if animateScript and animateScript:IsA("LocalScript") then
		patchAnimateScript(animateScript, movementIds, isClassicR6)
		animateScript.Disabled = true
		task.defer(function()
			if animateScript.Parent and humanoid.Parent then
				animateScript.Disabled = false
			end
		end)
	end

	installVelocityFallback(character, humanoid, movementIds)
	debugLog("patched character", patchRigName, character:GetFullName())
end

player.CharacterAdded:Connect(function(character)
	task.defer(patchCharacter, character)
end)

if player.Character then
	task.defer(patchCharacter, player.Character)
end
