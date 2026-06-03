local FIRST_OMEGA_BADGE_ENABLED = false

if FIRST_OMEGA_BADGE_ENABLED ~= true then
	return
end

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BADGE_ID = 4099644549108442
local CANONICAL_INVENTORY_NAME = "CrewMemberInventory"
local LEGACY_INVENTORY_NAME = "Inventory"
local OMEGA_RARITY = "Omega"

local CrewMembers = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewMembers"))

local omegaSet = {}
local omegaList = {}
local awardedSession = {}

local function addOmegaIdentifier(value)
	local id = tostring(value or "")
	if id == "" then
		return
	end

	omegaSet[id] = true
end

for _, info in ipairs(CrewMembers.Entries or {}) do
	if type(info) == "table" and tostring(info.Rarity) == OMEGA_RARITY then
		local id = tostring(info.CrewMemberId or info.DisplayName or info.Name or "")
		if id ~= "" then
			addOmegaIdentifier(info.CrewMemberId)
			addOmegaIdentifier(info.DisplayName)
			addOmegaIdentifier(info.Name)
			addOmegaIdentifier(info.LegacyId)
			addOmegaIdentifier(info.StorageName)
			table.insert(omegaList, id)
		end
	end
end

print("[OmegaBadge] Omega crew members found: " .. tostring(#omegaList))

local function awardBadgeIfNeeded(player)
	if awardedSession[player] == true then
		return false
	end

	local ok, hasBadge = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, BADGE_ID)
	end)

	if not ok then
		warn("[OmegaBadge] Failed to check badge for player: " .. player.Name)
		return false
	end

	if hasBadge then
		awardedSession[player] = true
		print("[OmegaBadge] Player already has the badge: " .. player.Name)
		return false
	end

	local awardOk, err = pcall(function()
		BadgeService:AwardBadge(player.UserId, BADGE_ID)
	end)

	if awardOk then
		awardedSession[player] = true
		print("[OmegaBadge] Badge awarded to player: " .. player.Name)
		return true
	else
		warn("[OmegaBadge] Failed to award badge to player: " .. player.Name .. " | Error: " .. tostring(err))
		return false
	end
end

local function readTextValue(instance, name)
	local child = instance:FindFirstChild(name)
	if child and child:IsA("StringValue") then
		return tostring(child.Value or "")
	end

	local attribute = instance:GetAttribute(name)
	if attribute ~= nil then
		return tostring(attribute)
	end

	return ""
end

local function instanceLooksLikeOmegaCrew(instance)
	if not instance then
		return false
	end

	if omegaSet[instance.Name] == true then
		return true
	end

	for _, fieldName in ipairs({
		"CrewMemberId",
		"CrewMemberID",
		"StorageName",
		"LegacyStorageName",
		"DisplayName",
		"Name",
	}) do
		local value = readTextValue(instance, fieldName)
		if value ~= "" and omegaSet[value] == true then
			return true
		end
	end

	return readTextValue(instance, "Rarity") == OMEGA_RARITY
end

local function checkContainerForOmega(player, container)
	if not container then
		return false
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if instanceLooksLikeOmegaCrew(descendant) then
			print("[OmegaBadge] Omega crew member detected for player: " .. player.Name .. " | Item: " .. descendant.Name)
			awardBadgeIfNeeded(player)
			return true
		end
	end

	return false
end

local function bindContainer(player, container)
	if not container then
		return
	end

	if checkContainerForOmega(player, container) then
		return
	end

	container.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if instanceLooksLikeOmegaCrew(descendant) or checkContainerForOmega(player, container) then
				print("[OmegaBadge] Omega crew member added for player: " .. player.Name .. " | Item: " .. descendant.Name)
				awardBadgeIfNeeded(player)
			end
		end)
	end)
end

local function bindPlayerInventories(player)
	local canonicalInventory = player:FindFirstChild(CANONICAL_INVENTORY_NAME)
	if canonicalInventory then
		bindContainer(player, canonicalInventory)
	end

	local legacyInventory = player:FindFirstChild(LEGACY_INVENTORY_NAME)
	if legacyInventory then
		bindContainer(player, legacyInventory)
	end
end

Players.PlayerAdded:Connect(function(player)
	print("[OmegaBadge] Player joined: " .. player.Name)

	task.spawn(function()
		local canonicalInventory = player:WaitForChild(CANONICAL_INVENTORY_NAME, 15)
		if not canonicalInventory then
			warn("[OmegaBadge] CrewMemberInventory folder not found for player: " .. player.Name)
		end

		bindPlayerInventories(player)

		player.ChildAdded:Connect(function(child)
			if child.Name == CANONICAL_INVENTORY_NAME or child.Name == LEGACY_INVENTORY_NAME then
				bindContainer(player, child)
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	awardedSession[player] = nil
end)
