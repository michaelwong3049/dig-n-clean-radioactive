--!strict
--[[
	ImportedNukeMeshes.luau -- static geometry for the 16 hand-imported reference
	nuke meshes (Studio 3D import, 2026-09-17), each mapped to the specific
	catalogue item (Shared.Config.Items) its part names match -- a locket+chain
	assembly is , a pocket-watch face is , and so on.
	ItemModels.create wires these in ahead of the procedural rarity capsule for
	those 16 items; ImportedNukeYard.luau builds the same data into a showcase.

	Each entry is a flat list of MeshParts with the exact size + position offset
	they were built at, all relative to the assembly's own bounding-box centre.
	Every source part came in axis-aligned (identity rotation), so only positions
	are stored -- no rotation matrix needed. Every part also shared one flat grey
	(the unpainted import colour), so that's a single constant below rather than
	per-part data.
]]

local ImportedNukeMeshes = {}

export type PartDef = {
	name: string,
	meshId: string,
	size: Vector3,
	offset: Vector3,
}

export type ModelDef = {
	itemId: string,
	label: string,
	parts: { PartDef },
}

-- The flat unpainted grey every imported part shares.
ImportedNukeMeshes.PART_COLOR = Color3.new(0.6392, 0.6353, 0.6471)

ImportedNukeMeshes.MODELS = {
	{
		itemId = "steel_rod",
		label = "Rusty Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://92684778358189", size = Vector3.new(1.1966, 1.704, 1.1966), offset = Vector3.new(0.0, 0.384, 0.0) },
			{ name = "TailTaper", meshId = "rbxassetid://118205228864560", size = Vector3.new(0.7964, 0.6, 0.7991), offset = Vector3.new(0.0, -0.616, 0.0) },
			{ name = "HoopBand1", meshId = "rbxassetid://125088629561799", size = Vector3.new(1.1787, 0.05, 1.1787), offset = Vector3.new(0.0, 0.724, 0.0) },
			{ name = "HoopBand2", meshId = "rbxassetid://116365403300216", size = Vector3.new(1.0886, 0.05, 1.0886), offset = Vector3.new(0.0, 0.844, 0.0) },
			{ name = "HoopBand3", meshId = "rbxassetid://121469918156200", size = Vector3.new(0.9706, 0.05, 0.9706), offset = Vector3.new(0.0, 0.954, 0.0) },
			{ name = "EquatorSeam", meshId = "rbxassetid://98267592589954", size = Vector3.new(1.2626, 0.052, 1.2626), offset = Vector3.new(0.0, 0.384, 0.0) },
			{ name = "Corrosion1", meshId = "rbxassetid://101408087743667", size = Vector3.new(0.1193, 0.072, 0.1174), offset = Vector3.new(-0.5557, 0.204, 0.069) },
			{ name = "Corrosion2", meshId = "rbxassetid://139796289678262", size = Vector3.new(0.1193, 0.072, 0.1174), offset = Vector3.new(-0.4005, 0.444, -0.3914) },
			{ name = "Corrosion3", meshId = "rbxassetid://96253517889520", size = Vector3.new(0.1193, 0.072, 0.1174), offset = Vector3.new(0.0564, 0.684, -0.5572) },
			{ name = "Corrosion4", meshId = "rbxassetid://90564051750746", size = Vector3.new(0.1193, 0.072, 0.1174), offset = Vector3.new(0.4707, 0.204, -0.3033) },
			{ name = "Corrosion5", meshId = "rbxassetid://112133776537358", size = Vector3.new(0.1193, 0.072, 0.1174), offset = Vector3.new(0.5306, 0.444, 0.1789) },
			{ name = "Corrosion6", meshId = "rbxassetid://72167493857678", size = Vector3.new(0.1193, 0.072, 0.1174), offset = Vector3.new(0.191, 0.684, 0.5264) },
			{ name = "Corrosion7", meshId = "rbxassetid://113266003307277", size = Vector3.new(0.1193, 0.072, 0.1174), offset = Vector3.new(-0.2925, 0.204, 0.4775) },
			{ name = "Fin1", meshId = "rbxassetid://82857127203868", size = Vector3.new(0.1415, 0.46, 0.3607), offset = Vector3.new(-0.3284, -0.756, -0.088) },
			{ name = "Fin2", meshId = "rbxassetid://109118155031230", size = Vector3.new(0.3607, 0.46, 0.1415), offset = Vector3.new(0.088, -0.756, -0.3284) },
			{ name = "Fin3", meshId = "rbxassetid://139580849527552", size = Vector3.new(0.1415, 0.46, 0.3607), offset = Vector3.new(0.3284, -0.756, 0.088) },
			{ name = "Fin4", meshId = "rbxassetid://100669483349848", size = Vector3.new(0.3607, 0.46, 0.1415), offset = Vector3.new(-0.088, -0.756, 0.3284) },
			{ name = "TailShroud", meshId = "rbxassetid://125013065663931", size = Vector3.new(1.12, 0.4, 1.12), offset = Vector3.new(0.0, -1.036, 0.0) },
			{ name = "TailCap", meshId = "rbxassetid://101522288811650", size = Vector3.new(0.3982, 0.08, 0.3995), offset = Vector3.new(0.0, -0.936, 0.0) },
			{ name = "ShroudFloor", meshId = "rbxassetid://127189439560851", size = Vector3.new(1.124, 0.06, 1.124), offset = Vector3.new(0.0, -1.186, 0.0) },
		},
	},
	{
		itemId = "clock_movement",
		label = "Clockwork Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://88630932374297", size = Vector3.new(0.88, 1.0912, 0.88), offset = Vector3.new(0.0273, 0.0975, 0.0) },
			{ name = "TailTaper", meshId = "rbxassetid://104151233583081", size = Vector3.new(0.5569, 0.4, 0.5569), offset = Vector3.new(0.0273, -0.5025, 0.0) },
			{ name = "HoopBand1", meshId = "rbxassetid://92875713912787", size = Vector3.new(0.8429, 0.044, 0.8429), offset = Vector3.new(0.0273, 0.3575, 0.0) },
			{ name = "HoopBand2", meshId = "rbxassetid://77378107260279", size = Vector3.new(0.7009, 0.044, 0.7009), offset = Vector3.new(0.0273, 0.4775, 0.0) },
			{ name = "KeyStem", meshId = "rbxassetid://96730147921852", size = Vector3.new(0.1909, 0.07, 0.1506), offset = Vector3.new(-0.3538, 0.1375, 0.22) },
			{ name = "KeyWing1", meshId = "rbxassetid://118516657778088", size = Vector3.new(0.0883, 0.1723, 0.113), offset = Vector3.new(-0.4231, 0.0675, 0.26) },
			{ name = "KeyWing2", meshId = "rbxassetid://85467292420213", size = Vector3.new(0.0883, 0.1723, 0.113), offset = Vector3.new(-0.4231, 0.2075, 0.26) },
			{ name = "GovernorPost", meshId = "rbxassetid://126528137922592", size = Vector3.new(0.0587, 0.14, 0.0597), offset = Vector3.new(0.0273, 0.6175, 0.0) },
			{ name = "GovernorCoil", meshId = "rbxassetid://98048952719921", size = Vector3.new(0.216, 0.036, 0.216), offset = Vector3.new(0.0273, 0.6775, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://137422047218790", size = Vector3.new(0.1059, 0.3, 0.2615), offset = Vector3.new(-0.2046, -0.5225, -0.0621) },
			{ name = "Fin2", meshId = "rbxassetid://92236657928241", size = Vector3.new(0.2615, 0.3, 0.1059), offset = Vector3.new(0.0894, -0.5225, -0.2318) },
			{ name = "Fin3", meshId = "rbxassetid://129831967466291", size = Vector3.new(0.1059, 0.3, 0.2615), offset = Vector3.new(0.2591, -0.5225, 0.0621) },
			{ name = "Fin4", meshId = "rbxassetid://133901221632115", size = Vector3.new(0.2615, 0.3, 0.1059), offset = Vector3.new(-0.0349, -0.5225, 0.2318) },
		},
	},
	{
		itemId = "photo_locket",
		label = "Locket Nuke",
		parts = {
			{ name = "LocketHalf1", meshId = "rbxassetid://120026919840996", size = Vector3.new(0.6068, 0.884, 0.4193), offset = Vector3.new(-0.0441, -0.025, -0.0656) },
			{ name = "LocketHalf2", meshId = "rbxassetid://76330917801998", size = Vector3.new(0.6068, 0.884, 0.4193), offset = Vector3.new(0.0038, -0.025, 0.0656) },
			{ name = "LocketRim", meshId = "rbxassetid://95778622264661", size = Vector3.new(0.6599, 0.9828, 0.4022), offset = Vector3.new(-0.0201, -0.025, 0.0) },
			{ name = "LocketHinge", meshId = "rbxassetid://97843511728220", size = Vector3.new(0.056, 0.16, 0.056), offset = Vector3.new(-0.3492, -0.025, 0.19) },
			{ name = "Clasp", meshId = "rbxassetid://102251844354302", size = Vector3.new(0.1279, 0.08, 0.1316), offset = Vector3.new(0.3133, -0.025, -0.1925) },
			{ name = "TailTaper", meshId = "rbxassetid://108823391198626", size = Vector3.new(0.3173, 0.22, 0.3173), offset = Vector3.new(-0.0201, -0.525, 0.0) },
			{ name = "ChainLink1", meshId = "rbxassetid://119843762557367", size = Vector3.new(0.0935, 0.108, 0.066), offset = Vector3.new(-0.0201, 0.395, 0.0) },
			{ name = "ChainLink2", meshId = "rbxassetid://102023234344009", size = Vector3.new(0.066, 0.108, 0.0935), offset = Vector3.new(-0.0201, 0.457, 0.0) },
			{ name = "ChainLink3", meshId = "rbxassetid://129670574211740", size = Vector3.new(0.0935, 0.108, 0.066), offset = Vector3.new(-0.0201, 0.519, 0.0) },
			{ name = "ChainLink4", meshId = "rbxassetid://113254787582992", size = Vector3.new(0.066, 0.108, 0.0935), offset = Vector3.new(-0.0201, 0.581, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://120520003697816", size = Vector3.new(0.1017, 0.18, 0.1511), offset = Vector3.new(-0.1414, -0.545, -0.07) },
			{ name = "Fin2", meshId = "rbxassetid://113598854656885", size = Vector3.new(0.1017, 0.18, 0.1511), offset = Vector3.new(0.1011, -0.545, -0.07) },
			{ name = "Fin3", meshId = "rbxassetid://128662297703330", size = Vector3.new(0.16, 0.18, 0.025), offset = Vector3.new(-0.0201, -0.545, 0.14) },
		},
	},
	{
		itemId = "socket_set",
		label = "Toolbox Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://78721906432347", size = Vector3.new(0.8771, 0.92, 0.8793), offset = Vector3.new(0.0, -0.107, 0.0) },
			{ name = "NoseDome", meshId = "rbxassetid://109611076964179", size = Vector3.new(0.8793, 0.374, 0.8771), offset = Vector3.new(0.0, 0.48, 0.0) },
			{ name = "HexSocket1", meshId = "rbxassetid://116877051132114", size = Vector3.new(0.195, 0.2, 0.1645), offset = Vector3.new(-0.3118, 0.033, 0.18) },
			{ name = "HexSocket2", meshId = "rbxassetid://79181503279977", size = Vector3.new(0.1675, 0.2, 0.1947), offset = Vector3.new(-0.1708, -0.207, -0.3169) },
			{ name = "HexSocket3", meshId = "rbxassetid://85235305171025", size = Vector3.new(0.1952, 0.2, 0.16), offset = Vector3.new(0.304, 0.033, -0.1928) },
			{ name = "HexSocket4", meshId = "rbxassetid://114784969309571", size = Vector3.new(0.1632, 0.2, 0.1951), offset = Vector3.new(0.1838, -0.207, 0.3095) },
			{ name = "RatchetLug", meshId = "rbxassetid://77691483682490", size = Vector3.new(0.2186, 0.1, 0.2186), offset = Vector3.new(-0.2598, 0.293, 0.15) },
			{ name = "DriveSquare", meshId = "rbxassetid://138467818916692", size = Vector3.new(0.0956, 0.12, 0.0956), offset = Vector3.new(-0.2598, 0.393, 0.15) },
			{ name = "BaseRim", meshId = "rbxassetid://106418148728244", size = Vector3.new(0.917, 0.12, 0.9193), offset = Vector3.new(0.0, -0.607, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://70520192508011", size = Vector3.new(0.1159, 0.3, 0.2821), offset = Vector3.new(-0.4057, -0.507, -0.1087) },
			{ name = "Fin2", meshId = "rbxassetid://116281285008270", size = Vector3.new(0.2821, 0.3, 0.1159), offset = Vector3.new(0.1087, -0.507, -0.4057) },
			{ name = "Fin3", meshId = "rbxassetid://116384491649428", size = Vector3.new(0.1159, 0.3, 0.2821), offset = Vector3.new(0.4057, -0.507, 0.1087) },
			{ name = "Fin4", meshId = "rbxassetid://105831586549283", size = Vector3.new(0.2821, 0.3, 0.1159), offset = Vector3.new(-0.1087, -0.507, 0.4057) },
		},
	},
	{
		itemId = "unlit_signal_flare",
		label = "Flare Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://118770499818514", size = Vector3.new(0.8752, 0.88, 0.88), offset = Vector3.new(0.0, -0.075, 0.0) },
			{ name = "SwirlBandA", meshId = "rbxassetid://101600542926637", size = Vector3.new(0.9733, 0.0856, 0.9735), offset = Vector3.new(0.0, -0.075, 0.0) },
			{ name = "SwirlBandB", meshId = "rbxassetid://106720689048093", size = Vector3.new(0.8048, 0.523, 0.9385), offset = Vector3.new(0.0, -0.075, 0.0) },
			{ name = "FuzeCollar", meshId = "rbxassetid://102033841601349", size = Vector3.new(0.3371, 0.12, 0.3371), offset = Vector3.new(0.0, 0.345, 0.0) },
			{ name = "FuzeCap", meshId = "rbxassetid://88923052924414", size = Vector3.new(0.1396, 0.14, 0.1384), offset = Vector3.new(0.0, 0.445, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://71858785952193", size = Vector3.new(0.1403, 0.26, 0.208), offset = Vector3.new(-0.2425, -0.375, -0.14) },
			{ name = "Fin2", meshId = "rbxassetid://92693719276503", size = Vector3.new(0.1403, 0.26, 0.208), offset = Vector3.new(0.2425, -0.375, -0.14) },
			{ name = "Fin3", meshId = "rbxassetid://112672236568429", size = Vector3.new(0.22, 0.26, 0.035), offset = Vector3.new(0.0, -0.375, 0.28) },
		},
	},
	{
		itemId = "bottle_cap",
		label = "Dud Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://119064368918966", size = Vector3.new(0.8373, 0.9, 0.8393), offset = Vector3.new(0.0, -0.053, 0.0) },
			{ name = "NoseDome", meshId = "rbxassetid://104949679163787", size = Vector3.new(0.8393, 0.336, 0.8373), offset = Vector3.new(0.0, 0.455, 0.0) },
			{ name = "HoopBand1", meshId = "rbxassetid://75276753486813", size = Vector3.new(0.9108, 0.056, 0.9108), offset = Vector3.new(0.0, 0.287, 0.0) },
			{ name = "HoopBand2", meshId = "rbxassetid://124270711020108", size = Vector3.new(0.9108, 0.056, 0.9108), offset = Vector3.new(0.0, -0.353, 0.0) },
			{ name = "BaseRim", meshId = "rbxassetid://125677831808695", size = Vector3.new(0.8771, 0.14, 0.8793), offset = Vector3.new(0.0, -0.553, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://121393015936597", size = Vector3.new(0.1159, 0.3, 0.2821), offset = Vector3.new(-0.3864, -0.433, -0.1035) },
			{ name = "Fin2", meshId = "rbxassetid://84754772175007", size = Vector3.new(0.2821, 0.3, 0.1159), offset = Vector3.new(0.1035, -0.433, -0.3864) },
			{ name = "Fin3", meshId = "rbxassetid://135543022884805", size = Vector3.new(0.1159, 0.3, 0.2821), offset = Vector3.new(0.3864, -0.433, 0.1035) },
			{ name = "Fin4", meshId = "rbxassetid://104429126839769", size = Vector3.new(0.2821, 0.3, 0.1159), offset = Vector3.new(-0.1035, -0.433, 0.3864) },
		},
	},
	{
		itemId = "garden_trowel",
		label = "Half-Dug Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://133565289160352", size = Vector3.new(0.9193, 1.1408, 0.917), offset = Vector3.new(0.0, 0.0398, 0.0) },
			{ name = "SoilSkirt", meshId = "rbxassetid://119551322529675", size = Vector3.new(1.48, 0.22, 1.48), offset = Vector3.new(0.0, -0.5002, 0.0) },
			{ name = "SoilMound", meshId = "rbxassetid://128367815000938", size = Vector3.new(1.269, 0.261, 1.269), offset = Vector3.new(0.0, -0.4297, 0.0) },
			{ name = "TrowelBlade", meshId = "rbxassetid://71493108153014", size = Vector3.new(0.2846, 0.34, 0.0267), offset = Vector3.new(-0.4049, 0.1998, 0.1645) },
			{ name = "TrowelHandle", meshId = "rbxassetid://116646791827668", size = Vector3.new(0.152, 0.2, 0.1178), offset = Vector3.new(-0.5755, 0.4011, 0.1949) },
			{ name = "HoopBand1", meshId = "rbxassetid://136188956019407", size = Vector3.new(0.9116, 0.04, 0.9116), offset = Vector3.new(0.0, 0.2598, 0.0) },
			{ name = "HoopBand2", meshId = "rbxassetid://127423842892363", size = Vector3.new(0.9776, 0.04, 0.9776), offset = Vector3.new(0.0, -0.0202, 0.0) },
			{ name = "Weed", meshId = "rbxassetid://138761327279395", size = Vector3.new(0.1041, 0.2602, 0.0764), offset = Vector3.new(0.3142, -0.2861, -0.4042) },
		},
	},
	{
		itemId = "charm_bracelet",
		label = "Charm Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://133322942410009", size = Vector3.new(0.4795, 0.6528, 0.4778), offset = Vector3.new(-0.0185, 0.0235, -0.0093) },
			{ name = "TailTaper", meshId = "rbxassetid://88874090795645", size = Vector3.new(0.2776, 0.2, 0.2776), offset = Vector3.new(-0.0185, -0.3565, -0.0093) },
			{ name = "HoopBand1", meshId = "rbxassetid://96600262605515", size = Vector3.new(0.501, 0.028, 0.501), offset = Vector3.new(-0.0185, 0.1235, -0.0093) },
			{ name = "HoopBand2", meshId = "rbxassetid://103855354790271", size = Vector3.new(0.501, 0.028, 0.501), offset = Vector3.new(-0.0185, -0.0765, -0.0093) },
			{ name = "CharmLoop1", meshId = "rbxassetid://106758752133770", size = Vector3.new(0.0813, 0.0156, 0.0813), offset = Vector3.new(-0.2421, 0.0635, 0.1198) },
			{ name = "CharmBead1", meshId = "rbxassetid://140539865215812", size = Vector3.new(0.06, 0.06, 0.06), offset = Vector3.new(-0.2681, 0.0335, 0.1348) },
			{ name = "CharmLoop2", meshId = "rbxassetid://139055277504754", size = Vector3.new(0.0806, 0.0156, 0.0806), offset = Vector3.new(-0.2104, 0.0635, -0.1821) },
			{ name = "CharmBead2", meshId = "rbxassetid://71856320898415", size = Vector3.new(0.06, 0.06, 0.06), offset = Vector3.new(-0.2327, 0.0335, -0.2021) },
			{ name = "CharmLoop3", meshId = "rbxassetid://104462327354161", size = Vector3.new(0.0816, 0.0156, 0.0816), offset = Vector3.new(0.0865, 0.0635, -0.2452) },
			{ name = "CharmBead3", meshId = "rbxassetid://91114485002093", size = Vector3.new(0.06, 0.06, 0.06), offset = Vector3.new(0.0987, 0.0335, -0.2726) },
			{ name = "CharmLoop4", meshId = "rbxassetid://128203671224513", size = Vector3.new(0.082, 0.0156, 0.082), offset = Vector3.new(0.2383, 0.0635, 0.0177) },
			{ name = "CharmBead4", meshId = "rbxassetid://89414036632130", size = Vector3.new(0.06, 0.06, 0.06), offset = Vector3.new(0.2681, 0.0335, 0.0208) },
			{ name = "CharmLoop5", meshId = "rbxassetid://123006903670264", size = Vector3.new(0.0819, 0.0156, 0.0819), offset = Vector3.new(0.0352, 0.0635, 0.2432) },
			{ name = "CharmBead5", meshId = "rbxassetid://138938892738644", size = Vector3.new(0.06, 0.06, 0.06), offset = Vector3.new(0.0414, 0.0335, 0.2726) },
			{ name = "Bail", meshId = "rbxassetid://125849245922778", size = Vector3.new(0.129, 0.146, 0.0851), offset = Vector3.new(-0.0185, 0.3835, -0.0093) },
			{ name = "Fin1", meshId = "rbxassetid://84149161611302", size = Vector3.new(0.0917, 0.16, 0.1337), offset = Vector3.new(-0.1224, -0.3765, -0.0693) },
			{ name = "Fin2", meshId = "rbxassetid://107037875170184", size = Vector3.new(0.0917, 0.16, 0.1337), offset = Vector3.new(0.0854, -0.3765, -0.0693) },
			{ name = "Fin3", meshId = "rbxassetid://97408768770498", size = Vector3.new(0.14, 0.16, 0.025), offset = Vector3.new(-0.0185, -0.3765, 0.1107) },
		},
	},
	{
		itemId = "tin_can",
		label = "Dented Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://127170662411877", size = Vector3.new(0.6792, 0.884, 0.6769), offset = Vector3.new(0.0, 0.124, 0.0) },
			{ name = "TailTaper", meshId = "rbxassetid://110786296076477", size = Vector3.new(0.44, 0.36, 0.4333), offset = Vector3.new(0.0, -0.376, 0.0) },
			{ name = "RolledSeam", meshId = "rbxassetid://80470172736376", size = Vector3.new(0.745, 0.056, 0.745), offset = Vector3.new(0.0, 0.124, 0.0) },
			{ name = "LithoStripe", meshId = "rbxassetid://87069546742212", size = Vector3.new(0.6271, 0.1, 0.6293), offset = Vector3.new(0.0, 0.344, 0.0) },
			{ name = "PressedCap", meshId = "rbxassetid://104906526331591", size = Vector3.new(0.2175, 0.07, 0.2194), offset = Vector3.new(0.0, 0.504, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://112850453407325", size = Vector3.new(0.0759, 0.26, 0.1997), offset = Vector3.new(-0.1739, -0.436, -0.0466) },
			{ name = "Fin2", meshId = "rbxassetid://127148500586039", size = Vector3.new(0.1997, 0.26, 0.0759), offset = Vector3.new(0.0466, -0.436, -0.1739) },
			{ name = "Fin3", meshId = "rbxassetid://139758386749805", size = Vector3.new(0.0759, 0.26, 0.1997), offset = Vector3.new(0.1739, -0.436, 0.0466) },
			{ name = "Fin4", meshId = "rbxassetid://119988265830636", size = Vector3.new(0.1997, 0.26, 0.0759), offset = Vector3.new(-0.0466, -0.436, 0.1739) },
		},
	},
	{
		itemId = "ignition_coil",
		label = "Ignition Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://128656729931009", size = Vector3.new(0.72, 0.86, 0.72), offset = Vector3.new(0.0001, -0.155, 0.0) },
			{ name = "CoilDome", meshId = "rbxassetid://80695001759161", size = Vector3.new(0.72, 0.252, 0.72), offset = Vector3.new(0.0001, 0.371, 0.0) },
			{ name = "Winding1", meshId = "rbxassetid://103465808540148", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, -0.515, 0.0) },
			{ name = "Winding2", meshId = "rbxassetid://118391572475308", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, -0.44, 0.0) },
			{ name = "Winding3", meshId = "rbxassetid://86194298170301", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, -0.365, 0.0) },
			{ name = "Winding4", meshId = "rbxassetid://140190533765351", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, -0.29, 0.0) },
			{ name = "Winding5", meshId = "rbxassetid://117430225561924", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, -0.215, 0.0) },
			{ name = "Winding6", meshId = "rbxassetid://137053094742600", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, -0.14, 0.0) },
			{ name = "Winding7", meshId = "rbxassetid://121520815360763", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, -0.065, 0.0) },
			{ name = "Winding8", meshId = "rbxassetid://121450949491951", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, 0.01, 0.0) },
			{ name = "Winding9", meshId = "rbxassetid://131418679068867", size = Vector3.new(0.8016, 0.052, 0.8005), offset = Vector3.new(0.0001, 0.085, 0.0) },
			{ name = "PlugTerminal", meshId = "rbxassetid://136064372353147", size = Vector3.new(0.178, 0.14, 0.1795), offset = Vector3.new(0.0001, 0.505, 0.0) },
			{ name = "TerminalNut", meshId = "rbxassetid://76079342264786", size = Vector3.new(0.17, 0.06, 0.1472), offset = Vector3.new(0.0001, 0.605, 0.0) },
			{ name = "SparkPin", meshId = "rbxassetid://71109412223863", size = Vector3.new(0.027, 0.12, 0.027), offset = Vector3.new(0.0001, 0.685, 0.0) },
			{ name = "Lead1", meshId = "rbxassetid://120002061627778", size = Vector3.new(0.1746, 0.6147, 0.0515), offset = Vector3.new(0.1699, -0.315, -0.3059) },
			{ name = "Lead2", meshId = "rbxassetid://92753549111706", size = Vector3.new(0.1025, 0.6147, 0.1616), offset = Vector3.new(-0.3497, -0.315, -0.0059) },
			{ name = "BaseCollar", meshId = "rbxassetid://84531801685585", size = Vector3.new(0.76, 0.14, 0.76), offset = Vector3.new(0.0001, -0.635, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://88759880082146", size = Vector3.new(0.1159, 0.3, 0.2821), offset = Vector3.new(-0.338, -0.595, -0.0906) },
			{ name = "Fin2", meshId = "rbxassetid://135402523697027", size = Vector3.new(0.2821, 0.3, 0.1159), offset = Vector3.new(0.0907, -0.595, -0.3381) },
			{ name = "Fin3", meshId = "rbxassetid://133533712941263", size = Vector3.new(0.1159, 0.3, 0.2821), offset = Vector3.new(0.3382, -0.595, 0.0906) },
			{ name = "Fin4", meshId = "rbxassetid://107677418925567", size = Vector3.new(0.2821, 0.3, 0.1159), offset = Vector3.new(-0.0905, -0.595, 0.3381) },
		},
	},
	{
		itemId = "radioactive_rubber_duck",
		label = "Rubber Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://100005509752957", size = Vector3.new(0.9928, 0.8464, 0.9904), offset = Vector3.new(0.0, -0.0985, 0.0) },
			{ name = "SoftNose", meshId = "rbxassetid://124978156309686", size = Vector3.new(0.3939, 0.34, 0.4), offset = Vector3.new(0.0, 0.3215, 0.0) },
			{ name = "AirPlug", meshId = "rbxassetid://133952478272139", size = Vector3.new(0.178, 0.08, 0.1795), offset = Vector3.new(0.0, 0.4815, 0.0) },
			{ name = "MouldSeam", meshId = "rbxassetid://102463548848403", size = Vector3.new(1.0588, 0.0571, 1.0588), offset = Vector3.new(0.0, -0.0985, 0.0) },
			{ name = "SoftFin1", meshId = "rbxassetid://116442661207267", size = Vector3.new(0.2898, 0.165, 0.1436), offset = Vector3.new(-0.3188, -0.3985, -0.0854) },
			{ name = "SoftFin2", meshId = "rbxassetid://85619602762620", size = Vector3.new(0.1436, 0.165, 0.2898), offset = Vector3.new(0.0854, -0.3985, -0.3188) },
			{ name = "SoftFin3", meshId = "rbxassetid://135839916875523", size = Vector3.new(0.2898, 0.165, 0.1436), offset = Vector3.new(0.3188, -0.3985, 0.0854) },
			{ name = "SoftFin4", meshId = "rbxassetid://89162982620177", size = Vector3.new(0.1436, 0.165, 0.2898), offset = Vector3.new(-0.0854, -0.3985, 0.3188) },
		},
	},
	{
		itemId = "cutlery_set",
		label = "Tarnished Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://99012568317583", size = Vector3.new(0.9174, 1.2328, 0.9174), offset = Vector3.new(0.0, 0.115, 0.0) },
			{ name = "TailTaper", meshId = "rbxassetid://109676810789885", size = Vector3.new(0.5967, 0.44, 0.5967), offset = Vector3.new(0.0, -0.565, 0.0) },
			{ name = "PolishedBand", meshId = "rbxassetid://96509273681864", size = Vector3.new(1.0484, 0.1046, 1.0484), offset = Vector3.new(0.0, 0.175, 0.0) },
			{ name = "PatinaPatch1", meshId = "rbxassetid://87914456710238", size = Vector3.new(0.0768, 0.198, 0.1938), offset = Vector3.new(-0.3926, -0.125, -0.0301) },
			{ name = "PatinaPatch2", meshId = "rbxassetid://87609313548821", size = Vector3.new(0.1916, 0.198, 0.0877), offset = Vector3.new(-0.1012, 0.095, -0.4177) },
			{ name = "PatinaPatch3", meshId = "rbxassetid://113806474229338", size = Vector3.new(0.122, 0.198, 0.1734), offset = Vector3.new(0.345, 0.315, -0.2124) },
			{ name = "PatinaPatch4", meshId = "rbxassetid://104883034265494", size = Vector3.new(0.1381, 0.198, 0.1582), offset = Vector3.new(0.2999, -0.125, 0.255) },
			{ name = "PatinaPatch5", meshId = "rbxassetid://116154701824359", size = Vector3.new(0.185, 0.198, 0.1033), offset = Vector3.new(-0.1636, 0.095, 0.3974) },
			{ name = "Finial", meshId = "rbxassetid://77677831519789", size = Vector3.new(0.1396, 0.14, 0.1384), offset = Vector3.new(0.0, 0.715, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://133431074846264", size = Vector3.new(0.1059, 0.3, 0.2615), offset = Vector3.new(-0.2318, -0.605, -0.0621) },
			{ name = "Fin2", meshId = "rbxassetid://86518980758136", size = Vector3.new(0.2615, 0.3, 0.1059), offset = Vector3.new(0.0621, -0.605, -0.2318) },
			{ name = "Fin3", meshId = "rbxassetid://136662376934110", size = Vector3.new(0.1059, 0.3, 0.2615), offset = Vector3.new(0.2318, -0.605, 0.0621) },
			{ name = "Fin4", meshId = "rbxassetid://139898556188673", size = Vector3.new(0.2615, 0.3, 0.1059), offset = Vector3.new(-0.0621, -0.605, 0.2318) },
		},
	},
	{
		itemId = "door_hinge",
		label = "Squeaky Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://119342121040167", size = Vector3.new(0.8793, 1.144, 0.8771), offset = Vector3.new(0.003, 0.1134, 0.0) },
			{ name = "TailTaper", meshId = "rbxassetid://76758769209007", size = Vector3.new(0.5569, 0.42, 0.5569), offset = Vector3.new(0.003, -0.5066, 0.0) },
			{ name = "HingeLeaf1", meshId = "rbxassetid://80072467444992", size = Vector3.new(0.096, 0.13, 0.1362), offset = Vector3.new(-0.3531, 0.3334, 0.2056) },
			{ name = "HingeKnuckle1", meshId = "rbxassetid://114792751930547", size = Vector3.new(0.064, 0.12, 0.064), offset = Vector3.new(-0.3834, 0.3334, 0.2231) },
			{ name = "HingeLeaf2", meshId = "rbxassetid://91379154674897", size = Vector3.new(0.096, 0.13, 0.1362), offset = Vector3.new(-0.3803, 0.0534, 0.2213) },
			{ name = "HingeKnuckle2", meshId = "rbxassetid://111856968953856", size = Vector3.new(0.064, 0.12, 0.064), offset = Vector3.new(-0.4106, 0.0534, 0.2388) },
			{ name = "HingeLeaf3", meshId = "rbxassetid://99268530465961", size = Vector3.new(0.096, 0.13, 0.1362), offset = Vector3.new(-0.3078, -0.2266, 0.1794) },
			{ name = "HingeKnuckle3", meshId = "rbxassetid://116456803837309", size = Vector3.new(0.064, 0.12, 0.064), offset = Vector3.new(-0.3381, -0.2266, 0.1969) },
			{ name = "PivotPin", meshId = "rbxassetid://124429077390679", size = Vector3.new(0.0313, 0.76, 0.0318), offset = Vector3.new(-0.4106, 0.0534, 0.2388) },
			{ name = "SwingSeam", meshId = "rbxassetid://70390666971090", size = Vector3.new(0.8073, 1.2064, 0.4808), offset = Vector3.new(0.003, 0.1134, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://110004736717603", size = Vector3.new(0.1059, 0.3, 0.2615), offset = Vector3.new(-0.2288, -0.5466, -0.0621) },
			{ name = "Fin2", meshId = "rbxassetid://91632309915157", size = Vector3.new(0.2615, 0.3, 0.1059), offset = Vector3.new(0.0651, -0.5466, -0.2318) },
			{ name = "Fin3", meshId = "rbxassetid://93187135418176", size = Vector3.new(0.1059, 0.3, 0.2615), offset = Vector3.new(0.2348, -0.5466, 0.0621) },
			{ name = "Fin4", meshId = "rbxassetid://107726429247884", size = Vector3.new(0.2615, 0.3, 0.1059), offset = Vector3.new(-0.0591, -0.5466, 0.2318) },
		},
	},
	{
		itemId = "stopped_watch",
		label = "Stopped Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://101730718430706", size = Vector3.new(0.8793, 1.144, 0.8771), offset = Vector3.new(0.0, 0.1224, 0.0165) },
			{ name = "TailTaper", meshId = "rbxassetid://103217808792919", size = Vector3.new(0.5569, 0.42, 0.5569), offset = Vector3.new(0.0, -0.5176, 0.0165) },
			{ name = "HoopBand1", meshId = "rbxassetid://127173496246547", size = Vector3.new(0.8403, 0.036, 0.8403), offset = Vector3.new(0.0, 0.3825, 0.0165) },
			{ name = "HoopBand2", meshId = "rbxassetid://121117274593564", size = Vector3.new(0.7144, 0.036, 0.7144), offset = Vector3.new(0.0, 0.5025, 0.0165) },
			{ name = "DialBezel", meshId = "rbxassetid://132179135348596", size = Vector3.new(0.3591, 0.38, 0.242), offset = Vector3.new(-0.2, 0.1825, -0.3299) },
			{ name = "DialFace", meshId = "rbxassetid://75146638310392", size = Vector3.new(0.2835, 0.31, 0.181), offset = Vector3.new(-0.22, 0.1825, -0.3645) },
			{ name = "HandMinute", meshId = "rbxassetid://108405149687286", size = Vector3.new(0.0233, 0.12, 0.0204), offset = Vector3.new(-0.235, 0.2425, -0.3905) },
			{ name = "HandHour", meshId = "rbxassetid://135910474653840", size = Vector3.new(0.0796, 0.018, 0.0529), offset = Vector3.new(-0.2696, 0.1825, -0.3705) },
			{ name = "WindKnob", meshId = "rbxassetid://91064523854267", size = Vector3.new(0.0743, 0.0902, 0.0836), offset = Vector3.new(-0.1, 0.6825, -0.1567) },
			{ name = "Fin1", meshId = "rbxassetid://127756324639768", size = Vector3.new(0.1111, 0.32, 0.2808), offset = Vector3.new(-0.2318, -0.5376, -0.0456) },
			{ name = "Fin2", meshId = "rbxassetid://105469836819739", size = Vector3.new(0.2808, 0.32, 0.1111), offset = Vector3.new(0.0621, -0.5376, -0.2153) },
			{ name = "Fin3", meshId = "rbxassetid://135630618322215", size = Vector3.new(0.1111, 0.32, 0.2808), offset = Vector3.new(0.2318, -0.5376, 0.0786) },
			{ name = "Fin4", meshId = "rbxassetid://84032613453841", size = Vector3.new(0.2808, 0.32, 0.1111), offset = Vector3.new(-0.0621, -0.5376, 0.2483) },
		},
	},
	{
		itemId = "cracked_tile",
		label = "Cracked Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://73331971626133", size = Vector3.new(0.9945, 1.36, 1.0), offset = Vector3.new(0.0, 0.145, 0.0) },
			{ name = "TailTaper", meshId = "rbxassetid://134916995291556", size = Vector3.new(0.6371, 0.46, 0.6393), offset = Vector3.new(0.0, -0.595, 0.0) },
			{ name = "Fissure1", meshId = "rbxassetid://101598063560855", size = Vector3.new(0.0852, 0.4221, 0.1339), offset = Vector3.new(-0.3962, 0.285, 0.0492) },
			{ name = "Fissure2", meshId = "rbxassetid://87114452103476", size = Vector3.new(0.0583, 0.3, 0.0505), offset = Vector3.new(0.1918, -0.015, -0.3464) },
			{ name = "Fissure3", meshId = "rbxassetid://123945665716371", size = Vector3.new(0.1418, 0.3262, 0.1605), offset = Vector3.new(0.3028, 0.205, 0.2736) },
			{ name = "HoopBand1", meshId = "rbxassetid://132837752591382", size = Vector3.new(0.974, 0.04, 0.974), offset = Vector3.new(0.0, 0.425, 0.0) },
			{ name = "HoopBand2", meshId = "rbxassetid://131506251201298", size = Vector3.new(0.974, 0.04, 0.974), offset = Vector3.new(0.0, -0.135, 0.0) },
			{ name = "Fin1", meshId = "rbxassetid://106572889354104", size = Vector3.new(0.1111, 0.32, 0.2808), offset = Vector3.new(-0.2511, -0.635, -0.0673) },
			{ name = "Fin2", meshId = "rbxassetid://126068068699401", size = Vector3.new(0.2808, 0.32, 0.1111), offset = Vector3.new(0.0673, -0.635, -0.2511) },
			{ name = "Fin3", meshId = "rbxassetid://106552197822293", size = Vector3.new(0.1111, 0.32, 0.2808), offset = Vector3.new(0.2511, -0.635, 0.0673) },
			{ name = "Fin4", meshId = "rbxassetid://123074142467456", size = Vector3.new(0.2808, 0.32, 0.1111), offset = Vector3.new(-0.0673, -0.635, 0.2511) },
		},
	},
	{
		itemId = "radiation_scanner",
		label = "Clicking Nuke",
		parts = {
			{ name = "Shell", meshId = "rbxassetid://106948522168136", size = Vector3.new(0.9992, 1.26, 0.9968), offset = Vector3.new(0.0, -0.0875, 0.0) },
			{ name = "TailTaper", meshId = "rbxassetid://73495849216034", size = Vector3.new(0.6365, 0.44, 0.6365), offset = Vector3.new(0.0, -0.7675, 0.0) },
			{ name = "ScannerHead", meshId = "rbxassetid://77899219554266", size = Vector3.new(0.5967, 0.2, 0.5967), offset = Vector3.new(0.0, 0.4525, 0.0) },
			{ name = "GaugeBezel", meshId = "rbxassetid://90728604041799", size = Vector3.new(0.3978, 0.06, 0.3978), offset = Vector3.new(0.0, 0.5725, 0.0) },
			{ name = "GaugeFace", meshId = "rbxassetid://132710907834520", size = Vector3.new(0.3282, 0.035, 0.3282), offset = Vector3.new(0.0, 0.6025, 0.0) },
			{ name = "GaugeNeedle", meshId = "rbxassetid://115740708945381", size = Vector3.new(0.0692, 0.016, 0.1012), offset = Vector3.new(-0.0346, 0.6225, 0.02) },
			{ name = "Probe", meshId = "rbxassetid://109609994478234", size = Vector3.new(0.1186, 0.414, 0.0815), offset = Vector3.new(-0.1714, 0.7532, 0.031) },
			{ name = "ProbeTip", meshId = "rbxassetid://110491535945973", size = Vector3.new(0.07, 0.07, 0.07), offset = Vector3.new(-0.2205, 0.9525, 0.058) },
			{ name = "Vent1", meshId = "rbxassetid://87535115661534", size = Vector3.new(0.0695, 0.17, 0.0603), offset = Vector3.new(-0.4241, -0.1075, 0.2449) },
			{ name = "Vent2", meshId = "rbxassetid://126779228708753", size = Vector3.new(0.0695, 0.17, 0.0603), offset = Vector3.new(-0.4241, -0.1075, -0.2449) },
			{ name = "Vent3", meshId = "rbxassetid://130080114649006", size = Vector3.new(0.035, 0.17, 0.06), offset = Vector3.new(0.0, -0.1075, -0.4897) },
			{ name = "Vent4", meshId = "rbxassetid://129931005881822", size = Vector3.new(0.0695, 0.17, 0.0603), offset = Vector3.new(0.4241, -0.1075, -0.2449) },
			{ name = "Vent5", meshId = "rbxassetid://125495763166654", size = Vector3.new(0.0695, 0.17, 0.0603), offset = Vector3.new(0.4241, -0.1075, 0.2449) },
			{ name = "Vent6", meshId = "rbxassetid://97534363191404", size = Vector3.new(0.035, 0.17, 0.06), offset = Vector3.new(0.0, -0.1075, 0.4897) },
			{ name = "Lamp1", meshId = "rbxassetid://126539582657809", size = Vector3.new(0.07, 0.07, 0.07), offset = Vector3.new(-0.0484, 0.4525, -0.2838) },
			{ name = "Lamp2", meshId = "rbxassetid://79620977316531", size = Vector3.new(0.07, 0.07, 0.07), offset = Vector3.new(-0.135, 0.4525, -0.2338) },
			{ name = "Lamp3", meshId = "rbxassetid://120312921184694", size = Vector3.new(0.07, 0.07, 0.07), offset = Vector3.new(-0.2216, 0.4525, -0.1838) },
			{ name = "CableCoil1", meshId = "rbxassetid://100966898939195", size = Vector3.new(0.1229, 0.0242, 0.1229), offset = Vector3.new(0.3448, 0.3925, -0.0028) },
			{ name = "CableCoil2", meshId = "rbxassetid://77952863734762", size = Vector3.new(0.0966, 0.1031, 0.1114), offset = Vector3.new(0.33, 0.35, 0.0201) },
			{ name = "CableCoil3", meshId = "rbxassetid://134852582314283", size = Vector3.new(0.0802, 0.1173, 0.11), offset = Vector3.new(0.3397, 0.3075, 0.0455) },
			{ name = "CableCoil4", meshId = "rbxassetid://127241087523245", size = Vector3.new(0.1152, 0.0601, 0.1226), offset = Vector3.new(0.366, 0.265, 0.0526) },
			{ name = "CableCoil5", meshId = "rbxassetid://120492717689041", size = Vector3.new(0.1102, 0.0861, 0.1116), offset = Vector3.new(0.3872, 0.2225, 0.0354) },
			{ name = "CableCoil6", meshId = "rbxassetid://130420790395609", size = Vector3.new(0.0754, 0.1227, 0.1064), offset = Vector3.new(0.3858, 0.18, 0.0082) },
			{ name = "CableCoil7", meshId = "rbxassetid://93395772670478", size = Vector3.new(0.1001, 0.0882, 0.1212), offset = Vector3.new(0.3629, 0.1375, -0.0066) },
			{ name = "CableCoil8", meshId = "rbxassetid://128963555403847", size = Vector3.new(0.1227, 0.0709, 0.1114), offset = Vector3.new(0.3375, 0.095, 0.0031) },
			{ name = "CableCoil9", meshId = "rbxassetid://92008912326779", size = Vector3.new(0.0896, 0.1188, 0.1021), offset = Vector3.new(0.3305, 0.0525, 0.0294) },
			{ name = "CableJack", meshId = "rbxassetid://113688179273894", size = Vector3.new(0.1108, 0.1046, 0.104), offset = Vector3.new(0.3913, 0.0301, 0.0304) },
			{ name = "ProbeCage1", meshId = "rbxassetid://127293853452554", size = Vector3.new(0.1276, 0.0156, 0.1274), offset = Vector3.new(-0.2032, 0.8725, 0.048) },
			{ name = "ProbeCage2", meshId = "rbxassetid://105797519983744", size = Vector3.new(0.1276, 0.0156, 0.1274), offset = Vector3.new(-0.2205, 0.9525, 0.058) },
			{ name = "Fin1", meshId = "rbxassetid://135546377351119", size = Vector3.new(0.1211, 0.34, 0.3014), offset = Vector3.new(-0.2705, -0.8075, -0.0725) },
			{ name = "Fin2", meshId = "rbxassetid://115920182947736", size = Vector3.new(0.3014, 0.34, 0.1211), offset = Vector3.new(0.0725, -0.8075, -0.2705) },
			{ name = "Fin3", meshId = "rbxassetid://95863688407758", size = Vector3.new(0.1211, 0.34, 0.3014), offset = Vector3.new(0.2705, -0.8075, 0.0725) },
			{ name = "Fin4", meshId = "rbxassetid://130407413408918", size = Vector3.new(0.3014, 0.34, 0.1211), offset = Vector3.new(-0.0725, -0.8075, 0.2705) },
		},
	},
}

