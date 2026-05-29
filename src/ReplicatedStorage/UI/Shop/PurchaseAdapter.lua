local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent:WaitForChild("Theme"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Monetization"))

local PurchaseAdapter = {}
PurchaseAdapter.__index = PurchaseAdapter

local DEFAULT_PAID_RANDOM_POLICY_STATE = {
	CanUsePaidRandomItems = false,
	Resolved = false,
	Status = "unknown",
	Reason = "policy_unknown",
}

local function copyTable(source)
	return table.clone(source)
end

local function disconnectAll(list)
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

local function getPurchaseKey(purchase)
	return tostring(purchase.kind) .. ":" .. tostring(purchase.id)
end

local function copyOfferForState(offer, inheritedItem)
	local result = copyTable(offer or {})
	if typeof(inheritedItem) == "table" then
		result.title = result.title or inheritedItem.title
		result.themeKey = result.themeKey or inheritedItem.themeKey
		result.RequiresPaidRandomItemPolicy = result.RequiresPaidRandomItemPolicy
			or inheritedItem.RequiresPaidRandomItemPolicy
		result.PaidRandomItem = result.PaidRandomItem or inheritedItem.PaidRandomItem
		result.RobuxFundedRandomCurrency = result.RobuxFundedRandomCurrency
			or inheritedItem.RobuxFundedRandomCurrency
		result.RandomRewardGenerator = result.RandomRewardGenerator or inheritedItem.RandomRewardGenerator
	end
	return result
end

local function readValuePath(root, path)
	if typeof(root) ~= "Instance" or typeof(path) ~= "string" or path == "" then
		return nil
	end

	local current = root
	for _, segment in ipairs(path:split(".")) do
		current = current and current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	return current
end

local function getPolicyRemoteNames()
	local policyConfig = MonetizationConfig.PaidRandomItemPolicy or {}
	local remotes = policyConfig.Remotes or {}
	return tostring(remotes.StateRequestName or "PaidRandomItemPolicyStateRequest"),
		tostring(remotes.ProductPromptRequestName or "PaidRandomProductPromptRequest")
end

local function getShopProductPromptRemoteName()
	return tostring(MonetizationConfig.ShopProductPromptRemoteName or "ShopProductPromptRequest")
end

local function normalizePolicyState(state)
	if typeof(state) ~= "table" then
		return table.clone(DEFAULT_PAID_RANDOM_POLICY_STATE)
	end

	return {
		CanUsePaidRandomItems = state.CanUsePaidRandomItems == true,
		Resolved = state.Resolved == true,
		Status = tostring(state.Status or "unknown"),
		Reason = tostring(state.Reason or "policy_unknown"),
	}
end

local function getPaidRandomUnavailableMessage(policyState)
	if policyState and policyState.Status == "restricted" then
		return MonetizationConfig.PaidRandomItemUnavailableMessage
	end
	return "Purchase availability could not be verified."
end

function PurchaseAdapter.new(player)
	local self = setmetatable({}, PurchaseAdapter)

	self.player = player or Players.LocalPlayer
	self._states = {}
	self._catalogItems = {}
	self._priceCache = {}
	self._priceRequests = {}
	self._connections = {}
	self._passConnections = {}
	self._changed = Instance.new("BindableEvent")
	self._paidRandomPolicyState = table.clone(DEFAULT_PAID_RANDOM_POLICY_STATE)
	self._paidRandomPolicyRequestInFlight = false
	self._paidRandomPolicyRequested = false
	self._policyStateRequest = nil
	self._paidRandomPromptRequest = nil
	self._shopProductPromptRequest = nil

	self:_bindPasses()
	self:_bindPromptSignals()
	self:_requestPaidRandomPolicyState()

	return self
end

function PurchaseAdapter:destroy()
	disconnectAll(self._connections)
	disconnectAll(self._passConnections)

	if self._changed then
		self._changed:Destroy()
		self._changed = nil
	end
end

function PurchaseAdapter:subscribe(callback)
	return self._changed.Event:Connect(callback)
end

function PurchaseAdapter:_emitChanged()
	if self._changed then
		self._changed:Fire()
	end
end

function PurchaseAdapter:_getState(item)
	local state = self._states[item.id]
	if state then
		return state
	end

	state = {
		priceText = item.priceText or "--",
		buttonText = item.callToAction or "Purchase",
		buttonEnabled = true,
		statusText = "Ready",
		isOwned = false,
		isPriceLoading = false,
		supportsPrompt = false,
	}

	self._states[item.id] = state
	return state
end

function PurchaseAdapter:_readOwnedValue(valueName)
	if typeof(valueName) ~= "string" or valueName == "" then
		return false
	end

	if valueName:find(".", 1, true) ~= nil then
		local valueObject = readValuePath(self.player, valueName)
		if valueObject and valueObject:IsA("BoolValue") then
			return valueObject.Value == true
		end
		if valueObject and valueObject:IsA("NumberValue") then
			return valueObject.Value > 0
		end
		return false
	end

	local passes = self.player:FindFirstChild("Passes")
	local valueObject = passes and passes:FindFirstChild(valueName)
	return valueObject ~= nil and valueObject:IsA("BoolValue") and valueObject.Value == true
end

function PurchaseAdapter:_bindPasses()
	local watchedRoots = {
		Passes = true,
		Packs = true,
		CrewProtection = true,
	}

	local function reconnectPasses()
		disconnectAll(self._passConnections)

		local function bindRoot(root)
			if not root then
				return
			end

			table.insert(self._passConnections, root.DescendantAdded:Connect(function()
				reconnectPasses()
				self:refreshOwnership()
			end))
			table.insert(self._passConnections, root.DescendantRemoving:Connect(function()
				task.defer(function()
					reconnectPasses()
					self:refreshOwnership()
				end)
			end))

			for _, child in ipairs(root:GetDescendants()) do
				if child:IsA("BoolValue") or child:IsA("NumberValue") then
					table.insert(self._passConnections, child:GetPropertyChangedSignal("Value"):Connect(function()
						self:refreshOwnership()
					end))
				end
			end
		end

		for rootName in pairs(watchedRoots) do
			bindRoot(self.player:FindFirstChild(rootName))
		end
	end

	table.insert(self._connections, self.player.ChildAdded:Connect(function(child)
		if watchedRoots[child.Name] then
			reconnectPasses()
			self:refreshOwnership()
		end
	end))
	table.insert(self._connections, self.player.ChildRemoved:Connect(function(child)
		if watchedRoots[child.Name] then
			reconnectPasses()
			self:refreshOwnership()
		end
	end))

	reconnectPasses()
end

function PurchaseAdapter:_bindPromptSignals()
	table.insert(self._connections, MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _, purchased)
		if player ~= self.player or not purchased then
			return
		end

		task.defer(function()
			self:refreshOwnership()
		end)
	end))

	table.insert(self._connections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(playerOrUserId)
		local matchesPlayer = playerOrUserId == self.player
			or playerOrUserId == self.player.UserId
			or playerOrUserId == tostring(self.player.UserId)
		if not matchesPlayer then
			return
		end

		self:_emitChanged()
	end))
