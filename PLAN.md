# Dig N Clean: Radioactive — Game Design Document

## Context

This is a **design-only** plan. No code is written in this pass.

The deliverable is a new folder `/Users/michael/Documents/Code/Roblox/Dig-N-Clean-Radioactive/`
containing `PLAN.md` — the full game design document below.

The concept is a radioactive-wasteland reskin-and-deepening of the Roblox game *Dig N Clean*.
The original's loop is: sweep with a metal detector → dig → clean the item → sell → upgrade.
The radiation layer is not paint. It adds four things the original loop doesn't have:

* a **second resource the player must manage** — exposure (§3.1);
* a **second gate on every item** — contamination (§2, step 4);
* a **timer on every item you unearth** — the decay clock, which turns the walk home into
the tensest part of the loop (§3.6);
* and a **soft, physical wall around every zone** — radiation burn instead of a locked door,
which turns "you can't go there" into "you can, and here's what it costs" (§3.5).

It also changes the extraction tool: **no shovel — a magnet.** Everything worth money out
here is irradiated metal, and pulling it up is click-driven rather than hold-driven, which
gives the loop an active skill beat at minute one instead of a progress bar (§2, step 2).

Together those give the game real tension, a natural reason for gear tiers to exist, and a
gamble the player can take at any level. On top of that sits a second exit for every item —
**display it for income instead of selling it** (§8) — which gives the loot table a
metagame and the shared server a point.

Scope decisions locked with the user:

* **Design only** — no engineering architecture section.
* **Shared server, solo progression** — everyone digs the same wasteland and sees each other;
cash, inventory and upgrades are per-player.
* **Full vision doc**, with an MVP slice marked at the end.
* **No hard zone locks.** The wasteland is physically open end to end from minute one.
Radiation, not a barrier, is what stops you. (§3.5)
* **Selling is not the only exit** for an item. Cleaned items can be **displayed** for
passive income instead. (§8)

\---

## 1\. The Pitch

> The bombs fell. Everything valuable is still down there — it's just glowing.
>
> Sweep the ash with a Geiger-detector, rip what beeps out of the ground with a magnet, then
> get it home and scrub the radiation off it before it eats through your gloves. The hotter the item, the more it's
> worth, and the worse it is to hold. Sell it, or bolt it to a pedestal and let the world
> come pay to look at it. Buy a better suit. Walk further into the dead zone than you should.

**One-line hook:** *the thing that makes an item valuable is the same thing that's killing you.*

That tension is the whole design. Every system below either feeds it or pays it off.

**Three corollaries the design commits to:**

1. **Nothing is locked, everything is lethal.** You may walk into the Crater at level 1.
You will die in about a second. The game never says "you can't" — it says "look what
happened." (§3.5)
2. **The clock starts when the item leaves the ground.** Finding it is not having it.
Getting it home is the game. (§3.6)
3. **An item you sell is gone. An item you display keeps paying.** (§8)

\---

## 2\. Core Loop

```
   SWEEP ──> PULL ──> HAUL ──> DECONTAMINATE ──┬──> SELL ─────> cash now ─────┐
     ▲                                        │                               │
     │                                        └──> DISPLAY ──> income ────────┤
     │                                                        forever         │
     └───────────────── UPGRADE (go deeper) <─────────────────────────────────┘

   EXPOSURE rises the entire time you are outside.
   The DECAY CLOCK runs from the PULL until you reach a decon station.
```

**Loop timing target:** 20–40 seconds per item at the low end, up to 3–4 minutes for a
top-tier artifact. Fast enough to feel like a clicker, slow enough that a rare find is an event.

### Step 1 — Sweep

Player walks a zone holding a detector. Detector emits pings that increase in rate and pitch
as they near a buried item — classic hot/cold. A radial sweep indicator on-screen shows
direction and a "signal strength" bar shows depth.

Detector tier determines:

* **Sweep radius** — how much ground you cover per second (pure speed).
* **Sensitivity floor** — the minimum rarity the detector can even register. A Bent Coil
detector physically cannot see a Reactor Core; it just won't beep. This is the key gate.
* **Depth range** — deeper items are rarer.
* **Signal clarity** — high-tier detectors show a rarity color on the ping before you
pull, so you stop wasting time hauling Scrap out of the ground.

### Step 2 — Pull

**Click-to-pull with a magnet.** Stand over the signal, aim down, and the magnet locks on.
Every click is a yank: the item lurches up through the soil a little, then the ground drags
it back down. A **depth bar** shows how far it still has to travel. Click fast enough that
your pulls outrun the drag and the item breaks the surface; stop clicking and it sinks.

This is the game's clicker beat, and it is deliberately physical — you can *feel* the weight
of a Reactor Core in your mouse hand in a way a hold-to-dig progress bar never conveys.

Magnet tier sets three things:

* **Pull force** — how much depth one click closes. This is the raw speed stat, and it is
what the player feels immediately: a better magnet means the same item takes half the clicks.
* **Draw** — passive lift between clicks. Low tiers have none, so the ground takes back what
you gained the instant you slow down. High tiers hold their ground and start pulling on
their own, which turns frantic mashing into steady, comfortable clicking. **Draw is the
comfort stat, and it's what people actually buy the top tiers for.**
* **Lock strength** — the **hard gate**. Every item has a mass; every deep-zone item is
half-fused into vitrified crust. Below the required lock strength the magnet snaps off the
item entirely and you get a failed-lock buzz. A Bent Horseshoe will never move a Reactor
Core no matter how fast you click. This is the gate that keeps deep zones honest — the
detector says *there is something here*, the magnet decides *whether you get it*.

Pulling is where **exposure** first spikes: the moment the item surfaces, it starts emitting.
The unearth moment is the game's little slot-machine pull — the item rips free with a magnetic
snap, ash bursts, a Geiger scream scaled to rarity, a colored aura, and a rarity banner.

**Why a magnet and not a shovel:** everything worth money out here is metal that soaked up
the fallout, so the tool that recovers it should be the one that grabs metal. It also makes
extraction an *active* input instead of a hold, which gives the loop a second skill beat
(the other being the clean, step 4) and gives the upgrade track something to sell beyond
"the bar fills faster" — it sells you your hand back.

**Mobile:** tap-to-pull, same math. Mobile players click slower, so **Draw** is tuned to be
generous enough that a mid-tier magnet is comfortable on a phone. Never balance the pull
around desktop mash rate — that quietly locks half the Roblox audience out of deep zones.

**It is also the moment the decay clock starts.** (§3.6) The banner that tells you what you
found also tells you how long you have to get it home.

### Step 3 — Haul (the run home)

Not a menu step — a *physical* one, and the reason movement speed is a real upgrade track (§5).

Everything you are carrying is emitting into you (§3.3) and getting hotter by the second
(§3.6). Base camp is behind you and the good dirt is ahead. This is the step where the
player's greed is actually charged interest, and it's what makes deep zones feel deep.

### Step 4 — Decontaminate (the new pillar)

The item goes to your **Decon Station** (a portable rig at the zone entrance, or a personal
one you upgrade). Cleaning is a **skill mini-interaction**, not a progress bar:

* The item is displayed with **contamination patches** — glowing hotspots on its surface.
* Player scrubs with the equipped cleaning tool. Tool has a **potency** rating; each patch has
a **hardness** rating derived from item rarity.
* **If tool potency < patch hardness, the patch will not clear.** This is the second hard gate:
you can *find* a rare item with a good detector but be unable to *sell* it without a
good scrubber. Uncleanable items sit in your **Quarantine Locker** as a visible taunt —
a strong pull toward the next cleaning upgrade.
* Cleaning grants **Decon XP** even on partial progress, so a failed attempt is not wasted.
* **Reaching any decon station stops the decay clock for good** (§3.6). The item is locked
at whatever stage it arrived in and is safe from then on. That permanence is the payoff
for the run home, and it's why the run is worth making.

