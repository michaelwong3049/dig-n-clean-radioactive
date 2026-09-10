--!strict
-- A polished sea-glass pebble with colored ribbons suspended inside its shell.
-- Built from ordinary parts so the model needs no uploaded assets.
local GlassPebble = {}

local PALETTE = {
	Color3.fromHex("26DAD1"),
	Color3.fromHex("488EFF"),
	Color3.fromHex("A767EE"),
	Color3.fromHex("F46CB3"),
	Color3.fromHex("FFC65C"),
}

local function ellipsoid(model: Model, name: string, size: Vector3, frame: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	-- A sphere mesh preserves all three dimensions; Ball parts force equal axes.
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Size = size
	part.CFrame = frame
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

function GlassPebble.create(): Model
	local model = Instance.new("Model")
	model.Name = "GlassPebble"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "GlassPebble")
	model:SetAttribute("DisplayName", "Glass Pebble")
	model:SetAttribute("GallerySize", 3.2)
	model:SetAttribute("GalleryRotation", CFrame.Angles(0, math.rad(-20), 0))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(18), 0, math.rad(-10)))
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(15), 0, math.rad(-12)))

	local shell = ellipsoid(model, "GlassShell", Vector3.new(2.8, 1.65, 2.25), CFrame.new(0, 0.825, 0), Color3.fromHex("BCF7F1"))
	shell.Material = Enum.Material.Glass
	shell.Transparency = 0.48
	shell.Reflectance = 0.12

	-- Opaque colored inclusions remain visible through Roblox's glass rendering.
	-- Each continuous ribbon curls around the interior of the flattened pebble.
	for ribbon, color in PALETTE do
		for segment = 0, 15 do
			local t = segment / 15
			local angle = t * math.pi * 1.55 + (ribbon - 1) * math.pi * 2 / #PALETTE
			local radius = 0.58 * math.sin(math.pi * (0.12 + t * 0.76))
			local position = Vector3.new(math.cos(angle) * radius * 1.5, 0.38 + t * 0.88, math.sin(angle) * radius)
			local tangent = Vector3.new(-math.sin(angle) * 1.5, 0.32, math.cos(angle)).Unit
			local frame = CFrame.lookAt(position, position + tangent)
			local bead = ellipsoid(model, `Ribbon{ribbon}_{segment}`, Vector3.new(0.19, 0.12, 0.3), frame, color)
			bead.Reflectance = 0.08
		end
	end

	return model
end

return GlassPebble
