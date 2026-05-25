local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Context = {}

local STEAL_PRODUCT_BY_RARITY = {
	Common = 3512126073,
	Uncommon = 3512126073,
	Rare = 3512126073,
	Epic = 3512126073,
	Legendary = 3512126373,
	Mythic = 3512127278,
	Godly = 3512127790,
	Secret = 3512128038,
	Omega = 3512128716,
}

local RARITY_PRIORITY = { "Omega", "Secret", "Godly", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }

local function normalizeRarity(rarity)
	local text = tostring(rarity or "")
	if text == "" then
		return "Common"
	end

	local lowered = string.lower(text)
	for _, key in ipairs(RARITY_PRIORITY) do
		if string.find(lowered, string.lower(key), 1, true) then
			return key
		end
	end

	return "Common"
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function countSavedStandEntries(incomeCrewMembers)
	if typeof(incomeCrewMembers) ~= "table" then
		return 0
	end

	local count = 0
	for _, row in pairs(incomeCrewMembers) do
		if typeof(row) == "table" and tostring(row.CrewMemberName or row.LegacyStorageName or "") ~= "" then
			count += 1
		end
	end

	return count
end

local function countTableEntries(value)
	if typeof(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	return count
end

local function makeTrace(enabled, prefix)
	return function(message, ...)
		if not enabled then
			return
		end

		print(string.format(prefix .. " t=%.3f " .. message, os.clock(), ...))
	end
end

local function formatCrewPickupDebugFields(fields)
	local parts = {}
	for _, field in ipairs(fields or {}) do
		parts[#parts + 1] = tostring(field[1]) .. "=" .. tostring(field[2])
	end
	return table.concat(parts, " ")
end

function Context.Create()
	local CrewFoodProgression = require(ServerScriptService.Modules:WaitForChild("CrewFoodProgression"))
	local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
	local CrewQuickSlotService = require(ServerScriptService.Modules:WaitForChild("CrewQuickSlotService"))
	local CaptainSlotRuntime = require(ServerScriptService.Modules:WaitForChild("CaptainSlotRuntime"))
	local CrewSlotAssignmentReconciler = require(ServerScriptService.Modules:WaitForChild("CrewSlotAssignmentReconciler"))
	local CrewStandIncomeAuthority = require(ServerScriptService.Modules:WaitForChild("CrewStandIncomeAuthority"))
	local IncomeClaimMath = require(ServerScriptService.Modules:WaitForChild("IncomeClaimMath"))
	local QuestSignals = require(ServerScriptService.Modules:WaitForChild("GrandLineRushQuestSignals"))
	local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))
	local ShipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
	local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))
	local StandUpgradeMults = require(ServerScriptService.Modules.StandsMultiply)

	local Modules = ReplicatedStorage:WaitForChild("Modules")
	local Configs = Modules:WaitForChild("Configs")
	local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
	local MonetizationConfig = require(Modules:WaitForChild("Configs"):WaitForChild("Monetization"))
	local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
	local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
	local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
	local ShipSlotLevelPanelState = require(Modules:WaitForChild("Crew"):WaitForChild("ShipSlotLevelPanelState"))
	local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))
	local RebirthConfig = require(Configs:WaitForChild("Rebirths"))
	local ShipVisuals = require(Configs:WaitForChild("ShipVisuals"))
	local CrewRegistry = require(Modules:WaitForChild("Server"):WaitForChild("Crew"):WaitForChild("Registry"))
	local ShipSlotGuiIdentity = require(Modules:WaitForChild("ShipSlotGuiIdentity"))
	local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))

	local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not Remotes then
		Remotes = Instance.new("Folder")
		Remotes.Name = "Remotes"
		Remotes.Parent = ReplicatedStorage
	end

	local MoneyCollectedRE = Remotes:FindFirstChild("StandMoneyCollected")
	if not MoneyCollectedRE then
		MoneyCollectedRE = Instance.new("RemoteEvent")
		MoneyCollectedRE.Name = "StandMoneyCollected"
		MoneyCollectedRE.Parent = Remotes
	end

	local incomeStatusDisplayMetadataRequest = ReplicatedStorage:FindFirstChild("IncomeStatusDisplayMetadataRequest")
	if incomeStatusDisplayMetadataRequest and not incomeStatusDisplayMetadataRequest:IsA("RemoteFunction") then
		incomeStatusDisplayMetadataRequest:Destroy()
		incomeStatusDisplayMetadataRequest = nil
	end
	if not incomeStatusDisplayMetadataRequest then
		incomeStatusDisplayMetadataRequest = Instance.new("RemoteFunction")
		incomeStatusDisplayMetadataRequest.Name = "IncomeStatusDisplayMetadataRequest"
		incomeStatusDisplayMetadataRequest.Parent = ReplicatedStorage
	end

	pcall(function()
		CrewRegistry.Build()
	end)

	local debugTrace = RunService:IsStudio() and game:GetAttribute("CrewIncomeDebugTrace") == true
	local CREW_PICKUP_DEBUG = true

	local ctx = {
		Players = Players,
		ReplicatedStorage = ReplicatedStorage,
		ServerScriptService = ServerScriptService,
		MarketplaceService = MarketplaceService,
		RunService = RunService,
		CollectionService = CollectionService,

		CrewFoodProgression = CrewFoodProgression,
		CrewInstanceService = CrewInstanceService,
		CrewQuickSlotService = CrewQuickSlotService,
		CaptainSlotRuntime = CaptainSlotRuntime,
		CrewSlotAssignmentReconciler = CrewSlotAssignmentReconciler,
		CrewStandIncomeAuthority = CrewStandIncomeAuthority,
		IncomeClaimMath = IncomeClaimMath,
		QuestSignals = QuestSignals,
		ShipRuntimeSignals = ShipRuntimeSignals,
		ShipRuntimeService = ShipRuntimeService,
		ShipSlotService = ShipSlotService,
		StandUpgradeMults = StandUpgradeMults,
		CurrencyUtil = CurrencyUtil,
		MonetizationConfig = MonetizationConfig,
		PopUpModule = PopUpModule,
		DataManager = DataManager,
		Modules = Modules,
		Configs = Configs,
		CrewCatalog = CrewCatalog,
		CrewOverhead = CrewOverhead,
		ShipSlotLevelPanelState = ShipSlotLevelPanelState,
		VariantCfg = CrewCatalog.GetVariantConfig(),
		PlotUpgradeConfig = PlotUpgradeConfig,
		RebirthConfig = RebirthConfig,
		ShipVisuals = ShipVisuals,
		CrewRegistry = CrewRegistry,
		ShipSlotGuiIdentity = ShipSlotGuiIdentity,

		MoneyCollectedRE = MoneyCollectedRE,
		incomeStatusDisplayMetadataRequest = incomeStatusDisplayMetadataRequest,
		standCommandFunction = ShipRuntimeSignals.GetStandCommandFunction(),

		STEAL_PRODUCT_BY_RARITY = STEAL_PRODUCT_BY_RARITY,
		MAX_INCOME_ON_JOIN = 1e16,
		CAPTAIN_SLOT_KEY = ShipSlotService.CaptainSlotKey or "Captain",
		CAPTAIN_RUNTIME_GUI_ATTRIBUTE = "ShipCaptainSlotRuntimeGui",
		CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE = "ShipCaptainSlotKey",
		CAPTAIN_RUNTIME_GUI_NAME = "ShipCaptainSlotLevelUp",
		STAND_DEBUG = false,
		DEBUG_TRACE = debugTrace,
		ALLOW_NON_OWNER_STEAL_PROMPTS = game:GetAttribute("AllowNonOwnerCrewStealPrompts") == true,
		TUTORIAL_RUNTIME_ACTIVE_ATTRIBUTE = "FirstTimeTutorialActive",
		TUTORIAL_RUNTIME_STEP_ATTRIBUTE = "FirstTimeTutorialStepId",
		CREW_ITEM_KIND = "CrewMember",
		LEGACY_STAND_CREW_PLACEMENT_ROTATION_OFFSET_DEGREES = 90,
		PLACEMENT_PICKUP_GUARD_SECONDS = 1.25,
		INCOME_SHADOW_BANK_THROTTLE_SECONDS = 3,
		INCOME_STATUS_DISPLAY_METADATA_CACHE_SECONDS = 15,
		OVERHEAD_ATTRIBUTES = CrewOverhead.Attribute,

		ensuredStandFolders = {},
		crewRecordCache = setmetatable({}, { __mode = "k" }),
		slotRuntimeByStand = setmetatable({}, { __mode = "k" }),
		playerStandList = {},
		touchDebounce = {},
		stealPromptDebounce = {},
		placementPickupGuardUntil = {},
		plotScanBound = {},

		normalizeRarity = normalizeRarity,
		formatVector3 = formatVector3,
		formatInstancePath = formatInstancePath,
		countSavedStandEntries = countSavedStandEntries,
		countTableEntries = countTableEntries,
		formatCrewPickupDebugFields = formatCrewPickupDebugFields,
	}

	ctx.ownershipTrace = makeTrace(debugTrace, "[OWNERSHIP TRACE]")
	ctx.plotTrace = makeTrace(debugTrace, "[PLOT TRACE]")
	ctx.saveTrace = makeTrace(debugTrace, "[SAVE TRACE]")
	ctx.standDebug = function(message, ...)
		if ctx.STAND_DEBUG ~= true then
			return
		end

		warn(string.format("[GLR StandDebug] " .. tostring(message), ...))
	end
	ctx.crewPickupDebug = function(message, ...)
		if CREW_PICKUP_DEBUG ~= true then
			return
		end

		local prefix = "[CrewPickupDebug] "
		if select("#", ...) == 0 then
			warn(prefix .. tostring(message))
			return
		end

		local ok, formatted = pcall(string.format, prefix .. tostring(message), ...)
		if ok then
			warn(formatted)
		else
			warn(prefix .. tostring(message))
		end
	end

	return ctx
end

return Context
