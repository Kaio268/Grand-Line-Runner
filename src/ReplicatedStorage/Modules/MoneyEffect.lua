local TweenService   = game:GetService("TweenService")
local RS             = game:GetService("ReplicatedStorage")
local RunService     = game:GetService("RunService")
local Players        = game:GetService("Players")
local Debris         = game:GetService("Debris")
local SoundService   = game:GetService("SoundService")

local player   = Players.LocalPlayer
local camera   = workspace.CurrentCamera

local module = {}

local CFG = {
	CoinsPerBurst      = 6,

	PopTime            = 0.18,
	HoverTimeBase      = 0.35,
	HoverTimeSpread    = 0.08,

	PopUpMin           = 3.6,
	PopUpMax           = 6.0,
	PopLatMin          = 3.0,
	PopLatMax          = 6.0,

	HoverBobAmp        = {0.30, 0.55},
	HoverBobFreq       = {1.3, 2.0},
	HoverDriftRad      = {0.30, 0.55},
	HoverDriftSpeed    = {0.25, 0.50},

	ShrinkTo           = 0.05,
	HitDistance        = 1.0,

	FlyDuration        = 1.0,
}

local function rand(a: number, b: number) return a + (b-a)*math.random() end
local function clamp01(x: number) return x<0 and 0 or (x>1 and 1 or x) end
local function easeOutCubic(t: number) t = clamp01(t); local k = 1-t; return 1 - k*k*k end
local function smoothPulse01(t: number, a: number, b: number)
	local u = clamp01(t/a); u = u*u*(3-2*u)
	local v = clamp01((1-t)/b); v = v*v*(3-2*v)
	return u*v
end
local function randUnitXZ()
	local ang = rand(0, math.pi*2)
	return Vector3.new(math.cos(ang), 0, math.sin(ang))
end

local function bezier3(t: number, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3): Vector3
	local mt = 1 - t
	return (mt^3)*p0 + 3*(mt^2)*t*p1 + 3*mt*(t^2)*p2 + (t^3)*p3
end

local function setAnchored(inst: Instance, anchored: boolean)
	if inst:IsA("BasePart") then
		inst.Anchored = anchored
		inst.CanCollide = false; inst.CanQuery = false; inst.CanTouch = false
	elseif inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = anchored
				d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			end
		end
	end
end

local function getPivotCF(inst: Instance): CFrame
	if inst:IsA("BasePart") then
		return inst.CFrame
	end
	if inst:IsA("Model") then
		return inst:GetPivot()
	end
	return CFrame.new()
end

local function setCFrame(inst: Instance, cf: CFrame)
	if inst:IsA("BasePart") then inst.CFrame = cf
	elseif inst:IsA("Model") then inst:PivotTo(cf) end
end

local function setTransparency(inst: Instance, transparency: number)
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

local function getHeadPosition(): Vector3?
	local char = player.Character
	if not char then
		return nil
	end
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return nil
end

local function playCollectHighlight()
	local char = player.Character
	if not char then
		return
	end
	local hl = Instance.new("Highlight")
	hl.Adornee = char
	hl.FillColor = Color3.fromRGB(80, 255, 120)
	hl.FillTransparency = 0.5
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = char
	local tween = TweenService:Create(hl, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FillTransparency = 1})
	tween:Play()
	tween.Completed:Connect(function()
		if hl then
			hl:Destroy()
		end
	end)
end

local lastCollectTime = 0
local currentPitch    = 1.0

local PITCH_MIN       = 1.0
local PITCH_MAX       = 1.75
local PITCH_STEP      = 0.15
local COMBO_TIMEOUT   = 0.5

local function playCollectSound()
	local template = SoundService:FindFirstChild("Collecting-Money")
	if not template or not template:IsA("Sound") then
		warn("Collecting-Money sound not found in SoundService!")
		return
	end

	local now = os.clock()

	if now - lastCollectTime > COMBO_TIMEOUT then
		currentPitch = PITCH_MIN
	else
		currentPitch = math.min(PITCH_MAX, currentPitch + PITCH_STEP)
	end

	lastCollectTime = now

	local s = template:Clone()
	s.Pitch = currentPitch
	s.Parent = SoundService
	s:Play()

	local lifeTime = (s.TimeLength > 0 and s.TimeLength or 2) + 0.2
	Debris:AddItem(s, lifeTime)
