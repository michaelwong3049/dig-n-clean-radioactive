--!strict
--[[
	MagnetHang — how a magnet hangs, and how big, SHARED by the shop rack and the hand.

	The rack (build/Shops, `hangTierModel`) hangs each magnet poles-down off a hook and
	fits it to a display height that climbs from the stall's cheapest tier to its
	dearest. The hand used to do its own thing (HoldCFrame + a flat 0.75x), which held
	the magnet sideways behind the player at a size nothing like the one on the rail.
	The user asked for the magnet you hold to be the one you bought: same size as the
	shop shows it, poles facing down. So both read this one spec.

	THE FRAMES. Magnets ignore HoldCFrame and are posed from their own grip-frame axes:
	`legs` (the poles) point down, `face` (+Y on the art) points at whoever is looking.
	The Horseshoe Magnet (T1) art has its poles along -X while every other tier has
	them along +Z, which is what `legsByName` is for. Keyed by NAME, not tier number,
	so a tier inserted into the line does not inherit someone else's axis.
]]

local Gear = require(script.Parent.Config.Gear)

local MagnetHang = {}

MagnetHang.LEGS = Vector3.new(0, 0, 1)
MagnetHang.LEGS_BY_NAME = { ["Horseshoe Magnet"] = Vector3.new(-1, 0, 0) } :: { [string]: Vector3 }
MagnetHang.FACE = Vector3.new(0, 1, 0)
--- Turned a little on the rack so the face catches the plaza, not dead-on.
MagnetHang.YAW = -20
--- Display height (studs) at the cheapest and dearest rung of a stall.
MagnetHang.HEIGHT = { 1.4, 3.0 }
--- The rack slot a hung magnet also has to fit (Shops' RACK_SLOT_WIDTH / _DEPTH).
MagnetHang.SLOT_WIDTH = 3.0
MagnetHang.SLOT_DEPTH = 3.6

--- The rotation that carries a magnet's legs to -Y and its face to +Z.
function MagnetHang.basis(tier: number): CFrame
	local legs = MagnetHang.LEGS_BY_NAME[Gear.tier("Magnet", tier).name] or MagnetHang.LEGS
	local up = -legs
	return CFrame.fromMatrix(Vector3.zero, up:Cross(MagnetHang.FACE), up, MagnetHang.FACE):Inverse()
end

--- Where `tier` sits up its own stall's ladder: 0 at the cheapest hook, 1 at the
--- dearest. A camp stall hangs every rung at the top height (Toxic Twilight's magnets
--- are one family drawn at one size — user rule).
function MagnetHang.rank(tier: number): number
	local camp = Gear.campOf("Magnet", tier)
	if camp ~= "base" then
		return 1
	end
	local tiers = Gear.tiersAt("Magnet", camp)
	local slot = table.find(tiers, tier) or 1
	return (slot - 1) / math.max(#tiers - 1, 1)
end

function MagnetHang.height(rank: number): number
	return MagnetHang.HEIGHT[1] + (MagnetHang.HEIGHT[2] - MagnetHang.HEIGHT[1]) * rank
end

--- The model's box in `frame`'s axes: every BasePart's 8 corners, then min/max.
function MagnetHang.box(model: Model, frame: CFrame): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local half = d.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = frame:PointToObjectSpace(d.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
						lo, hi = lo:Min(p), hi:Max(p)
					end
				end
			end
		end
	end
	return lo, hi
end

--- Pose `model` hung in `frame` (legs down its -Y, face out its +Z, turned YAW) and
--- scale it to the size the rack shows at `rank`. Returns nothing; the caller moves it
--- into place afterwards. Measured in the yawed pose on purpose — that is what the
--- rack measures, so the two come out the same size to the stud.
function MagnetHang.fit(model: Model, frame: CFrame, tier: number, rank: number)
	model:PivotTo(frame * CFrame.Angles(0, math.rad(MagnetHang.YAW), 0) * MagnetHang.basis(tier))
	local lo, hi = MagnetHang.box(model, frame)
	local e = hi - lo
	if math.min(e.X, e.Y, e.Z) > 0 then
		local f = math.min(MagnetHang.height(rank) / e.Y, MagnetHang.SLOT_WIDTH / e.X, MagnetHang.SLOT_DEPTH / e.Z)
		model:ScaleTo(model:GetScale() * f)
	end
end

return MagnetHang
