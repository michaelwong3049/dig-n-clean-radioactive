--[[
	DetectorController.lua — the sweep, rendered.

	WHAT THIS DRAWS NOW, AND WHAT IT USED TO DRAW.
	It used to be a NEEDLE. The server sent one angle and one strength and the whole
	screen was derived from those two numbers, because the field was a secret and a
	direction was the most the client was allowed to know.

	The detector no longer works that way. Its radius REVEALS: every registerable
	signal inside it stands up out of the ground as an aura, and the server sends this
	client the ones it personally registers, as offsets from the player. So the dial
	is a RADAR SCOPE — you at the centre, your radius as the ring, a blip per contact.
	The direction problem the needle existed to solve does not exist any more; the
	world answers it directly.

	THE SCOPE IS NOT REDUNDANT WITH THE AURAS, and the reason is worth keeping.
	An aura is one shared part that every player in the server can see, so it cannot
	say anything that is supposed to be private — and rarity is private, gated per
	player by detectorClarity (PLAN §2 step 1). The aura says "something is here"; the
	BLIP is where "and it is Legendary" gets to live, because the blip is drawn from a
	payload only this client receives. Delete the scope and the entire clarity upgrade
	track loses its display. It WAS deleted for one pass, for exactly that reason it
	should not have been, and it is back.

	IT IS IN THE BOTTOM-RIGHT CORNER NOW, ALONE, NOT IN THE INSTRUMENT BAND. It used to
	sit beside the dig button in the middle of the dock, which put a 180px dial in the
	busiest part of the screen and made INSTRUMENT_HEIGHT (and so RESERVE, and so
	every centred panel's headroom) 36px taller than the meter needed. Corner-anchored
	it costs the layout nothing: it shares only the INSTRUMENT_BOTTOM baseline with the
	meter diagonally opposite it — see Dock.SCOPE_BOTTOM. The index button briefly
	stacked above it here too, but has since moved to the opposite corner, above the
	cash badge; nothing shares this corner with the scope any more.

	NO SOUND. The detector used to carry hot/cold by audio — a rate-and-pitch ping
	keyed to the nearest contact, plus a chirp on each new reveal (PLAN §10.7's
	"sweep with your eyes half shut"). Both were removed on request. The feedback is
	entirely visual now: the scope dial and its blips on screen, and out in the world
	the aura wells and the range ring (FieldController).

	SCOPE_RADIUS stays local because nothing outside this file reads it, but it is
	DERIVED from Dock.SCOPE_DIAL rather than a second hardcode, because it drives the
	ring sizes, the sweep arm's length AND the blip polar-placement maths all at once
	— change the dial without updating this and blips cluster inside a ring that no
	longer matches what is drawn.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Detector = {}

-- Same fields UIKit.C already carries (panel/stroke/text/dim/green/amber/red/scope),
-- so every COLOR.xxx read throughout render/state logic below keeps working
-- unchanged — this is an alias, not a copy, on purpose.
local COLOR = UIKit.C

local DIAL_SIZE = Dock.SCOPE_DIAL
local SCOPE_RADIUS = Dock.SCOPE_DIAL / 2 - 15 -- px from the centre of the dial to the radius ring
local MAX_BLIPS = 12 -- matches DigService.MAX_CONTACTS; more would never arrive

-- The button's per-click kick. This is the ONLY instant feedback the mash has, and it
-- earns its place: SweepState arrives at 10 Hz, so the progress bar can be up to 100ms
-- behind a click, which on a verb this fast reads as unresponsiveness. The kick fires
-- off the local input instead, so the button answers the finger immediately while the
-- bar catches up. It deliberately reports the INPUT, never the outcome -- it is not
-- lying about progress the server may yet reject, it is confirming a click happened.
local YANK_KICK_SECONDS = 0.12
local YANK_KICK_SCALE = 0.05 -- how far the button swells at the peak of a kick

-- How fast the fill chases the server's value (1/seconds). The bar is smoothed rather
-- than snapped because drag is continuous and 10 Hz updates make a steady sink look
-- like a stutter; fast enough that a yank still lands as a visible jump.
local FILL_LERP_RATE = 14

type Contact = { dx: number, dz: number, rarity: string? }

local state = {
	inStage = false,
	hasSignal = false,
	radius = 0,
	contacts = {} :: { Contact },
	rarityHint = nil :: string?,
	inRange = false,
	blocked = nil :: string?,
	digProgress = 0,
	-- Committed to a signal and rooted in place. The server is the authority on this;
	-- the client never decides it is locked on its own, because being locked is what
	-- takes the player's movement away.
	locked = false,
}

local ui = {}
local blips: { Frame } = {}
-- What the fill is currently DRAWING, chasing state.digProgress. Separate from the
-- server's value so smoothing never feeds back into what we think progress is.
local shownProgress = 0
-- When the player last clicked, in os.clock. Drives the button's kick animation and
-- nothing else -- "are they hauling" is answered by state.locked now, which comes from
-- the server, rather than by guessing from how recently a key was pressed.
local lastYankAt = -math.huge

-- ── Build ───────────────────────────────────────────────────────────

local function buildScope(parent: GuiObject)
	-- The radius ring. This is the stat you are buying, drawn at its actual size
	-- relative to the blips inside it, so a detector upgrade is legible on the HUD
	-- and not just in the shop.
	local edge = Instance.new("Frame")
	edge.Name = "RadiusRing"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.fromOffset(SCOPE_RADIUS * 2, SCOPE_RADIUS * 2)
	edge.BackgroundTransparency = 1
	edge.Parent = parent

	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(1, 0)
	edgeCorner.Parent = edge

	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Color = COLOR.scope
	edgeStroke.Transparency = 0.55
	edgeStroke.Thickness = 1
	edgeStroke.Parent = edge
	ui.edgeStroke = edgeStroke

	-- Half-radius ring, purely so distance on the scope is readable rather than just
	-- ordinal. Without it every blip is "somewhere in the circle".
	local inner = Instance.new("Frame")
	inner.Name = "HalfRing"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromOffset(SCOPE_RADIUS, SCOPE_RADIUS)
	inner.BackgroundTransparency = 1
	inner.Parent = parent

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(1, 0)
	innerCorner.Parent = inner

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = COLOR.scope
	innerStroke.Transparency = 0.82
	innerStroke.Thickness = 1
	innerStroke.Parent = inner

	-- The sweep arm. One revolution per RANGE_RING_PERIOD, off the same clock as the
	-- range ring the detector throws on the ground, so the HUD and the world are
	-- visibly the same pulse rather than two unrelated animations.
	local arm = Instance.new("Frame")
	arm.Name = "SweepArm"
	arm.AnchorPoint = Vector2.new(0.5, 1)
	arm.Position = UDim2.fromScale(0.5, 0.5)
	arm.Size = UDim2.fromOffset(2, SCOPE_RADIUS)
	arm.BackgroundColor3 = COLOR.scope
	arm.BackgroundTransparency = 0.6
	arm.BorderSizePixel = 0
	arm.Parent = parent
	ui.arm = arm

	-- You. A fixed dot so the blips read as "relative to me" instantly.
	local origin = Instance.new("Frame")
	origin.Name = "Origin"
	origin.AnchorPoint = Vector2.new(0.5, 0.5)
	origin.Position = UDim2.fromScale(0.5, 0.5)
	origin.Size = UDim2.fromOffset(4, 4)
	origin.BackgroundColor3 = COLOR.text
	origin.BackgroundTransparency = 0.35
	origin.BorderSizePixel = 0
	origin.Parent = parent

	local originCorner = Instance.new("UICorner")
	originCorner.CornerRadius = UDim.new(1, 0)
	originCorner.Parent = origin

	-- Pooled. Contacts churn every tick as the player walks, and building and
	-- destroying twelve frames ten times a second to show the same twelve dots is
	-- pure garbage collection for no visible gain.
	for index = 1, MAX_BLIPS do
		local blip = Instance.new("Frame")
		blip.Name = `Blip{index}`
		blip.AnchorPoint = Vector2.new(0.5, 0.5)
		blip.Size = UDim2.fromOffset(8, 8)
		blip.BackgroundColor3 = COLOR.scope
		blip.BorderSizePixel = 0
		blip.Visible = false
		blip.ZIndex = 2
		blip.Parent = parent

		local blipCorner = Instance.new("UICorner")
		blipCorner.CornerRadius = UDim.new(1, 0)
		blipCorner.Parent = blip

		local blipStroke = Instance.new("UIStroke")
		blipStroke.Color = COLOR.panel
		blipStroke.Thickness = 1
		blipStroke.Parent = blip

		blips[index] = blip
	end
end


local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DetectorHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Radar scope: bottom-right corner, on the same INSTRUMENT_BOTTOM baseline as the
	-- rad meter diagonally opposite it, with the index button stacked above. It used
	-- to live inside the instrument band beside the dig button; out here it is clear
	-- of the screen's centre and no longer inflates the band's height for everything
	-- else. AnchorPoint(1,1) so the position places its bottom-RIGHT corner, which is
	-- what makes ROW_SIDE_MARGIN read as a margin from the screen edge.
	local dial, ring = UIKit.panel(gui, {
		name = "Scope",
		size = UDim2.fromOffset(DIAL_SIZE, DIAL_SIZE),
		position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 1, -Dock.SCOPE_BOTTOM),
		anchorPoint = Vector2.new(1, 1),
		color = COLOR.panel,
		transparency = 0.25,
		cornerRadius = UIKit.Radius.pill,
		strokeColor = COLOR.stroke,
	})
	dial.ClipsDescendants = true
	ui.ring = ring

	buildScope(dial)

	ui.centre = UIKit.label(dial, {
		name = "Centre",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, 53),
		size = UDim2.fromOffset(170, 22),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 3,
	})

	-- Status line: dead centre, above the instrument band.
	ui.status = UIKit.label(gui, {
		name = "Status",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -Dock.STATUS_BOTTOM),
		size = UDim2.fromOffset(640, Dock.STATUS_HEIGHT),
		font = UIKit.Font.body,
		textSize = 18,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
	})

	-- Dig button. Dead centre of the instrument band — the primary touch/click
	-- target, so it gets the middle rather than either instrument either side of it.
	local digButton, digStroke = UIKit.button(gui, {
		name = "DigButton",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -Dock.INSTRUMENT_BOTTOM),
		size = Dock.DIGBUTTON_SIZE,
		font = UIKit.Font.body,
		textSize = 20,
		color = COLOR.dim,
		fillColor = COLOR.panel,
		fillTransparency = 0.15,
		strokeColor = COLOR.stroke,
		cornerRadius = UIKit.Radius.button,
		text = "TAP  E  TO LOCK ON",
	})
	ui.digButton = digButton
	ui.digStroke = digStroke

	-- Dig progress, drawn as a fill sliding under the button label. Scale-based, so
	-- it tracks the button's new size with no change of its own.
	local digFill = Instance.new("Frame")
	digFill.Size = UDim2.fromScale(0, 1)
	digFill.BackgroundColor3 = COLOR.green
	digFill.BackgroundTransparency = 0.7
	digFill.BorderSizePixel = 0
	digFill.ZIndex = 0
	digFill.Parent = digButton
	ui.digFill = digFill

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UIKit.Radius.button
	fillCorner.Parent = digFill

	-- Unearth banner: true centre, upper-third of the screen. Already lived there
	-- before this pass; only the size and type grew.
	local banner, bannerStroke = UIKit.panel(gui, {
		name = "Banner",
		size = UDim2.fromOffset(640, 160),
		position = UDim2.fromScale(0.5, 0.32),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = COLOR.panel,
		transparency = 0.1,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		visible = false,
	})
	ui.banner = banner
	ui.bannerStroke = bannerStroke

	ui.bannerRarity = UIKit.label(banner, {
		name = "Rarity",
		position = UDim2.fromOffset(0, 14),
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.body,
		textSize = 18,
		xAlign = Enum.TextXAlignment.Center,
	})

	ui.bannerName = UIKit.label(banner, {
		name = "NameLabel", -- NOT "Name" — every Instance already has a .Name
		-- property, so a child actually named "Name" is unreachable by
		-- Banner.Name (that resolves to the property, a string, not the child).
		-- Harmless here since every reader uses the captured ui.bannerName
		-- reference, never a re-lookup, but it is a landmine for anyone who
		-- later does try to reach it by path.
		position = UDim2.fromOffset(0, 40),
		size = UDim2.new(1, 0, 0, 50),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero - 4,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
	})

	ui.bannerFlavor = UIKit.label(banner, {
		name = "Flavor",
		anchorPoint = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 96),
		size = UDim2.new(1, -40, 0, 50),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
	})

	-- ── The haul panel ────────────────────────────────────────────────
	-- Up only while locked onto a signal. This is the second beat of the pull: the
	-- first tap commits you to one buried thing and plants your feet, and everything
	-- from there happens in here.
	--
	-- It sits just above the dock rather than at screen centre, so the item climbing out
	-- of the soil stays visible above it. The whole reason the haul is a physical model
	-- in the world rather than a number is that you get to watch it surface; a panel
	-- over the middle of the screen would hide exactly that. Anchored off
	-- Dock.HAULPANEL_BOTTOM so it clears the instrument band on every viewport -- see
	-- that constant for why a screen fraction was wrong.
	local haul, haulStroke = UIKit.panel(gui, {
		name = "HaulPanel",
		size = Dock.HAULPANEL_SIZE,
		position = UDim2.new(0.5, 0, 1, -Dock.HAULPANEL_BOTTOM),
		anchorPoint = Vector2.new(0.5, 1),
		color = COLOR.panel,
		transparency = 0.08,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.normal,
		visible = false,
	})
	ui.haul = haul
	ui.haulStroke = haulStroke

	-- What you committed to. Carries the rarity when the detector is good enough to
	-- resolve it and "unknown mass" when it is not -- the same per-player gate the
	-- radar blips use, so a cheap detector still buys you a blind haul.
	ui.haulTitle = UIKit.label(haul, {
		name = "HaulTitle",
		anchorPoint = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 18),
		size = UDim2.new(1, -40, 0, 30),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
	})

	-- The haul bar. Bigger than the dock's own fill and the thing the player is
	-- actually watching while mashing; the dock button keeps its little fill for
	-- continuity but this is the readout that matters now.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 58)
	track.Size = UDim2.new(1, -48, 0, 26)
	track.BackgroundColor3 = COLOR.empty
	track.BorderSizePixel = 0
	track.Parent = haul

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UIKit.Radius.button
	trackCorner.Parent = track

	local haulFill = Instance.new("Frame")
	haulFill.Name = "Fill"
	haulFill.Size = UDim2.fromScale(0, 1)
	haulFill.BackgroundColor3 = COLOR.green
	haulFill.BorderSizePixel = 0
	haulFill.Parent = track
	ui.haulFill = haulFill

	local haulFillCorner = Instance.new("UICorner")
	haulFillCorner.CornerRadius = UIKit.Radius.button
	haulFillCorner.Parent = haulFill

	-- The mash prompt doubles as the touch target: a phone has no E key, so without a
	-- tappable control here the entire second beat would be keyboard-only.
	local haulButton, haulButtonStroke = UIKit.button(haul, {
		name = "HaulButton",
		anchorPoint = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 94),
		size = UDim2.new(1, -48, 0, 34),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = COLOR.green,
		fillColor = COLOR.panel,
		fillTransparency = 0.2,
		strokeColor = COLOR.stroke,
		cornerRadius = UIKit.Radius.button,
		text = "MASH  E  TO HAUL",
	})
	ui.haulButton = haulButton
	ui.haulButtonStroke = haulButtonStroke

	-- RELEASE HAS TO BE VISIBLE. Locking roots the character, so a player who cannot
	-- find the way out is stuck standing in a field. It is a real button rather than
	-- only a key hint for the same reason the mash prompt is: on touch there is no Q.
	local releaseButton = UIKit.button(haul, {
		name = "ReleaseButton",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -10),
		size = UDim2.new(1, -48, 0, 20),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = COLOR.dim,
		fillColor = COLOR.panel,
		fillTransparency = 1,
		-- No outline: this is a quiet way out, not a second call to action competing
		-- with the mash prompt directly above it.
		strokeThickness = 0,
		cornerRadius = UIKit.Radius.button,
		text = "Q  to release",
	})
	ui.releaseButton = releaseButton

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function signalColor(): Color3
	if state.rarityHint then
		local def = Rarity.DEFS[state.rarityHint]
		if def then
			return def.color
		end
	end
	return COLOR.scope
