local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ReactNpcDialogService = require(Modules:WaitForChild("ReactNpcDialogService"))
local NpcDialogScreen = require(UiFolder:WaitForChild("NpcDialog"):WaitForChild("NpcDialogScreen"))

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactNpcDialogRoot"
rootContainer.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)
local destroyed = false
local connections = {}

local KEY_TO_INDEX = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local function render()
	if destroyed then
		return
	end

	local dialog = ReactNpcDialogService.GetActiveDialog()
	if dialog == nil then
		root:render(nil)
		return
	end

	root:render(ReactRoblox.createPortal(React.createElement(NpcDialogScreen, {
		message = dialog.message,
		onRespond = function(index)
			ReactNpcDialogService.Respond(index)
		end,
		responses = dialog.responses,
		title = dialog.title,
	}), playerGui))
end

connections[#connections + 1] = ReactNpcDialogService.GetChangedSignal():Connect(render)
connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end

	local responseIndex = KEY_TO_INDEX[input.KeyCode]
	if responseIndex then
		ReactNpcDialogService.Respond(responseIndex)
	end
end)

render()

script.Destroying:Connect(function()
	destroyed = true
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	root:unmount()
end)
