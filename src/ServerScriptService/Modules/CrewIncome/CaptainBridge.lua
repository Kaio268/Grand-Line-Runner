local Module = {}

function Module.Install(ctx)
	local CaptainSlotRuntime = ctx.CaptainSlotRuntime

	CaptainSlotRuntime.Configure({
		BuildIncomeToastDisplayPayload = ctx.buildIncomeToastDisplayPayload,
		ClearCrewRecordCache = ctx.clearCrewRecordCache,
		ClearVisual = ctx.clearStandVisual,
		EquipCrewMemberToolByInstanceId = ctx.equipCrewMemberToolByInstanceId,
		FireMoneyCollected = ctx.fireMoneyCollected,
		GetBaseIncome = ctx.getBaseIncome,
		GetBeliBoostMultiplier = ctx.getBeliBoostMultiplier,
		GetCrewMemberLevel = ctx.getCrewMemberLevel,
		GetEquippedCrewMemberToolInfo = ctx.getEquippedCrewMemberToolInfo,
		GetTitleBeliMultiplier = ctx.getTitleBeliMultiplier,
		LogCrewSwitchFailure = ctx.logCrewSwitchFailure,
		RefreshNormalIncomeDisplays = ctx.refreshPlayerIncomeDisplays,
		ResolveDisplayName = ctx.resolveStandStatusDisplayName,
		SpawnCrewMember = ctx.spawnStandCrewMember,
		SyncPlacedOverheadMetadata = ctx.syncPlacedOverheadMetadata,
		UpdateCaptainLevelUpUI = ctx.updateCaptainLevelUpUI,
	})
end

return Module