**Cleaning tool line:** Wire Brush → Acid Sponge → Pressure Washer → Chem Bath →
Ultrasonic Rig → Ion Shower → Plasma Scour.

### Step 5 — Sell **or** Display

This is a fork, not a step, and it is the design's second real decision.

* **Sell** to the **Trader** at base camp: full cash, immediately, item gone.
An item sold *dirty* sells at **20%** — a deliberate escape valve so a player who is stuck
is never fully hard-blocked, just heavily taxed. This keeps the "I can't clean it yet"
frustration from becoming a quit moment.
* **Display** it in your **Exhibition** (§8): no cash now, but the item pays out forever,
attracts NPC visitors who pay more, counts toward set bonuses, and is *visible to every
other player on the server*.

Early game the answer is almost always sell — you need gear now and payback periods are long.
Late game the answer flips. The moment a player first chooses income over cash is the moment
they stop playing a digging game and start playing a *collection* game, and collection
players are the ones who stay for months.

### Step 6 — Upgrade

Cash buys the six upgrade tracks (§6). Better gear opens deeper zones, faster hauls, and
bigger exhibits. Deeper zones hold rarer items. Rarer items are worth more — as cash or as
income. Loop closes.

\---

## 3\. The Radiation System

This is the design's spine and what separates it from every other dig game.

### 3.1 Player Exposure (rads)

A rad meter fills as you spend time in a zone. Rate is:

```
rads/sec = (zone base rate)
         + (sum of carried items' current emission)   ← rises over time, §3.6
         - (suit mitigation)
         - (level-earned resistance)
```

Four consequences that all matter:

|Exposure|Effect|
|-|-|
|0–50%|Nothing. Clean play.|
|50–80%|Screen vignette greens, Geiger click bed rises, footsteps slow slightly.|
|80–99%|Vision distorts, audio muffles, heartbeat, detector pings get noisy/false positives.|
|100%|**Blackout.** You wake at base camp. You keep cash, gear and anything displayed; you **drop your uncleaned carry**.|

Blackout is deliberately *not* a death with a hard penalty — losing progress in a casual
Roblox digging game kills retention. Losing the dirty backpack you were greedily hauling
is exactly the right sting: it punishes greed, not existence.

**Dropped carry is recoverable-ish.** The bag stays on the ground where you fell for
90 seconds, glowing and visible server-wide. You can sprint back for it. So can anyone else.
That is a *fantastic* free social system and costs almost nothing to build.

### 3.2 Decontamination showers

Free rad-flush stations at each zone entrance and at base camp. Instant, no cost.
Their placement is a level-design lever: deep zones put the shower *far* from the good dirt,
so a run into the hot core is a genuine round-trip commitment.

Showers flush **your** exposure. They do **not** clean items and they do **not** stop the
decay clock — only a Decon Station does that (§3.6). Keeping these two things separate is
important: it means "I'm fine" and "my loot is fine" are two different problems, and a player
can be safe while their backpack is quietly rotting.

### 3.3 Carrying hot items — the Greed Dial

Every uncleaned item in your bag adds to rads/sec, scaled by rarity **and by how long you've
been carrying it**. This creates the **greed dial** — the single best moment-to-moment
decision in the game:

> "I've got four hot items, one of them's been out of the ground ninety seconds and it's
> starting to cook, and a Reactor Core just pinged two meters away.
> Do I run back now, or push one more pull?"

That decision repeating every 60 seconds is the retention engine. The decay clock (§3.6)
is what stops the answer from always being "push one more."

### 3.4 Hazmat suits — three stats, not one

Suits are the most important purchase in the game and carry three separate stats:

|Stat|What it does|
|-|-|
|**Mitigation**|Flat rads/sec subtracted. The obvious one.|
|**Capacity**|How many hot items you can haul before the rate becomes unmanageable. This is the inventory system, expressed as radiation instead of slots.|
|**Tolerance**|The rads/sec ceiling the suit can physically handle before it starts **failing** and you start taking direct damage. (§3.5)|

Tolerance is the new one and it is what replaces the old zone lock. A suit doesn't say
"you may not enter Zone 4." It says "above 15 rads/sec I start to come apart, and so do you."

### 3.5 Over-Tier Zones — no walls, just consequences

**There are no locked doors in this game.** Every zone is walkable from minute one.
Borders are fences with holes in them, collapsed checkpoints, and a lot of very clear
warning signage. Nothing stops you. This is a deliberate reversal of the standard Roblox
"buy the gamepass to enter Zone 4" wall, and it buys three things:

1. **It reads as a real place.** A world where you physically cannot walk down a road is a
menu with trees. A world where you can walk down the road and die is a world.
2. **It teaches by consequence, not by refusal.** A player who sprints into the Exclusion
Belt at level 3, watches their screen go white and wakes up at base camp has learned more
about the game in eight seconds than any tooltip could teach them — and they had *fun*
doing it.
3. **It creates the gamble.** Which is the actual point. See "The Dive," below.

#### Suit failure and radiation burn

When incoming rads/sec exceeds your suit's **tolerance**, two things happen on top of normal
exposure:

```
excess          = zone rate − suit tolerance
exposure gain   = normal accrual + (excess × 2)      ← the meter fills brutally fast
health burn     = 2 HP/sec for every 10 rads/sec of excess
```

Health burn is the honest, physical signal. It is not subtle:

* Screen edges char and bloom white, not green — a **different** color language from normal
exposure, so the player instantly knows this is a category change, not a degree change.
* The suit alarm is a continuous shriek, distinct from the Geiger bed.
* Controller/camera shake scaling with excess.
* Your own footsteps and breathing get louder as external audio drops away.

**And a countdown.** The HUD shows `SUIT FAILING — SURVIVABLE: 0:14`, ticking down in real
time, recalculating as you move. This is the single most important UI element in the section.
The risk must be **informed**, not hidden. A gamble where you can't see the odds isn't a
gamble, it's a trap, and traps make people quit. Show the number and let them choose.

#### Survivability at a glance

Rough survivable window walking into a zone with a given suit tier
(assumes full health, no items carried, standing still):

|Zone|Rated suit|One tier under|Two tiers under|Cloth wrap / unsuited|
|-|-|-|-|-|
|1 Ash Flats|indefinite|—|—|indefinite|
|2 The Suburbs|indefinite|\~2:30|—|\~50s|
|3 Fallout Fields|indefinite|\~1:10|\~30s|\~18s|
|4 The Exclusion Belt|indefinite|\~40s|\~15s|\~8s|
|5 Reactor Grounds|indefinite|\~25s|\~9s|\~3s|
|6 The Crater|\~90s|\~8s|\~2s|instant|

Read the "one tier under" column as the design's actual target. **\~25–40 seconds is a pull.**
That is not an accident — it is tuned to be exactly enough time to sprint in, take one
signal, extract it, and run. Which is the gamble.

#### The Dive — risking health for rarer items

A **Dive** is a deliberate over-tier run: go somewhere your suit isn't rated for, take one
or two signals from a much better item pool, and get out before the meter or your HP runs out.

Why it works as a system:

* **The reward is real and needs no artificial bonus.** A Zone 4 item pulled by a Zone 2
player is genuinely worth an order of magnitude more than anything in their normal loop.
The zone's own loot table is the prize. Resist the urge to add a "bravery multiplier" on
top — the temptation to over-reward this is the fastest way to break the economy.
* **It is self-balancing, and this is the elegant part.** A dived item is still an
*uncleaned* item, and a Zone 4 item's contamination hardness will almost certainly exceed
a Zone 2 player's scrubber. So a successful dive usually produces a **Quarantine Locker**
entry (§10.2) — a trophy you can see, can't clean, and can only dirty-sell at 20%.
The dive pays out *some* cash immediately and creates *enormous* upgrade motivation.
It lets a bold player punch above their tier without letting them skip the economy.
* **It fails loudly and cheaply.** Blackout costs you the bag, not your progress. The
failed dive is a story ("I had it, I had it, I was ten meters from the fence") and stories
are what get clipped.
* **It scales with skill forever.** A max-gear player dives the Crater. The dive is not a
low-level trick; it's a permanent skill ceiling that sits on top of the gear ceiling.

**Design guards on the Dive:**

* Deep-zone item pools should never contain items whose contamination hardness is *below*
the zone's rated cleaning tool tier — otherwise diving becomes strictly optimal.
* Health regenerates out of radiation, slowly, and fully at base camp. No healing items in
the field for MVP; a consumable stim is a natural later addition and an obvious monetization
hook, but it needs a hard cooldown or it eats the whole tension of this section.
* Radiation burn cannot kill you outright — at 0 HP you black out exactly as at 100%
exposure. **This game has no death, only failure to bring things home.** That is a tonal
commitment worth protecting.

### 3.6 The Decay Clock — get it home in time

The single biggest change to the loop's pacing. **An item that leaves the ground starts
waking up.**

Underground, packed in soil, an artifact is shielded and stable. Exposed to air it heats up:
it emits more into you every second, and its own value degrades as it cooks.

#### Stages

Every unearthed item has a **fuse length (T)** set by its rarity. It moves through four stages:

|Stage|Window|Emission|Value retained|Look / sound|
|-|-|-|-|-|
|**Fresh**|0 → T|×1|100%|Faint glow, slow tick|
|**Hot**|T → 2T|×2.5|90%|Visible aura, item icon pulses amber, tick doubles|
|**Critical**|2T → 3T|×5|55%|Item vents steam, icon flashes red, alarm chirps every 3s|
|**Slag**|past 3T|×8|10%|Item model visibly deforms and dulls. Cannot be displayed, ever.|

Two things worth noticing about that table. First, the value bleeds **gradually** — you watch
it drain rather than losing everything at a buzzer. Watching a number fall is far better
tension than a binary timer, and it means every second of the run home has a felt cost.
Second, emission climbs *faster* than value falls, so a decaying item is actively trying to
kill you before it becomes worthless. The bag gets heavier the longer you hesitate.

#### Fuse length by rarity

|Rarity|Fuse (T)|Time to Slag|
|-|-|-|
|Scrap / Common|5:00|15:00|
|Uncommon|4:00|12:00|
|Rare|3:00|9:00|
|Epic|2:30|7:30|
|Legendary|2:00|6:00|
|Mythic|1:30|4:30|
|Anomaly|1:15|3:45|

**Rarer items burn faster.** This is the whole point of the mechanic and it's worth being
explicit about why: it inverts the greed dial exactly when the greed dial matters most.
Common junk you can carry all day. The Legendary you just pulled is a live grenade — and it
pulled *you* into the deepest zone in the first place. The best find of your session is the
one that gives you the least time to enjoy having found it.

That is the moment the whole game is for. The Geiger scream, the banner, the rarity color —
and then a two-minute timer starts and you are very far from home.

#### Rules

* **Reaching a Decon Station stops the clock, permanently.** Docking an item at any station —
or racking it in the Quarantine Locker (§10.2) if you can't clean it yet — locks in
whatever stage it arrived at. Cleaning it afterwards is unhurried. **Getting it home is
the win condition; what you do with it next is your business.** Be generous here: the run
is the challenge, and turning "clean your backlog before it rots" into a second chore
would sour a mechanic that works because it's short and sharp.
* **Nothing else stops it.** Not your backpack, not standing still, not reading a menu, and
not the decontamination shower (§3.2) — the shower saves *you*, not your loot. Two
different problems, deliberately.
* **Being in base camp is not the same as being at the rig.** The clock runs until the item
is docked, and in the later zones the walk from the gate to the station is not short.
* **Slag is not zero.** It sells for a token amount and still grants full Decon XP and
discovery credit for the collection (§10.10). A wasted run is never a *fully* wasted run —
that's the anti-frustration floor this mechanic needs to stay fun rather than punishing.

#### Interaction with everything else

* **With the Dive (§3.5):** a dive isn't over when you clear the fence. You pulled a Zone 5
item with a 2-minute fuse and you're four zones from home. The dive's real difficulty is
the *exit*, which is a much better design than making the entrance hard.
* **With movement (§5):** this is what makes speed a genuine power stat rather than comfort.
Boots convert directly into value retained.
* **With the Exhibition (§8):** Slag can never be displayed. If you want the collection,
you have to run. Completionists — the most durable audience segment — now have a reason to
care about a mechanic that would otherwise only tax the economy players.

### 3.7 Containment gear — the mitigation layer

Because §3.6 is harsh, it needs answers the player can buy. All of these are earned, and all
of them create new decisions rather than removing the old one:

* **Lead-Lined Satchel** (upgrade line, 5 tiers): slows the decay clock by 15% / 30% / 45% /
60% / 70%. The single most-wanted item in the game by hour three. Note it slows, never
stops — a floor of tension always survives.
* **Containment Cell** (consumable): freezes one item's clock for 3 minutes. Bought in
stacks. This is the "I found something incredible and I need to not lose it" panic button,
and players will pay real money for it, which makes it the cleanest monetization in §11.
* **Field Decon Kit** (consumable): a single-use portable Decon Station. Cleans one item at
your current tool potency, wherever you are. Expensive. Turns a doomed run into a saved one.
* **Cold Packing** (perk, §9): the first item you unearth each trip gets a ×2 fuse.
* **Rail network** (§5.3): the structural answer. Not a consumable — a permanent, world-visible
reduction in travel time that the player builds themselves.

\---

## 4\. Zones (The Wasteland)

Six zones radiating outward from base camp toward the crater. Each is visually distinct,
has its own item pool, base rad rate, and soil hardness.

**None of them are locked.** The "suit" column below is what the zone is *rated* for —
the tier at which it becomes farmable rather than survivable. Every zone is enterable at
any time by anyone willing to pay for it in health. (§3.5)

|#|Zone|Base rads/s|Rated suit|Unsuited survival|Flavor|Signature items|
|-|-|-|-|-|-|-|
|1|**Ash Flats**|0.5|Cloth Wrap|indefinite|Grey dust, dead trees, tutorial ground|Bottle caps, rebar, coins|
|2|**The Suburbs**|2|Rubber Suit|\~50s|Collapsed houses, half-buried cars|Jewelry, tools, family heirlooms|
|3|**Fallout Fields**|6|Lead-Lined|\~18s|Green haze, glass-fused soil, sirens|Military tags, ordnance, gold|
|4|**The Exclusion Belt**|15|Reinforced Hazmat|\~8s|Concrete barriers, tipped choppers, silence|Prewar tech, lab samples|
|5|**Reactor Grounds**|40|Sealed Exo-Suit|\~3s|Cooling towers, visible heat shimmer|Fuel rods, control tech, black-box data|
|6|**The Crater**|100|Containment Rig|instant|Glassed floor, sky-glow, no ambient sound|Anomalies, one-of-a-kind relics|