end

function module:DropDollars(origin: Vector3 | CFrame, Amount)
	local oPos: Vector3
	if typeof(origin) == "CFrame" then
		oPos = (origin :: CFrame).Position
	elseif typeof(origin) == "Vector3" then
		oPos = origin :: Vector3
	else
		return
	end

	local template = RS:FindFirstChild("Dollar")
	if not template then
		warn("Dollar template not found in ReplicatedStorage!")
		return
	end

	task.spawn(function()
		for i = 1, Amount or CFG.CoinsPerBurst do
			task.spawn(function()
				local d = template:Clone()
				setAnchored(d, true)
				setCFrame(d, CFrame.new(oPos))
				d.Parent = workspace

				local baseRot = CFrame.fromEulerAnglesXYZ(getPivotCF(d):ToEulerAnglesXYZ())

				local lateral = randUnitXZ() * rand(CFG.PopLatMin, CFG.PopLatMax)
				local apex = oPos + lateral + Vector3.new(0, rand(CFG.PopUpMin, CFG.PopUpMax), 0)

				local popStart = os.clock()
				local popConn
				popConn = RunService.RenderStepped:Connect(function()
					if not d or not d.Parent then
						if popConn then
							popConn:Disconnect()
						end
						return
					end
					local t = (os.clock() - popStart)/CFG.PopTime
					if t > 1 then
						t = 1
					end
					local a = easeOutCubic(t)
					local pos = oPos:Lerp(apex, a)
					local spin = a * math.pi * 2
					local rot = baseRot * CFrame.Angles(0, spin, 0)
					setCFrame(d, CFrame.new(pos) * rot)
					if t >= 1 then
						popConn:Disconnect()
					end
				end)

				task.wait(CFG.PopTime)
				if not d or not d.Parent then
					return
				end

				local hoverT = math.max(0.15, CFG.HoverTimeBase + rand(-CFG.HoverTimeSpread, CFG.HoverTimeSpread))
				local hoverStart = getPivotCF(d).Position

				local bobAmp  = rand(CFG.HoverBobAmp[1],  CFG.HoverBobAmp[2])
				local bobFreq = rand(CFG.HoverBobFreq[1], CFG.HoverBobFreq[2])
				local driftR  = rand(CFG.HoverDriftRad[1], CFG.HoverDriftRad[2])
				local driftSp = rand(CFG.HoverDriftSpeed[1], CFG.HoverDriftSpeed[2])

				local phx, phy = math.random()*math.pi*2, math.random()*math.pi*2
				local hoverStartTime = os.clock()

				local hoverConn
				hoverConn = RunService.RenderStepped:Connect(function()
					if not d or not d.Parent then
						if hoverConn then
							hoverConn:Disconnect()
						end
						return
					end
					local el = os.clock() - hoverStartTime
					local t  = clamp01(el/hoverT)
					local intens = smoothPulse01(t, 0.18, 0.22)

					local y  = math.sin(el*bobFreq) * bobAmp * intens
					local dx = math.cos(el*driftSp + phx) * driftR * intens
					local dz = math.sin(el*driftSp + phy) * driftR * intens
					local pos = hoverStart + Vector3.new(dx, y, dz)

					local spin = el * 4
					local wobble = math.sin(el*3)*0.25
					local rot = baseRot * CFrame.Angles(wobble, spin, 0)
					setCFrame(d, CFrame.new(pos) * rot)
					if t >= 1 then
						hoverConn:Disconnect()
					end
				end)

				task.wait(hoverT)
				if not d or not d.Parent then
					return
				end

				local flyStartPos = getPivotCF(d).Position
				local char = player.Character
				local headPos0 = getHeadPosition() or (flyStartPos + Vector3.new(0,3,0))
				local center
				if char then
					local root = char:FindFirstChild("HumanoidRootPart")
					center = (root and root.Position) or headPos0
				else
					center = headPos0
				end

				local initialOffset = flyStartPos - center
				local initialRadius = initialOffset.Magnitude
				if initialRadius < 4 then
					initialRadius = 4
				end

				local startDistToHead = (flyStartPos - headPos0).Magnitude
				if startDistToHead < 4 then
					startDistToHead = 4
				end

				local baseAngle = math.atan2(initialOffset.Z, initialOffset.X)
				local orbitDir = math.random(0,1) == 0 and -1 or 1
				local orbitSpeed = rand(2,5) * orbitDir

				local p1BaseOffset = Vector3.new(math.cos(baseAngle),0,math.sin(baseAngle)) * (initialRadius*0.9)
				local p2BaseOffset = Vector3.new(math.cos(baseAngle+math.pi/2),0,math.sin(baseAngle+math.pi/2)) * (initialRadius*0.6)

				local startScaleModel = 1
				local startSizePart: Vector3? = nil
				if d:IsA("Model") then
					pcall(function()
						startScaleModel = d:GetScale()
					end)
				elseif d:IsA("BasePart") then
					startSizePart = d.Size
				end

				local flyTime = CFG.FlyDuration
				local flyStartTime = os.clock()

				local flyConn
				flyConn = RunService.RenderStepped:Connect(function()
					if not d or not d.Parent then
						if flyConn then
							flyConn:Disconnect()
						end
						return
					end

					local headPos = getHeadPosition()
					if not headPos then
						setTransparency(d, 1)
						flyConn:Disconnect()
						d:Destroy()
						return
					end

					local charNow = player.Character
					if charNow then
						local root = charNow:FindFirstChild("HumanoidRootPart")
						if root and root:IsA("BasePart") then
							center = root.Position
						else
							center = headPos
						end
					else
						center = headPos
					end

					local elapsed = os.clock() - flyStartTime
					local t = clamp01(elapsed / flyTime)
					local a = easeOutCubic(t)

					local angle = baseAngle + orbitSpeed*elapsed
					local cosA = math.cos(angle)
					local sinA = math.sin(angle)

					local function rotateOffset(off: Vector3): Vector3
						return Vector3.new(
							off.X*cosA - off.Z*sinA,
							off.Y,
							off.X*sinA + off.Z*cosA
						)
					end

					local radiusScale = 1 - t*0.7
					if radiusScale < 0.2 then
						radiusScale = 0.2
					end

					local heightKick = math.sin(t*math.pi)*2
					local p1 = center + rotateOffset(p1BaseOffset)*radiusScale + Vector3.new(0,2 + heightKick,0)
					local p2 = center + rotateOffset(p2BaseOffset)*radiusScale + Vector3.new(0,4 + heightKick,0)
					local p3 = headPos + Vector3.new(0,0.5,0)

					local pos = bezier3(a, flyStartPos, p1, p2, p3)

					local dist = (pos - headPos).Magnitude
					local distAlpha = clamp01(dist / startDistToHead)
					local scaleFactor = CFG.ShrinkTo + (1 - CFG.ShrinkTo) * distAlpha

					if d:IsA("Model") then
						pcall(function()
							d:ScaleTo(startScaleModel * scaleFactor)
						end)
					elseif d:IsA("BasePart") and startSizePart then
						d.Size = startSizePart * scaleFactor
					end

					local spinFast = elapsed * 10
					local tilt = math.sin(elapsed*6)*0.35
					local rot = baseRot * CFrame.Angles(tilt, spinFast, 0)
					setCFrame(d, CFrame.new(pos) * rot)

					if t > 0.85 then
						local fade = (t - 0.85) / 0.15
						setTransparency(d, clamp01(fade))
					end

					if dist <= CFG.HitDistance or t >= 1 then
						flyConn:Disconnect()
						playCollectHighlight()
						playCollectSound()
						d:Destroy()
					end
				end)

				Debris:AddItem(d, 5)
			end)
			task.wait(0.018)
		end
	end)
end

return module
