local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local SharedFolder = Modules:WaitForChild("DevilFruits"):WaitForChild("Shared")
local Registry = require(SharedFolder:WaitForChild("Registry"))
local DevilFruitLogger = require(SharedFolder:WaitForChild("DevilFruitLogger"))

local FruitModuleLoader = {}
FruitModuleLoader.__index = FruitModuleLoader

local FruitsFolder = script.Parent:WaitForChild("Fruits")
local LegacyFruitsFolder = script.Parent.Parent

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

	return current
end

function FruitModuleLoader.new()
	local self = setmetatable({}, FruitModuleLoader)
	self.cache = {}
	self.sourceByFruitKey = {}
	return self
end

function FruitModuleLoader:ResetHandler(fruitIdentifier)
	local fruitEntry = Registry.GetFruit(fruitIdentifier)
	if not fruitEntry then
		return false
	end

	local fruitKey = fruitEntry.FruitKey
	self.cache[fruitKey] = nil
	self.sourceByFruitKey[fruitKey] = nil
	DevilFruitLogger.Info("SERVER", "handler reset fruit=%s", tostring(fruitEntry.DisplayName))
	return true
end

function FruitModuleLoader:GetHandler(fruitIdentifier)
	local fruitEntry = Registry.GetFruit(fruitIdentifier)
	if not fruitEntry then
		return nil
	end

	local fruitKey = fruitEntry.FruitKey
	local cached = self.cache[fruitKey]
	if cached ~= nil then
		return cached or nil
	end

	local moduleName = Registry.GetServerModuleName(fruitEntry.DisplayName)
	if typeof(moduleName) ~= "string" or moduleName == "" then
		self.cache[fruitKey] = false
		return nil
	end

	local moduleScript = findModuleByPath(LegacyFruitsFolder, Registry.GetServerModulePath(fruitEntry.DisplayName))
	if not moduleScript then
		moduleScript = findNamedChild(FruitsFolder, moduleName, true)
	end
	if not moduleScript then
		local legacyModuleScript = findNamedChild(LegacyFruitsFolder, moduleName, true)
		if legacyModuleScript then
			local legacyOk, legacyHandler = pcall(require, legacyModuleScript)
			if legacyOk then
				self.cache[fruitKey] = legacyHandler or false
				self.sourceByFruitKey[fruitKey] = legacyModuleScript:GetFullName()
				DevilFruitLogger.Info(
					"SERVER",
					"loaded legacy server fruit handler fruit=%s module=%s path=%s",
					tostring(fruitEntry.DisplayName),
					tostring(moduleName),
					tostring(legacyModuleScript:GetFullName())
				)
				return legacyHandler
			end

			DevilFruitLogger.Warn("SERVER", "failed to require legacy fruit module fruit=%s module=%s err=%s", fruitEntry.DisplayName, moduleName, tostring(legacyHandler))
			return nil
		end

		self.cache[fruitKey] = false
		DevilFruitLogger.Warn("SERVER", "missing server fruit module fruit=%s module=%s", fruitEntry.DisplayName, moduleName)
		return nil
	end

	local ok, loadedModule = pcall(require, moduleScript)
	if not ok then
		DevilFruitLogger.Warn("SERVER", "failed to require server fruit module fruit=%s module=%s err=%s", fruitEntry.DisplayName, moduleName, tostring(loadedModule))
		return nil
	end

	local handler = loadedModule
	if typeof(loadedModule.GetLegacyHandler) == "function" then
		local handlerOk, resolvedHandler = pcall(loadedModule.GetLegacyHandler, loadedModule)
		if not handlerOk then
			DevilFruitLogger.Warn("SERVER", "failed to resolve legacy handler fruit=%s module=%s err=%s", fruitEntry.DisplayName, moduleName, tostring(resolvedHandler))
			return nil
		end

		handler = resolvedHandler
	end

	self.cache[fruitKey] = handler or false
	self.sourceByFruitKey[fruitKey] = moduleScript:GetFullName()
	DevilFruitLogger.Info(
		"SERVER",
		"loaded server fruit handler fruit=%s module=%s path=%s",
		tostring(fruitEntry.DisplayName),
		tostring(moduleName),
		tostring(moduleScript:GetFullName())
	)
	return handler
end

return FruitModuleLoader