end

--- Contacts arrive as WORLD-space offsets from the player. The scope is drawn in
--- camera space so "up" is wherever the player is looking — a radar that stays
--- locked to world north forces the player to do the rotation in their head, every
--- frame, forever.
---
--- The sign convention here is the needle's, kept deliberately: an angle measured
--- from the camera's look direction maps straight onto clockwise-from-up, which is
--- what both the old Rotation property and this offset use.
local function renderBlips()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local look = camera.CFrame.LookVector
	local cameraYaw = math.atan2(look.Z, look.X)
	local radius = if state.radius > 0 then state.radius else 1

	for index = 1, MAX_BLIPS do
		local blip = blips[index]
		local contact = state.contacts[index]

		if contact == nil then
			blip.Visible = false
			continue
		end

		local distance = math.sqrt(contact.dx * contact.dx + contact.dz * contact.dz)
		local relative = math.atan2(contact.dz, contact.dx) - cameraYaw
		-- Clamped, not hidden: a contact fractionally outside the ring because the
		-- player moved between ticks should sit ON the ring, not blink out.
		local reach = math.min(distance / radius, 1) * SCOPE_RADIUS

		blip.Position = UDim2.new(0.5, math.sin(relative) * reach, 0.5, -math.cos(relative) * reach)

		local def = if contact.rarity then Rarity.DEFS[contact.rarity] else nil
		blip.BackgroundColor3 = if def then def.color else COLOR.scope

		-- The nearest contact is the one every other part of the HUD is talking
		-- about, so it is drawn bigger. Without this the scope reads as a cloud and
		-- the status line appears to be describing an arbitrary member of it.
		local lead = index == 1
		blip.Size = UDim2.fromOffset(if lead then 11 else 7, if lead then 11 else 7)
		blip.Visible = true
	end
