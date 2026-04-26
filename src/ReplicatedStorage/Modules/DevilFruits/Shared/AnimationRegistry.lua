local function toriAnimationPath(animationName)
	return {
		"Assets",
		"Animations",
		"Tori",
		animationName,
	}
end

local function toriAnimationFallbackPaths(animationName)
	return {
		{
			"Assets",
			"VFX",
			"Tori",
			"PhoenixMan",
			"AnimSaves",
			animationName,
		},
		{
			"Modules",
			"DevilFruits",
			"Tori",
			"Assets",
			"VFX",
			"PhoenixMan",
			"AnimSaves",
			animationName,
		},
	}
end

local function toriEmbeddedAnimation(animationName, length)
	return {
		KeyframeSequencePath = toriAnimationPath(animationName),
		FallbackKeyframeSequencePaths = toriAnimationFallbackPaths(animationName),
		Length = length,
	}
end

local Animations = {
	Movement = {
		R6Walk = "rbxassetid://87454242265342",
		R6GWalk = "rbxassetid://106182133664289",
		-- Registered for future glide/flight wiring; no live caller uses it yet.
		R6Glide = "rbxassetid://75741316803179",
	},

	EatFruit = {
		R6 = "rbxassetid://131816863052592",
		R6G = "rbxassetid://95090703686197",
	},

	Mera = {
		FlameDash = "rbxassetid://85227673442132",
		FlameBurstR6 = "rbxassetid://115575898741735",
	},

	Hie = {
		IceBlast = {
			R6 = "rbxassetid://124055413998569",
			-- R6G rigs are modified R15; use R6-authored fruit animations as a safe fallback.
			R6G = "rbxassetid://124055413998569",
			-- This project uses R6 and an R6G (modified R15) rig; treat Default like R6.
			Default = "rbxassetid://124055413998569",
		},
		IceBoost = {
			R6 = "rbxassetid://80476214763415",
			-- R6G rigs are modified R15; use R6-authored fruit animations as a safe fallback.
			R6G = "rbxassetid://80476214763415",
			-- This project uses R6 and an R6G (modified R15) rig; treat Default like R6.
			Default = "rbxassetid://80476214763415",
		},
	},

	Gomu = {
		Rocket = "rbxassetid://100281752037524",
	},

	Mogu = {
		Dive = "rbxassetid://140152497789637",
		Exit = "rbxassetid://103374605603335",
	},

	Tori = {
		PhoenixFlightStart = toriEmbeddedAnimation("Phoenix Flystart", 3.1666667),
		PhoenixFlightLoop = toriEmbeddedAnimation("Phoenix Flying", 5.2),
		PhoenixFlightIdle = toriEmbeddedAnimation("Phoenix Flyidle", 1),
		PhoenixFlightEnd = toriEmbeddedAnimation("Phoenix FlyEnd", 1.2),
		PhoenixFlameShield = toriEmbeddedAnimation("Phoenix Flame Shield", 1.6666667),
	},
}

return Animations
