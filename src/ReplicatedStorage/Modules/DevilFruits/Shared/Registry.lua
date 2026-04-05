local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local Registry = {}

local EFFECT_CONTRACTS_BY_KEY = {
	Hie = {
		FreezeShot = {
			Phases = {
				Launch = true,
				Impact = true,
				Expire = true,
			},
			TargetScope = "all_clients",
			Prediction = "visual_only",
			ServerAuthoritative = true,
		},
		IceBoost = {
			Phases = {
				Start = true,
			},
			TargetScope = "all_clients",
			Prediction = "server_only",
			ServerAuthoritative = true,
		},
	},
	Mera = {
		FlameDash = {
			Phases = {
				Start = true,
				Resolve = true,
			},
			TargetScope = "all_clients",
			Prediction = "client_predicted",
			ServerAuthoritative = true,
		},
		FireBurst = {
			Phases = {
				Start = true,
				Release = true,
			},
			TargetScope = "all_clients",
			Prediction = "server_only",
			ServerAuthoritative = true,
		},
	},
}

local UI_OVERRIDES_BY_KEY = {
	Hie = {
		FreezeShot = {
			DisplayName = "Freeze Shot",
		},
		IceBoost = {
			DisplayName = "Ice Boost",
		},
	},
	Mera = {
		FlameDash = {
			DisplayName = "Flame Dash",
		},
		FireBurst = {
			DisplayName = "Fire Burst",
		},
	},
}

local DEFAULT_EFFECT_CONTRACT = {
	Phases = {
		Instant = true,
	},
	TargetScope = "all_clients",
	Prediction = "server_only",
	ServerAuthoritative = true,
}

local fruitEntriesByName = {}
local fruitEntriesByKey = {}
local STRUCTURED_FRUIT_ENTRY_MODULES = {
	Bomu = {
		Client = "BomuClient",
		Server = "BomuServer",
	},
	Gomu = {
		Client = "GomuClient",
		Server = "GomuServer",
	},
	Mera = {
		Client = "MeraClient",
		Server = "MeraServer",
	},
	Hie = {
		Client = "HieClient",
		Server = "HieServer",
	},
	Tori = {
		Client = "ToriClient",
		Server = "ToriServer",
	},
}

local function cloneDictionary(source)
	local clone = {}
	for key, value in pairs(source) do
		clone[key] = value
	end
	return clone
end

local function cloneArray(source)
	local clone = {}
	for index, value in ipairs(source or {}) do
		clone[index] = value
	end
	return clone
end

local function formatAbilityDisplayName(abilityName)
	return tostring(abilityName):gsub("(%l)(%u)", "%1 %2")
end

local function buildAbilityEntry(fruitEntry, abilityName, abilityConfig)
	local fruitKey = fruitEntry.FruitKey
	local uiOverrides = UI_OVERRIDES_BY_KEY[fruitKey]
	local abilityOverrides = uiOverrides and uiOverrides[abilityName] or nil
	local effectContracts = EFFECT_CONTRACTS_BY_KEY[fruitKey]
	local effectContract = cloneDictionary(DEFAULT_EFFECT_CONTRACT)
	local specificContract = effectContracts and effectContracts[abilityName] or nil

	if specificContract then
		for key, value in pairs(specificContract) do
			if key == "Phases" and type(value) == "table" then
				effectContract.Phases = cloneDictionary(value)
			else
				effectContract[key] = value
			end
		end
	end

	return {
		Name = abilityName,
		KeyCode = abilityConfig.KeyCode,
		Cooldown = tonumber(abilityConfig.Cooldown) or 0,
		Config = abilityConfig,
		DisplayName = (abilityOverrides and abilityOverrides.DisplayName) or formatAbilityDisplayName(abilityName),
		Input = {
			KeyCode = abilityConfig.KeyCode,
		},
		CooldownMeta = {
			Duration = tonumber(abilityConfig.Cooldown) or 0,
			StartsOn = abilityConfig.CooldownStartsOn or "Activated",
		},
		Ui = {
			DisplayName = (abilityOverrides and abilityOverrides.DisplayName) or formatAbilityDisplayName(abilityName),
			Order = tonumber(abilityConfig.Cooldown) or 0,
		},
		EffectContract = effectContract,
	}
end