end

local function renderFrame(dt: number)
	local colour = signalColor()

	renderBlips()

	-- One revolution per pulse period, sharing os.clock with FieldController's ground
	-- ring so the two land together without either one owning the other's timing.
	local phase = (os.clock() % Tuning.RANGE_RING_PERIOD) / Tuning.RANGE_RING_PERIOD
	ui.arm.Rotation = phase * 360
	ui.arm.BackgroundTransparency = if state.inStage then 0.6 else 0.9

	ui.ring.Color = if state.hasSignal then colour else COLOR.stroke
	ui.edgeStroke.Color = if state.hasSignal then colour else COLOR.scope

	-- Chase rather than snap. Exponential so it converges at the same visual rate
	-- whatever the framerate -- the naive `+= (target - shown) * rate * dt` overshoots
	-- and oscillates the moment dt gets large, which on a bar the player is staring at
	-- while mashing is very visible.
	shownProgress += (state.digProgress - shownProgress) * (1 - math.exp(-FILL_LERP_RATE * dt))
	local drawn = math.clamp(shownProgress, 0, 1)
	ui.digFill.Size = UDim2.fromScale(drawn, 1)
	-- Both bars read the SAME smoothed value. Two fills computing their own smoothing
	-- off one server number is how they end up visibly disagreeing by a frame.
	ui.haulFill.Size = UDim2.fromScale(drawn, 1)

	-- The kick. One ease-out swell per click, driven off the local timestamp so it
	-- starts on the same frame the player pressed the key.
	local sinceYank = os.clock() - lastYankAt
	local kick = if sinceYank < YANK_KICK_SECONDS then (1 - sinceYank / YANK_KICK_SECONDS) ^ 2 else 0
	local swell = 1 + kick * YANK_KICK_SCALE
	local base = Dock.DIGBUTTON_SIZE
	-- Scaled about the button's own anchor (bottom-centre), so it swells upward out of
	-- the instrument band rather than shoving the meters either side of it.
	ui.digButton.Size = UDim2.new(
		base.X.Scale * swell,
		base.X.Offset * swell,
		base.Y.Scale * swell,
		base.Y.Offset * swell
	)
