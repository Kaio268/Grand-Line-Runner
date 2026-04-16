local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VfxCommon = require(script.Parent:WaitForChild("VfxCommon"))

local FlameDashVfx = {}

local DEBUG_INFO = RunService:IsStudio()
local LOG_PREFIX = "[MERA VFX][FlameDash]"

local STARTUP_EMIT_COUNT = 20
local DASH_EMIT_COUNT = 10

local STARTUP_FADE_TIME = 0.06
local STARTUP_HOLD_TIME = 0.10

local ACTIVE_FADE_TIME = 0.08
local ACTIVE_HOLD_TIME = 0.18

local CLEANUP_BUFFER = 1.0
local DEFAULT_LOCAL_OFFSET = CFrame.Angles(0, math.rad(90), 0)

-- trail tuning
local DEFAULT_TRAIL_INTERVAL = 0.008
local DEFAULT_TRAIL_LIFETIME = 0.30
local DEFAULT_TRAIL_OFFSET = CFrame.new(0, 0, 0)

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if select("#", ...) > 0 then
		print(LOG_PREFIX, string.format(message, ...))
	else
		print(LOG_PREFIX, tostring(message))
	end
end

local function logWarn(message, ...)
	if select("#", ...) > 0 then
		warn(LOG_PREFIX, string.format(message, ...))
	else
		warn(LOG_PREFIX, tostring(message))
	end
end

local function getRootAsset()
	return VfxCommon.FindAsset("VFX", "Mera", "Flame Dash")
		or VfxCommon.FindAsset("Assets", "VFX", "Mera", "Flame Dash")
		or VfxCommon.FindAsset("Mera", "Flame Dash")
end

local function isBasePart(instance)
	return instance and instance:IsA("BasePart")
end

