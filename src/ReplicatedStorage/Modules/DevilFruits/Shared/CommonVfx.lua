local CommonVfx = {}

function CommonVfx.FormatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

function CommonVfx.GetPlanarDirection(vector, fallbackDirection)
	local source = typeof(vector) == "Vector3" and vector or fallbackDirection
	if typeof(source) ~= "Vector3" then
		source = Vector3.new(0, 0, -1)
	end

	local planar = Vector3.new(source.X, 0, source.Z)
	if planar.Magnitude <= 0.01 then
		planar = Vector3.new(0, 0, -1)
	end

	return planar.Unit
end

function CommonVfx.BuildPathLabel(rootSegments, ...)
	local segments = { "ReplicatedStorage" }
	for _, segment in ipairs(rootSegments or {}) do
		segments[#segments + 1] = tostring(segment)
	end
	for _, segment in ipairs({ ... }) do
		if typeof(segment) == "string" and segment ~= "" then
			segments[#segments + 1] = segment
		end
	end

	return table.concat(segments, "/")
end

return CommonVfx
