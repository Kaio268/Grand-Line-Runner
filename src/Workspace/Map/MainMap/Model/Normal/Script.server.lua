local ac = script.Parent:WaitForChild("AnimationController")
local animator = ac:WaitForChild("Animator")

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://136874323814262"

local track = animator:LoadAnimation(anim)
track:Play()