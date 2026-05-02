local Players = game:GetService("Players")

local TemporaryRagdollService = {}

local RUNTIME_FOLDER_NAME = "TemporaryRagdollRuntime"
local ATTACHMENT_PREFIX = "TemporaryRagdollAttachment"
local CONSTRAINT_PREFIX = "TemporaryRagdollConstraint"
local MIN_DURATION = 0.05
local DEFAULT_DURATION = 1

local activeRagdollsByHumanoid = setmetatable({}, { __mode = "k" })

local function getCharacterHumanoidAndRoot(character)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
		or (character.PrimaryPart and character.PrimaryPart:IsA("BasePart") and character.PrimaryPart or nil)
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return humanoid, nil
	end

	return humanoid, rootPart
end

local function clearRuntimeFolder(character)
	local existing = character and character:FindFirstChild(RUNTIME_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

local function createRuntimeFolder(character)
	clearRuntimeFolder(character)

	local folder = Instance.new("Folder")
	folder.Name = RUNTIME_FOLDER_NAME
	folder.Parent = character
	return folder
end

local function isCharacterPart(character, part)
	return part and part:IsA("BasePart") and part:IsDescendantOf(character)
end

local function shouldRagdollMotor(character, motor)
	if not motor:IsA("Motor6D") then
		return false
	end

	return isCharacterPart(character, motor.Part0) and isCharacterPart(character, motor.Part1)
end

local function snapshotHumanoidRequiresNeck(humanoid)
	local ok, value = pcall(function()
		return humanoid.RequiresNeck
	end)
	if ok then
		return value
	end

	return nil
end

local function setHumanoidRequiresNeck(humanoid, value)
	if value == nil then
		return
	end

	pcall(function()
		humanoid.RequiresNeck = value
	end)
end

local function snapshotCharacterParts(character, rootPart)
	local parts = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts[descendant] = {
				CanCollide = descendant.CanCollide,
				Massless = descendant.Massless,
			}

			descendant.Anchored = false
			if descendant == rootPart then
				descendant.CanCollide = false
			else
				descendant.CanCollide = true
				descendant.Massless = false
			end
		end
	end

	return parts
end

local function restoreCharacterParts(parts)
	for part, snapshot in pairs(parts or {}) do
		if part and part.Parent and type(snapshot) == "table" then
			part.CanCollide = snapshot.CanCollide == true
			part.Massless = snapshot.Massless == true
		end
	end
end

local function createRagdollJoint(folder, motor)
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = ATTACHMENT_PREFIX .. "0_" .. motor.Name
	attachment0.CFrame = motor.C0
	attachment0.Parent = motor.Part0

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = ATTACHMENT_PREFIX .. "1_" .. motor.Name
	attachment1.CFrame = motor.C1
	attachment1.Parent = motor.Part1

	local socket = Instance.new("BallSocketConstraint")
	socket.Name = CONSTRAINT_PREFIX .. "_" .. motor.Name
	socket.Attachment0 = attachment0
	socket.Attachment1 = attachment1
	socket.LimitsEnabled = true
	socket.TwistLimitsEnabled = true
	socket.UpperAngle = 70
	socket.TwistLowerAngle = -45
	socket.TwistUpperAngle = 45
	socket.Parent = folder

	local noCollision = Instance.new("NoCollisionConstraint")
	noCollision.Name = CONSTRAINT_PREFIX .. "NoCollision_" .. motor.Name
	noCollision.Part0 = motor.Part0
	noCollision.Part1 = motor.Part1
	noCollision.Parent = folder

	return {
		Motor = motor,
		Enabled = motor.Enabled,
		Attachment0 = attachment0,
		Attachment1 = attachment1,
	}
end

local function restoreMotors(motorSnapshots)
	for _, snapshot in ipairs(motorSnapshots or {}) do
		local motor = snapshot.Motor
		if motor and motor.Parent then
			motor.Enabled = snapshot.Enabled ~= false
		end
		if snapshot.Attachment0 then
			snapshot.Attachment0:Destroy()
		end
		if snapshot.Attachment1 then
			snapshot.Attachment1:Destroy()
		end
	end
end

local function applyWakeImpulse(rootPart, impulse)
	if typeof(impulse) ~= "Vector3" or impulse.Magnitude <= 0.01 then
		return
	end

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	rootPart:ApplyImpulse(impulse * rootPart.AssemblyMass)
	rootPart.AssemblyAngularVelocity += Vector3.new(0, 0, math.clamp(impulse.X, -25, 25))
end

function TemporaryRagdollService.Restore(state)
	if type(state) ~= "table" or state.Restored == true then
		return false
	end

	state.Restored = true
	if state.Humanoid and activeRagdollsByHumanoid[state.Humanoid] == state then
		activeRagdollsByHumanoid[state.Humanoid] = nil
	end

	restoreMotors(state.Motors)
	restoreCharacterParts(state.Parts)

	local humanoid = state.Humanoid
	if humanoid and humanoid.Parent then
		setHumanoidRequiresNeck(humanoid, state.RequiresNeck)
		humanoid.PlatformStand = state.PlatformStand == true
		humanoid.AutoRotate = state.AutoRotate ~= false

		if humanoid.Health > 0 and state.PlatformStand ~= true then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end

	if state.RuntimeFolder then
		state.RuntimeFolder:Destroy()
	end

	if state.RootPart and state.RootPart.Parent and state.NetworkOwner and state.NetworkOwner.Parent == Players then
		pcall(function()
			state.RootPart:SetNetworkOwner(state.NetworkOwner)
		end)
	end

	return true
end

function TemporaryRagdollService.Apply(character, duration, options)
	options = if typeof(options) == "table" then options else {}

	local humanoid, rootPart = getCharacterHumanoidAndRoot(character)
	if not humanoid or not rootPart then
		return nil
	end

	local previousState = activeRagdollsByHumanoid[humanoid]
	if previousState then
		TemporaryRagdollService.Restore(previousState)
	end

	local runtimeFolder = createRuntimeFolder(character)
	local state = {
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
		RuntimeFolder = runtimeFolder,
		Motors = {},
		Parts = snapshotCharacterParts(character, rootPart),
		PlatformStand = humanoid.PlatformStand,
		AutoRotate = humanoid.AutoRotate,
		RequiresNeck = snapshotHumanoidRequiresNeck(humanoid),
		NetworkOwner = options.NetworkOwner,
		Restored = false,
	}

	setHumanoidRequiresNeck(humanoid, false)
	humanoid.Sit = false
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.Jump = false

	for _, descendant in ipairs(character:GetDescendants()) do
		if shouldRagdollMotor(character, descendant) then
			table.insert(state.Motors, createRagdollJoint(runtimeFolder, descendant))
			descendant.Enabled = false
		end
	end

	if #state.Motors == 0 then
		runtimeFolder:Destroy()
		restoreCharacterParts(state.Parts)
		return nil
	end

	activeRagdollsByHumanoid[humanoid] = state
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	applyWakeImpulse(rootPart, options.Impulse)

	task.delay(math.max(MIN_DURATION, tonumber(duration) or DEFAULT_DURATION), function()
		TemporaryRagdollService.Restore(state)
	end)

	return state
end

return TemporaryRagdollService
