
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local PlotSystem = workspace:WaitForChild("PlotSystem")
local PlotsFolder = PlotSystem:WaitForChild("Plots")

local function setIndicatorVisible(plotModel, state)
	local home = plotModel:FindFirstChild("HOME", true)
	if not home then return end

	local billboard = home:FindFirstChild("BillboardGui")
	if not billboard then return end

	local imageLabel = billboard:FindFirstChild("ImageLabel")
	if not imageLabel or not imageLabel:IsA("ImageLabel") then return end

	imageLabel.Visible = state
end

local function isMyPlot(plotModel)
	local ownerId = plotModel:GetAttribute("OwnerUserId")
	if ownerId ~= nil then
		return ownerId == localPlayer.UserId
	end

	return plotModel.Name == localPlayer.Name
end

local function updateAllPlots()
	for _, plot in ipairs(PlotsFolder:GetChildren()) do
		if plot:IsA("Model") then
			setIndicatorVisible(plot, isMyPlot(plot))
		end
	end
end

local function watchPlot(plot)
	if not plot:IsA("Model") then return end

	task.defer(function()
		setIndicatorVisible(plot, isMyPlot(plot))
	end)

	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		setIndicatorVisible(plot, isMyPlot(plot))
	end)

	plot.DescendantAdded:Connect(function(desc)
		if desc.Name == "Home" or desc.Name == "BillboardGui" or desc.Name == "ImageLabel" then
			setIndicatorVisible(plot, isMyPlot(plot))
		end
	end)
end

for _, plot in ipairs(PlotsFolder:GetChildren()) do
	watchPlot(plot)
end

PlotsFolder.ChildAdded:Connect(function(plot)
	watchPlot(plot)
	updateAllPlots()
end)

PlotsFolder.ChildRemoved:Connect(function()
	updateAllPlots()
end)

task.defer(updateAllPlots)
