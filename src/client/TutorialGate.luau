--!strict
--[[
	TutorialGate — keeps a ScreenGui switched off until the new-player walkthrough is
	over. Used by the right-hand HUD (2x Luck / 2x Speed cards, the Boosts pills, the
	Daily + Potions corner row and the potion chips), so a new player only sees what
	the tutorial points at.

	Reads TutorialService's `TutorialActive` attribute: nil until the save loads, then
	true while the walkthrough runs. Only `false` opens the gui, so it starts hidden
	(as WarpController's HOME / SHOPS do).
]]

local Players = game:GetService("Players")

local TutorialGate = {}

function TutorialGate.done(): boolean
	return Players.LocalPlayer:GetAttribute("TutorialActive") == false
end

--- Enables `gui` only once the walkthrough is finished (or skipped).
function TutorialGate.bind(gui: ScreenGui)
	local function refresh()
		gui.Enabled = TutorialGate.done()
	end
	Players.LocalPlayer:GetAttributeChangedSignal("TutorialActive"):Connect(refresh)
	refresh()
end

return TutorialGate
