local LIMITED_REWARD_ENABLED = false

if LIMITED_REWARD_ENABLED ~= true then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local PLACE_ID = game.PlaceId
local GROUP_ID = 17179624
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
local rewardAlreadyClaimedLocal = false
local groupText = "0/1"
local claimText = "0/1"
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

local function syncRequirementState()
	local inGroup = false
	local ok, result = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	if ok and result == true then
		inGroup = true
	end

	groupText = if inGroup then "1/1" else "0/1"
	claimText = if hasRewardAlready() then "1/1" else "0/1"
	return inGroup
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

			syncRequirementState()
			root:render(ReactRoblox.createPortal(React.createElement(LimitedRewardScreen, {
				groupText = groupText,
				claimText = claimText,
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

					local inGroup = syncRequirementState()
					if not inGroup then
						scheduleRender()
						showPopup("Join the group to claim this reward.", Color3.new(0, 0, 0), true)
						return
					end

					RewardRemote:FireServer(PLACE_ID)
					showPopup("Checking reward claim...", Color3.new(0, 0.8, 0), false)
					scheduleRender()
				end,
				onClose = function()
					ReactModalRegistry.Close("LimitedReward")
				end,
				statusText = "Join the group, then claim your one-time limited reward.",
			}), host))
			modalAdapter:SyncOverlayState()
		end
	end)
end

connections[#connections + 1] = RewardRemote.OnClientEvent:Connect(function(status)
	if status == "Granted" then
		rewardAlreadyClaimedLocal = true
		syncRequirementState()
		showPopup("Reward claimed.", Color3.new(0, 0.8, 0), false)
	elseif status == "AlreadyClaimed" then
		rewardAlreadyClaimedLocal = true
		syncRequirementState()
		showPopup("You have already claimed this reward.", Color3.new(0.8, 0.8, 0.8), false)
	elseif status == "NotInGroup" then
		syncRequirementState()
		showPopup("Join the group to claim this reward.", Color3.new(0, 0, 0), true)
	else
		showPopup("Reward is unavailable right now.", Color3.new(0, 0, 0), true)
	end
	scheduleRender()
end)

syncRequirementState()
scheduleRender()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
