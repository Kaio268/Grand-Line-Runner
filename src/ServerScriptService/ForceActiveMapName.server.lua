local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Keep the renamed main gameplay map selected after the map swap.
Workspace:SetAttribute("ActiveMapName", "Map")

if RunService:IsStudio() and game:GetAttribute("MapTraceDebug") == true then
	print("[MAP TRACE] Server forced ActiveMapName =", Workspace:GetAttribute("ActiveMapName"))
end
