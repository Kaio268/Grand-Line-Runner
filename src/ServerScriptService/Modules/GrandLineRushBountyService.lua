local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local BountyConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushBounty"))
local Resolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushBountyResolver"))

local Service = {}

local started = false

local function coerceNumber(value, fallback)
	if typeof(value) == "number" then
		return value
	end

	return fallback
end

local function waitForReady(player, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 10)
	while player.Parent == Players and os.clock() <= deadline do
		if DataManager:IsReady(player) then
			return true
		end

		task.wait(0.1)
	end

	return DataManager:IsReady(player)
end

local function setNumberIfChanged(player, path, value)
	local current = DataManager:GetValue(player, path)
	if typeof(current) == "number" and current == value then
		return true
	end

	return DataManager:SetValue(player, path, value)
end

local function readCachedBreakdown(player)
	local bountyData = DataManager:GetValue(player, "Bounty")
	if typeof(bountyData) ~= "table" then
		return nil
	end

	local leaderstatKey = tostring(BountyConfig.Display.LeaderstatKey or "Bounty")
	local totalValue = DataManager:GetValue(player, "leaderstats." .. leaderstatKey)

	return {
		Crew = math.max(0, math.floor(coerceNumber(bountyData.Crew, 0))),
		LifetimeExtraction = math.max(0, math.floor(coerceNumber(bountyData.LifetimeExtraction, 0))),
		Total = math.max(
			0,
			math.floor(
				coerceNumber(totalValue, coerceNumber(bountyData.Total, 0))
			)
		),
	}
end

function Service.FormatNumber(value)
	local number = math.max(0, math.floor(coerceNumber(value, 0)))
	local formatted = tostring(number)

	while true do
		local replaced, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end

	return formatted
end

function Service.GetBreakdown(player, brainrotInventory)
	if not DataManager:IsReady(player) then
		return {
			Crew = 0,
			LifetimeExtraction = 0,
			Total = 0,
		}
	end

	local cached = readCachedBreakdown(player)
	if brainrotInventory == nil and cached ~= nil then
		if cached.Crew > 0 or cached.LifetimeExtraction > 0 or cached.Total > 0 then
			return cached
		end
	end

	local inventory = brainrotInventory or DataManager:GetValue(player, "BrainrotInventory")
	local lifetimeExtraction = DataManager:GetValue(player, "Bounty.LifetimeExtraction")
	return Resolver.BuildBreakdown(inventory, lifetimeExtraction)
end

function Service.RefreshPlayerBounty(player, brainrotInventory)
	if not DataManager:IsReady(player) then
		return nil, "not_ready"
	end

	local breakdown = Resolver.BuildBreakdown(
		brainrotInventory or DataManager:GetValue(player, "BrainrotInventory"),
		DataManager:GetValue(player, "Bounty.LifetimeExtraction")
	)
	local leaderstatKey = tostring(BountyConfig.Display.LeaderstatKey or "Bounty")

	setNumberIfChanged(player, "Bounty.Crew", breakdown.Crew)
	setNumberIfChanged(player, "Bounty.Total", breakdown.Total)
	setNumberIfChanged(player, "leaderstats." .. leaderstatKey, breakdown.Total)

	return breakdown
end

function Service.SetLifetimeExtractionBounty(player, newAmount)
	if not DataManager:IsReady(player) then
		return nil, "not_ready"
	end

	local targetAmount = math.max(0, math.floor(coerceNumber(newAmount, 0)))
	DataManager:SetValue(player, "Bounty.LifetimeExtraction", targetAmount)
	return Service.RefreshPlayerBounty(player)
end

function Service.AddLifetimeExtractionBounty(player, deltaAmount)
	if not DataManager:IsReady(player) then
		return nil, 0, "not_ready"
	end

	local delta = math.max(0, math.floor(coerceNumber(deltaAmount, 0)))
	if delta <= 0 then
		return Service.GetBreakdown(player), 0
	end

	local current = math.max(0, math.floor(coerceNumber(DataManager:GetValue(player, "Bounty.LifetimeExtraction"), 0)))
	DataManager:SetValue(player, "Bounty.LifetimeExtraction", current + delta)
	return Service.RefreshPlayerBounty(player), delta
end

function Service.AwardExtractionBountyForReward(player, rewardData)
	local amount = Resolver.ResolveExtractionBountyForReward(rewardData)
	local breakdown, grantedAmount, err = Service.AddLifetimeExtractionBounty(player, amount)
	if err ~= nil then
		return 0, nil, err
	end

	return grantedAmount or 0, breakdown
end

local function refreshWhenReady(player)
	task.spawn(function()
		if waitForReady(player, 15) then
			Service.RefreshPlayerBounty(player)
		end
	end)
end

function Service.Start()
	if started then
		return
	end

	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		refreshWhenReady(player)
	end

	Players.PlayerAdded:Connect(refreshWhenReady)
end

return Service
