local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local GroupLikeLuffyNpcSetupService = {}

local NPC_REF_KEY = "GroupLikeLuffyNpc"
local PROMPT_NAME = "GroupLikeRewardPrompt"
local NPC_PROMPT_TAG = "NPCprompt"
local RESOLVE_TIMEOUT_SECONDS = 20
local RETRY_ATTEMPTS = 3
local RETRY_DELAY_SECONDS = 2

local started = false
local activeMapConnection

local function getPath(instance)
	return if instance then instance:GetFullName() else "<nil>"
end

local function logInfo(message, ...)
	print(string.format("[GroupLikeLuffyNpcSetupService] " .. message, ...))
end

local function logWarn(message, ...)
	warn(string.format("[GroupLikeLuffyNpcSetupService] " .. message, ...))
end

local function getPrimaryPromptPart(npc)
	if not npc or not npc:IsA("Model") then
		return nil, "missing_npc"
	end

	local humanoidRootPart = npc:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		if npc.PrimaryPart ~= humanoidRootPart then
			npc.PrimaryPart = humanoidRootPart
		end
		return humanoidRootPart, nil
	end

	if npc.PrimaryPart and npc.PrimaryPart:IsA("BasePart") then
		return npc.PrimaryPart, "missing_humanoid_root_part"
	end

	local fallbackPart = npc:FindFirstChildWhichIsA("BasePart", true)
	if fallbackPart then
		npc.PrimaryPart = fallbackPart
		return fallbackPart, "missing_humanoid_root_part"
	end

	return nil, "missing_base_part"
end

local function getGuiTemplate(refs)
	local candidates = {
		refs and refs.AFKRayleighNpc,
		refs and refs.SellNpc,
	}

	for _, npc in ipairs(candidates) do
		local part = getPrimaryPromptPart(npc)
		local gui = part and part:FindFirstChild("gui")
		if gui and gui:IsA("BillboardGui") then
			return gui
		end
	end

	return nil
end

local function configureOverheadText(gui)
	if not gui then
		return
	end

	gui.Name = "gui"
	gui.Enabled = true

	local nameLabel = gui:FindFirstChild("name", true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = "Luffy"
	end

	local dialogLabel = gui:FindFirstChild("dialog", true)
	if dialogLabel and dialogLabel:IsA("TextLabel") then
		dialogLabel.Text = ""
	end
end

local function addStroke(label)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = label
	end
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(0, 0, 0)
end

local function createFallbackOverheadGui(parentPart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "gui"
	gui.AlwaysOnTop = true
	gui.Enabled = true
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	gui.Size = UDim2.fromOffset(240, 92)
	gui.StudsOffset = Vector3.new(0, 5.5, 0)
	gui.Parent = parentPart

	local dialogLabel = Instance.new("TextLabel")
	dialogLabel.Name = "dialog"
	dialogLabel.BackgroundTransparency = 1
	dialogLabel.Position = UDim2.fromScale(0, 0)
	dialogLabel.Size = UDim2.fromScale(1, 0.55)
	dialogLabel.Font = Enum.Font.GothamMedium
	dialogLabel.Text = ""
	dialogLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	dialogLabel.TextScaled = true
	dialogLabel.TextWrapped = true
	dialogLabel.Parent = gui
	addStroke(dialogLabel)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromScale(0, 0.55)
	nameLabel.Size = UDim2.fromScale(1, 0.45)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = "Luffy"
	nameLabel.TextColor3 = Color3.fromRGB(255, 232, 92)
	nameLabel.TextScaled = true
	nameLabel.TextWrapped = true
	nameLabel.Parent = gui
	addStroke(nameLabel)

	return gui
end

local function ensureOverheadGui(npc, parentPart, refs)
	local gui = parentPart:FindFirstChild("gui")
	if gui and gui:IsA("BillboardGui") then
		configureOverheadText(gui)
		return gui, "existing"
	end

	local template = getGuiTemplate(refs)
	if template then
		gui = template:Clone()
		gui.Parent = parentPart
		configureOverheadText(gui)
		return gui, "cloned"
	end

	logWarn("missing_gui_template; creating fallback overhead gui for %s", getPath(npc))
	gui = createFallbackOverheadGui(parentPart)
	configureOverheadText(gui)
	return gui, "fallback"
end

local function findPrompt(npc)
	local prompt = npc:FindFirstChild(PROMPT_NAME, true)
	if prompt and prompt:IsA("ProximityPrompt") then
		return prompt
	end

	return npc:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function ensurePrompt(npc, parentPart)
	local prompt = findPrompt(npc)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
	end

	prompt.Name = PROMPT_NAME
	prompt.Parent = parentPart
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Talk to Luffy"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Enabled = true

	if not CollectionService:HasTag(prompt, NPC_PROMPT_TAG) then
		CollectionService:AddTag(prompt, NPC_PROMPT_TAG)
	end

	return prompt
end

function GroupLikeLuffyNpcSetupService.Ensure(options)
	options = if typeof(options) == "table" then options else {}
	local timeoutSeconds = tonumber(options.TimeoutSeconds) or RESOLVE_TIMEOUT_SECONDS
	local refs = MapResolver.WaitForRefs({ NPC_REF_KEY }, timeoutSeconds, {
		warn = true,
		context = "GroupLikeLuffyNpcSetupService",
	})
	local npc = refs[NPC_REF_KEY]
	if not npc or not npc:IsA("Model") then
		logWarn("setup_failed missing_luffy resolved=%s", getPath(npc))
		return false, "missing_luffy"
	end

	local parentPart, partReason = getPrimaryPromptPart(npc)
	if not parentPart then
		logWarn("setup_failed luffy=%s reason=%s", getPath(npc), tostring(partReason or "missing_prompt_part"))
		return false, partReason or "missing_prompt_part"
	elseif partReason then
		logWarn("using_fallback_part luffy=%s part=%s reason=%s", getPath(npc), getPath(parentPart), tostring(partReason))
	end

	local gui, guiSource = ensureOverheadGui(npc, parentPart, refs)
	local prompt = ensurePrompt(npc, parentPart)
	logInfo(
		"setup_success luffy=%s promptParent=%s promptEnabled=%s gui=%s guiSource=%s",
		getPath(npc),
		getPath(prompt.Parent),
		tostring(prompt.Enabled),
		getPath(gui),
		tostring(guiSource)
	)

	return true, nil
end

local function runStartupRetries()
	for attempt = 1, RETRY_ATTEMPTS do
		local ok, reason = GroupLikeLuffyNpcSetupService.Ensure({
			TimeoutSeconds = RESOLVE_TIMEOUT_SECONDS,
		})
		if ok then
			return
		end

		logWarn("retry_pending attempt=%d/%d reason=%s", attempt, RETRY_ATTEMPTS, tostring(reason))
		if attempt < RETRY_ATTEMPTS then
			task.wait(RETRY_DELAY_SECONDS)
		end
	end
end

function GroupLikeLuffyNpcSetupService.Start()
	if started then
		return
	end
	started = true

	activeMapConnection = Workspace:GetAttributeChangedSignal("ActiveMapName"):Connect(function()
		task.spawn(runStartupRetries)
	end)

	task.spawn(runStartupRetries)
end

function GroupLikeLuffyNpcSetupService.Stop()
	if activeMapConnection then
		activeMapConnection:Disconnect()
		activeMapConnection = nil
	end
	started = false
end

return GroupLikeLuffyNpcSetupService
