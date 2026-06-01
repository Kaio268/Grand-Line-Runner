local Workspace = game:GetService("Workspace")

local BaseAreaService = {}

local BASE_AREA_NAMES = {
	"StartingArea",
	"Starting Area",
	"StartArea",
	"BaseArea",
	"Lobby",
}

local function findBaseArea()
	for _, name in ipairs(BASE_AREA_NAMES) do
		local found = Workspace:FindFirstChild(name, true)
		if found and (found:IsA("BasePart") or found:IsA("Model")) then
			return found
		end
	end
	return nil
end

local function isPointInsidePart(part, position, padding)
	local relative = part.CFrame:PointToObjectSpace(position)
	local halfSize = (part.Size * 0.5) + Vector3.new(padding, padding, padding)
	return math.abs(relative.X) <= halfSize.X
		and math.abs(relative.Y) <= halfSize.Y
		and math.abs(relative.Z) <= halfSize.Z
end

local function isPointInsideModel(model, position, padding)
	local cframe, size = model:GetBoundingBox()
	local relative = cframe:PointToObjectSpace(position)
	local halfSize = (size * 0.5) + Vector3.new(padding, padding, padding)
	return math.abs(relative.X) <= halfSize.X
		and math.abs(relative.Y) <= halfSize.Y
		and math.abs(relative.Z) <= halfSize.Z
end

function BaseAreaService.IsPlayerInBaseArea(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local area = findBaseArea()
	if area == nil then
		return false
	end

	local padding = 24
	if area:IsA("BasePart") then
		return isPointInsidePart(area, root.Position, padding)
	elseif area:IsA("Model") then
		return isPointInsideModel(area, root.Position, padding)
	end
	return false
end

return BaseAreaService
