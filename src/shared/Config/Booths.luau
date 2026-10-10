--!strict
--[[
	Booths.luau — what each gear booth sells, by its station id.

	A shop booth's stand carries StationKind = "shop" and StationId = the track it was
	built for ("Detector", "Magnet", "Aura", "Cleaner"), in Base Camp's plaza and at every
	site camp. THOSE IDS NEVER CHANGE, so a place saved before this file existed still
	works the moment the code lands; only what a booth SELLS is decided here.

	2026-10-09, on request ("the detector shop booth now turns into gear, and the magnet
	shop booth is upgrades"):
	  * the Detector booth is the GEAR booth: detectors AND magnets, one tab each;
	  * the Magnet booth is the UPGRADES booth: walk speed (Config/WalkSpeed), no gear.
]]

local Booths = {}

export type Booth = {
	-- What the booth's sign and panel call it.
	label: string,
	-- The gear tracks it sells, in tab order. Empty for the Upgrades booth.
	tracks: { string },
	-- Sells walk speed (client/SpeedPanel) instead of gear.
	speed: boolean?,
	-- The shop panel's title, when it is not the track's own name.
	title: string?,
}

Booths.BY_ID = {
	Detector = { label = "Gear", tracks = { "Detector", "Magnet" }, title = "Gear" },
	Magnet = { label = "Upgrades", tracks = {}, speed = true },
	Aura = { label = "Aura Shop", tracks = { "Aura" } },
	-- No booth any more: the Hoses pad beside every base's tub (build/Plots ensureHosePad,
	-- 2026-10-09). Every hose, no camp lock (Gear.CAMP_FREE).
	Cleaner = { label = "Hoses", tracks = { "Cleaner" }, title = "Hoses" },
} :: { [string]: Booth }

--- The booth a shop StationId names, or nil.
function Booths.get(stationId: any): Booth?
	return if type(stationId) == "string" then Booths.BY_ID[stationId] else nil
end

--- Whether the booth with `stationId` sells gear track `track`. A station id with no
--- entry here sells only its own track, as every booth did before this file.
function Booths.sells(stationId: any, track: any): boolean
	if type(track) ~= "string" then
		return false
	end
	local booth = Booths.get(stationId)
	if booth == nil then
		return stationId == track
	end
	return table.find(booth.tracks, track) ~= nil
end

--- The tracks the booth with `stationId` sells, in tab order.
function Booths.tracks(stationId: any): { string }
	local booth = Booths.get(stationId)
	if booth then
		return booth.tracks
	end
	return if type(stationId) == "string" then { stationId } else {}
end

--- Whether the booth with `stationId` is an Upgrades (walk speed) booth.
function Booths.sellsSpeed(stationId: any): boolean
	local booth = Booths.get(stationId)
	return booth ~= nil and booth.speed == true
end

--- The shop panel's title for this station: "Gear", "Hoses", or nil for the track name.
function Booths.title(stationId: any): string?
	local booth = Booths.get(stationId)
	return if booth then booth.title else nil
end

--- What the booth's sign says: "Gear", "Upgrades", "Aura Shop".
function Booths.label(stationId: any, fallback: string): string
	local booth = Booths.get(stationId)
	return if booth then booth.label else fallback
end

return Booths
