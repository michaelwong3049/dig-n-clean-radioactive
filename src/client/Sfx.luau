--[[
	Sfx.luau — every sound effect in the game, in one table, behind three verbs.

	ONE CATALOGUE, SO A SWAP IS ONE LINE. Every cue is a named DEF below: the asset,
	its volume, its pitch and how much the pitch wanders. Controllers ask for a cue by
	NAME (`Sfx.play("purchase")`) and never hold an asset id of their own, so replacing
	a sound, or quietening one that turned out too loud, never means hunting through
	the controllers for where it is played.

	THREE VERBS:
	  * `play(name)`         a 2D one-shot: UI, money, the stings. Heard only by you.
	  * `playAt(name, at)`   a 3D one-shot on a part/attachment or at a point: the dig
	                         crunch, crust flakes, a gear clack. Falls off with distance.
	  * `loop(name, at?)`    a held bed (hose, haul hum, aura hum) with a fade in/out;
	                         returns a handle you `set(true/false)` every frame for free
	                         and `destroy()` once.

	THE MUTE IS A SOUNDGROUP, NOT A FLAG IN EACH CALLER. Every sound this module makes
	joins one of four groups (sfx / ui / ambient / geiger) under a master group, and the
	Settings switch (Net.SfxMuted, saved on the profile) zeroes the master. The Settings
	volume sliders (Config/Prefs vol*) set the master and the groups the same way. A sound that is
	already playing goes quiet the same frame; nothing needs to remember to check.

	The Geiger bed, the detonation boom/fuse and the crate reels keep their own Sound
	instances (they predate this file), but they join the same master group through
	`Sfx.adopt`, so the one switch mutes the lot.

	SOURCES. Every id is a free Creator Store asset, checked loading in Studio on
	2026-09-27; most are Pro Sound Effects' library. Ids are ids, not taste: any of them
	can be swapped here without touching a caller.
]]

local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sfx = {}

export type Group = "sfx" | "ui" | "ambient" | "geiger" | "music"

type Def = {
	id: string,
	volume: number,
	speed: number?,
	-- ± fraction of random pitch per play, so a repeated cue does not read as a loop.
	jitter: number?,
	group: Group?,
	-- Minimum seconds between two plays of this cue; extra calls inside it are dropped.
	cooldown: number?,
	-- 3D only: the distance it fades out by.
	maxDistance: number?,
	-- Loops only: seconds to fade from silent to full (and back).
	fade: number?,
}

local function asset(id: number): string
	return "rbxassetid://" .. tostring(id)
end

