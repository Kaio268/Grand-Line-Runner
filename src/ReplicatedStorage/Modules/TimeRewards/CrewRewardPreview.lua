local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrewRewardResolver = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewRewardResolver")
)
local CrewPreviewImages = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewPreviewImages")
)
local RandomCrewReward = require(script.Parent:WaitForChild("RandomCrewReward"))

local CrewRewardPreview = {}

local CREW_PREVIEW_ASSET_ROOT_NAME = "One Piece Characters"
local CREW_REWARD_VIEWPORT_NAME = "CrewMemberRewardViewport"
local CREW_REWARD_FALLBACK_NAME = "CrewMemberRewardFallback"
local CREW_PREVIEW_ROTATION = CFrame.Angles(math.rad(-12), math.rad(208), 0)

local function isImageGuiObject(value: Instance?): boolean
	return value ~= nil and (value:IsA("ImageLabel") or value:IsA("ImageButton"))
end

local function isCrewRewardData(rewardData): boolean
	if typeof(rewardData) ~= "table" then
		return false
	end

	if RandomCrewReward.IsRandomCrewRewardData(rewardData) then
		return true
	end

	if rewardData.CrewMember == true or rewardData.Crew == true then
		return true
	end

	local kind = tostring(rewardData.Kind or rewardData.Type or rewardData.RewardKind or "")
	return kind == "CrewMember" or kind == "Crew"
end

