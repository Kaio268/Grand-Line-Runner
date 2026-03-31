-- FireBurstVfx.lua
-- Isolated VFX for FireBurst (Mera Mera no Mi).
-- One self-contained module. If this crashes, FlameDash is unaffected.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local VfxCommon = require(script.Parent:WaitForChild("VfxCommon"))

local ASSET_ROOT_SEGMENTS = { "Assets", "VFX", "Mera" }
local EFFECT_CANDIDATES = { "Flame burst", "Flame Burst" }
local STARTUP_CHILD_CANDIDATES = { "Start up", "Startup" }
local BURST_CHILD_CANDIDATES = { "Burst", "FX" }

local DEFAULT_STARTUP_LIFETIME = 0.55
local DEFAULT_STARTUP_FOLLOW = 0.22
local DEFAULT_STARTUP_EMIT_COUNT = 6
local DEFAULT_BURST_EMIT_COUNT = 15
local DEFAULT_BURST_CLEANUP_HOLD = 2.0

local FireBurstVfx = {}

local function findBurstRoot()
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
	return nil, "Flame burst child not found in Assets/VFX/Mera"
end

-- Play the startup (charge) effect attached to rootPart.
-- Returns a state table that can be passed to StopState.
function FireBurstVfx.PlayStartup(options)
	local rootPart = options and options.RootPart
	if not rootPart or not rootPart.Parent then
		print("[MERA VFX] FireBurst start skip reason=no_root")
		return nil
	end

	print("[MERA VFX] FireBurst start received")

	local burstRoot, err = findBurstRoot()
	if not burstRoot then
		print("[MERA VFX] FireBurst startup asset not found reason=" .. tostring(err))
		return nil
	end

	local startupChild = VfxCommon.FindChild(burstRoot, STARTUP_CHILD_CANDIDATES)
	if not startupChild then
		print("[MERA VFX] FireBurst startup child not found candidates=" .. table.concat(STARTUP_CHILD_CANDIDATES, ","))
		return nil
	end

	print("[MERA VFX] FireBurst asset resolved path=Assets/VFX/Mera/" .. burstRoot.Name .. "/" .. startupChild.Name)

	local clone = VfxCommon.Clone(startupChild, workspace)
	if not clone then
		print("[MERA VFX] FireBurst startup clone failed")
		return nil
	end

	-- Position at the player root.
	if clone:IsA("BasePart") then
		clone.CFrame = rootPart.CFrame
		clone.Anchored = true
	elseif clone:IsA("Model") then
		if clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(rootPart.CFrame)
		end
		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
	end

	VfxCommon.EnableEffects(clone)
	VfxCommon.EmitAll(clone, DEFAULT_STARTUP_EMIT_COUNT)

	local lifetime = math.max(0.25, tonumber(options and options.Lifetime) or DEFAULT_STARTUP_LIFETIME)
	local followDuration = math.max(0, tonumber(options and options.FollowDuration) or DEFAULT_STARTUP_FOLLOW)

	local state = {
		Clone = clone,
		StartedAt = os.clock(),
		FollowConnection = nil,
	}

	-- Follow the player for a short window so the effect tracks movement.
	if followDuration > 0 then
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not clone.Parent then
				conn:Disconnect()
				return
			end
			if not rootPart.Parent then
				conn:Disconnect()
				return
			end
			if os.clock() - state.StartedAt >= followDuration then
				conn:Disconnect()
				state.FollowConnection = nil
				return
			end
			if clone:IsA("BasePart") then
				clone.CFrame = rootPart.CFrame
			elseif clone:IsA("Model") and clone.PrimaryPart then
				clone:SetPrimaryPartCFrame(rootPart.CFrame)
			end
		end)
		state.FollowConnection = conn
	end

	Debris:AddItem(clone, lifetime + 0.5)
	return state
end

-- Stop a startup state early (e.g. cancelled or burst fired).
function FireBurstVfx.StopState(state, options)
	if type(state) ~= "table" then
		return
	end
	if typeof(state.FollowConnection) == "RBXScriptConnection" then
		state.FollowConnection:Disconnect()
		state.FollowConnection = nil
	end
	local clone = state.Clone
	state.Clone = nil
	if clone and clone.Parent then
		if options and options.ImmediateCleanup then
			VfxCommon.Cleanup(clone, 0)
		else
			VfxCommon.FadeAndCleanup(clone, tonumber(options and options.FadeTime) or 0.1, 0.2)
		end
	end
end

-- Play the release burst at the player's position.
function FireBurstVfx.PlayBurst(options)
	local rootPart = options and options.RootPart
	if not rootPart or not rootPart.Parent then
		print("[MERA VFX] FireBurst release skip reason=no_root")
		return false
	end

	print("[MERA VFX] FireBurst release received")

	local burstRoot, err = findBurstRoot()
	if not burstRoot then
		print("[MERA VFX] FireBurst burst asset not found reason=" .. tostring(err))
		return false
	end

	local burstChild = VfxCommon.FindChild(burstRoot, BURST_CHILD_CANDIDATES)
	local effectSource = burstChild or burstRoot

	print(
		"[MERA VFX] FireBurst asset resolved path=Assets/VFX/Mera/"
			.. burstRoot.Name
			.. (burstChild and "/" .. burstChild.Name or " (root)")
	)
	print("[MERA VFX] FireBurst emit begin")

	local clone = VfxCommon.Clone(effectSource, workspace)
	if not clone then
		print("[MERA VFX] FireBurst clone failed")
		return false
	end

	-- Anchor and position at the burst origin.
	local origin = rootPart.Position
	if clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(origin)
		clone.Anchored = true
	elseif clone:IsA("Model") then
		if clone.PrimaryPart then
			clone:SetPrimaryPartCFrame(CFrame.new(origin))
		else
			-- Reposition all parts relative to origin.
			local firstPart = nil
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") then
					if not firstPart then
						firstPart = desc
					end
					desc.Anchored = true
				end
			end
			if firstPart then
				local offset = CFrame.new(origin) * firstPart.CFrame:Inverse()
				for _, desc in ipairs(clone:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.CFrame = offset * desc.CFrame
					end
				end
			end
		end
	end

	VfxCommon.EnableEffects(clone)

	-- Scale emit count with ability radius for bigger explosions at higher radius.
	local radius = math.max(1, tonumber(options and options.Radius) or 10)
	local emitCount = math.floor(DEFAULT_BURST_EMIT_COUNT * math.max(1, radius / 10))
	VfxCommon.EmitAll(clone, emitCount)

	local duration = math.max(0.3, tonumber(options and options.Duration) or 0.6)

	-- Stop new particles after the ability duration, then wait for existing ones to fade.
	task.delay(duration, function()
		if clone and clone.Parent then
			VfxCommon.DisableEffects(clone)
		end
	end)

	Debris:AddItem(clone, duration + DEFAULT_BURST_CLEANUP_HOLD)

	print("[MERA VFX] FireBurst cleanup complete scheduled=+" .. string.format("%.1f", duration + DEFAULT_BURST_CLEANUP_HOLD) .. "s")
	return true
end

return FireBurstVfx