end

local function renderState()
	-- THE PANEL IS DRIVEN OFF THE SERVER'S `locked`, NOT off anything the client
	-- decided. Every release path lives on the server (bag full, signal gone, blackout,
	-- item surfaced), so the panel closing is always downstream of the lock actually
	-- being dropped -- it can never linger over a lock the server has already let go
	-- of, and it can never hide one that is still holding the player's feet.
	ui.haul.Visible = state.locked
	if state.locked then
		local named = if state.rarityHint then string.upper(state.rarityHint) else "UNKNOWN MASS"
		ui.haulTitle.Text = `LOCKED ON \u{2014} {named}`
		ui.haulTitle.TextColor3 = signalColor()
		ui.haulStroke.Color = signalColor()
		-- An under-rated magnet still locks on and still visibly strains -- it just
		-- stalls at STRAIN_CEILING. Saying so here is the whole teaching moment, and
		-- the panel is now where the player is looking when it happens.
		local weak = state.blocked == "weak"
		ui.haulFill.BackgroundColor3 = if weak then COLOR.red else COLOR.green
		ui.haulButton.Text = if weak then "MAGNET TOO WEAK" else "MASH  E  TO HAUL"
		ui.haulButton.TextColor3 = if weak then COLOR.red else COLOR.green
	end

	if not state.inStage then
		-- BLANK, AND THE BUTTON GOES WITH IT. Out of a stage means you are in the plaza
		-- shopping, banking or racking. A status line telling you that you cannot dig
		-- on the shop floor, and a PULL button that does nothing when pressed, are
		-- both noise printed over the top of whatever panel you actually came here to
		-- use — and between them they are what stopped the station panel from being
		-- able to sit at screen centre. Every other branch below still speaks,
		-- because every other branch is about a stage you are standing in.
		--
		-- The button costs nothing to lose here: it is inert out of a stage (the
		-- server has no signal to give), and E still works, so nothing is unreachable
		-- — it reappears the moment you step onto sludge, which is also the moment it
		-- starts meaning something.
		--
		-- The SCOPE stays, unlike the button. It is the detector itself rather than a
		-- verb attached to it, it now lives out in the corner where it is not in the
		-- way of anything, and a dial that vanished every time you walked into the
		-- plaza would read as broken hardware rather than as a quiet one.
		ui.status.Text = ""
		ui.centre.Text = ""
		ui.digButton.Visible = false
		ui.digButton.Text = "TAP  E  TO LOCK ON"
		ui.digStroke.Color = COLOR.stroke
		return
	end

	ui.centre.Text = `{math.floor(state.radius + 0.5)} stud sweep`
	ui.centre.TextColor3 = COLOR.dim
	ui.digButton.Visible = true

	if not state.hasSignal then
		-- Standing in a glow that somebody else's detector put there. This is a real
		-- state, not an error: auras are public, the tier gates are not.
		if state.blocked == "unregistered" then
			ui.status.Text = "that signal is past your detector \u{2014} you cannot lock on"
			ui.status.TextColor3 = COLOR.red
			ui.digButton.Text = "CANNOT LOCK ON"
			ui.digButton.TextColor3 = COLOR.red
			ui.digStroke.Color = COLOR.red
			return
		end

		-- Detector on, nothing revealed in range. The old "sweeping… nothing in
		-- range" status line was removed on request -- the empty scope says it.
		ui.status.Text = ""
		ui.digButton.Text = "TAP  E  TO LOCK ON"
		ui.digStroke.Color = COLOR.stroke
		ui.digButton.TextColor3 = COLOR.dim
		return
	end

	local named = if state.rarityHint then ` \u{2014} nearest reads {string.lower(state.rarityHint)}` else ""

	if state.blocked == "weak" then
		-- It still moves. It just will not come free — and the player can see that.
		ui.status.Text = "it shifts, then stops \u{2014} magnet is too weak"
		ui.status.TextColor3 = COLOR.red
		ui.digButton.Text = "MAGNET TOO WEAK"
		ui.digButton.TextColor3 = COLOR.red
		ui.digStroke.Color = COLOR.red
	elseif state.blocked == "full" then
		ui.status.Text = "bag is full"
		ui.status.TextColor3 = COLOR.red
		ui.digButton.Text = "BAG FULL"
		ui.digButton.TextColor3 = COLOR.red
		ui.digStroke.Color = COLOR.red
	elseif state.inRange then
		ui.status.Text = `you are standing on it{named}`
		ui.status.TextColor3 = COLOR.green
		-- Two phases, one button: it names the NEXT thing to do. Before the lock that
		-- is committing; after it the dock button steps back, because the haul panel
		-- is where the mashing is being reported.
		ui.digButton.Text = if state.locked then "HAULING\u{2026}" else "TAP  E  TO LOCK ON"
		ui.digButton.TextColor3 = COLOR.green
		ui.digStroke.Color = COLOR.green
	else
		-- Signal(s) revealed but out of reach. The glow on the ground is the cue; a
		-- status line counting them and saying "walk to the glow" was noise on top of
		-- it (removed on request). The button still says GET CLOSER.
		ui.status.Text = ""
		ui.digButton.Text = "GET CLOSER"
		ui.digButton.TextColor3 = COLOR.dim
		ui.digStroke.Color = COLOR.stroke
	end
