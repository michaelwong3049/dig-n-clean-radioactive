--!strict
--[[
	StandNuke.luau — the nuke on a display stand, drawn by each client.

	WHY THE CLIENT DRAWS IT. A nuke is 20-190 MeshParts, almost every one a different
	mesh, so a full three-floor base was ~1,950 draw calls, and the server's clone of
	every one replicated to every player. Only the nearest few nukes ever animate.
	So the server publishes WHAT stands where (these attributes, on the stand's
	`Display{slot}` part) and each client builds it: the still copy
	(Assets.NukeStillTemplates, ~7 meshes, built by
	tools/studio-migrations/apply-still-nuke-meshes.luau) for every stand, and the full
	model only for the nearest Config/ItemFx DETAIL fullBudget, where its effects run.
	Same split as the stand cards (Shared/StandCard) and the base nameplate.

	THE SERVER STILL WORKS OUT THE POSE. ExhibitService clones the full model off-world
	to size and seat it (payload roll, height cap, GIGA pierce) exactly as it always
	has, writes the result here, and destroys the clone without parenting it. The
	client only clones, scales and moves, so both copies land in the same spot.

	ATTRIBUTES (on the Display part, tagged TAG once it has ever held a nuke):
	  item      item id, or nil when the stand is empty or shows a placeholder block
	  modifier  the dig's quality roll ("None", "Pristine", "Fused", "Irradiated")
	  scale     multiply the template's own GetScale() by this
	  pivot     CFrame for the scaled model's pivot: seated on the plinth and lifted
	            by the hover amplitude
	  rate, amp the hover's turn rate (rad/s) and bob (studs), for StationMotion
]]

local StandNuke = {}

StandNuke.TAG = "StandNuke"

StandNuke.ATTR = {
	item = "NukeItem",
	modifier = "NukeModifier",
	scale = "NukeScale",
	pivot = "NukePivot",
	rate = "NukeMotionRate",
	amp = "NukeMotionAmp",
}

--- Set on every still copy (tools/studio-migrations/apply-still-nuke-meshes.luau).
StandNuke.STILL_ATTRIBUTE = "StillCopy"

--- What the client names the model it parents under the Display part. The same name
--- the server's clone used, so FastModeController's "any ItemModel under Plots" rule
--- keeps holding.
StandNuke.MODEL_NAME = "ItemModel"

return StandNuke
