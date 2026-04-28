local function getStructuredToriFolder()
	for _, child in ipairs(script.Parent:GetChildren()) do
		if child.Name == "Tori" and child:IsA("Folder") then
			return child
		end
	end

	error("[Tori] Missing structured Tori folder for legacy module fallback")
end

-- Keep legacy requires pointed at the maintained structured server module.
return require(getStructuredToriFolder():WaitForChild("Server"):WaitForChild("ToriServer"))
