local ac = script.Parent:WaitForChild("AnimationController")
local animator = ac:WaitForChild("Animator")

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://94395632772482"

local track = animator:LoadAnimation(anim)
track:Play()