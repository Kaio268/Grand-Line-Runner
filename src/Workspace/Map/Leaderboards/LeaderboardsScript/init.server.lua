local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local shorten  = require(ReplicatedStorage.Modules.Shorten)

local okLB, LBChat = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("LeaderboardChatConfig"))
end)
if not okLB then LBChat = nil end

local shornten = require(ReplicatedStorage.Modules.Shorten)

local REFRESH_SECONDS = 120
local MIN_SAVE_INTERVAL = 60
local DEBOUNCE_SECONDS = 5
local MAX_WRITES_PER_CYCLE = 20
local DEBUG = false

local function dbg(...)
	if not DEBUG then return end
	local t = {}
	for i, v in ipairs({...}) do t[i] = tostring(v) end
	print("[Leaderboard]", table.concat(t, " "))
end

local function Round(v) return math.floor((v or 0) + 0.5) end
local function Encode(v) v = (v or 0) + 1 return math.log10(v) * 1000 end
local function Decode(v)
	v = (v or 0) / 1000
	local n = (10 ^ v) - 1
	if n < 0 then n = 0 end
	return math.floor(n + 0.5)
end

local Suffixes = {" ","K","M","B","T","Qd","Qn","Sx","Sp","Oc","No","De","UDe","DDe","TDe","QtDe","QnDe","SxDe","SpDe","OcDe","NoDe","Vg","UVg","DVg","TVg","QtVg","QnVg","SxVg","SpVg","OcVg","NoVg","Tg","UTg","DTg","TTg","QdTg","QnTg","SxTg","SpTg","OcTg","NoTg","qg","Uqg","Dqg","Tqg","Qdqg","Qnqg","Sxqg","Spqg","Ocqg","Noqg","Qg","UQg","DQg","TQg","QdQg","QnQg","SxQg","SpQg","OcQg","NoQg","sg","Usg","Dsg","Tsg","Qdsg","Qnsg","Sxsg","Spsg","Ocsg","Nosg","Sg","USg","DSg","TSg","QdSg","QnSg","SxSg","SpSg","OcSg","NoSg","Og","UOg","DOg","TOg","QdOg","QnOg","SxOg","SpOg","OcOg","NoOg","Ng","UNg","DNg","TNg","QdNg","QnNg","SxNg","SpNg","OcNg","NoNg","Ce"}
local function Suffix(n)
	n = tonumber(n) or 0
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then return sign .. tostring(math.floor(n + 0.5)) end
	local tier = math.floor(math.log10(n) / 3)
	if tier > #Suffixes - 1 then tier = #Suffixes - 1 end
	local scaled = n / (10 ^ (tier * 3))
	local fmt = (scaled < 10) and "%.2f" or ((scaled < 100) and "%.1f" or "%.0f")
	local s = string.format(fmt, scaled)
	if tonumber(s) and tonumber(s) >= 1000 and tier < #Suffixes - 1 then
		tier += 1
		scaled = n / (10 ^ (tier * 3))
		fmt = (scaled < 10) and "%.2f" or ((scaled < 100) and "%.1f" or "%.0f")
		s = string.format(fmt, scaled)
	end
	s = s:gsub("%.?0+$", "")
	return sign .. s .. Suffixes[tier + 1]
end

local Root = game.Workspace.Map.Leaderboards
local Boards = {
	{
		name = "TotalMoney",
		stat = "TotalMoney",
		ds = DataStoreService:GetOrderedDataStore("TotalMonDa2ta0fbsdfb24"),
		folder = Root:WaitForChild("TotalMoney"),
		display = function(v) return Suffix(v) end,
	},
	{
		name = "TotalSpeed",
		stat = "TotalSpeed",
		ds = DataStoreService:GetOrderedDataStore("TotsaddnData0fbsdfb24"),
		folder = Root:WaitForChild("TotalSpeed"),
		display = function(v) return Suffix(v) end,
	},
	{
		name = "TimePlayed",
		stat = "TimePlayed",
		ds = DataStoreService:GetOrderedDataStore("TotsddsaaddnData0fbsdfb24"),
		folder = Root:WaitForChild("TimePlayed"),
		display = function(v) return shornten.timeSuffix(v) end,
	},
}


