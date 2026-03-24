local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DEBUG = true
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local function log(...)
	if DEBUG then
		print("[COMET]", ...)
	end
end
local function warnlog(...)
	warn("[COMET]", ...)
end

local CurrentEvent = workspace:WaitForChild("CurrentEvent")
local CurrentEventTime = workspace:WaitForChild("CurrentEventTime")

local refs = MapResolver.WaitForRefs(
	{ "MapRoot", "SpawnFolder" },
	nil,
	{
		warn = true,
		context = "CometEvent",
	}
)
local Map = refs.MapRoot
local SpawnPartsFolder = refs.SpawnFolder

local CometTemplate = ReplicatedStorage:WaitForChild("Comet")
CometTemplate.Archivable = true

local function getOrMakeRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local CometCollectFX = getOrMakeRemote("CometCollectFX")
local CometCollectDone = getOrMakeRemote("CometCollectDone")

local FXFolder = workspace:FindFirstChild("EventFX_Comets")
if not FXFolder then
	FXFolder = Instance.new("Folder")
	FXFolder.Name = "EventFX_Comets"
	FXFolder.Parent = workspace
end

local rng = Random.new()

local INTERVAL_MIN = 2
local INTERVAL_MAX = 4
local COMETS_PER_PART_MIN = 5
local COMETS_PER_PART_MAX = 12

local MAX_PER_PART = 20
local HEIGHT_MIN = 380
local HEIGHT_MAX = 520

local COMET_GROUP = "Comets"
local BRAINROT_GROUP = "Brainrots"

pcall(function() PhysicsService:CreateCollisionGroup(COMET_GROUP) end)
pcall(function() PhysicsService:CreateCollisionGroup(BRAINROT_GROUP) end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(COMET_GROUP, BRAINROT_GROUP, false)
end)

local running = false
local runId = 0
local prevClockTime = Lighting.ClockTime

local partCount = {}
local cometById = {}

local function norm(s)
	s = tostring(s or "")
	s = s:lower()
	s = s:gsub("%s+", "")
	return s
end

local function isCometEvent()
	return norm(CurrentEvent.Value) == "comet"
end

local function stillValid(token)
	return running and token == runId and isCometEvent()
end

local function formatTime(seconds)
	seconds = tonumber(seconds) or 0
	if seconds < 0 then seconds = 0 end
	seconds = math.floor(seconds + 0.5)

	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60

	if h > 0 then
		return string.format("%02d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

local function findCometTimeLabel()
	local eventsFolder = workspace:FindFirstChild("Events")
	if not eventsFolder then return nil end

	local cometFolder = eventsFolder:FindFirstChild("Comet")
	if not cometFolder then return nil end

	local likeCounter = cometFolder:FindFirstChild(`Walls`):FindFirstChild("LikeCounter")
	if not likeCounter then return nil end

	local timers = likeCounter:FindFirstChild("Timers")
	if not timers then return nil end

	local gui = timers:FindFirstChildOfClass("SurfaceGui") or timers:FindFirstChild("SurfaceGui")
	if not gui then return nil end

	local lbl = gui:FindFirstChild("Time")
	if lbl and lbl:IsA("TextLabel") then
		return lbl
	end
	return nil
end

local function startCometTimerUI(token)
	task.spawn(function()
		local label = findCometTimeLabel()
		while stillValid(token) do
			if not label or not label.Parent then
				label = findCometTimeLabel()
			end
			if label then
				label.Text = formatTime(CurrentEventTime.Value)
			end
			task.wait(0.15)
		end
		local label2 = findCometTimeLabel()
		if label2 then
			label2.Text = "00:00"
		end
	end)
end

local function getSpawnPlatforms()
	local t = {}
	for _, v in ipairs(SpawnPartsFolder:GetChildren()) do
		if v:IsA("BasePart") then
			t[#t + 1] = v
		end
	end
	return t
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

local function forEachPart(inst, fn)
	if inst:IsA("BasePart") then
		fn(inst)
		return
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

local function setCollisionGroup(inst, groupName)
	forEachPart(inst, function(p)
		pcall(function()
			PhysicsService:SetPartCollisionGroup(p, groupName)
		end)
	end)
end

local function setCollide(inst, v)
	forEachPart(inst, function(p)
		p.CanCollide = false
		p.CanTouch = v
		p.CanQuery = false
	end)
end

local function setAnchored(inst, v)
	forEachPart(inst, function(p)
		p.Anchored = v
	end)
end

local function setVisible(inst, alpha)
	alpha = alpha or 0
	forEachPart(inst, function(p)
		p.Transparency = alpha
	end)
end

local function randomLocalXZ(part: BasePart)
	local sx = part.Size.X * 0.46
	local sz = part.Size.Z * 0.46
	return rng:NextNumber(-sx, sx), rng:NextNumber(-sz, sz)
end

local function targetPosOnTop(part: BasePart, lx: number, lz: number)
	return part.CFrame:PointToWorldSpace(Vector3.new(lx, part.Size.Y * 0.5 + 1.25, lz))
end

local function shockwave(pos: Vector3)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.22
	ring.Size = Vector3.new(1, 0.25, 1)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0))
	ring.Parent = FXFolder

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(1, 0.08, 1)
	mesh.Parent = ring

	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.6
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(2, 2, 2)
	flash.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
	flash.Parent = FXFolder

	TweenService:Create(mesh, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = Vector3.new(95, 0.08, 95) }):Play()
	TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
	TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(55, 55, 55), Transparency = 1 }):Play()

	task.delay(0.8, function()
		if ring then ring:Destroy() end
		if flash then flash:Destroy() end
	end)
