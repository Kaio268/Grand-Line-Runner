local CrewIncomeRuntime = {}

local started = false

local CrewIncomeFolder = script.Parent:WaitForChild("CrewIncome")
local Context = require(CrewIncomeFolder:WaitForChild("Context"))

local installers = {
	require(CrewIncomeFolder:WaitForChild("CrewResolver")),
	require(CrewIncomeFolder:WaitForChild("StandState")),
	require(CrewIncomeFolder:WaitForChild("SlotRuntimeCache")),
	require(CrewIncomeFolder:WaitForChild("VisualRuntime")),
	require(CrewIncomeFolder:WaitForChild("DisplayRuntime")),
	require(CrewIncomeFolder:WaitForChild("ClaimRuntime")),
	require(CrewIncomeFolder:WaitForChild("PromptRuntime")),
	require(CrewIncomeFolder:WaitForChild("CaptainBridge")),
	require(CrewIncomeFolder:WaitForChild("StandRegistry")),
	require(CrewIncomeFolder:WaitForChild("Bootstrap")),
	require(CrewIncomeFolder:WaitForChild("BankLoop")),
}

function CrewIncomeRuntime.Start()
	if started then
		return
	end
	started = true

	local ctx = Context.Create()
	for _, installer in ipairs(installers) do
		installer.Install(ctx)
	end

	if typeof(ctx.StartBankLoop) == "function" then
		ctx.StartBankLoop()
	end
end

return CrewIncomeRuntime
