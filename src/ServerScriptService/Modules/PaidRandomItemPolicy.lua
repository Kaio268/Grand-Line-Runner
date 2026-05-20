local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Monetization")
)

local PaidRandomItemPolicy = {}

local cacheByUserId = {}
local inFlightByUserId = {}
local remotesInstalled = false

local receiptFallbackConfig = MonetizationConfig.PaidRandomItemPolicy
	and MonetizationConfig.PaidRandomItemPolicy.ReceiptFallback
	or {}
local receiptFallbackMode = tostring(receiptFallbackConfig.Mode or "SupportMarker")
local receiptFallbackDataKey = tostring(receiptFallbackConfig.DataKey or "PaidRandomItemReceiptFallbacks")
local receiptFallbackMaxEntries = math.max(1, math.floor(tonumber(receiptFallbackConfig.MaxEntries) or 100))

local function getUserId(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	return tonumber(player.UserId)
end

local function buildState(status, reason, restricted)
	status = tostring(status or "unknown")
	return {
		Allowed = status == "allowed",
		Resolved = status == "allowed" or status == "restricted",
		Restricted = restricted == true,
		Status = status,
		Reason = tostring(reason or status),
		CheckedAt = os.time(),
	}
end

local function getFailClosedState(reason)
	return buildState("unknown", reason or "policy_unknown", false)
end

local function sanitizeForClient(state)
	state = if typeof(state) == "table" then state else getFailClosedState("policy_unknown")

	return {
		CanUsePaidRandomItems = state.Allowed == true,
		Resolved = state.Resolved == true,
		Status = tostring(state.Status or "unknown"),
		Reason = tostring(state.Reason or "policy_unknown"),
	}
end

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and remotes:IsA("Folder") then
		return remotes
	end

	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemote(parent, className, remoteName)
	local remote = parent:FindFirstChild(remoteName)
	if remote and not remote:IsA(className) then
		warn(string.format(
			"[PaidRandomItemPolicy] Replacing %s because it is %s, expected %s",
			tostring(remoteName),
			remote.ClassName,
			className
		))
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new(className)
		remote.Name = remoteName
		remote.Parent = parent
	end

	return remote
end

local function ensureReceiptFallbacks(dataRoot)
	if typeof(dataRoot[receiptFallbackDataKey]) ~= "table" then
		dataRoot[receiptFallbackDataKey] = {}
	end

	return dataRoot[receiptFallbackDataKey]
end

local function findReceiptFallbackByPurchaseId(fallbacks, purchaseId)
	if tostring(purchaseId or "") == "" then
		return nil
	end

	for index, marker in ipairs(fallbacks) do
		if typeof(marker) == "table" and tostring(marker.PurchaseId or "") == purchaseId then
			return marker, index
		end
	end

	return nil
end

function PaidRandomItemPolicy.RecordBlockedReceiptFallback(profile, player, receiptInfo, policyState)
	if typeof(profile) ~= "table" or typeof(profile.Data) ~= "table" then
		error("profile_data_required")
	end

	receiptInfo = if typeof(receiptInfo) == "table" then receiptInfo else {}
	policyState = if typeof(policyState) == "table" then policyState else getFailClosedState("policy_unknown")

	local dataRoot = profile.Data
	local fallbacks = ensureReceiptFallbacks(dataRoot)
	local purchaseId = tostring(receiptInfo.PurchaseId or "")
	local productId = tonumber(receiptInfo.ProductId)
	local now = os.time()

	local existing = findReceiptFallbackByPurchaseId(fallbacks, purchaseId)
	if existing then
		existing.LastSeenAt = now
		existing.PolicyStatus = tostring(policyState.Status or existing.PolicyStatus or "unknown")
		existing.Reason = tostring(policyState.Reason or existing.Reason or "policy_unknown")
		return existing, false
	end

	local productStatus, productMetadata = MonetizationConfig.GetDeveloperProductStatus(productId)
	local marker = {
		Type = "PaidRandomItemPolicyBlockedReceipt",
		FallbackMode = receiptFallbackMode,
		UserId = if player and player.UserId then player.UserId else tonumber(receiptInfo.PlayerId),
		Username = if player and player.Name then player.Name else nil,
		ProductId = productId,
		ProductName = if productMetadata and productMetadata.Name then tostring(productMetadata.Name) else nil,
		ProductStatus = tostring(productStatus or "unknown"),
		PurchaseId = purchaseId,
		PolicyStatus = tostring(policyState.Status or "unknown"),
		Reason = tostring(policyState.Reason or "policy_unknown"),
		CreatedAt = now,
		LastSeenAt = now,
		Resolved = false,
	}

	table.insert(fallbacks, marker)
	while #fallbacks > receiptFallbackMaxEntries do
		table.remove(fallbacks, 1)
	end

	return marker, true
end

function PaidRandomItemPolicy.ClearPlayer(player)
	local userId = getUserId(player)
	if userId == nil then
		return
	end

	cacheByUserId[userId] = nil

	local inFlight = inFlightByUserId[userId]
	if inFlight then
		inFlightByUserId[userId] = nil
		inFlight:Fire()
	end
end

function PaidRandomItemPolicy.GetCachedState(player)
	local userId = getUserId(player)
	if userId == nil then
		return getFailClosedState("invalid_player")
	end

	return cacheByUserId[userId] or getFailClosedState("policy_unknown")
end

function PaidRandomItemPolicy.GetClientState(player)
	return sanitizeForClient(PaidRandomItemPolicy.GetCachedState(player))
end

function PaidRandomItemPolicy.GetPolicyStateAsync(player)
	local userId = getUserId(player)
	if userId == nil or player.Parent ~= Players then
		return getFailClosedState("invalid_player")
	end

	local cached = cacheByUserId[userId]
	if cached then
		return cached
	end

	local inFlight = inFlightByUserId[userId]
	if inFlight then
		inFlight.Event:Wait()
		return cacheByUserId[userId] or getFailClosedState("policy_unknown")
	end

	inFlight = Instance.new("BindableEvent")
	inFlightByUserId[userId] = inFlight

	local ok, policyInfo = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)

	local state
	if ok ~= true then
		state = getFailClosedState("policy_service_error")
	elseif typeof(policyInfo) ~= "table" then
		state = getFailClosedState("policy_response_invalid")
	elseif policyInfo.ArePaidRandomItemsRestricted == true then
		state = buildState("restricted", "paid_random_items_restricted", true)
	elseif policyInfo.ArePaidRandomItemsRestricted == false then
		state = buildState("allowed", "allowed", false)
	else
		state = getFailClosedState("policy_missing_are_paid_random_items_restricted")
	end

	if player.Parent == Players then
		cacheByUserId[userId] = state
	end
	if inFlightByUserId[userId] == inFlight then
		inFlightByUserId[userId] = nil
	end
	pcall(function()
		inFlight:Fire()
	end)
	pcall(function()
		inFlight:Destroy()
	end)

	return state
