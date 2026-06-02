local function getStructuredPhoenixFolder()
	for _, child in ipairs(script.Parent:GetChildren()) do
		if child.Name == "Phoenix" and child:IsA("Folder") then
			return child
		end
	end

	error("[Phoenix] Missing structured Phoenix folder")
end

return require(getStructuredPhoenixFolder():WaitForChild("Server"):WaitForChild("PhoenixServer"))
