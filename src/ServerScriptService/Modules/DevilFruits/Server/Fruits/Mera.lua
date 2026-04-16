local MeraServerFruit = {}

local function getFruitFolder(parent, fruitFolderName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == fruitFolderName and child:IsA("Folder") then
			return child
		end
	end

	error(string.format("[DevilFruits] Missing fruit folder %s under %s", fruitFolderName, parent:GetFullName()))
end

function MeraServerFruit.GetLegacyHandler()
	return require(getFruitFolder(script.Parent.Parent.Parent, "Mera"):WaitForChild("Server"):WaitForChild("MeraServer"))
end

return MeraServerFruit
