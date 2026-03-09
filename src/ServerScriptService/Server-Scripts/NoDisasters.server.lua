local Workspace = game:GetService("Workspace")

local timer = Workspace:WaitForChild("NoDisastersTimer")

local running = false

local function countdown()
	if running then return end
	running = true

	while timer.Value > 0 do
		task.wait(1)
		if timer.Value > 0 then
			timer.Value -= 1
		end
	end

	running = false
end

timer:GetPropertyChangedSignal("Value"):Connect(function()
	if timer.Value > 0 then
		countdown()
	end
end)

if timer.Value > 0 then
	countdown()
end
