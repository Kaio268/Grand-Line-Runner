local PerformanceArchitectureFlags = {}

local DEFAULTS = {
	RuntimeSchedulerEnabled = true,
	HazardSchedulerEnabled = true,
	VFXSchedulerEnabled = true,
	UIPerformanceSchedulerEnabled = true,
	RuntimeSchedulerDiagnosticsEnabled = true,
}

function PerformanceArchitectureFlags.IsEnabled(flagName)
	local value = DEFAULTS[tostring(flagName or "")]
	if value == nil then
		return false
	end
	return value == true
end

function PerformanceArchitectureFlags.GetDefaults()
	return table.clone(DEFAULTS)
end

return PerformanceArchitectureFlags
