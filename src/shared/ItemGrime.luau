--!strict
--[[
	ItemGrime.luau — what contamination LOOKS like, on the item itself.

	Every item in this game is dug out of poisoned ground, carried home filthy and
	hosed clean, and until now not one of those three states was visible on the object.
	A Gold Ring came out of the mud looking exactly like a Gold Ring, sat in your hand
	looking like a Gold Ring, and finished a wash looking like a Gold Ring. The only
	thing that ever said "this is dirty" was a row of green blobs the wash bay painted
	NEXT TO it (WashController.paintBlobs) and a pip count in a list.

	So: a contaminated item wears a green film, and the film comes off as you scrub.
	`Contamination` already knows how many patches are left out of how many it started
	with; that fraction is the whole input. Nothing here decides anything about
	gameplay -- it reads a number the maths already produced and paints with it.

	A FILM, NOT A REPAINT. The tint tops out at TINT_MAX, deliberately well under half,
	because the object still has to be readable while it is dirty: a bottle cap has to
	look like a bottle cap in your hand, or the catalogue art might as well not exist
	and the hotbar is unreadable. This is a wash of green OVER the authored materials,
	not a replacement of them. The glow is what makes it read as radioactive rather
	than merely grubby.

	IT ALWAYS RESTORES EXACTLY. The authored colour is stashed on each part in an
	attribute the first time it is tinted, and every later apply() re-lerps FROM that
	stash rather than from whatever is on the part now -- so calling apply() every tick
	with a falling level walks the colour back to the original instead of compounding
	green onto green. clear() puts the stash back and removes it. That round trip is
	the "turns back into the original model" half of the feature, and it is pinned in
	Spec.

	WHO CALLS THIS. Three places, one per state the item can be seen in:
	  DigService.createHaul   the lump breaking the surface  (always fully dirty)
	  ToolService.equipItem   the thing in your off hand     (level from its patches)
	  WashService             sitting on the tub             (re-applied as patches pop)

	The gallery and the exhibit pedestals do not, and must not: ExhibitService refuses
	an item that is not clean, so a green one can never legitimately stand there.
]]

local ItemGrime = {}

--- The same green WashController paints its patch blobs with. PLAN §14's one-colour
--- rule: contamination is this green everywhere it appears, and it is not the
--- rarity green (Uncommon's 5CD65C) for exactly that reason.
local GRIME = Color3.fromHex("6BEE2E")

--- How far toward GRIME a fully contaminated part is dragged. A light film: the
--- authored silver/gold/brass is still what you are looking at.
local TINT_MAX = 0.40

--- ...and how far a nearly-clean one still is. Without a floor, an item on its last
--- patch is a couple of percent green -- indistinguishable from finished, which would
--- make "why won't this sell" a mystery again. One patch left has to LOOK like one
--- patch left.
local TINT_FLOOR = 0.14

local GLOW_RANGE = 5
local GLOW_NAME = "GrimeGlow"

--- Set on the model so a caller can skip a redundant repaint (ToolService reads it to
--- decide whether the thing already in the hand needs touching), and so anything
--- inspecting a live item in Studio can see what state it thinks it is in.
local LEVEL_ATTR = "GrimeLevel"
local STASH_ATTR = "GrimeCleanColor"

local EPSILON = 0.005

local function eachPart(root: Instance, fn: (BasePart) -> ())
	if root:IsA("BasePart") then
		fn(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			fn(descendant)
		end
	end
end

--- The colour this part was authored with, whatever has been painted over it since.
local function cleanColor(part: BasePart): Color3
	local stashed = part:GetAttribute(STASH_ATTR)
	if typeof(stashed) == "Color3" then
		return stashed
	end
	part:SetAttribute(STASH_ATTR, part.Color)
	return part.Color
end

--- Somewhere to hang the light. Models built by ItemModels have no PrimaryPart (they
--- are moved with PivotTo), so the first part found is the normal answer.
local function glowAnchor(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end
	if root:IsA("Model") and root.PrimaryPart then
		return root.PrimaryPart
	end
	return root:FindFirstChildWhichIsA("BasePart", true)
end

--- Paint `root` as `level` dirty, 0 (clean) to 1 (straight out of the ground).
--- Idempotent and safe to call every tick: it re-derives from the stashed colour, so
--- a falling level walks the item back toward its own art.
function ItemGrime.apply(root: Instance, level: number)
	local amount = math.clamp(level, 0, 1)
	if amount <= EPSILON then
		ItemGrime.clear(root)
		return
	end

	local tint = TINT_FLOOR + (TINT_MAX - TINT_FLOOR) * amount
	eachPart(root, function(part)
		part.Color = cleanColor(part):Lerp(GRIME, tint)
	end)

	local anchor = glowAnchor(root)
	if anchor then
		local glow = anchor:FindFirstChild(GLOW_NAME)
		if glow == nil or not glow:IsA("PointLight") then
			local made = Instance.new("PointLight")
			made.Name = GLOW_NAME
			made.Color = GRIME
			made.Shadows = false
			made.Parent = anchor
			glow = made
		end
		local light = glow :: PointLight
		light.Range = GLOW_RANGE
		light.Brightness = 0.5 + 1.0 * amount
	end

	root:SetAttribute(LEVEL_ATTR, amount)
end

--- Put the authored art back and leave no trace. Called by apply() itself at level 0,
--- so nothing has to special-case "it just came clean".
function ItemGrime.clear(root: Instance)
	eachPart(root, function(part)
		local stashed = part:GetAttribute(STASH_ATTR)
		if typeof(stashed) == "Color3" then
			part.Color = stashed
			part:SetAttribute(STASH_ATTR, nil)
		end
		local glow = part:FindFirstChild(GLOW_NAME)
		if glow then
			glow:Destroy()
		end
	end)
	root:SetAttribute(LEVEL_ATTR, nil)
end

--- What apply() last painted, or 0. Lets a caller avoid repainting twenty parts on a
--- tick where nothing about the item changed.
function ItemGrime.levelOf(root: Instance): number
	local level = root:GetAttribute(LEVEL_ATTR)
	return if type(level) == "number" then level else 0
end

return ItemGrime