end

function PurchaseAdapter:_getRemoteFunction(remoteName)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 5)
	if not remotes then
		return nil
	end

	local remote = remotes:FindFirstChild(remoteName) or remotes:WaitForChild(remoteName, 5)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	return nil
end

function PurchaseAdapter:_getPolicyStateRequest()
	if self._policyStateRequest and self._policyStateRequest.Parent then
		return self._policyStateRequest
	end

	local stateRequestName = getPolicyRemoteNames()
	self._policyStateRequest = self:_getRemoteFunction(stateRequestName)
	return self._policyStateRequest
end

function PurchaseAdapter:_getPaidRandomPromptRequest()
	if self._paidRandomPromptRequest and self._paidRandomPromptRequest.Parent then
		return self._paidRandomPromptRequest
	end

	local _, promptRequestName = getPolicyRemoteNames()
	self._paidRandomPromptRequest = self:_getRemoteFunction(promptRequestName)
	return self._paidRandomPromptRequest
end

function PurchaseAdapter:_getShopProductPromptRequest()
	if self._shopProductPromptRequest and self._shopProductPromptRequest.Parent then
		return self._shopProductPromptRequest
	end

	self._shopProductPromptRequest = self:_getRemoteFunction(getShopProductPromptRemoteName())
	return self._shopProductPromptRequest
end

function PurchaseAdapter:_refreshPaidRandomItems()
	for _, item in pairs(self._catalogItems) do
		if MonetizationConfig.ItemRequiresPaidRandomItemPolicy(item) then
			self:_refreshStateForItem(item)
		end
	end
end

function PurchaseAdapter:_requestPaidRandomPolicyState()
	if self._paidRandomPolicyRequestInFlight or self._paidRandomPolicyRequested then
		return
	end

	self._paidRandomPolicyRequestInFlight = true
	self._paidRandomPolicyRequested = true
	task.spawn(function()
		local remote = self:_getPolicyStateRequest()
		local nextState = table.clone(DEFAULT_PAID_RANDOM_POLICY_STATE)
		if remote then
			local ok, result = pcall(function()
				return remote:InvokeServer()
			end)
			if ok then
				nextState = normalizePolicyState(result)
			end
		end

		self._paidRandomPolicyState = nextState
		self._paidRandomPolicyRequestInFlight = false
		self:_refreshPaidRandomItems()
		self:_emitChanged()
	end)
