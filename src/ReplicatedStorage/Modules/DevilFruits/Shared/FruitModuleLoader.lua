local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruits = Modules:WaitForChild("DevilFruits")
local SharedFolder = DevilFruits:WaitForChild("Shared")
local Registry = require(SharedFolder:WaitForChild("Registry"))
local DevilFruitLogger = require(SharedFolder:WaitForChild("DevilFruitLogger"))

local FruitModuleLoader = {}
FruitModuleLoader.__index = FruitModuleLoader

local function getModuleScript(instance)
	if instance and instance:IsA("ModuleScript") then
		return instance
	end

	return nil
end

local function findNamedChild(parent, childName, isLeaf)
	if typeof(parent) ~= "Instance" then
		return nil
	end

	local namedChildren = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName then
			namedChildren[#namedChildren + 1] = child
		end
	end

	if #namedChildren == 0 then
		return nil
	end

	if not isLeaf then
		for _, child in ipairs(namedChildren) do
			if child:IsA("Folder") then
				return child
			end
		end
	end

	if isLeaf then
		for _, child in ipairs(namedChildren) do
			if child:IsA("ModuleScript") then
				return child
			end
		end
	end

	return namedChildren[1]
end

local function findModuleByPath(root, pathSegments)
	local current = root
	local segments = pathSegments or {}
	for index, segment in ipairs(segments) do
		if typeof(current) ~= "Instance" then
			return nil
		end

		current = findNamedChild(current, segment, index == #segments)
		if not current then
			return nil
		end
	end

	return getModuleScript(current)
end

local function findModuleByName(root, moduleName)
	if typeof(root) ~= "Instance" or typeof(moduleName) ~= "string" or moduleName == "" then
		return nil
	end

	local direct = root:FindFirstChild(moduleName)
	if direct and direct:IsA("ModuleScript") then
		return direct
	end

	for _, child in ipairs(root:GetChildren()) do
		if child.Name == moduleName and child:IsA("ModuleScript") then
			return child
		end
	end

	return nil
end

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
	self.loadedModuleSources = {}
	self.loadedControllerSources = {}
	return self
end

function FruitModuleLoader:ResetFruit(fruitIdentifier)
	local fruitEntry = Registry.GetFruit(fruitIdentifier)
	if not fruitEntry then
		return false
	end

	local fruitKey = fruitEntry.FruitKey
	self.loadedModules[fruitKey] = nil
	self.loadedControllers[fruitKey] = nil
	self.loadedModuleSources[fruitKey] = nil
	self.loadedControllerSources[fruitKey] = nil
	DevilFruitLogger.Info("CLIENT", "loader reset fruit=%s", tostring(fruitEntry.DisplayName))
	return true
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

	local moduleScript = findModuleByPath(DevilFruits, Registry.GetClientModulePath(fruitEntry.DisplayName))
	if not moduleScript then
		moduleScript = findModuleByPath(DevilFruits, { "Client", "Fruits", moduleName })
			or findModuleByName(DevilFruits, moduleName)
	end
	if not moduleScript then
		self.loadedModules[fruitKey] = false
		DevilFruitLogger.Warn("CLIENT", "missing fruit module fruit=%s module=%s", fruitEntry.DisplayName, moduleName)
		return nil
	end

	DevilFruitLogger.Info(
		"CLIENT",
		"requiring fruit module fruit=%s module=%s path=%s",
		tostring(fruitEntry.DisplayName),
		tostring(moduleName),
		tostring(moduleScript:GetFullName())
	)
	local ok, loadedModule = safeCall("require:" .. moduleName, function()
		return require(moduleScript)
	end)
	if not ok then
		return nil
	end

	self.loadedModules[fruitKey] = loadedModule
	self.loadedModuleSources[fruitKey] = moduleScript:GetFullName()
	DevilFruitLogger.Info(
		"CLIENT",
		"loaded fruit module fruit=%s module=%s path=%s",
		tostring(fruitEntry.DisplayName),
		tostring(moduleName),
		tostring(moduleScript:GetFullName())
	)
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
		if self.loadedModules[fruitKey] == false then
			self.loadedControllers[fruitKey] = false
		end
		return nil
	end

	local controller
	if typeof(module.Create) == "function" then
		DevilFruitLogger.Info(
			"CLIENT",
			"creating fruit controller fruit=%s source=%s",
			tostring(fruitEntry.DisplayName),
			tostring(self.loadedModuleSources[fruitKey] or "<unknown>")
		)
		local ok, result = safeCall("create:" .. fruitKey, function()
			return module.Create(self.config, fruitEntry)
		end)
		if ok then
			controller = result
		else
			return nil
		end
	else
		controller = module
	end

	self.loadedControllers[fruitKey] = controller or false
	self.loadedControllerSources[fruitKey] = self.loadedModuleSources[fruitKey] or tostring(module)
	if controller then
		DevilFruitLogger.Info(
			"CLIENT",
			"created fruit controller fruit=%s source=%s",
			tostring(fruitEntry.DisplayName),
			tostring(self.loadedControllerSources[fruitKey])
		)
	end
	return controller
end

function FruitModuleLoader:CallControllerMethod(fruitIdentifier, methodName, ...)
	local fruitEntry = Registry.GetFruit(fruitIdentifier)
	local controller = self:GetController(fruitIdentifier)
	if not controller then
		if methodName == "BeginPredictedRequest" or methodName == "BuildRequestPayload" then
			DevilFruitLogger.Warn(
				"REQUEST",
				"controller missing fruit=%s method=%s",
				tostring(fruitIdentifier),
				tostring(methodName)
			)
		end
		return false, nil
	end

	local method = controller[methodName]
	if typeof(method) ~= "function" then
		if methodName == "BeginPredictedRequest" or methodName == "BuildRequestPayload" then
			DevilFruitLogger.Warn(
				"REQUEST",
				"controller method missing fruit=%s method=%s source=%s",
				tostring(fruitIdentifier),
				tostring(methodName),
				tostring(fruitEntry and self.loadedControllerSources[fruitEntry.FruitKey] or "<unknown>")
			)
		end
		return false, nil
	end

	if methodName == "BeginPredictedRequest" or methodName == "BuildRequestPayload" then
		DevilFruitLogger.Info(
			"CLIENT",
			"controller dispatch fruit=%s method=%s source=%s",
			tostring(fruitIdentifier),
			tostring(methodName),
			tostring(fruitEntry and self.loadedControllerSources[fruitEntry.FruitKey] or "<unknown>")
		)
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
