--!strict
--[[
	ShopFx.luau — the label the plaza stalls' theme props carry so a client can move
	them.

	    tagged by build/ShopThemes, read by ShopFxController

	WHY THE SERVER ONLY TAGS. The same reasoning as Shared/ItemFx: motion written on
	the server would replicate every part write of every frame to every player, and
	could not be culled by each player's own distance. A tag plus one attribute costs
	nothing and survives a save, so a stall built in Studio carries it into the
	published place.

	THREE KINDS, one per prop that moves:

	  * SPIN — a model turned about its pivot's own up axis (the Detector's radar head).
	    The pivot is the top of the mast.
	  * SWAY — a model swung like a pendulum about its pivot (the Magnet's crane load).
	    The pivot is where the cable meets the jib.
	  * DRIP — a part that water drips from (the Hose Shop's shower heads). The part
	    carries DRIP_FALL: how far a drop falls from its underside to the stall floor.

	ATOMIC STREAMING. The place runs StreamingEnabled. A half-streamed radar head would
	spin whichever of its parts had arrived, so a tagged model arrives whole or not at
	all.
]]

local CollectionService = game:GetService("CollectionService")

local ShopFx = {}

ShopFx.TAG = "ShopFx"
ShopFx.ATTRIBUTE = "ShopFx"
ShopFx.DRIP_FALL = "DripFall"

ShopFx.SPIN = "spin"
ShopFx.SWAY = "sway"
ShopFx.DRIP = "drip"

--- Label a theme prop for the client. `instance` is a Model for SPIN/SWAY (its
--- WorldPivot is the joint it turns about) or a BasePart for DRIP.
function ShopFx.tag(instance: Instance, kind: string)
	instance:SetAttribute(ShopFx.ATTRIBUTE, kind)
	if instance:IsA("Model") then
		instance.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	CollectionService:AddTag(instance, ShopFx.TAG)
end

return ShopFx
