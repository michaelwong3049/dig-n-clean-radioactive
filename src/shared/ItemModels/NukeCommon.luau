--!strict
-- A small, dead nuke. Dull and dented -- no fins, no shine, nothing lit.
local NukeBase = require(script.Parent.NukeBase)
local NukeCommon = {}

function NukeCommon.create(): Model
	return NukeBase.create({
		key = "NukeCommon",
		displayName = "Nuke",
		bodyColor = Color3.fromHex("8A8D90"),
		noseColor = Color3.fromHex("6B6E71"),
		finColor = Color3.fromHex("6B6E71"),
		finCount = 0,
		gallerySize = 2.6,
	})
end

return NukeCommon
