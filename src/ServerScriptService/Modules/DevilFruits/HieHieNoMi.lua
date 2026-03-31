local function getFruitFolder(parent, fruitFolderName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == fruitFolderName and child:IsA("Folder") then
			return child
		end
	end

	error(string.format("[DevilFruits] Missing fruit folder %s under %s", fruitFolderName, parent:GetFullName()))
end

return require(getFruitFolder(script.Parent, "Hie"):WaitForChild("Server"):WaitForChild("HieServer"))
