--!strict
--[[
	ToolModels — gear-tier models that live in git instead of in the place file.

	THE PROBLEM THIS IS THE START OF A WAY OUT OF. Every gear track's tier models are
	supposed to come from `Assets/Tools/<Track>/T<n>`, built by a generator that ran
	from the command bar once and was then lost (Config/ToolTiers' header, and
	build/BaseCamp's). What that leaves behind: ToolTiers is a recipe with no cook,
	nothing at runtime reads a column of it, the shop rack silently degrades to painted
	fallback blocks for any track whose folder is missing, and no one can regenerate
	the art. Geometry that was born from code should stay as code — the same argument
	build/BaseCamp makes about the camp, and Shared/ItemModels about the catalogue.

	The Cleaner track is the first one moved across, because it had the strongest case:
	its models were the least seen in the game (ToolService pulls the cleaner OUT of
	your hand at the wash bay, which is the only place you would use one) and the wash
	bay already built a real hose from primitives, so the geometry was half here.

	Detector and Magnet still come out of the place. `has()` is the honest answer to
	"can this track be built from code yet", and every caller is expected to fall back
	to the place-file lookup rather than assume either way.
]]

local Hose = require(script.Hose)

local ToolModels = {}

--- Track name (as used in Gear.TRACKS, ToolTiers and the world's SellsTrack
--- attribute) to its factory. A track absent here is a track whose art is still in
--- the place file.
local factories: { [string]: (tier: number) -> Model } = {
	Cleaner = Hose.create,
}

ToolModels.Hose = Hose

function ToolModels.has(track: string): boolean
	return factories[track] ~= nil
end

--- One tier's model for `track`, or nil if this track has no code-authored art.
--- Callers that get nil must fall back to `Assets/Tools/<Track>/T<n>` (ToolService,
--- build/Shops) rather than treating it as an error.
function ToolModels.create(track: string, tier: number): Model?
	local factory = factories[track]
	if factory == nil then
		return nil
	end
	return factory(tier)
end

return ToolModels
