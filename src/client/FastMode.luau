--!strict
--[[
	FastMode.luau — an opt-in "turn off decoration" toggle, for testing whether a low
	frame rate is coming from particles/motion rather than scene complexity.

	WHY THIS EXISTS: a direct measurement (Stats.FrameTime vs RunService.Heartbeat)
	showed script/physics ticking fine at 120Hz while actual render frame time sat
	around 30 FPS -- pointing at render load (the game's 100k+-part world), not
	script cost. This switch is cheap to try and easy to rule in or out; it is NOT
	expected to be the real fix, but it costs little to let a player check.

	WHAT IT TOUCHES: every ParticleEmitter already in the world (Enabled forced off,
	restored to exactly what it was before), the two purely-ambient motion loops that
	carry no gameplay meaning at all (StationMotionController's idle machines --
	fans, dial needles, ripples, screen pulse -- and ToolMotionController's orbiting
	magnet parts), and AuraController's rings -- every character's aura is fully
	hidden (beams off, electrons transparent, sparkle emitters off), on request, the
	same off-state setShown already uses for one out of range. All three just check
	FastMode.enabled at the top of their own per-frame step; nothing here reaches
	into any of them.

	WHAT IT DELIBERATELY DOES NOT TOUCH: the radiation damage overlay (RadFx) and
	displayed-item glow (ItemFxController) are read by the player as real state, not
	decoration, so they stay on even in fast mode. A particle burst a gameplay system
	triggers fresh WHILE fast mode is already on (a crate reveal, say) still plays --
	this sweeps what exists at the moment it is switched on, not a continuous watch
	on every emitter in the game.

	NOT PERSISTED. A one-session diagnostic switch, not a profile setting -- it
	defaults off on every join.
]]

local Workspace = game:GetService("Workspace")

local FastMode = {}

FastMode.enabled = false

local changed = Instance.new("BindableEvent")
FastMode.Changed = changed.Event

-- Only the emitters FastMode itself turned off, so turning it back off can never
-- re-enable something a gameplay system had already turned off for its own reasons.
local turnedOff: { ParticleEmitter } = {}

function FastMode.set(on: boolean)
	if on == FastMode.enabled then
		return
	end
	FastMode.enabled = on
	if on then
		table.clear(turnedOff)
		for _, inst in Workspace:GetDescendants() do
			if inst:IsA("ParticleEmitter") and inst.Enabled then
				inst.Enabled = false
				table.insert(turnedOff, inst)
			end
		end
	else
		for _, emitter in turnedOff do
			if emitter.Parent then
				emitter.Enabled = true
			end
		end
		table.clear(turnedOff)
	end
	changed:Fire(on)
end

return FastMode
