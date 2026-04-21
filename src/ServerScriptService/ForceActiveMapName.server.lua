local Workspace = game:GetService("Workspace")

-- Keep the renamed main gameplay map selected after the map swap.
Workspace:SetAttribute("ActiveMapName", "Map")

print("[MAP TRACE] Server forced ActiveMapName =", Workspace:GetAttribute("ActiveMapName"))
