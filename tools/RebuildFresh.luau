--[[
	RebuildFresh.luau — paste into Roblox Studio's Command Bar (Edit mode) to force a
	world rebuild that can't be served from a stale require() cache.

	NOT SYNCED BY ROJO. default.project.json only maps src/shared, src/server and
	src/client into the game -- this file lives outside all three on purpose, so it
	never becomes an Instance and never runs anywhere by itself. It is a reference
	copy for the command bar only.

	WHY THIS EXISTS. Rojo edits a ModuleScript's Source in place, but Roblox Studio's
	Edit-mode require() cache does not get busted by that -- the FIRST require() of a
	build module in an Edit session compiles it once, and every later require() in
	that same session (even after Source has changed again) silently returns that
	same cached compile. Symptom: workspace.Scenery/Plots/etc.'s BuilderVersion
	attribute does not match the version in the file on disk after a rebuild, and
	the rebuild's own part counts stay suspiciously identical run to run.

	A plain `require(game.ServerScriptService.Server.build.World).rebuild()` is safe
	to run ONCE per fresh Edit session (e.g. right after opening/restarting Studio).
	After that first call, use the script below instead of a plain require -- it
	clones the module tree it needs into a throwaway location with a brand-new
	Instance identity, which require() has never cached, so it always compiles fresh
	regardless of how many times you've already rebuilt this session.

	Both halves matter. `build/` modules use RELATIVE requires (script.Parent.X), so a
	plain throwaway clone anywhere works and can just be destroyed afterward.
	`ReplicatedStorage.Shared` is reached by every build module via an ABSOLUTE path
	instead, so it has to be renamed aside and swapped for a fresh clone in place, then
	the real one restored under its original name once the rebuild is done --
	`Shared` may never be destroyed, since Rojo holds a live reference to that specific
	Instance and destroying it silently breaks sync (a human then has to reconnect the
	Rojo plugin by hand). The pcall + unconditional restore below guarantees `Shared`
	comes back even if the rebuild itself errors partway through.
]]

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local realShared = RS.Shared
local freshShared = realShared:Clone()
local ok, err = pcall(function()
	realShared.Name = "__SharedReal" -- renamed, NOT destroyed or unparented
	freshShared.Name = "Shared"
	freshShared.Parent = RS
	local fb = SSS.Server.build:Clone() -- build/ needs the same treatment
	fb.Name = "__buildFresh"
	fb.Parent = SSS
	require(fb.World).rebuild() -- resolves ReplicatedStorage.Shared -> the clone
	fb:Destroy() -- a clone may be destroyed; the original may not
end)
freshShared:Destroy()
realShared.Name = "Shared" -- restore unconditionally, even on error
if not ok then
	warn(err)
end
