local HieServerFruit = {}

local function getFruitFolder(parent, fruitFolderName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == fruitFolderName and child:IsA("Folder") then
			return child
		end
	end

	error(string.format("[DevilFruits] Missing fruit folder %s under %s", fruitFolderName, parent:GetFullName()))
end

function HieServerFruit.GetLegacyHandler()
	return require(getFruitFolder(script.Parent.Parent.Parent, "Hie"):WaitForChild("Server"):WaitForChild("HieServer"))
end

return HieServerFruit