end

-- ── Banner ──────────────────────────────────────────────────────────

local bannerToken = 0

local function showUnearthed(found)
	local def = Rarity.DEFS[found.rarity]
	local colour = if def then def.color else COLOR.text

	local modifier = if found.modifier == "None" then "" else found.modifier .. " "
	ui.bannerRarity.Text = string.upper(modifier .. found.rarity)
	ui.bannerRarity.TextColor3 = colour
	ui.bannerName.Text = found.name
	ui.bannerFlavor.Text = found.flavor
	ui.bannerStroke.Color = colour
	ui.banner.Visible = true

	bannerToken += 1
	local token = bannerToken
	task.delay(3.5, function()
		if token == bannerToken then
			ui.banner.Visible = false
		end
	end)
end

-- ── Input ───────────────────────────────────────────────────────────

local digYank: any = nil
local digLock: any = nil

--- One click, one yank. There is deliberately NO local rate limit and no debounce
--- here: the server's token bucket is the authority on what counts, and a second
--- limiter on the client would only ever disagree with it -- quietly eating clicks
--- the server would have honoured, which reads as input lag on a verb whose whole
--- appeal is that it answers instantly.
local function sendYank()
	if not state.locked then
		return
	end

	lastYankAt = os.clock()
	digYank:FireServer()
	renderState()
