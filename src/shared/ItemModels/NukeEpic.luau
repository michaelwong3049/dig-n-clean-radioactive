--!strict
-- Active-looking: teal plastic shell, a chrome collar, and a glowing purple seam.
local NukeBase = require(script.Parent.NukeBase)
local NukeEpic = {}

function NukeEpic.create(signature: NukeBase.SignatureFn?): Model
	return NukeBase.create({
		key = "NukeEpic",
		displayName = "Nuke",
		bodyColor = Color3.fromHex("2FB8A6"),
		noseColor = Color3.fromHex("21867A"),
		finColor = Color3.fromHex("9B5DE5"),
		finCount = 4,
		stripeColor = Color3.fromHex("9B5DE5"),
		chrome = true,
		glowColor = Color3.fromHex("9B5DE5"),
		sizeScale = 1.35,
		gallerySize = 3.2,
		signature = signature,
	})
end

return NukeEpic
