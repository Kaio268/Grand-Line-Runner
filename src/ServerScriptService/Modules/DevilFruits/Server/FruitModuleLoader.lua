local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Registry = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Registry"))
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DevilFruitLogger"))

local FruitModuleLoader = {}
FruitModuleLoader.__index = FruitModuleLoader

local FruitsFolder = script.Parent:WaitForChild("Fruits")
local LegacyFruitsFolder = script.Parent.Parent

function FruitModuleLoader.new()
	local self = setmetatable({}, FruitModuleLoader)
	self.cache = {}
	return self
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

	local moduleScript = FruitsFolder:FindFirstChild(moduleName)
	if not moduleScript then
		local legacyModuleScript = LegacyFruitsFolder:FindFirstChild(moduleName)
		if legacyModuleScript then
			local legacyOk, legacyHandler = pcall(require, legacyModuleScript)
			if legacyOk then
				self.cache[fruitKey] = legacyHandler or false
				return legacyHandler
			end

			self.cache[fruitKey] = false
			DevilFruitLogger.Warn("SERVER", "failed to require legacy fruit module fruit=%s module=%s err=%s", fruitEntry.DisplayName, moduleName, tostring(legacyHandler))
			return nil
		end

		self.cache[fruitKey] = false
		DevilFruitLogger.Warn("SERVER", "missing server fruit module fruit=%s module=%s", fruitEntry.DisplayName, moduleName)
		return nil
	end

	local ok, loadedModule = pcall(require, moduleScript)
	if not ok then
		self.cache[fruitKey] = false
		DevilFruitLogger.Warn("SERVER", "failed to require server fruit module fruit=%s module=%s err=%s", fruitEntry.DisplayName, moduleName, tostring(loadedModule))
		return nil
	end

	local handler = loadedModule
	if typeof(loadedModule.GetLegacyHandler) == "function" then
		local handlerOk, resolvedHandler = pcall(loadedModule.GetLegacyHandler, loadedModule)
		if not handlerOk then
			self.cache[fruitKey] = false
			DevilFruitLogger.Warn("SERVER", "failed to resolve legacy handler fruit=%s module=%s err=%s", fruitEntry.DisplayName, moduleName, tostring(resolvedHandler))
			return nil
		end

		handler = resolvedHandler
	end

	self.cache[fruitKey] = handler or false
	return handler
end

return FruitModuleLoader