local DEFS: { [string]: Def } = {
	-- ── Money and shops ─────────────────────────────────────────────
	purchase = { id = asset(120891770644830), volume = 0.5, group = "ui", cooldown = 0.15 },
	denied = { id = asset(96076237507837), volume = 0.4, group = "ui", cooldown = 0.25 },
	sell = { id = asset(9121189379), volume = 0.6, jitter = 0.06, group = "ui", cooldown = 0.08 },
	sellAll = { id = asset(9113849583), volume = 0.7, group = "ui", cooldown = 0.2 },
	awayCollect = { id = asset(9113849583), volume = 0.75, speed = 1.1, group = "ui" },
	robux = { id = asset(4612374393), volume = 0.6, group = "ui" },
	click = { id = asset(8816939097), volume = 0.35, jitter = 0.04, group = "ui", cooldown = 0.04 },
	mastery = { id = asset(4612374036), volume = 0.6, speed = 1.1, group = "ui", cooldown = 1 }, -- the "Mastery reached" toast

	-- ── Digging ─────────────────────────────────────────────────────
	dig = { id = asset(9114083746), volume = 0.45, jitter = 0.12, group = "sfx", cooldown = 0.07, maxDistance = 70 },
	dig2 = { id = asset(9114083260), volume = 0.4, jitter = 0.12, group = "sfx", cooldown = 0.07, maxDistance = 70 },
	haulHum = { id = asset(9125674129), volume = 0.3, speed = 1.15, group = "sfx", maxDistance = 60, fade = 0.35 },
	unearth = { id = asset(88369764315144), volume = 0.6, group = "sfx", maxDistance = 80 },
	rareSpot = { id = asset(108553348043184), volume = 0.22, speed = 0.9, group = "ambient", maxDistance = 45, fade = 0.8 },
	rareDrop = { id = asset(9119159511), volume = 0.45, group = "ui", cooldown = 2 },

	-- ── Cleaning and washing ────────────────────────────────────────
	hose = { id = asset(9126200774), volume = 0.4, group = "sfx", maxDistance = 55, fade = 0.15 },
	scrub = { id = asset(6383276435), volume = 0.22, speed = 1.2, group = "sfx", maxDistance = 40, fade = 0.2 },
	flake = { id = asset(9120962232), volume = 0.3, speed = 1.35, jitter = 0.18, group = "sfx", cooldown = 0.05, maxDistance = 40 },
	pump = { id = asset(9112889082), volume = 0.12, speed = 0.8, group = "ambient", maxDistance = 35, fade = 0.6 },
	pour = { id = asset(9113555949), volume = 0.45, group = "sfx", cooldown = 0.5 },
	brew = { id = asset(9125959246), volume = 0.4, group = "sfx", cooldown = 0.5 },
	-- A weak point bursting under the stream (WashWeakSpots): the flake crack, pitched down and louder.
	weakPop = { id = asset(9120962232), volume = 0.55, speed = 0.85, jitter = 0.1, group = "sfx", cooldown = 0.08, maxDistance = 40 },
	cleaned = { id = asset(4612374036), volume = 0.6, group = "sfx", cooldown = 1 },

	-- ── Aura and gear ───────────────────────────────────────────────
	auraEquip = { id = asset(70690253942164), volume = 0.55, group = "sfx", cooldown = 0.4 },
	auraHum = { id = asset(9125674114), volume = 0.08, group = "ambient", maxDistance = 30, fade = 1 },
	gearEquip = { id = asset(9116673277), volume = 0.5, jitter = 0.05, group = "sfx", cooldown = 0.15 },
	auraWarning = { id = asset(16903690359), volume = 0.4, group = "ui", cooldown = 1.5 },

	-- ── Radiation and health ────────────────────────────────────────
	heartbeat = { id = asset(139459003161851), volume = 0.5, group = "sfx", cooldown = 0.3 },
	sickness = { id = asset(9125484367), volume = 0.35, group = "sfx", cooldown = 1 },
	hurt = { id = asset(119089158569324), volume = 0.6, jitter = 0.08, group = "sfx", cooldown = 0.2 },
	flatline = { id = asset(120522903801665), volume = 0.4, group = "sfx" },
	respawn = { id = asset(9114156829), volume = 0.35, group = "sfx", cooldown = 1 },

	-- ── World ───────────────────────────────────────────────────────
	stage = { id = asset(9042305931), volume = 0.25, group = "ambient", cooldown = 3 },
	bagFull = { id = asset(119089158569324), volume = 0.55, speed = 0.7, group = "ui", cooldown = 0.5 },
	aurora = { id = asset(86488607363887), volume = 0.55, group = "sfx", cooldown = 5 },

	-- ── Nuke voices (NukeVoices, via ItemFxController) ──────────────
	-- 3D beds on a cleaned nuke: short reach, so you only hear one when you walk up to it.
	voiceTick = { id = asset(4940109913), volume = 0.45, group = "ambient", maxDistance = 22, fade = 0.4 },
	voiceDrone = { id = asset(1843770413), volume = 0.5, speed = 0.9, group = "ambient", maxDistance = 30, fade = 1 },
	voiceRumble = { id = asset(127117160383220), volume = 0.45, group = "ambient", maxDistance = 30, fade = 0.8 },
	voiceHum = { id = asset(9125674129), volume = 0.3, speed = 1.35, group = "ambient", maxDistance = 26, fade = 0.8 },
	voiceChime = { id = asset(9125674114), volume = 0.3, speed = 1.5, group = "ambient", maxDistance = 26, fade = 1 },
}

Sfx.DEFS = DEFS

-- ── Groups ──────────────────────────────────────────────────────────

-- Music starts silent: it is opt-in (Config/Prefs musicVol defaults to 0).
local GROUP_VOLUME: { [Group]: number } = { sfx = 1, ui = 1, ambient = 1, geiger = 1, music = 0 }

local folder: Folder? = nil
local master: SoundGroup? = nil
local groups: { [string]: SoundGroup } = {}
local lastPlayed: { [string]: number } = {}
local muted = false
-- Settings' master volume (Config/Prefs volMaster); the mute zeroes it on top.
local masterVolume = 1

local function ensure(): Folder
	if folder then
		return folder
	end
	local root = Instance.new("Folder")
	root.Name = "Sfx"

	local top = Instance.new("SoundGroup")
	top.Name = "Master"
	top.Volume = if muted then 0 else masterVolume
	top.Parent = root
	master = top

	for name, volume in GROUP_VOLUME do
		local group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = volume
		group.Parent = top
		groups[name] = group
	end

	root.Parent = SoundService
	folder = root
	return root
end

local function groupFor(def: Def): SoundGroup
	ensure()
	return groups[def.group or "sfx"]
end

--- Mute or unmute everything this module (and anything adopted) plays.
function Sfx.setMuted(on: boolean)
	muted = on
	ensure()
	if master then
		master.Volume = if on then 0 else masterVolume
	end
end

--- Settings' volume sliders (Config/Prefs), each 0..1. `ambient` follows the effects
--- slider: it is the hum and drone under them, not a channel anyone asked for.
function Sfx.setVolumes(master_: number, sfx: number, ui: number, geiger: number, music: number)
	masterVolume = master_
	ensure()
	if master then
		master.Volume = if muted then 0 else masterVolume
	end
	groups.sfx.Volume = sfx
	groups.ambient.Volume = sfx
	groups.ui.Volume = ui
	groups.geiger.Volume = geiger
	groups.music.Volume = music
