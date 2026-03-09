local parent = script.Parent.Modules

local function requireModules()
	local modules = {}
	local retries = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(modules, child)
		end
	end
	local function tryRequire(module)
		local success, result = pcall(require, module)
		return success, result
	end
	while #modules > 0 do
		for i = #modules, 1, -1 do
			local module = modules[i]
			local success, result = tryRequire(module)

			if success then
				print("✅Loaded module:", module.Name)
				table.remove(modules, i) 
			else
				wait(1)
				print("❌Failed to load module:", module.Name, "Retrying.")
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
