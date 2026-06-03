local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ObjectiveIndicator = require(UiFolder:WaitForChild("Tutorial"):WaitForChild("ObjectiveIndicator"))

local TutorialObjectiveIndicatorController = {}
TutorialObjectiveIndicatorController.__index = TutorialObjectiveIndicatorController

function TutorialObjectiveIndicatorController.new(playerGui, options)
	options = if typeof(options) == "table" then options else {}

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = tostring(options.Name or "TutorialObjectiveGui")
	screenGui.DisplayOrder = math.floor(tonumber(options.DisplayOrder) or 181)
	screenGui.IgnoreGuiInset = options.IgnoreGuiInset ~= false
	screenGui.ResetOnSpawn = options.ResetOnSpawn == true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local self = setmetatable({
		_destroyed = false,
		_defaultZIndex = math.floor(tonumber(options.ZIndex) or 184),
		_root = ReactRoblox.createRoot(screenGui),
		_screenGui = screenGui,
	}, TutorialObjectiveIndicatorController)

	return self
end

function TutorialObjectiveIndicatorController:SetTarget(target, options)
	if self._destroyed then
		return
	end

	if typeof(target) ~= "table" then
		self:Clear()
		return
	end

	options = if typeof(options) == "table" then options else {}
	self._screenGui.Enabled = true
	self._root:render(React.createElement(ObjectiveIndicator, {
		target = target,
		zIndex = math.floor(tonumber(options.ZIndex or options.zIndex) or self._defaultZIndex),
		showPath = options.ShowPath == true or options.showPath == true,
		pathOptions = options.PathOptions or options.pathOptions,
	}))
end

function TutorialObjectiveIndicatorController:Clear()
	if self._destroyed then
		return
	end

	self._screenGui.Enabled = false
	self._root:render(React.createElement(React.Fragment))
end

function TutorialObjectiveIndicatorController:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._root:unmount()
	self._screenGui:Destroy()
end

return TutorialObjectiveIndicatorController
