local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local CurrentEvent = workspace:WaitForChild("CurrentEvent")
local Map = workspace:WaitForChild("Map")
local SpawnPartsFolder = Map:WaitForChild("SpawnPart")

local LuckyTemplate = ReplicatedStorage:WaitForChild("LuckyBlock")
LuckyTemplate.Archivable = true

local PopUpModule = require(ReplicatedStorage.Modules:WaitForChild("PopUpModule"))

local function getOrMakeRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local LuckyBlockHit = getOrMakeRemote("LuckyBlockHit")

local FXFolder = workspace:FindFirstChild("EventFX_LuckyBlocks")
if not FXFolder then
	FXFolder = Instance.new("Folder")
	FXFolder.Name = "EventFX_LuckyBlocks"
	FXFolder.Parent = workspace
end

local rng = Random.new()

local INTERVAL_MIN = 2
local INTERVAL_MAX = 4
local PER_PART_MIN = 1
local PER_PART_MAX = 3
local MAX_PER_PART = 7

local running = false
local runId = 0

local partCount = {}
local blockById = {}
local hitDebounce = {}

local DataManager
pcall(function()
	DataManager = require(script.Parent.Parent.Data.DataManager)
end)

local function addValuePath(plr, path, amount)
	amount = tonumber(amount) or 0
	if amount == 0 then return end

	if DataManager and DataManager.AddValue then
		pcall(function()
			DataManager:AddValue(plr, path, amount)
		end)
		return
	end

	pcall(function()
		local cur = plr
		for seg in string.gmatch(path, "[^%.]+") do
			cur = cur:FindFirstChild(seg)
			if not cur then return end
		end
		if cur and cur:IsA("ValueBase") then
			cur.Value += amount
		end
	end)
end

local POPUP_COLOR = Color3.new(1, 0.972549, 0.192157)
local POPUP_STROKE = Color3.new(0.101961, 0.101961, 0.101961)
local addbrairntos = require(script.Parent.Parent.Modules.AddBrainrot)

local REWARDS = {
	["Nothing"] = {
		chance = 40, -- NAJWIĘKSZA SZANSA
		amount = 0,
		Give = function(plr, amount) end,
		Popup = "LuckyBlock didn't give anything 😭",
	},

	["Money"] = {
		chance = 27, -- dość częste
		amount = math.random(2500, 5000),
		Give = function(plr, amount)
			DataManager:AddValue(plr, "leaderstats.Money", amount)
		end,
		Popup = "You got {reward} +{amount}!",
	},

	["MoneyBoost"] = {
		chance = 8, -- rzadziej
		amount = 2*60,
		Give = function(plr, amount)
			DataManager:AddValue(plr, "Potions.x2MoneyTime", amount)
		end,
		Popup = "You got 2 Minutes x2 Money Boost!",
	},

	["SpeedBoost"] = {
		chance = 7, -- rzadziej
		amount = 2*60,
		Give = function(plr, amount)
			DataManager:AddValue(plr, "Potions.x15WalkSpeedTime", amount)
		end,
		Popup = "You got 2 Minutes x1.5 Speed Boost!",
	},

	-- RARE BRAINROTS
	["Garamararam"] = {
		chance = 3,
		Give = function(plr)
			addbrairntos:AddBrainrot(plr, "Garamararam", 1)
		end,
		Popup = "You got 1 Garamararam!",
	},

	["Bombombini Gusini"] = {
		chance = 3,
		Give = function(plr)
			addbrairntos:AddBrainrot(plr, "Bombombini Gusini", 1)
		end,
		Popup = "You got 1 Bombombini Gusini!",
	},

	["Pandaccini Bananini"] = {
		chance = 3,
		Give = function(plr)
			addbrairntos:AddBrainrot(plr, "Pandaccini Bananini", 1)
		end,
		Popup = "You got 1 Pandaccini Bananini!",
	},

	["Girafa Celestre"] = {
		chance = 3,
		Give = function(plr)
			addbrairntos:AddBrainrot(plr, "Girafa Celestre", 1)
		end,
		Popup = "You got 1 Girafa Celestre!",
	},

	["Karkerkar Kurkur"] = {
		chance = 3,
		Give = function(plr)
			addbrairntos:AddBrainrot(plr, "Karkerkar Kurkur", 1)
		end,
		Popup = "You got 1 Karkerkar Kurkur!",
	},

	["Pakrahmatmatina"] = {
		chance = 3,
		Give = function(plr)
			addbrairntos:AddBrainrot(plr, "Pakrahmatmatina", 1)
		end,
		Popup = "You got 1 Pakrahmatmatina!",
	},
}


