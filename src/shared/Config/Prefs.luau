--!strict
--[[
	Prefs.luau — the Settings panel's player preferences: what each one is called, the
	values it may take, and its default. ONE table so the server's validation
	(Services/PrefsService), the profile's defaults (DataService `prefs`) and the
	client's readers (client/Prefs.luau) can never disagree.

	ALL CLIENT-SIDE IN EFFECT. Nothing here changes what the server decides — damage,
	drops, prices. Every pref only changes what THIS player sees or hears, so the server
	only stores and echoes them; it never reads one for gameplay.

	TWO SHAPES:
	  choice  one of `options` (strings), e.g. graphics "low" | "med" | "high".
	  flag    a boolean.
	  volume  a number 0..1, snapped to VOLUME_STEP so a slider cannot spam saves of
	          0.73125 then 0.7315.

	Base colour, HIDE MY AURA, SOUND EFFECTS (the mute) and the walk cap predate this and
	keep their own remotes; they are not prefs.
]]

local Prefs = {}

export type Kind = "choice" | "flag" | "volume"

export type Def = {
	kind: Kind,
	default: any,
	options: { string }?,
}

Prefs.VOLUME_STEP = 0.05

Prefs.DEFS = {
	-- NEW PLAYERS START ON THE LIGHT SETTINGS: graphics "low", radFx "reduced"
	-- and reduceFlashing on. Profiles snapshot these defaults, so a change here
	-- reaches new saves only; existing players keep what they chose.

	-- GRAPHICS. "high" is the game as built. "med" pulls nuke detail in closer and
	-- halves the lights; "low" also stops ambient machine/magnet motion and draws only
	-- your own aura (client ItemFxController, StationMotionController,
	-- ToolMotionController, AuraController).
	graphics = { kind = "choice", default = "low", options = { "low", "med", "high" } },

	-- SCREEN SHAKE. Off = no blast shake or FOV kick (DetonationController) and no
	-- radiation camera wobble (HudController).
	shake = { kind = "flag", default = true },

	-- RADIATION SCREEN EFFECTS (client RadFx). "reduced" softens every layer and drops
	-- the snow, scanlines, dust and blur. No "off" on purpose: the over-tier keyhole is
	-- the soft gate that warns you are too deep, so reduced still narrows the view.
	radFx = { kind = "choice", default = "reduced", options = { "full", "reduced" } },

	-- REDUCE FLASHING. Full-screen flashes (blast, wash reveal, crate, flask, death)
	-- are skipped or dimmed and the Anomaly colour cycle slows right down.
	reduceFlashing = { kind = "flag", default = true },

	-- VOLUME. Master scales everything; the rest are client/Sfx.luau's groups. The
	-- Geiger clicks have their own because they are the one sound people want quieter.
	volMaster = { kind = "volume", default = 1 },
	volSfx = { kind = "volume", default = 1 },
	volUi = { kind = "volume", default = 1 },
	volGeiger = { kind = "volume", default = 1 },
	-- The background playlist (MusicController). ON at 50% by default: MusicController's
	-- track volume is set so 50% is the intended quiet bed. Key history: `volMusic` (old
	-- saves held 1) → `musicVol` (opt-in, default 0) → `musicLevel`. Each rename is
	-- because profiles snapshot Prefs.defaults(), so a changed default never reaches
	-- existing saves; the stale keys are ignored.
	musicLevel = { kind = "volume", default = 0.5 },

	-- RARE DROP ANNOUNCEMENTS (client RareDropController). "mine" keeps only the line
	-- when YOU claim one. The drop's glow in the field is untouched either way.
	rareDrops = { kind = "choice", default = "all", options = { "all", "mine", "off" } },

	-- CONFIRM RARE NUKE DROPS. The "are you sure?" before a Rare+ nuke is bombed
	-- (client InventoryController); its "Don't show again" box turns this off.
	confirmDrop = { kind = "flag", default = true },

	-- FAST MODE (client FastModeController). On = the nukes standing on OTHER players'
	-- bases are hidden from you, along with their effects: far less to draw on a busy
	-- server. Your own base is untouched.
	fastMode = { kind = "flag", default = false },

	-- SHOW AURAS (client AuraController). Off = no aura is drawn, yours or anyone's, so
	-- none of their rings, trails and sparkles move or cost a frame. On by default.
	auras = { kind = "flag", default = true },
} :: { [string]: Def }

--- A fresh table of every default, for the profile template and a client that has not
--- heard from the server yet.
function Prefs.defaults(): { [string]: any }
	local out = {}
	for key, def in Prefs.DEFS do
		out[key] = def.default
	end
	return out
end

--- `value` made legal for `key`, or nil if it cannot be (unknown key, wrong type, an
--- option that does not exist). Volumes are clamped and snapped rather than refused.
function Prefs.sanitize(key: any, value: any): any
	if type(key) ~= "string" then
		return nil
	end
	local def = Prefs.DEFS[key]
	if def == nil then
		return nil
	end
	if def.kind == "flag" then
		return if type(value) == "boolean" then value else nil
	elseif def.kind == "volume" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		local step = Prefs.VOLUME_STEP
		return math.clamp(math.round(value / step) * step, 0, 1)
	else
		if type(value) ~= "string" then
			return nil
		end
		for _, option in def.options :: { string } do
			if option == value then
				return value
			end
		end
		return nil
	end
end

return Prefs