### Zone design rules

* **Every zone keeps a full rarity range**, just with shifted odds. A Zone 1 player can
hit a 1-in-50,000 legendary. That "it could happen right here" chance is what keeps early
players sweeping instead of quitting.
* **Borders are visible and legible, never solid.** A rusted fence with a hole in it. A
toppled checkpoint. A hand-painted sign that says DON'T. Crossing one triggers a full-screen
warning card with the survivability number (§3.5) and then gets out of the way. No
confirmation dialog — asking "are you sure?" kills the impulse that makes this fun.
* **Distance to the nearest decon station scales super-linearly with zone number.** This is
the primary lever on run tension and it should be tuned before rad rates are. Zone 5's
station should be a genuinely intimidating distance from Zone 5's good dirt.
* **Hot pockets:** each zone has 2–3 roaming high-radiation patches (visible as heat shimmer

  * audible Geiger spike). They triple the rad rate but also triple the rarity roll.
Voluntary risk, clearly telegraphed. This gives skilled players a way to punch above
their gear tier *inside* their own zone, the same way the Dive lets them punch above it
outside — same verb, two scales.
* **Zone 6 stays special by physics, not by permission.** Even a full Containment Rig only
buys \~90 seconds inside, and Anomalies carry a 1:15 fuse, so a Crater run is a timed heist
with a live bomb in your hands. It never becomes a farm, at any gear level, forever.

\---

## 5\. Movement, Speed \& Extraction

The decay clock (§3.6) turns distance into money, so movement stops being flavor and becomes
a **first-class upgrade track**. It is also the single biggest quality-of-life lever in the
game: without it, a deep run is a walking simulator with a stopwatch, and that is a real risk
worth designing against directly.

### 5.1 The Boots line

Six tiers, same pricing curve as everything else (§6):

**Taped Boots → Tread Boots → Field Runners → Servo Braces → Powered Frame → Strider Rig**

Each tier moves four stats, so an upgrade is always felt on multiple axes:

|Stat|What it does|Why it matters|
|-|-|-|
|**Walk speed**|Base movement|The floor. Affects every second of play.|
|**Sprint + Stamina**|Burst speed on a drainable meter that refills when walking|Makes the run home an *active* skill, not a hold-forward. Lets a player spend a resource to save an item.|
|**Haul penalty**|Reduces the slow applied per carried hot item|The key one. See below.|
|**Traversal**|T3 unlocks vault/climb over rubble; T5 unlocks a short dash|Turns level geometry into skill expression — good players learn the fast lines out of Zone 5.|

**The haul penalty is the important stat.** Carrying hot items should physically slow you
down — a full bag is heavy and you are visibly staggering. This creates the tradeoff that
makes capacity interesting: more items means more rads, more decay risk, *and* a slower run
home to deal with all of it. Better boots erase the penalty, which is why the boots track and
the suit track want to be bought in alternation rather than straight down one line.

Without the haul penalty, capacity is just a bigger number. With it, capacity is a decision.

### 5.2 Speed as a balance problem

Speed multiplies everything: more ground swept per minute, faster round trips, more value
retained on the decay clock, longer effective dive windows. It is the most economically
dangerous track in the game and should be priced as the most expensive per unit of stat.

Three guards:

* **Cap total movement speed** well below "the wasteland feels small." The round trip has to
stay a commitment or §3.6 stops meaning anything.
* **Sprint costs stamina, stamina does not scale as fast as speed.** Top-tier boots make you
fast in bursts, not permanently fast. Preserves the decision.
* **Deep-zone station distances scale with expected player boot tier.** As the player gets
faster, the deep zones get further. Net tension stays flat; net *comfort* rises, which is
exactly the right outcome — the player feels the upgrade without the game getting easier.

### 5.3 The Rail Network — the structural answer

The best version of "make the walk shorter" isn't a speed number, it's **infrastructure the
player restores themselves**.

Each zone contains a derelict **extraction rail station**. Find and pull its three missing
parts (they're zone-specific items in the normal loot table, uncommon-tier, so you'll get
them incidentally while doing everything else), and the line comes online — permanently,
for you, and **visibly for the whole server**. Lights come on. The car starts moving. A
piece of the wasteland is no longer dead.

Rules:

* Rail runs **one way only: outward zone → base camp.** It is an *extraction* line, never a
commute. You always walk in and you can always ride out. This preserves the entire tension
of the trip in while removing the tedium of the trip back.
* Riding does **not** pause the decay clock — it just beats it. Speed is the point.
* Repairing a station is the best-feeling long-term goal in the game that isn't a gear
purchase, and it makes the world visibly improve as a result of play. Roblox players share
screenshots of things they built. Give them things to build.

### 5.4 Extraction Beacon (consumable)

Instant teleport to base camp, with a hard 5-minute cooldown and a real cash cost.
This exists specifically so that "I found an Anomaly with a 1:15 fuse in the Crater" has an
answer. Losing the rarest item in the game to a timer is the single most likely rage-quit
moment in this design (§16), and this is its pressure valve.

Deliberately: it is a *cash* purchase before it is a Robux one, so a free player always has
the answer available.

\---

## 6\. Upgrade Tracks

Six parallel tracks. The player is always saving toward *something*, and the tracks
deliberately gate different things so no single purchase trivializes the game.

|Track|Gates|Tiers|Feels like|
|-|-|-|-|
|**Detector**|*what you can find*|8|Discovery|
|**Magnet**|*how fast you extract, and what you can lift at all*|6|Speed / comfort|
|**Cleaning tool**|*what you can sell*|7|Unlocking your locker|
|**Hazmat suit**|*how long you survive, and how far over-tier you dare go*|6|Territory \& nerve|
|**Boots**|*how much of what you found survives the trip*|6|Freedom|
|**Satchel**|*how long the clock gives you*|5|Breathing room|

Plus one non-gear track: **Exhibit pedestals** (§8.4), bought with cash, which gates how much
passive income you can have running at once.

### Detector line

Bent Coil → Scavenger MkI → Surplus Geiger → Pulse Array → Isotope Scanner →
Resonance Mapper → Deep Core Array → **The Oracle**

### Magnet line

Bent Horseshoe → Salvage Magnet → Ferrite Coil → Electromagnet Rig → Servo Winch →
**Superconductor Core**

### Cleaning tool line

Wire Brush → Acid Sponge → Pressure Washer → Chem Bath → Ultrasonic Rig → Ion Shower →
Plasma Scour

### Suit line

Cloth Wrap → Rubber Suit → Lead-Lined → Reinforced Hazmat → Sealed Exo-Suit → Containment Rig

### Boots line

Taped Boots → Tread Boots → Field Runners → Servo Braces → Powered Frame → Strider Rig

### Satchel line

Canvas Bag → Lined Pack → Lead Satchel → Shielded Case → Containment Pack

### Pricing philosophy

* Each tier costs roughly **2.4×** the previous. Sub-3× keeps upgrade cadence frequent.
* The **first** upgrade in every track is cheap (under 90 seconds of play). Players must feel
the upgrade dopamine inside their first two minutes or they leave.
* Tracks should be affordable in **rotation**, not in parallel. The natural rhythm is
"find better things → now clean better things → now survive longer → now get home faster."
Price them so a player who buys straight down one track hits a visible wall.
The wall is the teaching mechanism.
* **Six tracks is a lot.** Do not show all six at once. Reveal them in the order the player
first *feels the pain* they solve: detector and magnet at minute one, cleaning tool at the
first uncleanable item, suit at the first border, boots at the first item that reaches Hot
in the player's hands, satchel at the first item lost to Slag. A track introduced by a
frustration the player just personally experienced sells itself.

