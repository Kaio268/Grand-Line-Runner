local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local DEBUG_TRACE = RunService:IsStudio()
local seenWaveLogKeys = {}

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function formatCFrame(value)
	if typeof(value) ~= "CFrame" then
		return tostring(value)
	end

	return string.format(
		"pos=%s look=%s",
		formatVector3(value.Position),
		formatVector3(value.LookVector)
	)
end

local function mapTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[MAP TRACE] " .. message, ...))
end

local function waveTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[WAVE TRACE] " .. message, ...))
end

local function waveWarn(message, ...)
	warn(string.format("[WAVE WARN] " .. message, ...))
end

local function waveError(message, ...)
	warn(string.format("[WAVE ERROR] " .. message, ...))
end

local function waveWarnOnce(key, message, ...)
	if seenWaveLogKeys[key] then
		return
	end

	seenWaveLogKeys[key] = true
	waveWarn(message, ...)
end

local function waveTry(context, callback)
	local ok, result = xpcall(callback, function(err)
		return debug.traceback(tostring(err), 2)
	end)

	if not ok then
		waveError("context=%s error=%s", tostring(context), tostring(result))
	end

	return ok, result
end

local WavesConfig = require(
	Modules
		:WaitForChild("Configs")
		:WaitForChild("LavaWaves")
)

local BrainrotsConfig = require(
	Modules
		:WaitForChild("Configs")
		:WaitForChild("Brainrots")
)
local HazardRuntime = require(
	Modules
		:WaitForChild("DevilFruits")
		:WaitForChild("HazardRuntime")
)
local ProtectionRuntime = require(
	Modules
		:WaitForChild("DevilFruits")
		:WaitForChild("ProtectionRuntime")
)
local WaveHazardVisuals = require(Modules:WaitForChild("WaveHazardVisuals"))

waveTrace("startup awaiting ReplicatedStorage.Waves")
local WavesFolder = ReplicatedStorage:WaitForChild("Waves", 15)
if not WavesFolder then
	waveWarn("startup waitForChild timed out path=ReplicatedStorage.Waves; continuing to wait indefinitely")
	WavesFolder = ReplicatedStorage:WaitForChild("Waves")
end
waveTrace("startup resolvedWavesFolder path=%s", formatInstancePath(WavesFolder))

waveTrace("startup awaiting map refs required=MapRoot,WaveFolder,WaveStart,WaveEnd")
local resolvedMapRefs
do
	local ok, result = waveTry("startup map resolution", function()
		return MapResolver.WaitForRefs(
			{ "MapRoot", "WaveFolder", "WaveStart", "WaveEnd" },
			nil,
			{
				warn = true,
				context = "WaveClient",
			}
		)
	end)

	if not ok then
		error(result, 0)
	end

	resolvedMapRefs = result
end
local waveFolder = resolvedMapRefs.WaveFolder
local startPart = resolvedMapRefs.WaveStart
local endPart = resolvedMapRefs.WaveEnd
waveTrace(
	"startup mapResolved requestedMap=%s activeMap=%s mapPath=%s waveFolder=%s startPart=%s startPos=%s endPart=%s endPos=%s",
	tostring(resolvedMapRefs.RequestedMapName),
	tostring(resolvedMapRefs.ActiveMapName),
	formatInstancePath(resolvedMapRefs.MapRoot),
	formatInstancePath(waveFolder),
	formatInstancePath(startPart),
	formatVector3(startPart and startPart.Position or nil),
	formatInstancePath(endPart),
	formatVector3(endPart and endPart.Position or nil)
)
mapTrace(
	"WaveClient requestedMap=%s activeMap=%s mapPath=%s waveFolder=%s start=%s startPos=%s end=%s endPos=%s",
	tostring(resolvedMapRefs.RequestedMapName),
	tostring(resolvedMapRefs.ActiveMapName),
	formatInstancePath(resolvedMapRefs.MapRoot),
	formatInstancePath(waveFolder),
	formatInstancePath(startPart),
	formatVector3(startPart and startPart.Position or nil),
	formatInstancePath(endPart),
	formatVector3(endPart and endPart.Position or nil)
)

