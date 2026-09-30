--[[
	tweak-nuke-touchups.luau — one-off template edits in
	ReplicatedStorage.Assets.ImportedNukeTemplates (run once in the Studio command bar,
	then Save + Publish; the place file isn't in git).

	  pearl_necklace  drop the clam's upper shell (the "backplate") and its hinge.
	  phoenix_nuke    tuck the five tail plumes (and their eyes) up and in so they
	                  stop trailing off the pad.
	  steel_rod       bake the rust in: corroded-metal material and rust colours on the
	                  parts themselves (was an ItemFx finish that only ran after a wash).
]]

local folder = game:GetService("ReplicatedStorage").Assets.ImportedNukeTemplates

local function each(model: Instance, pred: (string) -> boolean, fn: (BasePart) -> ())
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and pred(d.Name:gsub("[%d_]+$", "")) then
			fn(d)
		end
	end
end

-- Pearl: no backplate.
local pearl = folder.pearl_necklace
each(pearl, function(n)
	return n == "ClamUpper" or n == "ClamHinge"
end, function(p)
	p:Destroy()
end)

-- Phoenix: tails up 0.35 and 0.7 back toward the body, in model space.
local phoenix = folder.phoenix_nuke
local pivot = phoenix:GetPivot()
local shift = pivot:VectorToWorldSpace(Vector3.new(0, 0.35, -0.7))
each(phoenix, function(n)
	return n == "TailPlume" or n == "TailEye" or n == "TailEyeRing"
end, function(p)
	p.CFrame += shift
end)

-- Rusty: the look lives on the parts now.
local RUST = {
	Shell = Color3.fromHex("9A4A22"),
	TailTaper = Color3.fromHex("9A4A22"),
	HoopBand = Color3.fromHex("5C2E17"),
	EquatorSeam = Color3.fromHex("5C2E17"),
	Fin = Color3.fromHex("5C2E17"),
	TailCap = Color3.fromHex("5C2E17"),
	TailShroud = Color3.fromHex("5C2E17"),
	ShroudFloor = Color3.fromHex("5C2E17"),
	Corrosion = Color3.fromHex("C8621F"),
}
each(folder.steel_rod, function(n)
	return RUST[n] ~= nil
end, function(p)
	local sa = p:FindFirstChildOfClass("SurfaceAppearance")
	if sa then
		sa:Destroy()
	end
	p.Material = Enum.Material.CorrodedMetal
	p.Color = RUST[p.Name:gsub("[%d_]+$", "")]
end)

print("nuke touch-ups applied")
