local SpeedUpgradeTutorialBridge = {}

local refs = {}

function SpeedUpgradeTutorialBridge.SetRefs(nextRefs)
	refs = nextRefs or {}
end

function SpeedUpgradeTutorialBridge.ClearRefs()
	refs = {}
end

function SpeedUpgradeTutorialBridge.GetRefs()
	return refs.buyButton, refs.closeButton, refs.root
end

function SpeedUpgradeTutorialBridge.WaitForRefs(timeoutSeconds)
	local deadline = os.clock() + math.max(0, tonumber(timeoutSeconds) or 0)
	repeat
		local buyButton, closeButton, root = SpeedUpgradeTutorialBridge.GetRefs()
		if buyButton and closeButton and root then
			return buyButton, closeButton, root
		end
		task.wait(0.05)
	until os.clock() >= deadline

	return SpeedUpgradeTutorialBridge.GetRefs()
end

return SpeedUpgradeTutorialBridge
