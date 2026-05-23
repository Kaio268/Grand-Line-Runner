local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local LEGACY_SERVER_SCRIPT_NAMES = {
	Plot = true,
	PlotUpgrades = true,
}

local function formatPath(instance)
	return instance and instance:GetFullName() or "<nil>"
end

local function disableLegacyScript(instance, reason)
	if not instance then
		return
	end

	if not instance:IsA("Script") then
		warn(("[LegacyPlotCleanup] Ignoring unexpected %s at %s."):format(instance.ClassName, formatPath(instance)))
		return
	end

	if instance.Enabled then
		instance.Enabled = false
		warn(("[LegacyPlotCleanup] Disabled legacy plot script %s (%s)."):format(formatPath(instance), tostring(reason)))
	end
end

local function disableKnownLegacyScripts(container, reason)
	if not container then
		return
	end

	for scriptName in pairs(LEGACY_SERVER_SCRIPT_NAMES) do
		disableLegacyScript(container:FindFirstChild(scriptName), reason)
	end
end

local function clearFolderChildren(folder, label)
	if not folder or not folder:IsA("Folder") then
		return
	end

	local children = folder:GetChildren()
	if #children == 0 then
		return
	end

	for _, child in ipairs(children) do
		child:Destroy()
	end

	warn(("[LegacyPlotCleanup] Cleared %d legacy %s from %s."):format(#children, label, formatPath(folder)))
end

local function clearLegacyPlotRuntimeOutput()
	local plotSystem = workspace:FindFirstChild("PlotSystem")
	local plotsFolder = plotSystem and plotSystem:FindFirstChild("Plots")
	clearFolderChildren(plotsFolder, "plot runtime clone(s)")

	local hiddenPlots = ServerStorage:FindFirstChild("HiddenPlots")
	clearFolderChildren(hiddenPlots, "hidden plot runtime folder(s)")
end

local function removeLegacyPlotCommandBridge()
	local signalsRoot = ServerScriptService:FindFirstChild("ShipRuntimeSignals")
	local plotCommand = signalsRoot and signalsRoot:FindFirstChild("PlotCommand")
	if plotCommand and plotCommand:IsA("BindableFunction") then
		plotCommand:Destroy()
		warn("[LegacyPlotCleanup] Removed deprecated ShipRuntimeSignals.PlotCommand bindable.")
	end
end

local function runCleanup(reason)
	disableKnownLegacyScripts(script.Parent, reason)
	clearLegacyPlotRuntimeOutput()
	removeLegacyPlotCommandBridge()
end

local function hookLegacyScriptReappearance()
	script.Parent.ChildAdded:Connect(function(child)
		if LEGACY_SERVER_SCRIPT_NAMES[child.Name] then
			disableLegacyScript(child, "child_added")
		end
	end)
end

local function hookLegacyPlotCloneReappearance()
	local plotSystem = workspace:FindFirstChild("PlotSystem")
	local plotsFolder = plotSystem and plotSystem:FindFirstChild("Plots")
	if not plotsFolder or not plotsFolder:IsA("Folder") then
		return
	end

	plotsFolder.ChildAdded:Connect(function(child)
		warn(("[LegacyPlotCleanup] Destroyed legacy plot runtime clone %s."):format(formatPath(child)))
		child:Destroy()
	end)
end

runCleanup("startup")
hookLegacyScriptReappearance()
hookLegacyPlotCloneReappearance()

task.defer(runCleanup, "deferred")
task.delay(1, runCleanup, "delayed")
