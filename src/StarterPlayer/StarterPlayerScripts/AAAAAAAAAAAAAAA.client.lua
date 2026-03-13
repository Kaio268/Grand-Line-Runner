local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local WavesConfig = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("Configs")
		:WaitForChild("LavaWaves")
)

local BrainrotsConfig = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("Configs")
		:WaitForChild("Brainrots")
)
local HazardRuntime = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("HazardRuntime")
)

local WavesFolder = ReplicatedStorage:WaitForChild("Waves")

local map = workspace:WaitForChild("Map")
local waveFolder = map:WaitForChild("WaveFolder")
local startPart = waveFolder:WaitForChild("Start")
local endPart = waveFolder:WaitForChild("End")

local clientWavesFolder = waveFolder:FindFirstChild("ClientWaves")
if not clientWavesFolder then
	clientWavesFolder = Instance.new("Folder")
	clientWavesFolder.Name = "ClientWaves"
	clientWavesFolder.Parent = waveFolder
end

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local KillMeEvent = Remotes and Remotes:FindFirstChild("KillMe")
local ProgressBarSync = Remotes and Remotes:FindFirstChild("ProgressBarSync")

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("HUD")
local progressBar = hud:WaitForChild("ProgressBar")

local pfpTemplate = progressBar:WaitForChild("PFP")
pfpTemplate.Visible = false

local disasterTemplate = progressBar:WaitForChild("Disaster")
disasterTemplate.Visible = false

local pfpClones = {}
local waveIndicators = {}

local function getImageNode(obj)
	if not obj then return nil end
	if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		return obj
	end
	return obj:FindFirstChildWhichIsA("ImageLabel", true) or obj:FindFirstChildWhichIsA("ImageButton", true)
end

local function setGuiVisible(obj, v)
	if obj and obj:IsA("GuiObject") then
		obj.Visible = v
	end
end

local function setPfpImage(guiObj, userId)
	local img = getImageNode(guiObj)
	if not img then
		img = guiObj:FindFirstChild("Image", true)
		img = getImageNode(img)
	end
	if img then
		img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"
	end
end

local function setDisasterImage(guiObj, waveName)
	local img = getImageNode(guiObj)
	if not img then
		img = guiObj:FindFirstChild("Image", true)
		img = getImageNode(img)
	end
	if img then
		local cfg = WavesConfig[waveName]
		if cfg and cfg.IMAGE then
			img.Image = tostring(cfg.IMAGE)
		end
	end
end

local function applyBrainrotToPfp(pfpGui, plr)
	local container = pfpGui:FindFirstChild("Brainrot", true)
	if not container then
		return
	end

	local img = getImageNode(container)
	if not img then
		return
	end

	local render = plr:GetAttribute("CarriedBrainrotImage")
	if render and tostring(render) ~= "" then
		img.Image = tostring(render)
		setGuiVisible(container, true)
		setGuiVisible(img, true)
		return
	end

	local id = plr:GetAttribute("CarriedBrainrot")
	if id and tostring(id) ~= "" then
		local info = BrainrotsConfig[tostring(id)]
		local fallback = info and info.Render
		if fallback and tostring(fallback) ~= "" then
			img.Image = tostring(fallback)
			setGuiVisible(container, true)
			setGuiVisible(img, true)
			return
		end
	end

	setGuiVisible(img, false)
	setGuiVisible(container, false)
end

local function applySkullToPfp(pfpGui, plr)
	local container = pfpGui:FindFirstChild("Skull", true)
	if not container then
		return
	end

	local img = getImageNode(container) or container
	local dead = (plr:GetAttribute("IsDead") == true)

	setGuiVisible(container, dead)
	setGuiVisible(img, dead)
end

