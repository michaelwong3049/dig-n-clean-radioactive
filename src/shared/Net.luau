--!strict
--[[
	Net.lua — every remote in the game, declared in one table.

	ARCHITECTURE.md schedules this for Phase 1. It arrived early because the debug
	HUD needed a channel (that HUD and its remote are both gone now), and the
	alternative — one ad-hoc RemoteEvent parented wherever it was convenient — is
	exactly the mess this file exists to prevent.

	The server creates the instances; the client waits for them. Add a line to
	REMOTES and both sides get it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTES: { [string]: string } = {
	-- Phase 1: the sweep/dig loop.
	--
	-- SweepState carries contacts INSIDE THE PLAYER'S OWN REVEAL RADIUS, as offsets
	-- relative to that player — never world coordinates, and never anything outside
	-- the radius. Those signals are already standing in the world as auras that every
	-- client can see, so the payload leaks nothing a player is not looking at. The
	-- rest of the field never crosses: a digging game that replicates buried loot
	-- positions gets an ESP script written for it inside a week, and the rarity
	-- economy is the whole product. See the header of Services/DigService.
	SweepState = "RemoteEvent", -- server -> client, one payload per tick
	--
	-- DigYank replaced a DigInput boolean when the pull became a mash (PLAN §Step 2).
	-- It carries NO PAYLOAD, and that is the security design, not laziness: the client
	-- says "I clicked", never how hard, so the only thing it can lie about is HOW OFTEN.
	-- That one remaining lie is capped by a token bucket on the server -- see the yank
	-- limiter in Services/DigService, and Tuning's PULL_YANK_* block for why the ceiling
	-- sits where it does.
	DigYank = "RemoteEvent", -- client -> server, one per click, no payload
	--
	-- The pull is two beats: you TAP to commit to one buried item, and only then do you
	-- mash it out. DigLock carries a single boolean -- lock, or release -- and never an
	-- item id: the server picks whatever the player is standing on, exactly as it does
	-- for a yank. Locking roots the character, so the RELEASE half of this remote is
	-- load-bearing in a way most remotes are not; every path that can strand a rooted
	-- player is enumerated in Services/DigService.
	DigLock = "RemoteEvent", -- client -> server, true = lock on, false = release
	--
	-- Unearthed is the DIG moment and it no longer names anything. What breaks the
	-- surface is a lump of slag: the payload carries the rarity, the modifier and the
	-- weight -- everything the detector legitimately read -- and NOT the itemId, name or
	-- flavour, which would be the client holding the answer to a question the wash bay
	-- is supposed to ask. `identified` is true only for a pull that needed no cleaning
	-- at all (none rolls today), and only then does an identity ride along.
	Unearthed = "RemoteEvent", -- server -> client, the slot-machine moment
	--
	-- A Meteor Shower meteor (Config/Weather), to every client the moment it appears:
	-- { position = the impact point, landsAt = server time }. Pure presentation -- the
	-- spot it plants arrives as an ordinary aura at the impact.
	MeteorFall = "RemoteEvent", -- server -> all clients

	-- The backpack, as the player sees it. Fires only when the bag actually CHANGES
	-- (contents, decay condition, value or clean state) rather than on every tick — the
	-- bag is static for most of a run, and the smooth countdown on the detail card is
	-- computed client-side from Shared/Decay instead of being streamed.
	CarryState = "RemoteEvent", -- server -> client, on change

	-- Phase 1: base camp. Decontamination and the trader.
	StationState = "RemoteEvent", -- server -> client, what you're standing at and what's in your bag
	StationAction = "RemoteEvent", -- client -> server, scrub / sell / rack
	StationResult = "RemoteEvent", -- server -> client, "sold for $340", "needs Chem Bath"
	-- The Merge Reactor's roll, already decided (Services/MergeService): the outcome,
	-- the levels either side of it and the copy that came out, for the panel's reveal.
	MergeResult = "RemoteEvent", -- server -> client, { outcome, from, to, item }
	-- The Reforge Station's roll (Services/ReforgeService): the old and new damage/radius
	-- pair for the panel's KEEP / REVERT, any quality it added, and the copy as it stands.
	ReforgeResult = "RemoteEvent", -- server -> client, { uid, old, new, quality, item }
	-- The popup over the hotbar (InventoryController) for a refusal at something that
	-- has no panel to toast into -- StationResult is invisible there (memory:
	-- station-result-toast-needs-panel). The exhibit stands are the first user.
	Notice = "RemoteEvent", -- server -> client, "inventory full"

	-- The fluid bottle (Config/Liquids, Services/LiquidService). There used to be a
	-- LiquidState remote here feeding the wash pad's loaded-fluid readout; the bottle's
	-- own colour and sign replaced it, so it went with the pad.
	--
	-- One spin, already decided: the reel of liquid ids to scroll, the index it lands
	-- on, how long to take, and what came out. The server rolls before this fires, so
	-- the client is only ever animating a result -- it never asks for one, and the
	-- remote carries nothing the client could send back to steer it. The request half
	-- is the bottle's ProximityPrompt, which fires on the server by itself.
	FluidSpin = "RemoteEvent", -- server -> client, { reel, land, seconds, result, held, loaded }
	--
	-- The fluid panel you get walking up to your own bottle (LiquidController). State
	-- is change-driven: the loaded fluid and what is left of it, seconds until the
	-- next roll, and the Luck upgrade's multiplier and next price. `notice` rides along
	-- once when an action is refused ("not enough cash"), so the panel can say why.
	FluidState = "RemoteEvent", -- server -> client, { liquid, held, cooldown, luck, luckLevel, luckPrice, boost, rollLuck, notice? }
	--
	-- The panel's two buttons. A bare verb, never an amount or a target: the server
	-- finds the player's own bottle, checks they are standing at it, and does the rest.
	FluidAction = "RemoteEvent", -- client -> server, "roll" | "luck"

	-- Which carried item the player is physically holding. The tub refuses to wash
	-- anything you are not holding, so this had to become real state rather than the
	-- client-only hotbar selection it used to be.
	HoldInput = "RemoteEvent", -- client -> server, "hold this uid" (or nil for nothing)
	-- Where each item sits in the hotbar/bag after a drag-to-swap (InventoryController).
	-- Client -> server { uid or "" } by slot; saved as data.slotOrder and handed back
	-- on CarryState (`order`) so the arrangement survives a rejoin.
	SlotOrder = "RemoteEvent",

	-- Supply crates (Config/Crates). CrateOpen asks to open the crate in your hands; a
	-- nuke crate answers on CrateOpened (the reel popup), a liquid crate on FluidSpin.
	CrateOpen = "RemoteEvent", -- client -> server, the held crate's uid
	CrateOpened = "RemoteEvent", -- server -> client, { crate, reel, land, seconds, result, name, rarity, modifier, notice? }

	-- The wash bay. WashState is the session; WashInput is aim + intent, never
	-- progress -- the server owns the clock, exactly as the scrub timer did before it.
	WashState = "RemoteEvent", -- server -> client, the session (nil payload = ended)
	WashInput = "RemoteEvent", -- client -> server, { spraying, patchIndex }

	-- The treadmill (Config/Treadmill, Services/TreadmillService). What the player's
	-- banked training is worth right now: speed, the bar to the next point, the rate
	-- the belt they are standing on is paying, and what the next rung costs.
	--
	-- CHANGE-DRIVEN, NOT PER-TICK, with one deliberate exception: while a player is
	-- actually ON a belt this fires on the training cadence, because the bar creeping
	-- forward IS the feedback and a readout that only moves once every few minutes is
	-- indistinguishable from a broken one. Off the belt it goes quiet entirely, which
	-- is most of the time for most players.
	SpeedState = "RemoteEvent", -- server -> client, lifetime Speed + level + belt readout

	-- Phase 2: exposure.
	ExposureState = "RemoteEvent", -- server -> client, the rad meter, once per tick
	Blackout = "RemoteEvent", -- server -> client, you went down and what it cost
	-- Your own dropped bag, for the "get it back" tracker (BagTrackerController). One
	-- message when it lands { id, position, expiresAt, items }, another whenever someone
	-- takes from it { id, items } -- plus { stolenBy, stolenCount } when that someone is
	-- not you -- and a last one when it is emptied or times out { id, gone = true }.
	-- Owner only: everyone else reads the bag's own attributes (DroppedBagController).
	DroppedBag = "RemoteEvent", -- server -> client
	-- Client -> server, (bagId): the owner pressed Recover. The SERVER holds the bag
	-- and opens the purchase prompt, so the hold is in place before the dialog is.
	RecoverBag = "RemoteEvent",

	-- A nuke's pull fuse ran out and it went off (Services/HazardService). Fired to
	-- EVERY client, not just the puller: the flash, the cloud and the shake are a
	-- shared-server moment, and anyone inside the blast gets knocked flat by their own
	-- client (the character's physics is theirs). Carries a world position, which is
	-- fine -- there is nothing buried there any more. The crater it leaves is a real
	-- part in Workspace (Config/Detonation.FOLDER), so late joiners see that too.
	Detonation = "RemoteEvent", -- server -> all clients, { position, rarity, blastRadius, orbRadius }
	--
	-- Dropping the held clean nuke as a bomb (Services/BombService). BombDrop carries NO
	-- PAYLOAD: the server drops whatever the player is holding, so the only thing a
	-- client can lie about is when. BombState answers the dropper with the cooldown
	-- { readyAt, cooldown } (a server-clock deadline) or a refusal { notice }.
	BombDrop = "RemoteEvent", -- client -> server, no payload
	BombState = "RemoteEvent", -- server -> client, { readyAt, cooldown } | { notice }

	-- The index GUI. One snapshot on load, { discovered, stats } (data.discovered and
	-- data.indexStats); the client tops it up itself from the `index` record riding on
	-- ItemIdentified as new identifications happen, so this never needs to fire a
	-- second time. It used to top up from Unearthed, which lit the catalogue tile for
	-- something the player had not been told they were carrying.
	IndexState = "RemoteEvent", -- server -> client, once per load
	-- "I have looked at this entry": clears its NEW badge. Carries one itemId. The
	-- server only ever flips a flag it set itself, so a spoofed id does nothing.
	IndexSeen = "RemoteEvent", -- client -> server

	-- WHAT THE LUMP TURNED OUT TO BE. An item comes out of the ground encased in slag
	-- (Shared/ItemCrust) and is "???" everywhere until the crust is off, so Unearthed
	-- can no longer carry an identity -- this is the remote that does, fired the moment
	-- the last patch pops at the wash bay (or the trader names it on a blind sale). It
	-- is also what unlocks the index tile, which is why the itemId rides on THIS rather
	-- than on the dig.
	ItemIdentified = "RemoteEvent", -- server -> client, the reveal

	-- The persistent cash badge. Fires only when data.cash actually changes (sell,
	-- spend, award, or a debug /cash) plus once on load -- not per tick, since cash
	-- moves far less often than exposure does. Payload is (cash, source?): `source` is
	-- "exhibit" for the passive stand payouts ExhibitService deposits every few
	-- seconds, so the badge can give those a quieter popup than a sale; nil otherwise.
	CashState = "RemoteEvent", -- server -> client, on change
	--
	-- The "While you were away" card (AwayEarningsService, client
	-- AwayEarningsController). Server -> client: the offer
	-- { amount, away, counted, rate, capped } on login, then { collected, doubled? }
	-- once it is paid. Client -> server: a bare verb, "ask" (push the offer if there
	-- is one) or "collect". Never an amount: the server holds that on the save. The
	-- DOUBLE IT half is a Robux product and arrives through ProcessReceipt instead.
	AwayEarnings = "RemoteEvent",
	--
	-- The floor purchase popup (ExhibitService, client FloorPurchaseController).
	-- Server -> client: { kind = "offer", plot, floor, price, stands, cash, board } when
	-- you hold E on your own base's floor sign, then { kind = "result", ok, message,
	-- floor, cash } after a BUY. Client -> server: "buy", plot, floor -- the server
	-- range-checks it against the live sign and buyFloor does every other check.
	FloorPurchase = "RemoteEvent",
	--
	-- The combined $/s every nuke on the player's stands is paying right now, hourly cap
	-- applied -- the number the badge prints under the balance. Fired only when that
	-- rate changes (a stand placed or cleared, a yield or level change), never per tick.
	IncomeState = "RemoteEvent", -- server -> client, exhibit $/s, on change
	--
	-- The Nukes panel (client NukesController, ExhibitService.nukeList). Every nuke on
	-- the player's stands, with what it pays per second. Asked for, never streamed: the
	-- panel requests a snapshot when it opens and again when CarryState / IncomeState
	-- say something moved while it is showing.
	NukeList = "RemoteEvent", -- server -> client, { slots, used, rate, raw, displayed, notice? }
	-- A bare verb: "list" (send me a snapshot) or "equipBest" (fill + upgrade my
	-- stands from the bag). No uid, no slot: the server picks everything.
	NukeAction = "RemoteEvent", -- client -> server, "list" | "equipBest" | "unequipAll" | "unequip" + uid
	--
	-- What gear you own (ShopService.loadout): every tier on every track, and which is in
	-- your hands. Asked for, never streamed; PurchaseHintController reads it. (The Gear
	-- panel and its "equip from anywhere" were removed on request, 2026-10-05.)
	GearList = "RemoteEvent", -- server -> client, { tracks = { LoadoutTrack } }
	GearAction = "RemoteEvent", -- client -> server, "list"

	-- "Getting around": the top-of-screen HOME / SHOPS portals (client WarpController)
	-- and the Warp tile's camp list (client CampWarpController). The client sends only
	-- a destination NAME -- { dest = "base" | "shops" } -- never a position, and
	-- WarpService re-derives the CFrame server-side, exactly the way DigService
	-- re-derives which signal a yank means. It is REFUSED from inside a stage
	-- (StageService.stageOf ~= nil) so it can never be an escape hatch out of a lethal
	-- field; the bar hides itself there and the camp list greys out, so that path is
	-- edge-only. A site camp's key (Config/Camps, e.g. "twilight") is also a
	-- destination, refused until the player has reached that camp on foot once.
	Warp = "RemoteEvent", -- client -> server, { dest = "base" | "shops" | <camp key> }
	--
	-- Which site camps this player has reached on foot (so their warp is unlocked) and
	-- which exist in this world at all (a place saved before the camp was built has no
	-- CampAnchor to land on, so its Warp-panel row must not show). Change-driven: once on load,
	-- then whenever either set moves. `unlocked` names a camp reached THIS push, so the
	-- banner can say so exactly once. Services/CampService. A client may also fire it
	-- EMPTY to ask for a fresh push: a push that lands before any listener is queued for
	-- the first controller to connect only (StageBanner), so the Warp panel asks.
	CampState = "RemoteEvent", -- server -> client, { reached, available, unlocked? }; client -> server, (nothing)

	-- Which physical plot this player was assigned this session, so the client can
	-- find its own base (placement, own-station prompts, signs). Server ->
	-- client, fired once from ExhibitService.assign after the profile loads; the
	-- payload is the bare integer index, never a position. Plot assignment is
	-- per-session and never changes once made, so there is nothing to persist and
	-- no reason to re-fire -- same "once on load" shape as CashState / IndexState.
	PlotState = "RemoteEvent", -- server -> client, plot index, once on assignment

	-- The player's chosen base accent colour (Settings GUI -> client SettingsController).
	-- Server -> client once on load with the saved value, so the picker opens showing
	-- it -- same "once on load" shape as PlotState above. Client -> server to change it:
	-- the payload is a bare "RRGGBB" hex string, or "" to reset the base back to the
	-- neutral grey an unclaimed plot wears. The colour lives on the profile
	-- (data.plotColor), not on a plot -- it follows the player onto whatever plot they
	-- are assigned. ExhibitService validates the hex (format only) and repaints.
	PlotColor = "RemoteEvent",

	-- Settings' HIDE MY AURA toggle (client SettingsController, server AuraService). Same
	-- shape as PlotColor: server -> client once on load with the saved boolean, and
	-- again as the confirmed echo after every change; client -> server a bare boolean.
	-- It is a profile setting (data.hideAura), and while it is on AuraService stops
	-- publishing the player's AuraTier, so NOBODY draws their aura. The protection is
	-- untouched: the aura's stats come from data.gear.aura, never from this.
	HideAura = "RemoteEvent",

	-- The new-player walkthrough (Config/Tutorial, client TutorialController). Server ->
	-- client on change: { step = StepId, holding = boolean, plot = number? }, or nil once it is over
	-- (finished or skipped). Client -> server: the bare verb "skip".
	TutorialState = "RemoteEvent",
	TutorialAction = "RemoteEvent",

	-- Sound effects (client Sfx.luau). Sfx: server -> client, a cue NAME the client
	-- plays for its own player only ("denied", "robux") -- for the moments only the
	-- server sees. SfxMuted: Settings' SOUND EFFECTS switch, the same once-on-load-then-
	-- echo shape as HideAura; a profile setting (data.sfxMuted), client -> server a
	-- bare boolean.
	Sfx = "RemoteEvent",
	SfxMuted = "RemoteEvent",

	-- The rest of the Settings panel (Config/Prefs). Server -> client the WHOLE prefs
	-- table, once on load and again as the confirmed echo after every change. Client ->
	-- server { key = string, value = any } to change one, or nil to ask for the table
	-- (the same "ask rather than wait" as SfxMuted). PrefsService sanitizes every value
	-- against Config/Prefs; a rejected or rate-limited change just echoes what stuck.
	Prefs = "RemoteEvent",

	-- The walk-speed picker (SpeedController's pencil). Client -> server a number: the
	-- walk to cap at, or 0 for full speed. The confirmed value comes back on SpeedState
	-- (`walkCap`), so there is no echo remote of its own.
	WalkCap = "RemoteEvent",
	-- The red cash button on a treadmill's upgrade sign (client TreadmillSignController):
	-- "buy my next belt". No payload: the server prices the rung the save is on, and
	-- checks the player owns the base and is standing by its sign.
	TreadmillBuy = "RemoteEvent", -- client -> server, no payload

	-- Nuke models on demand (Services/ModelCacheService, Shared/ItemModels). The
	-- templates live in ServerStorage so nobody downloads all 10k parts at join; a
	-- client names the item ids it is about to draw and the server copies those
	-- templates into that player's own PlayerGui.NukeModels, once each.
	NukeModels = "RemoteEvent", -- client -> server, { itemId }

	-- The Masteries panel (Config/Masteries, Services/MasteryService). Server -> client:
	-- { masteries = { {id, count, tier} }, unlocked = { {id, tier} }? }, whenever a
	-- counter moves; `unlocked` is a tier reached since the last push (the toast).
	-- Client -> server, no payload: "send me the panel" (once, when it is built).
	MasteryState = "RemoteEvent",

	-- Settings > Stats (Services/StatsService). Client -> server, no payload: "send my
	-- numbers" (while the page is open). Server -> client: { playtime, dug, itemsCleaned,
	-- cashEarned, indexFound, indexTotal, deepestStage, kills, bagsStolen, deaths,
	-- bombsDropped, rareFinds, merges, rolls, cratesOpened }.
	PlayerStats = "RemoteEvent",

	-- The daily login calendar (Config/DailyRewards, Services/DailyRewardService).
	-- Client -> server: "ask" or "claim". Server -> client: { day, ready, readyAt,
	-- resetAt, days = { {cash, crates, luckSeconds, cashBoostSeconds, big} }, claimed? }.
	DailyRewards = "RemoteEvent",

	-- The Free Gifts ladder (Config/PlaytimeGifts, Services/PlaytimeGiftService). Client ->
	-- server: "ask", "claim" + gift index, or "claimAll". Server -> client: { startedAt, now,
	-- gifts = { {minutes, cash, speed, luckSeconds, cashBoostSeconds, potions, crates, big} },
	-- claimed = { index }, justClaimed? }, on load, on each ask and after each claim.
	PlaytimeGifts = "RemoteEvent",

	-- Potions (Config/Potions, Services/PotionService). Client -> server: "ask", or
	-- "drink" + potion id. Server -> client: { stash = { id -> count }, got?, drank?,
	-- notice? }.
	Potions = "RemoteEvent",

	-- The group chest on Stage 1 (Config/GroupReward, Services/GroupRewardService).
	-- Server -> client: { result = "join" | "claimed" | "already", groupId?, text? }
	-- on each press of the chest. Client -> server: "claim" (after joining the group).
	GroupReward = "RemoteEvent",

	-- The Shop's CODES section (Config/Codes, Services/CodeService). Client -> server:
	-- the typed code (a string). Server -> client: { result = "ok" | "invalid" | "used" |
	-- "join" | "busy", text?, groupId? } -- "join" means not in the group yet (the client
	-- opens the join prompt and sends the same code again).
	RedeemCode = "RemoteEvent",

	-- Gifting the nuke in your hands (Config/Gift, Services/GiftService), unlocked at
	-- Toxic Twilight for both players. Client -> server: ("offer", targetPlayer) from the
	-- giver's prompt, then a bare "accept" / "decline" from the receiver's card -- never
	-- a uid: the server gifts whatever the giver is holding. Server -> client, to the
	-- receiver: { kind = "offer", from, fromUserId, seconds, item }, { kind = "result",
	-- ok, message, keep? } after ACCEPT, or { kind = "closed", reason } when it lapses.
	Gift = "RemoteEvent",

	-- The bottom-right Boosts widget (Services/BoostsService, BoostsController). Server ->
	-- client: StatResolver.boosts(data), sent on join and whenever a total or a source
	-- changes. Countdowns are not in it: the client reads each source's `timer` attribute.
	Boosts = "RemoteEvent",
}

local Net = {}

local folder: Instance

-- Edit mode counts as neither running-server nor running-client: IsServer() is false
-- and IsClient() is true, so the naive version of this took the client branch and
-- blocked on WaitForChild forever the moment anyone required Net from the command
-- bar. Edit takes the create-if-missing path instead — idempotent, and it keeps
-- static checks from hanging Studio.
--
-- IsEdit() is plugin-security, so calling it straight from a real client script
-- throws "lacking capability Plugin". pcall gives us the answer where we are allowed
-- to have it (the command bar) and a safe `false` everywhere else — which is exactly
-- right, because everywhere else is genuinely not edit mode.
local isEdit = false
do
	local ok, result = pcall(function()
		return RunService:IsEdit()
	end)
	isEdit = ok and result == true
end

if RunService:IsServer() or isEdit then
	local existing = ReplicatedStorage:FindFirstChild("Net")
	if existing then
		folder = existing
	else
		local made = Instance.new("Folder")
		made.Name = "Net"
		made.Parent = ReplicatedStorage
		folder = made
	end

	for name, className in REMOTES do
		if folder:FindFirstChild(name) == nil then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	local found = ReplicatedStorage:WaitForChild("Net", 15)
	assert(found, "Net: the server never created ReplicatedStorage.Net — did the server bootstrap fail?")
	folder = found
end

--- Fetch a remote by name. Yields on the client until it replicates.
function Net.get(name: string): any
	assert(REMOTES[name], `Net: no remote named "{name}" — add it to REMOTES`)
	return folder:WaitForChild(name)
end

return Net
