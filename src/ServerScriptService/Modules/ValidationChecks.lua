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

		if typeof(current) == "Instance" then
			current = current:FindFirstChild(segment)
		else
			current = current[segment]
		end
	end

	return current
end

local function stringifyPath(path)
	return table.concat(path, ".")
end

function ValidationChecks.ValidateProfileData(data)
	local issues = {}
	local requiredChecks = {
		{ Path = { "leaderstats", "Beli" }, ExpectedType = "number" },
		{ Path = { "leaderstats", "Bounty" }, ExpectedType = "number" },
		{ Path = { "HiddenLeaderstats", "PlotUpgrade" }, ExpectedType = "number" },
		{ Path = { "HiddenLeaderstats", "TutorialSkipped" }, ExpectedType = "boolean" },
		{ Path = { "HiddenLeaderstats", "TutorialInProgress" }, ExpectedType = "boolean" },
		{ Path = { "HiddenLeaderstats", "TutorialCurrentStep" }, ExpectedType = "string" },
		{ Path = { "Bounty", "LifetimeExtraction" }, ExpectedType = "number" },
		{ Path = { "Bounty", "Crew" }, ExpectedType = "number" },
		{ Path = { "Bounty", "Total" }, ExpectedType = "number" },
		{ Path = { "Titles", "Unlocked" }, ExpectedType = "table" },
		{ Path = { "Titles", "Equipped" }, ExpectedType = "string" },
		{ Path = { "FoodInventory" }, ExpectedType = "table" },
		{ Path = { "CrewMemberInventory", "ById" }, ExpectedType = "table" },
		{ Path = { "CrewMemberIncome" }, ExpectedType = "table" },
		{ Path = { "CrewMemberQuickSlots", "SchemaVersion" }, ExpectedType = "number" },
		{ Path = { "CrewMemberQuickSlots", "UnlockedSlots" }, ExpectedType = "number" },
		{ Path = { "CrewMemberQuickSlots", "MaxSlots" }, ExpectedType = "number" },
		{ Path = { "UnopenedChests", "ById" }, ExpectedType = "table" },
		{ Path = { "UnopenedChests", "Stacks" }, ExpectedType = "table" },
		{ Path = { "ChestRewards" }, ExpectedType = "table" },
		{ Path = { "Quests" }, ExpectedType = "table" },
		{ Path = { "DevilFruit", "Equipped" }, ExpectedType = "string" },
		{ Path = { "IndexCollection", "CrewMembers" }, ExpectedType = "table" },
		{ Path = { "IndexCollection", "DevilFruits" }, ExpectedType = "table" },
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
		{ Root = Workspace, Label = "Workspace.Map.Main Map.ShipSystem", Path = { "Map", "Main Map", "ShipSystem" } },
		{
			Root = ReplicatedStorage,
			Label = "ReplicatedStorage.Assets.Ships",
			Path = { "Assets", "Ships" },
		},
		{
			Root = ReplicatedStorage,
			Label = "ReplicatedStorage.Assets.One Piece Characters",
			Path = { "Assets", "One Piece Characters" },
		},
		{ Root = ReplicatedStorage, Label = "ReplicatedStorage.LuckyBlock", Path = { "LuckyBlock" } },
		{ Root = ReplicatedFirst, Label = "ReplicatedFirst.Loading", Path = { "Loading" } },
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