for _, fruitConfig in ipairs(DevilFruitConfig.GetAllFruits()) do
	local structuredEntryModules = STRUCTURED_FRUIT_ENTRY_MODULES[fruitConfig.FruitKey]
	local legacyClientModuleName = fruitConfig.ClientModule or fruitConfig.FruitKey
	local legacyServerModuleName = fruitConfig.ServerModule or fruitConfig.AbilityModule or fruitConfig.FruitKey
	local fruitEntry = {
		Id = fruitConfig.Id,
		FruitKey = fruitConfig.FruitKey,
		DisplayName = fruitConfig.DisplayName,
		AssetFolder = fruitConfig.AssetFolder,
		ClientModuleName = legacyClientModuleName,
		ServerModuleName = legacyServerModuleName,
		ClientModulePath = structuredEntryModules
			and { fruitConfig.FruitKey, "Client", structuredEntryModules.Client }
			or { "Client", "Fruits", legacyClientModuleName },
		ServerModulePath = structuredEntryModules
			and { fruitConfig.FruitKey, "Server", structuredEntryModules.Server }
			or { "Server", "Fruits", legacyServerModuleName },
		Config = fruitConfig,
		Abilities = {},
		AbilityList = {},
		AbilityByKeyCode = {},
	}

	for abilityName, abilityConfig in pairs(fruitConfig.Abilities or {}) do
		local abilityEntry = buildAbilityEntry(fruitEntry, abilityName, abilityConfig)
		fruitEntry.Abilities[abilityName] = abilityEntry
		fruitEntry.AbilityList[#fruitEntry.AbilityList + 1] = abilityEntry

		if abilityConfig.KeyCode ~= nil then
			fruitEntry.AbilityByKeyCode[abilityConfig.KeyCode] = abilityName
		end
	end

	table.sort(fruitEntry.AbilityList, function(a, b)
		if a.Ui.Order == b.Ui.Order then
			return a.Name < b.Name
		end

		return a.Ui.Order < b.Ui.Order
	end)

	fruitEntriesByName[fruitEntry.DisplayName] = fruitEntry
	fruitEntriesByKey[fruitEntry.FruitKey] = fruitEntry
end

function Registry.ResolveFruitEntry(identifier)
	if identifier == nil or identifier == DevilFruitConfig.None then
		return nil
	end

	local fruitConfig = DevilFruitConfig.GetFruit(identifier)
	if not fruitConfig then
		return nil
	end

	return fruitEntriesByName[fruitConfig.DisplayName] or fruitEntriesByKey[fruitConfig.FruitKey]
end

function Registry.ResolveFruitName(identifier)
	return DevilFruitConfig.ResolveFruitName(identifier)
end

function Registry.GetFruit(identifier)
	return Registry.ResolveFruitEntry(identifier)
end

function Registry.GetAbility(fruitIdentifier, abilityName)
	local fruitEntry = Registry.ResolveFruitEntry(fruitIdentifier)
	if not fruitEntry or typeof(abilityName) ~= "string" then
		return nil
	end

	return fruitEntry.Abilities[abilityName]
end

function Registry.GetAbilityByKeyCode(fruitIdentifier, keyCode)
	local fruitEntry = Registry.ResolveFruitEntry(fruitIdentifier)
	if not fruitEntry then
		return nil
	end

	local abilityName = fruitEntry.AbilityByKeyCode[keyCode]
	if not abilityName then
		return nil
	end

	return fruitEntry.Abilities[abilityName]
end

function Registry.GetUiAbilities(fruitIdentifier)
	local fruitEntry = Registry.ResolveFruitEntry(fruitIdentifier)
	if not fruitEntry then
		return {}
	end

	return fruitEntry.AbilityList
end

function Registry.GetEffectContract(fruitIdentifier, abilityName)
	local abilityEntry = Registry.GetAbility(fruitIdentifier, abilityName)
	return abilityEntry and abilityEntry.EffectContract or cloneDictionary(DEFAULT_EFFECT_CONTRACT)
end

function Registry.GetClientModuleName(fruitIdentifier)
	local fruitEntry = Registry.ResolveFruitEntry(fruitIdentifier)
	return fruitEntry and fruitEntry.ClientModuleName or nil
end

function Registry.GetClientModulePath(fruitIdentifier)
	local fruitEntry = Registry.ResolveFruitEntry(fruitIdentifier)
	if not fruitEntry or type(fruitEntry.ClientModulePath) ~= "table" then
		return nil
	end

	return cloneArray(fruitEntry.ClientModulePath)
end

function Registry.GetServerModuleName(fruitIdentifier)
	local fruitEntry = Registry.ResolveFruitEntry(fruitIdentifier)
	return fruitEntry and fruitEntry.ServerModuleName or nil
end

function Registry.GetServerModulePath(fruitIdentifier)
	local fruitEntry = Registry.ResolveFruitEntry(fruitIdentifier)
	if not fruitEntry or type(fruitEntry.ServerModulePath) ~= "table" then
		return nil
	end

	return cloneArray(fruitEntry.ServerModulePath)
end

function Registry.GetAllFruits()
	local entries = {}
	for _, fruitEntry in pairs(fruitEntriesByName) do
		entries[#entries + 1] = fruitEntry
	end

	table.sort(entries, function(a, b)
		return a.DisplayName < b.DisplayName
	end)

	return entries
end

return Registry