end

function PaidRandomItemPolicy.RefreshPolicyStateAsync(player)
	local userId = getUserId(player)
	if userId ~= nil then
		cacheByUserId[userId] = nil
	end

	return PaidRandomItemPolicy.GetPolicyStateAsync(player)
end

function PaidRandomItemPolicy.CanUsePaidRandomItems(player)
	local state = PaidRandomItemPolicy.GetPolicyStateAsync(player)
	return state.Allowed == true, state
end

function PaidRandomItemPolicy.PreloadPlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	task.spawn(function()
		PaidRandomItemPolicy.GetPolicyStateAsync(player)
	end)
end

function PaidRandomItemPolicy.SetupRemotes(options)
	if remotesInstalled then
		return
	end
	remotesInstalled = true

	options = if typeof(options) == "table" then options else {}
	local remotesConfig = MonetizationConfig.PaidRandomItemPolicy
		and MonetizationConfig.PaidRandomItemPolicy.Remotes
		or {}
	local stateRequestName = tostring(remotesConfig.StateRequestName or "PaidRandomItemPolicyStateRequest")
	local promptRequestName = tostring(remotesConfig.ProductPromptRequestName or "PaidRandomProductPromptRequest")

	local remotes = getOrCreateRemotesFolder()
	local stateRequest = getOrCreateRemote(remotes, "RemoteFunction", stateRequestName)
	local promptRequest = getOrCreateRemote(remotes, "RemoteFunction", promptRequestName)

	stateRequest.OnServerInvoke = function(player)
		local state = PaidRandomItemPolicy.GetPolicyStateAsync(player)
		return sanitizeForClient(state)
	end

	promptRequest.OnServerInvoke = function(player, productId)
		if typeof(options.PromptProductPurchase) ~= "function" then
			return {
				ok = false,
				error = "prompt_handler_unavailable",
				policy = PaidRandomItemPolicy.GetClientState(player),
			}
		end

		local ok, result = pcall(options.PromptProductPurchase, player, productId)
		if not ok then
			warn(string.format(
				"[PaidRandomItemPolicy] Paid random prompt handler failed player=%s productId=%s error=%s",
				player and player.Name or "<unknown>",
				tostring(productId),
				tostring(result)
			))
			return {
				ok = false,
				error = "prompt_handler_failed",
				policy = PaidRandomItemPolicy.GetClientState(player),
			}
		end

		if typeof(result) == "table" then
			result.policy = result.policy or PaidRandomItemPolicy.GetClientState(player)
			return result
		end

		return {
			ok = result == true,
			error = if result == true then nil else "prompt_rejected",
			policy = PaidRandomItemPolicy.GetClientState(player),
		}
	end
end

Players.PlayerAdded:Connect(function(player)
	PaidRandomItemPolicy.PreloadPlayer(player)
end)

Players.PlayerRemoving:Connect(PaidRandomItemPolicy.ClearPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	PaidRandomItemPolicy.PreloadPlayer(player)
end

return PaidRandomItemPolicy
