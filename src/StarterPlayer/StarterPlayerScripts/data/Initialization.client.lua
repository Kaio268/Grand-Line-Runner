if not game:IsLoaded() then game.Loaded:Wait() end
local Start = tick()

local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local DataScript = require(script.Parent.Client_Data)
DataScript.New("PlayerDataStore")

DataScript.WaitUntilReady()
DataScript:GetData()

print("✅ Client {RP} took " .. (tick() - Start) .. "s to load!")
