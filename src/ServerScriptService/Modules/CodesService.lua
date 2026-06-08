local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local ChestService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
local CodesConfig = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CodesConfig"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local RewardIconResolver = require(Modules:WaitForChild("RewardIconResolver"))

local CodesService = {}

local REMOTE_NAME = "CodeRedeemRequest"
local REMOTES_FOLDER_NAME = "Remotes"
local MAX_CODE_LENGTH = 32
local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local primaryCurrency = CurrencyUtil.getConfig()
local started = false
local requestRemote
local redeemLocks = {}
local REQUEST_ACTION_ALLOWLIST = {
	Redeem = true,
}

local MATERIAL_ALIASES = {
	ancient = "AncientTimber",
	ancienttimber = "AncientTimber",
	commonshipmaterial = "Timber",
	iron = "Iron",
	rareshipmaterial = "Iron",
	timber = "Timber",
}

local function deepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[key] = deepCopy(child)
	end
	return result
end

local function trim(value)
	local text = tostring(value or "")
	return text:match("^%s*(.-)%s*$") or ""
end

local function normalizeCode(rawCode)
	local code = string.upper(trim(rawCode))
	if code == "" or #code > MAX_CODE_LENGTH then
		return nil
	end
	if code:match("^[A-Z0-9_%-]+$") == nil then
		return nil
	end
	return code
