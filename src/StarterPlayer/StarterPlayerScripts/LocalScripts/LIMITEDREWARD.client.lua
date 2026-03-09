local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

local player = Players.LocalPlayer
local playerGui = player.PlayerGui

local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PopUpModule = require(ModulesFolder:WaitForChild("PopUpModule"))

local PLACE_ID = 129073777843683
local ITEM_TYPE = Enum.AvatarItemType.Asset
local COOLDOWN_TIME = 5

local rewardRemote = ReplicatedStorage:WaitForChild("LimitedRewardClaim")

local mainGui = playerGui:WaitForChild("Frames")
local limitedRewardFrame = mainGui:WaitForChild("LimitedReward")
local mainFrame = limitedRewardFrame:WaitForChild("Main")
local claimButton = mainFrame:WaitForChild("JoinEvent")
local innerFrame = limitedRewardFrame:WaitForChild("Frame")
local likeTextLabel = innerFrame:WaitForChild("Like"):WaitForChild("TextL")
local favoriteTextLabel = innerFrame:WaitForChild("Favorite"):WaitForChild("TextL")

local hasInventoryAccess = false
local cooldownStarted = false
local cooldownFinished = false
local rewardAlreadyClaimedLocal = false

AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(result)
	if result == Enum.AvatarPromptResult.Success then
		hasInventoryAccess = true
	else
		hasInventoryAccess = false
	end
end)

local function showLikePopup()
	PopUpModule:Local_SendPopUp(
		"You must leave a like on the game.",
		Color3.new(1, 1, 1),
		Color3.new(0, 0, 0),
		2,
		true
	)
end

local function showFavoritePopup()
	PopUpModule:Local_SendPopUp(
		"Please leave a favorite on the game.",
		Color3.new(1, 1, 1),
		Color3.new(0, 0, 0),
		2,
		true
	)
end

local function showRewardPopup()
	PopUpModule:Local_SendPopUp(
		"Reward claimed.",
		Color3.new(1, 1, 1),
		Color3.new(0, 0.8, 0),
		2,
		false
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

local function getFavoriteState()
	if not hasInventoryAccess then
		return false
	end
	local ok, result = pcall(function()
		return AvatarEditorService:GetFavorite(PLACE_ID, ITEM_TYPE)
	end)
	if not ok then
		return false
	end
	return result
end

local function getLikeAndFavorite()
	local hasLike = likeTextLabel.Text == "1/1"
	local isFavorited = getFavoriteState()
	if isFavorited then
		favoriteTextLabel.Text = "1/1"
	else
		favoriteTextLabel.Text = "0/1"
	end
	return hasLike, isFavorited
end

local function startCooldown()
	if cooldownStarted then
		return
	end
	cooldownStarted = true
	task.delay(COOLDOWN_TIME, function()
		cooldownFinished = true
		if hasInventoryAccess then
			local isFavorited = getFavoriteState()
			if isFavorited then
				likeTextLabel.Text = "1/1"
			end
		end
	end)
end
local CLICK_COOLDOWN = 0.2
local lastClick = 0
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

	if not hasInventoryAccess then
		AvatarEditorService:PromptAllowInventoryReadAccess()
	end

	if not cooldownStarted then
		startCooldown()
	end

	if not cooldownFinished then
		local hasLike, isFavorited = false, false
		if hasInventoryAccess then
			hasLike, isFavorited = getLikeAndFavorite()
		end
		if not hasInventoryAccess or not isFavorited then
			showFavoritePopup()
		else
			showLikePopup()
		end
		return
	end

	local hasLike, isFavorited = getLikeAndFavorite()

	if isFavorited and likeTextLabel.Text ~= "1/1" then
		likeTextLabel.Text = "1/1"
		hasLike = true
	end

	if hasLike and isFavorited then
		rewardRemote:FireServer(PLACE_ID, hasLike, isFavorited)
		showRewardPopup()
		rewardAlreadyClaimedLocal = true
	else
		if not isFavorited then
			showFavoritePopup()
		elseif not hasLike then
			showLikePopup()
		end
	end
end

if claimButton:IsA("TextButton") or claimButton:IsA("ImageButton") then
	claimButton.MouseButton1Click:Connect(onClaimClicked)
else
	claimButton.Activated:Connect(onClaimClicked)
end
