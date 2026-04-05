--[[
	Neutral FlameDash VFX backend.

	This keeps the FlameDash VFX API stable while leaving the move with no
	custom visuals so it can be rebuilt from a clean baseline.
]]

local VfxCommon = require(script.Parent:WaitForChild("VfxCommon"))

local FlameDashVfx = {}
local FLAME_DASH_DEBUG = true
local FLAME_DASH_LOG_PREFIX = "[MERA VFX][FlameDash]"

local function flameDashLog(message, ...)
	if FLAME_DASH_DEBUG ~= true then
		return
	end

	if select("#", ...) > 0 then
		print(FLAME_DASH_LOG_PREFIX, string.format(message, ...))
	else
		print(FLAME_DASH_LOG_PREFIX, tostring(message))
	end
end

local function flameDashWarn(message, ...)
	if select("#", ...) > 0 then
		warn(FLAME_DASH_LOG_PREFIX, string.format(message, ...))
	else
		warn(FLAME_DASH_LOG_PREFIX, tostring(message))
	end
end

local function attachToRoot(rootPart, offset)
	local attachment = Instance.new("Attachment")
	attachment.Position = offset or Vector3.new(0, 0, 0)
	attachment.Parent = rootPart
	return attachment
end

local function getAsset()
	return VfxCommon.FindAsset("Assets", "VFX", "Mera", "Flame Dash", "Dash")
end

local function getDirection(direction, rootPart)
	local resolved = typeof(direction) == "Vector3" and Vector3.new(direction.X, 0, direction.Z) or nil
	if resolved and resolved.Magnitude > 0.001 then
		return resolved.Unit
	end

	if rootPart and rootPart:IsA("BasePart") then
		local lookVector = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		if lookVector.Magnitude > 0.001 then
			return lookVector.Unit
		end
	end

	return Vector3.new(0, 0, -1)
end

local function getPosition(options, rootPart)
	if typeof(options) == "table" and typeof(options.Position) == "Vector3" then
		return options.Position
	end

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end

	return nil
end

local function applyTransform(state, options)
	if type(state) ~= "table" or state.Destroyed == true then
		return false
	end

	local model = state.Model
	if not model or not model.Parent then
		state.Destroyed = true
		return false
	end

	local rootPart = state.RootPart
	local position = getPosition(options, rootPart)
	if typeof(position) ~= "Vector3" then
		return false
	end

	local direction = getDirection(type(options) == "table" and options.Direction or nil, rootPart)
	local pivotCFrame = CFrame.lookAt(position, position + direction)
	local localOffset = state.LocalOffset or CFrame.new()
	model:PivotTo(pivotCFrame * localOffset)
	state.LastPosition = position
	state.LastDirection = direction
	return true
end

local function createState(kind, model, rootPart, localOffset, attachment)
	return {
		Kind = kind,
		Model = model,
		Clone = model,
		RootPart = rootPart,
		LocalOffset = localOffset or CFrame.new(),
		Attachment = attachment,
		Destroyed = false,
		Active = true,
	}
end

local function stopState(state, options)
	if type(state) ~= "table" then
		if typeof(state) == "Instance" and state.Parent then
			local immediateCleanup = type(options) == "table" and options.ImmediateCleanup == true
			if immediateCleanup then
				state:Destroy()
			else
				VfxCommon.FadeAndCleanup(state, tonumber(options and options.FadeTime) or 0.1, 0.2)
			end
			return true
		end

		return false
	end

	if state.Destroyed == true then
		return false
	end

	state.Destroyed = true
	state.Active = false

	if state.Attachment then
		state.Attachment:Destroy()
		state.Attachment = nil
	end

	local model = state.Model or state.Clone
	state.Model = nil
	state.Clone = nil

	if model and model.Parent then
		local immediateCleanup = type(options) == "table" and options.ImmediateCleanup == true
		if immediateCleanup then
			model:Destroy()
		else
			VfxCommon.FadeAndCleanup(model, tonumber(options and options.FadeTime) or 0.1, 0.2)
		end
	end

	return true
end

local function startMountedState(kind, options, localOffset, attachmentOffset)
	local root = type(options) == "table" and options.RootPart or nil
	if not root then
		flameDashWarn("%s skipped because RootPart was missing.", kind)
		return nil
	end

	local asset = getAsset()
	if not asset then
		flameDashWarn("%s skipped because the Dash asset could not be found.", kind)
		return nil
	end

	local clone = VfxCommon.Clone(asset, workspace)
	if not clone then
		flameDashWarn("%s skipped because the Dash asset failed to clone.", kind)
		return nil
	end

	VfxCommon.EnableEffects(clone)

	local attachment = attachToRoot(root, attachmentOffset)
	local state = createState(kind, clone, root, localOffset, attachment)
	if not applyTransform(state, options) then
		stopState(state, {
			ImmediateCleanup = true,
		})
		flameDashWarn("%s failed initial placement and was cleaned up immediately.", kind)
		return nil
	end

	flameDashLog("%s started root=%s", kind, root:GetFullName())
	return state
end

function FlameDashVfx.PlayFlameDashStartup(options)
	local root = type(options) == "table" and options.RootPart or nil
	if not root then
		flameDashWarn("Startup skipped because RootPart was missing.")
		return nil
	end

	local asset = getAsset()
	if not asset then
		flameDashWarn("Startup skipped because the Dash asset could not be found.")
		return nil
	end

	local clone = VfxCommon.Clone(asset, workspace)
	if not clone then
		flameDashWarn("Startup skipped because the Dash asset failed to clone.")
		return nil
	end

	local state = createState("FlameDashStartup", clone, root, CFrame.new())
	if not applyTransform(state, options) then
		stopState(state, {
			ImmediateCleanup = true,
		})
		flameDashWarn("Startup failed initial placement and was cleaned up immediately.")
		return nil
	end

	VfxCommon.EnableEffects(clone)
	VfxCommon.EmitAll(clone, 25)
	flameDashLog("Startup started root=%s", root:GetFullName())

	return state
end

function FlameDashVfx.StartFlameDashPart(options)
	return startMountedState("FlameDashMountedTrail", options, CFrame.new(), Vector3.new())
end

function FlameDashVfx.StartFlameDashHead(options)
	return startMountedState("FlameDashMountedBody", options, CFrame.new(0, 0, -2), Vector3.new(0, 0, -2))
end

function FlameDashVfx.UpdateFlameDashPart(state, options)
	return applyTransform(state, options)
end

function FlameDashVfx.UpdateFlameDashHead(state, options)
	return applyTransform(state, options)
end

function FlameDashVfx.StopFlameDashPart(state, options)
	return stopState(state, options)
end

function FlameDashVfx.StopFlameDashHead(state, options)
	return stopState(state, options)
end

function FlameDashVfx.StopFlameDashStartup(state, options)
	return stopState(state, options)
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
