local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local Gears = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))

local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GearStore")

local function getMoney(player)
	local v = DataManager:GetValue(player, "leaderstats.Money")
	if typeof(v) == "number" then
		return v
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	if money and money:IsA("NumberValue") then
		return money.Value
	end
	return 0
end

local function getProfileReplica(player)
	local profile = DataManager:GetProfile(player)
	local replica = DataManager:GetReplica(player)
	if not (profile and replica) then
		return nil, nil
	end
	return profile, replica
end

local function getGearBool(player, gearName)
	local gearsFolder = player:FindFirstChild("Gears")
	if not gearsFolder then
		return nil
	end
	local bv = gearsFolder:FindFirstChild(gearName)
	if bv and bv:IsA("BoolValue") then
		return bv
	end
	return nil
end

local function applyGearUpdates(player, updates)
	local profile, replica = getProfileReplica(player)
	if not (profile and replica) then
		return
	end

	profile.Data.Gears = profile.Data.Gears or {}
	local gearsFolder = player:FindFirstChild("Gears")

	for name, value in pairs(updates) do
		profile.Data.Gears[name] = value
		replica:Set({ "Gears", name }, value)

		if gearsFolder then
			local bv = gearsFolder:FindFirstChild(name)
			if bv and bv:IsA("BoolValue") then
				bv.Value = value
			end
		end
	end

	DataManager:UpdateData(player)
end

local function equipGearWithTypeRule(player, gearName)
	local gearsFolder = player:FindFirstChild("Gears")
	if not gearsFolder then
		return
	end

	local myCfg = Gears[gearName]
	local myType = myCfg and myCfg.Type or nil

	local updates = {}
	updates[gearName] = true

	if myType then
		for _, inst in ipairs(gearsFolder:GetChildren()) do
			if inst:IsA("BoolValue") and inst.Value == true and inst.Name ~= gearName then
				local cfg = Gears[inst.Name]
				if cfg and cfg.Type == myType then
					updates[inst.Name] = false
				end
			end
		end
	end

	applyGearUpdates(player, updates)
end

Remote.OnServerEvent:Connect(function(player, gearName)
	if typeof(gearName) ~= "string" then
		return
	end

	local gearData = Gears[gearName]
	if not gearData then
		return
	end

	local price = tonumber(gearData.Price) or 0
	if price < 0 then
		return
	end

	local ownedBool = getGearBool(player, gearName)

	if not ownedBool then
		if getMoney(player) < price then
			return
		end
		DataManager:AdjustValue(player, "leaderstats.Money", -price)
		DataManager:AddValue(player, "Gears", { [tostring(gearName)] = false })
		return
	end

	if ownedBool.Value == false then
		equipGearWithTypeRule(player, gearName)
	end
end)
