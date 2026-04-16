local function hideGuiObject(guiObject, preserveImageData)
	if not guiObject or not guiObject:IsA("GuiObject") then
		return
	end

	guiObject.Visible = false
	guiObject.BackgroundTransparency = 1

	if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox") then
		guiObject.TextTransparency = 1
		guiObject.TextStrokeTransparency = 1
	end
end

local function hideCompatibilityCounter(host, preserveImages)
	if not host or not host:IsA("GuiObject") then
		return
	end

	hideGuiObject(host, false)

	local preserved = {}
	for _, instance in ipairs(preserveImages or {}) do
		if typeof(instance) == "Instance" then
			preserved[instance] = true
			hideGuiObject(instance, true)
		end
	end

	for _, descendant in ipairs(host:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			hideGuiObject(descendant, preserved[descendant] == true)
		end
	end
end

return {
	hideGuiObject = hideGuiObject,
	hideCompatibilityCounter = hideCompatibilityCounter,
}
