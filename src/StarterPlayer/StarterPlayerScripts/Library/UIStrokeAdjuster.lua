--[=[
	Awesom3_Eric
	12/24/2024 @ 12:01AM
	@module UIStrokesAdjuster
		Adjusts the UIStrokes of GuiObjects based on viewport size and distance from BillboardGuis
]=]

--!strict



-----[[ Configuration ]]-----

-- Paste the following code into the command bar and change the Studio_Viewport_Size to the values in the output bar:
-- print(workspace.CurrentCamera.ViewportSize)
local Studio_Viewport_Size = Vector2.new(1920, 1080)

-- Set to true to automatically tag BillboardGuis and ScreenGuis recursively in PlayerGui
-- It's advised to use the :TagScreenGui() and :TagBillboardGui() features for the best performance
local Auto_Tag = true

-- Stroke sizes update every Update_Delay seconds
local Update_Delay = 1

-- Change if you want
local Billboard_Tag = "Billboard"
local Screen_Gui_Tag = "ScreenGui"
local UIStroke_Tag = "UIStroke"
local Screen_Stroke_Tag = "ScreenStroke"
local Default_Billboard_Distance = 15 -- Estimated distance if "Distance" attribute of BillboardGui is not set





-----[[ Initialization ]]-----

-- Services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Player
local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui", 100)

-- Variables
local camera = workspace.CurrentCamera





-----[[ Utility Functions ]]-----

--[=[
	Returns average resolution of Vector2
		@param vector2: Vector2
		@return min: number
]=]
local function getBox(vector2: Vector2): number
	return math.min(vector2.X, vector2.Y)
end

--[=[
	Returns ratio of current viewport size to studio viewport size
		@return viewportSize: number
]=]
local function getScreenRatio(): number
	return getBox(camera.ViewportSize)/getBox(Studio_Viewport_Size)
end

--[=[
	Recursively tags instance with tag based on objectType
	Listens for added instances
		@param instance: Instance
		@param objectType: string
		@param tag: string
]=]
local function tagRecursive(instance: Instance, objectType: string, tag: string)
	if instance:IsA(objectType) then
		instance:AddTag(tag)
	end
	for _, child in instance:GetChildren() do
		tagRecursive(child, objectType, tag)
	end
	instance.ChildAdded:Connect(function(child)
		tagRecursive(child, objectType, tag)
	end)
end

--[=[
	Returns position of part or model (for relative BillboardGui position)
		@param instance: Instance
		@return position: Vector3
]=]
local function getInstancePosition(instance: Instance): Vector3
	if instance:IsA("Part") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return Vector3.new(0, 0, 0)
end





-----[[ ScreenGui Updating ]]-----

-- Set OriginalThickness attribute
local function initTaggedUIStroke(uiStroke: UIStroke)
	-- Check if tagged instance is a UIStroke
	if not uiStroke:IsA("UIStroke") then
		uiStroke:RemoveTag(Screen_Stroke_Tag)
		uiStroke:RemoveTag(UIStroke_Tag)
		return
	end

	-- Initialize OriginalThickness
	if not uiStroke:GetAttribute("OriginalThickness") then
		uiStroke:SetAttribute("OriginalThickness", uiStroke.Thickness)
	end

	-- Initialize if has screen tag
	if uiStroke:HasTag(Screen_Stroke_Tag) then
		uiStroke.Thickness *= getScreenRatio()
	end
end

-- Initialize tagged UI Strokes
for _, uiStroke: UIStroke in CollectionService:GetTagged(UIStroke_Tag) do
	initTaggedUIStroke(uiStroke)
end

-- Listen for tagged UI Strokes
CollectionService:GetInstanceAddedSignal(UIStroke_Tag):Connect(initTaggedUIStroke)


-- Initialize currently tagged UIStrokes
for _, uiStroke: UIStroke in CollectionService:GetTagged(Screen_Stroke_Tag) do
	uiStroke:AddTag("UIStroke")
end

-- Indexes UIStroke in ScreenStrokes and its original thickness to update
CollectionService:GetInstanceAddedSignal(Screen_Stroke_Tag):Connect(function(uiStroke: UIStroke)
	uiStroke:AddTag("UIStroke")
end)


-- Recurisvely tags UIStrokes in ScreenGui that are currently tagged
for _, screenGui in CollectionService:GetTagged(Screen_Gui_Tag) do
	if not screenGui:IsA("ScreenGui") then
		screenGui:RemoveTag(Screen_Gui_Tag)
		continue
	end
	tagRecursive(screenGui, "UIStroke", Screen_Stroke_Tag)
end

-- Listen for new instances that are tagged
CollectionService:GetInstanceAddedSignal(Screen_Gui_Tag):Connect(function(screenGui: ScreenGui)
	if not screenGui:IsA("ScreenGui") then
		return
	end
	tagRecursive(screenGui, "UIStroke", Screen_Stroke_Tag)
end)