local sharedHazardsFolder = waveFolder:FindFirstChild("Hazards") or waveFolder:WaitForChild("Hazards", 15)
local useSharedHazards = sharedHazardsFolder ~= nil
local clientWavesFolder = sharedHazardsFolder or resolvedMapRefs.ClientWaves or waveFolder:FindFirstChild("ClientWaves")
local clientWavesFolderCreated = false
if not clientWavesFolder then
	waveWarn(
		"startup hazards folder missing under waveFolder=%s; falling back to a local ClientWaves folder",
		formatInstancePath(waveFolder)
	)
	clientWavesFolder = Instance.new("Folder")
	clientWavesFolder.Name = "ClientWaves"
	clientWavesFolder.Parent = waveFolder
	clientWavesFolderCreated = true
end
waveTrace(
	"startup trackedHazardsFolder path=%s useSharedHazards=%s created=%s",
	formatInstancePath(clientWavesFolder),
	tostring(useSharedHazards),
	tostring(clientWavesFolderCreated)
)

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local KillMeEvent = Remotes and Remotes:FindFirstChild("KillMe")
local ProgressBarSync = Remotes and Remotes:FindFirstChild("ProgressBarSync")
waveTrace(
	"startup remotes remotesFolder=%s killMe=%s progressBarSync=%s",
	formatInstancePath(Remotes),
	formatInstancePath(KillMeEvent),
	formatInstancePath(ProgressBarSync)
)

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("HUD")
local progressBar = hud:WaitForChild("ProgressBar")

local pfpTemplate = progressBar:WaitForChild("PFP")
pfpTemplate.Visible = false

local disasterTemplate = progressBar:WaitForChild("Disaster")
disasterTemplate.Visible = false

local pfpClones = {}
local waveIndicators = {}
local chestIndicators = {}

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

local function getRewardWorldPos(obj)
	if not obj then
		return nil
	end

	if obj:IsA("Model") then
		local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		if primary then
			return primary.Position
		end
		return obj:GetPivot().Position
	end

	if obj:IsA("BasePart") then
		return obj.Position
	end

	return nil
end

local disasterYScale = disasterTemplate.Position.Y.Scale
local disasterYOffset = disasterTemplate.Position.Y.Offset

local function createChestIndicator(rewardObject)
	local indicator = Instance.new("TextLabel")
	indicator.Name = "ChestIndicator_" .. rewardObject.Name
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.AutomaticSize = Enum.AutomaticSize.None
	indicator.BackgroundColor3 = Color3.fromRGB(184, 126, 56)
	indicator.BorderSizePixel = 0
	indicator.Size = UDim2.fromOffset(74, 26)
	indicator.Text = "CHEST"
	indicator.TextColor3 = Color3.fromRGB(255, 247, 198)
	indicator.TextScaled = true
	indicator.TextStrokeTransparency = 0
	indicator.Font = Enum.Font.GothamBlack
	indicator.Visible = true
	indicator.ZIndex = 30
	indicator.Parent = progressBar

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = indicator

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(59, 34, 8)
	stroke.Thickness = 2
	stroke.Parent = indicator

	return indicator
end

local function ensureChestIndicator(rewardObject)
	if chestIndicators[rewardObject] and chestIndicators[rewardObject].Parent then
		return chestIndicators[rewardObject]
	end

	local indicator = createChestIndicator(rewardObject)
	chestIndicators[rewardObject] = indicator
	return indicator
end

local function removeUnusedChestIndicators(validMap)
	for rewardObject, gui in pairs(chestIndicators) do
		if not validMap[rewardObject] then
			if gui and gui.Parent then
				gui:Destroy()
			end
			chestIndicators[rewardObject] = nil
		end
	end
end

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
	waveTrace(
		"clientWavesFolder childAdded name=%s path=%s class=%s",
		tostring(child.Name),
		formatInstancePath(child),
		tostring(child.ClassName)
	)
	waveTry("clientWavesFolder.ChildAdded", function()
		ensureWaveIndicator(child)
	end)
