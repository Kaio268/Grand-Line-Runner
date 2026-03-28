local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Registry = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Registry"))
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DevilFruitLogger"))

local ClientFolder = script.Parent
local FruitsFolder = ClientFolder:WaitForChild("Fruits")

local FruitModuleLoader = {}
FruitModuleLoader.__index = FruitModuleLoader

local function safeCall(scope, callback)
	local ok, result = pcall(callback)
	if not ok then
		DevilFruitLogger.Warn("CLIENT", "fruit module scope=%s failed: %s", tostring(scope), tostring(result))
		return false, result
	end

	return true, result
end

function FruitModuleLoader.new(config)
	local self = setmetatable({}, FruitModuleLoader)
	self.config = config or {}
	self.loadedModules = {}
	self.loadedControllers = {}
	return self
end

function FruitModuleLoader:GetModule(fruitIdentifier)
	local fruitEntry = Registry.GetFruit(fruitIdentifier)
	if not fruitEntry then
		return nil
	end

	local fruitKey = fruitEntry.FruitKey
	local cached = self.loadedModules[fruitKey]
	if cached ~= nil then
		return cached or nil
	end

	local moduleName = Registry.GetClientModuleName(fruitEntry.DisplayName)
	if typeof(moduleName) ~= "string" or moduleName == "" then
		self.loadedModules[fruitKey] = false
		return nil
	end

	local moduleScript = FruitsFolder:FindFirstChild(moduleName)
	if not moduleScript then
		self.loadedModules[fruitKey] = false
		return nil
	end

	local ok, loadedModule = safeCall("require:" .. moduleName, function()
		return require(moduleScript)
	end)
	if not ok then
		self.loadedModules[fruitKey] = false
		return nil
	end

	self.loadedModules[fruitKey] = loadedModule
	return loadedModule
end

function FruitModuleLoader:GetController(fruitIdentifier)
	local fruitEntry = Registry.GetFruit(fruitIdentifier)
	if not fruitEntry then
		return nil
	end

	local fruitKey = fruitEntry.FruitKey
	local cached = self.loadedControllers[fruitKey]
	if cached ~= nil then
		return cached or nil
	end

	local module = self:GetModule(fruitEntry.DisplayName)
	if not module then
		self.loadedControllers[fruitKey] = false
		return nil
	end

	local controller
	if typeof(module.Create) == "function" then
		local ok, result = safeCall("create:" .. fruitKey, function()
			return module.Create(self.config, fruitEntry)
		end)
		if ok then
			controller = result
		end
	else
		controller = module
	end

	self.loadedControllers[fruitKey] = controller or false
	return controller
end

function FruitModuleLoader:CallControllerMethod(fruitIdentifier, methodName, ...)
	local controller = self:GetController(fruitIdentifier)
	if not controller then
		return false, nil
	end

	local method = controller[methodName]
	if typeof(method) ~= "function" then
		return false, nil
	end

	local packed = table.pack(...)
	local ok, result = safeCall(
		string.format("%s:%s", tostring(fruitIdentifier), tostring(methodName)),
		function()
			return method(controller, table.unpack(packed, 1, packed.n))
		end
	)
	if not ok then
		return false, nil
	end

	return true, result
end

function FruitModuleLoader:ForEachLoadedController(methodName, ...)
	local packed = table.pack(...)
	for fruitKey, controller in pairs(self.loadedControllers) do
		if controller and typeof(controller[methodName]) == "function" then
			safeCall(
				string.format("%s:%s", tostring(fruitKey), tostring(methodName)),
				function()
					controller[methodName](controller, table.unpack(packed, 1, packed.n))
				end
			)
		end
	end
end

return FruitModuleLoader