end

--- Commit to whatever we are standing on. The server picks the actual signal; all this
--- says is "yes, this one". Gated on inRange so a tap in open ground is not a wasted
--- remote, but NOT on `blocked` -- an under-rated magnet is allowed to lock on and
--- discover it cannot finish, which is the lesson that sells the next magnet.
local function sendLock()
	if not state.inStage or not state.inRange or state.locked or state.blocked == "full" then
		return
	end
	digLock:FireServer(true)
end

--- Give up the haul. NEVER gated on client state: this is the only way out of a lock
--- that has rooted the character, so it fires unconditionally and lets the server
--- decide whether there was anything to release. A client-side `if` in front of this
--- is a way for a player to get stuck standing in a field.
local function sendRelease()
	digLock:FireServer(false)
end

--- E means different things either side of the commitment: the first press picks the
--- item, every press after that hauls on it.
local function pressPull()
	if state.locked then
		sendYank()
	else
		sendLock()
	end
end

-- ── Lifecycle ────────────────────────────────────────────────────────

--- Read by FieldController so the ground ring is drawn at the radius the server
--- actually resolved, rather than the client guessing from its own gear numbers —
--- perks fold into detectorRadius and only StatResolver knows the answer.
function Detector.radius(): number
	return if state.inStage then state.radius else 0
