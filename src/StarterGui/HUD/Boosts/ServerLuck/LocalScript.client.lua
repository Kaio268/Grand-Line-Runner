
local imageObject = script.Parent
local serverLuck = workspace:WaitForChild("ServerLuck")

local images = {
	[2] = "rbxassetid://118518723004729",
	[4] = "rbxassetid://81862592925901",
	[8] = "rbxassetid://107262434211544",
	[16] = "rbxassetid://80206263750065"
}

local function updateImage()
	local value = serverLuck.Value
	local newImage = images[value]

	if newImage then
		imageObject.Image = newImage
	end
end

updateImage()

serverLuck:GetPropertyChangedSignal("Value"):Connect(updateImage)