local function firstDescByName(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then return d end
	end
end

local function getContainers(boardFolder)
	local views = {}
	local mains = {}
	for _, inst in ipairs(boardFolder:GetDescendants()) do
		if inst.Name == "Main" and inst:IsA("BasePart") then
			mains[#mains + 1] = inst
		end
	end
	if #mains == 0 then
		local main = boardFolder:FindFirstChild("Main")
		if main then
			mains[1] = main
		end
	end
	if #mains == 0 then
		local surface = boardFolder:FindFirstChildOfClass("SurfaceGui") or boardFolder:FindFirstChild("SurfaceGui")
		local holder = surface and surface:FindFirstChild("ScrollingFrame")
		local players = holder 
		local stats = players  
		local container = stats or players or holder or surface or boardFolder
		local template = (container and container:FindFirstChild("Template")) or firstDescByName(boardFolder, "Template")
		if container and template then
			views[1] = {container = container, template = template}
		end
		return views
	end
	for _, main in ipairs(mains) do
		local surface = main:FindFirstChildOfClass("SurfaceGui") or main:FindFirstChild("SurfaceGui")
		local holder = surface and surface:FindFirstChild("ScrollingFrame")
		local players = holder 
		local stats = players  
		local container = stats or players or holder or surface or boardFolder
		local template = (container and container:FindFirstChild("Template")) or firstDescByName(boardFolder, "Template")
		if container and template then
			table.insert(views, {container = container, template = template})
		end
	end
	return views
end

for _, b in ipairs(Boards) do
	b.views = getContainers(b.folder)
end

local uidCache, dispCache = {}, {}
local function resolveIdentity(name)
	if uidCache[name] then return uidCache[name], dispCache[uidCache[name]] end
	local ok1, userId = pcall(function() return Players:GetUserIdFromNameAsync(name) end)
	if not ok1 then return nil, nil end
	uidCache[name] = userId
	local ok2, infos = pcall(function() return UserService:GetUserInfosByUserIdsAsync({ userId }) end)
	if ok2 and infos and infos[1] then dispCache[userId] = infos[1].DisplayName end
	return uidCache[name], dispCache[userId]
end

local function setMedals(frame, rank)
	local a = frame:FindFirstChild("1")
	local b = frame:FindFirstChild("2")
	local c = frame:FindFirstChild("3")
	if a then a.Enabled = rank == 1 end
	if b then b.Enabled = rank == 2 end
	if c then c.Enabled = rank == 3 end
end

local function DSCall(fn, retries)
	retries = retries or 5
	local i = 0
	while i < retries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		i += 1
		task.wait(math.min(5, 0.4 * (2 ^ i)))
	end
	return false
end

local function clearContainer(container)
	for _, ch in ipairs(container:GetChildren()) do
		if ch:IsA("Frame") and ch.Name ~= "Template" and ch.Name ~= "BREAK" and ch.Name ~= "UIListLayout" then
			ch:Destroy()
		end
	end
end

local lastRanks = {}

local function updateChatTagsForBoard(board, page)
	local included = {}
	for rank, entry in ipairs(page) do
		if entry and entry.key then
			included[entry.key] = rank
		end
	end

	lastRanks[board.name] = included

	local attrLB = "LB_" .. board.name
	local cfgAttr = LBChat and LBChat.Boards and LBChat.Boards[board.name] and LBChat.Boards[board.name].attr

	for _, plr in ipairs(Players:GetPlayers()) do
		local r = included[plr.Name]
		if r and r >= 1 and r <= 100 then
			plr:SetAttribute(attrLB, r)
			if cfgAttr then plr:SetAttribute(cfgAttr, r) end
		else
			plr:SetAttribute(attrLB, nil)
			if cfgAttr then plr:SetAttribute(cfgAttr, nil) end
		end
	end
end

local SEARCH_ROOTS = {"TotalStats", "Stats", "leaderstats"}

local function isNumericValueObject(inst)
	if not inst then return false end
	local ok, v = pcall(function() return inst.Value end)
	return ok and typeof(v) == "number"
end

local function findNumericUnder(root, name)
	if not root then return nil, nil end
	local obj = root:FindFirstChild(name, true)
	if obj and isNumericValueObject(obj) then
		return obj.Value, obj
	end
	return nil, nil
end

local function getNumericStat(plr, statName)
	for _, rootName in ipairs(SEARCH_ROOTS) do
		local top = plr:FindFirstChild(rootName)
		local v, obj = findNumericUnder(top, statName)
		if v ~= nil then return v, obj end
		if top then
			local attr = top:GetAttribute(statName)
			if typeof(attr) == "number" then return attr, nil end
		end
	end
	local any = plr:FindFirstChild(statName, true)
	if any and isNumericValueObject(any) then
		return any.Value, any
	end
	local attr = plr:GetAttribute(statName)
	if typeof(attr) == "number" then
		return attr, nil
	end
	return nil, nil
end

local lastSaved = {}
local pending = {}
local pendingOrder = {}
local debouncers = {}

local function markPending(board, playerName, encoded)
	if not pending[board.name] then pending[board.name] = {} end
	if not lastSaved[board.name] then lastSaved[board.name] = {} end
	local prev = pending[board.name][playerName]
	if prev and prev.encoded == encoded then return end
	pending[board.name][playerName] = {encoded = encoded, t = os.clock()}
	pendingOrder[#pendingOrder + 1] = {b = board, key = playerName}
end

local function canWriteNow()
	local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	return budget
end

local function writeOne(board, playerName, encoded)
	local ok = DSCall(function()
		return board.ds:UpdateAsync(playerName, function() return encoded end)
	end, 3)
	if ok then
		if not lastSaved[board.name] then lastSaved[board.name] = {} end
		lastSaved[board.name][playerName] = {when = os.clock(), encoded = encoded}
	end
	return ok
end

local function drainQueue()
	while true do
		local processed = 0
		local budget = canWriteNow()
		if budget > 0 then
			local i = 1
			while i <= #pendingOrder and processed < math.min(budget, MAX_WRITES_PER_CYCLE) do
				local item = table.remove(pendingOrder, 1)
				if item then
					local b = item.b
					local key = item.key
					local entry = pending[b.name] and pending[b.name][key]
					if entry then
						local ls = lastSaved[b.name] and lastSaved[b.name][key]
						if not ls or (os.clock() - (ls.when or 0)) >= MIN_SAVE_INTERVAL or (ls.encoded ~= entry.encoded) then
							local ok = writeOne(b, key, entry.encoded)
							pending[b.name][key] = nil
							processed += 1
							if not ok then
								pending[b.name][key] = entry
								pendingOrder[#pendingOrder + 1] = {b = b, key = key}
							end
						else
							pending[b.name][key] = nil
						end
					end
				end
				i += 1
			end
		end
		task.wait(0.2)
	end
end

local function queueSave(board, plr, value)
	local encoded = Round(Encode((value or 0) + 1))
	local key = plr.Name
	if not debouncers[board.name] then debouncers[board.name] = {} end
	local d = debouncers[board.name][key]
	if d then
		d.value = encoded
		return
	end
	debouncers[board.name][key] = {value = encoded}
	task.delay(DEBOUNCE_SECONDS, function()
		local cur = debouncers[board.name] and debouncers[board.name][key]
		if cur then
			markPending(board, key, cur.value)
			debouncers[board.name][key] = nil
		end
	end)
end

local function pushOne(board, plr)
	local val = select(1, getNumericStat(plr, board.stat))
	if val == nil then return end
	queueSave(board, plr, val)
end

local function fillBoard(board)
	if not board.views or #board.views == 0 then return end
	for _, view in ipairs(board.views) do
		if view.container then
			clearContainer(view.container)
		end
	end
	local tries = 0
	local gotPage = nil
	while tries < 10 and not gotPage do
		local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync)
		if budget > 0 then
			local ok, pages = DSCall(function() return board.ds:GetSortedAsync(false, 100) end, 5)
			if ok then
				gotPage = pages:GetCurrentPage()
				break
			end
		end
		tries += 1
		task.wait(0.5)
	end
	if not gotPage then return end
	updateChatTagsForBoard(board, gotPage)
	for rank, entry in ipairs(gotPage) do
		if type(entry.value) == "number" then
			for _, view in ipairs(board.views) do
				if view.container and view.template then
					local clone = view.template:Clone()
					clone.Visible = true
					clone.Name = (entry.key or "Unknown") .. "Leaderboard"
					local userId, displayName = resolveIdentity(entry.key or "")
					local u = clone:FindFirstChild("Username");    if u and u:IsA("TextLabel") then u.Text = "@" .. (entry.key or "Unknown") end
 					local a = clone:FindFirstChild("Avatar");      if a and a:IsA("ImageLabel") then a.Image = userId and ("rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=150&h=150") or "" end
					local r = clone:FindFirstChild("Rank");        if r and r:IsA("TextLabel") then r.Text = "#" .. tostring(rank) end
					local raw = Decode(entry.value)
					local v = clone:FindFirstChild("Value");       if v and v:IsA("TextLabel") then v.Text = board.display(raw) end
					clone.LayoutOrder = rank
					setMedals(clone, rank)
					clone.Parent = view.container
				end
			end
		end
	end
end

local function pushAllStores()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.UserId and plr.UserId >= 0 then
			for _, b in ipairs(Boards) do
				pushOne(b, plr)
			end
		end
	end
end

local function initRankAttributes(plr)
	if LBChat and LBChat.Boards then
		for _, cfg in pairs(LBChat.Boards) do
			if cfg.attr then plr:SetAttribute(cfg.attr, nil) end
		end
	end
end

local function hookFolderForStat(folder, b, plr)
	if not folder then return end
	local obj = folder:FindFirstChild(b.stat, true)
	if obj and isNumericValueObject(obj) then
		obj.Changed:Connect(function()
			local v = select(1, getNumericStat(plr, b.stat))
			if v ~= nil then queueSave(b, plr, v) end
		end)
		local v = select(1, getNumericStat(plr, b.stat))
		if v ~= nil then queueSave(b, plr, v) end
	end
	local attr = folder:GetAttribute(b.stat)
	if typeof(attr) == "number" then
		queueSave(b, plr, attr)
	end
	folder:GetAttributeChangedSignal(b.stat):Connect(function()
		local a = folder:GetAttribute(b.stat)
		if typeof(a) == "number" then
			queueSave(b, plr, a)
		end
	end)
	folder.DescendantAdded:Connect(function(inst)
		if inst.Name == b.stat and isNumericValueObject(inst) then
			inst.Changed:Connect(function()
				local v = select(1, getNumericStat(plr, b.stat))
				if v ~= nil then queueSave(b, plr, v) end
			end)
			local v = select(1, getNumericStat(plr, b.stat))
			if v ~= nil then queueSave(b, plr, v) end
		end
	end)
end

local function bindStatChanges(plr)
	for _, board in ipairs(Boards) do
		local b = board
		plr:GetAttributeChangedSignal(b.stat):Connect(function()
			local a = plr:GetAttribute(b.stat)
			if typeof(a) == "number" then
				queueSave(b, plr, a)
			end
		end)
	end
	local function attachToRoots()
		for _, board in ipairs(Boards) do
			local b = board
			hookFolderForStat(plr:FindFirstChild("TotalStats"), b, plr)
			hookFolderForStat(plr:FindFirstChild("Stats"), b, plr)
			hookFolderForStat(plr:FindFirstChild("leaderstats"), b, plr)
		end
	end
	attachToRoots()
	plr.ChildAdded:Connect(function(child)
		if child.Name == "TotalStats" or child.Name == "Stats" or child.Name == "leaderstats" then
			for _, board in ipairs(Boards) do
				hookFolderForStat(child, board, plr)
			end
		end
	end)
	plr.DescendantAdded:Connect(function(inst)
		for _, board in ipairs(Boards) do
			if inst.Name == board.stat and isNumericValueObject(inst) then
				inst.Changed:Connect(function()
					local v = select(1, getNumericStat(plr, board.stat))
					if v ~= nil then queueSave(board, plr, v) end
				end)
				local v = select(1, getNumericStat(plr, board.stat))
				if v ~= nil then queueSave(board, plr, v) end
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	initRankAttributes(plr)
	bindStatChanges(plr)
	
	task.defer(function()
		for _, board in ipairs(Boards) do
			local included = lastRanks[board.name]
			if included then
				local r = included[plr.Name]
				local attrLB = "LB_" .. board.name
				local cfgAttr = LBChat and LBChat.Boards and LBChat.Boards[board.name] and LBChat.Boards[board.name].attr

				if r and r >= 1 and r <= 100 then
					plr:SetAttribute(attrLB, r)
					if cfgAttr then plr:SetAttribute(cfgAttr, r) end
				else
					plr:SetAttribute(attrLB, nil)
					if cfgAttr then plr:SetAttribute(cfgAttr, nil) end
				end
			end
		end
	end)

end)

Players.PlayerRemoving:Connect(function(plr)
	if LBChat and LBChat.Boards then
		for _, cfg in pairs(LBChat.Boards) do
			if cfg.attr then plr:SetAttribute(cfg.attr, nil) end
		end
	end
end)

task.spawn(function()
	drainQueue()
end)

task.spawn(function()
	task.wait(2)
	while true do
		pushAllStores()
		for _, b in ipairs(Boards) do
			fillBoard(b)
		end
		task.wait(REFRESH_SECONDS)
	end
end)