local function pickReward()
	local total = 0
	for _, r in pairs(REWARDS) do
		local w = tonumber(r.chance) or 0
		if w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil, nil
	end

	local roll = rng:NextNumber() * total
	local acc = 0

	for name, r in pairs(REWARDS) do
		local w = tonumber(r.chance) or 0
		if w > 0 then
			acc += w
			if roll <= acc then
				return name, r
			end
		end
	end

	return nil, nil
end

local function norm(s)
	s = tostring(s or "")
	s = s:lower()
	s = s:gsub("%s+", "")
	return s
end

local function isLuckyEvent()
	return norm(CurrentEvent.Value) == "luckyblock"
end

local function stillValid(token)
	return running and token == runId and isLuckyEvent()
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

local function ensurePrimary(model: Model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local p = model:FindFirstChildWhichIsA("BasePart", true)
	if p then
		model.PrimaryPart = p
	end
	return model.PrimaryPart
end

local function anchorModel(model: Model, v: boolean)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = v
			d.CanCollide = true
			d.CanTouch = true
			d.CanQuery = true
		end
	end
end

local function safeScaleTo(model: Model, s: number)
	pcall(function()
		model:ScaleTo(s)
	end)
end

local function randomEvenHealth()
	local v = rng:NextInteger(5, 8)
	if v % 2 == 1 then
		v += 1
	end
	if v > 50 then v = 50 end
	return v
end

local function randomLocalXZ(part: BasePart)
	local sx = part.Size.X * 0.46
	local sz = part.Size.Z * 0.46
	return rng:NextNumber(-sx, sx), rng:NextNumber(-sz, sz)
end

local function topSurfacePos(part: BasePart, lx: number, lz: number)
	return part.CFrame:PointToWorldSpace(Vector3.new(lx, part.Size.Y * 0.5, lz))
end

local function destroyFX(pos: Vector3)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.25
	ring.Size = Vector3.new(1, 0.22, 1)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0))
	ring.Parent = FXFolder

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(1, 0.1, 1)
	mesh.Parent = ring

	TweenService:Create(mesh, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = Vector3.new(30, 0.1, 30) }):Play()
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()

	task.delay(0.7, function()
		if ring then ring:Destroy() end
	end)
end

local function destroyBlockById(id: string)
	local data = blockById[id]
	if not data then return end

	local inst = data.Instance
	local platform = data.Platform

	if inst and inst.Parent then
		inst:Destroy()
	end

	blockById[id] = nil

	if platform and platform.Parent then
		partCount[platform] = math.max(0, (partCount[platform] or 1) - 1)
	end
end

local function sendRewardPopup(plr: Player, rewardName: string, rewardDef: table)
	if not rewardDef then return end

	local amount = tonumber(rewardDef.amount) or 0
	local msg = nil

	if typeof(rewardDef.Popup) == "function" then
		msg = rewardDef.Popup(plr, rewardName, amount)
	elseif type(rewardDef.Popup) == "string" then
		msg = rewardDef.Popup
		msg = msg:gsub("{reward}", tostring(rewardName))
		msg = msg:gsub("{amount}", tostring(amount))
	end

	if msg and msg ~= "" then
		PopUpModule:Server_SendPopUp(plr, msg, rewardDef.Color or POPUP_COLOR, rewardDef.Stroke or POPUP_STROKE, rewardDef.PopupDuration or 3, false)
	end
end

local function giveReward(plr: Player)
	local rewardName, rewardDef = pickReward()
	if not rewardDef then return end

	local amount = tonumber(rewardDef.amount) or 0

	if rewardDef.Give then
		pcall(function()
			rewardDef.Give(plr, amount)
		end)
	end

	sendRewardPopup(plr, rewardName, rewardDef)
end

