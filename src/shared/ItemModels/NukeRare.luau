--!strict
-- Half-armed: bright warning-yellow paint and a hazard stripe around the middle.
local NukeBase = require(script.Parent.NukeBase)
local NukeRare = {}

function NukeRare.create(signature: NukeBase.SignatureFn?): Model
	return NukeBase.create({
		key = "NukeRare",
		displayName = "Nuke",
		bodyColor = Color3.fromHex("E8A33D"),
		noseColor = Color3.fromHex("D6432B"),
		finColor = Color3.fromHex("D6432B"),
		finCount = 3,
		stripeColor = Color3.fromHex("2B2B2B"),
		sizeScale = 1.15,
		gallerySize = 3.0,
		signature = signature,
	})
end

return NukeRare