local function ensurePfp(userId)
	if pfpClones[userId] and pfpClones[userId].Parent then
		return pfpClones[userId]
	end

	local c = pfpTemplate:Clone()
	c.Name = "PFP_" .. tostring(userId)
	c.Visible = true
	c.Parent = pfpTemplate.Parent

	setPfpImage(c, userId)

	local plr = Players:GetPlayerByUserId(userId)
	if plr then
		applyBrainrotToPfp(c, plr)
		applySkullToPfp(c, plr)
	else
		local b = c:FindFirstChild("Brainrot", true)
		if b then setGuiVisible(b, false) end
		local s = c:FindFirstChild("Skull", true)
		if s then setGuiVisible(s, false) end
	end

	pfpClones[userId] = c
	return c
end

local function removeUnusedPfps(validMap)
	for userId, gui in pairs(pfpClones) do
		if not validMap[userId] then
			if gui and gui.Parent then
				gui:Destroy()
			end
			pfpClones[userId] = nil
		end
	end
end

local function getAlphaOnLine(worldPos)
	local a = endPart.Position
	local b = startPart.Position
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then
		return 0
	end
	local t = (worldPos - a):Dot(ab) / len2
	return math.clamp(t, 0, 1)
end

local function alphaToXScale(alpha)
	return 0.025 + alpha * 0.95
end

local function updatePfpPositions()
	for _, plr in ipairs(Players:GetPlayers()) do
		local gui = pfpClones[plr.UserId]
		if gui and gui.Parent then
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local a = getAlphaOnLine(hrp.Position)
				gui.Position = UDim2.new(alphaToXScale(a), 0, 0.823, 0)
			end
		end
	end
end

local function updatePfpBrainrotAndSkull()
	for _, plr in ipairs(Players:GetPlayers()) do
		local gui = pfpClones[plr.UserId]
		if gui and gui.Parent then
			applyBrainrotToPfp(gui, plr)
			applySkullToPfp(gui, plr)
		end
	end
end

local function getWaveWorldPos(obj)
	if obj:IsA("Model") then
		return obj:GetPivot().Position
	elseif obj:IsA("BasePart") then
		return obj.Position
	end
	return nil
end

local disasterYScale = disasterTemplate.Position.Y.Scale
local disasterYOffset = disasterTemplate.Position.Y.Offset

local function ensureWaveIndicator(waveObj)
	if waveIndicators[waveObj] and waveIndicators[waveObj].Parent then
		return waveIndicators[waveObj]
	end
	local c = disasterTemplate:Clone()
	c.Name = "Disaster_" .. waveObj.Name
	c.Visible = true
	c.Parent = disasterTemplate.Parent
	setDisasterImage(c, waveObj.Name)
	waveIndicators[waveObj] = c
	return c
end

local function removeWaveIndicator(waveObj)
	local gui = waveIndicators[waveObj]
	if gui and gui.Parent then
		gui:Destroy()
	end
	waveIndicators[waveObj] = nil
end

clientWavesFolder.ChildAdded:Connect(function(child)
	ensureWaveIndicator(child)
end)

clientWavesFolder.ChildRemoved:Connect(function(child)
	removeWaveIndicator(child)
end)

local function updateWaveIndicators()
	for waveObj, gui in pairs(waveIndicators) do
		if not waveObj or not waveObj.Parent or not gui or not gui.Parent then
			if gui and gui.Parent then
				gui:Destroy()
			end
			waveIndicators[waveObj] = nil
		else
			local pos = getWaveWorldPos(waveObj)
			if pos then
				local a = getAlphaOnLine(pos)
				gui.Position = UDim2.new(alphaToXScale(a), 0, disasterYScale, disasterYOffset)
			end
		end
	end
end

if ProgressBarSync and ProgressBarSync:IsA("RemoteEvent") then
	ProgressBarSync.OnClientEvent:Connect(function(_, payload)
		local valid = {}
		for _, info in ipairs(payload) do
			local uid = info.UserId
			valid[uid] = true
			ensurePfp(uid)
		end
		removeUnusedPfps(valid)
	end)
	ProgressBarSync:FireServer("Request")
