local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local vipValue = player:WaitForChild("Passes"):WaitForChild("VIP")
local vipFolder = workspace:WaitForChild("Map"):WaitForChild("VipParts")

local GAMEPASS_ID = 912847213

local connections = {}
local lastPromptAt = 0

local function isLocalCharacterHit(hit)
	local char = player.Character
	if not char then return false end
	return hit and hit:IsDescendantOf(char)
end

local function setVipLook(part)
	part.CanCollide = false
	part.Transparency = 0.9

	local sg = part:FindFirstChild("SurfaceGui")
	if sg then
		local img = sg:FindFirstChild("ImageLabel", true)
		if img and img:IsA("ImageLabel") then
			img.ImageTransparency = 0.89
		end
	end
end

local function connectPart(part)
	if not part:IsA("BasePart") then return end
	if connections[part] then return end

	connections[part] = part.Touched:Connect(function(hit)
		if vipValue.Value == true then return end
		if not isLocalCharacterHit(hit) then return end

		local now = os.clock()
		if now - lastPromptAt < 1 then return end
		lastPromptAt = now

		MarketplaceService:PromptGamePassPurchase(player, GAMEPASS_ID)
	end)
end

local function applyState()
	if vipValue.Value == true then
		for _, obj in ipairs(vipFolder:GetDescendants()) do
			if obj:IsA("BasePart") then
				setVipLook(obj)
			end
		end
	end
end

for _, obj in ipairs(vipFolder:GetDescendants()) do
	if obj:IsA("BasePart") then
		connectPart(obj)
	end
end

vipFolder.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") then
		connectPart(obj)
		if vipValue.Value == true then
			setVipLook(obj)
		end
	end
end)

vipValue:GetPropertyChangedSignal("Value"):Connect(applyState)
applyState()