end

function Sfx.muted(): boolean
	return muted
end

--- Put a Sound some other controller built under the same mute switch.
function Sfx.adopt(sound: Sound, group: Group?)
	ensure()
	sound.SoundGroup = groups[group or "sfx"]
end

-- ── One-shots ───────────────────────────────────────────────────────

type Opts = {
	volume: number?, -- multiplies the def's volume
	speed: number?, -- multiplies the def's pitch
}

local function make(name: string, opts: Opts?): Sound?
	local def = DEFS[name]
	if def == nil then
		warn(`[Sfx] no such sound: {name}`)
		return nil
	end

	local now = os.clock()
	if def.cooldown and now - (lastPlayed[name] or -math.huge) < def.cooldown then
		return nil
	end
	lastPlayed[name] = now

	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.id
	sound.Volume = def.volume * (if opts and opts.volume then opts.volume else 1)
	local jitter = def.jitter or 0
	local speed = (def.speed or 1) * (if opts and opts.speed then opts.speed else 1)
	sound.PlaybackSpeed = speed * (1 + (math.random() * 2 - 1) * jitter)
	sound.SoundGroup = groupFor(def)
	if def.maxDistance then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 8
		sound.RollOffMaxDistance = def.maxDistance
	end
	return sound
end

local function fire(sound: Sound)
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	-- Belt and braces: a sound that never loads never fires Ended.
	task.delay(12, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

--- A 2D one-shot, heard only by this player.
function Sfx.play(name: string, opts: Opts?)
	local sound = make(name, opts)
	if sound == nil then
		return
	end
	sound.Parent = ensure()
	fire(sound)
end

--- A 3D one-shot at a part, an attachment or a world point.
function Sfx.playAt(name: string, at: Instance | Vector3, opts: Opts?)
	local sound = make(name, opts)
	if sound == nil then
		return
	end
	if typeof(at) == "Vector3" then
		local anchor = Instance.new("Attachment")
		anchor.Name = "SfxAt"
		anchor.WorldPosition = at
		anchor.Parent = Workspace.Terrain
		sound.Parent = anchor
		sound.Destroying:Once(function()
			anchor:Destroy()
		end)
	elseif at and at.Parent then
		sound.Parent = at
	else
		sound.Parent = ensure()
	end
	fire(sound)
end

-- ── Loops ───────────────────────────────────────────────────────────

export type Loop = {
	--- Want it on or off. Cheap: call it every frame if that is easiest.
	set: (self: Loop, on: boolean, volume: number?) -> (),
	destroy: (self: Loop) -> (),
	sound: Sound,
}

type LoopState = {
	sound: Sound,
	base: number,
	fade: number,
	level: number,
	target: number,
	scale: number,
}

local loops: { [Loop]: LoopState } = {}
local stepping: RBXScriptConnection? = nil

local function step(dt: number)
	for handle, st in loops do
		if st.sound.Parent == nil then
			loops[handle] = nil
			continue
		end
		local rate = dt / math.max(st.fade, 0.01)
		if st.level < st.target then
			st.level = math.min(st.target, st.level + rate)
		elseif st.level > st.target then
			st.level = math.max(st.target, st.level - rate)
		end
		st.sound.Volume = st.base * st.scale * st.level
		if st.level > 0 and not st.sound.IsPlaying then
			st.sound:Resume()
		elseif st.level <= 0 and st.sound.IsPlaying then
			st.sound:Pause()
		end
	end
end

--- A held bed with a fade. `at` is a part/attachment for a 3D loop, nil for 2D.
function Sfx.loop(name: string, at: Instance?): Loop?
	local def = DEFS[name]
	if def == nil then
		warn(`[Sfx] no such sound: {name}`)
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.id
	sound.Looped = true
	sound.Volume = 0
	sound.PlaybackSpeed = def.speed or 1
	sound.SoundGroup = groupFor(def)
	if at and def.maxDistance then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 6
		sound.RollOffMaxDistance = def.maxDistance
	end
	sound.Parent = at or ensure()

	local st: LoopState = {
		sound = sound,
		base = def.volume,
		fade = def.fade or 0.3,
		level = 0,
		target = 0,
		scale = 1,
	}

	local handle = {} :: any
	handle.sound = sound
	function handle.set(_self, on: boolean, volume: number?)
		st.target = if on then 1 else 0
		st.scale = volume or 1
	end
	function handle.destroy(_self)
		loops[handle] = nil
		sound:Destroy()
	end

	loops[handle] = st
	if stepping == nil then
		stepping = RunService.Heartbeat:Connect(step)
	end
	return handle :: Loop
end

return Sfx
