--[[
	Brighter paint for the five Base Camp detectors (Assets/Tools/Detector/T1-T5:
	Rust Bucket, Bent Coil, Scavenger MkI, Surplus Geiger, Pulse Array).

	The imported models carry dark baked textures (one per material slot), so a
	MeshPart's Color does nothing while TextureID is set. This clears TextureID and
	paints each part by its ROLE instead. Every tier shares the same part names, so
	one ROLE table covers all five; only the palette changes per tier.

	Run once from the Studio command bar in EDIT. It repaints the templates AND every
	placed copy in Workspace (shop rack displays etc.) matched by TierName, so no
	rebuild is needed. Then Save + Publish.

	Pass PREVIEW = folder to paint only that folder's T1-T5 clones.
]]

local PREVIEW: Instance? = nil

local H = Color3.fromHex

local ROLE = {}
local function set(role, names)
	for n in names:gmatch("[%w_]+") do
		ROLE[n] = role
	end
end
set("rubber", "pistol_grip,grip_ridge,cuff_pad,coiled_cable,rod_boot,skid_foot")
set("dark", "screen_backing,speaker_slot,vent_slot")
set("screen", "screen")
set("glow", "led,battery_gauge,under_sensor_lens,pulse_node,speaker_cone,stencil_bar")
set("body", "telescope_collar,grip_mount,guard_front,guard_bottom,cuff_stalk,cuff_shell,box_saddle,box_arm,housing_shell,battery_pack,knuckle,bolt,wire_wrap,dangling_cable,yoke_l,yoke_r,under_sensor_puck,under_puck_mount,corner_guard_lb,corner_guard_lf,corner_guard_rb,corner_guard_rf,rivet,skid_rail_l,skid_rail_r,cable_gland")
set("metal", "upper_shaft,lower_rod,shaft_tail,bezel,cracked_disc,coil_neck,bent_hoop,coil_hoop,spine_arm,knob_r,plate_coil,crossbar,coil_post")
set("accent", "cam_lock,grip_cap,trigger,shaft_endcap,cuff_strap,rod_collar,rib_clamp,bolted_patch,dented_hub,under_sensor_ring,under_rib,clamp,brace_a,brace_b,tape_wrap,spine_plate,knob_l,plate_face,speaker,whip_antenna,bumper_rear,bumper_l,bumper_r,shaft_trim,pulse_coil")

-- `metal` is the shaft + search coil (the biggest read), `accent` the clamps,
-- trigger and trims, `body` the control box and yoke.
local PALETTE = {
	["Rust Bucket"] = { body = H("4A5260"), metal = H("FF7A1F"), accent = H("FFE2B8"), glow = H("FFB347") },
	["Bent Coil"] = { body = H("B8322A"), metal = H("EEF2F6"), accent = H("FF4B3E"), glow = H("FF9A8A") },
	["Scavenger MkI"] = { body = H("4A5260"), metal = H("FFD23F"), accent = H("FFB000"), glow = H("FFE680") },
	["Surplus Geiger"] = { body = H("2F7A4A"), metal = H("C9F2D6"), accent = H("2EE06A"), glow = H("8CFFB0") },
	["Pulse Array"] = { body = H("2C4F9E"), metal = H("9CC8FF"), accent = H("2F8CFF"), glow = H("8FD0FF") },
}
local COMMON = { rubber = H("2B2F36"), dark = H("1C1F24"), screen = H("7CFF9E") }
local MATERIAL = {
	glow = Enum.Material.Neon,
	screen = Enum.Material.Neon,
	rubber = Enum.Material.Plastic,
}

local function paint(model: Instance, palette): number
	local n = 0
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") then
			local role = ROLE[p.Name] or ROLE[(p.Name:gsub("%d+$", ""))]
			if role then
				p.TextureID = ""
				p.Color = palette[role] or COMMON[role]
				p.Material = MATERIAL[role] or Enum.Material.SmoothPlastic
				n += 1
			else
				warn("[paint-starter-detectors] no role for " .. p:GetFullName())
			end
		end
	end
	return n
end

local log = {}
local function paintAll(list: { Instance })
	for _, m in list do
		if m:IsA("Model") then
			local palette = PALETTE[m:GetAttribute("TierName")]
			if palette then
				table.insert(log, ("%s: %d parts"):format(m:GetFullName(), paint(m, palette)))
			end
		end
	end
end

if PREVIEW then
	paintAll(PREVIEW:GetChildren())
else
	-- Templates are direct children only (Detector._Legacy holds old art).
	paintAll(game:GetService("ReplicatedStorage").Assets.Tools.Detector:GetChildren())
	paintAll(workspace:GetDescendants())
end
print(table.concat(log, "\n"))
return table.concat(log, "\n")
