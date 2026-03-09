local ServerStorage = game:GetService("ServerStorage")

local timer       = workspace:WaitForChild("ServerLuckTimer")
local serverLuck = workspace:WaitForChild("ServerLuck")

local isCounting = false

local function startCountdown()
	if isCounting then return end   
	if timer.Value <= 0 then return end 

	isCounting = true

	while timer.Value > 0 do
		wait(1)         
		timer.Value = timer.Value - 1 
	end

	serverLuck.Value = 1  
	isCounting = false          
end

timer:GetPropertyChangedSignal("Value"):Connect(function()
	if timer.Value > 0 then
		startCountdown()
	end
end)
