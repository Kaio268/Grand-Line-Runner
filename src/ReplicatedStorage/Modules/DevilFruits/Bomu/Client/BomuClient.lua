local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local BomuClient = {}
BomuClient.__index = BomuClient

local LAND_MINE_ABILITY = "LandMine"
local LAND_MINE_ACTION_PLACED = "Placed"
local PLACEMENT_PULSE_NAME = "BomuLandMinePlacementPulse"
local PLACEMENT_PULSE_COLOR = Color3.fromRGB(255, 89, 89)
local PLACEMENT_PULSE_TRANSPARENCY = 0.25
local PLACEMENT_PULSE_SIZE = Vector3.new(1.1, 1.1, 1.1)
local PLACEMENT_PULSE_OFFSET = Vector3.new(0, 0.35, 0)
local PLACEMENT_PULSE_SIZE_STEP = Vector3.new(0.18, 0.18, 0.18)
local PLACEMENT_PULSE_TRANSPARENCY_STEP = 0.1
local PLACEMENT_PULSE_STEPS = 6
local PLACEMENT_PULSE_STEP_DELAY = 0.03
local PLACEMENT_PULSE_LIFETIME = 0.3

local function playLandMinePlacementPulse(worldPosition)
	if typeof(worldPosition) ~= "Vector3" then
		return false
	end

	local pulse = Instance.new("Part")
	pulse.Name = PLACEMENT_PULSE_NAME
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanTouch = false
	pulse.CanQuery = false
	pulse.Shape = Enum.PartType.Ball
	pulse.Material = Enum.Material.Neon
	pulse.Color = PLACEMENT_PULSE_COLOR
	pulse.Transparency = PLACEMENT_PULSE_TRANSPARENCY
	pulse.Size = PLACEMENT_PULSE_SIZE
	pulse.CFrame = CFrame.new(worldPosition + PLACEMENT_PULSE_OFFSET)
	pulse.Parent = Workspace

	task.spawn(function()
		for _ = 1, PLACEMENT_PULSE_STEPS do
			if not pulse.Parent then
				break
			end

			pulse.Size += PLACEMENT_PULSE_SIZE_STEP
			pulse.Transparency += PLACEMENT_PULSE_TRANSPARENCY_STEP
			task.wait(PLACEMENT_PULSE_STEP_DELAY)
		end
	end)

	Debris:AddItem(pulse, PLACEMENT_PULSE_LIFETIME)
	return true
end

function BomuClient.Create(config)
	config = config or {}

	local self = setmetatable({}, BomuClient)
	self.player = config.player
	self.playOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or nil
	return self
end

function BomuClient:BeginPredictedRequest(_abilityName, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:BuildRequestPayload(_abilityName, _abilityConfig, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:HandleEffect(_targetPlayer, abilityName, payload)
	if abilityName ~= LAND_MINE_ABILITY or typeof(payload) ~= "table" then
		return false
	end

	if payload.Action ~= LAND_MINE_ACTION_PLACED then
		-- Detonation intentionally falls through so the current generic Bomu
		-- explosion fallback stays in control of that path.
		return false
	end

	local minePosition = payload.MinePosition or payload.OriginPosition
	if not playLandMinePlacementPulse(minePosition) then
		return false
	end

	return true
end

function BomuClient:HandleStateEvent(_eventName, _abilityName, _value, _payload)
	return false
end

function BomuClient:Update()
end

function BomuClient:HandleCharacterRemoving()
end

function BomuClient:HandlePlayerRemoving(_leavingPlayer)
end

return BomuClient