end)

clientWavesFolder.ChildRemoved:Connect(function(child)
	waveTrace(
		"clientWavesFolder childRemoved name=%s path=%s class=%s",
		tostring(child.Name),
		formatInstancePath(child),
		tostring(child.ClassName)
	)
	waveTry("clientWavesFolder.ChildRemoved", function()
		removeWaveIndicator(child)
	end)
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

local function updateChestIndicators()
	local valid = {}
	local controllerFolder = waveFolder:FindFirstChild("GrandLineRush")
	local rewardFolder = controllerFolder and controllerFolder:FindFirstChild("RunRewards")
	if not rewardFolder then
		removeUnusedChestIndicators(valid)
		return
	end

	for _, rewardObject in ipairs(rewardFolder:GetChildren()) do
		if rewardObject:GetAttribute("RewardType") == "Chest" then
			local pos = getRewardWorldPos(rewardObject)
			if pos then
				local indicator = ensureChestIndicator(rewardObject)
				local a = getAlphaOnLine(pos)
				indicator.Position = UDim2.new(alphaToXScale(a), 0, 0.28, 0)
				valid[rewardObject] = true
			end
		end
	end

	removeUnusedChestIndicators(valid)
end

if ProgressBarSync and ProgressBarSync:IsA("RemoteEvent") then
	ProgressBarSync.OnClientEvent:Connect(function(_, payload)
		waveTry("ProgressBarSync.OnClientEvent", function()
			local valid = {}
			for _, info in ipairs(payload) do
				local uid = info.UserId
				valid[uid] = true
				ensurePfp(uid)
			end
			removeUnusedPfps(valid)
		end)
	end)
	ProgressBarSync:FireServer("Request")
else
	waveWarnOnce(
		"progress_bar_sync_missing",
		"startup ProgressBarSync remote missing; falling back to current Players list"
	)
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
local configuredWaveCount = 0
if useSharedHazards then
	waveTrace(
		"startup shared hazards detected; client-side wave spawning disabled trackedFolder=%s",
		formatInstancePath(clientWavesFolder)
	)
else
	for waveName, info in pairs(WavesConfig) do
		configuredWaveCount += 1
		local template = getTemplate(waveName)
		if template then
			table.insert(entries, {
				Name = waveName,
				Info = info,
				Template = template,
			})
			waveTrace(
				"startup registeredWave name=%s template=%s class=%s chance=%s speed=%s",
				tostring(waveName),
				formatInstancePath(template),
				tostring(template.ClassName),
				tostring(info and info.Chance),
				tostring(info and info.Speed)
			)
		else
			waveWarn(
				"startup waveTemplateMissing name=%s expectedPath=%s chance=%s speed=%s",
				tostring(waveName),
				"ReplicatedStorage.Waves." .. tostring(waveName),
				tostring(info and info.Chance),
				tostring(info and info.Speed)
			)
		end
	end
	waveTrace(
		"startup spawnEntriesReady count=%s configCount=%s",
		tostring(#entries),
		tostring(configuredWaveCount)
	)
	if #entries <= 0 then
		waveWarn(
			"startup no spawnable wave entries found wavesFolder=%s configCount=%s",
			formatInstancePath(WavesFolder),
			tostring(configuredWaveCount)
		)
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
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and ProtectionRuntime.IsProtected(LocalPlayer, hrp.Position, "WaveKill") then
		waveTrace(
			"killLocalPlayer skipped reason=protected hrpPos=%s",
			formatVector3(hrp.Position)
		)
		return
	end

	if hum and hum.Health > 0 then
		if KillMeEvent and KillMeEvent:IsA("RemoteEvent") then
			waveTrace(
				"killLocalPlayer firing kill remote=%s",
				formatInstancePath(KillMeEvent)
			)
			KillMeEvent:FireServer()
		else
			waveWarnOnce(
				"kill_remote_missing",
				"killLocalPlayer no KillMe remote found; applying local Humanoid.Health = 0 fallback"
			)
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

local function hookKillOnTouchPart(p, shouldKill)
	if not p or not p:IsA("BasePart") then
		return
	end
	p.CanTouch = true
	p.Touched:Connect(function(hit)
		if isLocalHRP(hit) and (shouldKill == nil or shouldKill(p) == true) then
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

local LOCAL_WAVE_VISUAL_FOLDER_NAME = "_LocalWaveVisuals"
local SMOOTHED_VISUAL_SOURCE_ATTRIBUTE = "SmoothedWaveVisualSource"
local REGULAR_WAVE_VISUAL_ASSET_NAME = "Regular Wave"
local FROZEN_WAVE_VISUAL_ASSET_NAME = "Frozen Wave"
local WAVE_VISUAL_NAME = "WaveVisual"
local FROZEN_WAVE_VISUAL_NAME = "FrozenWaveVisual"
local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "WaveVisualOriginalTransparency"
local ORIGINAL_ENABLED_ATTRIBUTE = "WaveVisualOriginalEnabled"
local SHARED_WAVE_VISUAL_SMOOTHNESS = 28
local SHARED_WAVE_VISUAL_MAX_LEAD = 0.08
local SHARED_WAVE_VISUAL_DECAY_DELAY = 0.12
local SHARED_WAVE_VISUAL_SNAP_DISTANCE = 90
local SHARED_WAVE_VISUAL_REBUILD_DELAY = 0.05

local localWaveVisualsFolder = nil
local sharedHazardVisualSmoothers = {}

local function isWaveVisualRoot(instance)
	return (instance and (instance:IsA("Model") or instance:IsA("BasePart")))
		and (instance.Name == WAVE_VISUAL_NAME or instance.Name == FROZEN_WAVE_VISUAL_NAME)
end

local function isVisualEffect(instance)
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles")
end

local function forEachVisualItem(root, callback)
	if not root then
		return
	end

	callback(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		callback(descendant)
	end
end

local function getDescendantCount(root)
	if not root then
		return 0
	end

	return #root:GetDescendants()
end

local function getLocalWaveVisualsFolder()
	local folder = localWaveVisualsFolder
	if folder and folder.Parent then
		return folder
	end

	local existing = workspace:FindFirstChild(LOCAL_WAVE_VISUAL_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		localWaveVisualsFolder = existing
		return existing
	end

	folder = Instance.new("Folder")
	folder.Name = LOCAL_WAVE_VISUAL_FOLDER_NAME
	folder.Parent = workspace
	localWaveVisualsFolder = folder
	return folder
end

local function hideReplicatedVisual(root)
	forEachVisualItem(root, function(item)
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = 1
		elseif item:IsA("Decal") or item:IsA("Texture") then
			item.Transparency = 1
		elseif isVisualEffect(item) then
			item.Enabled = false
		end
	end)
end

local function setLocalVisualVisible(root, isVisible)
	forEachVisualItem(root, function(item)
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = if isVisible then 0 else 1
			if isVisible then
				local originalTransparency = item:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
				if typeof(originalTransparency) == "number" then
					item.Transparency = originalTransparency
				elseif item.Transparency >= 1 then
					item.Transparency = 0
				end
			end
		elseif item:IsA("Decal") or item:IsA("Texture") then
			if isVisible then
				local originalTransparency = item:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
				item.Transparency = if typeof(originalTransparency) == "number" then originalTransparency else 0
			else
				item.Transparency = 1
			end
		elseif isVisualEffect(item) then
			if isVisible then
				local originalEnabled = item:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE)
				item.Enabled = if typeof(originalEnabled) == "boolean" then originalEnabled else true
			else
				item.Enabled = false
			end
		end
	end)
end

local function createSharedHazardVisualSmoother(hazard)
	if not useSharedHazards or not hazard or sharedHazardVisualSmoothers[hazard] then
		return sharedHazardVisualSmoothers[hazard]
	end

	if not (hazard:IsA("Model") or hazard:IsA("BasePart")) then
		return nil
	end

	local now = os.clock()
	local startingPivot = getPivot(hazard)
	local controller = {
		Hazard = hazard,
		ClonesByName = {},
		Connections = {},
		SourceConnections = {},
		CurrentCFrame = startingPivot,
		TargetCFrame = startingPivot,
		LastSampleTime = now,
		Velocity = Vector3.zero,
		Destroyed = false,
		RefreshQueued = false,
	}

	sharedHazardVisualSmoothers[hazard] = controller

	function controller:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		sharedHazardVisualSmoothers[self.Hazard] = nil

		for _, connection in ipairs(self.Connections) do
			connection:Disconnect()
		end

		for _, connection in pairs(self.SourceConnections) do
			connection:Disconnect()
		end

		for _, entry in pairs(self.ClonesByName) do
			if entry.Clone and entry.Clone.Parent then
				entry.Clone:Destroy()
			end
		end
	end

	function controller:GetActiveVisualName()
		local activeAsset = self.Hazard:GetAttribute("ActiveWaveVisualAssetName")
		if activeAsset == FROZEN_WAVE_VISUAL_ASSET_NAME then
			return FROZEN_WAVE_VISUAL_NAME
		end

		if activeAsset == REGULAR_WAVE_VISUAL_ASSET_NAME then
			return WAVE_VISUAL_NAME
		end

		if self.Hazard:GetAttribute("Frozen") == true and self.ClonesByName[FROZEN_WAVE_VISUAL_NAME] then
			return FROZEN_WAVE_VISUAL_NAME
		end

		return WAVE_VISUAL_NAME
	end

	function controller:HideSource(source)
		hideReplicatedVisual(source)

		if self.SourceConnections[source] then
			return
		end

		self.SourceConnections[source] = source.DescendantAdded:Connect(function()
			hideReplicatedVisual(source)
			self:ScheduleRefresh()
		end)
	end

	function controller:ScheduleRefresh()
		if self.Destroyed or self.RefreshQueued then
			return
		end

		self.RefreshQueued = true
		task.delay(SHARED_WAVE_VISUAL_REBUILD_DELAY, function()
			if self.Destroyed then
				return
			end

			self.RefreshQueued = false
			self:Refresh()
		end)
	end

	function controller:EnsureClone(source)
		if not isWaveVisualRoot(source) then
			return nil
		end

		local entry = self.ClonesByName[source.Name]
		local hazardPivot = getPivot(self.Hazard)
		local sourcePivot = getPivot(source)
		local offset = hazardPivot:ToObjectSpace(sourcePivot)
		local sourceDescendantCount = getDescendantCount(source)
		if entry and entry.Clone and entry.Clone.Parent then
			if sourceDescendantCount <= (entry.DescendantCount or 0) then
				entry.Source = source
				entry.Offset = offset
				self:HideSource(source)
				return entry
			end

			entry.Clone:Destroy()
			self.ClonesByName[source.Name] = nil
		end

		local ok, cloneOrError = pcall(function()
			return source:Clone()
		end)

		if not ok or not cloneOrError then
			waveWarnOnce(
				"smooth_visual_clone_failed_" .. tostring(source.Name),
				"shared wave visual smoothing skipped clone failed visual=%s error=%s",
				formatInstancePath(source),
				tostring(cloneOrError)
			)
			return nil
		end

		local clone = cloneOrError
		clone.Name = tostring(self.Hazard.Name) .. "_" .. tostring(source.Name) .. "_Local"
		clone:SetAttribute(SMOOTHED_VISUAL_SOURCE_ATTRIBUTE, source:GetFullName())
		clone.Parent = getLocalWaveVisualsFolder()
		WaveHazardVisuals.ConfigureVisualRoot(clone)
		setLocalVisualVisible(clone, false)
		self:HideSource(source)

		entry = {
			Clone = clone,
			Name = source.Name,
			Offset = offset,
			Source = source,
			DescendantCount = sourceDescendantCount,
		}
		self.ClonesByName[source.Name] = entry
		return entry
	end

	function controller:Refresh()
		if self.Destroyed then
			return
		end

		if not self.Hazard.Parent then
			self:Destroy()
			return
		end

		for _, child in ipairs(self.Hazard:GetChildren()) do
			if isWaveVisualRoot(child) then
				self:EnsureClone(child)
			end
		end

		for name, entry in pairs(self.ClonesByName) do
			if not entry.Source or entry.Source.Parent ~= self.Hazard then
				local sourceConnection = entry.Source and self.SourceConnections[entry.Source]
				if sourceConnection then
					sourceConnection:Disconnect()
					self.SourceConnections[entry.Source] = nil
				end

				if entry.Clone and entry.Clone.Parent then
					entry.Clone:Destroy()
				end
				self.ClonesByName[name] = nil
			elseif entry.Source then
				self:HideSource(entry.Source)
			end
		end

		self:UpdateVisibility()
	end

	function controller:UpdateVisibility()
		local activeName = self:GetActiveVisualName()
		if activeName == FROZEN_WAVE_VISUAL_NAME and not self.ClonesByName[activeName] then
			activeName = WAVE_VISUAL_NAME
		end

		for name, entry in pairs(self.ClonesByName) do
			if entry.Source then
				self:HideSource(entry.Source)
			end
			setLocalVisualVisible(entry.Clone, name == activeName)
		end
	end

	function controller:Update(deltaTime)
		if self.Destroyed then
			return
		end

		if not self.Hazard.Parent then
			self:Destroy()
			return
		end

		local currentTarget = getPivot(self.Hazard)
		local sampleNow = os.clock()
		local previousTarget = self.TargetCFrame
		local moved = (currentTarget.Position - previousTarget.Position).Magnitude

		if moved > 0.01 then
			local sampleDelta = math.max(sampleNow - self.LastSampleTime, 1 / 240)
			self.Velocity = (currentTarget.Position - previousTarget.Position) / sampleDelta
			self.LastSampleTime = sampleNow
			self.TargetCFrame = currentTarget
		elseif self.Hazard:GetAttribute("Frozen") == true or sampleNow - self.LastSampleTime > SHARED_WAVE_VISUAL_DECAY_DELAY then
			local decayAlpha = math.clamp(deltaTime * 10, 0, 1)
			self.Velocity = self.Velocity:Lerp(Vector3.zero, decayAlpha)
			self.TargetCFrame = currentTarget
		end

		local leadTime = 0
		if self.Hazard:GetAttribute("Frozen") ~= true then
			leadTime = math.min(math.max(sampleNow - self.LastSampleTime, 0), SHARED_WAVE_VISUAL_MAX_LEAD)
		end

		local predictedTarget = self.TargetCFrame + self.Velocity * leadTime
		local smoothAlpha = math.clamp(1 - math.exp(-SHARED_WAVE_VISUAL_SMOOTHNESS * deltaTime), 0, 1)
		if (self.CurrentCFrame.Position - predictedTarget.Position).Magnitude > SHARED_WAVE_VISUAL_SNAP_DISTANCE then
			self.CurrentCFrame = predictedTarget
		else
			self.CurrentCFrame = self.CurrentCFrame:Lerp(predictedTarget, smoothAlpha)
		end

		for _, entry in pairs(self.ClonesByName) do
			if entry.Clone and entry.Clone.Parent then
				setPivot(entry.Clone, self.CurrentCFrame * entry.Offset)
			end
		end
	end

	table.insert(controller.Connections, hazard.ChildAdded:Connect(function(child)
		if isWaveVisualRoot(child) then
			WaveHazardVisuals.ConfigureVisualRoot(child)
			controller:ScheduleRefresh()
		end
	end))

	table.insert(controller.Connections, hazard.ChildRemoved:Connect(function(child)
		if isWaveVisualRoot(child) then
			controller:ScheduleRefresh()
		end
	end))

	table.insert(controller.Connections, hazard:GetAttributeChangedSignal("Frozen"):Connect(function()
		controller:ScheduleRefresh()
	end))

	table.insert(controller.Connections, hazard:GetAttributeChangedSignal("ActiveWaveVisualAssetName"):Connect(function()
		controller:ScheduleRefresh()
	end))

	table.insert(controller.Connections, hazard.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			controller:Destroy()
		end
	end))

	controller:Refresh()
	return controller
end

local function updateSharedHazardVisualSmoothers(deltaTime)
	for _, controller in pairs(sharedHazardVisualSmoothers) do
		controller:Update(deltaTime)
	end
end

local function hookSharedHazardKillOnTouch(hazard)
	for _, child in ipairs(hazard:GetChildren()) do
		if child.Name == "WaveVisual" or child.Name == "FrozenWaveVisual" then
			WaveHazardVisuals.ConfigureVisualRoot(child)
		end
	end

	local function syncFrozenHitboxState()
		WaveHazardVisuals.SetHitboxFrozen(hazard, hazard:GetAttribute("Frozen") == true)
	end

	syncFrozenHitboxState()
	hazard:GetAttributeChangedSignal("Frozen"):Connect(syncFrozenHitboxState)

	hazard.ChildAdded:Connect(function(child)
		if child.Name == "WaveVisual" or child.Name == "FrozenWaveVisual" then
			WaveHazardVisuals.ConfigureVisualRoot(child)
		elseif child.Name == "WaveHitbox" then
			syncFrozenHitboxState()
		end
	end)

	local hitboxParts = WaveHazardVisuals.GetHitboxParts(hazard)
	if #hitboxParts <= 0 then
		hookKillOnTouch(hazard)
		return
	end

	for _, part in ipairs(hitboxParts) do
		hookKillOnTouchPart(part, function()
			return hazard:GetAttribute("Frozen") ~= true
		end)
	end
end

local function attachSharedHazard(hazard)
	hookSharedHazardKillOnTouch(hazard)
	createSharedHazardVisualSmoother(hazard)
end

if useSharedHazards then
	for _, hazard in ipairs(clientWavesFolder:GetChildren()) do
		attachSharedHazard(hazard)
	end

	clientWavesFolder.ChildAdded:Connect(function(child)
		attachSharedHazard(child)
	end)
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
	if not entry then
		waveWarn("spawnSkipped reason=nil_entry")
		return false
	end

	local ok = waveTry("spawnWave:" .. tostring(entry.Name), function()
		local clone = entry.Template:Clone()
		clone.Name = entry.Name
		clone.Parent = clientWavesFolder

		waveTrace(
			"spawnWave selected name=%s template=%s templateClass=%s chance=%s configuredSpeed=%s clientFolder=%s",
			tostring(entry.Name),
			formatInstancePath(entry.Template),
			tostring(entry.Template.ClassName),
			tostring(entry.Info and entry.Info.Chance),
			tostring(entry.Info and entry.Info.Speed),
			formatInstancePath(clientWavesFolder)
		)

		local extraRot = getExtraRot(entry.Info)

		local movePart = nil
		if clone:IsA("Model") then
			movePart = ensureModelPrimaryPartByPart(clone)
			if not movePart then
				waveWarn(
					"spawnWave model has no primary move part name=%s clonePath=%s",
					tostring(entry.Name),
					formatInstancePath(clone)
				)
			end
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
		if speed <= 0 then
			waveWarn(
				"spawnWave invalid speed name=%s configuredSpeed=%s defaultingTo=50",
				tostring(entry.Name),
				tostring(entry.Info and entry.Info.Speed)
			)
			speed = 50
		end

		local distance = (startCF.Position - endCF.Position).Magnitude
		local duration = distance / speed
		if duration < 0.05 then
			duration = 0.05
		end

		local isRock = (entry.Name == "Rock" or entry.Name == "FastRock")
		local isTornado = (entry.Name == "Tornado" or entry.Name == "FastTornado")
		local movementMode = "alpha_tween"
		if (not isRock and not isTornado) and clone:IsA("BasePart") then
			movementMode = "basepart_cframe_tween"
		elseif isRock then
			movementMode = "rock_spin_alpha_tween"
		elseif isTornado then
			movementMode = "tornado_alpha_tween"
		end

		waveTrace(
			"spawnWave movement name=%s startPart=%s startPos=%s endPart=%s endPos=%s spawnCFrame=%s targetCFrame=%s distance=%.2f speed=%.2f duration=%.2f mode=%s",
			tostring(entry.Name),
			formatInstancePath(startPart),
			formatVector3(startPart.Position),
			formatInstancePath(endPart),
			formatVector3(endPart.Position),
			formatCFrame(startCF),
			formatCFrame(endCF),
			distance,
			speed,
			duration,
			movementMode
		)

		if movementMode == "basepart_cframe_tween" then
			local tween = TweenService:Create(
				clone,
				TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
				{ CFrame = endCF }
			)
			local freezeController = createFreezeController(clone, tween)
			tween:Play()
			tween.Completed:Connect(function()
				waveTry("spawnWave completed:" .. tostring(entry.Name), function()
					freezeController:Destroy()
					if clone.Parent then
						clone:Destroy()
					end
					waveTrace("spawnWave completed name=%s mode=%s", tostring(entry.Name), movementMode)
				end)
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
			waveTry("spawnWave completed:" .. tostring(entry.Name), function()
				if conn then conn:Disconnect() end
				if alpha.Parent then alpha:Destroy() end
				freezeController:Destroy()
				if clone.Parent then clone:Destroy() end
				waveTrace("spawnWave completed name=%s mode=%s", tostring(entry.Name), movementMode)
			end)
		end)
	end)

	return ok
end

local NoDisastersTimer = workspace:WaitForChild("NoDisastersTimer")
local paused = false
waveTrace(
	"startup noDisastersTimer path=%s initialValue=%s",
	formatInstancePath(NoDisastersTimer),
	tostring(NoDisastersTimer.Value)
)

local function updatePause()
	if NoDisastersTimer.Value > 0 then
		if not paused then
			waveWarn(
				"spawnPaused reason=no_disasters_timer timerValue=%s trackedHazardsCount=%s",
				tostring(NoDisastersTimer.Value),
				tostring(#clientWavesFolder:GetChildren())
			)
		end
		paused = true
		if not useSharedHazards then
			clientWavesFolder:ClearAllChildren()
		end
	else
		if paused then
			waveTrace(
				"spawnResumed timerValue=%s",
				tostring(NoDisastersTimer.Value)
			)
		end
		paused = false
	end
end

NoDisastersTimer:GetPropertyChangedSignal("Value"):Connect(updatePause)
updatePause()

RunService.RenderStepped:Connect(function(deltaTime)
	updateSharedHazardVisualSmoothers(deltaTime)
	updatePfpPositions()
	updateWaveIndicators()
	updateChestIndicators()
	updatePfpBrainrotAndSkull()
end)

while true do
	if useSharedHazards then
		task.wait(1)
	elseif not paused then
		local selectedEntry = nil
		local spawned = false
		if #entries > 0 then
			selectedEntry = chooseByChance(entries)
			if selectedEntry then
				spawned = spawnWave(selectedEntry)
			else
				waveWarn("spawnSkipped reason=chooseByChance_returned_nil entryCount=%s", tostring(#entries))
			end
		else
			waveWarnOnce(
				"spawn_loop_no_entries",
				"spawnSkipped reason=no_wave_entries wavesFolder=%s configCount=%s",
				formatInstancePath(WavesFolder),
				tostring(configuredWaveCount)
			)
		end
		local waitSeconds = rng:NextInteger(4, 5)
		waveTrace(
			"spawnLoop cycleComplete selectedWave=%s spawned=%s nextWaitSeconds=%s",
			tostring(selectedEntry and selectedEntry.Name or "<nil>"),
			tostring(spawned),
			tostring(waitSeconds)
		)
		task.wait(waitSeconds)
	else
		task.wait(0.2)
	end
end
