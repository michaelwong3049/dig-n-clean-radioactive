--!strict
--[[
	LiquidService.lua — the wash pad. Step on it, roll a liquid, load the hose.

	THE ROLL IS AN EDGE, NOT AN ACTION, and that is the whole design. There is no
	"ROLL" button anywhere: `StationService.onChanged` tells this service the moment a
	player's feet arrive inside a `StationKind = "roller"` radius and the pad pays out
	right there. Stepping on a thing and having it go off is a five-year-old's idea of
	a good time, and a confirmation dialog in front of it would be worth exactly
	nothing. DeconService already sets this precedent — docking is an edge for the
	same reason — so the machinery for it exists and this file just subscribes.

	WHAT STOPS AN INFINITE RE-ROLL IS THE FEE, NOT THE COOLDOWN. Those two constants
	do genuinely different jobs and swapping them breaks the pad:

	  Tuning.LIQUID_ROLL_COST      the actual limiter. Without it, hopping on and off
	                               until Stardust lands is strictly optimal and every
	                               weight in Config/Liquids is decoration.
	  Tuning.LIQUID_ROLL_COOLDOWN  a debounce, nothing more. One roll per crossing
	                               would otherwise machine-gun the reveal animation.

	A PLAYER WHO CANNOT AFFORD A ROLL IS NOT STUCK. Plain Water is unlimited and
	always loaded (Config/Liquids), so a broke player cleans slowly rather than not at
	all. The pad says so out loud rather than silently doing nothing, because a pad
	that ignores you is indistinguishable from a pad that is broken.

	THE PAD ANSWERS IN THE WORLD, NOT ON A SCREEN. There used to be a panel here
	listing all ten liquids and their live odds, and it was the wrong shape: a big lit
	button you step on should not open a menu. `announce()` below flashes the plate in
	the rolled liquid's colour and names it on the pad's own billboard instead, which
	every player on that base sees rather than only whoever stepped on it.

	The odds are still readable, just not mid-roll: the pad's shelf shows the top five
	prizes as physical canisters (build/Plots.buildWashPad), the wooden Luck sign next
	to it lists the whole ladder, and `/odds` prints the live table. All three read
	`Liquids.oddsAt`, the same function `roll()` below samples against — the same
	deterministic-order weighted walk `DigService.rollRarity` uses, for the same reason
	(`pairs()` order is not stable, and a weighted roll over an unstable order has
	unstable odds). A pad that advertises 1-in-40 and rolls 1-in-800 is the worst bug
	this feature could ship, and the only way to guarantee it cannot happen is for
	every one of those numbers to come out of the same code.

	CHARGES ARE THE SCARCITY. A rolled liquid clears `def.charges` patches and then
	quietly reverts to water — see StatResolver.liquidFor, which is the single place
	"...unless it ran out" is written down. Stacking is capped at
	Tuning.LIQUID_MAX_STACK multiples so an idle player parked on the pad cannot
	accumulate an unbounded supply of the top of the table.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Liquids = require(Shared.Config.Liquids)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)

local LiquidService = {}

local stateRemote: any = nil

--- Last roll time per player, for the debounce. Wall clock rather than a tick
--- counter: this is a "how long since a human did a thing" question, and nothing
--- else in this file runs on the Ticker at all.
local lastRoll: { [Player]: number } = {}
local lastSignature: { [Player]: string } = {}

-- ── Rolling ───────────────────────────────────────────────────────────

--- Deterministic-order weighted pick, mirroring DigService.rollRarity. Walks
--- `Liquids.ORDER` rather than the DEFS table so the odds cannot drift with
--- whatever order Lua feels like handing back today.
local function roll(luck: number): string
	local total = 0
	for _, id in Liquids.ORDER do
		total += Liquids.effectiveWeight(Liquids.DEFS[id], luck)
	end

	if total <= 0 then
		-- Every rollable liquid has weight 0, which means somebody emptied the
		-- catalogue. Water is still a correct answer, so degrade rather than error:
		-- this runs off a movement edge and an error here would fire every time
		-- anyone walked over the pad.
		return Liquids.WATER
	end

	local pick = math.random() * total
	for _, id in Liquids.ORDER do
		local weight = Liquids.effectiveWeight(Liquids.DEFS[id], luck)
		if weight > 0 then
			pick -= weight
			if pick <= 0 then
				return id
			end
		end
	end

	-- Floating-point undershoot on the last entry. Take the commonest rollable
	-- liquid rather than water: the player paid, so they get something.
	for _, id in Liquids.ORDER do
		if Liquids.isRollable(id) then
			return id
		end
	end
	return Liquids.WATER
end

--- Pay for and perform one roll. Returns the liquid id, or nil plus a reason.
---
--- THE FIRST ROLL OF A PROFILE'S LIFE IS FREE, and `data.stats.rolls` is the whole
--- mechanism: it is 0 on a fresh profile and `pull` increments it below, so a broke
--- new player still gets to see the pad do its thing once. After that the fee is the
--- limiter the header describes. Refusal strings are kept SHORT because they are shown
--- on the pad's own sign now (see `flashSign` / the roller branch in `start`), not in
--- a screen toast -- the toast lived inside the station panel, which the wash pad
--- deliberately never opens, so a refused roll used to produce no feedback at all.
local function pull(player: Player, data: any): (string?, string?)
	local now = os.clock()
	local previous = lastRoll[player]
	if previous and now - previous < Tuning.LIQUID_ROLL_COOLDOWN then
		return nil, "still resetting\u{2026}"
	end

	local free = (data.stats.rolls or 0) == 0

	if not free and data.cash < Tuning.LIQUID_ROLL_COST then
		return nil, `roll costs ${Tuning.LIQUID_ROLL_COST}`
	end

	if not free then
		data.cash -= Tuning.LIQUID_ROLL_COST
		EconomyService.pushCash(player)
	end
	lastRoll[player] = now

	local stats = StatResolver.get(data)
	local id = roll(stats.luckMultiplier)
	local def = Liquids.get(id)

	-- Stacking, capped. A repeat roll of something you already hold tops it up
	-- rather than replacing it, which is what makes the common end of the table
	-- feel like a consolation prize instead of a wasted fee.
	local ceiling = def.charges * Tuning.LIQUID_MAX_STACK
	local held = data.liquids[id] or 0
	data.liquids[id] = math.min(held + def.charges, ceiling)

	data.stats.rolls = (data.stats.rolls or 0) + 1

	-- Auto-equip anything strictly better than what is loaded. A player who rolls
	-- Stardust and then has to find the equip button before it means anything has
	-- had the moment taken off them. Rolling something WORSE never silently
	-- downgrades you -- that would be a punishment for engaging with the pad.
	local _, current = LiquidService.equipped(data)
	if def.order > current.order then
		data.equippedLiquid = id
	end

	return id, nil
end

-- ── The pad answers for itself ─────────────────────────────────────────

--- How long the pad wears the rolled liquid before settling back.
local ANNOUNCE_SECONDS = 4

--- Per-pad token, so two rolls in quick succession cannot leave the earlier one's
--- reset timer wiping the later one's announcement off the sign.
local announceToken: { [BasePart]: number } = {}

--- The flash colour is BLENDED TOWARD REST, not scaled toward black. First cut of
--- this fix multiplied the raw liquid hex by a flat 0.5 -- an improvement, but still
--- an ABSOLUTE colour with no relationship to whatever the disc's resting state
--- actually renders as under this world's bright ambient (build/Daylight.apply(),
--- Lighting.Brightness = 2.4, explicitly documented there as pushing things toward
--- near-white). The rest colour is the one shade already proven to look calm in
--- THIS lighting, on THIS material, next to THIS PointLight -- so the flash is now a
--- partial step FROM it toward the liquid's hue, which can never render brighter
--- than a straight blend of two colours the scene already renders acceptably.
local FLASH_MIX = 0.4
local function flashColor(rawHex: string, rest: Color3): Color3
	local raw = Color3.fromHex(rawHex)
	return rest:Lerp(raw, FLASH_MIX)
