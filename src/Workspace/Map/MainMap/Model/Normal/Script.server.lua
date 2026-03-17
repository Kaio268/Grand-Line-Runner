local ac = script.Parent:FindFirstChild("AnimationController") or script.Parent:FindFirstChildWhichIsA("AnimationController", true)
if not ac then
	warn(("%s is missing an AnimationController under %s"):format(script:GetFullName(), script.Parent:GetFullName()))
	return
end

local animator = ac:FindFirstChild("Animator") or ac:FindFirstChildWhichIsA("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = ac
end

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://136874323814262"

local track = animator:LoadAnimation(anim)
track:Play()
