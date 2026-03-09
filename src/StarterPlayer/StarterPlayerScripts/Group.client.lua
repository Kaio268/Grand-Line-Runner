local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GroupService = game:GetService("GroupService")

local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

local GROUP_ID = 17179624
local REMOTE_NAME = "GroupRewardClaim"

local player = Players.LocalPlayer

local PlotSystem = workspace:WaitForChild("PlotSystem")
local PlotsFolder = PlotSystem:WaitForChild("Plots")

local remoteEvent = ReplicatedStorage:WaitForChild(REMOTE_NAME)

local function popup(text, isError)
	local textColor = isError and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(60, 255, 60)
	local strokeColor = Color3.fromRGB(0, 0, 0)
	PopUpModule:Local_SendPopUp(text, textColor, strokeColor, 3, isError)
end

local function getOwnedPlot()
	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			local ownerId = plot:GetAttribute("OwnerUserId")
			if ownerId == player.UserId then
				return plot
			end
		end
	end
	return nil
end

local function getPromptFromPlot(plot)
	local groupReward = plot:WaitForChild("GroupReward", 30)
	if not groupReward then
		return nil
	end

	local hitbox = groupReward:WaitForChild("Hitbox", 30)
	if not hitbox then
		return nil
	end

	local prompt = hitbox:WaitForChild("ProximityPrompt", 30)
	if not prompt then
		return nil
	end

	return prompt
end

local currentPlot = nil
local currentPrompt = nil
local promptConn = nil
local busy = false

local function disconnectPrompt()
	if promptConn then
		promptConn:Disconnect()
		promptConn = nil
	end
	currentPrompt = nil
end

local function connectPrompt(prompt)
	disconnectPrompt()
	currentPrompt = prompt

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
	local plot = getOwnedPlot()
	if not plot then
		return
	end

	if currentPlot ~= plot then
		currentPlot = plot
		local prompt = getPromptFromPlot(plot)
		if not prompt then
			warn("GroupReward prompt not found in your plot.")
			return
		end
		connectPrompt(prompt)
	end
end

PlotsFolder.ChildAdded:Connect(function()
	task.defer(tryBind)
end)

PlotsFolder.ChildRemoved:Connect(function(child)
	if child == currentPlot then
		currentPlot = nil
		disconnectPrompt()
		task.defer(tryBind)
	end
end)

task.defer(function()
	while not currentPlot do
		tryBind()
		task.wait(0.5)
	end
end)
