local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Responsive = {}

local DEFAULT_VIEWPORT = Vector2.new(1280, 720)
local MOBILE_WIDTH = 760
local MOBILE_SHORT_SIDE = 560
local MOBILE_AREA = 760 * 720
local COMPACT_WIDTH = 900
local COMPACT_HEIGHT = 700
local COMPACT_AREA = 1100 * 720

function Responsive.getViewportSize()
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or DEFAULT_VIEWPORT
end

function Responsive.isMobile(viewport)
	local size = viewport or Responsive.getViewportSize()
	local width = size.X
	local height = size.Y
	local shortSide = math.min(width, height)
	local area = width * height
	local landscape = width > height

	if UserInputService.TouchEnabled then
		return true
	end

	if width <= MOBILE_WIDTH or shortSide <= MOBILE_SHORT_SIDE then
		return true
	end

	return landscape and area <= MOBILE_AREA
end

function Responsive.isCompact(viewport)
	local size = viewport or Responsive.getViewportSize()
	local width = size.X
	local height = size.Y
	local shortSide = math.min(width, height)
	local area = width * height

	return Responsive.isMobile(size)
		or width <= COMPACT_WIDTH
		or height <= COMPACT_HEIGHT
		or shortSide <= MOBILE_SHORT_SIDE
		or area <= COMPACT_AREA
end

function Responsive.getClass(viewport)
	return if Responsive.isMobile(viewport) then "mobile" elseif Responsive.isCompact(viewport) then "compact" else "desktop"
end

return Responsive
