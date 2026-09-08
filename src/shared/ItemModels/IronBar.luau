--!strict
local Ingot = require(script.Parent.Ingot)
local IronBar = {}

function IronBar.create(): Model
	return Ingot.create("IronBar", "Iron Bar", Color3.fromHex("59636B"),
		Color3.fromHex("89949C"), Color3.fromHex("343D43"), true)
end

return IronBar
