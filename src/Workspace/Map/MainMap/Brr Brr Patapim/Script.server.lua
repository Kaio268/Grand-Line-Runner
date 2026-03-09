local ac = script.Parent:WaitForChild("AnimationController")
local animator = ac:WaitForChild("Animator")

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://108530253041260"

local track = animator:LoadAnimation(anim)
track:Play()