--!strict
--[[
	Config/Tutorial — the new-player walkthrough's steps and what each one says.

	ON REQUEST: first stage, then find a spot, pull the nuke up, clean it, put it on a
	stand, let it earn the Bent Coil's $15 (a live "$0/$15" count), buy the Bent Coil, then the HOME / SHOPS buttons ("navigate"), and that is the
	end: no "You're set!" card (removed on request). The banner (client TutorialController) says only what to
	do NOW. It never says "step 3 of 6", on request, so there is no count anywhere in
	here either.

	THE STEP IS DERIVED, NEVER STORED. TutorialService reads it off the player's real
	state every tick (in a stage? locked on? carrying a crusted nuke? a clean one? a
	stand filled? the Bent Coil owned?), in the reverse order of `ORDER` below. That
	is what makes it resume after a rejoin and step back if the nuke is sold or blows
	up: there is no progress counter to get out of step with the world. The save holds
	only whether the walkthrough is still running (DataService's `onboarding`).
]]

local Gear = require(script.Parent.Gear)

local Tutorial = {}

export type StepId = "stage" | "dig" | "haul" | "clean" | "place" | "earn" | "upgrade" | "navigate"

--- `title` is the whole banner. The banner went text-only on request (client
--- TutorialController), so `hint` and `holdHint` are not drawn at the moment. They
--- are kept so a hint line can come back without rewriting the copy.
export type Step = {
	title: string,
	hint: string,
	--- Shown instead of `hint` while the step needs the nuke in your hands and it
	--- is not (TutorialService sends `holding = false`).
	holdHint: string?,
}

--- The walk, in order. `navigate` is the last: TutorialController points at the HOME
--- and SHOPS buttons, and the walkthrough ends the moment you use one (WarpService) or
--- after NAVIGATE_SECONDS.
Tutorial.ORDER = { "stage", "dig", "haul", "clean", "place", "earn", "upgrade", "navigate" } :: { StepId }

Tutorial.STEPS = {
	stage = { title = "Head to the first stage", hint = "Follow the trail out of camp" },
	dig = { title = "Find a spot to dig", hint = "Walk onto a glowing spot and hold E" },
	haul = { title = "Click the nuke to the top before it explodes", hint = "Click the button or press E" },
	clean = {
		title = "Clean your nuke at your base",
		hint = "Take it to your cleansing station",
		holdHint = "Pick your nuke from the hotbar, then take it to your cleansing station",
	},
	place = {
		title = "Place the nuke on a stand",
		hint = "Hold E at an empty stand",
		holdHint = "Pick your nuke from the hotbar, then hold E at an empty stand",
	},
	-- ON REQUEST: the banner carries a live "$0/$15" count after the title
	-- (TutorialController), fed by TutorialService's `earned`.
	earn = { title = "Earn $15", hint = "Your stand earns cash on its own" },
	upgrade = { title = "Upgrade your detector", hint = "Buy the Bent Coil at the Detector Shop" },
	navigate = { title = "Use Home and Sell to get around", hint = "Tap Home or Sell at the top of the screen" },
} :: { [StepId]: Step }

--- ON REQUEST, the "navigate" step ends the walkthrough by itself after this long if
--- neither HOME nor SHOPS is pressed (walking home on foot is fine too).
Tutorial.NAVIGATE_SECONDS = 45

--- The tier the last step asks for: the $15 Bent Coil (Config/Gear.Detector).
Tutorial.UPGRADE_TIER = 2

--- What the "earn" step counts up to: the Bent Coil's price, so "upgrade" only comes
--- up once you can pay for it. The step is read off your cash (TutorialService).
Tutorial.EARN_TARGET = Gear.Detector[Tutorial.UPGRADE_TIER].price

--- True while this save's first dig should be made safe. That means the walkthrough is
--- running and nothing has come out of the ground yet (empty bag, no crates, empty
--- stands). DigService then reads every signal as a plain Common for this player. The
--- fuse still burns (on request), so the haul step warns before it explodes. It is a pure read of the save, so the ping, the lock and the haul all
--- give the same answer.
function Tutorial.isSafeDig(data: any): boolean
	if data == nil or data.onboarding ~= "active" then
		return false
	end
	return #data.carry == 0 and #(data.crates or {}) == 0 and #data.exhibit.pedestals == 0
end

--- ON REQUEST: a brand-new player joins at Stage 1's doorstep instead of on their base,
--- so "Head to the first stage" is a few steps, not a walk across camp. Their base is
--- still assigned and still their RespawnLocation. This only moves the join spawn.
--- Same test as isSafeDig: nothing dug yet. A rejoin partway through the walkthrough
--- with a nuke in the bag or on a stand has base work to do, so it lands on the base.
function Tutorial.spawnsAtField(data: any): boolean
	return Tutorial.isSafeDig(data)
end

--- Where spawnsAtField puts you: this many studs west of Stage 1's west edge, on the
--- plaza's green strip, level with the stage's middle and facing into it.
Tutorial.FIELD_SPAWN_BACK = 24

--- ON REQUEST: the "Find a spot to dig" step has exactly ONE spot, so nobody wanders
--- off. DigService plants it this many studs in from Stage 1's west edge, level with
--- the field spawn, and a safe digger registers nothing else. TutorialController points
--- arrows at it (the `TutorialDigSpot` attribute).
Tutorial.DIG_SPOT_IN = 18

-- ── What is shut while the walkthrough runs ──────────────────────────────────────
--
-- ON REQUEST: nothing the walkthrough does not ask for works until it is over. Your
-- cleansing station and stands stay open (the "clean" and "place" steps need them),
-- and the Detector shop (the Gear booth) opens on the "upgrade" step, which asks for the
-- Bent Coil. The Trader, every other shop, the Quarantine Locker, the luck button
-- and the floor signs are shut until you finish or SKIP.
--
-- Read off two attributes TutorialService writes every tick, `TutorialActive` and
-- `TutorialStep`, so both sides give the same answer: StationService treats a shut
-- station as nowhere (no panel opens, and nothing bought or sold there can land), the
-- server prompt handlers refuse, and TutorialController hides the prompts.

--- Station kinds that stay open for the whole walkthrough.
local OPEN_STATIONS = { decon = true, pedestal = true }
--- Steps on which the Detector shop is open.
local SHOP_STEPS = { upgrade = true }

function Tutorial.isActive(player: Player): boolean
	return player:GetAttribute("TutorialActive") == true
end

--- Whether the walkthrough still shuts things. False on the last step ("navigate"):
--- every task is done by then and it is pointing you at the shops, so they are open.
function Tutorial.gated(player: Player): boolean
	return Tutorial.isActive(player) and player:GetAttribute("TutorialStep") ~= "navigate"
end

--- Whether `player` may use the station (kind, id) right now.
function Tutorial.stationOpen(player: Player, kind: string?, id: string?): boolean
	if kind == nil or OPEN_STATIONS[kind] or not Tutorial.gated(player) then
		return true
	end
	return kind == "shop" and id == "Detector" and SHOP_STEPS[player:GetAttribute("TutorialStep")] == true
end

--- Whether `player` may use this prompt right now. Only the prompts that open or buy
--- something are named. Anything else (dig, crates, wash, stands, pickups) stays open.
function Tutorial.promptOpen(player: Player, prompt: ProximityPrompt): boolean
	if not Tutorial.gated(player) then
		return true
	end
	local parent = prompt.Parent
	if parent == nil then
		return true
	end
	local name = prompt.Name
	if name == "ViewShop" or name == "OpenLocker" or name == "OpenMerge" or name == "OpenReforge" or name == "OpenFurnace" then
		-- The desk / the rack carries the station attributes itself.
		return Tutorial.stationOpen(player, parent:GetAttribute("StationKind"), parent:GetAttribute("StationId"))
	elseif name == "Upgrade" then
		-- A rack mount names its track. Luck's
		-- button is a "Luck" mount, so it stays shut with the other shops.
		local track = parent:GetAttribute("SellsTrack")
		return type(track) == "string" and Tutorial.stationOpen(player, "shop", track)
	elseif name == "BuyFloor" then
		return false
	end
	return true
end

return Tutorial
