local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local WantedPoster = require(script.Parent:WaitForChild("WantedPoster"))

local e = React.createElement

-- Tune these values in Studio to align each React poster over the physical parchment slots.
-- The one SurfaceGui is the full board canvas; each slot is positioned as a percentage of it.
local SLOT_LAYOUT = {
	{ position = UDim2.fromScale(0.015, 0.055), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.207, 0.055), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.399, 0.055), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.591, 0.055), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.783, 0.055), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.015, 0.555), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.207, 0.555), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.399, 0.555), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.591, 0.555), size = UDim2.fromScale(0.18, 0.385) },
	{ position = UDim2.fromScale(0.783, 0.555), size = UDim2.fromScale(0.18, 0.385) },
}

local function WantedBoard(props)
	local entries = props.entries or {}
	local children = {}

	for index, layout in ipairs(SLOT_LAYOUT) do
		children["Slot" .. tostring(index)] = e("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = false,
			Position = layout.position,
			Size = layout.size,
		}, {
			Poster = e(WantedPoster, {
				entry = entries[index],
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
	}, children)
end

return WantedBoard
