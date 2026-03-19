local ServerScriptService = game:GetService("ServerScriptService")

local Module = {}

local ROOT_NAME = "ShipRuntimeSignals"

local function ensureRoot()
	local root = ServerScriptService:FindFirstChild(ROOT_NAME)
	if root and not root:IsA("Folder") then
		root:Destroy()
		root = nil
	end

	if not root then
		root = Instance.new("Folder")
		root.Name = ROOT_NAME
		root.Parent = ServerScriptService
	end

	return root
end

local function ensureBindableFunction(name)
	local root = ensureRoot()
	local bindable = root:FindFirstChild(name)
	if bindable and not bindable:IsA("BindableFunction") then
		bindable:Destroy()
		bindable = nil
	end

	if not bindable then
		bindable = Instance.new("BindableFunction")
		bindable.Name = name
		bindable.Parent = root
	end

	return bindable
end

function Module.GetPlotCommandFunction()
	return ensureBindableFunction("PlotCommand")
end

function Module.GetStandCommandFunction()
	return ensureBindableFunction("StandCommand")
end

return Module
