local Workspace = game:GetService("Workspace")

-- Keep the renamed main gameplay map selected after the map swap.
Workspace:SetAttribute("ActiveMapName", "Map")

if game:GetAttribute("MapTraceDebug") == true then
	print("[MAP TRACE] Server forced ActiveMapName =", Workspace:GetAttribute("ActiveMapName"))
end