\---

## 7\. Items \& Rarity

### Rarity tiers

|Tier|Color|Base odds (Zone 1)|Contam. hardness|Fuse (T)|Value band|
|-|-|-|-|-|-|
|Scrap|Grey|55%|1|5:00|$1–5|
|Common|White|28%|1|5:00|$5–25|
|Uncommon|Green|12%|2|4:00|$25–120|
|Rare|Blue|4%|3|3:00|$120–700|
|Epic|Purple|0.8%|4|2:30|$700–4k|
|Legendary|Orange|0.15%|5|2:00|$4k–30k|
|Mythic|Red|0.04%|6|1:30|$30k–250k|
|**Anomaly**|Prismatic|0.002%|7|1:15|$250k–2M|

Odds shift heavily toward the top as zone number increases; by Zone 6, Scrap is under 5%.

Three gates now sit on the same rarity number, which is why one column can drive the whole
game: **hardness** decides whether you can clean it, **fuse** decides whether you can get it
home, and the zone it spawns in decides whether you can survive collecting it. A rare item is
hard to find, hard to keep, and hard to finish — and the player understands all three from a
single color.

### Item modifiers (rolled on top of rarity)

These multiply the item's value and give players something to chase *within* a rarity tier —
the reason a veteran still cares about a Common drop.

* **Pristine** (×2) — no rust, cleans faster. Displays at ×1.3 yield.
* **Irradiated** (×3, rads ×2, **fuse ×0.6**) — glows visibly; risky to carry, worth the burn.
The purest expression of the whole design: the best modifier is also the worst one to hold.
* **Fused** (×2.5) — melted into another object; needs one extra decon pass.
* **Prewar Sealed** (×4) — still in packaging. **Sells as-is, no cleaning needed, and the
seal means it does not decay** — the clock never starts. Jackpot feel, and a genuine
moment of relief on a hot run.
* **Cracked** (×0.4) — damaged. The bad roll, so good rolls mean something.
* **Slagged** (×0.1) — not rolled; *earned*, by letting the clock run out (§3.6). The only
modifier the player inflicts on themselves, and the reason the others feel like luck.

### Item catalogue direction

Roughly 120 items at full scope, themed per zone. Bias toward objects that carry a *story*
in one line of flavor text — "Child's lunchbox, dented, still latched" hits far harder than
"Rare Metal Object #7." Collection UI shows flavor text on discovery. Cheap, high-impact.

**Write the catalogue with the Exhibition in mind (§8).** Every item should have an
*audience*: a thing a scientist would want to study, a thing a collector would want to own,
or a thing a scavenger would want to use. Tag each item with one of those three appeals when
it's written. That single tag is what turns 120 items from a loot table into a museum.

\---

## 8\. The Exhibition — Display as an Income Engine

### 8.1 The idea

Selling an item is a transaction. **Displaying it is an investment.**

Every cleaned item can go on a pedestal in your **Exhibition** — a personal plot at base camp
that other players can walk through. A displayed item pays out continuously, forever, and
draws NPC visitors who pay more on top of that. It also sits there where everyone can see it,
which is the part that actually drives behavior.

Why this belongs in the design:

* **It gives the loot table a second axis.** Right now every item resolves to one number:
cash. With the Exhibition, an item has a *sale price* and a *display value*, and those two
don't rank items in the same order. Suddenly there are items worth keeping that aren't the
most expensive ones, and "what should I do with this" becomes a real question.
* **It converts an action game into an idle game without becoming one.** Passive income is
the single strongest retention mechanic on Roblox, and this is a version of it that is
*earned by play* rather than bought. You can't buy income; you have to go get it.
* **It makes the shared server matter.** Right now the shared server is scenery — you see
other players and nothing else. An Exhibition Row means you *see what other people found*,
permanently, and that is the strongest possible advertisement for the deep zones.
* **It answers "what is the point of a Mythic."** A Mythic sells for money you'll spend and
forget. A Mythic on a pedestal is a landmark on the server with your name under it.

### 8.2 Yield math

Base rate is a **percentage of the item's sale value paid out per minute**, and it decreases
as rarity rises:

|Rarity|Base yield / min|Payback at base|Role|
|-|-|-|-|
|Scrap / Common|2.0%|\~50 min|Income filler|
|Uncommon|1.8%|\~56 min|Income filler|
|Rare|1.5%|\~67 min|Balanced|
|Epic|1.2%|\~83 min|Balanced|
|Legendary|0.8%|\~2:05|Prestige|
|Mythic|0.5%|\~3:20|Prestige|
|Anomaly|0.25%|\~6:40|Landmark|

This curve is doing deliberate work, and it produces the design's nicest emergent behavior:
**cheap items are your income, rare items are your prestige.** A veteran's exhibit is a wall
of humble Commons quietly printing money, anchored by one Legendary that pulls the crowd in.
That is a much more interesting-looking room than eight of the same expensive object, and it
gives the bottom 80% of the loot table a permanent reason to exist.

**Multipliers** stack on the base rate, up to roughly ×4 total:

|Multiplier|Range|Source|
|-|-|-|
|**Vitrine tier**|×1.0 → ×2.0|Pedestal upgrade (bare plinth → lit case → sealed display)|
|**Set bonus**|×1.1 → ×1.5|Themed groups (§8.5)|
|**Traffic**|×0.5 → ×2.0|Driven by Prestige (§8.3)|

So a fresh player's first displayed item pays back in about an hour of play — correctly bad.
A built-out exhibit pays back in \~15–20 minutes — correctly excellent, and it took real
investment to get there.

**Duplicate damping:** a second copy of the same item yields 40%, a third 15%, a fourth and
beyond 5%. You cannot farm one good item into an income machine. Breadth beats depth, which
pushes players back into zones they've "finished."

**Offline earnings:** accrue at **25%** of your online rate, banked up to **4 hours**
(8 with a gamepass). Enough that logging in tomorrow is rewarding, capped low enough that
logging in tomorrow *and playing* is much better. This is the single most valuable retention
number in the document and should be tuned aggressively in live data.

### 8.3 Prestige and visitors

**Prestige** is the exhibit's score: the sum of displayed items' values, weighted upward by
rarity and set bonuses. It drives two things — the **traffic multiplier** above, and **which
visitors show up**.

Visitors are NPCs that spawn at your plot, walk the room, stop in front of individual
pedestals, and react. They are the readable, physical version of a number going up, and they
should be the reason a player stands in their own exhibit watching instead of leaving.

|Visitor|Drawn to|Pays in|
|-|-|-|
|**Tourists**|Nothing specific — pure prestige volume|Small, constant admission. The baseline hum.|
|**Researchers**|Lab samples, prewar tech, fuel rods, black-box data, Anomalies|**Research grants**: cash lump sum + a large XP payout. Occasionally leave a **Data Cache** (10 min of ×2 luck).|
|**Collectors**|Pristine, Prewar Sealed, heirlooms, story items|High admission, and **buyout offers** (§8.4).|
|**Gearheads**|Tools, detectors, military kit, ordnance|Small frequent tips, plus **parts**: a 15% discount voucher on your next purchase in one upgrade track.|
|**Rival Curator**|High-prestige exhibits only|Issues a themed challenge ("show me three Fallout Fields military pieces by tomorrow") for a large payout. Ties into Field Contracts (§10.14).|

