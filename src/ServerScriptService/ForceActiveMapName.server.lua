local Workspace = game:GetService("Workspace")

-- Temporary map override for server-side swap testing.
Workspace:SetAttribute("ActiveMapName", "NewMap_Test")

print("[MAP TRACE] Server forced ActiveMapName =", Workspace:GetAttribute("ActiveMapName"))