end

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if remotes and remotes:IsA("Folder") then
		return remotes
	end

	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = REMOTES_FOLDER_NAME
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemote(parent, className, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote.ClassName == className then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRemotes()
	local remotes = getOrCreateRemotesFolder()
	requestRemote = getOrCreateRemote(remotes, "RemoteFunction", REMOTE_NAME)
end

local function makeResponse(ok, message, errorCode, extra)
	local response = {
		ok = ok == true,
		message = tostring(message or ""),
		error = errorCode,
	}
	if typeof(extra) == "table" then
		for key, value in pairs(extra) do
			response[key] = value
		end
	end
	return response
end

local function sendPopup(player, text, isError)
	if player.Parent ~= Players then
		return
	end

	PopUpModule:Server_SendPopUp(
		player,
		text,
		if isError then ERROR_COLOR else SUCCESS_COLOR,
		STROKE_COLOR,
		3,
		isError == true
	)
end

local function getCodeDefinition(code)
	local codes = if typeof(CodesConfig.Codes) == "table" then CodesConfig.Codes else {}
	local direct = codes[code]
	if typeof(direct) == "table" then
		return direct
	end

	for rawCode, definition in pairs(codes) do
		if typeof(definition) == "table" and normalizeCode(rawCode) == code then
			return definition
		end
	end

	return nil
end

local function getExpiresAtUnix(definition)
	local explicitExpiry = tonumber(definition.ExpiresAtUnix)
	if explicitExpiry ~= nil then
		return math.max(0, math.floor(explicitExpiry))
	end

	local startsAtUnix = math.max(0, math.floor(tonumber(definition.StartsAtUnix) or 0))
	local defaultDuration = math.max(0, math.floor(tonumber(CodesConfig.DefaultDurationSeconds) or 0))
	if startsAtUnix > 0 and defaultDuration > 0 then
		return startsAtUnix + defaultDuration
	end

	return 0
end

local function getRedeemedState(dataRoot, code)
	local codes = if typeof(dataRoot.Codes) == "table" then dataRoot.Codes else nil
	local redeemedCodes = if codes and typeof(codes.Redeemed) == "table" then codes.Redeemed else nil
	return redeemedCodes and redeemedCodes[code] or nil
end

local function normalizeMaterialKey(rawKey)
	local key = string.lower(tostring(rawKey or ""))
	key = key:gsub("[%s_%-]", "")
	return MATERIAL_ALIASES[key]
end

local function formatChestReward(amount, displayName)
	if amount == 1 then
		return "1x " .. displayName
	end
	if displayName:sub(-5) == "Chest" then
		return string.format("%dx %ss", amount, displayName)
	end
	return string.format("%dx %s", amount, displayName)
end

local function addRewardRow(rows, text, iconKey)
	rows[#rows + 1] = {
		Text = text,
		Icon = RewardIconResolver.GetIcon(iconKey or text),
	}
end

local function addPopupRow(rows, text, iconKey)
	rows[#rows + 1] = {
		text,
		RewardIconResolver.GetIcon(iconKey or text),
	}
end

local function applyChestReward(workingData, reward, code, rewardRows, popupRows)
	local amount = math.max(0, math.floor(tonumber(reward.Amount) or 0))
	if amount <= 0 then
		return false, "invalid_reward_amount"
	end

	local grant = ChestService.ApplyChestStackGrantToDataRoot(workingData, reward.Tier or reward.ChestTier, amount, {
		Source = "Code:" .. code,
	})
	if typeof(grant) ~= "table" or grant.ok ~= true then
		return false, tostring(grant and grant.error or "chest_grant_failed")
	end

	local displayName = tostring(grant.DisplayName or "Chest")
	local text = formatChestReward(math.max(1, math.floor(tonumber(grant.Amount) or amount)), displayName)
	addRewardRow(rewardRows, text, displayName)
	addPopupRow(popupRows, text, displayName)
	return true, nil, "UnopenedChests"
end

local function applyCurrencyReward(workingData, reward, rewardRows, popupRows)
	local amount = math.max(0, math.floor(tonumber(reward.Amount) or 0))
	if amount <= 0 then
		return false, "invalid_reward_amount"
	end

	local currency = string.lower(tostring(reward.Currency or reward.Key or reward.Name or "primary"))
	if currency ~= "primary"
		and currency ~= "beli"
		and currency ~= "doubloons"
		and currency ~= "money"
		and currency ~= "moeny"
	then
		return false, "invalid_currency"
	end

	local leaderstats = if typeof(workingData.leaderstats) == "table" then workingData.leaderstats else {}
	local totalStats = if typeof(workingData.TotalStats) == "table" then workingData.TotalStats else {}
	workingData.leaderstats = leaderstats
	workingData.TotalStats = totalStats

	leaderstats[primaryCurrency.Key] = math.max(0, tonumber(leaderstats[primaryCurrency.Key]) or 0) + amount
	totalStats[primaryCurrency.TotalKey] = math.max(0, tonumber(totalStats[primaryCurrency.TotalKey]) or 0) + amount

	local displayName = CurrencyUtil.getDisplayName()
	local text = CurrencyUtil.formatIncomeExactAmount(amount)
	addRewardRow(rewardRows, text, displayName)
	addPopupRow(popupRows, text, displayName)
	return true, nil, "Currency"
end

local function normalizeMaterialsForGrant(materials)
	materials.Inventory = if typeof(materials.Inventory) == "table" then materials.Inventory else {}
	materials.Timber = math.max(0, tonumber(materials.Timber) or tonumber(materials.CommonShipMaterial) or 0)
	materials.Iron = math.max(0, tonumber(materials.Iron) or tonumber(materials.RareShipMaterial) or 0)
	materials.AncientTimber = math.max(0, tonumber(materials.AncientTimber) or 0)
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron
end

local function applyMaterialReward(workingData, reward, rewardRows, popupRows)
	local materialKey = normalizeMaterialKey(reward.Key or reward.Material or reward.Name)
	if materialKey == nil then
		return false, "invalid_material"
	end

	local amount = math.max(0, math.floor(tonumber(reward.Amount) or 0))
	if amount <= 0 then
		return false, "invalid_reward_amount"
	end

	local materials = if typeof(workingData.Materials) == "table" then workingData.Materials else {}
	workingData.Materials = materials
	normalizeMaterialsForGrant(materials)
	materials[materialKey] = math.max(0, tonumber(materials[materialKey]) or 0) + amount
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron

	local displayName = if materialKey == "AncientTimber" then "Ancient Timber" else materialKey
	local text = string.format("%dx %s", amount, displayName)
	addRewardRow(rewardRows, text, displayName)
	addPopupRow(popupRows, text, displayName)
	return true, nil, "Materials"
end

local function applyConfiguredRewards(workingData, code, rewards)
	local rewardRows = {}
	local popupRows = {}
	local touched = {}

	for _, reward in ipairs(if typeof(rewards) == "table" then rewards else {}) do
		if typeof(reward) ~= "table" then
			return false, "invalid_reward_config"
		end

		local rewardType = string.lower(tostring(reward.Type or reward.Kind or reward.RewardType or ""))
		local ok, reason, touchedKey
		if rewardType == "chest" then
			ok, reason, touchedKey = applyChestReward(workingData, reward, code, rewardRows, popupRows)
		elseif rewardType == "currency" or rewardType == "beli" or rewardType == "doubloons" then
			ok, reason, touchedKey = applyCurrencyReward(workingData, reward, rewardRows, popupRows)
		elseif rewardType == "material" or rewardType == "resource" then
			ok, reason, touchedKey = applyMaterialReward(workingData, reward, rewardRows, popupRows)
		else
			return false, "unknown_reward_type"
		end

		if ok ~= true then
			return false, reason
		end
		touched[touchedKey] = true
	end

	if #rewardRows <= 0 then
		return false, "empty_rewards"
	end

	return true, nil, rewardRows, popupRows, touched
end

local function buildOperations(workingData, code, definition, redeemedAtUnix, touched)
	local operations = {}

	if touched.UnopenedChests == true then
		operations[#operations + 1] = {
			Kind = "Set",
			Path = "UnopenedChests",
			Value = workingData.UnopenedChests,
		}
	end
	if touched.Currency == true then
		operations[#operations + 1] = {
			Kind = "Set",
			Path = primaryCurrency.Path,
			Value = workingData.leaderstats[primaryCurrency.Key],
		}
		operations[#operations + 1] = {
			Kind = "Set",
			Path = primaryCurrency.TotalPath,
			Value = workingData.TotalStats[primaryCurrency.TotalKey],
		}
	end
	if touched.Materials == true then
		operations[#operations + 1] = {
			Kind = "Set",
			Path = "Materials",
			Value = workingData.Materials,
		}
	end

	operations[#operations + 1] = {
		Kind = "Set",
		Path = "Codes.Redeemed." .. code,
		Value = {
			RedeemedAtUnix = redeemedAtUnix,
			CodeVersion = tostring(definition.CodeVersion or definition.Version or "1"),
			DisplayName = tostring(definition.DisplayName or code),
		},
	}

	return operations
end

local function redeemInternal(player, rawCode)
	if typeof(rawCode) ~= "string" then
		sendPopup(player, "Enter a valid code.", true)
		return makeResponse(false, "Enter a valid code.", "invalid_code")
	end

	if trim(rawCode) == "" then
		sendPopup(player, "Enter a code first.", true)
		return makeResponse(false, "Enter a code first.", "empty_code")
	end

	local code = normalizeCode(rawCode)
	if code == nil then
		sendPopup(player, "Code can only use letters, numbers, hyphens, and underscores.", true)
		return makeResponse(false, "Code can only use letters, numbers, hyphens, and underscores.", "invalid_code")
	end

	local definition = getCodeDefinition(code)
	if definition == nil then
		sendPopup(player, "That code was not found.", true)
		return makeResponse(false, "That code was not found.", "unknown_code")
	end

	local now = os.time()
	local startsAtUnix = math.max(0, math.floor(tonumber(definition.StartsAtUnix) or 0))
	local expiresAtUnix = getExpiresAtUnix(definition)
	if definition.Enabled == false then
		sendPopup(player, "That code is not active.", true)
		return makeResponse(false, "That code is not active.", "disabled")
	end
	if startsAtUnix > 0 and now < startsAtUnix then
		sendPopup(player, "That code is not active yet.", true)
		return makeResponse(false, "That code is not active yet.", "not_started")
	end
	if expiresAtUnix > 0 and now >= expiresAtUnix then
		sendPopup(player, "That code has expired.", true)
		return makeResponse(false, "That code has expired.", "expired")
	end

	if not DataManager:WaitUntilReady(player, 10) then
		sendPopup(player, "Data is still loading. Try again soon.", true)
		return makeResponse(false, "Data is still loading. Try again soon.", "profile_not_ready")
	end

	local profile = DataManager:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		sendPopup(player, "Data is still loading. Try again soon.", true)
		return makeResponse(false, "Data is still loading. Try again soon.", "profile_not_ready")
	end

	local dataRoot = profile.Data
	if getRedeemedState(dataRoot, code) ~= nil then
		sendPopup(player, "You already redeemed this code.", true)
		return makeResponse(false, "You already redeemed this code.", "already_redeemed", {
			code = code,
		})
	end

	local workingData = {
		UnopenedChests = deepCopy(dataRoot.UnopenedChests or {}),
		leaderstats = deepCopy(dataRoot.leaderstats or {}),
		TotalStats = deepCopy(dataRoot.TotalStats or {}),
		Materials = deepCopy(dataRoot.Materials or {}),
	}

	local rewardsOk, rewardReason, rewardRows, popupRows, touched = applyConfiguredRewards(
		workingData,
		code,
		definition.Rewards
	)
	if rewardsOk ~= true then
		warn(string.format("[CodesService] Invalid reward config code=%s reason=%s", code, tostring(rewardReason)))
		sendPopup(player, "Code reward config is invalid.", true)
		return makeResponse(false, "Code reward config is invalid.", "invalid_reward_config")
	end

	local operations = buildOperations(workingData, code, definition, now, touched)
	local saved, saveResult = DataManager:TryApplyBatch(player, operations, {
		PerfContext = {
			Target = "codes_redeem",
			Code = code,
		},
	})
	if saved ~= true then
		warn(string.format(
			"[CodesService] Save failed player=%s code=%s reason=%s",
			player.Name,
			code,
			tostring(saveResult and saveResult.Reason or "unknown")
		))
		sendPopup(player, "Code redemption failed. Try again soon.", true)
		return makeResponse(false, "Code redemption failed. Try again soon.", "save_failed")
	end

	PopUpModule:Server_ShowReward(player, popupRows)
	sendPopup(player, "Code redeemed!", false)
	return makeResponse(true, "Code redeemed!", nil, {
		code = code,
		rewards = rewardRows,
	})
end

local function redeem(player, rawCode)
	if redeemLocks[player] ~= nil then
		return makeResponse(false, "A code is already being redeemed.", "busy")
	end

	redeemLocks[player] = true
	local ok, response = pcall(redeemInternal, player, rawCode)
	redeemLocks[player] = nil

	if ok then
		return response
	end

	warn(string.format("[CodesService] Redeem failed for %s: %s", player.Name, tostring(response)))
	sendPopup(player, "Code redemption failed. Try again soon.", true)
	return makeResponse(false, "Code redemption failed. Try again soon.", "server_error")
end

local function handleRequest(player, actionName, payload)
	if not RemoteGuard.Check(player, REMOTE_NAME, { actionName, payload }, {
		Cooldown = 0.5,
		ActionIndex = 1,
		ActionAllowlist = REQUEST_ACTION_ALLOWLIST,
		Args = {
			{ Type = "string", MaxLength = 32 },
			{ Type = "table" },
		},
	}) then
		return makeResponse(false, "Invalid code request.", "remote_guard_rejected")
	end

	if actionName == "Redeem" then
		return redeem(player, payload.Code)
	end

	return makeResponse(false, "Unknown code request.", "unknown_action")
end

function CodesService.Start()
	if started then
		return
	end
	started = true

	ensureRemotes()
	requestRemote.OnServerInvoke = function(player, actionName, payload)
		return handleRequest(player, actionName, payload)
	end

	Players.PlayerRemoving:Connect(function(player)
		redeemLocks[player] = nil
	end)
end

function CodesService.Stop()
	if requestRemote then
		requestRemote.OnServerInvoke = nil
	end
	started = false
	table.clear(redeemLocks)
end

return CodesService