Researchers are the load-bearing one for the fantasy the pitch promises — *scientists come to
look at what you dug up*. Give them the best behavior: they linger longest, they bring
equipment, they talk to each other in front of your best piece, and their grant popup should
be the single most satisfying passive-income moment in the game.

### 8.4 Buyout offers — the second greed dial

Periodically a Collector will offer to buy a specific displayed item outright, at
**3–8× its base sale value**. The offer stands for a few minutes and then leaves.

The player chooses: take a windfall that would take hours to earn passively, or keep the
piece, the income, the set bonus and the prestige.

This is the same shape as the §3.3 greed dial moved into the metagame, and it's what stops
the Exhibition from being a fire-and-forget system. It also gives the player an out — if you
display something and regret it, the game will eventually offer you a very good exit.

**Rule:** never offer a buyout on an item that's the last piece of a completed set, or on an
Anomaly. Some things should be un-sellable so the player can feel that they're un-sellable.

### 8.5 Pedestals, vitrines and sets

* **Pedestal slots** start at **3** and upgrade with cash to a cap around **40**. This is the
seventh purchase track and the one that keeps mattering after gear is maxed — the natural
endgame money sink.
* **Vitrine tiers** upgrade individual pedestals: bare plinth → lit stand → glass case →
sealed containment display. Yield multiplier plus a real visual upgrade to the room.
* **Sets** are themed groups defined in the item catalogue — "Suburban Kitchen," "Field
Medicine," "Reactor Control," "Children's Toys." Completing one lights a plaque, adds a
yield multiplier to every item in it, and permanently increases luck for that set's zone.
This is where the Exhibition and the Museum (§10.10) merge into one system rather than two
overlapping ones.
* **Layout is free.** Let players place pedestals where they want. Zero gameplay value,
enormous ownership value, and it costs one drag interaction to build.

### 8.6 The Row — exhibits are public

All player exhibits sit in a **Row** along base camp's main street: open plots, walk-in,
no permission needed. Anyone on the server can wander through anyone's collection.

* **Tip button** on another player's exhibit. Costs the tipper a trivial amount, pays the
owner meaningfully, and gives both a small XP bump. Cheap goodwill machine.
* **Most-visited exhibit** on the weekly leaderboard, next to richest and deepest run.
* Displayed **Anomalies are announced server-wide** when first placed, with a pin on the map
pointing at the plot. The rarest item in the game becomes a *destination*.
* A visitor walking someone else's Row sees flavor text on hover — which means the item
catalogue's writing does double duty as the game's best marketing surface.

### 8.7 Guards

* **Displayed items are locked from selling** while displayed. Pulling one off has a 60-second
"crating" delay — enough friction to stop churn-optimizing, not enough to be annoying.
* **Slag cannot be displayed, ever** (§3.6). This is the mechanic's main hook into the
collection game.
* **Income is capped per real-time hour** at a value tied to your Contractor Level, so a
lucky early Legendary can't fund the whole midgame while the player is AFK.
* **Nothing displayed is ever lost.** Blackout, decay, dives — none of it touches the exhibit.
It is the one permanently safe place in the game, and that safety is exactly what makes it
emotionally worth filling.

\---

## 9\. Progression \& Leveling

Two progression currencies so that unlucky sessions still advance the player.

### 9.1 Cash — the horizontal axis

Buys gear. Directly gated by luck and rarity. Volatile by nature. Now also flows in
passively from the Exhibition (§8), which smooths the volatility for players who have
invested in it — a deliberate reward for the collection path.

### 9.2 Contractor Level (XP) — the vertical axis

XP is earned from **actions**, not luck: pulling items, completing cleans, discovering a new item
for the first time, surviving high-exposure runs, surviving an over-tier dive, and hosting
exhibition visitors. A player who finds nothing good still levels. This is the
anti-frustration floor.

Level rewards, every level:

* **+1% base rad resistance** (compounding, capped at 40%) — long-term power that
no purchase provides, and the thing that slowly makes over-tier dives survivable.
* Every 5 levels: **+1 carry capacity**.
* Every 10 levels: a **perk choice** (pick 1 of 3), e.g.:

  * *Steady Hands* — cleaning tool potency +1 against a single patch per item.
  * *Bloodhound* — detector shows rarity color one tier earlier.
  * *Iron Lungs* — blackout threshold raised to 120%.
  * *Scrapper* — Scrap-tier items auto-sell on pickup, no rad cost.
  * *Hot Handler* — Irradiated modifier gives ×4 instead of ×3.
  * *Cold Packing* — the first item you unearth each trip gets a ×2 fuse. (§3.7)
  * *Second Wind* — one free 25% health restore per trip when suit failure begins. (§3.5)
  * *Curator* — +15% exhibition yield and visitors linger longer. (§8)
  * *Sure Footing* — haul penalty halved. (§5.1)

Level cap 100, with a long tail so a whale-hour player still has runway.

### 9.3 Rebirth — "Decontamination Protocol"

At Level 50 + full gear in any track, the player may **Decontaminate**: reset cash, gear
and level in exchange for **Clean Tokens**.

**The Exhibition does not reset.** Your collection is the one thing that survives a rebirth,
which makes it the true long-term progression and makes the decision to display something
much heavier than the decision to sell it. This one rule does more retention work than any
multiplier in the list below.

Clean Tokens buy permanent multipliers that never reset:

* Sell value ×
* Rarity luck ×
* Pull force ×
* Rad resistance flat %
* Decay clock slowdown %
* Exhibition yield ×
* **Cosmetic suit skins** — the visible status symbol on a shared server. This is where
the social pressure lives, and it's the reason to rebirth more than once.

Rebirth 1 should take \~4–6 hours of play. Each subsequent one gets faster because the
multipliers compound — the standard, proven Roblox curve.

\---

## 10\. Interesting Features (the differentiators)

These are what get the game clipped and shared. Ranked by expected impact.

### 10.1 The Greed Dial — *core*

Already described in §3.3. The single mechanic the whole game is built around. Not a feature
so much as the reason the game exists.

### 10.2 Quarantine Locker — *core*

A visible, physical rack at your base of items you found but **can't clean yet**. Each one is
labeled with the tool tier required. It is a wish list made of your own bad luck, and it is
the strongest upgrade motivator in the design. Players will grind specifically to empty it.

Now doubly important: the Locker is where successful **Dives** (§3.5) land, so it fills up
with trophies from places you had no business being. It becomes a record of your nerve as
much as your luck.

### 10.3 The Dive — *core*

Walking into a zone you can't survive, taking one signal, and running (§3.5). No unlock, no
gamepass, no permission — just a countdown on your HUD and a decision. It's the highest-skill
expression in the game, it's available from minute one, and it's free to build because it
consists entirely of *not* putting up a wall.

### 10.4 The Decay Clock — *core*

Items wake up when they leave the ground and cook themselves into worthlessness if you
dawdle (§3.6). Converts the walk home from dead time into the tensest part of the loop, and
makes the rarest finds the most stressful — which is exactly backwards from every other
digging game and exactly right for this one.

### 10.5 Hot Pockets — *core*

Roaming radiation surges. Telegraphed, voluntary, high-risk/high-reward. Lets skill and
nerve substitute for gear inside your own zone, the same way the Dive does outside it.

### 10.6 The Row — *social*

Every player's exhibit is a walk-in plot on base camp's main street (§8.6). The shared server
stops being scenery and becomes a museum district. Tipping, hover-flavor-text, most-visited
leaderboards, and Anomaly pins on the map.

