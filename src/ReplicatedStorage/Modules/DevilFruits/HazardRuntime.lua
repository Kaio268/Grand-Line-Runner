local HazardRuntime = {}

local controllersByRoot = setmetatable({}, { __mode = "k" })

function HazardRuntime.Register(rootInstance, controller)
	if typeof(rootInstance) ~= "Instance" or type(controller) ~= "table" then
		return false
	end

	controllersByRoot[rootInstance] = controller
	return true
end

function HazardRuntime.Unregister(rootInstance)
	if typeof(rootInstance) ~= "Instance" then
		return
	end

	controllersByRoot[rootInstance] = nil
end

function HazardRuntime.GetController(instance)
	local current = instance

	while current and current ~= workspace do
		local controller = controllersByRoot[current]
		if controller then
			return current, controller
		end

		current = current.Parent
	end

	return nil, nil
end

function HazardRuntime.Freeze(instance, duration)
	local rootInstance, controller = HazardRuntime.GetController(instance)
	if not controller or typeof(controller.Freeze) ~= "function" then
		return false, rootInstance, controller
	end

	return controller:Freeze(duration) ~= false, rootInstance, controller
end

function HazardRuntime.Destroy(instance)
	local rootInstance, controller = HazardRuntime.GetController(instance)
	local targetInstance = rootInstance or instance
	if typeof(targetInstance) ~= "Instance" then
		return false, rootInstance, controller
	end

	if controller and typeof(controller.Destroy) == "function" then
		controller:Destroy()
	end

	if targetInstance.Parent then
		targetInstance:Destroy()
	end

	return true, rootInstance, controller
end

return HazardRuntime