end

function PurchaseAdapter:_refreshStateForItem(item)
	local purchase = item.purchase or { kind = "stub" }
	local state = self:_getState(item)
	local requiresPaidRandomPolicy = MonetizationConfig.ItemRequiresPaidRandomItemPolicy(item)

	state.priceText = item.priceText or state.priceText or "--"
	state.isPriceLoading = false
	state.isOwned = false
	state.supportsPrompt = false
	state.buttonEnabled = true
	state.buttonText = item.callToAction or "Purchase"
	state.statusText = "Ready"
	state.requiresPaidRandomPolicy = requiresPaidRandomPolicy

	if purchase.kind == "stub" or purchase.id == nil then
		state.buttonText = item.placeholderAction or "Coming Soon"
		state.statusText = "Arriving soon"
		state.buttonEnabled = false
		return
	end

	if requiresPaidRandomPolicy then
		self:_requestPaidRandomPolicyState()
	end

	if requiresPaidRandomPolicy and self._paidRandomPolicyState.CanUsePaidRandomItems ~= true then
		state.buttonText = "Unavailable"
		state.statusText = "Unavailable"
		state.priceText = item.priceText or "Unavailable"
		state.buttonEnabled = false
		return
	end

	if not MonetizationConfig.CanPromptPurchase(purchase.kind, purchase.id) then
		state.buttonText = item.placeholderAction or "Coming Soon"
		state.statusText = "Not available yet"
		state.priceText = item.priceText or "Soon"
		state.buttonEnabled = false
		return
	end

	state.supportsPrompt = true
	if purchase.kind == "gamepass" then
		state.isOwned = self:_readOwnedValue(purchase.ownedPath or purchase.ownedKey or item.title)
	elseif purchase.kind == "product" and (purchase.oneTime == true or purchase.OneTime == true) then
		state.isOwned = self:_readOwnedValue(purchase.ownedPath or purchase.OwnedPath)
	end

	if state.isOwned then
		state.buttonEnabled = false
		state.buttonText = "Owned"
		state.statusText = "Unlocked"
	else
		state.buttonEnabled = true
		state.buttonText = item.callToAction or "Purchase"
		state.statusText = purchase.kind == "gamepass" and "Permanent unlock" or "Instant delivery"
	end

	local purchaseKey = getPurchaseKey(purchase)
	local cachedPrice = self._priceCache[purchaseKey]
	if cachedPrice ~= nil then
		state.priceText = cachedPrice
		state.isPriceLoading = false
		return
	end

	state.isPriceLoading = true
	if self._priceRequests[purchaseKey] then
		return
	end

	self._priceRequests[purchaseKey] = true
	task.spawn(function()
		local infoType = purchase.kind == "gamepass" and Enum.InfoType.GamePass or Enum.InfoType.Product
		local priceText = item.priceText or "--"

		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(purchase.id, infoType)
		end)
		if ok and typeof(info) == "table" then
			local price = tonumber(info.PriceInRobux or info.Price or 0)
			if price ~= nil then
				priceText = Theme.formatPrice(price)
			end
		end

		self._priceCache[purchaseKey] = priceText
		self._priceRequests[purchaseKey] = nil

		for _, candidate in pairs(self._catalogItems) do
			local candidatePurchase = candidate.purchase
			if candidatePurchase and getPurchaseKey(candidatePurchase) == purchaseKey then
				local candidateState = self:_getState(candidate)
				candidateState.priceText = priceText
				candidateState.isPriceLoading = false
			end
		end

		self:_emitChanged()
	end)
end

function PurchaseAdapter:primeCatalog(catalog)
	local seen = {}
	self._catalogItems = {}

	local function register(item)
		if not item or seen[item.id] then
			return
		end
		seen[item.id] = true
		self._catalogItems[item.id] = item
		self:_refreshStateForItem(item)
	end

	local function registerItemAndVariants(item)
		register(item)
		for _, variant in ipairs(item and item.variants or {}) do
			register(copyOfferForState(variant, item))
		end
	end

	for _, item in ipairs(catalog.featuredOffers or {}) do
		registerItemAndVariants(item)
	end

	for _, section in ipairs(catalog.featuredSections or {}) do
		for _, item in ipairs(section.items or {}) do
			registerItemAndVariants(item)
		end
	end

	for _, section in ipairs(catalog.sections or {}) do
		for _, item in ipairs(section.items or {}) do
			registerItemAndVariants(item)
		end
	end

	self:_emitChanged()
