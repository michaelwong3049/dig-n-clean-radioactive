--!strict
--[[
	ExhibitService.lua — the second exit for an item, and the one that keeps paying.

	AN ITEM YOU SELL IS GONE. AN ITEM YOU DISPLAY KEEPS PAYING (PLAN §8). Everything
	this file needs was already sitting in the codebase waiting for a service to
	read it: the profile schema (`data.exhibit`), every tuning number
	(`Tuning.EXHIBIT_*`), the world contract (`Plots.luau`'s Stand
	attributes), and even the multiplier hook (`StatResolver.yieldMultiplier`,
	wired to the Curator perk before this file existed to use it). This is the
	service that plugs all of that together.

	PLOTS ARE ASSIGNED, NOT OWNED. Per-session only, exactly as `Plots.luau`'s own
	header promised: "a player's plot contents persist; their plot number is
	meaningless across servers." `data.exhibit.pedestals` is the persistent part;
	`plotOf` here is a runtime map that gets rebuilt every time someone joins. A
	returning player may land on a different physical plot and see their own
	collection re-rendered onto it.

	THE SLOT ARRAY MUST STAY DENSE. ProfileStore forbids gaps in numeric arrays
	(DataService's own comment), so `pedestals` is `{ {slot=1,...}, {slot=3,...} }`
	with a `slot` field on each entry, not a sparse table indexed BY slot. Undisplay
	removes the entry (`table.remove`); it never sets one to nil.

	NO INCOME CAP, ON REQUEST (balance/economy-pacing-pass). Stands pay exactly what
	their nukes earn. There used to be an hourly cap (`EXHIBIT_HOURLY_CAP_PER_LEVEL *
	level`), but `level` never rose past 1, so it pinned every player at ~$139/sec from
	Stage 3 on. The shop prices in Config/Gear, Config/Floors and Config/Treadmill are
	sized against the uncapped rate instead.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net) -- assign(): tell the owning client its plot index for the "YOUR BASE" beacon
local Bag = require(Shared.Bag)
local Tuning = require(Shared.Config.Tuning)
local Floors = require(Shared.Config.Floors)
local Gear = require(Shared.Config.Gear) -- renderLuck: the plot's luck-button billboard
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Weight = require(Shared.Config.Weight)
local Payload = require(Shared.Config.Payload)
local Merge = require(Shared.Config.Merge)
local ItemModels = require(Shared.ItemModels)
local ItemCrust = require(Shared.ItemCrust)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local StandCard = require(Shared.StandCard) -- the attribute contract StandCardController draws from
local Ticker = require(Shared.Util.Ticker)
local Tutorial = require(Shared.Config.Tutorial) -- assign(): new players join at Stage 1
local Stages = require(Shared.Config.Stages)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local AwayEarningsService = require(script.Parent.AwayEarningsService)
local IdentifyService = require(script.Parent.IdentifyService)

-- THE ONE build/ REQUIRE IN THIS FILE, and it is the same shape as DigService's
-- require of build/SignalAura: a service that has to change world geometry asks the
-- module that built that geometry to change it, rather than learning the geometry's
-- shape for itself. `PLOT_COUNT` below is deliberately NOT taken from here — a
-- constant is worth copying to avoid a dependency; a builder is not worth
-- reimplementing to avoid one.
local Plots = require(script.Parent.Parent.build.Plots)

local ExhibitService = {}

local PLOT_COUNT = 6 -- matches build/Plots.Plots.COUNT; not required so Services never depend on build/
-- Stand display motion: turn rate (radians/sec, ~1 turn per 25s) and bob height (studs).
local STAND_HOVER = { rate = 0.25, amp = 0.12 }
local LOCKER_VISIBLE =Tuning.LOCKER_SLOTS -- one per tube; a profile racked past the cap shows the first eight
local LOCKER_ITEM_SIZE = 1.2 -- longest axis a stored item model is scaled to; the imported rack's tubes are ~1.36 across
-- Config/Payload's per-dig roll applies here too, capped the same way WashService
-- caps it -- the tubes are narrow, no room for a "giga nuke" roll on top of an
-- already-normalised size.
local LOCKER_PAYLOAD_CAP = 1.05
-- THE STAND HEIGHT CAP. A displayed nuke is ~7 studs x its sizeMult x its Payload roll,
-- which left alone runs anywhere up to ~61 (the Atomic Bomb rolling GIGA: through TWO
-- floors). So every stand nuke is capped to stay under the deck overhead with
-- STAND_CEILING_ROOM to spare for its trophy card -- except a GIGA Anomaly, on request:
-- the one roll big enough to punch up THROUGH the floor above. Its top always clears
-- that deck by GIGA_PIERCE.min..max studs (low end of the GIGA band to the top), never
-- more, so it never reaches a second floor. Floor 3 measures against where a 4th deck
-- would be, so the rule reads the same on the roof.
local STAND_CEILING_ROOM = 6 -- the deck's own 1.2 thickness plus the card
local GIGA_PIERCE = { min = 3, max = 8 }
-- The pool a crusted ??? sits in: the crust's own brown, since its rarity is all the
-- rack is allowed to say and the brown says "not washed yet" first.
local LOCKER_CRUST_GLOW = Color3.fromHex("8A6440")
local LOCKER_EMPTY_GLOW = Color3.fromHex("4A5560")
-- The reach of the station ensureLockerStation stands in front of an old cabinet.
local STALE_LOCKER_RADIUS = 4.5
-- Matches build/Kit.FLOOR_TAG: the sign that sells a base's next floor. A string,
-- not a require, for the same reason PLOT_COUNT is.
local FLOOR_TAG = "BuyFloor"
-- How long a refused floor purchase stays written on the sign before it goes back.
local SIGN_FLASH_SECONDS = 2.5

-- Who is sitting on which physical plot this session. Never persisted — see header.
local plotOf: { [Player]: number } = {}
local plotOwner: { [number]: Player? } = {}

local resultRemote: any = nil
local noticeRemote: any = nil
local colorRemote: any = nil
local incomeRemote: any = nil

-- Last os.clock() each player set their base colour, so a client cannot spam the
-- PlotColor remote into a repaint loop. Cleared on release.
local lastColorSet: { [Player]: number } = {}

--- The colour this player's plot wears while they have not picked one
--- (Plots.DEFAULT_ACCENTS, by plot index) — sent alongside every PlotColor echo so the
--- Settings swatch shows what the base actually wears. "" if they hold no plot.
local function defaultAccentHex(player: Player): string
	local index = plotOf[player]
	return if index then Plots.DEFAULT_ACCENTS[index] or "" else ""
end

-- ── Rendering ─────────────────────────────────────────────────────────────────
-- The only place this file touches Workspace directly. Kept small and separate so
-- the rest of the service can be reasoned about as pure data manipulation.

local function plotModel(index: number): Model?
	local row = Workspace:FindFirstChild("Plots")
	if row == nil then
		return nil
	end
	return row:FindFirstChild(`Plot{index}`) :: Model?
end

-- How far away the plate stays drawn (camera-to-plate, studs). Mirrors
-- build/Plots.buildNamePlate's own value; stamped here too so an already-built
-- place picks a change up on the next claim without a Plots rebuild.
local NAMEPLATE_REACH = 400

--- Repaint one plot's avatar plate (build/Plots.buildNamePlate) with the owner's
--- headshot and display name AS THEY CAPITALISED it (no `string.upper` — a name
--- like "MattM" stays "MattM"). `owner == nil` clears it back to a blank face and
--- the literal "UNCLAIMED", the same placeholder a freshly built plot wears.
local function renderName(index: number, owner: Player?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local plate = plot:FindFirstChild("NamePlate", true)
	local gui = plate and plate:FindFirstChildWhichIsA("BillboardGui")
	local face = gui and gui:FindFirstChild("Face")
	local caption = gui and gui:FindFirstChild("Caption")
	if gui and gui:IsA("BillboardGui") then
		gui.MaxDistance = NAMEPLATE_REACH
	end
	if face and face:IsA("ImageLabel") then
		face.Image = if owner then `rbxthumb://type=AvatarHeadShot&id={owner.UserId}&w=150&h=150` else ""
	end
	if caption and caption:IsA("TextLabel") then
		caption.Text = if owner and owner.DisplayName ~= "" then owner.DisplayName else "UNCLAIMED"
	end
	-- The entrance arch's sign (build/Plots.buildEntranceArch): the same name in the
	-- same casing, at eye level. An empty base's sign is left blank, not "UNCLAIMED".
	local archName = plot:FindFirstChild("OwnerName", true)
	if archName and archName:IsA("TextLabel") then
		archName.Text = if owner and owner.DisplayName ~= "" then `{owner.DisplayName}'s Base` else ""
	end
end

--- Repaint one plot's accent pieces — the side Trim, the nameplate frame, the
--- cleansing-station lamp, the two station-sign subtitles and the gallery's arch,
--- plinth bands, fence caps and slot brackets — from the owner's chosen colour
--- (`data.plotColor`, an "RRGGBB" hex). A claimed plot whose owner has never picked
--- (an empty string) wears that plot's Plots.DEFAULT_ACCENTS hue instead — chosen
--- here at paint time, never written to the profile. `data == nil` (unclaimed) or a
--- malformed hex fall through to nil, and Plots.setPlotAccent then paints the neutral
--- grey a freshly built plot wears. `Color3.fromHex` throws on bad input, hence the
--- pcall — the format is checked on the way in (setPlotColor) but a save could still
--- carry something odd.
local function renderAccent(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local color: Color3? = nil
	local hex = data and data.plotColor
	if data ~= nil and (type(hex) ~= "string" or hex == "") then
		hex = Plots.DEFAULT_ACCENTS[index]
	end
	if type(hex) == "string" and hex ~= "" then
		local ok, parsed = pcall(Color3.fromHex, hex)
		if ok then
			color = parsed
		end
	end
	Plots.setPlotAccent(plot, color)
end

--- Repaint one plot's luck button to the given profile's current multiplier and the
--- price of the NEXT purchase, or to the starting values when `data` is nil (an
--- unclaimed plot). The Sign/Title/Subtitle names match build/Plots.buildLuckButton
--- exactly, the same convention renderBottle uses to name the fluid on the bottle.
--- Title carries the multiplier, Subtitle the price — Luck has no tier
--- name left to put in Title's place now that a purchase is a flat +Gear.LUCK_STEP.
local function renderLuck(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local luckButton = plot:FindFirstChild("LuckButton", true)
	local button = luckButton and luckButton:FindFirstChild("Button")
	local sign = button and button:FindFirstChild("Sign")
	local title = sign and sign:FindFirstChild("Title")
	local subtitle = sign and sign:FindFirstChild("Subtitle")
	local level = if data then (data.gear.luck or 1) else 1
	if title then
		(title :: TextLabel).Text = string.format("LUCK %gx", Gear.luckMultiplier(level))
	end
	if subtitle then
		(subtitle :: TextLabel).Text = string.format("+%gx for $%d", Gear.LUCK_STEP, Gear.luckPrice(level))
	end
end

--- Put the Cleaner rung this profile owns on the plot's wash machine, or the
--- unclaimed-plot default when `data` is nil.
---
--- THIS IS THE WHOLE POINT OF THE CLEANER TRACK BEING A MACHINE. You buy a hose at the
--- plaza's HOSES stall like every other track, and this is what makes that purchase
--- something you can walk up to and look at: the monitor on your own mast is the rung
--- you paid for, and it changes the moment the money leaves (ShopService calls
--- refreshHose) rather than at the next rebuild.
---
--- SAME SHAPE AS renderLuck, and for the same reason it lives here rather than in
--- ShopService: this file owns what a plot LOOKS like for its owner, and the buy path
--- should not have to know that a plot has a cleansing station in it, let alone that
--- the station has a mast.
local function renderHose(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	-- Recursive: the station is a Model inside the plot, and its own name is the only
	-- thing this file knows about it. Everything past that name — where the mast is,
	-- which Beam runs to which attachment — is build/Plots' business.
	local station = plot:FindFirstChild("CleansingStation", true)
	Plots.setHoseTier(station, if data then data.gear.cleaner else nil)
end

--- Dress the plot's treadmill in the belt rung this profile owns, or the free
--- starting belt when `data` is nil (an unclaimed plot).
---
--- SAME SHAPE AS renderHose, and it is the same argument: TreadmillService takes the
--- money, this file owns what a plot looks like, and the buy path should not have to
--- know a plot has a treadmill in it. What "dressing" means — which parts repaint,
--- what the sign says — is entirely build/Plots.setTreadmillTier's business.
local function renderTreadmill(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local treadmill = plot:FindFirstChild("Treadmill", true)
	Plots.setTreadmillTier(
		treadmill,
		if data then data.treadmill else nil,
		if data then data.speedPoints else nil,
		data == nil or data.treadmillUnlocked ~= true
	)
end

--- Fill the plot's fluid bottle AND its cleansing tub with the fluid this profile has
--- loaded, or Plain Water when `data` is nil (an unclaimed plot). Colour only: the
--- fluid's name, washes left and the ROLL button live on the owner's own panel (the
--- client's LiquidController).
---
--- SAME SHAPE AS renderTreadmill: LiquidService spins, this file owns what a plot
--- looks like, and which parts of the bottle and the tub hold the fluid is
--- build/Plots' business (Plots.setFluidBottle, Plots.setTubFluid).
local function renderBottle(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local liquidId = if data then StatResolver.get(data).liquidId else nil
	Plots.setFluidBottle(plot:FindFirstChild("FluidBottle", true), liquidId)
	Plots.setTubFluid(plot:FindFirstChild("CleansingStation", true), liquidId)
end

--- The world half of "hold the item, hold E on the stand": a plain default-styled
--- ProximityPrompt (small white ActionText, same as the wash tub's own "Wash"
--- prompt — see WashService/build/Plots' `buildCleansingStation`), built once per
--- stand and reused after that, same lazy-once shape `setStandCard` uses below
--- for the card's tag.
---
--- ONE PROMPT PER STAND, NOT TWO. An earlier version ran separate "Place" and
--- "Take" prompts so a swap (something already there, and you are holding a
--- replacement) could offer both at once — confirmed live that TWO ProximityPrompts
--- enabled on the SAME part, even with different KeyboardKeyCodes, are unreliable
--- for a real player (they visibly overlap, and which one an actual keypress/click
--- reaches is inconsistent) even though driving them directly via
--- InputHoldBegin/InputHoldEnd in isolation looked fine. One prompt whose verb
--- flips with the stand's occupied state (a fact every viewer agrees on) sidesteps
--- the whole problem.
---
--- WHICH STAND THIS IS is captured in the closure at build time (`plot`, `slot`),
--- not re-derived from the player's facing or position when pressed. That used to
--- be necessary because nothing in the world was tied to a specific stand; now
--- that the prompt itself IS the specific stand — Roblox already decided which one
--- you reached by which prompt it let you trigger — re-deriving it a second way
--- could only ever introduce a disagreement, never resolve one. This is also why
--- `StationService.facedStation` and the old two-function `display`/`undisplay`
--- split are gone: `ExhibitService.interact` below is the only entry point.
local function ensurePrompt(stand: BasePart, plot: number, slot: number): ProximityPrompt
	local existing = stand:FindFirstChild("Interact")
	if existing and existing:IsA("ProximityPrompt") then
		return existing
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Interact"
	prompt.ObjectText = ""
	prompt.HoldDuration = Tuning.EXHIBIT_STAND_HOLD_SECONDS
	prompt.MaxActivationDistance = (stand:GetAttribute("Radius") :: number?) or 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = stand

	prompt.Triggered:Connect(function(player: Player)
		local ok, message = ExhibitService.interact(player, plot, slot)
		if resultRemote then
			resultRemote:FireClient(player, message)
		end
		-- A stand has no panel, so the StationResult toast above lands in a hidden
		-- widget. A refusal also goes to the hotbar popup, where it is actually seen.
		if not ok and noticeRemote then
			noticeRemote:FireClient(player, message)
		end
		if ok then
			print(`[exhibit] {player.Name}: {message}`)
		end
	end)

	return prompt
end

--- Repaint one stand with real item art when it exists, or the old rarity-coloured
--- block while that catalogue entry is still waiting for a model. `uid` is the
--- specific dig on display, so its own Config/Payload roll can size the model --
--- nil (clearing a stand) just skips that.
local function renderStand(index: number, slot: number, itemId: string?, rarity: string?, uid: string?, modifier: string?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end

	-- ActionText is the one thing safe to flip here: occupied is the same fact for
	-- every viewer, unlike ownership (which the prompt does not attempt to gate —
	-- a non-owner who presses it gets refused by `interact` itself, same as
	-- pressing Wash on someone else's tub costs nothing to attempt and fails
	-- cleanly) and unlike "are you holding something" (per-player, which is why a
	-- swap has to be decided inside `interact`, never by the prompt's own label).
	local stand = plot:FindFirstChild(`Stand{slot}`, true) :: BasePart?
	if stand then
		local prompt = ensurePrompt(stand, index, slot)
		prompt.ActionText = if itemId == nil then "Place" else "Take"
		-- The per-player half of the label: InventoryController reads these and says
		-- "Swap" on an occupied stand while YOU are holding a nuke. `interact` still
		-- decides; the label only tells the truth about what it will do.
		prompt:SetAttribute("ExhibitStand", true)
		prompt:SetAttribute("Occupied", itemId ~= nil)
	end

	-- The gallery's empty/full look (build/Plots.setStandState): slot brackets while
	-- empty, a line in the displayed item's rarity colour while full.
	Plots.setStandState(plot, slot, if rarity then Rarity.get(rarity).color else nil)

	local display = plot:FindFirstChild(`Display{slot}`, true) :: BasePart?
	if display == nil then
		return
	end

	local previous = display:FindFirstChild("ItemModel")
	if previous then
		previous:Destroy()
	end

	local model: Model? = nil
	if itemId then
		local item = Items.get(itemId)
		model = ItemModels.create(item.model, itemId, modifier)
	end

	if model then
		display.Transparency = 1
		model.Name = "ItemModel"
		model:SetAttribute("ItemId", itemId)
		model.Parent = display

		-- Config/Payload's per-dig roll, full range -- this is an open plinth, not a
		-- fixed-footprint aiming surface (unlike WashService's capped version). The
		-- only ceiling is the deck overhead -- the height cap just below.
		-- Plus the item's own Config/Items `sizeMult` (the Atomic Bomb's is huge).
		local sizeMult = Items.get(itemId :: string).sizeMult or 1
		local mult = sizeMult * (if uid then Payload.forUid(uid) else 1)
		if mult ~= 1 then
			model:ScaleTo(model:GetScale() * mult)
		end

		-- -0.72 used to be a hand-tuned constant that happened to seat the old
		-- horizontal nuke's belly on the plinth; it has no relation to an upright
		-- model's height, so this now seats whatever bounding box actually comes
		-- back, the same way renderLocker already does below.
		model:PivotTo(display.CFrame * ItemModels.rotation(model, "Display"))
		local bounds, extent = model:GetBoundingBox()
		local floorY = display.Position.Y - display.Size.Y / 2

		-- The height cap (STAND_CEILING_ROOM / GIGA_PIERCE above), against the deck
		-- one storey up from the deck this stand is on.
		local room = display.Position.Y - Plots.DISPLAY_LIFT + Floors.HEIGHT - floorY
		local roll = if uid then Payload.forUid(uid) else 1
		local height = math.min(extent.Y, room - STAND_CEILING_ROOM)
		if Items.get(itemId :: string).rarity == "Anomaly" and Payload.calloutFor(roll) == "GIGA" then
			local t = math.clamp((roll - Payload.CALLOUTS[1].min) / (Payload.MAX - Payload.CALLOUTS[1].min), 0, 1)
			height = room + GIGA_PIERCE.min + (GIGA_PIERCE.max - GIGA_PIERCE.min) * t
		end
		if math.abs(height - extent.Y) > 0.01 and extent.Y > 0 then
			model:ScaleTo(model:GetScale() * height / extent.Y)
			model:PivotTo(display.CFrame * ItemModels.rotation(model, "Display"))
			bounds, extent = model:GetBoundingBox()
		end
		model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - (bounds.Position.Y - extent.Y / 2) + 0.03, 0))
		-- Where the card hangs from: the model's own top, so a GIGA roll lifts its
		-- card with it instead of swallowing a card pinned at a fixed height.
		display:SetAttribute(StandCard.ATTR.top, floorY + 0.03 + extent.Y - display.Position.Y)
		-- A slow turn and a faint bob, animated client-side by StationMotionController
		-- from this seated pose. Lifted by the bob's amplitude so the low point still
		-- clears the plinth.
		model:PivotTo(model:GetPivot() + Vector3.new(0, STAND_HOVER.amp, 0))
		model:SetAttribute("Motion", "hover")
		model:SetAttribute("MotionRate", STAND_HOVER.rate)
		model:SetAttribute("MotionAmp", STAND_HOVER.amp)
		CollectionService:AddTag(model, "StationMotion")
	elseif rarity then
		display.Color = Rarity.get(rarity).color
		display.Transparency = 0
		display:SetAttribute(StandCard.ATTR.top, display.Size.Y / 2)
	else
		display.Transparency = 1
		display:SetAttribute(StandCard.ATTR.top, nil)
	end
end

-- ── The trophy-ribbon card over a displayed item ──────────────────────────────
-- Every occupied stand carries a card: rarity, tier stars, the name on a ribbon, what
-- the piece pays per second, what it weighs, and any modifier / size roll / duplicate
-- damping. The CLIENT draws it (StandCardController); this file only publishes the
-- facts onto the stand's Display part -- Shared/StandCard says why, and names every
-- attribute. It is all per-player content (the item, its roll modifier, the owner's
-- Curator perk, and how many copies share the plot all move the number), which is why
-- it is written at runtime rather than built into the plot geometry.

--- One displayed item's contribution to the plot's per-second yield. `damping` comes
--- from the caller because it depends on how many EARLIER pedestals share the item id
--- (Tuning.EXHIBIT_DUPLICATE_YIELD). Per-minute in the design doc, per-second here
--- like everything else in this codebase. Shared by rawRatePerSecond (which sums it,
--- then the hourly cap clamps the total) and refreshStandCards (which publishes it for
--- the plinth's card), so a card can never disagree with what the piece pays in.
local function entryYieldPerSecond(entry: any, damping: number, stats: any): number
	local def = Items.get(entry.itemId)
	local rarity = Rarity.get(entry.rarity)
	-- Weight.valueMult and Payload.forUid layer in here exactly as they do in
	-- EconomyService.valueOf, so a heavy/big-rolled piece pays more per second AND
	-- sells for more, off the same two factors.
	return def.baseValue
		* Rarity.valueMult(entry.modifier, entry.bonus)
		* Weight.valueMult(def.weight)
		* Payload.forUid(entry.uid)
		* Merge.valueMult(Merge.levelOf(entry))
		* rarity.displayYield
		* damping
		* stats.yieldMultiplier
		/ 60
end

type StandCardInfo = {
	itemId: string,
	rarity: string,
	modifier: string,
	bonus: { string }?,
	merge: number,
	rate: number,
	copy: number,
	payload: number,
	placedAt: number,
	owner: number,
}

--- Publish one stand's card, or clear it (`card == nil`: an empty stand, or a released
--- plot). Shared/StandCard names every attribute and says why this is all the server
--- does; the tag goes on here, lazily, so a plot rebuilt in Studio still gets it.
local function setStandCard(display: BasePart, card: StandCardInfo?)
	if not CollectionService:HasTag(display, StandCard.TAG) then
		CollectionService:AddTag(display, StandCard.TAG)
	end

	local A = StandCard.ATTR
	display:SetAttribute(A.item, if card then card.itemId else "")
	display:SetAttribute(A.rarity, if card then card.rarity else nil)
	display:SetAttribute(A.modifier, if card then card.modifier else nil)
	display:SetAttribute(A.bonus, if card then Rarity.bonusText(card.bonus) else nil)
	display:SetAttribute(A.merge, if card and card.merge > 0 then card.merge else nil)
	display:SetAttribute(A.rate, if card then card.rate else nil)
	display:SetAttribute(A.copy, if card then card.copy else nil)
	display:SetAttribute(A.payload, if card then card.payload else nil)
	display:SetAttribute(A.placedAt, if card then card.placedAt else nil)
	display:SetAttribute(A.owner, if card then card.owner else nil)
end

--- Republish every stand's card on one plot from the profile: clear them all, then
--- fill the occupied ones -- the same shape as renderAll. It walks `pedestals` in the
--- same order rawRatePerSecond does, so the damping baked into each card matches the
--- damping that entry is actually paid at (a wall of one repeated Legendary visibly
--- shows its 4th copy paying almost nothing). `data == nil` clears all of them.
---
--- Clearing and refilling in one go never flickers on the client: every write here
--- lands in the same replication frame, and the controller redraws once per frame.
local function refreshStandCards(index: number, data: any?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end

	for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
		local display = plot:FindFirstChild(`Display{slot}`, true) :: BasePart?
		if display then
			setStandCard(display, nil)
		end
	end
	if data == nil then
		return
	end

	local owner = plotOwner[index]
	local stats = StatResolver.get(data)
	local seen: { [string]: number } = {}
	for _, entry in data.exhibit.pedestals do
		local copyIndex = (seen[entry.itemId] or 0) + 1
		seen[entry.itemId] = copyIndex
		local damping = Tuning.EXHIBIT_DUPLICATE_YIELD[math.min(copyIndex, #Tuning.EXHIBIT_DUPLICATE_YIELD)]

		local display = plot:FindFirstChild(`Display{entry.slot}`, true) :: BasePart?
		if display then
			setStandCard(display, {
				itemId = entry.itemId,
				rarity = entry.rarity,
				modifier = entry.modifier or "None",
				bonus = entry.bonus,
				merge = Merge.levelOf(entry),
				rate = entryYieldPerSecond(entry, damping, stats),
				copy = copyIndex,
				payload = Payload.forUid(entry.uid),
				placedAt = entry.placedAt or 0,
				owner = if owner then owner.UserId else 0,
			})
		end
	end
end

--- Give a plot's locker its station part and "OpenLocker" prompt if it has none, and
--- wire that prompt's refusal once. A world rebuilt since the tube rack landed already
--- has both (build/Plots.buildQuarantineLocker); an older world still stands the old
--- cabinet, and gets the same invisible station in front of it, so the panel opens on
--- a stale world instead of the locker going dead again. The prompt's only server-side
--- job is telling a visitor it isn't theirs -- the owner's E opens the panel
--- client-side (StationController).
local function ensureLockerStation(index: number)
	local plot = plotModel(index)
	local locker = if plot then plot:FindFirstChild("QuarantineLocker", true) else nil
	if locker == nil or not locker:IsA("Model") then
		return
	end
	local station = locker:FindFirstChild("LockerStation")
	if station == nil then
		-- The old cabinet faced -Z in its Sign's frame; stand the station off that
		-- front, down on the cabinet's floor.
		local box, size = locker:GetBoundingBox()
		local sign = locker:FindFirstChild("Sign")
		local rotation = if sign and sign:IsA("BasePart") then sign.CFrame.Rotation else box.Rotation
		local face = CFrame.new(box.X, box.Y - size.Y / 2, box.Z) * rotation
		station = Plots.lockerStation(locker, face, index)
		-- The old cabinet stands ~2 studs nearer the tub than the rack does; a shorter
		-- reach keeps the stand-in clear of the Basin's (World.verify's gap rule).
		local stale = station :: BasePart
		stale:SetAttribute("Radius", STALE_LOCKER_RADIUS)
		local stalePrompt = stale:FindFirstChild("OpenLocker") :: ProximityPrompt?
		if stalePrompt then
			stalePrompt.MaxActivationDistance = STALE_LOCKER_RADIUS - 0.5
		end
	end
	local prompt = (station :: Instance):FindFirstChild("OpenLocker")
	if prompt and prompt:IsA("ProximityPrompt") and not prompt:GetAttribute("Wired") then
		prompt:SetAttribute("Wired", true)
		prompt.Triggered:Connect(function(player: Player)
			if plotOf[player] ~= index and noticeRemote then
				noticeRemote:FireClient(player, "that isn't your locker")
			end
		end)
	end
end

--- The model a stored entry shows in its tube: the nuke itself once washed, the slag
--- lump it came up in while it is still ???. The lump matters: the old cabinet drew
--- the real model for a crusted find, which named it before the hose had.
local function lockerModel(entry: any): Model?
	if Contamination.isClean(entry.patches or {}) then
		return ItemModels.create(Items.get(entry.itemId).model, entry.itemId, entry.modifier)
	end
	return ItemCrust.lump(entry.rarity, entry.uid)
end

--- Fill one plot's Quarantine Locker (build/Plots.buildQuarantineLocker) from
--- `data.locker`: a model in each filled tube, its pool tinted and lit. `data == nil`
--- clears it -- used on release.
---
--- Also still swings an old cabinet's LockerDoor when the world predates the rack, so
--- an un-rebuilt place keeps looking the way it did.
local function renderLocker(index: number, data: any)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	ensureLockerStation(index)

	local locker = if data ~= nil then data.locker else {}

	local door = plot:FindFirstChild("LockerDoor", true) :: Model?
	if door then
		local pivot = door:GetAttribute(if #locker > 0 then "OpenPivot" else "ClosedPivot")
		if typeof(pivot) == "CFrame" then
			door:PivotTo(pivot)
		end
	end

	for i = 1, LOCKER_VISIBLE do
		local entry = locker[i]

		local glow = plot:FindFirstChild(`LockerGlow{i}`, true) :: BasePart?
		if glow then
			local tint: Color3? = if entry == nil
				then nil
				elseif Contamination.isClean(entry.patches or {}) then Rarity.get(entry.rarity).color
				else LOCKER_CRUST_GLOW
			glow.Color = tint or LOCKER_EMPTY_GLOW
			local lamp = glow:FindFirstChild("GlowLight") :: PointLight?
			if lamp then
				lamp.Enabled = tint ~= nil
				lamp.Color = tint or lamp.Color
			end
		end

		local anchor = plot:FindFirstChild(`LockerSlot{i}`, true) :: BasePart?
		if anchor then
			local previous = anchor:FindFirstChild("ItemModel")
			if previous then
				previous:Destroy()
			end

			if entry == nil then
				anchor.Transparency = 1
			else
				local model = lockerModel(entry)
				if model then
					anchor.Transparency = 1
					model.Name = "ItemModel"
					-- Only a washed find's id: a crust lump carrying its real id would
					-- name it to anything that reads attributes.
					if Contamination.isClean(entry.patches or {}) then
						model:SetAttribute("ItemId", entry.itemId)
					end
					model.Parent = anchor

					-- Every model normalised to one longest-axis size (unlike the
					-- pedestals, which show items life-ish size on an open plinth) and
					-- seated on the tube's floor. `GetScale()` multiplier: see
					-- WashService.placeOnStand's identical fix -- a model already
					-- pre-scaled (every imported-mesh template) would otherwise get
					-- LOCKER_ITEM_SIZE divided by its prior scale a second time.
					model:PivotTo(CFrame.identity)
					local extents = model:GetExtentsSize()
					local longest = math.max(extents.X, extents.Y, extents.Z)
					if longest > 0 then
						local payload = math.min(Payload.forUid(entry.uid), LOCKER_PAYLOAD_CAP)
						model:ScaleTo(model:GetScale() * (LOCKER_ITEM_SIZE * payload / longest))
					end
					model:PivotTo(anchor.CFrame * ItemModels.rotation(model, "Display"))
					local bounds, size = model:GetBoundingBox()
					local floorY = anchor.Position.Y - anchor.Size.Y / 2
					model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - (bounds.Position.Y - size.Y / 2) + 0.03, 0))
				else
					anchor.Color = Rarity.get(entry.rarity).color
					anchor.Transparency = 0
				end
			end
		end
	end
end

--- Show the floors this profile has built on its plot and hide the rest, or strip an
--- unclaimed plot back to its ground floor (`data == nil`) — which also takes every
--- floor sign away, since there is nobody there to buy one. Which parts that moves is
--- build/Plots.setFloors' business.
---
--- CALL IT BEFORE ANYTHING THAT PAINTS THE PLOT. A hidden floor is out of Workspace,
--- so renderAccent and renderStand cannot reach it; renderAll brings the floors back
--- first so the accent and the stands on them are painted for THIS owner.
local function renderFloors(index: number, data: any?)
	Plots.setFloors(plotModel(index), if data then data.exhibit.floors else 1, data ~= nil)
end

--- Redraw everything on a plot from the profile — called once on assignment so a
--- returning player's collection shows up on whichever physical plot they land on,
--- and again after a floor is built, so the new floor's stands wake up.
local function renderAll(index: number, data: any)
	local owner = plotOwner[index]
	renderFloors(index, data)
	renderName(index, owner)
	renderAccent(index, data)
	renderLuck(index, data)
	for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
		renderStand(index, slot, nil, nil)
	end
	for _, entry in data.exhibit.pedestals do
		renderStand(index, entry.slot, entry.itemId, entry.rarity, entry.uid, entry.modifier)
	end
	renderLocker(index, data)
	renderHose(index, data)
	renderTreadmill(index, data)
	renderBottle(index, data)
	refreshStandCards(index, data)
end

-- ── Spawning ──────────────────────────────────────────────────────────────────
--
-- BaseCamp no longer carries a spawn of its own (see BaseCamp.luau) — every
-- player's character has to land on their own assigned PlotSpawn instead, and
-- setting player.RespawnLocation alone is not enough for that: it only takes
-- effect on the player's NEXT respawn, and by the time assign() runs (after
-- DataService's async load) the player's character has usually already spawned
-- once, at Roblox's undefined "no enabled SpawnLocation yet" fallback position.
-- This moves that already-existing character over explicitly, the one time it
-- matters — every respawn after this one is already correctly routed by
-- RespawnLocation on its own.

--- Move `player`'s current character onto `spawn`, waiting for the character to
--- exist first if this somehow runs before it does (should not happen in
--- practice — CharacterAutoLoads fires immediately on join, well before a
--- profile finishes loading — but a spawn point silently doing nothing is a
--- much worse failure than a few seconds of extra caution here).
local function teleportTo(player: Player, landing: CFrame)
	local character = player.Character
	if character == nil then
		local connection
		connection = player.CharacterAdded:Connect(function(newCharacter)
			connection:Disconnect()
			local root = newCharacter:WaitForChild("HumanoidRootPart", 5) :: BasePart?
			if root then
				root.CFrame = landing
			end
		end)
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.CFrame = landing
	end
end

local function teleportToSpawn(player: Player, spawn: SpawnLocation)
	teleportTo(player, spawn.CFrame + Vector3.new(0, 4, 0))
end

--- A brand-new player's join spot (Tutorial.spawnsAtField): just west of Stage 1's
--- west edge, halfway along it, facing east into the field. That strip is open plaza
--- tile, so the same +4 drop-in as a plot spawn lands them on the floor.
local function fieldSpawnCFrame(): CFrame
	local minX, minZ, _, maxZ = Stages.bounds(1)
	local at = Vector3.new(minX - Tutorial.FIELD_SPAWN_BACK, Stages.SURFACE_Y + 4, (minZ + maxZ) / 2)
	return CFrame.lookAt(at, at + Vector3.xAxis)
end

-- ── Plot assignment ──────────────────────────────────────────────────────────

function ExhibitService.plotOf(player: Player): number?
	return plotOf[player]
end

--- Which plot a world part is built into (Workspace.Plots.Plot<n>), or nil for anything
--- off the plot ring — the camps' public cleansing stations, shop counters, the trader.
function ExhibitService.plotIndexOf(part: Instance): number?
	local row = Workspace:FindFirstChild("Plots")
	if row == nil or not part:IsDescendantOf(row) then
		return nil
	end
	local node: Instance? = part
	while node and node.Parent ~= row do
		node = node.Parent
	end
	return if node then tonumber(string.match(node.Name, "^Plot(%d+)$")) else nil
end

--- May this player use a station that sits on plot `index`? A base's cleansing station
--- and treadmill are its OWNER's alone (on request — they used to be open to anyone);
--- `nil` means the station is not on a plot at all, which everyone may use.
function ExhibitService.ownsPlotStation(player: Player, index: number?): boolean
	return index == nil or plotOf[player] == index
end

--- Repaint a player's own luck button to their current multiplier. Called by
--- ShopService right after a Luck purchase lands, since the button's billboard is
--- world state ExhibitService already owns (the same object `assign` repaints for a
--- brand-new owner) rather than something ShopService should learn to poke into.
function ExhibitService.refreshLuck(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	renderLuck(index, DataService.data(player))
end

--- Swap this player's own wash machine to the Cleaner rung they now own. Called by
--- ShopService the moment a purchase on that track lands, for exactly the reason
--- refreshLuck exists: the world state a purchase changes belongs to the service that
--- owns plot rendering, not to the one that took the money. No-op if they have no plot
--- this session (all six taken — see assign()'s trailing warn).
function ExhibitService.refreshHose(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	renderHose(index, DataService.data(player))
end

--- Re-dress this player's own treadmill: after an upgrade lands (TreadmillService
--- .buy) and once on data load. Exactly refreshHose's contract, including the no-op
--- when they have no plot this session — which is a state a treadmill owner really can
--- be in, since a belt on somebody else's base trains them just as well (see
--- TreadmillService's header).
---
--- Also the readout's refresh path: the sign shows banked progress, so a player who
--- crosses a point of speed while standing on their own belt wants the world to say so
--- without waiting for a rebuild. TreadmillService does not call this per tick — the
--- sign is repainted on the events that change the RUNG, and the live bar is the
--- client's SpeedState readout.
function ExhibitService.refreshTreadmill(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	renderTreadmill(index, DataService.data(player))
end

--- Repaint this player's own stand cards' $/s. Called when something outside this
--- service raises their yieldMultiplier for good (the group chest's permanent cash
--- bonus); income itself needs nothing, tickPlayer resolves stats fresh.
function ExhibitService.refreshStandCards(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	refreshStandCards(index, DataService.data(player))
end

--- Refill this player's own fluid bottle from their profile. Called by LiquidService
--- when their loaded fluid or its charges change, and once a spin has landed on their
--- screen. Exactly refreshTreadmill's contract, including the no-op without a plot.
function ExhibitService.refreshBottle(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	renderBottle(index, DataService.data(player))
end

--- This player's assigned plot's spawn pad, or nil if they never got a plot this
--- session (all six taken — see assign()'s trailing warn). assign() and release()
--- already resolve this exact part this exact way; the top-of-screen warp bar's
--- "BASE" button (WarpService) is the fourth reader, so the lookup lives here in the
--- service that owns plot assignment rather than being reached for by string path
--- from outside.
function ExhibitService.plotSpawn(player: Player): SpawnLocation?
	local index = plotOf[player]
	if index == nil then
		return nil
	end
	local plot = plotModel(index)
	if plot == nil then
		return nil
	end
	return plot:FindFirstChild("PlotSpawn", true) :: SpawnLocation?
end

--- Re-mirror `data.locker` onto this player's plot rack. Called by DeconService after a
--- store, a take or a sale, the only things that move an item in or out of the locker.
--- No-op if the player has no plot this session.
function ExhibitService.refreshLocker(player: Player)
	local index = plotOf[player]
	local data = DataService.data(player)
	if index ~= nil and data ~= nil then
		renderLocker(index, data)
	end
end

--- Set this player's chosen base accent colour and repaint their plot. `hex` is a
--- bare "RRGGBB" (a leading "#" is tolerated) or "" to go back to the plot's default
--- hue (Plots.DEFAULT_ACCENTS, see renderAccent).
--- The Settings GUI's picker is a full RGB wheel by design, so this validates FORMAT
--- ONLY — there is no palette to check against and no saturation/brightness floor.
--- The colour lives on the profile and renderAccent re-applies it on the next
--- assignment, so it follows the player onto whatever plot they land on.
---
--- Same "a purchase/choice changes world state ExhibitService owns" shape as
--- refreshLuck / refreshHose: the client's remote handler (start) calls this, the
--- validation and the repaint both live here.
function ExhibitService.setPlotColor(player: Player, hex: string?): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	-- Blunt a client spamming the remote — a cosmetic write never needs to run more
	-- than several times a second, and each one walks the plot's descendants. Short
	-- enough that two deliberate drag-releases in a row both land.
	local now = os.clock()
	local previous = lastColorSet[player]
	if previous ~= nil and now - previous < 0.12 then
		return false, "slow down"
	end
	lastColorSet[player] = now

	local clean: string
	if hex == nil or hex == "" then
		clean = ""
	else
		local matched = if type(hex) == "string" then string.match(hex, "^#?(%x%x%x%x%x%x)$") else nil
		if matched == nil then
			return false, "that isn't a colour"
		end
		clean = string.lower(matched)
	end

	data.plotColor = clean

	local index = plotOf[player]
	if index ~= nil then
		renderAccent(index, data)
		-- BaseMarkerController reads Trim.Color when it builds the "YOUR BASE" beacon;
		-- PlotState is the signal that (re)builds it, so re-fire it so the ring follows.
		Net.get("PlotState"):FireClient(player, index)
	end

	return true, if clean == "" then "base colour reset" else "base colour updated"
end

local function assign(player: Player)
	for index = 1, PLOT_COUNT do
		if plotOwner[index] == nil then
			plotOwner[index] = player
			plotOf[player] = index

			local data = DataService.data(player)
			-- The plot is still theirs and still their RespawnLocation either way; a
			-- first-timer just starts at Stage 1 for the walkthrough's first step.
			local startsAtField = data ~= nil and Tutorial.spawnsAtField(data)

			local plot = plotModel(index)
			if plot then
				local spawn = plot:FindFirstChild("PlotSpawn", true) :: SpawnLocation?
				if spawn then
					spawn.Enabled = true
					player.RespawnLocation = spawn
					if not startsAtField then
						teleportToSpawn(player, spawn)
					end
				end
			end
			if startsAtField then
				teleportTo(player, fieldSpawnCFrame())
			end

			if data then
				renderAll(index, data)
			end

			-- Tell the owning client which plot is theirs, so BaseMarkerController can
			-- float the "YOUR BASE" beacon over it. Fired unconditionally (the beacon
			-- needs only the index, not `data`); assign() runs from DataService.onLoaded,
			-- well after the client's controllers have connected — the same "once on
			-- load" timing CashState and IndexState already rely on.
			Net.get("PlotState"):FireClient(player, index)
			return
		end
	end
	-- All 6 plots taken (should not happen with MaxPlayers = 6, but a place
	-- setting is not something this code can enforce). Used to mean only "nowhere
	-- to display"; now that BaseCamp carries no fallback spawn, it also means this
	-- player never gets a RespawnLocation or a teleport, and is stuck wherever
	-- their character's initial undefined-position spawn happened to land. Selling
	-- and upgrading still work regardless.
	warn(`[exhibit] no free plot for {player.Name} — all {PLOT_COUNT} are taken, and they have nowhere to spawn`)
end

local function release(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	plotOf[player] = nil
	plotOwner[index] = nil
	lastColorSet[player] = nil

	local plot = plotModel(index)
	if plot then
		local spawn = plot:FindFirstChild("PlotSpawn", true) :: SpawnLocation?
		if spawn then
			spawn.Enabled = false
		end
		renderName(index, nil)
		renderAccent(index, nil)
		renderLuck(index, nil)
		renderHose(index, nil)
		renderTreadmill(index, nil)
		renderBottle(index, nil)
		for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
			renderStand(index, slot, nil, nil)
		end
		renderLocker(index, nil)
		refreshStandCards(index, nil)
		-- Last: the stands on the upper floors have to be cleared while they are
		-- still in Workspace to be found.
		renderFloors(index, nil)
	end
end

-- ── Yield ─────────────────────────────────────────────────────────────────────

--- Dollars per second this profile's exhibit is currently worth, BEFORE the
--- hourly cap. Tuning.EXHIBIT_DUPLICATE_YIELD is flat 100% now, so every copy
--- pays in full. Per-entry math is
--- entryYieldPerSecond (also what each plinth's card prints), so the two agree.
local function rawRatePerSecond(data: any, stats: any): number
	local seen: { [string]: number } = {}
	local total = 0

	for _, entry in data.exhibit.pedestals do
		local copyIndex = (seen[entry.itemId] or 0) + 1
		seen[entry.itemId] = copyIndex
		local damping = Tuning.EXHIBIT_DUPLICATE_YIELD[math.min(copyIndex, #Tuning.EXHIBIT_DUPLICATE_YIELD)]
		total += entryYieldPerSecond(entry, damping, stats)
	end

	return total
end

--- Called once, right after a profile loads. Works out what the stands earned while
--- the player was offline (capped at EXHIBIT_OFFLINE_BANK_HOURS) and hands it to
--- AwayEarningsService, which holds it for the "While you were away" card's COLLECT
--- rather than dropping it silently into the wallet.
local function bankOffline(player: Player, data: any)
	local now = os.time()
	if data.exhibit.bankedAt <= 0 then
		data.exhibit.bankedAt = now
		return
	end

	local away = math.max(0, now - data.exhibit.bankedAt)
	local elapsed = math.min(away, Tuning.EXHIBIT_OFFLINE_BANK_HOURS * 3600)
	data.exhibit.bankedAt = now
	if elapsed <= 0 then
		return
	end

	local stats = StatResolver.get(data)
	-- stats.awayRate is Tuning.EXHIBIT_OFFLINE_RATE, raised by the Tycoon mastery.
	local offlineRate = rawRatePerSecond(data, stats) * stats.awayRate
	AwayEarningsService.offer(player, data, offlineRate * elapsed, away, offlineRate)
end

--- /away: pretend this player just came back from `seconds` offline, through the
--- same path a real login takes.
function ExhibitService.simulateAway(player: Player, seconds: number)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	data.exhibit.bankedAt = os.time() - seconds
	bankOffline(player, data)
end

--- Whole dollars are swept from bankedCash into spendable cash on a slow cadence,
--- not every tick: CashController documents that CashState must never fire per-tick,
--- and passive income trickles slowly enough that a DEPOSIT_INTERVAL batch is
--- invisible to the player — the badge just counts up on its own.
local DEPOSIT_INTERVAL = 2
local sinceDeposit = 0

--- Move the whole-dollar part of this profile's accrued exhibit income into
--- spendable cash, leaving the sub-dollar remainder in bankedCash so nothing is
--- lost to flooring each deposit. EconomyService.award fires CashState itself.
local function deposit(player: Player, data: any)
	local whole = math.floor(data.exhibit.bankedCash)
	if whole >= 1 then
		data.exhibit.bankedCash -= whole
		EconomyService.award(player, whole, "exhibit")
	end
end

--- The last rate IncomeState told each client, so the badge's "+$/s" line is sent on
--- change only. Checked from the tick rather than hooked into interact/level/stats,
--- because every one of those feeds rawRatePerSecond and the tick already calls it:
--- one comparison catches all of them, including ones added later.
local lastIncome: { [Player]: number } = {}

local function pushIncome(player: Player, rate: number)
	local last = lastIncome[player]
	if last ~= nil and math.abs(last - rate) < 1e-6 then
		return
	end
	lastIncome[player] = rate
	incomeRemote:FireClient(player, rate)
end

local function tickPlayer(player: Player, dt: number, flush: boolean)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	if #data.exhibit.pedestals == 0 then
		pushIncome(player, 0)
		return
	end

	local stats = StatResolver.get(data)
	local rate = rawRatePerSecond(data, stats)
	pushIncome(player, rate)
	data.exhibit.bankedCash += rate * dt
	data.exhibit.bankedAt = os.time()

	if flush then
		deposit(player, data)
	end
end

-- ── Actions ───────────────────────────────────────────────────────────────────

--- A plain take: pedestal `index` comes off its stand into the bag. Shared by the stand
--- prompt (`interact`, holding nothing) and the Nukes panel's Unequip.
local function takeOff(data: any, plot: number, index: number): (boolean, string)
	local entry = data.exhibit.pedestals[index]
	local elapsed = os.time() - entry.placedAt
	if elapsed < Tuning.EXHIBIT_UNCRATE_SECONDS then
		return false, `still crating \u{2014} {Tuning.EXHIBIT_UNCRATE_SECONDS - elapsed}s left`
	end
	-- A plain take is the one stand action that ADDS a slot (a swap trades one
	-- for one), so it is the one that has to ask whether there is room.
	if Bag.used(data) >= StatResolver.get(data).capacity then
		return false, "inventory full"
	end

	table.remove(data.exhibit.pedestals, index)
	table.insert(data.carry, {
		uid = entry.uid,
		itemId = entry.itemId,
		rarity = entry.rarity,
		modifier = entry.modifier,
		merge = entry.merge,
		bonus = entry.bonus,
		forge = entry.forge,
		reforges = entry.reforges,
		elapsed = 0,
		frozen = true,
		patches = {},
	})

	renderStand(plot, entry.slot, nil, nil)
	refreshStandCards(plot, data)
	return true, `{Items.get(entry.itemId).name} back in your bag`
end

--- The stand's one ProximityPrompt calls this and only this — `plot`/`slot` come
--- from the prompt's own closure (which physical stand you reached), never
--- re-derived from facing or position, so it can never disagree with what the
--- player actually pressed.
---
--- WHICH OF PLACE / TAKE / SWAP HAPPENS IS DECIDED BY WHETHER YOU ARE HOLDING
--- SOMETHING, not by anything the prompt itself knows (its label is a hint, not
--- the logic — "are you holding something" is per-player and the prompt's
--- `ActionText` is not). Holding nothing at an occupied stand takes; holding
--- something at an empty stand places; holding something at an occupied stand
--- swaps — the occupant comes off into the bag exactly like a plain take (frozen,
--- crating delay respected) and the held item goes up in its place, in one step.
function ExhibitService.interact(player: Player, plot: number, slot: number): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	if plotOf[player] ~= plot then
		return false, "that isn't your plot"
	end
	if slot < 1 or slot > Floors.slotsFor(data.exhibit.floors) then
		return false, "that stand doesn't exist"
	end

	local occupiedIndex = nil
	for i, entry in data.exhibit.pedestals do
		if entry.slot == slot then
			occupiedIndex = i
			break
		end
	end

	if data.heldUid == "" then
		-- Nothing in hand to place -- the only thing left worth trying is taking
		-- whatever is already here.
		if occupiedIndex == nil then
			return false, "hold something first \u{2014} pick it from your bag"
		end

		return takeOff(data, plot, occupiedIndex)
	end

	-- Holding something: validate it before worrying about what, if anything, is
	-- already up there.
	local item, list, index = EconomyService.find(data, data.heldUid)
	if item == nil or list ~= data.carry or index == nil then
		if Bag.findCrate(data, data.heldUid) then
			return false, "open the crate first \u{2014} you can't do that with a crate"
		end
		return false, "you aren't carrying that"
	end
	if not Contamination.isClean(item.patches or {}) then
		return false, "clean it first"
	end
	if item.modifier == "Slagged" then
		return false, "slag can't be displayed"
	end

	local displaced: any = nil
	if occupiedIndex then
		local entry = data.exhibit.pedestals[occupiedIndex]
		local elapsed = os.time() - entry.placedAt
		if elapsed < Tuning.EXHIBIT_UNCRATE_SECONDS then
			return false, `still crating \u{2014} {Tuning.EXHIBIT_UNCRATE_SECONDS - elapsed}s left`
		end
		table.remove(data.exhibit.pedestals, occupiedIndex)
		displaced = entry
	end

	table.remove(data.carry, index)
	if displaced then
		-- Same shape a plain take gives a retrieved item: frozen, no patches, clock
		-- reset. It was already docked; coming off must not restart the decay clock.
		table.insert(data.carry, {
			uid = displaced.uid,
			itemId = displaced.itemId,
			rarity = displaced.rarity,
			modifier = displaced.modifier,
			merge = displaced.merge,
			bonus = displaced.bonus,
			forge = displaced.forge,
			reforges = displaced.reforges,
			elapsed = 0,
			frozen = true,
			patches = {},
		})
	end

	table.insert(data.exhibit.pedestals, {
		slot = slot,
		uid = item.uid,
		itemId = item.itemId,
		rarity = item.rarity,
		modifier = item.modifier,
		merge = item.merge,
		bonus = item.bonus,
		forge = item.forge,
		reforges = item.reforges,
		placedAt = os.time(),
	})

	renderStand(plot, slot, item.itemId, item.rarity, item.uid, item.modifier)
	refreshStandCards(plot, data)

	if displaced then
		return true, `swapped in {Items.get(item.itemId).name} \u{2014} {Items.get(displaced.itemId).name} back in your bag`
	end
	return true, `{Items.get(item.itemId).name} is on display`
end

-- ── The Nukes panel: list + Equip Best ───────────────────────────────────────

type Pick = { item: any, value: number, onStand: boolean }

local nukeListRemote: any = nil
local lastEquip: { [Player]: number } = {}
local EQUIP_COOLDOWN = 1
local lastUnequip: { [Player]: number } = {}
local UNEQUIP_COOLDOWN = 0.2

--- Seconds this stand's piece is still crating for (0 = free to come off). The same
--- clock `interact` refuses a take/swap on.
local function crateLeft(entry: any): number
	return math.max(0, Tuning.EXHIBIT_UNCRATE_SECONDS - (os.time() - (entry.placedAt or 0)))
end

--- What one item id's copies pay together: highest first, each at its
--- EXHIBIT_DUPLICATE_YIELD step. `values` is every copy's undamped rate.
local function groupYield(values: { number }): number
	local sorted = table.clone(values)
	table.sort(sorted, function(a, b)
		return a > b
	end)
	local total = 0
	for i, value in sorted do
		total += value * Tuning.EXHIBIT_DUPLICATE_YIELD[math.min(i, #Tuning.EXHIBIT_DUPLICATE_YIELD)]
	end
	return total
end

--- What this profile's stands earn per second right now (the cash badge's "+$/s").
--- The daily rewards price their cash in minutes of it.
function ExhibitService.ratePerSecond(data: any): number
	if #data.exhibit.pedestals == 0 then
		return 0
	end
	return rawRatePerSecond(data, StatResolver.get(data))
end

--- What `item` would pay per second on a stand as a first copy (undamped): the number
--- the wash reveal prints under its price, off the same entryYieldPerSecond the stand
--- card uses, so the two agree once it is placed.
function ExhibitService.itemRatePerSecond(item: any, stats: any): number
	return entryYieldPerSecond(item, 1, stats)
end

--- Everything the Nukes panel draws, from the profile: the pieces on the stands, each
--- with the rate its stand card prints (damped, walked in `pedestals` order like
--- refreshStandCards). The bag is not listed -- the hotbar already shows it.
function ExhibitService.nukeList(player: Player): any?
	local data = DataService.data(player)
	if data == nil then
		return nil
	end
	local stats = StatResolver.get(data)

	local displayed = {}
	local seen: { [string]: number } = {}
	for _, entry in data.exhibit.pedestals do
		local copyIndex = (seen[entry.itemId] or 0) + 1
		seen[entry.itemId] = copyIndex
		local damping = Tuning.EXHIBIT_DUPLICATE_YIELD[math.min(copyIndex, #Tuning.EXHIBIT_DUPLICATE_YIELD)]
		table.insert(displayed, {
			uid = entry.uid,
			itemId = entry.itemId,
			name = Items.get(entry.itemId).name,
			rarity = entry.rarity,
			modifier = entry.modifier or "None",
			bonus = entry.bonus,
			merge = Merge.levelOf(entry),
			rate = entryYieldPerSecond(entry, damping, stats),
			copy = copyIndex,
			slot = entry.slot,
			crating = crateLeft(entry),
		})
	end

	return {
		slots = Floors.slotsFor(data.exhibit.floors),
		used = #data.exhibit.pedestals,
		rate = rawRatePerSecond(data, stats),
		displayed = displayed,
	}
end

--- The Nukes panel's Unequip: the piece with `uid` comes off its stand into the bag,
--- exactly as the stand prompt's plain take (crating clock and bag room included).
function ExhibitService.unequip(player: Player, uid: string): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	local plot = plotOf[player]
	if plot == nil then
		return false, "you don't have a base yet"
	end
	for i, entry in data.exhibit.pedestals do
		if entry.uid == uid then
			return takeOff(data, plot, i)
		end
	end
	return false, "that nuke isn't on display"
end

--- Fill every stand with the best set of nukes the player owns, and swap weaker
--- displayed ones back into the bag. "Best" is what the plot actually earns: the
--- duplicate damping is counted, so it spreads across different nukes instead of
--- stacking four copies of one Legendary.
---
--- THE PICK IS GREEDY ON MARGINAL YIELD, which is exact here: every item id's copies
--- earn a decreasing sequence (sorted value times a decreasing damping step), and the
--- best k picks from a set of decreasing sequences are the k biggest heads. Pieces
--- still crating are pinned -- they stay where they are and count as copies -- the
--- same clock `interact` refuses a take on.
---
--- The bag can never overflow: every piece that comes off a stand is replaced by one
--- going up out of the bag, and the picked set is never smaller than what was up.
--- Pieces that stay stay on their own stand; new ones fill the lowest free slot.
function ExhibitService.equipBest(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	local plot = plotOf[player]
	if plot == nil then
		return false, "you don't have a base yet"
	end
	-- Required here, not at the top: WashService -> LiquidService -> ExhibitService
	-- is already a chain, so a top-level require would close the loop.
	local WashService = require(script.Parent.WashService) :: any
	if WashService.isWashing(player) then
		return false, "finish your wash first"
	end

	local stats = StatResolver.get(data)
	local slots = Floors.slotsFor(data.exhibit.floors)

	local chosen: { Pick } = {}
	local pool: { Pick } = {}
	local groups: { [string]: { number } } = {}

	local function take(pick: Pick)
		table.insert(chosen, pick)
		local group = groups[pick.item.itemId]
		if group == nil then
			group = {}
			groups[pick.item.itemId] = group
		end
		table.insert(group, pick.value)
	end

	for _, entry in data.exhibit.pedestals do
		local pick = { item = entry, value = entryYieldPerSecond(entry, 1, stats), onStand = true }
		if crateLeft(entry) > 0 or entry.slot > slots then
			take(pick)
		else
			table.insert(pool, pick)
		end
	end
	for _, item in data.carry do
		if Contamination.isClean(item.patches or {}) and item.modifier ~= "Slagged" then
			table.insert(pool, { item = item, value = entryYieldPerSecond(item, 1, stats), onStand = false })
		end
	end

	while #chosen < slots and #pool > 0 do
		local bestIndex, bestGain = 0, -math.huge
		for i, pick in pool do
			local group = groups[pick.item.itemId] or {}
			local with = table.clone(group)
			table.insert(with, pick.value)
			local gain = groupYield(with) - groupYield(group)
			-- A tie keeps what is already up, so pressing it twice never shuffles.
			local better = gain > bestGain + 1e-9
				or (math.abs(gain - bestGain) <= 1e-9 and pick.onStand and not pool[bestIndex].onStand)
			if better then
				bestIndex, bestGain = i, gain
			end
		end
		take(table.remove(pool, bestIndex) :: Pick)
	end

	-- What goes up and what comes off.
	local keep: { [string]: boolean } = {}
	local goingUp: { any } = {}
	for _, pick in chosen do
		if pick.onStand then
			keep[pick.item.uid] = true
		else
			table.insert(goingUp, pick.item)
		end
	end
	if #goingUp == 0 then
		return false, "your best nukes are already on display"
	end

	local stays = {}
	local comingOff = {}
	local used: { [number]: boolean } = {}
	for _, entry in data.exhibit.pedestals do
		if keep[entry.uid] then
			table.insert(stays, entry)
			used[entry.slot] = true
		else
			table.insert(comingOff, entry)
		end
	end

	local placing: { [string]: boolean } = {}
	for _, item in goingUp do
		placing[item.uid] = true
	end
	for i = #data.carry, 1, -1 do
		if placing[data.carry[i].uid] then
			table.remove(data.carry, i)
		end
	end
	-- Same shape a plain take gives a retrieved piece (see `interact`).
	for _, entry in comingOff do
		table.insert(data.carry, {
			uid = entry.uid,
			itemId = entry.itemId,
			rarity = entry.rarity,
			modifier = entry.modifier,
			merge = entry.merge,
			bonus = entry.bonus,
			forge = entry.forge,
			reforges = entry.reforges,
			elapsed = 0,
			frozen = true,
			patches = {},
		})
	end

	local changed: { [number]: any } = {}
	for _, entry in comingOff do
		changed[entry.slot] = false
	end
	local now = os.time()
	local nextSlot = 1
	for _, item in goingUp do
		while used[nextSlot] do
			nextSlot += 1
		end
		used[nextSlot] = true
		local entry = {
			slot = nextSlot,
			uid = item.uid,
			itemId = item.itemId,
			rarity = item.rarity,
			modifier = item.modifier,
			merge = item.merge,
			bonus = item.bonus,
			forge = item.forge,
			reforges = item.reforges,
			placedAt = now,
		}
		table.insert(stays, entry)
		changed[nextSlot] = entry
	end

	-- Best first, so each item id's top copy is the one paid at full rate:
	-- rawRatePerSecond hands out the damping in array order.
	table.sort(stays, function(a, b)
		return entryYieldPerSecond(a, 1, stats) > entryYieldPerSecond(b, 1, stats)
	end)
	data.exhibit.pedestals = stays

	for slot, entry in changed do
		if entry then
			renderStand(plot, slot, entry.itemId, entry.rarity, entry.uid, entry.modifier)
		else
			renderStand(plot, slot, nil, nil)
		end
	end
	refreshStandCards(plot, data)

	local message = `{#goingUp} {if #goingUp == 1 then "nuke" else "nukes"} on display`
	if #comingOff > 0 then
		message ..= ` \u{2014} {#comingOff} back in your bag`
	end
	return true, message
end

-- ── Floors ────────────────────────────────────────────────────────────────────

--- Build the next floor on this player's own base. `plot`/`floor` come from the
--- sign's own attributes (which base it stands on, which floor it sells), the same
--- "the prompt IS the thing" rule `interact` follows. Same shape as
--- TreadmillService.buy: check everything, debit FIRST, and only touch the profile
--- once the money has actually moved.
---
--- NO PROXIMITY CHECK: only ever reached from a ProximityPrompt.Triggered, which the
--- engine has already range-checked (TreadmillService.buy says the same).
function ExhibitService.buyFloor(player: Player, plot: number, floor: number): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	if plotOf[player] ~= plot then
		return false, "that isn't your base"
	end

	local owned = Floors.clamp(data.exhibit.floors)
	if floor <= owned then
		return false, `you already have floor {floor}`
	end
	if floor ~= owned + 1 then
		return false, `build floor {owned + 1} first`
	end
	local price = Floors.PRICES[floor]
	if price == nil then
		return false, "your base can't go any higher"
	end

	local paid, reason = EconomyService.spend(player, price)
	if not paid then
		return false, reason
	end

	data.exhibit.floors = floor
	data.exhibit.slots = Floors.slotsFor(floor)
	renderAll(plot, data)
	-- The "YOUR BASE" beacon rides over the top deck; PlotState is what (re)builds it.
	Net.get("PlotState"):FireClient(player, plot)
	return true, `floor {floor} built \u{2014} {Floors.UPPER_SLOTS} more stands (paid ${price})`
end

-- Per sign, so a second refusal inside the flash window restarts it rather than
-- being cut short by the first one's timer.
local signFlash: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

--- Write `message` into a floor sign's painted subtitle for a moment, then put its
--- price back. The world answer for a refused purchase — see build/Plots.buildFloorSign.
local function flashSign(board: BasePart, message: string)
	local sign = board:FindFirstChild("Sign")
	local subtitle = sign and sign:FindFirstChild("Subtitle")
	if subtitle == nil or not subtitle:IsA("TextLabel") then
		return
	end
	local token = (signFlash[board] or 0) + 1
	signFlash[board] = token
	subtitle.Text = message
	task.delay(SIGN_FLASH_SECONDS, function()
		if signFlash[board] == token then
			local rest = board:GetAttribute("SignText")
			subtitle.Text = if type(rest) == "string" then rest else ""
		end
	end)
end

local wiredSigns: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- The floor purchase popup (client FloorPurchaseController). Holding E on a sign no
-- longer buys: it sends the offer, and the popup's BUY button asks for it back.
local floorRemote: RemoteEvent = nil
-- How far from the board a BUY may be pressed. The prompt reaches 10; this leaves room
-- to step back while reading the popup, and the popup closes itself past it.
local FLOOR_BUY_REACH = 16

--- The live (in-Workspace) board selling `floor` on plot `plot`, or nil.
local function liveFloorBoard(plot: number, floor: number): BasePart?
	for board in wiredSigns do
		if
			board:IsA("BasePart")
			and board:IsDescendantOf(Workspace)
			and board:GetAttribute("PlotIndex") == plot
			and board:GetAttribute("BuysFloor") == floor
		then
			return board
		end
	end
	return nil
end

--- Open the popup for `floor` on `player`'s screen: the price, what it adds and what
--- they have, so the card can say up front whether they can afford it.
local function offerFloor(player: Player, board: BasePart, plot: number, floor: number)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	floorRemote:FireClient(player, {
		kind = "offer",
		plot = plot,
		floor = floor,
		price = Floors.PRICES[floor] or 0,
		stands = Floors.UPPER_SLOTS,
		cash = data.cash,
		board = board,
	})
end

--- The popup's BUY. Range-checked here because, unlike the prompt, a remote is not.
local function onFloorBuy(player: Player, plot: any, floor: any)
	if type(plot) ~= "number" or type(floor) ~= "number" then
		return
	end
	local board = liveFloorBoard(plot, floor)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local ok, message
	if board == nil then
		ok, message = false, "that floor isn't for sale"
	elseif root == nil or ((root :: BasePart).Position - board.Position).Magnitude > FLOOR_BUY_REACH then
		ok, message = false, "walk back to the sign"
	else
		ok, message = ExhibitService.buyFloor(player, plot, floor)
	end
	if ok then
		print(`[exhibit] {player.Name}: {message}`)
	end
	local data = DataService.data(player)
	floorRemote:FireClient(player, {
		kind = "result",
		ok = ok,
		message = message,
		floor = floor,
		cash = if data then data.cash else nil,
	})
end

--- Connect one floor sign's prompt to buyFloor. Built by build/Plots.buildFloorSign and
--- saved with the place; wired here by tag, the same build-time/runtime split every
--- world purchase uses. Once per board: a parked floor sign never leaves the DataModel
--- (it goes to ServerStorage), so its connection survives being hidden.
local function wireFloorSign(board: Instance)
	if not board:IsA("BasePart") or wiredSigns[board] then
		return
	end
	local prompt = board:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then
		warn(`[exhibit] {board:GetFullName()} sells a floor but has no ProximityPrompt — nobody can buy from it`)
		return
	end
	wiredSigns[board] = true
	-- A place saved with the sign hung on the inside of the fence gets it stood up
	-- outside the base instead, the same no-rebuild way.
	Plots.placeFloorSign(board :: BasePart)
	-- A place saved before the painted "Floor N / Purchase floor for $X" look still
	-- wears the old billboard; this swaps it in without a world rebuild.
	Plots.dressFloorSign(board :: BasePart)
	-- The popup is the confirm step now, so a tap opens it (a saved place still has
	-- the old half-second hold).
	prompt.HoldDuration = 0
	prompt.ActionText = `Purchase Floor {board:GetAttribute("BuysFloor")}`

	prompt.Triggered:Connect(function(player: Player)
		if not Tutorial.promptOpen(player, prompt) then
			return
		end
		local plot = board:GetAttribute("PlotIndex")
		local floor = board:GetAttribute("BuysFloor")
		if type(plot) ~= "number" or type(floor) ~= "number" then
			return
		end
		-- Someone else's base: answer on the sign, the way it always has. Your own:
		-- the popup, which does the buying.
		if plotOf[player] ~= plot then
			flashSign(board, "that isn't your base")
			return
		end
		offerFloor(player, board :: BasePart, plot, floor)
	end)
end

-- ── Bootstrap ─────────────────────────────────────────────────────────────────

function ExhibitService.init()
	resultRemote = Net.get("StationResult")
	noticeRemote = Net.get("Notice")
	colorRemote = Net.get("PlotColor")
	incomeRemote = Net.get("IncomeState")
	nukeListRemote = Net.get("NukeList")
	floorRemote = Net.get("FloorPurchase")
end

function ExhibitService.start()
	-- The Settings GUI's base-colour picker. The client sends a bare hex string ("" to
	-- reset); setPlotColor validates the format, persists it and repaints. We echo the
	-- SERVER-CONFIRMED value straight back so the picker snaps to what actually stuck
	-- (a rejected or debounced change leaves data.plotColor unchanged, so the echo
	-- reverts the client). No StationResult toast — the picker is not a station, and
	-- that toast is invisible away from one (memory: station-result-toast-needs-panel).
	-- The second value is the plot's default hue, which the base wears while the first
	-- is "" — the picker shows it rather than a grey the world no longer uses.
	colorRemote.OnServerEvent:Connect(function(player: Player, hex)
		ExhibitService.setPlotColor(player, if type(hex) == "string" then hex else "")
		local data = DataService.data(player)
		colorRemote:FireClient(player, if data then data.plotColor else "", defaultAccentHex(player))
	end)

	-- The Nukes panel. "list" answers with a snapshot; "equipBest" and "unequip" (+ uid)
	-- do the work and answer with the snapshot after it, carrying the outcome as
	-- `notice`. Equip Best rewrites a whole plot, so it gets a short cooldown the list
	-- does not need; Unequip a shorter one against a spammed button.
	Net.get("NukeAction").OnServerEvent:Connect(function(player: Player, action, uid)
		local notice: string? = nil
		if action == "equipBest" then
			local now = os.clock()
			if now - (lastEquip[player] or 0) < EQUIP_COOLDOWN then
				return
			end
			lastEquip[player] = now
			local _, message = ExhibitService.equipBest(player)
			notice = message
		elseif action == "unequip" then
			local now = os.clock()
			if type(uid) ~= "string" or now - (lastUnequip[player] or 0) < UNEQUIP_COOLDOWN then
				return
			end
			lastUnequip[player] = now
			local _, message = ExhibitService.unequip(player, uid)
			notice = message
		elseif action ~= "list" then
			return
		end
		local list = ExhibitService.nukeList(player)
		if list then
			list.notice = notice
			nukeListRemote:FireClient(player, list)
		end
	end)

	-- Every locker's prompt, claimed or not, so a visitor pressing E on a stranger's
	-- rack is told why nothing opened. renderLocker re-runs this after a rebuild.
	for index = 1, PLOT_COUNT do
		ensureLockerStation(index)
	end

	-- Every floor sign, including ones a later World.rebuild() adds mid-session.
	for _, board in CollectionService:GetTagged(FLOOR_TAG) do
		wireFloorSign(board)
	end
	CollectionService:GetInstanceAddedSignal(FLOOR_TAG):Connect(wireFloorSign)
	floorRemote.OnServerEvent:Connect(function(player: Player, verb, plot, floor)
		if verb == "buy" then
			onFloorBuy(player, plot, floor)
		end
	end)

	-- The place is saved with every floor of every plot showing (build/Plots builds
	-- them all); nobody owns anything yet, so strip every plot to its ground floor.
	for index = 1, PLOT_COUNT do
		renderFloors(index, nil)
		-- And every treadmill gets its upgrade sign up (and a saved place's old E
		-- prompt taken down) before anyone claims it; Plots.setTreadmillTier does both.
		renderTreadmill(index, nil)
	end

	DataService.onLoaded(function(player, data)
		-- `slots` is always derived from `floors` (Config/Floors). This also brings up
		-- saves from before every ground stand was free (the old EXHIBIT_STARTING_SLOTS
		-- was 3, upgraded with cash) — Reconcile can't, since the key already exists.
		data.exhibit.floors = Floors.clamp(data.exhibit.floors)
		data.exhibit.slots = Floors.slotsFor(data.exhibit.floors)
		bankOffline(player, data)
		deposit(player, data)
		assign(player)

		-- Open the Settings picker on the player's saved base colour ("" = never
		-- picked, so the plot's default hue follows). Same "once on load" timing as the
		-- PlotState fire inside assign(), which is also what makes plotOf valid here.
		colorRemote:FireClient(player, data.plotColor, defaultAccentHex(player))
	end)

	-- A completed index stage raises yieldMultiplier (Tuning.INDEX_COMPLETE_CASH), so
	-- every stand card's $/s is stale the moment it happens. Income itself needs
	-- nothing: tickPlayer resolves stats fresh.
	IdentifyService.onStageComplete(function(player, _stageId)
		local plot = ExhibitService.plotOf(player)
		local data = DataService.data(player)
		if plot and data then
			refreshStandCards(plot, data)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		release(player)
		lastIncome[player] = nil
		lastEquip[player] = nil
		lastUnequip[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		sinceDeposit += dt
		local flush = sinceDeposit >= DEPOSIT_INTERVAL
		if flush then
			sinceDeposit = 0
		end
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(tickPlayer, player, dt, flush)
			if not ok then
				warn(`[exhibit] tick failed for {player.Name}: {err}`)
			end
		end
	end, "ExhibitService")
end

return ExhibitService
