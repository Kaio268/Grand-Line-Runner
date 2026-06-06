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
local GiftsViewBridge = require(Modules:WaitForChild("GiftsViewBridge"))
local TimeRewardsConfig = require(Modules:WaitForChild("TimeRewards"):WaitForChild("Config"))
local GiftsScreen = require(UiFolder:WaitForChild("Gifts"):WaitForChild("GiftsScreen"))

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactGiftsRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Gifts",
	hostName = "ReactGiftsHost",
	backdropName = "ReactGiftsBackdrop",
	backdropActive = false,
	modalStateKey = "GiftsModal",
	minSize = Vector2.new(520, 480),
	maxSize = Vector2.new(760, 720),
	frameSize = UDim2.fromScale(0.5, 0.66),
	createFrameIfMissing = true,
	standalone = true,
})

local rewardCount = 0
for rewardId in pairs(TimeRewardsConfig) do
	if tonumber(rewardId) ~= nil then
		rewardCount += 1
	end
end
rewardCount = math.max(rewardCount, 1)

local destroyed = false
local render

local noClipGuarded = setmetatable({}, { __mode = "k" })
local function keepUnclipped(inst)
	if not inst then
		return
	end

	inst.ClipsDescendants = false
	if noClipGuarded[inst] then
		return
	end

	noClipGuarded[inst] = true
	inst:GetPropertyChangedSignal("ClipsDescendants"):Connect(function()
		if inst.ClipsDescendants then
			inst.ClipsDescendants = false
		end
	end)
end

local unregisterModal = ReactModalRegistry.Register("Gifts", {
	toggle = function()
		modalAdapter:Toggle()
		if render then
			task.defer(render)
		end
	end,
	open = function()
		if not modalAdapter:IsVisible() then
			modalAdapter:Toggle()
		end
		if render then
			task.defer(render)
		end
	end,
	close = function()
		modalAdapter:Close()
	end,
	isVisible = function()
		return modalAdapter:IsVisible()
	end,
})

render = function()
	if destroyed then
		return
	end

	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end

	local frame = modalAdapter:GetFrame()
	if frame then
		frame.ZIndex = 120
		keepUnclipped(frame)
	end
	host.ZIndex = 140
	keepUnclipped(host)

	root:render(ReactRoblox.createPortal(React.createElement(GiftsScreen, {
		onClose = function()
			ReactModalRegistry.Close("Gifts")
		end,
		onRefsChanged = function(_, mainFrame, closeButton)
			GiftsViewBridge.SetRefs({
				frame = modalAdapter:GetFrame(),
				main = mainFrame,
				closeButton = closeButton,
			})
		end,
		rewardCount = rewardCount,
	}), host))
	modalAdapter:SyncOverlayState()
end

render()

script.Destroying:Connect(function()
	destroyed = true
	GiftsViewBridge.ClearRefs()
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