else
	for _, plr in ipairs(Players:GetPlayers()) do
		ensurePfp(plr.UserId)
	end
end

local function getTemplate(name)
	local t = WavesFolder:FindFirstChild(name)
	if not t then return nil end
	if t:IsA("Model") or t:IsA("BasePart") then
		return t
	end
	return nil
end

local entries = {}
for waveName, info in pairs(WavesConfig) do
	local template = getTemplate(waveName)
	if template then
		table.insert(entries, {
			Name = waveName,
			Info = info,
			Template = template,
		})
	end
end

local rng = Random.new()

local function getStringAttribute(source, attributeName, fallback)
	if not source then
		return fallback
	end

	local value = source:GetAttribute(attributeName)
	if typeof(value) == "string" and value ~= "" then
		return string.lower(value)
	end

	return fallback
end

local function getBooleanAttribute(source, attributeName, fallback)
	if not source then
		return fallback
	end

	local value = source:GetAttribute(attributeName)
	if value == nil then
		return fallback
	end

	if typeof(value) == "boolean" then
		return value
	end

	if typeof(value) == "number" then
		return value ~= 0
	end

	if typeof(value) == "string" then
		local lowered = string.lower(value)
		return lowered == "true" or lowered == "1" or lowered == "yes"
	end

	return fallback
end

local function applyHazardMetadata(clone, template)
	clone:SetAttribute("HazardClass", getStringAttribute(template, "HazardClass", "major"))
	clone:SetAttribute("HazardType", getStringAttribute(template, "HazardType", "wave"))
	clone:SetAttribute("CanFreeze", getBooleanAttribute(template, "CanFreeze", true))
	clone:SetAttribute("FreezeBehavior", getStringAttribute(template, "FreezeBehavior", "pause"))
end

local function forEachHazardPart(root, callback)
	if root:IsA("BasePart") then
		callback(root)
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

local function createFreezeController(hazardRoot, tween)
	local controller = {
		HazardRoot = hazardRoot,
		Tween = tween,
		FrozenUntil = 0,
		TouchStates = {},
		Destroyed = false,
		FreezeToken = 0,
	}

	function controller:SetTouchEnabled(isEnabled)
		forEachHazardPart(self.HazardRoot, function(part)
			if isEnabled then
				local originalState = self.TouchStates[part]
				if originalState ~= nil then
					part.CanTouch = originalState
					self.TouchStates[part] = nil
				end
			else
				if self.TouchStates[part] == nil then
					self.TouchStates[part] = part.CanTouch
				end
				part.CanTouch = false
			end
		end)
	end

	function controller:SetFrozen(isFrozen)
		if isFrozen then
			if self.Tween and self.Tween.PlaybackState == Enum.PlaybackState.Playing then
				pcall(function()
					self.Tween:Pause()
				end)
			end
			self:SetTouchEnabled(false)
			return
		end

		self:SetTouchEnabled(true)

		if self.Tween and self.HazardRoot.Parent and self.Tween.PlaybackState == Enum.PlaybackState.Paused then
			pcall(function()
				self.Tween:Play()
			end)
		end
	end

	function controller:Freeze(duration)
		if self.Destroyed or not self.HazardRoot.Parent then
			return false
		end

		local freezeDuration = math.max(0, tonumber(duration) or 0)
		if freezeDuration <= 0 then
			return false
		end

		self.FrozenUntil = math.max(self.FrozenUntil, os.clock() + freezeDuration)
		self.FreezeToken += 1
		local token = self.FreezeToken

		self:SetFrozen(true)

		task.spawn(function()
			while not self.Destroyed and self.HazardRoot.Parent and os.clock() < self.FrozenUntil do
				task.wait(0.05)
			end

			if self.Destroyed or self.FreezeToken ~= token then
				return
			end

			if self.HazardRoot.Parent then
				self:SetFrozen(false)
			end
		end)

		return true
	end

	function controller:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		self:SetTouchEnabled(true)
		HazardRuntime.Unregister(self.HazardRoot)
	end

	HazardRuntime.Register(hazardRoot, controller)
	hazardRoot.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			controller:Destroy()
		end
	end)

	return controller
