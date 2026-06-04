local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService = game:GetService("GroupService")

local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local ShipVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ShipVisuals"))
local SocialGroups = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SocialGroups"))

local GROUP_ID = SocialGroups.GroupRewardGroupId
local REMOTE_NAME = "GroupRewardClaim"

local player = Players.LocalPlayer

local remoteEvent = ReplicatedStorage:WaitForChild(REMOTE_NAME)

local function popup(text, isError)
	local textColor = isError and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(60, 255, 60)
	local strokeColor = Color3.fromRGB(0, 0, 0)
	PopUpModule:Local_SendPopUp(text, textColor, strokeColor, 3, isError)
end

local function resolveWorkspacePath(pathSegments)
	local current = workspace
	for _, segment in ipairs(pathSegments or {}) do
		current = current and current:WaitForChild(segment, 30)
		if not current then
			return nil
		end
	end
	return current
end

local function getActiveShipsFolder()
	local shipSystem = resolveWorkspacePath(ShipVisuals.ShipSystemPath)
	return shipSystem and shipSystem:WaitForChild(ShipVisuals.ActiveShipsName, 30) or nil
end

local ActiveShips = getActiveShipsFolder()

local function getOwnedShip()
	if not ActiveShips then
		return nil
	end

	for _, ship in ipairs(ActiveShips:GetChildren()) do
		if ship:IsA("Model") and ship:GetAttribute(ShipVisuals.Attributes.OwnerUserId) == player.UserId then
			return ship
		end
	end

	return nil
end

local function getPromptFromShip(ship)
	local groupReward = ship:FindFirstChild("GroupReward", true)
	if not groupReward then
		return nil
	end

	local hitbox = groupReward:FindFirstChild("Hitbox", true) or groupReward:FindFirstChild("HitBox", true)
	if not hitbox then
		return nil
	end

	local prompt = hitbox:FindFirstChildOfClass("ProximityPrompt") or hitbox:FindFirstChild("ProximityPrompt", true)
	if not prompt then
		return nil
	end

	return prompt
end

local currentShip = nil
local promptConn = nil
local busy = false

local function disconnectPrompt()
	if promptConn then
		promptConn:Disconnect()
		promptConn = nil
	end
end

local function connectPrompt(prompt)
	disconnectPrompt()

	promptConn = prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer and triggeringPlayer ~= player then
			return
		end

		if busy then
			return
		end
		busy = true

		task.defer(function()
			local inGroup = false
			local okCheck, errCheck = pcall(function()
				inGroup = player:IsInGroup(GROUP_ID)
			end)

			if not okCheck then
				warn("Group check failed:", errCheck)
				popup("Group check failed.", true)
				busy = false
				return
			end

			if not inGroup then
				local status
				local okPrompt, errPrompt = pcall(function()
					status = GroupService:PromptJoinAsync(GROUP_ID)
				end)

				if not okPrompt then
					warn("Group join prompt failed:", errPrompt)
					popup("Group join prompt failed.", true)
					busy = false
					return
				end

				local joinedNow = false
				local okRecheck = pcall(function()
					joinedNow = player:IsInGroup(GROUP_ID)
				end)

				if okRecheck and joinedNow then
					popup("Thanks for joining! Click again to claim your reward.", false)
				else
					if status == Enum.GroupMembershipStatus.None then
						popup("Join the group to claim the reward.", true)
					else
						popup("Your group status is not eligible yet. Click again after joining.", true)
					end
				end

				busy = false
				return
			end

			remoteEvent:FireServer()
			busy = false
		end)
	end)
end

local function tryBind()
	local ship = getOwnedShip()
	if not ship then
		return
	end

	if currentShip ~= ship then
		currentShip = ship
		local prompt = getPromptFromShip(ship)
		if not prompt then
			warn("GroupReward prompt not found on your active ship.")
			return
		end
		connectPrompt(prompt)
	end
end

if ActiveShips then
	ActiveShips.ChildAdded:Connect(function()
		task.defer(tryBind)
	end)

	ActiveShips.ChildRemoved:Connect(function(child)
		if child == currentShip then
			currentShip = nil
			disconnectPrompt()
			task.defer(tryBind)
		end
	end)
end

task.defer(function()
	while not currentShip do
		tryBind()
		task.wait(0.5)
	end
end)
