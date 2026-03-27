local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local CometCollectFX = ReplicatedStorage:WaitForChild("CometCollectFX")
local CometCollectDone = ReplicatedStorage:WaitForChild("CometCollectDone")
local serverFolder = workspace:WaitForChild("EventFX_Comets")

local clientFolder = workspace:FindFirstChild("EventFX_CometsClient")
if not clientFolder then
	clientFolder = Instance.new("Folder")
	clientFolder.Name = "EventFX_CometsClient"
	clientFolder.Parent = workspace
end

local CFG = {
	PopTime = 0.25,
	HoverTime = 0.4,
	FlyDuration = 0.9,
	ShrinkTo = 0.03,
	HitDistance = 1.2,
	OrbitSpeed = {3, 6},
	SpinSpeed = 12,
	HeightKickMult = 2.5,
}

local function rand(a, b)
	return a + (b - a) * math.random()
end

local function clamp01(x)
	return x < 0 and 0 or (x > 1 and 1 or x)
end

local function easeOutCubic(t)
	t = clamp01(t)
	local k = 1 - t
	return 1 - k * k * k
end

local function smoothPulse01(t, a, b)
	local u = clamp01(t / a)
	u = u * u * (3 - 2 * u)
	local v = clamp01((1 - t) / b)
	v = v * v * (3 - 2 * v)
	return u * v
end

local function bezier3(t, p0, p1, p2, p3)
	local mt = 1 - t
	return (mt^3)*p0 + 3*(mt^2)*t*p1 + 3*mt*(t^2)*p2 + (t^3)*p3
end

local function getHead()
	local ch = player.Character
	if not ch then
		return nil
	end
	return ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart")
end

local function getRoot(inst)
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		if inst.PrimaryPart and inst.PrimaryPart:IsA("BasePart") then
			return inst.PrimaryPart
		end
		local p = inst:FindFirstChildWhichIsA("BasePart", true)
		if p then
			inst.PrimaryPart = p
			return p
		end
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function setPivot(inst, cf)
	if inst:IsA("Model") then
		inst:PivotTo(cf)
	else
		local r = getRoot(inst)
		if r then
			r.CFrame = cf
		end
	end
end

local function getPivot(inst)
	if inst:IsA("Model") then
		return inst:GetPivot()
	else
		local r = getRoot(inst)
		if r then
			return r.CFrame
		end
	end
	return CFrame.new()
end

local function findServerComet(cometId)
	for _, obj in ipairs(serverFolder:GetChildren()) do
		if obj:GetAttribute("CometId") == cometId then
			return obj
		end
	end
	return nil
end

local function stripSounds(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Sound") then
			d:Destroy()
		end
	end
end

local function prepClientComet(inst)
	if inst:IsA("BasePart") then
		inst.Anchored = true
		inst.CanCollide = false
		inst.CanTouch = false
		inst.CanQuery = false
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
			end
		end
	end
end

local function buildScaleCache(inst)
	local parts = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[#parts + 1] = d
		end
	end
	if inst:IsA("BasePart") then
		parts[#parts + 1] = inst
	end

	local cache = {}
	for _, p in ipairs(parts) do
		if cache[p] == nil then
			local mesh = p:FindFirstChildOfClass("SpecialMesh")
			cache[p] = {
				size = p.Size,
				mesh = mesh,
				meshScale = mesh and mesh.Scale or nil,
			}
		end
	end

	return cache
end

local function applyScale(cache, s)
	for part, info in pairs(cache) do
		if part and part.Parent then
			part.Size = info.size * s
			if info.mesh and info.mesh.Parent then
				info.mesh.Scale = info.meshScale * s
			end
		end
	end
end

local function setTransparency(inst, transparency)
	if inst:IsA("BasePart") then
		inst.Transparency = transparency
	elseif inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Transparency = transparency
			end
		end
	end
end

local function createSparkles(parent, duration)
	local attachment = Instance.new("Attachment")
	attachment.Parent = getRoot(parent)

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Parent = attachment
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 220, 100), Color3.fromRGB(255, 255, 255))
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(1, 0)
	})
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1)
	})
	sparkles.Lifetime = NumberRange.new(0.4, 0.7)
	sparkles.Rate = 40
	sparkles.Speed = NumberRange.new(4, 7)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.EmissionDirection = Enum.NormalId.Top
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0

	task.delay(duration, function()
		sparkles.Enabled = false
		task.wait(1)
		attachment:Destroy()
	end)

	return sparkles
end

local function createTrail(parent)
	local root = getRoot(parent)
	if not root then
		return
	end

	local att0 = Instance.new("Attachment")
	local att1 = Instance.new("Attachment")
	att0.Parent = root
	att1.Parent = root

	local trail = Instance.new("Trail")
	trail.Parent = root
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1)
	})
	trail.Lifetime = 0.6
	trail.MinLength = 0
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0)
	})

	return trail
end

