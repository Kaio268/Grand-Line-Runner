local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AbilityTargeting = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Shared")
		:WaitForChild("AbilityTargeting")
)

local HazardProtection = {}

local moduleCache = {}

local function findNamedChildOfClass(parent, childName, className)
	if typeof(parent) ~= "Instance" then
		return nil
	end

	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName and child.ClassName == className then
			return child
		end
	end

	return nil
end

local function getServerFruitModule(fruitFolderName, moduleName)
	local cacheKey = fruitFolderName .. "." .. moduleName
	if moduleCache[cacheKey] ~= nil then
		return if moduleCache[cacheKey] == false then nil else moduleCache[cacheKey]
	end

	local modulesFolder = ServerScriptService:FindFirstChild("Modules")
	local devilFruitsFolder = modulesFolder and findNamedChildOfClass(modulesFolder, "DevilFruits", "Folder")
	local fruitFolder = devilFruitsFolder and findNamedChildOfClass(devilFruitsFolder, fruitFolderName, "Folder")
	local serverFolder = fruitFolder and findNamedChildOfClass(fruitFolder, "Server", "Folder")
	local moduleScript = serverFolder and serverFolder:FindFirstChild(moduleName)

	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		moduleCache[cacheKey] = false
		return nil
	end

	local ok, module = pcall(require, moduleScript)
	if not ok then
		warn(string.format("[HazardProtection] Failed to require %s: %s", moduleScript:GetFullName(), tostring(module)))
		moduleCache[cacheKey] = false
		return nil
	end

	moduleCache[cacheKey] = module
	return module
end

local function buildReason(source, reason)
	local normalizedSource = tostring(source or "hazard_protection")
	local normalizedReason = tostring(reason or "protected")
	return string.format("%s:%s", normalizedSource, normalizedReason)
end

function HazardProtection.GetProtection(target, options)
	options = type(options) == "table" and options or {}
	if options.IgnoreProtection == true or options.IgnoreHazardProtection == true then
		return nil
	end

	local targetContext = type(options.TargetContext) == "table" and options.TargetContext
		or AbilityTargeting.GetCharacterContext(target)
	if not targetContext then
		return nil
	end

	local targetPlayer = targetContext.Player
	if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then
		return nil
	end

	local rootPart = targetContext.RootPart
	local position = if typeof(options.Position) == "Vector3"
		then options.Position
		elseif typeof(options.HitPosition) == "Vector3" then options.HitPosition
		elseif rootPart and rootPart:IsA("BasePart") then rootPart.Position
		else nil

	local moguServer = getServerFruitModule("Mogu", "MoguServer")
	if moguServer and typeof(moguServer.IsProtected) == "function" then
		local ok, isProtected = pcall(moguServer.IsProtected, targetPlayer)
		if ok and isProtected == true then
			return {
				Protected = true,
				Source = "MoguBurrow",
				Reason = "mogu_burrow",
				Player = targetPlayer,
				Position = position,
			}
		end
	end

	local toriServer = getServerFruitModule("Tori", "ToriServer")
	if toriServer and typeof(toriServer.GetProtection) == "function" then
		local ok, protection = pcall(toriServer.GetProtection, targetPlayer, position, options)
		if ok and type(protection) == "table" and protection.Protected == true then
			return protection
		end
	elseif toriServer and typeof(toriServer.IsProtected) == "function" then
		local ok, isProtected, reason = pcall(toriServer.IsProtected, targetPlayer, position, options)
		if ok and isProtected == true then
			return {
				Protected = true,
				Source = "Tori",
				Reason = tostring(reason or "tori_protected"),
				Player = targetPlayer,
				Position = position,
			}
		end
	end

	return nil
end

function HazardProtection.IsProtected(target, options)
	local protection = HazardProtection.GetProtection(target, options)
	if not protection then
		return false
	end

	return true, buildReason(protection.Source, protection.Reason), protection
end

return HazardProtection
