--!strict
-- A small, dead nuke. Dull and dented -- no fins, no shine, nothing lit.
local NukeBase = require(script.Parent.NukeBase)
local NukeCommon = {}

function NukeCommon.create(signature: NukeBase.SignatureFn?): Model
	return NukeBase.create({
		key = "NukeCommon",
		displayName = "Nuke",
		bodyColor = Color3.fromHex("8A8D90"),
		noseColor = Color3.fromHex("6B6E71"),
		finColor = Color3.fromHex("6B6E71"),
		finCount = 0,
		sizeScale = 0.85,
		gallerySize = 2.6,
		signature = signature,
	})
end

return NukeCommon
