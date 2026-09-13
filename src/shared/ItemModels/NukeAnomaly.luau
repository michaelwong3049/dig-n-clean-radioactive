--!strict
-- The coolest one: solid gold, a white glow, sparkle studs, and a spiked crown tip.
local NukeBase = require(script.Parent.NukeBase)
local NukeAnomaly = {}

function NukeAnomaly.create(): Model
	return NukeBase.create({
		key = "NukeAnomaly",
		displayName = "Nuke",
		bodyColor = Color3.fromHex("FFD700"),
		noseColor = Color3.fromHex("FFF3B0"),
		finColor = Color3.fromHex("FFD700"),
		finCount = 4,
		chrome = true,
		glowColor = Color3.fromHex("FFFFFF"),
		sparkleColor = Color3.fromHex("FFFFFF"),
		crownColor = Color3.fromHex("FFFFFF"),
		gallerySize = 4.2,
	})
end

return NukeAnomaly