local function spawnOne(platform: BasePart, token: number)
	if not stillValid(token) then return end

	local c = partCount[platform] or 0
	if c >= MAX_PER_PART then return end
	partCount[platform] = c + 1

	local inst: Model?
	local ok = pcall(function()
		inst = LuckyTemplate:Clone()
	end)
	if not ok or not inst or not inst:IsA("Model") then
		partCount[platform] = math.max(0, (partCount[platform] or 1) - 1)
		return
	end

	local root = ensurePrimary(inst)
	if not root then
		partCount[platform] = math.max(0, (partCount[platform] or 1) - 1)
		inst:Destroy()
		return
	end

	inst.Parent = FXFolder
	anchorModel(inst, true)

	local lx, lz = randomLocalXZ(platform)
	local surface = topSurfacePos(platform, lx, lz)
	local up = platform.CFrame.UpVector

	local _, boxSize = inst:GetBoundingBox()
	local halfY = (boxSize.Y * 0.5)
	local center = surface + up * (halfY + 0.05)

	local yaw = rng:NextNumber(0, math.pi * 2)
	local baseCF = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	inst:PivotTo(baseCF)

	local maxHp = randomEvenHealth()
	local id = "LB_" .. tostring(token) .. "_" .. tostring(math.floor(os.clock() * 1000)) .. "_" .. tostring(rng:NextInteger(1000, 9999))

	inst:SetAttribute("LuckyBlockId", id)
	inst:SetAttribute("Health", maxHp)
	inst:SetAttribute("MaxHealth", maxHp)

	blockById[id] = {
		Instance = inst,
		Platform = platform,
		Token = token,
	}

	local scaleVal = Instance.new("NumberValue")
	scaleVal.Value = 0.05
	scaleVal.Parent = inst

	local rotVal = Instance.new("NumberValue")
	rotVal.Value = 0
	rotVal.Parent = inst

	local connA, connB
	connA = scaleVal.Changed:Connect(function(v)
		if inst and inst.Parent then
			safeScaleTo(inst, tonumber(v) or 1)
		end
	end)

	connB = rotVal.Changed:Connect(function(v)
		if inst and inst.Parent then
			inst:PivotTo(baseCF * CFrame.Angles(0, tonumber(v) or 0, 0))
		end
	end)

	safeScaleTo(inst, 0.05)
	TweenService:Create(scaleVal, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
	TweenService:Create(rotVal, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = math.pi * 2 }):Play()

	task.delay(0.55, function()
		if connA then connA:Disconnect() end
		if connB then connB:Disconnect() end
		if scaleVal.Parent then scaleVal:Destroy() end
		if rotVal.Parent then rotVal:Destroy() end
		if inst and inst.Parent then
			safeScaleTo(inst, 1)
			inst:PivotTo(baseCF)
		end
	end)

	task.spawn(function()
		while inst and inst.Parent do
			if not stillValid(token) then
				destroyBlockById(id)
				return
			end
			task.wait(0.25)
		end
	end)
end

local function spawnWave(token: number)
	local platforms = getSpawnPlatforms()
	local perPart = rng:NextInteger(PER_PART_MIN, PER_PART_MAX)

	for _, platform in ipairs(platforms) do
		if not stillValid(token) then return end

		local c = partCount[platform] or 0
		local free = MAX_PER_PART - c
		if free > 0 then
			local count = math.min(perPart, free)
			for _ = 1, count do
				if not stillValid(token) then return end
				spawnOne(platform, token)
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
	blockById = {}
	hitDebounce = {}
end

LuckyBlockHit.OnServerEvent:Connect(function(plr: Player, blockId: string)
	if type(blockId) ~= "string" then return end
	local data = blockById[blockId]
	if not data then return end
	if not data.Instance or not data.Instance.Parent then return end

	local inst = data.Instance
	local root = ensurePrimary(inst)
	if not root then return end

	local now = os.clock()
	hitDebounce[plr.UserId] = hitDebounce[plr.UserId] or {}
	local last = hitDebounce[plr.UserId][blockId]
	if last and (now - last) < 0.08 then
		return
	end
	hitDebounce[plr.UserId][blockId] = now

	local char = plr.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - root.Position).Magnitude > 18 then
		return
	end

	local hp = tonumber(inst:GetAttribute("Health")) or 0
	if hp <= 0 then return end

	hp -= 1
	inst:SetAttribute("Health", hp)

	if hp <= 0 then
		local pos = root.Position
		print(plr.Name .. " destroyed a Lucky Block")
		giveReward(plr)
		destroyFX(pos)
		destroyBlockById(blockId)
	end
end)

local function startLucky()
	if running then return end
	running = true
	runId += 1
	local token = runId

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
	end)
end

local function stopLucky()
	if not running then return end
	running = false
	runId += 1
	clearAll()
end

local function sync()
	if isLuckyEvent() then
		startLucky()
	else
		stopLucky()
	end
end

CurrentEvent:GetPropertyChangedSignal("Value"):Connect(sync)
sync()
