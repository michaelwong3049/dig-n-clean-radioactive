--!strict
-- Still dead, but assembled -- olive drab paint and a first set of tail fins.
local NukeBase = require(script.Parent.NukeBase)
local NukeUncommon = {}

function NukeUncommon.create(signature: NukeBase.SignatureFn?): Model
	return NukeBase.create({
		key = "NukeUncommon",
		displayName = "Nuke",
		bodyColor = Color3.fromHex("5C6B3F"),
		noseColor = Color3.fromHex("48542F"),
		finColor = Color3.fromHex("3F4A2B"),
		finCount = 3,
		sizeScale = 1.00,
		gallerySize = 2.8,
		signature = signature,
	})
end

return NukeUncommon