local function animateCollect(cometId)
	local head = getHead()
	if not head then
		CometCollectDone:FireServer(cometId)
		return
	end

	local serverComet = findServerComet(cometId)
	local startCF
	if serverComet then
		startCF = getPivot(serverComet)
	else
		startCF = CFrame.new(head.Position + Vector3.new(0, 8, 0) + head.CFrame.LookVector * -6)
	end

	local clientComet
	if serverComet then
		local ok, cloned = pcall(function()
			return serverComet:Clone()
		end)
		if ok and cloned then
			clientComet = cloned
		end
	end

	if not clientComet then
		CometCollectDone:FireServer(cometId)
		return
	end

	clientComet.Parent = clientFolder
	clientComet.Transparency = 0

	stripSounds(clientComet)
	prepClientComet(clientComet)

	local cache = buildScaleCache(clientComet)
	setPivot(clientComet, startCF)
	applyScale(cache, 1)

	local sparkles = createSparkles(clientComet, CFG.FlyDuration + 0.5)
	local trail = createTrail(clientComet)

	local baseRot = CFrame.fromEulerAnglesXYZ(getPivot(clientComet):ToEulerAnglesXYZ())
	local flyStartPos = startCF.Position

	local center = head.Position
	local initialOffset = flyStartPos - center
	local initialRadius = initialOffset.Magnitude
	if initialRadius < 4 then
		initialRadius = 4
	end

	local startDistToHead = (flyStartPos - head.Position).Magnitude
	if startDistToHead < 4 then
		startDistToHead = 4
	end

	local baseAngle = math.atan2(initialOffset.Z, initialOffset.X)
	local orbitDir = math.random(0, 1) == 0 and -1 or 1
	local orbitSpeed = rand(CFG.OrbitSpeed[1], CFG.OrbitSpeed[2]) * orbitDir

	local p1BaseOffset = Vector3.new(math.cos(baseAngle), 0, math.sin(baseAngle)) * (initialRadius * 0.9)
	local p2BaseOffset = Vector3.new(math.cos(baseAngle + math.pi/2), 0, math.sin(baseAngle + math.pi/2)) * (initialRadius * 0.6)

	local flyTime = CFG.FlyDuration
	local flyStartTime = os.clock()

	local flyConn
	flyConn = RunService.RenderStepped:Connect(function()
		if not clientComet or not clientComet.Parent then
			if flyConn then
				flyConn:Disconnect()
			end
			return
		end

		local headNow = getHead()
		if not headNow then
			setTransparency(clientComet, 1)
			flyConn:Disconnect()
			clientComet:Destroy()
			CometCollectDone:FireServer(cometId)
			return
		end

		local headPos = headNow.Position
		center = headPos

		local elapsed = os.clock() - flyStartTime
		local t = clamp01(elapsed / flyTime)
		local a = easeOutCubic(t)

		local angle = baseAngle + orbitSpeed * elapsed
		local cosA = math.cos(angle)
		local sinA = math.sin(angle)

		local function rotateOffset(off)
			return Vector3.new(
				off.X * cosA - off.Z * sinA,
				off.Y,
				off.X * sinA + off.Z * cosA
			)
		end

		local radiusScale = 1 - t * 0.7
		if radiusScale < 0.2 then
			radiusScale = 0.2
		end

		local heightKick = math.sin(t * math.pi) * CFG.HeightKickMult
		local p1 = center + rotateOffset(p1BaseOffset) * radiusScale + Vector3.new(0, 2 + heightKick, 0)
		local p2 = center + rotateOffset(p2BaseOffset) * radiusScale + Vector3.new(0, 4 + heightKick, 0)
		local p3 = headPos + Vector3.new(0, 0.5, 0)

		local pos = bezier3(a, flyStartPos, p1, p2, p3)

		local dist = (pos - headPos).Magnitude
		local distAlpha = clamp01(dist / startDistToHead)
		local scaleFactor = CFG.ShrinkTo + (1 - CFG.ShrinkTo) * distAlpha

		applyScale(cache, scaleFactor)

		local spinFast = elapsed * CFG.SpinSpeed
		local tilt = math.sin(elapsed * 6) * 0.35
		local rot = baseRot * CFrame.Angles(tilt, spinFast, 0)
		setPivot(clientComet, CFrame.new(pos) * rot)

		if sparkles then
			sparkles.Rate = math.max(5, 40 * distAlpha)
		end

		if t > 0.85 then
			local fade = (t - 0.85) / 0.15
			setTransparency(clientComet, clamp01(fade))
		end

		if dist <= CFG.HitDistance or t >= 1 then
			flyConn:Disconnect()
			if clientComet and clientComet.Parent then
				clientComet:Destroy()
			end
			CometCollectDone:FireServer(cometId)
			script.pop:Play()
		end
	end)

	Debris:AddItem(clientComet, 3)
end

CometCollectFX.OnClientEvent:Connect(function(cometId)
	if type(cometId) ~= "string" then
		return
	end
	task.spawn(function()
		animateCollect(cometId)
	end)
end)
