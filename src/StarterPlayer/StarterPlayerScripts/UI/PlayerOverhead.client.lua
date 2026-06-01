local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local TitlesConfig = require(Modules:WaitForChild("Configs"):WaitForChild("Titles"))
local PlayerOverheadBillboard = require(UiFolder:WaitForChild("Player"):WaitForChild("PlayerOverheadBillboard"))

local BOARD_ATTRIBUTES = {
	"LB_TotalMoney",
	"LB_TotalSpeed",
	"LB_Bounty",
	"EquippedTitleId",
	"EquippedTitleDisplay",
}

local HORO_ATTRIBUTES = {
	"HoroProjectionActive",
	"HoroProjectionEndTime",
}

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactPlayerOverheadRoot"

local portalHost = Instance.new("ScreenGui")
portalHost.Name = "ReactPlayerOverheadLayer"
portalHost.IgnoreGuiInset = true
portalHost.ResetOnSpawn = false
portalHost.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
portalHost.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)
local changedEvent = Instance.new("BindableEvent")
local trackedPlayers = {}
local playerConnections = {}
local characterConnections = {}
local leaderstatsConnections = {}
local currencyConnections = {}
local statusConnections = {}
local nextPlayerKey = 0

local function fireChanged()
	changedEvent:Fire()
end

local function disconnectConnections(connections)
	for _, connection in ipairs(connections or {}) do
		connection:Disconnect()
	end
end

local function hideDefaultDisplay(character)
	if not character then
		return
	end

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function hasLegacyNametagText(instance, playerName)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			local text = tostring(descendant.Text or "")
			if text == playerName or string.find(text, " Beli", 1, true) then
				return true
			end
		end
	end

	return false
end

local function removeLegacyOverheads(character, playerName)
	if not character then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BillboardGui") then
			local lowerName = string.lower(descendant.Name)
			if lowerName == "nametag" or hasLegacyNametagText(descendant, playerName) then
				descendant:Destroy()
			end
		end
	end
end

local function disconnectCharacter(player)
	disconnectConnections(characterConnections[player])
	characterConnections[player] = nil
end

local function connectCharacter(player, character)
	disconnectCharacter(player)
	if not character then
		fireChanged()
		return
	end

	hideDefaultDisplay(character)
	removeLegacyOverheads(character, player.Name)
	characterConnections[player] = {
		character.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then
				hideDefaultDisplay(character)
			end
			fireChanged()
		end),
		character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BillboardGui") then
				task.defer(function()
					if descendant.Parent and descendant:IsDescendantOf(character) then
						removeLegacyOverheads(character, player.Name)
					end
				end)
			end
		end),
		character.ChildRemoved:Connect(fireChanged),
		character.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				fireChanged()
			end
		end),
	}
	fireChanged()
end

local function disconnectLeaderstats(player)
	disconnectConnections(leaderstatsConnections[player])
	leaderstatsConnections[player] = nil
end

local function disconnectCurrency(player)
	local connection = currencyConnections[player]
	if connection then
		connection:Disconnect()
	end
	currencyConnections[player] = nil
end

local function disconnectStatus(player)
	disconnectConnections(statusConnections[player])
	statusConnections[player] = nil
end

local function getStatusFolder(player)
	local potions = player:FindFirstChild("Potions")
	if potions and potions:IsA("Folder") then
		return potions
	end

	return nil
end

