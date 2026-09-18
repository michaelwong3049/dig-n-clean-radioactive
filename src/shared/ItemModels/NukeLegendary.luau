--!strict
-- Bold and toyetic: fire-engine red, chrome trim, a glowing seam, and cartoon stars.
local NukeBase = require(script.Parent.NukeBase)
local NukeLegendary = {}

function NukeLegendary.create(signature: NukeBase.SignatureFn?): Model
	return NukeBase.create({
		key = "NukeLegendary",
		displayName = "Nuke",
		bodyColor = Color3.fromHex("E63946"),
		noseColor = Color3.fromHex("B32734"),
		finColor = Color3.fromHex("FFD23F"),
		finCount = 4,
		stripeColor = Color3.fromHex("FFD23F"),
		chrome = true,
		glowColor = Color3.fromHex("FFD23F"),
		starColor = Color3.fromHex("FFD23F"),
		sizeScale = 1.65,
		gallerySize = 3.6,
		signature = signature,
	})
end

return NukeLegendary
