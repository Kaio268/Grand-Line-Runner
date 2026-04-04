local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local DEBUG_R6_ANIM = true
local PATCH_FLAG_ATTRIBUTE = "ReactR6AnimationPatched"

-- Classic Roblox R6 animation ids.
local R6_IDS = {
	idle = { "180435571", "180435792" },
	walk = "180426354",
	run = "180426354",
	jump = "125750702",
	fall = "180436148",
	climb = "180436334",
	swim = "180426354",
	swimidle = "180426354",
}

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

	animation.AnimationId = "rbxassetid://" .. tostring(id)
end

local function patchAnimateScript(animateScript)
	setAnimationId(animateScript, "idle", "Animation1", R6_IDS.idle[1])
	setAnimationId(animateScript, "idle", "Animation2", R6_IDS.idle[2])
	setAnimationId(animateScript, "walk", "WalkAnim", R6_IDS.walk)
	setAnimationId(animateScript, "run", "RunAnim", R6_IDS.run)
	setAnimationId(animateScript, "jump", "JumpAnim", R6_IDS.jump)
	setAnimationId(animateScript, "fall", "FallAnim", R6_IDS.fall)
	setAnimationId(animateScript, "climb", "ClimbAnim", R6_IDS.climb)
	setAnimationId(animateScript, "swim", "Swim", R6_IDS.swim)
	setAnimationId(animateScript, "swimidle", "SwimIdle", R6_IDS.swimidle)
end

local function installVelocityFallback(character, humanoid)
	local rootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then
		return
	end

	local animator = ensureAnimator(humanoid)
	local walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = "rbxassetid://" .. R6_IDS.walk
	local runAnim = Instance.new("Animation")
	runAnim.AnimationId = "rbxassetid://" .. R6_IDS.run

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
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return
	end
	if character:GetAttribute(PATCH_FLAG_ATTRIBUTE) == true then
		return
	end
	character:SetAttribute(PATCH_FLAG_ATTRIBUTE, true)

	local animateScript = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 10)
	if animateScript and animateScript:IsA("LocalScript") then
		patchAnimateScript(animateScript)
		animateScript.Disabled = true
		task.defer(function()
			if animateScript.Parent and humanoid.Parent then
				animateScript.Disabled = false
			end
		end)
	end

	installVelocityFallback(character, humanoid)
	debugLog("patched R6 character", character:GetFullName())
end

player.CharacterAdded:Connect(function(character)
	task.defer(patchCharacter, character)
end)

if player.Character then
	task.defer(patchCharacter, player.Character)
end
