local SocialGroups = {
	ChefsStudiosGroupId = 730746687,
}

SocialGroups.GroupRewardGroupId = SocialGroups.ChefsStudiosGroupId
SocialGroups.ChatTagGroupId = SocialGroups.ChefsStudiosGroupId
SocialGroups.GroupLikeRewardGroupId = SocialGroups.ChefsStudiosGroupId

SocialGroups.GroupLikeReward = {
	GroupId = SocialGroups.GroupLikeRewardGroupId,
	RewardTier = "Gold",
	RewardAmount = 100,
	Source = "GroupLikeLuffy",
}

return SocialGroups
