-- FlameDashVfx.lua
-- Isolated VFX for FlameDash (Mera Mera no Mi).
-- One self-contained module. If this crashes, FireBurst is unaffected.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local VfxCommon = require(script.Parent:WaitForChild("VfxCommon"))

local ASSET_ROOT_SEGMENTS = { "Assets", "VFX", "Mera" }
local EFFECT_CANDIDATES = { "Flame Dash" }
local STARTUP_CHILD_CANDIDATES = { "Startup", "Start up", "FX" }
local BODY_CHILD_CANDIDATES = { "Dash", "FX" }
local TRAIL_CHILD_CANDIDATES = { "Part", "FX2", "Trail" }

local STARTUP_LIFETIME = 0.35
local TRAIL_STAMP_INTERVAL = 0.045 -- seconds between trail stamps
local TRAIL_STAMP_LIFETIME = 0.28
local TRAIL_STAMP_EMIT_COUNT = 8
local TRAIL_BACK_OFFSET = 1.7
local TRAIL_UP_OFFSET = -2.35

local FlameDashVfx = {}

local function findDashRoot()
	local meraRoot = VfxCommon.FindAsset(table.unpack(ASSET_ROOT_SEGMENTS))
	if not meraRoot then
		return nil, "Assets/VFX/Mera not found"
	end
	for _, name in ipairs(EFFECT_CANDIDATES) do
		local child = meraRoot:FindFirstChild(name)
		if child then
			return child, nil
		end
	end
	return nil, "Flame Dash child not found in Assets/VFX/Mera"
end

-- Position a clone (BasePart or Model) at the given CFrame.
local function placeClonoAt(clone, cf)
	if clone:IsA("BasePart") then
		clone.CFrame = cf
	elseif clone:IsA("Model") then
		if clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(cf)
		else
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.CFrame = cf
					break -- only move first to keep relative offsets
				end
			end
		end
	end
end

-- Anchor all BaseParts under a clone so they don't fall.
local function anchorClone(clone)
	if clone:IsA("BasePart") then
		clone.Anchored = true
	end
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end
end

-- ─── Startup ────────────────────────────────────────────────────────────────

-- Play the short ignition / startup flash at the player's root.
-- Returns a state table for cleanup.
function FlameDashVfx.PlayStartup(options)
	local rootPart = options and options.RootPart
	if not rootPart or not rootPart.Parent then
		print("[MERA VFX] FlameDash start skip reason=no_root")
		return nil
	end

	print("[MERA VFX] FlameDash start received")

	local dashRoot, err = findDashRoot()
	if not dashRoot then
		print("[MERA VFX] FlameDash startup asset not found reason=" .. tostring(err))
		return nil
	end

	local startupChild = VfxCommon.FindChild(dashRoot, STARTUP_CHILD_CANDIDATES)
	if not startupChild then
		print("[MERA VFX] FlameDash startup child not found candidates=" .. table.concat(STARTUP_CHILD_CANDIDATES, ","))
		return nil
	end

	print("[MERA VFX] FlameDash asset resolved path=Assets/VFX/Mera/" .. dashRoot.Name .. "/" .. startupChild.Name)
	print("[MERA VFX] FlameDash body attach begin phase=startup")

	local clone = VfxCommon.Clone(startupChild, workspace)
	if not clone then
		print("[MERA VFX] FlameDash startup clone failed")
		return nil
	end

	anchorClone(clone)
	placeClonoAt(clone, rootPart.CFrame)
	VfxCommon.EnableEffects(clone)
	Debris:AddItem(clone, STARTUP_LIFETIME + 0.5)

	return { Type = "startup", Clone = clone }
end

-- Stop a startup state.
function FlameDashVfx.StopStartup(state, options)
	if type(state) ~= "table" or state.Type ~= "startup" then
		return
	end
	local clone = state.Clone
	state.Clone = nil
	if clone and clone.Parent then
		if options and options.ImmediateCleanup then
			VfxCommon.Cleanup(clone, 0)
		else
			VfxCommon.FadeAndCleanup(clone, tonumber(options and options.FadeTime) or 0.08, 0.25)
		end
	end
end

-- ─── Body (Head) ─────────────────────────────────────────────────────────────

-- Attach the body flame to the player for the duration of the dash.
-- The clone follows rootPart each Heartbeat while active.
-- Returns a state table.
function FlameDashVfx.StartBody(options)
	local rootPart = options and options.RootPart
	if not rootPart or not rootPart.Parent then
		return nil
	end

	local dashRoot, err = findDashRoot()
	if not dashRoot then
		print("[MERA VFX] FlameDash body asset not found reason=" .. tostring(err))
		return nil
	end

	local bodyChild = VfxCommon.FindChild(dashRoot, BODY_CHILD_CANDIDATES)
	if not bodyChild then
		print("[MERA VFX] FlameDash body child not found candidates=" .. table.concat(BODY_CHILD_CANDIDATES, ","))
		return nil
	end

	local clone = VfxCommon.Clone(bodyChild, workspace)
	if not clone then
		return nil
	end

	anchorClone(clone)
	placeClonoAt(clone, rootPart.CFrame)
	VfxCommon.EnableEffects(clone)

	local state = {
		Type = "body",
		Clone = clone,
		RootPart = rootPart,
		Active = true,
		Connection = nil,
	}

	print("[MERA VFX] FlameDash body attach begin phase=active")

	-- Follow the player while the dash is active.
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not state.Active then
			conn:Disconnect()
			return
		end
		if not clone.Parent or not rootPart.Parent then
			state.Active = false
			conn:Disconnect()
			return
		end
		placeClonoAt(clone, rootPart.CFrame)
	end)
	state.Connection = conn

	return state