### 10.7 Geiger Audio as the Primary Feedback Channel

Commit to sound. The detector ping, the item's own emission, the decay-stage alarm, the
suit-failure shriek, the ambient zone bed, and the danger warning are six distinct layers of
clicking and tone. A skilled player should be able to play with their eyes half-closed. This
is cheap to build and is the thing that will define the game's identity in clips.

### 10.8 Fallout Storms — *server event*

Every \~20 minutes, a server-wide storm rolls in. 90-second warning siren, then:

* All zone rad rates ×3.
* Rarity odds ×5.
* **Decay clocks run at double speed.**
* Fresh items are seeded into the ground (the storm "uncovers" things).

Players choose: shelter in the bunker (safe, zero income) or ride it out (huge income, real
blackout risk). Because it's server-wide, it creates a shared moment — everyone in the
server is simultaneously making the same decision, and that's what makes a shared server
feel alive rather than parallel.

The doubled decay clock is what makes storms *hard* rather than just lucrative — during a
storm, the rarest drops in the game have a sub-40-second fuse, and everyone is sprinting.

### 10.9 The Beacon — *social*

When any player unearths a Legendary or above, a light pillar shoots up from the extraction site,
visible server-wide, with their name announced. Everyone knows. Free social proof, free
aspiration, free "I want to be that guy."

And now: the beacon marks a spot where someone is currently carrying something enormous on a
two-minute fuse, very far from home. Everyone watches to see if they make it. That's a
spectator moment generated by systems already built.

### 10.10 Museum / Collection Wall

Base camp gallery of every item you've discovered, per zone, with flavor text. Completion of
a zone set grants a permanent luck bonus in that zone. Completionists are the most durable
segment of a Roblox audience; give them a wall.

The Museum is *discovery* (have you ever held it) and the Exhibition (§8) is *possession*
(do you still have it, on display, right now). Keeping them separate means the completionist
and the curator are two different long games running on the same item catalogue.

### 10.11 Anomalies — *long tail*

Prismatic-tier one-off items with unique models, unique names, and a **server-wide
announcement plus a permanent entry on the museum wall** listing who found it and when.
Roughly one per server-week. The rarest thing in the game should leave a permanent mark on
the world, not just a number in a wallet.

With §3.6 in play, an Anomaly is a 1:15 fuse in the deepest zone in the game. Recovering one
successfully should be, and will be, the hardest thing anyone does in this game.

### 10.12 Rail Network — *world progression*

Repairable one-way extraction lines out of each zone (§5.3). The world visibly improves
because of the player's work, and the improvement is permanent and shared.

### 10.13 The Assay Bench — *depth*

Before cleaning, an item can be **assayed** for a small fee: reveals its modifiers, exact
value, and **exact remaining fuse**. Lets experienced players triage under pressure — dump
the Cracked one, sprint the Irradiated one home first. A small system that rewards knowledge,
and much more valuable now that there's a clock to triage against.

### 10.14 Field Contracts — *retention*

Rotating daily/weekly objectives from an NPC quartermaster: "Recover 3 Rare items from
Fallout Fields," "Survive a Fallout Storm at 80%+ exposure," "Clean an Exclusion Belt item
while wearing a Lead-Lined suit," "Bring home a Legendary at Fresh stage," "Host 50 visitors."
Rewards: cash, XP, Clean Tokens, Containment Cells, cosmetic dyes. Standard, and it works.

### 10.15 Pets — *the Roblox tax*

Irradiated mutant critters (two-headed rat, glow-moth, ash hound) that follow the player and
give passive bonuses: detector radius, pull force, rad resistance, decay slowdown, cash
multiplier. Hatched from eggs bought with cash or found in-ground. This is expected by the
audience, cheap to implement, and a natural monetization vehicle.

\---

## 11\. Monetization

Everything is a **convenience or a cosmetic**. Nothing sold here is required to reach the
Crater — a free player reaching endgame is what makes the game look worth spending on.

**Gamepasses (one-time):**

* 2× Cash — 199 R$
* 2× Luck — 399 R$
* Auto-Clean (cleans automatically at your current tool potency; does not exceed it) — 299 R$
* +50 Carry Capacity — 249 R$
* VIP Bunker (private decon shower + trader + decon station, skip the walk) — 499 R$
* Auto-Pull (the magnet draws on its own at your current tier; does not exceed it) — 149 R$
* **+8 Pedestal Slots** — 349 R$
* **Extended Offline Bank** (4h → 8h of exhibition income) — 299 R$
* **Curator's Eye** (see exact fuse and modifiers without the Assay Bench) — 199 R$

**Developer products (repeatable):**