-- Updates ScreenGui strokes
local function updateScreenGuiStrokes()
	for _, uiStroke: UIStroke in CollectionService:GetTagged(Screen_Stroke_Tag) do
		local originalThickness = uiStroke:GetAttribute("OriginalThickness") :: number
		if originalThickness then
			uiStroke.Thickness = originalThickness * getScreenRatio()
		end
	end
end

-- Updates UIStrokes thickness in ScreenStrokes when camera viewport size changes
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScreenGuiStrokes)





-----[[ BillboardGui Updating ]]-----

-- This dictionary keeps track of the UIStrokes that are children of a billboard gui
-- Used to iterate and update UIStrokes based on distances
local BillboardData: {[BillboardGui]: {UIStroke}} = {}

-- Recurisvely tag ui strokes and append to BillboardData
local function recurseGetUIStrokes(instance: Instance, billboardGui: BillboardGui)
	if instance:IsA("UIStroke") then
		instance:AddTag("UIStroke")
		table.insert(BillboardData[billboardGui], instance)
	end
	for _, child in instance:GetChildren() do
		recurseGetUIStrokes(child, billboardGui)
	end
	instance.ChildAdded:Connect(function(child: Instance)
		recurseGetUIStrokes(child, billboardGui)
	end)
end

-- Initialize billboard
local function initBillboard(billboardGui: BillboardGui)	
	-- Remove tag is not billboard
	if not billboardGui:IsA("BillboardGui") then
		billboardGui:RemoveTag(Billboard_Tag)
		return
	end

	-- Create billboard
	-- Add clean function
	BillboardData[billboardGui] = {}
	billboardGui.Destroying:Once(function()
		BillboardData[billboardGui] = nil
	end)

	-- Get UIStrokes from Billboard recursively
	recurseGetUIStrokes(billboardGui, billboardGui)
end

-- Tag billboard guis
for _, billboardGui: BillboardGui in CollectionService:GetTagged(Billboard_Tag) do
	initBillboard(billboardGui)
end

-- Listen for tagged billboards
CollectionService:GetInstanceAddedSignal(Billboard_Tag):Connect(initBillboard)



-- Update UIStrokes every Update_Delay seconds
local start = tick()
local update; update = RunService.Heartbeat:Connect(function()
	if tick() - start < Update_Delay then 
		return 
	end
	start = tick()

	-- Update
	for billboardGui, uiStrokes in BillboardData do
		local adornee = billboardGui.Adornee
		local origin: Vector3

		-- Check adornee or parent
		if adornee then
			origin = getInstancePosition(adornee)
		else
			if billboardGui.Parent then
				origin = getInstancePosition(billboardGui.Parent)
			end
		end

		-- If no origin is defined, don't update
		if not origin then
			continue
		end

		-- Check if camera is within range
		local magnitude = (camera.CFrame.Position - origin).Magnitude
		local maxDistance = billboardGui.MaxDistance
		if magnitude > maxDistance then
			continue
		end
		
		-- Update BillboardStrokes
		local distanceRatio = ((billboardGui:GetAttribute("Distance") or Default_Billboard_Distance)/magnitude)
		for _, uiStroke in uiStrokes do
			if not uiStroke:IsDescendantOf(billboardGui) then
				table.remove(uiStrokes, table.find(uiStrokes, uiStroke))
			end
			
			local originalThickness = uiStroke:GetAttribute("OriginalThickness") :: number
			if originalThickness then
				uiStroke.Thickness = originalThickness * distanceRatio * getScreenRatio()
			end
		end
	end
end)





-----[[ Auto_Tag ]]-----

-- Automatically tag ScreenGuis and BillboardGuis in PlayerGui if Auto_Tag == true
if Auto_Tag then
	tagRecursive(PlayerGui, "ScreenGui", Screen_Gui_Tag)
	tagRecursive(PlayerGui, "BillboardGui", Billboard_Tag)
end





-----[[  Module Functions ]]-----

type UIStrokeAdjuster = {
	TagScreenGui: (self: UIStrokeAdjuster, screenGui: ScreenGui) -> (),
	TagBillboardGui: (self: UIStrokeAdjuster, billboardGui: BillboardGui) -> (),
}
type _UIStrokeAdjuster = UIStrokeAdjuster & {

}
local UIStrokeAdjuster = {} :: any

--[=[
	Tags ScreenGui to apply UIStrokes update
		@param screenGui: ScreenGui
]=]
function UIStrokeAdjuster.TagScreenGui(self: _UIStrokeAdjuster, screenGui: ScreenGui)
	if screenGui:IsA("ScreenGui") then
		CollectionService:AddTag(screenGui, Screen_Gui_Tag)
	end
end

--[=[
	Tags ScreenGui to apply UIStrokes update
		@param billboardGui: BillboardGui
]=]
function UIStrokeAdjuster.TagBillboardGui(self: _UIStrokeAdjuster, billboardGui: BillboardGui)
	if billboardGui:IsA("BillboardGui") then
		CollectionService:AddTag(billboardGui, Billboard_Tag)
	end
end

return UIStrokeAdjuster :: UIStrokeAdjuster
