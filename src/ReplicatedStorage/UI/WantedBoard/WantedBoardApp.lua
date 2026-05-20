local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local WantedBoard = require(script.Parent:WaitForChild("WantedBoard"))

local e = React.createElement

local function WantedBoardApp(props)
	return e(WantedBoard, {
		entries = props.entries,
	})
end

return WantedBoardApp