local function connectStatusValue(connections, value)
	if value and value:IsA("NumberValue") then
		connections[#connections + 1] = value:GetPropertyChangedSignal("Value"):Connect(fireChanged)
	end
end

local function refreshStatusConnections(player)
	disconnectStatus(player)

	local connections = {}
	local leaderstats = player:FindFirstChild("leaderstats")
	local potions = getStatusFolder(player)

	connectStatusValue(connections, leaderstats and leaderstats:FindFirstChild("Rebirths"))
	connectStatusValue(connections, potions and potions:FindFirstChild("x2MoneyTime"))
	connectStatusValue(connections, potions and potions:FindFirstChild("x15WalkSpeedTime"))

	if potions then
		connections[#connections + 1] = potions.ChildAdded:Connect(function(child)
			if child.Name == "x2MoneyTime" or child.Name == "x15WalkSpeedTime" then
				refreshStatusConnections(player)
			end
		end)
		connections[#connections + 1] = potions.ChildRemoved:Connect(function(child)
			if child.Name == "x2MoneyTime" or child.Name == "x15WalkSpeedTime" then
				refreshStatusConnections(player)
			end
		end)
	end

	statusConnections[player] = connections
	fireChanged()
end

local function refreshCurrencyConnection(player)
	disconnectCurrency(player)

	local valueObject = CurrencyUtil.findPrimaryValueObject(player)
	if valueObject then
		currencyConnections[player] = valueObject:GetPropertyChangedSignal("Value"):Connect(fireChanged)
	end
	fireChanged()
end

local function connectLeaderstats(player, leaderstats)
	disconnectLeaderstats(player)
	if not leaderstats then
		refreshCurrencyConnection(player)
		return
	end

	leaderstatsConnections[player] = {
		leaderstats.ChildAdded:Connect(function()
			refreshCurrencyConnection(player)
			refreshStatusConnections(player)
		end),
		leaderstats.ChildRemoved:Connect(function()
			refreshCurrencyConnection(player)
			refreshStatusConnections(player)
		end),
	}
	refreshCurrencyConnection(player)
	refreshStatusConnections(player)
end

local function disconnectPlayer(player)
	disconnectConnections(playerConnections[player])
	playerConnections[player] = nil
	disconnectCharacter(player)
	disconnectLeaderstats(player)
	disconnectCurrency(player)
	disconnectStatus(player)
	trackedPlayers[player] = nil
end

local function connectPlayer(player)
	if trackedPlayers[player] then
		return
	end

	nextPlayerKey += 1
	trackedPlayers[player] = tostring(nextPlayerKey)

	local connections = {
		player.CharacterAdded:Connect(function(character)
			connectCharacter(player, character)
		end),
		player.CharacterRemoving:Connect(function()
			connectCharacter(player, nil)
		end),
		player.ChildAdded:Connect(function(child)
			if child.Name == "leaderstats" then
				connectLeaderstats(player, child)
			elseif child.Name == "Potions" then
				refreshStatusConnections(player)
			end
			fireChanged()
		end),
		player.ChildRemoved:Connect(function(child)
			if child.Name == "leaderstats" then
				connectLeaderstats(player, nil)
			elseif child.Name == "Potions" then
				refreshStatusConnections(player)
			end
			fireChanged()
		end),
		player:GetPropertyChangedSignal("Name"):Connect(fireChanged),
	}

	for _, attributeName in ipairs(BOARD_ATTRIBUTES) do
		connections[#connections + 1] = player:GetAttributeChangedSignal(attributeName):Connect(fireChanged)
	end
	for _, attributeName in ipairs(HORO_ATTRIBUTES) do
		connections[#connections + 1] = player:GetAttributeChangedSignal(attributeName):Connect(fireChanged)
	end

	playerConnections[player] = connections
	connectCharacter(player, player.Character)
	connectLeaderstats(player, player:FindFirstChild("leaderstats"))
	fireChanged()
end

local function getHead(player)
	local character = player.Character
	if not character or not character.Parent then
		return nil
	end

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end

	return nil
end

local function buildEntries(now)
	local entries = {}

	for player, key in pairs(trackedPlayers) do
		local adornee = getHead(player)
		if adornee then
			local equippedTitleId = tostring(player:GetAttribute("EquippedTitleId") or "")
			local titleDefinition = equippedTitleId ~= "" and TitlesConfig.Get(equippedTitleId) or nil
			local visualStyle = titleDefinition and titleDefinition.VisualStyle or nil
			local titleColor = visualStyle and visualStyle.LedgerColor or nil
			local currencyValue = CurrencyUtil.findPrimaryValueObject(player)
			local endTime = tonumber(player:GetAttribute("HoroProjectionEndTime"))
			local horoActive = player:GetAttribute("HoroProjectionActive") == true
			local leaderstats = player:FindFirstChild("leaderstats")
			local rebirthsValue = leaderstats and leaderstats:FindFirstChild("Rebirths")
			local potions = getStatusFolder(player)
			local beliBoostValue = potions and potions:FindFirstChild("x2MoneyTime")
			local speedBoostValue = potions and potions:FindFirstChild("x15WalkSpeedTime")

			entries[#entries + 1] = {
				key = key,
				adornee = adornee,
				playerName = player.Name,
				titleDisplay = if titleDefinition then tostring(player:GetAttribute("EquippedTitleDisplay") or titleDefinition.DisplayName or equippedTitleId) else "",
				titleColor = titleColor,
				balance = currencyValue and currencyValue.Value or 0,
				rebirths = rebirthsValue and rebirthsValue.Value or 0,
				beliBoostRemaining = beliBoostValue and beliBoostValue.Value or 0,
				speedBoostRemaining = speedBoostValue and speedBoostValue.Value or 0,
				horoActive = horoActive and endTime ~= nil,
				horoRemaining = if horoActive and endTime then math.max(0, endTime - now) else nil,
			}
		end
	end

	table.sort(entries, function(a, b)
		return tostring(a.key) < tostring(b.key)
	end)

	return entries
end

local function PlayerOverheadLayer()
	local _, setRevision = React.useState(0)
	local now, setNow = React.useState(Workspace:GetServerTimeNow())

	React.useEffect(function()
		local changedConnection = changedEvent.Event:Connect(function()
			setRevision(function(value)
				return value + 1
			end)
		end)

		local running = true
		task.spawn(function()
			while running do
				task.wait(1)
				setNow(Workspace:GetServerTimeNow())
			end
		end)

		return function()
			running = false
			changedConnection:Disconnect()
		end
	end, {})

	local children = {}
	for _, entry in ipairs(buildEntries(now)) do
		children[entry.key] = React.createElement(PlayerOverheadBillboard, {
			entry = entry,
		})
	end

	return ReactRoblox.createPortal(children, portalHost)
end

for _, player in ipairs(Players:GetPlayers()) do
	connectPlayer(player)
end

local addedConnection = Players.PlayerAdded:Connect(connectPlayer)
local removingConnection = Players.PlayerRemoving:Connect(function(player)
	disconnectPlayer(player)
	fireChanged()
end)

root:render(React.createElement(PlayerOverheadLayer))

script.Destroying:Connect(function()
	addedConnection:Disconnect()
	removingConnection:Disconnect()
	for player in pairs(trackedPlayers) do
		disconnectPlayer(player)
	end
	changedEvent:Destroy()
	root:unmount()
	rootContainer:Destroy()
	portalHost:Destroy()
end)
