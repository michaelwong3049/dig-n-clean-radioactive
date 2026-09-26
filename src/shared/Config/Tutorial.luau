--!strict
--[[
	Config/Tutorial — the new-player walkthrough's steps and what each one says.

	ON REQUEST: first stage, then find a spot, pull the nuke up, clean it, put it on a
	stand, buy the Bent Coil. The banner (client TutorialController) says only what to
	do NOW. It never says "step 3 of 6", on request, so there is no count anywhere in
	here either.

	THE STEP IS DERIVED, NEVER STORED. TutorialService reads it off the player's real
	state every tick (in a stage? locked on? carrying a crusted nuke? a clean one? a
	stand filled? the Bent Coil owned?), in the reverse order of `ORDER` below. That
	is what makes it resume after a rejoin and step back if the nuke is sold or blows
	up: there is no progress counter to get out of step with the world. The save holds
	only whether the walkthrough is still running (DataService's `onboarding`).
]]

local Tutorial = {}

export type StepId = "stage" | "dig" | "haul" | "clean" | "place" | "upgrade" | "finish"

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

--- The walk, in order. `finish` is the "You're set!" card, not a task.
Tutorial.ORDER = { "stage", "dig", "haul", "clean", "place", "upgrade", "finish" } :: { StepId }

Tutorial.STEPS = {
	stage = { title = "Head to the first stage", hint = "Follow the trail out of camp" },
	dig = { title = "Find a spot to dig", hint = "Walk onto a glowing spot and hold E" },
	haul = { title = "Click the nuke to the top", hint = "Click the button or press E" },
	clean = {
		title = "Clean the nuke",
		hint = "Take it to your cleansing station",
		holdHint = "Pick your nuke from the hotbar, then take it to your cleansing station",
	},
	place = {
		title = "Place the nuke on a stand",
		hint = "Hold E at an empty stand",
		holdHint = "Pick your nuke from the hotbar, then hold E at an empty stand",
	},
	upgrade = { title = "Upgrade your detector", hint = "Buy the Bent Coil at the Detector Shop" },
	finish = { title = "You're set!", hint = "Dig deeper, clean rarer nukes, fill your stands." },
} :: { [StepId]: Step }

--- The tier the last step asks for: the $15 Bent Coil (Config/Gear.Detector).
Tutorial.UPGRADE_TIER = 2

--- True while this save's first dig should be made safe. That means the walkthrough is
--- running and nothing has come out of the ground yet (empty bag, no crates, empty
--- stands). DigService then reads every signal as a plain Common for this player and
--- lights no fuse under the magnet. A brand-new player should not be blown up in their
--- first minute. It is a pure read of the save, so the ping, the lock and the haul all
--- give the same answer.
function Tutorial.isSafeDig(data: any): boolean
	if data == nil or data.onboarding ~= "active" then
		return false
	end
	return #data.carry == 0 and #(data.crates or {}) == 0 and #data.exhibit.pedestals == 0
end

return Tutorial
