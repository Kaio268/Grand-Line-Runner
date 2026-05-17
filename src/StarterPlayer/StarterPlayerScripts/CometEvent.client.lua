local Workspace = game:GetService("Workspace")

local LEGACY_FOLDERS = {
	EventFX_Comets = true,
	EventFX_CometsClient = true,
}

local function cleanupLegacyFolder(folder)
	if folder and LEGACY_FOLDERS[folder.Name] then
		folder:Destroy()
	end
end

for _, folderName in ipairs({
	"EventFX_Comets",
	"EventFX_CometsClient",
}) do
	cleanupLegacyFolder(Workspace:FindFirstChild(folderName))
end

Workspace.ChildAdded:Connect(cleanupLegacyFolder)
