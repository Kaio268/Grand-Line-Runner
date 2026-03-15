local ProtectionRuntime = {}

local evaluators = {}

function ProtectionRuntime.Register(name, evaluator)
	if typeof(name) ~= "string" or name == "" then
		return false
	end

	if typeof(evaluator) ~= "function" then
		return false
	end

	evaluators[name] = evaluator
	return true
end

function ProtectionRuntime.Unregister(name)
	if typeof(name) ~= "string" then
		return
	end

	evaluators[name] = nil
end

function ProtectionRuntime.IsProtected(targetPlayer, position, context)
	for _, evaluator in pairs(evaluators) do
		local ok, isProtected = pcall(evaluator, targetPlayer, position, context)
		if ok and isProtected then
			return true
		end
	end

	return false
end

return ProtectionRuntime
