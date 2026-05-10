local Placement = {}

function Placement.AnchorModel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function Placement.EnsurePrimaryPart(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local pp = model:FindFirstChildWhichIsA("BasePart", true)
	if pp then
		pcall(function()
			model.PrimaryPart = pp
		end)
	end
	return model.PrimaryPart or pp
end

function Placement.AlignModelOnPartUpright(model, spawnPart, localXZ, yaw)
	local boxCF, boxSize = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(boxCF)

	local lv = spawnPart.CFrame.LookVector
	local dir = Vector3.new(lv.X, 0, lv.Z)
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end

	local flatCF = CFrame.lookAt(spawnPart.Position, spawnPart.Position + dir, Vector3.yAxis)
	local right = flatCF.RightVector
	local look = flatCF.LookVector
	local up = Vector3.yAxis

	local surface = spawnPart.Position + up * (spawnPart.Size.Y / 2) + right * localXZ.X + look * localXZ.Y
	local rotOnly = (flatCF - flatCF.Position) * CFrame.Angles(0, yaw, 0)
	local desiredBoxCF = CFrame.new(surface + up * (boxSize.Y / 2)) * rotOnly
	local pivotTarget = desiredBoxCF * offset:Inverse()
	model:PivotTo(pivotTarget)
end

return Placement
