--!strict
local Ingot = require(script.Parent.Ingot)
local GoldBar = {}

function GoldBar.create(): Model
	return Ingot.create("GoldBar", "Gold Bar", Color3.fromHex("DCA52E"),
		Color3.fromHex("F4CC62"), Color3.fromHex("91601D"), false)
end

return GoldBar
