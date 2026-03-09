if not game:IsLoaded() then game.Loaded:Wait() end
local Start = tick()

local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local Modules_Table = {}

local function requireModules(Folder)
	for _, Module_Script in pairs(Folder:GetChildren()) do
		if Module_Script:IsA("ModuleScript") then
			local Module_Req = require(Module_Script)

			if type(Module_Req) == "table" then
				setmetatable(Module_Req, {__index = Modules_Table})
				Modules_Table[Module_Script.Name] = Module_Req

				if type(Module_Req.Init) == "function" then
					task.spawn(function()
						Module_Req:Init()
					end)
				end
			else
				warn("⚠️ Module '" .. Module_Script.Name .. "' did not return a table (returned " .. typeof(Module_Req) .. ")")
			end
		end
	end
end


local localModulesFolder = script.Parent.Modules
requireModules(localModulesFolder)

local UIStrokeAdjuster = require(script.UIStrokeAdjuster)

 
print("✅ Client {RP} took " .. (tick() - Start) .. "s to load!")
