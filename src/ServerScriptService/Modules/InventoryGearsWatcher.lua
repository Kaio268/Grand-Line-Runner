local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:FindFirstChild("InventoryGearRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "InventoryGearRemote"
	remote.Parent = ReplicatedStorage
end

local Module = {}

local function watchInventory(player, inventory)
	local watched = {}

	local function hookFolder(folder)
		if watched[folder] then return end
		watched[folder] = true

		local qty = folder:FindFirstChild("Quantity")
		if not qty then
			qty = folder:WaitForChild("Quantity", 10)
		end
		if not qty or not qty:IsA("NumberValue") then return end

		if qty.Value > 0 then
			remote:FireClient(player, "Brainrot", folder.Name, qty.Value)
		end

		qty.Changed:Connect(function()
			local v = qty.Value
			if v > 0 then
				remote:FireClient(player, "Brainrot", folder.Name, v)
			end
		end)
	end

	for _, child in ipairs(inventory:GetChildren()) do
		if child:IsA("Folder") then
			hookFolder(child)
		end
	end

	inventory.ChildAdded:Connect(function(child)
		if child:IsA("Folder") then
			hookFolder(child)
		end
	end)
end

local function watchGears(player, gearsFolder)
	local watched = {}

	local function hookBool(bv)
		if watched[bv] then return end
		watched[bv] = true

		local function send()
			if bv.Value == true then
				remote:FireClient(player, "Gear", bv.Name, true)
			end
		end

		send()
		bv.Changed:Connect(send)
	end

	for _, child in ipairs(gearsFolder:GetChildren()) do
		if child:IsA("BoolValue") then
			hookBool(child)
		end
	end

	gearsFolder.ChildAdded:Connect(function(child)
		if child:IsA("BoolValue") then
			hookBool(child)
		end
	end)
end

function Module.Start()
	local function setup(player)
		local inventory = player:WaitForChild("Inventory")
		local gearsFolder = player:WaitForChild("Gears")

		watchInventory(player, inventory)
		watchGears(player, gearsFolder)
	end

	Players.PlayerAdded:Connect(setup)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(setup, p)
	end
end

return Module