end

local function addFallFX(root: BasePart)
	local att = Instance.new("Attachment")
	att.Parent = root

	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 140
	pe.Lifetime = NumberRange.new(0.22, 0.55)
	pe.Speed = NumberRange.new(16, 32)
	pe.SpreadAngle = Vector2.new(26, 26)
	pe.Drag = 6
	pe.Brightness = 2.5
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.05),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.07),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Parent = att

	local light = Instance.new("PointLight")
	light.Brightness = 1.2
	light.Range = 10
	light.Shadows = false
	light.Parent = root

	task.delay(2, function()
		if light and light.Parent then
			TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
		end
	end)

	return pe
end

local function playFlySound(inst)
	local fly = inst:FindFirstChild("Fly", true)
	if fly and fly:IsA("Sound") then
		fly.Looped = true
		pcall(function() fly:Play() end)
		return fly
	end
	return nil
end

local function playBoomSound(inst)
	local boom = inst:FindFirstChild("Boom", true)
	if boom and boom:IsA("Sound") then
		boom.Looped = false
		pcall(function() boom:Play() end)
	end
end

local function setCF(inst, cf)
	if inst:IsA("Model") then
		inst:PivotTo(cf)
	else
		local r = getRoot(inst)
		if r then
			r.CFrame = cf
		end
	end
end

local function tweenCF(inst, cf0, cf1, t)
	if inst:IsA("Model") then
		local v = Instance.new("CFrameValue")
		v.Value = cf0
		local conn
		conn = v:GetPropertyChangedSignal("Value"):Connect(function()
			if inst and inst.Parent then
				inst:PivotTo(v.Value)
			else
				if conn then conn:Disconnect() end
			end
		end)
		inst:PivotTo(cf0)
		local tw = TweenService:Create(v, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = cf1 })
		tw:Play()
		tw.Completed:Wait()
		if conn then conn:Disconnect() end
		v:Destroy()
		return
	end

	local root = getRoot(inst)
	if not root then return end
	root.CFrame = cf0
	local tw = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = cf1 })
	tw:Play()
	tw.Completed:Wait()
end

local function tagBrainrotsCollision()
	for _, platform in ipairs(getSpawnPlatforms()) do
		local brainrotsFolder = platform:FindFirstChild("Brainrots")
		if brainrotsFolder then
			setCollisionGroup(brainrotsFolder, BRAINROT_GROUP)
			brainrotsFolder.DescendantAdded:Connect(function(obj)
				if obj:IsA("BasePart") then
					pcall(function()
						PhysicsService:SetPartCollisionGroup(obj, BRAINROT_GROUP)
					end)
				end
			end)
		end
	end
end

local function destroyCometById(id: string)
	local data = cometById[id]
	if not data then return end

	local inst = data.Instance
	local platform = data.Platform

	if inst and inst.Parent then
		inst:Destroy()
	end

	cometById[id] = nil

	if platform and platform.Parent then
		partCount[platform] = math.max(0, (partCount[platform] or 1) - 1)
	end
end

CometCollectDone.OnServerEvent:Connect(function(plr, cometId)
	if type(cometId) ~= "string" then return end
	local data = cometById[cometId]
	if not data then return end
	if data.CollectedBy ~= plr.UserId then return end
	destroyCometById(cometId)
end)

local function bindCollect(inst, cometId: string)
	local root = getRoot(inst)
	if not root then return end

	local conn
	conn = root.Touched:Connect(function(hit)
		if not hit then return end
		local ch = hit.Parent
		if not ch then return end
		local plr = Players:GetPlayerFromCharacter(ch)
		if not plr then return end

		local data = cometById[cometId]
		if not data then return end
		if data.Collected then return end
		if not data.Landed then return end

		data.Collected = true
		data.CollectedBy = plr.UserId

		setCollide(inst, false)
		setAnchored(inst, true)
		setVisible(inst, 1)

		local dm = require(script.Parent.Parent.Data.DataManager)
		dm:AddValue(plr, "HiddenLeaderstats.Comets", 1)

		CometCollectFX:FireClient(plr, cometId)

		task.delay(2.5, function()
			if cometById[cometId] then
				destroyCometById(cometId)
			end
		end)

		if conn then conn:Disconnect() end
	end)
end

