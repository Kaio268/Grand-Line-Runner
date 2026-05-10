local ServerScriptService = game:GetService("ServerScriptService")

-- Compatibility bootstrap. CrewIncomeRuntime is the canonical implementation;
-- legacy script name remains so saved stand state and Studio wiring stay stable.
local CrewIncomeRuntime = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewIncomeRuntime"))

CrewIncomeRuntime.Start()
