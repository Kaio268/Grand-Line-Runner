local Module = {}

function Module.Install(ctx)
	local CaptainSlotRuntime = ctx.CaptainSlotRuntime

	CaptainSlotRuntime.Configure({
		BuildIncomeToastDisplayPayload = ctx.buildIncomeToastDisplayPayload,
		CanEquipCrewMember = function(player, crewMemberId)
			return ctx.CrewQuickSlotService.CanEquipCrewMember(player, crewMemberId)
		end,
		ClearCrewRecordCache = ctx.clearCrewRecordCache,
		ClearVisual = ctx.clearStandVisual,
		EquipCrewMemberToolByInstanceId = ctx.equipCrewMemberToolByInstanceId,
		FindAvailableTutorialPlacementReward = ctx.findAvailableTutorialPlacementReward,
		FireMoneyCollected = ctx.fireMoneyCollected,
		GetBaseIncome = ctx.getBaseIncome,
		GetBeliBoostMultiplier = ctx.getBeliBoostMultiplier,
		GetCrewMemberLevel = ctx.getCrewMemberLevel,
		GetEquippedCrewMemberToolInfo = ctx.getEquippedCrewMemberToolInfo,
		GetInventoryQuantity = ctx.getInventoryQuantity,
		LogCrewSwitchFailure = ctx.logCrewSwitchFailure,
		PromptUnlockForCrewMember = function(player, crewMemberId)
			ctx.CrewQuickSlotService.PromptUnlockForCrewMember(player, crewMemberId)
		end,
		RefreshNormalIncomeDisplays = ctx.refreshPlayerIncomeDisplays,
		ResolveDisplayName = ctx.resolveStandStatusDisplayName,
		SpawnCrewMember = ctx.spawnStandCrewMember,
		SyncPlacedOverheadMetadata = ctx.syncPlacedOverheadMetadata,
		UpdateCaptainLevelUpUI = ctx.updateCaptainLevelUpUI,
	})
end

return Module