end

local function chooseByChance(list)
	local total = 0
	for _, e in ipairs(list) do
		local ch = tonumber(e.Info.Chance) or 0
		if ch > 0 then
			total += ch
		end
	end
	if total <= 0 then
		return list[rng:NextInteger(1, #list)]
	end
	local pick = rng:NextNumber(0, total)
	local acc = 0
	for _, e in ipairs(list) do
		local ch = tonumber(e.Info.Chance) or 0
		if ch > 0 then
			acc += ch
			if pick <= acc then
				return e
			end
		end
	end
	return list[#list]
end

local function anchor(obj)
	if obj:IsA("BasePart") then
		obj.Anchored = true
		obj.AssemblyLinearVelocity = Vector3.zero
		obj.AssemblyAngularVelocity = Vector3.zero
		return
	end
	for _, d in ipairs(obj:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function getPivot(obj)
	if obj:IsA("Model") then
		return obj:GetPivot()
	end
	return obj.CFrame
end

local function setPivot(obj, cf)
	if obj:IsA("Model") then
		obj:PivotTo(cf)
	else
		obj.CFrame = cf
	end
end

local function getBox(obj)
	if obj:IsA("Model") then
		return obj:GetBoundingBox()
	end
	return obj.CFrame, obj.Size
end

local function getExtraRot(info)
	local rx = tonumber(info.RotX) or 0
	local ry = tonumber(info.RotY) or 0
	local rz = tonumber(info.RotZ) or 0
	return CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
end

local function computePivotOnTop(obj, refPart, extraRot)
	local boxCF, boxSize = getBox(obj)
	local offset = getPivot(obj):ToObjectSpace(boxCF)

	local up = refPart.CFrame.UpVector
	local surface = refPart.Position + up * (refPart.Size.Y / 2)
	local rot = refPart.CFrame - refPart.Position

	local desiredBox =
		CFrame.new(surface + up * (boxSize.Y / 2))
		* rot
		* CFrame.Angles(0, math.rad(-90), 0)
		* extraRot

	return desiredBox * offset:Inverse()
end

local function computeModelPivotOnTopUsingPart(model, part, refPart, extraRot)
	local modelPivot = model:GetPivot()
	local partCF = part.CFrame
	local offset = modelPivot:ToObjectSpace(partCF)

	local up = refPart.CFrame.UpVector
	local surface = refPart.Position + up * (refPart.Size.Y / 2)
	local rot = refPart.CFrame - refPart.Position

	local desiredPartCF =
		CFrame.new(surface + up * (part.Size.Y / 2))
		* rot
		* CFrame.Angles(0, math.rad(-90), 0)
		* extraRot

	return desiredPartCF * offset:Inverse()
end

local function killLocalPlayer()
	local char = LocalPlayer.Character
	if not char then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		if KillMeEvent and KillMeEvent:IsA("RemoteEvent") then
			KillMeEvent:FireServer()
		else
			hum.Health = 0
		end
	end
end

local function isLocalHRP(hit)
	local char = LocalPlayer.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return (hit ~= nil and hrp ~= nil and hit == hrp)
end

local function hookKillOnTouchPart(p)
	if not p or not p:IsA("BasePart") then
		return
	end
	p.CanTouch = true
	p.Touched:Connect(function(hit)
		if isLocalHRP(hit) then
			killLocalPlayer()
		end
	end)
end

local function hookKillOnTouch(obj, hitPart)
	if hitPart and hitPart:IsA("BasePart") then
		hookKillOnTouchPart(hitPart)
		return
	end
	if obj:IsA("BasePart") then
		hookKillOnTouchPart(obj)
	else
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("BasePart") then
				hookKillOnTouchPart(d)
			end
		end
	end
end

local function ensureModelPrimaryPartByPart(model)
	local p = model:FindFirstChild("Part", true)
	if p and p:IsA("BasePart") then
		p.CanTouch = true
		pcall(function()
			model.PrimaryPart = p
		end)
		return p
	end

	local any = model:FindFirstChildWhichIsA("BasePart", true)
	if any then
		any.CanTouch = true
		pcall(function()
			model.PrimaryPart = any
		end)
	end

	return model.PrimaryPart or any
end

local function getSpinTargetRock(clone)
	local t = clone:FindFirstChild("Model", true)
	if t and (t:IsA("Model") or t:IsA("BasePart")) then
		return t
	end
	return clone
end

local function getTornadoSubmodels(clone)
	local out = {}
	for _, n in ipairs({ "1", "2", "3" }) do
		local m = clone:FindFirstChild(n, true)
		if m and m:IsA("Model") then
			out[#out + 1] = m
		end
	end
	return out
end

local function spawnWave(entry)
	local clone = entry.Template:Clone()
	clone.Name = entry.Name
	clone.Parent = clientWavesFolder

	local extraRot = getExtraRot(entry.Info)

	local movePart = nil
	if clone:IsA("Model") then
		movePart = ensureModelPrimaryPartByPart(clone)
	end

	anchor(clone)
	hookKillOnTouch(clone, movePart)
	applyHazardMetadata(clone, entry.Template)

	local startCF, endCF
	if clone:IsA("Model") and movePart then
		startCF = computeModelPivotOnTopUsingPart(clone, movePart, startPart, extraRot)
		endCF = computeModelPivotOnTopUsingPart(clone, movePart, endPart, extraRot)
	else
		startCF = computePivotOnTop(clone, startPart, extraRot)
		endCF = computePivotOnTop(clone, endPart, extraRot)
	end

	setPivot(clone, startCF)

	local speed = tonumber(entry.Info.Speed) or 50
	if speed <= 0 then speed = 50 end

	local distance = (startCF.Position - endCF.Position).Magnitude
	local duration = distance / speed
	if duration < 0.05 then duration = 0.05 end

	local isRock = (entry.Name == "Rock" or entry.Name == "FastRock")
	local isTornado = (entry.Name == "Tornado" or entry.Name == "FastTornado")

	if (not isRock and not isTornado) and clone:IsA("BasePart") then
		local tween = TweenService:Create(
			clone,
			TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
			{ CFrame = endCF }
		)
		local freezeController = createFreezeController(clone, tween)
		tween:Play()
		tween.Completed:Connect(function()
			freezeController:Destroy()
			if clone.Parent then clone:Destroy() end
		end)
		return
	end

	local rockSpinTarget, rockSpinOffset, rockRadius
	if isRock then
		rockSpinTarget = getSpinTargetRock(clone)
		local basePivot = getPivot(clone)
		local spinPivot = getPivot(rockSpinTarget)
		rockSpinOffset = basePivot:ToObjectSpace(spinPivot)
		local _, s = getBox(rockSpinTarget)
		rockRadius = math.max(2, math.max(s.Y, s.Z) * 0.5)
	end

	local tornadoData = nil
	if isTornado then
		local subs = getTornadoSubmodels(clone)
		if #subs > 0 then
			tornadoData = {}
			local basePivot = getPivot(clone)

			for i = 1, #subs do
				local m = subs[i]
				local off = basePivot:ToObjectSpace(m:GetPivot())

				local dir = (rng:NextInteger(0, 1) == 0) and -1 or 1
				local degPerSec = rng:NextNumber(55, 120)
				local scaleAmp = rng:NextNumber(0.05, 0.09)
				local scaleFreq = rng:NextNumber(1.5, 2)
				local scalePhase = rng:NextNumber(0, math.pi * 2)
				local noiseAmp = math.rad(rng:NextNumber(1.5, 3.5))
				local noiseFreq = rng:NextNumber(2, 3)
				local seedA = rng:NextNumber(-1000, 1000)
				local seedB = rng:NextNumber(-1000, 1000)

				tornadoData[i] = {
					Model = m,
					Offset = off,
					Dir = dir,
					DegPerSec = degPerSec,
					ScaleAmp = scaleAmp,
					ScaleFreq = scaleFreq,
					ScalePhase = scalePhase,
					NoiseAmp = noiseAmp,
					NoiseFreq = noiseFreq,
					SeedA = seedA,
					SeedB = seedB,
				}
			end
		end
	end

	local travelDir = (endCF.Position - startCF.Position)
	if travelDir.Magnitude < 1e-4 then
		travelDir = Vector3.new(0, 0, -1)
	else
		travelDir = travelDir.Unit
	end

	local axisWorld = travelDir:Cross(Vector3.yAxis)
	if axisWorld.Magnitude < 1e-4 then
		axisWorld = Vector3.xAxis
	else
		axisWorld = axisWorld.Unit
	end

	local startTime = os.clock()

	local alpha = Instance.new("NumberValue")
	alpha.Value = 0
	alpha.Parent = clone

	local conn
	conn = alpha.Changed:Connect(function(v)
		if not clone.Parent then
			if conn then conn:Disconnect() end
			return
		end

		local a = math.clamp(tonumber(v) or 0, 0, 1)
		local baseCF = startCF:Lerp(endCF, a)
		setPivot(clone, baseCF)

		if isRock and rockSpinTarget and rockSpinOffset and rockRadius then
			local roll = -((a * distance) / rockRadius)

			local baseSpinCF = getPivot(clone) * rockSpinOffset
			local rotOnly = baseSpinCF - baseSpinCF.Position
			local localAxis = rotOnly:VectorToObjectSpace(axisWorld)

			local spinCF = baseSpinCF * CFrame.fromAxisAngle(localAxis, roll)
			setPivot(rockSpinTarget, spinCF)
		end

		if tornadoData then
			local t = os.clock() - startTime
			for i = 1, #tornadoData do
				local td = tornadoData[i]
				local m = td.Model
				if m and m.Parent then
					local subBase = getPivot(clone) * td.Offset

					local yaw = math.rad(td.DegPerSec * td.Dir) * t
					local n1 = math.noise(td.SeedA, t * td.NoiseFreq, 0)
					local n2 = math.noise(td.SeedB, t * td.NoiseFreq, 0)
					local pitch = td.NoiseAmp * n1
					local roll = td.NoiseAmp * n2

					local s = 1 + td.ScaleAmp * math.sin(t * td.ScaleFreq + td.ScalePhase)
					pcall(function()
						m:ScaleTo(s)
					end)

					m:PivotTo(subBase * CFrame.Angles(pitch, yaw, roll))
				end
			end
		end
	end)

	local tween = TweenService:Create(
		alpha,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
		{ Value = 1 }
	)
	local freezeController = createFreezeController(clone, tween)

	tween:Play()
	tween.Completed:Connect(function()
		if conn then conn:Disconnect() end
		if alpha.Parent then alpha:Destroy() end
		freezeController:Destroy()
		if clone.Parent then clone:Destroy() end
	end)
end

local NoDisastersTimer = workspace:WaitForChild("NoDisastersTimer")
local paused = false

local function updatePause()
	if NoDisastersTimer.Value > 0 then
		paused = true
		clientWavesFolder:ClearAllChildren()
	else
		paused = false
	end
end

NoDisastersTimer:GetPropertyChangedSignal("Value"):Connect(updatePause)
updatePause()

RunService.RenderStepped:Connect(function()
	updatePfpPositions()
	updateWaveIndicators()
	updatePfpBrainrotAndSkull()
end)

while true do
	if not paused then
		if #entries > 0 then
			local e = chooseByChance(entries)
			if e then
				spawnWave(e)
			end
		end
		task.wait(rng:NextInteger(4, 5))
	else
		task.wait(0.2)
	end
end
