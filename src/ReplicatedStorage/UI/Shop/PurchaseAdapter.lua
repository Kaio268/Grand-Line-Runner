local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Theme = require(script.Parent:WaitForChild("Theme"))

local PurchaseAdapter = {}
PurchaseAdapter.__index = PurchaseAdapter

local function copyTable(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
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

	self:_bindPasses()
	self:_bindPromptSignals()

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
	local passes = self.player:FindFirstChild("Passes")
	local valueObject = passes and passes:FindFirstChild(valueName)
	return valueObject ~= nil and valueObject:IsA("BoolValue") and valueObject.Value == true
end

function PurchaseAdapter:_bindPasses()
	local function reconnectPasses()
		disconnectAll(self._passConnections)

		local passes = self.player:FindFirstChild("Passes")
		if not passes then
			return
		end

		table.insert(self._passConnections, passes.ChildAdded:Connect(function()
			reconnectPasses()
			self:refreshOwnership()
		end))
		table.insert(self._passConnections, passes.ChildRemoved:Connect(function()
			reconnectPasses()
			self:refreshOwnership()
		end))

		for _, child in ipairs(passes:GetChildren()) do
			if child:IsA("BoolValue") then
				table.insert(self._passConnections, child:GetPropertyChangedSignal("Value"):Connect(function()
					self:refreshOwnership()
				end))
			end
		end
	end

	table.insert(self._connections, self.player.ChildAdded:Connect(function(child)
		if child.Name == "Passes" then
			reconnectPasses()
			self:refreshOwnership()
		end
	end))
	table.insert(self._connections, self.player.ChildRemoved:Connect(function(child)
		if child.Name == "Passes" then
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

function PurchaseAdapter:_refreshStateForItem(item)
	local purchase = item.purchase or { kind = "stub" }
	local state = self:_getState(item)

	state.priceText = item.priceText or state.priceText or "--"
	state.isPriceLoading = false
	state.isOwned = false
	state.supportsPrompt = false
	state.buttonEnabled = true
	state.buttonText = item.callToAction or "Purchase"
	state.statusText = "Ready"

	if purchase.kind == "stub" or purchase.id == nil then
		state.buttonText = item.callToAction or "Coming Soon"
		state.statusText = "Arriving soon"
		return
	end

	state.supportsPrompt = true
	if purchase.kind == "gamepass" then
		state.isOwned = self:_readOwnedValue(purchase.ownedKey or item.title)
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

	for _, item in ipairs(catalog.featuredOffers or {}) do
		register(item)
	end

	for _, section in ipairs(catalog.sections or {}) do
		for _, item in ipairs(section.items or {}) do
			register(item)
		end
	end

	self:_emitChanged()
end

function PurchaseAdapter:refreshOwnership()
	for _, item in pairs(self._catalogItems) do
		local purchase = item.purchase
		if purchase and purchase.kind == "gamepass" then
			self:_refreshStateForItem(item)
		end
	end

	self:_emitChanged()
end

function PurchaseAdapter:getViewModel(item)
	local model = copyTable(item)
	model.purchaseState = copyTable(self:_getState(item))
	return model
end

function PurchaseAdapter:requestPurchase(item)
	local purchase = item and item.purchase
	if not purchase then
		return false, "This offer is missing purchase metadata."
	end

	if purchase.kind == "stub" or purchase.id == nil then
		return false, "This offer is not available just yet."
	end

	local state = self:_getState(item)
	if state.isOwned then
		return false, item.title .. " is already unlocked."
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
