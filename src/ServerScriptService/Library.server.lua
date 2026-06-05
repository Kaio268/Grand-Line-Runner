local parent = script.Parent.Modules
local LOG_LOADED_MODULES = game:GetAttribute("LibraryModuleLoadDebug") == true

local function requireModules()
	local modules = {}
	local retries = {}
	local failureCounts = {}

	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(modules, child)
		end
	end

	local function tryRequire(module)
		return xpcall(function()
			return require(module)
		end, debug.traceback)
	end

	local function summarizeError(result)
		local text = tostring(result)
		return text:match("([^\n]+)") or text
	end

	while #modules > 0 do
		for index = #modules, 1, -1 do
			local module = modules[index]
			local success, result = tryRequire(module)

			if success then
				if LOG_LOADED_MODULES then
					print("[Library] Loaded module:", module.Name)
				end
				table.remove(modules, index)
			else
				failureCounts[module] = (failureCounts[module] or 0) + 1
				if failureCounts[module] == 1 then
					warn(("[Library] Failed to load module %s (%s):\n%s"):format(
						module.Name,
						module:GetFullName(),
						tostring(result)
					))
				else
					warn(("[Library] Failed to load module %s. Retrying. Attempt=%d Error=%s"):format(
						module.Name,
						failureCounts[module],
						summarizeError(result)
					))
				end

				wait(1)
				table.insert(retries, module)
				wait(1)
			end
		end
		modules = retries
		retries = {}
	end
end

requireModules()