end

--- The colour a REFUSED roll flashes -- amber, because "you can't afford this yet" is
--- information, not an error. Blended toward the disc's rest shade by `flashColor` the
--- same way a liquid hue is, so it reads as the same kind of event as a real roll.
local REFUSAL_HEX = "F2B134"

--- Flash the pad's sign and disc, then ease them back after ANNOUNCE_SECONDS. The
--- mechanism behind both a real roll (`announce`) and a refused one (the roller branch
--- in `start`) -- the pad is a physical button, and a physical button answers on
--- itself, not on a screen. `title == nil` keeps the pad's own resting headline
--- ("WASH PAD") but tints it `hex`, which is what a refusal wants: the line under it
--- turns amber and says why nothing happened, and the sign always eases back to rest
--- afterwards no matter what state it was flashed from.
---
--- SERVER-SIDE ON PURPOSE, the same argument ToolService's header makes for held
--- models: everyone standing on that base sees it, not just whoever stepped on the
--- plate. A client-local flash would be invisible to the person you are showing your
--- base to, which is most of the point of rolling something rare.
---
--- THE SIGN REMEMBERS ITS OWN RESTING STATE, captured once on the first flash and
--- read back on every reset. The alternative was a copy of the builder's title,
--- subtitle and label colour living here -- constants duplicated out of
--- build/Plots.buildWashPad, which is precisely the drift this codebase keeps writing
--- headers about. Restore-what-was-there needs no constants, and it stays correct the
--- day somebody retitles the pad.
local function flashSign(pad: BasePart?, title: string?, subtitle: string, hex: string)
	if pad == nil then
		return
	end

	local glow = pad.Parent and pad.Parent:FindFirstChild("Glow")
	local sign = pad:FindFirstChild("Sign")
	local titleLabel = if sign then sign:FindFirstChild("Title") else nil
	local subtitleLabel = if sign then sign:FindFirstChild("Subtitle") else nil

	-- Rest state is captured on the FIRST flash of any kind, title included even when
	-- this flash is a refusal that does not rename the sign -- so the reset below can
	-- always put the headline back regardless of which flash type ran last.
	if titleLabel and titleLabel:IsA("TextLabel") and titleLabel:GetAttribute("RestText") == nil then
		titleLabel:SetAttribute("RestText", titleLabel.Text)
		titleLabel:SetAttribute("RestColor", titleLabel.TextColor3)
	end
	if subtitleLabel and subtitleLabel:IsA("TextLabel") and subtitleLabel:GetAttribute("RestText") == nil then
		subtitleLabel:SetAttribute("RestText", subtitleLabel.Text)
	end
	if glow and glow:IsA("BasePart") and glow:GetAttribute("RestColor") == nil then
		glow:SetAttribute("RestColor", glow.Color)
	end

	announceToken[pad] = (announceToken[pad] or 0) + 1
	local token = announceToken[pad]

	-- Snap to the new colour, then ease back on the reset. Tweening in BOTH
	-- directions reads as a slow fade with no event in it; a payout wants the hard cut.
	if glow and glow:IsA("BasePart") then
		local rest = glow:GetAttribute("RestColor")
		glow.Color = flashColor(hex, if typeof(rest) == "Color3" then rest else glow.Color)
	end
	if titleLabel and titleLabel:IsA("TextLabel") then
		-- A refusal (title == nil) keeps the resting headline but wears the flash tint;
		-- a real roll renames it to the liquid.
		if title ~= nil then
			titleLabel.Text = string.upper(title)
		elseif titleLabel:GetAttribute("RestText") ~= nil then
			titleLabel.Text = tostring(titleLabel:GetAttribute("RestText"))
		end
		titleLabel.TextColor3 = Color3.fromHex(hex)
	end
	if subtitleLabel and subtitleLabel:IsA("TextLabel") then
		subtitleLabel.Text = subtitle
	end

	task.delay(ANNOUNCE_SECONDS, function()
		if announceToken[pad] ~= token then
			return -- a newer flash owns the sign now
		end
		if glow and glow:IsA("BasePart") and glow.Parent then
			local rest = glow:GetAttribute("RestColor")
			if typeof(rest) == "Color3" then
				TweenService:Create(glow, TweenInfo.new(0.8), { Color = rest }):Play()
			end
		end
		if titleLabel and titleLabel:IsA("TextLabel") and titleLabel.Parent and titleLabel:GetAttribute("RestText") ~= nil then
			titleLabel.Text = tostring(titleLabel:GetAttribute("RestText"))
			local rest = titleLabel:GetAttribute("RestColor")
			if typeof(rest) == "Color3" then
				titleLabel.TextColor3 = rest
			end
		end
		if subtitleLabel and subtitleLabel:IsA("TextLabel") and subtitleLabel.Parent then
			subtitleLabel.Text = tostring(subtitleLabel:GetAttribute("RestText"))
		end
	end)
