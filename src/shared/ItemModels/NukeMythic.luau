--!strict
-- Vivid and glowing: a dark chrome body wrapped in a full rainbow of neon bands.
local NukeBase = require(script.Parent.NukeBase)
local NukeMythic = {}

function NukeMythic.create(): Model
	return NukeBase.create({
		key = "NukeMythic",
		displayName = "Nuke",
		bodyColor = Color3.fromHex("2B2B33"),
		noseColor = Color3.fromHex("1C1C21"),
		finColor = Color3.fromHex("EF4444"),
		finCount = 4,
		chrome = true,
		sparkleColor = Color3.fromHex("FFFFFF"),
		bandColors = {
			Color3.fromHex("EF4444"),
			Color3.fromHex("F59E0B"),
			Color3.fromHex("EAB308"),
			Color3.fromHex("22C55E"),
			Color3.fromHex("3B82F6"),
			Color3.fromHex("A855F7"),
		},
		sizeScale = 2.00,
		gallerySize = 3.8,
	})
end

return NukeMythic