local function eachSelfAndDescendants(root, callback)
	if not root then
		return
	end

	callback(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		callback(descendant)
	end
end

local function setLightsEnabled(root, enabled)
	if not root then
		return
	end

	eachSelfAndDescendants(root, function(item)
		if item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			item.Enabled = enabled
		end
	end)
end

local function enableVisuals(root)
	if not root then
		return
	end

	VfxCommon.EnableEffects(root)
	setLightsEnabled(root, true)
end

local function disableVisuals(root)
	if not root then
		return
	end

	VfxCommon.DisableEffects(root)
	setLightsEnabled(root, false)
end

local function emitVisuals(root, count)
	if not root then
		return
	end

	enableVisuals(root)
	VfxCommon.EmitAll(root, count)
end

local function getDirection(direction, rootPart)
	if typeof(direction) == "Vector3" then
		local planar = Vector3.new(direction.X, 0, direction.Z)
		if planar.Magnitude > 0.001 then
			return planar.Unit
		end
	end

	if isBasePart(rootPart) then
		local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		if look.Magnitude > 0.001 then
			return look.Unit
		end
	end

	return Vector3.new(0, 0, -1)
end

local function getTargetCFrame(rootPart, options, localOffset)
	local offset = localOffset or DEFAULT_LOCAL_OFFSET

	if type(options) == "table" and typeof(options.Position) == "Vector3" then
		local direction = getDirection(options.Direction, rootPart)
		return CFrame.lookAt(options.Position, options.Position + direction) * offset
	end

	if isBasePart(rootPart) and rootPart.Parent then
		return rootPart.CFrame * offset
	end

	return nil
end

local function moveModelByAnchor(model, anchorPart, targetCFrame)
	if not model or not model.Parent or not isBasePart(anchorPart) or typeof(targetCFrame) ~= "CFrame" then
		return false
	end

	local delta = targetCFrame * anchorPart.CFrame:Inverse()
	local moved = false

	eachSelfAndDescendants(model, function(item)
		if item:IsA("BasePart") then
			item.CFrame = delta * item.CFrame
			moved = true
		end
	end)

	return moved
end

local function makeSafe(root)
	if not root then
		return
	end

	eachSelfAndDescendants(root, function(item)
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
			item.Anchored = false
		end
	end)
end

local function makeWorldSafe(root)
	if not root then
		return
	end

	eachSelfAndDescendants(root, function(item)
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.Massless = true
			item.Anchored = true
		end
	end)
end

local function clearWeld(anchorPart)
	if not isBasePart(anchorPart) then
		return
	end

	local old = anchorPart:FindFirstChild("FlameDashFollowWeld")
	if old and old:IsA("WeldConstraint") then
		old:Destroy()
	end
end

local function makeWeld(anchorPart, rootPart)
	if not isBasePart(anchorPart) or not isBasePart(rootPart) then
		return nil
	end

	clearWeld(anchorPart)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "FlameDashFollowWeld"
	weld.Part0 = anchorPart
	weld.Part1 = rootPart
	weld.Parent = anchorPart

	return weld
end

local function fadeOut(root)
	if not root then
		return
	end

	disableVisuals(root)
end

local function isLiveState(state)
	return type(state) == "table"
		and state.Kind == "FlameDash"
		and state.Destroyed ~= true
		and state.Clone ~= nil
		and state.Clone.Parent ~= nil
end

local function detachFollow(state)
	if type(state) ~= "table" then
		return
	end

	if state.FollowWeld and state.FollowWeld.Parent then
		state.FollowWeld:Destroy()
	end
	state.FollowWeld = nil
end

local function disconnectTrailLoop(state)
	if type(state) ~= "table" then
		return
	end

	if state.TrailConnection then
		state.TrailConnection:Disconnect()
		state.TrailConnection = nil
	end
end

local function destroyRuntimeState(state)
	if type(state) ~= "table" or state.Destroyed == true then
		return
	end

	state.Destroyed = true
	disconnectTrailLoop(state)
	detachFollow(state)

	local clone = state.Clone
	state.Clone = nil

	if clone and clone.Parent then
		pcall(function()
			clone:Destroy()
		end)
	end
end

local function scheduleDestroy(state, delaySeconds)
	if not isLiveState(state) then
		return
	end

	local clone = state.Clone
	local resolvedDelay = math.max(0, tonumber(delaySeconds) or 0)

	Debris:AddItem(clone, resolvedDelay + CLEANUP_BUFFER)

	task.delay(resolvedDelay, function()
		if not isLiveState(state) then
			return
		end
		if state.Clone ~= clone then
			return
		end

		destroyRuntimeState(state)
	end)
end

local function attachFollow(state, options)
	if not isLiveState(state) then
		return false
	end

	local rootPart = state.RootPart
	local clone = state.Clone
	local anchorPart = state.AnchorPart

	if not isBasePart(rootPart) or not rootPart.Parent or not clone or not clone.Parent or not isBasePart(anchorPart) then
		return false
	end

	local targetCFrame = getTargetCFrame(rootPart, options, state.LocalOffset)
	if typeof(targetCFrame) ~= "CFrame" then
		return false
	end

	detachFollow(state)

	if not moveModelByAnchor(clone, anchorPart, targetCFrame) then
		return false
	end

	state.FollowWeld = makeWeld(anchorPart, rootPart)
	return state.FollowWeld ~= nil
end

local function snapToFinal(state, options)
	if not isLiveState(state) then
		return false
	end

	local clone = state.Clone
	local anchorPart = state.AnchorPart
	if not clone or not clone.Parent or not isBasePart(anchorPart) then
		return false
	end

	local targetCFrame = nil

	if type(options) == "table" and typeof(options.FinalPosition) == "Vector3" then
		local direction = getDirection(options.Direction, state.RootPart)
		targetCFrame = CFrame.lookAt(options.FinalPosition, options.FinalPosition + direction) * state.LocalOffset
	else
		targetCFrame = getTargetCFrame(state.RootPart, options, state.LocalOffset)
	end

	if typeof(targetCFrame) ~= "CFrame" then
		return false
	end

	return moveModelByAnchor(clone, anchorPart, targetCFrame)
end

local function spawnTrailBurst(state, options)
	if not isLiveState(state) then
		return nil
	end

	local template = state.EmitDash
	local rootPart = state.RootPart
	if not isBasePart(template) or not isBasePart(rootPart) then
		return nil
	end

	local burst = template:Clone()
	burst.Name = "FlameDashTrailBurst"
	burst.Parent = Workspace

	makeWorldSafe(burst)

	local trailOffset = DEFAULT_TRAIL_OFFSET
	if type(options) == "table" and typeof(options.TrailOffset) == "CFrame" then
		trailOffset = options.TrailOffset
	end

	local moveDir = state.LastTrailDirection
	if not moveDir or moveDir.Magnitude < 0.001 then
		moveDir = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end

	if moveDir.Magnitude < 0.001 then
		moveDir = Vector3.new(0, 0, -1)
	else
		moveDir = moveDir.Unit
	end

	local spawnPos = rootPart.Position
	local burstFrame = CFrame.lookAt(spawnPos, spawnPos + moveDir) * state.LocalOffset * trailOffset
	burst.CFrame = burstFrame

	emitVisuals(burst, tonumber(type(options) == "table" and options.EmitCount) or DASH_EMIT_COUNT)

	local fadeDelay = math.max(0, tonumber(type(options) == "table" and options.TrailLifetime) or DEFAULT_TRAIL_LIFETIME)
	task.delay(fadeDelay * 0.35, function()
		if burst and burst.Parent then
			disableVisuals(burst)
		end
	end)

	Debris:AddItem(burst, fadeDelay + CLEANUP_BUFFER)
	return burst
end

local function ensureTrailLoop(state, options)
	if not isLiveState(state) then
		return false
	end

	if state.TrailConnection then
		return true
	end

	state.TrailElapsed = 0
	state.TrailInterval = math.max(0.01, tonumber(type(options) == "table" and options.TrailInterval) or DEFAULT_TRAIL_INTERVAL)

	state.TrailConnection = RunService.Heartbeat:Connect(function(dt)
		if not isLiveState(state) or state.Stopped then
			disconnectTrailLoop(state)
			return
		end

		local currentPos = state.RootPart.Position
		local lastPos = state.LastTrailPosition

		if lastPos then
			local delta = currentPos - lastPos
			local planar = Vector3.new(delta.X, 0, delta.Z)
			if planar.Magnitude > 0.01 then
				state.LastTrailDirection = planar.Unit
			end
		end

		state.LastTrailPosition = currentPos
		state.TrailElapsed += dt

		local interval = math.max(0.01, tonumber(state.TrailInterval) or DEFAULT_TRAIL_INTERVAL)
		while state.TrailElapsed >= interval do
			state.TrailElapsed -= interval
			spawnTrailBurst(state, options)
		end
	end)

	return true
end

local function createRuntimeState(options)
	local rootPart = type(options) == "table" and options.RootPart or nil
	if not isBasePart(rootPart) or not rootPart.Parent then
		logWarn("runtime creation skipped because RootPart was missing.")
		return nil
	end

	local source = getRootAsset()
	if not source then
		logWarn("Flame Dash asset could not be found.")
		return nil
	end

	local clone = VfxCommon.Clone(source, Workspace)
	if not clone then
		logWarn("Flame Dash asset failed to clone.")
		return nil
	end

	local followModel = clone:FindFirstChild("FX")
	local emitDash = clone:FindFirstChild("FX2")
	local emitStartup = emitDash

	if not isBasePart(followModel) or not isBasePart(emitDash) then
		clone:Destroy()
		logWarn("Flame Dash is missing FX / FX2 BaseParts.")
		return nil
	end

	makeSafe(clone)

	local initialLook = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if initialLook.Magnitude < 0.001 then
		initialLook = Vector3.new(0, 0, -1)
	else
		initialLook = initialLook.Unit
	end

	local state = {
		Kind = "FlameDash",
		Clone = clone,
		RootPart = rootPart,
		FollowModel = followModel,
		EmitStartup = emitStartup,
		EmitDash = emitDash,
		AnchorPart = followModel,
		FollowWeld = nil,
		LocalOffset = (type(options) == "table" and typeof(options.LocalOffset) == "CFrame" and options.LocalOffset) or DEFAULT_LOCAL_OFFSET,
		TrailConnection = nil,
		TrailElapsed = 0,
		TrailInterval = DEFAULT_TRAIL_INTERVAL,
		LastTrailPosition = rootPart.Position,
		LastTrailDirection = initialLook,
		Destroyed = false,
		Stopped = false,
		StartupPlayed = false,
		DashPlayed = false,
	}

	disableVisuals(followModel)
	disableVisuals(emitDash)

	if not attachFollow(state, options) then
		destroyRuntimeState(state)
		logWarn("Flame Dash follow attach failed.")
		return nil
	end

	enableVisuals(followModel)
	logInfo("runtime created root=%s", rootPart:GetFullName())
	return state
end

local function getOrCreateRuntimeState(options)
	if type(options) == "table" and isLiveState(options.RuntimeState) then
		return options.RuntimeState
	end

	return createRuntimeState(options)
end

local function updateRuntimeTransform(state, options)
	if not isLiveState(state) then
		return false
	end

	if type(options) == "table" and typeof(options.LocalOffset) == "CFrame" then
		state.LocalOffset = options.LocalOffset
	end

	if type(options) == "table" and tonumber(options.TrailInterval) then
		state.TrailInterval = math.max(0.01, tonumber(options.TrailInterval))
	end

	if not state.FollowWeld or state.FollowWeld.Parent == nil then
		return attachFollow(state, options)
	end

	return true
end

local function stopRuntimeState(state, options)
	if not isLiveState(state) then
		return false
	end

	if state.Stopped then
		return false
	end

	state.Stopped = true
	disconnectTrailLoop(state)

	if type(options) == "table" and options.ImmediateCleanup == true then
		destroyRuntimeState(state)
		return true
	end

	detachFollow(state)
	snapToFinal(state, options)

	local fadeTime = math.max(0, tonumber(type(options) == "table" and options.FadeTime) or ACTIVE_FADE_TIME)
	local holdTime = math.max(0, tonumber(type(options) == "table" and options.HoldTime) or ACTIVE_HOLD_TIME)

	fadeOut(state.FollowModel)
	fadeOut(state.EmitDash)

	scheduleDestroy(state, fadeTime + holdTime)
	return true
end

function FlameDashVfx.PlayFlameDashStartup(options)
	local state = getOrCreateRuntimeState(options)
	if not state then
		return nil
	end

	updateRuntimeTransform(state, options)

	if not state.StartupPlayed and state.EmitStartup then
		emitVisuals(state.EmitStartup, tonumber(type(options) == "table" and options.EmitCount) or STARTUP_EMIT_COUNT)
		state.StartupPlayed = true

		-- make the wind/trail begin with the startup instead of after it
		enableVisuals(state.EmitDash)
		spawnTrailBurst(state, options)
	end

	enableVisuals(state.FollowModel)
	return state
end

local function spawnInitialTrailStack(state, options)
	if not isLiveState(state) then
		return
	end

	-- first burst at current position
	spawnTrailBurst(state, options)

	-- second burst slightly behind
	spawnTrailBurst(state, {
		TrailOffset = CFrame.new(0, 0, -1.5),
		EmitCount = tonumber(type(options) == "table" and options.EmitCount) or DASH_EMIT_COUNT,
		TrailLifetime = tonumber(type(options) == "table" and options.TrailLifetime) or DEFAULT_TRAIL_LIFETIME
	})

	-- third burst a bit farther behind
	spawnTrailBurst(state, {
		TrailOffset = CFrame.new(0, 0, -3),
		EmitCount = tonumber(type(options) == "table" and options.EmitCount) or DASH_EMIT_COUNT,
		TrailLifetime = tonumber(type(options) == "table" and options.TrailLifetime) or DEFAULT_TRAIL_LIFETIME
	})
end

function FlameDashVfx.StartFlameDashPart(options)
	local state = getOrCreateRuntimeState(options)
	if not state then
		return nil
	end

	updateRuntimeTransform(state, options)

	enableVisuals(state.FollowModel)
	enableVisuals(state.EmitDash)

	if not state.DashPlayed then
		state.DashPlayed = true

		-- attached dash emission immediately
		emitVisuals(state.EmitDash, tonumber(type(options) == "table" and options.EmitCount) or DASH_EMIT_COUNT)

		-- pre-seed trail so wind appears right away with the first flames
		spawnInitialTrailStack(state, options)
	end

	ensureTrailLoop(state, options)

	return state
end

function FlameDashVfx.StartFlameDashHead(options)
	local state = getOrCreateRuntimeState(options)
	if not state then
		return nil
	end

	updateRuntimeTransform(state, options)
	enableVisuals(state.FollowModel)
	return state
end

function FlameDashVfx.UpdateFlameDashPart(state, options)
	return updateRuntimeTransform(state, options)
end

function FlameDashVfx.UpdateFlameDashHead(state, options)
	return updateRuntimeTransform(state, options)
end

function FlameDashVfx.StopFlameDashPart(state, options)
	return stopRuntimeState(state, options)
end

function FlameDashVfx.StopFlameDashHead(state, options)
	return stopRuntimeState(state, options)
end

function FlameDashVfx.StopFlameDashStartup(state, options)
	if not isLiveState(state) then
		return false
	end

	if type(options) ~= "table" then
		options = {}
	end

	options = table.clone(options)
	options.FadeTime = tonumber(options.FadeTime) or STARTUP_FADE_TIME
	options.HoldTime = tonumber(options.HoldTime) or STARTUP_HOLD_TIME

	return stopRuntimeState(state, options)
end

function FlameDashVfx.PlayStartup(options)
	return FlameDashVfx.PlayFlameDashStartup(options)
end

function FlameDashVfx.StopStartup(state, options)
	return FlameDashVfx.StopFlameDashStartup(state, options)
end

function FlameDashVfx.StartBody(options)
	return FlameDashVfx.StartFlameDashHead(options)
end

function FlameDashVfx.UpdateBody(state, options)
	return FlameDashVfx.UpdateFlameDashHead(state, options)
end

function FlameDashVfx.StopBody(state, options)
	return FlameDashVfx.StopFlameDashHead(state, options)
end

function FlameDashVfx.StartTrail(options)
	return FlameDashVfx.StartFlameDashPart(options)
end

function FlameDashVfx.UpdateTrail(state, options)
	return FlameDashVfx.UpdateFlameDashPart(state, options)
end

function FlameDashVfx.StopTrail(state, options)
	return FlameDashVfx.StopFlameDashPart(state, options)
end

return FlameDashVfx