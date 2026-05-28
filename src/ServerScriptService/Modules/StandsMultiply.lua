local MAX_LEVEL = 50
local MULTIPLIER_STEP_PER_LEVEL = 0.08

local multipliers = {}

for level = 1, MAX_LEVEL do
	multipliers[tostring(level)] = math.floor((1 + MULTIPLIER_STEP_PER_LEVEL * (level - 1)) * 100 + 0.5) / 100
end

return multipliers