end

function PurchaseAdapter:refreshOwnership()
	for _, item in pairs(self._catalogItems) do
		local purchase = item.purchase
		if purchase and (
			purchase.kind == "gamepass"
			or (purchase.kind == "product" and (purchase.oneTime == true or purchase.OneTime == true))
		) then
			self:_refreshStateForItem(item)
		end
	end

	self:_emitChanged()
end

function PurchaseAdapter:getViewModel(item)
	local model = copyTable(item)
	model.purchaseState = copyTable(self:_getState(item))
	if typeof(item.variants) == "table" then
		model.variants = {}
		for index, variant in ipairs(item.variants) do
			local variantModel = copyOfferForState(variant, item)
			variantModel.purchaseState = copyTable(self:_getState(variantModel))
			model.variants[index] = variantModel
		end
	end
	return model
end

function PurchaseAdapter:requestPurchase(item, selectedVariant)
	local offer = if selectedVariant ~= nil then copyOfferForState(selectedVariant, item) else item
	local purchase = offer and offer.purchase
	if not purchase then
		return false, "This offer is missing purchase metadata."
	end

	if purchase.kind == "stub" or purchase.id == nil then
		return false, "This offer is not available just yet."
	end

	if not MonetizationConfig.CanPromptPurchase(purchase.kind, purchase.id) then
		local status, metadata
		if purchase.kind == "gamepass" then
			status, metadata = MonetizationConfig.GetGamepassStatus(purchase.id)
		else
			status, metadata = MonetizationConfig.GetDeveloperProductStatus(purchase.id)
		end
		warn(string.format(
			"[PurchaseAdapter] Blocked disabled/non-GTR purchase prompt item=%s kind=%s id=%s status=%s reason=%s",
			tostring(offer.id or item.id or item.title or "<unknown>"),
			tostring(purchase.kind),
			tostring(purchase.id),
			tostring(status),
			tostring(metadata and metadata.Reason or "not_active_chefs_product")
		))
		return false, MonetizationConfig.UnavailableMessage
	end

	local requiresPaidRandomPolicy = MonetizationConfig.ItemRequiresPaidRandomItemPolicy(offer)
		or MonetizationConfig.ItemRequiresPaidRandomItemPolicy(item)
	if requiresPaidRandomPolicy and self._paidRandomPolicyState.CanUsePaidRandomItems ~= true then
		self:_requestPaidRandomPolicyState()
		return false, getPaidRandomUnavailableMessage(self._paidRandomPolicyState)
	end

	local state = self:_getState(offer)
	if state.isOwned then
		return false, item.title .. " is already unlocked."
	end

	if purchase.kind == "product" and requiresPaidRandomPolicy then
		local remote = self:_getPaidRandomPromptRequest()
		if not remote then
			return false, "Purchase availability could not be verified."
		end

		local ok, response = pcall(function()
			return remote:InvokeServer(purchase.id)
		end)

		if ok and typeof(response) == "table" then
			if typeof(response.policy) == "table" then
				self._paidRandomPolicyState = normalizePolicyState(response.policy)
				self:_refreshPaidRandomItems()
				self:_emitChanged()
			end
			if response.ok == true then
				return true, nil
			end
			return false, getPaidRandomUnavailableMessage(self._paidRandomPolicyState)
		end

		return false, "The Roblox purchase prompt could not be opened."
	end

	if purchase.kind == "product" and (purchase.oneTime == true or purchase.OneTime == true) then
		local remote = self:_getShopProductPromptRequest()
		if not remote then
			return false, "Purchase availability could not be verified."
		end

		local ok, response = pcall(function()
			return remote:InvokeServer(purchase.id)
		end)

		if ok and typeof(response) == "table" then
			if response.ok == true then
				return true, nil
			end
			if response.error == "already_owned" then
				self:refreshOwnership()
				return false, item.title .. " is already unlocked."
			end
			return false, MonetizationConfig.UnavailableMessage
		end

		return false, "The Roblox purchase prompt could not be opened."
	end

	local ok = pcall(function()
		if purchase.kind == "gamepass" then
			MarketplaceService:PromptGamePassPurchase(self.player, purchase.id)
		else
			MarketplaceService:PromptProductPurchase(self.player, purchase.id)
		end
	end)

	if not ok then
		return false, "The Roblox purchase prompt could not be opened."
	end

	return true, nil
end

return PurchaseAdapter