end

-- Returns true if the body state is still valid.
function FlameDashVfx.UpdateBody(state, _options)
	if type(state) ~= "table" or not state.Active then
		return false
	end
	local clone = state.Clone
	if not clone or not clone.Parent then
		return false
	end
	return true
end

-- Stop the body flame with optional fade.
function FlameDashVfx.StopBody(state, options)
	if type(state) ~= "table" then
		return
	end
	state.Active = false
	if typeof(state.Connection) == "RBXScriptConnection" then
		state.Connection:Disconnect()
		state.Connection = nil
	end
	local clone = state.Clone
	state.Clone = nil
	if clone and clone.Parent then
		if options and options.ImmediateCleanup then
			VfxCommon.Cleanup(clone, 0)
		else
			VfxCommon.FadeAndCleanup(clone, tonumber(options and options.FadeTime) or 0.12, 0.4)
		end
	end
end

-- ─── Trail (Part) ────────────────────────────────────────────────────────────

-- Start a stamp-based trail that follows the player's dash path.
-- Emits discrete effect clones behind the player at TRAIL_STAMP_INTERVAL.
-- Returns a state table.
function FlameDashVfx.StartTrail(options)
	local rootPart = options and options.RootPart
	if not rootPart or not rootPart.Parent then
		return nil
	end

	local dashRoot, err = findDashRoot()
	if not dashRoot then
		print("[MERA VFX] FlameDash trail asset not found reason=" .. tostring(err))
		return nil
	end

	local trailChild = VfxCommon.FindChild(dashRoot, TRAIL_CHILD_CANDIDATES)
	if not trailChild then
		print("[MERA VFX] FlameDash trail child not found candidates=" .. table.concat(TRAIL_CHILD_CANDIDATES, ","))
		return nil
	end

	print("[MERA VFX] FlameDash asset resolved path=Assets/VFX/Mera/" .. dashRoot.Name .. "/" .. trailChild.Name)
	print("[MERA VFX] FlameDash trail begin")

	local state = {
		Type = "trail",
		Active = true,
		RootPart = rootPart,
		TrailAsset = trailChild,
		Direction = typeof(options and options.Direction) == "Vector3" and options.Direction or Vector3.new(0, 0, -1),
		LastStampAt = os.clock(),
		Connection = nil,
	}

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not state.Active then
			conn:Disconnect()
			state.Connection = nil
			return
		end
		if not rootPart.Parent then
			return
		end

		local now = os.clock()
		if now - state.LastStampAt < TRAIL_STAMP_INTERVAL then
			return
		end
		state.LastStampAt = now

		-- Place the stamp behind the player along the dash direction.
		local dir = typeof(state.Direction) == "Vector3" and state.Direction.Magnitude > 0.01 and state.Direction.Unit
			or Vector3.new(0, 0, -1)
		local stampCF = CFrame.new(rootPart.Position + (-dir) * TRAIL_BACK_OFFSET + Vector3.new(0, TRAIL_UP_OFFSET, 0))

		local stampClone = VfxCommon.Clone(state.TrailAsset, workspace)
		if stampClone then
			anchorClone(stampClone)
			placeClonoAt(stampClone, stampCF)
			VfxCommon.EnableEffects(stampClone)
			VfxCommon.EmitAll(stampClone, TRAIL_STAMP_EMIT_COUNT)
			Debris:AddItem(stampClone, TRAIL_STAMP_LIFETIME)
		end
	end)
	state.Connection = conn

	return state
end

-- Update trail direction from caller (called each Heartbeat by MeraPresentationClient).
function FlameDashVfx.UpdateTrail(state, options)
	if type(state) ~= "table" or not state.Active then
		return false
	end
	if options and typeof(options.Direction) == "Vector3" then
		state.Direction = options.Direction
	end
	return true
end

-- Stop the trail. Existing stamps fade naturally via Debris.
function FlameDashVfx.StopTrail(state, _options)
	if type(state) ~= "table" then
		return
	end
	state.Active = false
	if typeof(state.Connection) == "RBXScriptConnection" then
		state.Connection:Disconnect()
		state.Connection = nil
	end
	state.TrailAsset = nil
	print("[MERA VFX] FlameDash cleanup complete")
end

-- ─── Generic stop ────────────────────────────────────────────────────────────

-- Stop any state returned by a FlameDash VFX function.
function FlameDashVfx.StopState(state, options)
	if type(state) ~= "table" then
		return
	end
	local t = state.Type
	if t == "startup" then
		FlameDashVfx.StopStartup(state, options)
	elseif t == "body" then
		FlameDashVfx.StopBody(state, options)
	elseif t == "trail" then
		FlameDashVfx.StopTrail(state, options)
	end
end

return FlameDashVfx
