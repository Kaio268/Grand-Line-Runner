local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService   = game:GetService("DataStoreService")
local Players            = game:GetService("Players")
local DS = DataStoreService:GetDataStore("OwnedGamepasse7")
local GamepassHandler = {}
local _gamepasses = {}
local _byId, _byName = {}, {}


local function getOrCreateFolder(plr)
	local folder = plr:FindFirstChild("Passes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Passes"
		folder.Parent = plr
	end
	return folder
end

local function addValueIfMissing(folder, className, name, defaultValue)
	local val = folder:FindFirstChild(name)
	if not val then
		val = Instance.new(className)
		val.Name = name
		val.Value = defaultValue
		val.Parent = folder
	end
	return val
end

local function ensureDefaultValues(plr)
	local folder = getOrCreateFolder(plr)
	for _, gp in ipairs(_gamepasses) do
		addValueIfMissing(folder, "BoolValue", gp.Name, false)
		if gp.IsMult then
			addValueIfMissing(folder, "NumberValue", gp.Name.."Value", 1)
		end
	end
end

local function ensureValuesOwned(plr, gp)
	local folder = getOrCreateFolder(plr)
	addValueIfMissing(folder, "BoolValue", gp.Name, false)
	if gp.IsMult then
		addValueIfMissing(folder, "NumberValue", gp.Name.."Value", 1)
	end
	local flag = folder:FindFirstChild(gp.Name)
	if flag and not flag.Value then
		flag.Value = true
	end
end

local function getOrCreateRobuxSpent(folder)
	local robuxSpent = folder:FindFirstChild("RobuxSpent")
	if not robuxSpent then
		robuxSpent = Instance.new("NumberValue")
		robuxSpent.Name = "RobuxSpent"
		robuxSpent.Value = 0
		robuxSpent.Parent = folder
	end
	return robuxSpent
end

local VIP_WHITELIST = {
	["piotrek3493"] = true,
	["filip270215"] = true,
	["antekwojtek007xd1"] = true,
	["dominikmach24"] = true,
	["k9bbbyyy"] = true,
	["wotos36"] = true,
	["macjektt47"] = true,
	["wzkm0"] = true,
	["obdart_szalik"] = true,
	["oliwierkropka45"] = true,
}

local function giveVipForWhitelist(plr)
	if not VIP_WHITELIST[plr.Name:lower()] then return end

	local gp = _byName["vip"] 
	if not gp then return end

	ensureValuesOwned(plr, gp)   
	task.spawn(gp.Callback, plr) 
end

---------------------------------------------------------------------

function GamepassHandler.AddGamepass(name, id, onOwnedFunc, isMult)
	isMult = isMult or false
	local price = 0
	local success, productInfo = pcall(function()
		return MarketplaceService:GetProductInfo(id, Enum.InfoType.GamePass)
	end)
	if success and productInfo then
		price = productInfo.PriceInRobux or 0
	else
		warn("Nie udało się pobrać informacji o gamepassie ID " .. id)
	end
	local entry = {Name = name, Id = id, Price = price, Callback = onOwnedFunc, IsMult = isMult}
	table.insert(_gamepasses, entry)
	_byId[id], _byId[tostring(id)] = entry, entry
	_byName[name:lower()] = entry
	for _, plr in ipairs(Players:GetPlayers()) do
		ensureDefaultValues(plr)
	end
end

---------------------------------------------------------------------

function GamepassHandler.GiveGamepass(plr, name)
	local gp = _byName[name:lower()]
	if not gp then
		warn(("GiveGamepass: nie znaleziono gamepassa '%s'"):format(name))
		return
	end
	ensureValuesOwned(plr, gp)
	task.spawn(gp.Callback, plr)
	pcall(function()
		local key = "Player_" .. plr.UserId
		local owned = DS:GetAsync(key) or {}
		owned[tostring(gp.Id)] = true
		DS:SetAsync(key, owned)
	end)
	local folder = getOrCreateFolder(plr)
	local robuxSpent = getOrCreateRobuxSpent(folder)
	robuxSpent.Value += gp.Price
end

---------------------------------------------------------------------


local function playerOwnsGamepass(plr, gpId)
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, gpId)
	end)
	return ok and owns
end


local function setupPlayer(plr)
	ensureDefaultValues(plr)

	local ok, stored = pcall(function()
		return DS:GetAsync("Player_" .. plr.UserId)
	end)
	if not ok then
		stored = {}        
	end
	stored = stored or {}

	local folder      = getOrCreateFolder(plr)
	local robuxSpent  = getOrCreateRobuxSpent(folder)
	local totalSpent  = 0
	local changedDS   = false        

	for _, gp in ipairs(_gamepasses) do
		local idKey = tostring(gp.Id)

		if stored[idKey] then
			ensureValuesOwned(plr, gp)
			task.spawn(gp.Callback, plr)
			totalSpent += gp.Price
			continue
		end

		if playerOwnsGamepass(plr, gp.Id) then
			ensureValuesOwned(plr, gp)
			task.spawn(gp.Callback, plr)

			stored[idKey] = true
			changedDS = true

			totalSpent += gp.Price
		end
	end

	robuxSpent.Value = totalSpent
	giveVipForWhitelist(plr)

	if changedDS then
		pcall(function()
			DS:SetAsync("Player_" .. plr.UserId, stored)
		end)
	end
end

Players.PlayerAdded:Connect(setupPlayer)

---------------------------------------------------------------------

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, id, purchased)
	if not purchased then return end
	local gp = _byId[id] or _byId[tostring(id)]
	if not gp then return end
	ensureValuesOwned(plr, gp)
	task.spawn(gp.Callback, plr)
	pcall(function()
		local key = "Player_" .. plr.UserId
		local owned = DS:GetAsync(key) or {}
		owned[tostring(id)] = true
		DS:SetAsync(key, owned)
	end)
	local folder = getOrCreateFolder(plr)
	local robuxSpent = getOrCreateRobuxSpent(folder)
	robuxSpent.Value += gp.Price
end)

---------------------------------------------------------------------
GamepassHandler.AddGamepass(
	"VIP",
	1667049739 ,
	function(plr)
		local folder = plr:FindFirstChild("Passes")
		 
	end,
	false
)
 
GamepassHandler.AddGamepass(
	"x2 Money",
	1667343349 ,
	function(plr)
		local folder = plr:FindFirstChild("Passes")
		local money = folder:FindFirstChild("x2 MoneyValue")
		money.Value += 1
	end,
	true
)

for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, plr)
end
return GamepassHandler
