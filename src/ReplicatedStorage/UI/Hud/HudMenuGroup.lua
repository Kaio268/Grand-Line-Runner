local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local React = require(Packages:WaitForChild("React"))

local HudMenuTile = require(script.Parent:WaitForChild("HudMenuTile"))

local e = React.createElement

local function HudMenuGroup(props)
	local children = {}

	for index, tile in ipairs(props.tiles or {}) do
		children[tile.name .. tostring(index)] = e(HudMenuTile, tile)
	end

	return e(React.Fragment, nil, children)
end

return HudMenuGroup