-- Built once at require time: itemId -> its ModelDef, for ItemModels.create.
local byItemId: { [string]: ImportedNukeMeshes.ModelDef } = {}
for _, def in ImportedNukeMeshes.MODELS do
	byItemId[def.itemId] = def
end
ImportedNukeMeshes.byItemId = byItemId

--- Reconstruct one assembly as a fresh, unparented Model: one anchored,
--- non-colliding, massless MeshPart per captured part, positioned at its
--- stored offset from the model's own origin. Every gameplay call site
--- (wash rack, held item, exhibit locker, the model yard) already normalises
--- whatever Model it gets to its own target size via GetExtentsSize/ScaleTo,
--- so this hands back the assembly at its raw captured scale and lets the
--- caller do that -- the same contract ItemModels.create's tier factories honour.
function ImportedNukeMeshes.build(def: ImportedNukeMeshes.ModelDef): Model
	local model = Instance.new("Model")
	model.Name = def.itemId
	model:SetAttribute("ImportedNukeId", def.itemId)

	local primary: MeshPart? = nil
	for _, partDef in def.parts do
		local mesh = Instance.new("MeshPart")
		mesh.Name = partDef.name
		mesh.MeshId = partDef.meshId
		mesh.Size = partDef.size
		mesh.Color = ImportedNukeMeshes.PART_COLOR
		mesh.Material = Enum.Material.SmoothPlastic
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.Massless = true
		mesh.CFrame = CFrame.new(partDef.offset)
		mesh.Parent = model

		if primary == nil or partDef.name == "Shell" then
			primary = mesh
		end
	end
	model.PrimaryPart = primary

	return model
end

return ImportedNukeMeshes
