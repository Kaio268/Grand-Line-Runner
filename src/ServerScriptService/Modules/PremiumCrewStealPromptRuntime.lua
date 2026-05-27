local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PremiumCrewStealConfig")
)
local ShipVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ShipVisuals"))
local PremiumCrewStealService = require(ServerScriptService.Modules:WaitForChild("PremiumCrewStealService"))

local PromptRuntime = {}

local ATTR = ShipVisuals.Attributes
local OWNER_USER_ID_ATTRIBUTE = ATTR.OwnerUserId or "OwnerUserId"
local HIDE_FROM_OWNER_ATTRIBUTE = ATTR.HideFromOwnerInteraction or Config.Attributes.HideFromOwnerInteraction
local INTERACTION_KIND_ATTRIBUTE = ATTR.InteractionKind or "ShipInteractionKind"
local INTERACTION_SLOT_ATTRIBUTE = ATTR.InteractionSlotKey or "ShipInteractionSlotKey"

local function setAttributeIfChanged(instance, attributeName, value)
	if instance and instance:GetAttribute(attributeName) ~= value then
		instance:SetAttribute(attributeName, value)
	end
end

local function getPrompt(handle)
	local existing = handle and handle:FindFirstChild(Config.Prompt.Name)
	if existing and not existing:IsA("ProximityPrompt") then
		existing:Destroy()
		existing = nil
	end
	if existing then
		return existing
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Config.Prompt.Name
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = tonumber(Config.Prompt.HoldDuration) or 0.45
	prompt.MaxActivationDistance = tonumber(Config.Prompt.MaxActivationDistance) or 12
	prompt.Parent = handle
	return prompt
end

local function getDisplayName(ctx, owner, crewMemberName)
	if crewMemberName == "" then
		return "Premium Steal"
	end
	if typeof(ctx.resolveStandStatusDisplayName) == "function" then
		return ctx.resolveStandStatusDisplayName(owner, crewMemberName)
	end
	return tostring(crewMemberName)
end

function PromptRuntime.UpdateStandPrompt(ctx, owner, activeShip, standModel, cache)
	if Config.Enabled ~= true then
		return
	end
	if typeof(owner) ~= "Instance" or not owner:IsA("Player") then
		return
	end
	if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
		return
	end

	cache = cache or (typeof(ctx.getSlotRuntime) == "function" and ctx.getSlotRuntime(owner, activeShip, standModel) or nil)
	if not cache then
		return
	end

	local handle = cache.Handle
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local shipSlotService = ctx.ShipSlotService
	if shipSlotService
		and (
			(typeof(shipSlotService.IsCaptainSlot) == "function" and shipSlotService.IsCaptainSlot(standModel))
			or (
				typeof(shipSlotService.IsCaptainSlotName) == "function"
				and shipSlotService.IsCaptainSlotName(standModel.Name)
			)
		)
	then
		local existingPrompt = handle:FindFirstChild(Config.Prompt.Name)
		if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
			existingPrompt.Enabled = false
		end
		return
	end

	local prompt = getPrompt(handle)
	cache.PremiumCrewStealPrompt = prompt

	local standName = tostring(standModel.Name or "")
	local crewMemberName = ""
	if typeof(ctx.getPlayerStandCrewMemberName) == "function" then
		crewMemberName = tostring(ctx.getPlayerStandCrewMemberName(owner, standName) or "")
	end

	prompt.ActionText = Config.Prompt.ActionText
	prompt.ObjectText = getDisplayName(ctx, owner, crewMemberName)
	prompt.Enabled = crewMemberName ~= ""

	setAttributeIfChanged(prompt, HIDE_FROM_OWNER_ATTRIBUTE, true)
	setAttributeIfChanged(prompt, OWNER_USER_ID_ATTRIBUTE, owner.UserId)
	setAttributeIfChanged(prompt, Config.Attributes.PromptKind, true)
	setAttributeIfChanged(prompt, INTERACTION_KIND_ATTRIBUTE, "PremiumCrewSteal")
	setAttributeIfChanged(prompt, INTERACTION_SLOT_ATTRIBUTE, standName)

	if cache.Connections.PremiumCrewStealPromptTriggered then
		return
	end

	cache.Connections.PremiumCrewStealPromptTriggered = prompt.Triggered:Connect(function(actor)
		PremiumCrewStealService.RequestPromptFromStand(actor, owner, activeShip, standModel)
	end)
end

return PromptRuntime
