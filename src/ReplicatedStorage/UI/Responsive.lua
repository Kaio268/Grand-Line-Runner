local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Responsive = {}

Responsive.DESIGN_VIEWPORT = Vector2.new(1280, 720)
Responsive.BREAKPOINTS = {
	MobileMaxWidth = 760,
	MobileMaxHeight = 560,
	MobileMaxArea = 760 * 720,
	TabletLikeMaxLongSide = 1500,
	TabletLikeMaxShortSide = 1100,
	TabletLikeMinShortSide = 600,
	TabletLikeMaxAspect = 1.7,
	CompactMaxWidth = 900,
	CompactMaxHeight = 700,
	CompactMaxArea = 1100 * 720,
}
Responsive.SCALE_LIMITS = {
	DesktopMin = 0.85,
	DesktopMax = 1.25,
	CompactMin = 0.9,
	CompactMax = 1.05,
}

local function roundToHundredths(value)
	return math.floor((value * 100) + 0.5) / 100
end

function Responsive.getViewportSize()
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or Responsive.DESIGN_VIEWPORT
end

function Responsive.getViewport()
	return Responsive.getViewportSize()
end

function Responsive.hasTouchOnlyInput()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function Responsive.isPhoneViewport(viewport)
	local size = viewport or Responsive.getViewportSize()
	local width = size.X
	local height = size.Y
	local shortSide = math.min(width, height)
	local area = width * height
	local landscape = width > height
	local breakpoints = Responsive.BREAKPOINTS

	return width <= breakpoints.MobileMaxWidth
		or shortSide <= breakpoints.MobileMaxHeight
		or (landscape and area <= breakpoints.MobileMaxArea)
end

function Responsive.isMobile(viewport)
	local size = viewport or Responsive.getViewportSize()

	return Responsive.hasTouchOnlyInput() and (Responsive.isPhoneViewport(size) or Responsive.isTabletViewport(size))
end

function Responsive.isTabletViewport(viewport)
	local size = viewport or Responsive.getViewportSize()

	return Responsive.hasTouchOnlyInput() and not Responsive.isPhoneViewport(size)
end

function Responsive.isTabletLikeViewport(viewport)
	local size = viewport or Responsive.getViewportSize()
	if Responsive.isPhoneViewport(size) then
		return false
	end

	local longSide = math.max(size.X, size.Y)
	local shortSide = math.min(size.X, size.Y)
	local aspect = longSide / math.max(shortSide, 1)
	local breakpoints = Responsive.BREAKPOINTS

	return longSide <= breakpoints.TabletLikeMaxLongSide
		and shortSide <= breakpoints.TabletLikeMaxShortSide
		and shortSide >= breakpoints.TabletLikeMinShortSide
		and aspect <= breakpoints.TabletLikeMaxAspect
end

function Responsive.isCompact(viewport)
	local size = viewport or Responsive.getViewportSize()
	local width = size.X
	local height = size.Y
	local shortSide = math.min(width, height)
	local area = width * height
	local breakpoints = Responsive.BREAKPOINTS

	return width <= breakpoints.CompactMaxWidth
		or height <= breakpoints.CompactMaxHeight
		or shortSide <= breakpoints.MobileMaxHeight
		or area <= breakpoints.CompactMaxArea
end

function Responsive.getHudLayoutMode(viewport)
	local size = viewport or Responsive.getViewportSize()
	if Responsive.hasTouchOnlyInput() then
		return if Responsive.isPhoneViewport(size) then "phone" else "tablet"
	end

	return if Responsive.isCompact(size) then "compactDesktop" else "desktop"
end

function Responsive.getViewportLayoutMode(viewport)
	local size = viewport or Responsive.getViewportSize()
	if Responsive.isPhoneViewport(size) then
		return "phone"
	end

	if Responsive.isTabletLikeViewport(size) then
		return "tablet"
	end

	return if Responsive.isCompact(size) then "compactDesktop" else "desktop"
end

function Responsive.getClass(viewport)
	local mode = Responsive.getHudLayoutMode(viewport)
	return if mode == "phone" or mode == "tablet" then "mobile" elseif mode == "compactDesktop" then "compact" else "desktop"
end

function Responsive.getDesktopScale(viewport)
	local size = viewport or Responsive.getViewportSize()
	local widthScale = size.X / Responsive.DESIGN_VIEWPORT.X
	local heightScale = size.Y / Responsive.DESIGN_VIEWPORT.Y
	local scale = math.min(widthScale, heightScale)
	local limits = Responsive.SCALE_LIMITS

	return roundToHundredths(math.clamp(scale, limits.DesktopMin, limits.DesktopMax))
end

function Responsive.getUiScale(viewport)
	local size = viewport or Responsive.getViewportSize()

	if Responsive.hasTouchOnlyInput() then
		return 1
	end

	local desktopScale = Responsive.getDesktopScale(size)
	if Responsive.isCompact(size) then
		local limits = Responsive.SCALE_LIMITS
		return roundToHundredths(math.clamp(desktopScale, limits.CompactMin, limits.CompactMax))
	end

	return desktopScale
end

function Responsive.scaleNumber(value, viewport)
	return (tonumber(value) or 0) * Responsive.getUiScale(viewport)
end

function Responsive.scaleOffset(value, viewport)
	return math.floor(Responsive.scaleNumber(value, viewport) + 0.5)
end

return Responsive