local function setPreviewPartDefaults(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function sanitizeCrewPreviewClone(previewModel: Instance)
	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			setPreviewPartDefaults(descendant)
		elseif descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("PointLight")
			or descendant:IsA("SpotLight")
			or descendant:IsA("SurfaceLight")
		then
			descendant.Enabled = false
		end
	end
end

local function findCrewPreviewModel(modelName)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local root = assets and assets:FindFirstChild(CREW_PREVIEW_ASSET_ROOT_NAME)
	local name = tostring(modelName or "")
	if not root or name == "" then
		return nil
	end

	local direct = root:FindFirstChild(name)
	if direct and direct:IsA("Model") then
		return direct
	end

	local descendant = root:FindFirstChild(name, true)
	if descendant and descendant:IsA("Model") then
		return descendant
	end

	return nil
end

local function cloneCrewPreviewModel(modelName)
	local template = findCrewPreviewModel(modelName)
	if not template then
		return nil
	end

	local ok, clone = pcall(function()
		return template:Clone()
	end)
	if not ok or typeof(clone) ~= "Instance" then
		return nil
	end

	sanitizeCrewPreviewClone(clone)
	return clone
end

local function getBoundingInfo(previewModel: Instance)
	if previewModel:IsA("BasePart") then
		return previewModel.CFrame, previewModel.Size
	end

	local ok, cf, size = pcall(function()
		return previewModel:GetBoundingBox()
	end)
	if ok then
		return cf, size
	end

	local part = previewModel:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.CFrame, part.Size
	end

	return CFrame.new(), Vector3.new(1, 1, 1)
end

local function makeInitials(value)
	local initials = {}
	for word in tostring(value or ""):gmatch("%S+") do
		initials[#initials + 1] = string.sub(word, 1, 1)
		if #initials >= 2 then
			break
		end
	end
	return string.upper(table.concat(initials))
end

local function showCrewRewardFallback(iconObj: Instance, displayName)
	local label = Instance.new("TextLabel")
	label.Name = CREW_REWARD_FALLBACK_NAME
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Size = UDim2.fromScale(1, 1)
	label.Text = makeInitials(displayName)
	label.TextColor3 = Color3.fromRGB(255, 245, 210)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.25
	label.ZIndex = math.max((iconObj :: GuiObject).ZIndex + 1, 6)
	label.Parent = iconObj
end

local function getPreviewContextValue(context, key)
	if typeof(context) ~= "table" then
		return nil
	end
	return context[key]
end

function CrewRewardPreview.Resolve(cfg, context)
	if typeof(cfg) ~= "table" or typeof(cfg.Rewards) ~= "table" then
		return nil
	end

	for rewardName, rewardData in pairs(cfg.Rewards) do
		if isCrewRewardData(rewardData) then
			if RandomCrewReward.IsRandomCrewRewardData(rewardData) then
				return RandomCrewReward.BuildPreviewInfo(
					getPreviewContextValue(context, "Player") or getPreviewContextValue(context, "UserId"),
					getPreviewContextValue(context, "RewardId"),
					getPreviewContextValue(context, "CycleStartPlayTime"),
					rewardData
				)
			end

			return CrewRewardResolver.Resolve(rewardName, rewardData)
		end
	end

	return nil
end

function CrewRewardPreview.ResolveDisplayName(rewardName, rewardData, context): string
	if not isCrewRewardData(rewardData) then
		return tostring(rewardName)
	end

	if RandomCrewReward.IsRandomCrewRewardData(rewardData) then
		local previewInfo = RandomCrewReward.BuildPreviewInfo(
			getPreviewContextValue(context, "Player") or getPreviewContextValue(context, "UserId"),
			getPreviewContextValue(context, "RewardId"),
			getPreviewContextValue(context, "CycleStartPlayTime"),
			rewardData
		)
		return tostring(previewInfo.DisplayName or rewardName)
	end

	local resolved = CrewRewardResolver.Resolve(rewardName, rewardData)
	return tostring(resolved.DisplayName or rewardName)
end

function CrewRewardPreview.Clear(iconObj: Instance)
	local viewport = iconObj:FindFirstChild(CREW_REWARD_VIEWPORT_NAME)
	if viewport then
		viewport:Destroy()
	end

	local fallback = iconObj:FindFirstChild(CREW_REWARD_FALLBACK_NAME)
	if fallback then
		fallback:Destroy()
	end
end

function CrewRewardPreview.Apply(iconObj: Instance, previewInfo): boolean
	if not isImageGuiObject(iconObj) or typeof(previewInfo) ~= "table" then
		return false
	end

	CrewRewardPreview.Clear(iconObj)

	local image = iconObj :: ImageLabel
	image.Image = ""
	image.ImageTransparency = 1

	local staticPreviewImage = CrewPreviewImages.Resolve(previewInfo)
	if staticPreviewImage ~= "" then
		image.BackgroundTransparency = 1
		image.Image = staticPreviewImage
		image.ImageTransparency = 0
		image.ScaleType = Enum.ScaleType.Crop
		return true
	end

	local previewModel = cloneCrewPreviewModel(previewInfo.ModelName)
	if not previewModel then
		showCrewRewardFallback(iconObj, previewInfo.DisplayName)
		return true
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = CREW_REWARD_VIEWPORT_NAME
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Position = UDim2.fromScale(0, 0)
	viewport.Ambient = Color3.fromRGB(206, 196, 186)
	viewport.LightColor = Color3.fromRGB(255, 252, 246)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.ZIndex = math.max(image.ZIndex + 1, 6)
	viewport.Parent = iconObj

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	previewModel.Parent = worldModel

	pcall(function()
		if previewModel:IsA("Model") or previewModel:IsA("WorldModel") then
			previewModel:PivotTo(CREW_PREVIEW_ROTATION)
		elseif previewModel:IsA("BasePart") then
			previewModel.CFrame = CREW_PREVIEW_ROTATION
		end
	end)

	local boxCF, boxSize = getBoundingInfo(previewModel)
	local maxSize = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)
	local camera = Instance.new("Camera")
	camera.Name = "CrewRewardPreviewCamera"
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(
		boxCF.Position + Vector3.new(maxSize * 0.92, maxSize * 0.38, maxSize * 1.7),
		boxCF.Position
	)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	return true
end

return CrewRewardPreview
