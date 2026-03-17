local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ValidationChecks = {}

local function readPath(root, path)
	local current = root
	for _, segment in ipairs(path) do
		if current == nil then
			return nil
		end

		current = current[segment]
	end

	return current
end

local function stringifyPath(path)
	return table.concat(path, ".")
end

function ValidationChecks.ValidateProfileData(data)
	local issues = {}
	local requiredChecks = {
		{ Path = { "leaderstats", "Doubloons" }, ExpectedType = "number" },
		{ Path = { "HiddenLeaderstats", "PlotUpgrade" }, ExpectedType = "number" },
		{ Path = { "FoodInventory" }, ExpectedType = "table" },
		{ Path = { "BrainrotInventory", "ById" }, ExpectedType = "table" },
		{ Path = { "CrewInventory", "ById" }, ExpectedType = "table" },
		{ Path = { "UnopenedChests", "ById" }, ExpectedType = "table" },
		{ Path = { "DevilFruit", "Equipped" }, ExpectedType = "string" },
	}

	for _, check in ipairs(requiredChecks) do
		local value = readPath(data, check.Path)
		if typeof(value) ~= check.ExpectedType then
			table.insert(
				issues,
				string.format("%s expected %s, got %s", stringifyPath(check.Path), check.ExpectedType, typeof(value))
			)
		end
	end

	return issues
end

function ValidationChecks.WarnProfileData(player: Player, data)
	local issues = ValidationChecks.ValidateProfileData(data)
	if #issues > 0 then
		warn(string.format("[Validation] %s profile data issues: %s", player.Name, table.concat(issues, " | ")))
	end

	return issues
end

function ValidationChecks.ValidateCoreDependencies()
	local missing = {}
	local checks = {
		{ Root = Workspace, Label = "Workspace.PlotSystem", Path = { "PlotSystem" } },
		{ Root = ReplicatedStorage, Label = "ReplicatedStorage.BrainrotFolder", Path = { "BrainrotFolder" } },
		{ Root = ReplicatedStorage, Label = "ReplicatedStorage.Rarities", Path = { "Rarities" } },
		{ Root = ReplicatedStorage, Label = "ReplicatedStorage.Particles", Path = { "Particles" } },
		{ Root = ReplicatedStorage, Label = "ReplicatedStorage.LuckyBlock", Path = { "LuckyBlock" } },
		{ Root = ReplicatedFirst, Label = "ReplicatedFirst.LoadingScreen", Path = { "LoadingScreen" } },
	}

	for _, check in ipairs(checks) do
		if readPath(check.Root, check.Path) == nil then
			table.insert(missing, check.Label)
		end
	end

	return missing
end

function ValidationChecks.WarnMissingDependencies()
	local missing = ValidationChecks.ValidateCoreDependencies()
	if #missing > 0 then
		warn("[Validation] Missing expected runtime dependencies: " .. table.concat(missing, ", "))
	end

	return missing
end

return ValidationChecks
