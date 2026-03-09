local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BADGE_ID = 4099644549108442

local brainrotsModule = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots")

local brainrots
do
	local ok, result = pcall(function()
		return require(brainrotsModule)
	end)

	if not ok then
		warn("[OmegaBadge] Failed to require Brainrots config | Error: " .. tostring(result))
		return
	end

	brainrots = result
end

local omegaSet = {}
local omegaList = {}

for id, info in pairs(brainrots) do
	if type(info) == "table" and tostring(info.Rarity) == "Omega" then
		omegaSet[tostring(id)] = true
		table.insert(omegaList, tostring(id))
	end
end

print("[OmegaBadge] Omega brainrots found: " .. tostring(#omegaList))

local function awardBadgeIfNeeded(player)
	local ok, hasBadge = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, BADGE_ID)
	end)

	if not ok then
		warn("[OmegaBadge] Failed to check badge for player: " .. player.Name)
		return false
	end

	if hasBadge then
		print("[OmegaBadge] Player already has the badge: " .. player.Name)
		return false
	end

	local awardOk, err = pcall(function()
		BadgeService:AwardBadge(player.UserId, BADGE_ID)
	end)

	if awardOk then
		print("[OmegaBadge] Badge awarded to player: " .. player.Name)
		return true
	else
		warn("[OmegaBadge] Failed to award badge to player: " .. player.Name .. " | Error: " .. tostring(err))
		return false
	end
end

local function checkInventoryForOmega(player, inventory)
	for omegaName in pairs(omegaSet) do
		if inventory:FindFirstChild(omegaName) then
			print("[OmegaBadge] Omega brainrot detected for player: " .. player.Name .. " | Item: " .. omegaName)
			awardBadgeIfNeeded(player)
			return
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	print("[OmegaBadge] Player joined: " .. player.Name)

	task.spawn(function()
		local inventory = player:WaitForChild("Inventory", 15)
		if not inventory then
			warn("[OmegaBadge] Inventory folder not found for player: " .. player.Name)
			return
		end

		checkInventoryForOmega(player, inventory)

		inventory.ChildAdded:Connect(function(child)
			if omegaSet[child.Name] then
				print("[OmegaBadge] Omega brainrot added to inventory: " .. player.Name .. " | Item: " .. child.Name)
				awardBadgeIfNeeded(player)
			end
		end)
	end)
end)
