local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ReactFrameModalAdapter = require(Modules:WaitForChild("ReactFrameModalAdapter"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local LimitedRewardScreen = require(UiFolder:WaitForChild("LimitedReward"):WaitForChild("LimitedRewardScreen"))

local PLACE_ID = 129073777843683
local ITEM_TYPE = Enum.AvatarItemType.Asset
local COOLDOWN_TIME = 5
local CLICK_COOLDOWN = 0.2

local RewardRemote = ReplicatedStorage:WaitForChild("LimitedRewardClaim")

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactLimitedRewardRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "LimitedReward",
	hostName = "ReactLimitedRewardHost",
	backdropName = "ReactLimitedRewardBackdrop",
	modalStateKey = "LimitedRewardModal",
	minSize = Vector2.new(460, 320),
	maxSize = Vector2.new(720, 460),
	frameSize = UDim2.fromScale(0.5, 0.46),
	createFrameIfMissing = true,
	standalone = true,
})

local destroyed = false
local renderQueued = false
local connections = {}
local hasInventoryAccess = false
local cooldownStarted = false
local cooldownFinished = false
local rewardAlreadyClaimedLocal = false
local favoriteText = "0/1"
local likeText = "0/1"
local lastClick = 0
local scheduleRender

local unregisterModal = ReactModalRegistry.Register("LimitedReward", {
	toggle = function()
		modalAdapter:Toggle()
		if scheduleRender then
			scheduleRender()
		end
	end,
	open = function()
		if not modalAdapter:IsVisible() then
			modalAdapter:Toggle()
		end
		if scheduleRender then
			scheduleRender()
		end
	end,
	close = function()
		modalAdapter:Close()
	end,
	isVisible = function()
		return modalAdapter:IsVisible()
	end,
})

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function showPopup(text, strokeColor, withSound)
	PopUpModule:Local_SendPopUp(text, Color3.new(1, 1, 1), strokeColor, 2, withSound)
end

local function hasRewardAlready()
	if rewardAlreadyClaimedLocal then
		return true
	end
	local hiddenStats = player:FindFirstChild("HiddenLeaderstats")
	local flag = hiddenStats and hiddenStats:FindFirstChild("LimitedReward")
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
	return ok and result == true
end

local function syncFavoriteState()
	local isFavorited = getFavoriteState()
	favoriteText = if isFavorited then "1/1" else "0/1"
	return isFavorited
end

scheduleRender = function()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			local host = modalAdapter:EnsureHost()
			if not host then
				return
			end

			root:render(ReactRoblox.createPortal(React.createElement(LimitedRewardScreen, {
				favoriteText = favoriteText,
				likeText = likeText,
				onClaim = function()
					local now = os.clock()
					if now - lastClick < CLICK_COOLDOWN then
						return
					end
					lastClick = now

					if hasRewardAlready() then
						showPopup("You have already claimed this reward.", Color3.new(0.8, 0.8, 0.8), false)
						return
					end

					if not hasInventoryAccess then
						AvatarEditorService:PromptAllowInventoryReadAccess()
					end

					if not cooldownStarted then
						cooldownStarted = true
						task.delay(COOLDOWN_TIME, function()
							cooldownFinished = true
							if hasInventoryAccess and syncFavoriteState() then
								likeText = "1/1"
							end
							scheduleRender()
						end)
					end

					if not cooldownFinished then
						local isFavorited = hasInventoryAccess and syncFavoriteState()
						scheduleRender()
						if not hasInventoryAccess or not isFavorited then
							showPopup("Please leave a favorite on the game.", Color3.new(0, 0, 0), true)
						else
							showPopup("You must leave a like on the game.", Color3.new(0, 0, 0), true)
						end
						return
					end

					local isFavorited = syncFavoriteState()
					if isFavorited and likeText ~= "1/1" then
						likeText = "1/1"
					end

					if likeText == "1/1" and isFavorited then
						RewardRemote:FireServer(PLACE_ID, true, true)
						showPopup("Reward claimed.", Color3.new(0, 0.8, 0), false)
						rewardAlreadyClaimedLocal = true
					elseif not isFavorited then
						showPopup("Please leave a favorite on the game.", Color3.new(0, 0, 0), true)
					else
						showPopup("You must leave a like on the game.", Color3.new(0, 0, 0), true)
					end
					scheduleRender()
				end,
				onClose = function()
					ReactModalRegistry.Close("LimitedReward")
				end,
				statusText = "Complete both steps, then claim your reward.",
			}), host))
			modalAdapter:SyncOverlayState()
		end
	end)
end

connections[#connections + 1] = AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(result)
	hasInventoryAccess = result == Enum.AvatarPromptResult.Success
	if hasInventoryAccess then
		syncFavoriteState()
	end
	scheduleRender()
end)

scheduleRender()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