end

--- Show the roll ON THE PAD, in the world, rather than on anybody's screen: the plate
--- flashes the liquid's own colour and its billboard names what came out. The panel
--- that used to do this is gone (see StationController's header).
local function announce(pad: BasePart?, def: Liquids.LiquidDef, held: number)
	flashSign(
		pad,
		def.name,
		if def.charges > 0 then `{held} washes in the shed` else "always free",
		def.color
	)
end

-- ── Reading ───────────────────────────────────────────────────────────

--- The loaded liquid: its id and its definition. Thin delegate over StatResolver so
--- callers do not each re-derive "equipped, unless the charges ran out".
function LiquidService.equipped(data: any): (string, Liquids.LiquidDef)
	local stats = StatResolver.get(data)
	return stats.liquidId, Liquids.get(stats.liquidId)
end

--- Spend one charge against the loaded liquid. Called once per cleared patch.
--- Water is unlimited, so this is a no-op on the floor — which is what makes
--- "always able to clean something" true rather than aspirational.
function LiquidService.spendCharge(data: any): ()
	local id = LiquidService.equipped(data)
	if id == Liquids.WATER then
		return
	end

	local left = (data.liquids[id] or 0) - 1
	if left <= 0 then
		-- Drop the key rather than storing a 0. An empty table is exactly the "on
		-- water" state DataService's TEMPLATE documents, and leaving zeroed entries
		-- behind would grow the profile with rows the panel then has to filter.
		data.liquids[id] = nil
		data.equippedLiquid = ""
	else
		data.liquids[id] = left
	end
end

--- The whole shelf: what you hold of each liquid, what is loaded, and the live odds
--- at this player's current luck. Read by LiquidController's badge (which uses only
--- `equipped` and that entry's `held`) and by the `/odds` debug command, which is
--- where the full table lives now that the panel is gone.
function LiquidService.viewFor(data: any): any
	local stats = StatResolver.get(data)
	local odds = Liquids.oddsAt(stats.luckMultiplier)

	local shelf: { any } = {}
	for _, id in Liquids.ORDER do
		local def = Liquids.DEFS[id]
		if def.weight <= 0 then
			continue
		end
		table.insert(shelf, {
			id = id,
			name = def.name,
			color = def.color,
			flavor = def.flavor,
			potency = def.potency,
			rateMult = def.rateMult,
			xpMult = def.xpMult,
			charges = def.charges,
			odds = odds[id] or 0,
			held = data.liquids[id] or 0,
		})
	end

	return {
		luck = stats.luckMultiplier,
		cost = Tuning.LIQUID_ROLL_COST,
		equipped = stats.liquidId,
		equippedName = Liquids.get(stats.liquidId).name,
		potency = stats.cleanPotency,
		effectivePotency = stats.effectivePotency,
		liquids = shelf,
	}
end

--- Fingerprints everything `viewFor` can render, so LiquidState fires on a real
--- change and not ten times a second. Same rule CarryService.signatureOf spells
--- out: anything the client draws has to be in here or it silently goes stale.
--- `luck` is in it because buying a Luck tier moves every odds figure on the panel
--- with nothing about the shelf itself having moved.
local function signatureOf(data: any, stats: any): string
	local parts = { stats.liquidId, string.format("%.4f", stats.luckMultiplier), tostring(data.cash >= Tuning.LIQUID_ROLL_COST) }
	for _, id in Liquids.ORDER do
		table.insert(parts, `{id}:{data.liquids[id] or 0}`)
	end
	return table.concat(parts, "|")
end

function LiquidService.push(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local stats = StatResolver.get(data)
	local signature = signatureOf(data, stats)
	if lastSignature[player] == signature then
		return
	end
	lastSignature[player] = signature
	stateRemote:FireClient(player, LiquidService.viewFor(data))
end

-- ── Actions ───────────────────────────────────────────────────────────

--- Load a canister into the hose. "" and "water" both mean the floor, and both are
--- always allowed — a player must be able to put the good stuff away and save it.
function LiquidService.equip(player: Player, id: string): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "no profile"
	end

	if id == "" or id == Liquids.WATER then
		data.equippedLiquid = ""
		return true, "loaded Plain Water"
	end

	if not Liquids.isRollable(id) then
		return false, "no such liquid"
	end
	if (data.liquids[id] or 0) <= 0 then
		return false, `you have no {Liquids.get(id).name} left`
	end

	data.equippedLiquid = id
	return true, `loaded {Liquids.get(id).name}`
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

function LiquidService.init()
	stateRemote = Net.get("LiquidState")
end

function LiquidService.start()
	StationService.onChanged(function(player, kind)
		if kind ~= "roller" then
			return
		end

		local data = DataService.data(player)
		if data == nil then
			return
		end

		local id, refusal = pull(player, data)

		-- The pad itself is the only surface that reports this, WIN OR LOSE. Found by
		-- asking StationService where the player is standing rather than being handed
		-- down through onChanged, because onChanged's signature is shared by every
		-- station kind and widening it for one caller would be the wrong trade.
		--
		-- A refusal used to fire a StationResult toast, which rendered into a label
		-- inside the station panel -- and the wash pad is precisely the station that
		-- never opens a panel (StationController's PANEL_KINDS), so the message went
		-- nowhere and a broke player saw a dead button. The refusal flashes the sign
		-- amber instead, the same event shape as a real roll.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local pad: BasePart? = nil
		if root and root:IsA("BasePart") then
			local _, _, part = StationService.at(root.Position)
			pad = part
		end

		if id == nil then
			flashSign(pad, nil, tostring(refusal), REFUSAL_HEX)
			return
		end

		local def = Liquids.get(id)
		announce(pad, def, data.liquids[id] or 0)
		print(`[liquid] {player.Name} rolled {def.name}`)
	end)

	-- PUSHED ON THE TICK, GATED BY THE SIGNATURE — the CarryService pattern, and
	-- chosen over calling push() from each mutation site for one specific reason:
	-- the panel shows whether you can AFFORD a roll, and cash moves from six places
	-- (a sale, a shop, an exhibit payout, three debug commands) that have no reason
	-- to know this service exists. A tick that almost always compares one string and
	-- returns is cheaper than the bug where one of those six forgets.
	Ticker.every(Tuning.TICK_RATE, function()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(LiquidService.push, player)
			if not ok then
				warn(`[liquid] push failed for {player.Name}: {err}`)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		lastSignature[player] = nil
	end)
end

return LiquidService