end

function Detector.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	digYank = Net.get("DigYank")
	digLock = Net.get("DigLock")

	Net.get("SweepState").OnClientEvent:Connect(function(payload)
		state.inStage = payload.inStage == true
		state.hasSignal = payload.hasSignal == true
		state.radius = payload.radius or 0
		state.contacts = payload.contacts or {}
		state.rarityHint = payload.rarityHint
		state.inRange = payload.inRange == true
		state.blocked = payload.blocked
		state.digProgress = payload.digProgress or 0
		state.locked = payload.locked == true
		-- payload.carrying / payload.capacity are deliberately ignored: the hotbar
		-- (InventoryController, fed by CarryState) is the authority on the bag now,
		-- and two widgets answering "how full am I" from two different remotes is how
		-- they end up disagreeing by a tick. payload.strength / payload.newContacts
		-- too, since the audio cues they fed are gone.
		renderState()
	end)

	Net.get("Unearthed").OnClientEvent:Connect(function(found)
		showUnearthed(found)
	end)

	-- InputBegan only, and no InputEnded partner. Roblox does not auto-repeat a held
	-- key through InputBegan, so holding E down yields exactly one yank -- which is
	-- precisely the behaviour this feature wants. Nothing has to suppress the hold;
	-- the platform already does.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			pressPull()
		elseif input.KeyCode == Enum.KeyCode.Q then
			sendRelease()
		end
	end)

	-- MouseButton1Click, not Down/Up. Click fires for touch taps too, so these three
	-- are the whole mobile input path -- and unlike the Down/Up pair they need no
	-- MouseLeave rescue, because there is no held state left to get stranded when a
	-- finger slides off a button mid-press.
	--
	-- The release button matters most of the three. A phone has no Q key, so without
	-- it a touch player could commit to a haul and have no way to stop being rooted.
	ui.digButton.MouseButton1Click:Connect(pressPull)
	ui.haulButton.MouseButton1Click:Connect(sendYank)
	ui.releaseButton.MouseButton1Click:Connect(sendRelease)

	-- Heartbeat, NOT RenderStepped. This used to matter because the ping audio ran
	-- here and could not be allowed to stall with the render loop; the ping is gone
	-- now, but the scope's sweep arm and blips are still driven off os.clock (not
	-- dt), so Heartbeat vs RenderStepped only changes how often they refresh, never
	-- what they show. Left on Heartbeat — moving it buys nothing.
	RunService.Heartbeat:Connect(function(dt)
		renderFrame(dt)
	end)

	renderState()
end

return Detector