local function spawnCometOnPlatform(platform: BasePart, token: number)
	if not stillValid(token) then return end

	local c = partCount[platform] or 0
	if c >= MAX_PER_PART then return end
	partCount[platform] = c + 1

	local inst
	local ok = pcall(function()
		inst = CometTemplate:Clone()
	end)
	if not ok or not inst then
		partCount[platform] = math.max(0, (partCount[platform] or 1) - 1)
		return
	end

	if not stillValid(token) then
		inst:Destroy()
		partCount[platform] = math.max(0, (partCount[platform] or 1) - 1)
		return
	end

	local cometId = "C_" .. tostring(token) .. "_" .. tostring(math.floor(os.clock() * 1000)) .. "_" .. tostring(rng:NextInteger(1000, 9999))
	inst:SetAttribute("CometId", cometId)

	inst.Parent = FXFolder
	setVisible(inst, 0)
	setCollisionGroup(inst, COMET_GROUP)

	setAnchored(inst, true)
	setCollide(inst, false)

	local root = getRoot(inst)
	if not root then
		partCount[platform] = math.max(0, (partCount[platform] or 1) - 1)
		inst:Destroy()
		return
	end

	local flySound = playFlySound(inst)

	local lx, lz = randomLocalXZ(platform)
	local targetPos = targetPosOnTop(platform, lx, lz)
	local up = platform.CFrame.UpVector
	local height = rng:NextNumber(HEIGHT_MIN, HEIGHT_MAX)
	local spawnPos = targetPos + up * height

	local yaw = rng:NextNumber(0, math.pi * 2)
	local cf0 = CFrame.new(spawnPos) * CFrame.Angles(0, yaw, 0)
	local cf1 = CFrame.new(targetPos) * CFrame.Angles(0, yaw, 0)

	setCF(inst, cf0)

	local pe = addFallFX(root)

	cometById[cometId] = {
		Instance = inst,
		Platform = platform,
		Landed = false,
		Collected = false,
		CollectedBy = nil,
		Token = token,
	}

	task.spawn(function()
		while inst.Parent do
			if not stillValid(token) then
				destroyCometById(cometId)
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)

	task.spawn(function()
		local fallTime = rng:NextNumber(1.35, 2.15)
		tweenCF(inst, cf0, cf1, fallTime)

		if not cometById[cometId] then return end
		if not stillValid(token) then
			destroyCometById(cometId)
			return
		end

		if flySound and flySound.Parent then
			pcall(function() flySound:Stop() end)
		end
		if pe and pe.Parent then
			pe.Rate = 0
		end

		playBoomSound(inst)
		shockwave(targetPos)

		local data = cometById[cometId]
		if data then
			data.Landed = true
		end

		setVisible(inst, 0)
		setAnchored(inst, true)
		setCollide(inst, true)

		bindCollect(inst, cometId)
	end)
end

local function spawnWave(token: number)
	local platforms = getSpawnPlatforms()
	local COMETS_PER_PART = rng:NextInteger(COMETS_PER_PART_MIN, COMETS_PER_PART_MAX)

	log("Wave start | platforms:", #platforms, "| per platform:", COMETS_PER_PART)

	for _, platform in ipairs(platforms) do
		if not stillValid(token) then return end

		local c = partCount[platform] or 0
		local free = MAX_PER_PART - c
		if free > 0 then
			local toSpawn = math.min(COMETS_PER_PART, free)
			for _ = 1, toSpawn do
				if not stillValid(token) then return end
				spawnCometOnPlatform(platform, token)
				task.wait(0.01)
			end
		end
	end
end

local function clearAll()
	for _, obj in ipairs(FXFolder:GetChildren()) do
		pcall(function()
			obj:Destroy()
		end)
	end
	partCount = {}
	cometById = {}
end

local function startComet()
	if running then return end
	running = true
	runId += 1

	local token = runId

	prevClockTime = Lighting.ClockTime
	Lighting.ClockTime = 0

	tagBrainrotsCollision()
	startCometTimerUI(token)

	log("START Comet | platforms:", #getSpawnPlatforms())

	task.spawn(function()
		while stillValid(token) do
			pcall(function()
				spawnWave(token)
			end)

			if not stillValid(token) then break end

			local interval = rng:NextNumber(INTERVAL_MIN, INTERVAL_MAX)
			local t0 = os.clock()
			while stillValid(token) and (os.clock() - t0) < interval do
				task.wait(0.05)
			end
		end
		log("Loop ended")
	end)
end

local function stopComet()
	if not running then return end

	running = false
	runId += 1

	Lighting.ClockTime = prevClockTime
	log("STOP Comet")

	clearAll()

	local label = findCometTimeLabel()
	if label then
		label.Text = "00:00"
	end
end

local function sync()
	log("CurrentEvent =", tostring(CurrentEvent.Value))
	if isCometEvent() then
		startComet()
	else
		stopComet()
	end
end

CurrentEvent:GetPropertyChangedSignal("Value"):Connect(sync)
sync()