* Rad Flush (instant full decontamination anywhere) — 25 R$
* **Containment Cell 5-pack** (freeze one item's decay clock for 3 min) — 49 R$
* **Extraction Beacon** (instant return to base camp) — 39 R$
* Lucky Sweep (10 min of ×3 luck) — 99 R$
* Storm Ticket (trigger a personal fallout storm) — 149 R$
* Egg bundles.

**Cosmetics:** suit skins, detector skins, magnet-arc trails, glow colors on your rad meter,
**vitrine styles, exhibit lighting, velvet ropes, and a custom sign over your plot on the
Row.** On a shared server these are visible, which is the entire point — and the Row makes
exhibit cosmetics the most-seen surface in the game.

**Deliberately not sold:**

* Any tool that exceeds its tier's potency.
* Immunity to the decay clock, or a permanent stop on it. Slowing is purchasable; stopping
is not.
* Immunity to radiation burn, or any increase to suit tolerance. **You cannot buy your way
into a zone.** Since there are no zone locks to sell (§3.5), the temptation here is to sell
survivability instead — don't. The moment burn is purchasable, the Dive stops being brave.
* Exhibition income multipliers beyond the slot/offline conveniences above. You can buy more
room; you cannot buy a better collection.

\---

## 12\. First-Session Flow (first 5 minutes)

The most important five minutes in any Roblox game. Scripted tightly:

1. **0:00** — Spawn at base camp in a cloth wrap, broken detector already in hand.
No menu, no cutscene. A quartermaster NPC says one line: *"Ash Flats. Find me something."*
2. **0:15** — First ping fires within seconds of walking. First pull — four
clicks, it's rigged short. Guaranteed **Uncommon**
(rigged) so the first find feels good. The fuse bar appears on the item card — generous,
4 minutes, and base camp is 40 seconds away. Pressure introduced without ever being felt.
3. **0:40** — Forced walk past the decon station, which teaches the shower by proximity prompt.
4. **1:00** — First clean at the station. Tutorial highlights the scrub. Item fuse visibly
stops. Sells for enough to afford the first detector upgrade exactly.
5. **1:30** — First upgrade purchased. Ping rate visibly improves. **The loop has now closed
once.** Everything after this is repetition with escalation.
6. **2:30** — Second good find. Quartermaster interrupts: *"Or don't sell it. Put it up —
people pay to look."* One free pedestal is granted. Player displays the item and gets
their first tourist within 20 seconds. **The second loop is now open.**
7. **3:00** — Rad meter crosses 50% for the first time; vignette and audio shift teach the
danger state without a death.
8. **4:00** — Player is walked past the Zone 2 border — a leaning fence with a gap in it.
No lock, no gate, no price. Crossing pops the survivability card: `UNSUITED — SURVIVABLE: 0:50`. **They will cross it.** Everyone crosses it. They get ten seconds of
white-edged screen and an alarm, and they run back out, and they understand the entire
game now.
9. **4:45** — The Row. Player walks past three high-level exhibits on the way back to the
trader and sees a Legendary in a lit case with a stranger's name on the plaque.
Player leaves the tutorial with two specific goals: a suit, and a wall.

The old flow ended with a locked door and a price tag. This one ends with an open fence and
somebody else's trophy, which is a much stronger pull.

\---

## 13\. Retention Design

* **Session goal:** always a visible next purchase under \~5 minutes away.
* **Session hook:** the exhibit is running while you play and banking while you don't.
* **Daily:** login streak rewards, rotating contracts, one guaranteed free egg, and up to
4 hours of banked exhibition income waiting at the door.
* **Weekly:** leaderboard reset (richest, most items cleaned, deepest run survived,
most-visited exhibit).
* **Long-term:** rebirth multipliers, museum completion, set completion, anomaly hunting,
rail network restoration.
* **Social:** beacons, storms, visible cosmetics, the museum wall of names, and the Row.
* **The one that matters most:** the Exhibition survives rebirth (§9.3). Every other
progression system in this game eventually resets. One doesn't, and it's the one made
entirely out of things the player personally went and got.

\---

## 14\. Art \& Audio Direction

* **Palette:** desaturated ash-grey and bone-white ground, sickly green for radiation,
amber for value/rarity. Radiation should be the **only** saturated color in the world, so
the eye is trained to read green = money = danger. This one rule does most of the art work.
* **The one exception is suit failure**, which blooms **white**, not green (§3.5). A second
color language, used exactly once, for the one state that means something categorically
different. Because it's the only white in the game, it will read instantly and forever.
* **The Row is the other exception:** exhibits are warm, lit, indoor, clean. Walking base
camp's main street should feel like relief after the wasteland, and it should make the
wasteland look worse by comparison.
* **Lighting:** heavy fog, low sun, per-zone fog color shift (grey → green → orange at the crater).
* **Models:** low-poly, chunky, readable at distance. Roblox-native, no realism attempt.
* **Audio:** Geiger clicks are the lead instrument. Sparse ambient drone, distant wind,
occasional far-off structural groan. The Crater is near-silent except for your own suit.
Silence is the scariest zone effect available and it's free.
* **The decay stages are an audio ladder:** Fresh is a slow tick from your bag. Hot adds a
second, faster layer. Critical adds a chirping alarm every three seconds. Slag goes
*silent* — and that silence, after two minutes of escalating noise, is how the player
learns they've lost it without a single line of UI text.

\---

## 15\. MVP Slice (build this first)

Everything above is the full vision. Ship this first and validate the loop:

* Zones **1–3** fully built, **4 reachable and lethal** (§3.5). Zone 4 needs no content in
MVP beyond its loot table and its rad rate — an empty, deadly, diggable field is enough to
test whether players dive into it. That test is worth more than a finished Zone 4.
* Detector tiers **1–4**, magnet **1–3**, cleaning tool **1–4**, suit **1–3**,
**boots 1–3**, **satchel 1–2**.
* \~35 items across 5 rarity tiers (Scrap → Epic). No modifiers except Cracked, Pristine and
Slagged.
* Radiation exposure, blackout, decon showers, carry-rads. **All of §3 — non-negotiable,
it's the differentiator.**
* **Radiation burn, suit tolerance, and the survivability countdown (§3.5).** Cheap to build:
it's one formula, one HUD element, and the *absence* of the walls you were going to build.
* **The decay clock (§3.6)**, all four stages, with the Assay Bench's fuse readout folded
into the item card for free so players can actually see what they're racing.
* **A slim Exhibition (§8):** 6 pedestal slots, one vitrine tier, tourists and collectors
only, no sets, no Row cosmetics — but **with offline banking**, because that's the part
that gets people back tomorrow and it's the number you most need real data on.
* Quarantine Locker (§10.2).
* Beacons (§10.9).
* Level 1–25 with the compounding rad resistance. No perks yet, no rebirth.
* Two gamepasses: 2× Cash, 2× Luck. One dev product: Containment Cells.

**Cut from MVP:** storms, anomalies, museum wall, pets, contracts, rebirth, rail network,
set bonuses, researchers/gearheads/rival curators, buyout offers, traversal moves, the
standalone Assay Bench.
Each is additive and can ship as an update — and shipping them as updates is itself a
retention strategy.

**Validation questions for the MVP**, in priority order:

1. *Do players voluntarily push past 80% exposure?* If yes, the greed dial works and the rest
of the game is worth building.
2. *Do players cross into Zone 4 unrated, on purpose, more than once?* Once is curiosity.
Twice is a mechanic. If they don't come back for a second dive, the reward isn't worth the
burn and the loot tables need to move before anything else does.
3. *Do items reach Critical stage in players' hands, and does it change their route?*
If nothing ever cooks, the fuses are too long and the run home is still dead time.
If everything slags, they're too short and the mechanic is a tax.
4. *Does anyone choose to display instead of sell before hour three?* If nobody does, the
yield curve is too shallow and the Exhibition is decoration rather than a second loop.

\---

## 16\. Open Questions

* **Rad rate tuning** is entirely unvalidated. Every number in §4 is a starting guess and
should be treated as such until playtested against the §15 validation questions.
* **The survivability countdown may be too honest.** Showing `SURVIVABLE: 0:14` makes the
gamble informed, but it also makes it *solvable* — players will optimize dives down to
a stopwatch routine. That's probably fine (it's skill), but if it flattens into a rote
loop, consider adding variance: suit degradation over a session, or a ±20% jitter on
the number so the last few seconds are always a real risk.
* **The decay clock's failure mode is rage, not challenge.** Losing a Legendary to a timer
after a five-minute run is the most likely quit moment in this entire design. Mitigations
are in place (§3.7, §5.4, gradual value bleed rather than a cliff, Slag still granting XP
and discovery credit) but this needs the closest possible watch in playtest. If the data
says people quit after their first Slagged Legendary, soften the top-tier fuses before
touching anything else.
* **Anomaly fuse of 1:15 in Zone 6 may be impossible**, and "impossible" here means "the
rarest item in the game is unobtainable," which is the worst possible outcome. Likely
answer: Anomalies come pre-shielded (fuse doesn't start until you leave the Crater), or the
Crater gets its own on-site Decon Station as the reward for reaching it. Decide before the
Crater ships.
* **Exhibition income could eat the economy.** Passive cash that scales with collection size
is exactly the shape of thing that trivializes gear purchases by hour ten. The per-hour cap
tied to Contractor Level (§8.7) is the intended guard, but the honest answer is that this
number can only be found in live data. Ship it low. Raising an income cap is a beloved
patch note; lowering one is a riot.
* **Movement speed is the most dangerous stat in the game** (§5.2). It multiplies sweep rate,
round-trip time, decay retention, and dive viability simultaneously. If one thing in this
document breaks the balance, it will be boots.
* **Six upgrade tracks plus pedestals may be too many** for the audience. The staggered
reveal (§6) is the intended answer, but if playtest shows players spreading thin and never
feeling powerful in any direction, merge satchel into suit and make it five.
* **Cleaning as a mini-game** — the scrub interaction needs to stay satisfying at repetition
#500, not just #5. If it doesn't, fall back to a hold-to-clean bar with the potency gate
intact; the gate matters more than the interaction.
* **Does the Row need moderation?** Public, permanent, player-authored plots with custom
signage on a Roblox game is a well-known problem surface. Assume yes; scope it before the
Row ships, not after.

