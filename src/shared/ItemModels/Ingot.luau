--!strict
-- Shared upload-free ingot geometry, resting at Y = 0 with its length on X.
local Ingot = {}

function Ingot.create(key: string, displayName: string, color: Color3, topColor: Color3, stampColor: Color3, worn: boolean): Model
	local model = Instance.new("Model")
	model.Name = key
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", key)
	model:SetAttribute("DisplayName", displayName)
	model:SetAttribute("GallerySize", 3.3)
	model:SetAttribute("GalleryRotation", CFrame.Angles(0, math.rad(-25), 0))
	model:SetAttribute("DisplayRotation", CFrame.Angles(0, math.rad(-20), 0))
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(12), math.rad(20), math.rad(10)))

	local function part(name: string, size: Vector3, frame: CFrame, tint: Color3, wedge: boolean?): BasePart
		local p = if wedge then Instance.new("WedgePart") else Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = frame
		p.Color = tint
		p.Material = Enum.Material.Metal
		p.Reflectance = if worn then 0.03 else 0.12
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	part("CastBody", Vector3.new(3, 0.65, 1), CFrame.new(0, 0.325, 0), color)
	-- Wedges rise toward the centre, forming the long sloped casting faces.
	part("FrontSlope", Vector3.new(3, 0.65, 0.3), CFrame.new(0, 0.325, -0.65), color, true)
	part("BackSlope", Vector3.new(3, 0.65, 0.3), CFrame.new(0, 0.325, 0.65) * CFrame.Angles(0, math.pi, 0), color, true)
	part("PolishedTop", Vector3.new(2.94, 0.025, 0.96), CFrame.new(0, 0.65, 0), topColor)
	-- A geometric maker's stamp remains visible in 3D without a SurfaceGui.
	part("StampLeft", Vector3.new(0.035, 0.012, 0.55), CFrame.new(-0.5, 0.67, 0), stampColor)
	part("StampRight", Vector3.new(0.035, 0.012, 0.55), CFrame.new(0.5, 0.67, 0), stampColor)
	for _, side in { -1, 1 } do
		part("StampBorder" .. tostring(side), Vector3.new(1, 0.012, 0.035), CFrame.new(0, 0.67, side * 0.275), stampColor)
	end
	for index = 1, 3 do
		part("AssayMark" .. tostring(index), Vector3.new(0.13, 0.012, 0.24), CFrame.new((index - 2) * 0.23, 0.67, 0), stampColor)
	end
	if worn then
		for index = 1, 4 do
			part("CastingScratch" .. tostring(index), Vector3.new(0.22, 0.012, 0.025),
				CFrame.new(if index < 3 then -1.05 else 1.05, 0.67, (index % 2 - 0.5) * 0.5)
					* CFrame.Angles(0, math.rad(index * 17), 0), stampColor)
		end
	end
	return model
end

return Ingot
