local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player.PlayerGui

local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PopUpModule = require(ModulesFolder:WaitForChild("PopUpModule"))

local PLACE_ID = 129073777843683
local CLAIM_TIMEOUT = 6

local rewardRemote = ReplicatedStorage:WaitForChild("LimitedRewardClaim")

local mainGui = playerGui:WaitForChild("Frames")
local limitedRewardFrame = mainGui:WaitForChild("LimitedReward")
local mainFrame = limitedRewardFrame:WaitForChild("Main")
local claimButton = mainFrame:WaitForChild("JoinEvent")

local rewardAlreadyClaimedLocal = false
local claimPending = false

local function showRewardPopup()
	PopUpModule:Local_SendPopUp(
		"Reward claimed.",
		Color3.new(1, 1, 1),
		Color3.new(0, 0.8, 0),
		2,
		false
	)
end

local function showJoinGroupPopup()
	PopUpModule:Local_SendPopUp(
		"Join the group first.",
		Color3.new(1, 1, 1),
		Color3.new(0, 0, 0),
		2,
		true
	)
end

local function showUnavailablePopup()
	PopUpModule:Local_SendPopUp(
		"Reward unavailable right now.",
		Color3.new(1, 1, 1),
		Color3.new(0, 0, 0),
		2,
		true
	)
end

local function showAlreadyClaimedPopup()
	PopUpModule:Local_SendPopUp(
		"You have already claimed this reward.",
		Color3.new(1, 1, 1),
		Color3.new(0.8, 0.8, 0.8),
		2,
		false
	)
end

local function hasRewardAlready()
	if rewardAlreadyClaimedLocal then
		return true
	end
	local hiddenStats = player:FindFirstChild("HiddenLeaderstats")
	if not hiddenStats then
		return false
	end
	local flag = hiddenStats:FindFirstChild("LimitedReward")
	if flag and flag:IsA("BoolValue") and flag.Value == true then
		rewardAlreadyClaimedLocal = true
		return true
	end
	return false
end

local CLICK_COOLDOWN = 0.2
local lastClick = 0

rewardRemote.OnClientEvent:Connect(function(status)
	claimPending = false

	if status == "Granted" then
		rewardAlreadyClaimedLocal = true
		showRewardPopup()
	elseif status == "AlreadyClaimed" then
		rewardAlreadyClaimedLocal = true
		showAlreadyClaimedPopup()
	elseif status == "NotInGroup" then
		showJoinGroupPopup()
	elseif status == "Unavailable" then
		showUnavailablePopup()
	end
end)

local function onClaimClicked()
	local now = os.clock()
	if (now - lastClick) < CLICK_COOLDOWN then
		return
	end
	lastClick = now

	if hasRewardAlready() then
		showAlreadyClaimedPopup()
		return
	end

	if claimPending then
		return
	end

	claimPending = true
	rewardRemote:FireServer(PLACE_ID)
	task.delay(CLAIM_TIMEOUT, function()
		if claimPending then
			claimPending = false
			showUnavailablePopup()
		end
	end)
end

if claimButton:IsA("TextButton") or claimButton:IsA("ImageButton") then
	claimButton.MouseButton1Click:Connect(onClaimClicked)
else
	claimButton.Activated:Connect(onClaimClicked)
end
