--!strict
--[[
	FlyController.luau — dev-only free-fly, toggled by DebugService's `/fly` chat
	command (the tuning console, gated to Studio or the place owner in a live
	server — see DebugService.mayUseConsole). The server side of the toggle is
	just `player:SetAttribute("FlyMode", bool)`, the same "poke an attribute and
	let the client react" channel DebugService's own header already documents
	for its scriptable hook.

	Movement is entirely client-side and immediate — no remote round-trip — the
	same way it would be if you were driving Studio's own free camera. That is
	fine here specifically BECAUSE this is unreachable by an ordinary player: the
	permission check already happened server-side before the attribute was ever
	set, so there is nothing for a client-authoritative fly to cheat.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local FlyController = {}

local FLY_SPEED = 80 -- studs/sec at rest
local BOOST_MULTIPLIER = 3 -- held Shift

local heldKeys: { [Enum.KeyCode]: boolean } = {}
local renderConnection: RBXScriptConnection? = nil

local function setPlatformStand(character: Model, value: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	humanoid.PlatformStand = value
	humanoid.AutoRotate = not value
end

local function stopFlying()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	-- Zero the residual velocity BEFORE handing control back to the Humanoid —
	-- PlatformStand held the part kinematically still while flying, but the
	-- part can pick up a large AssemblyLinearVelocity from the last frame's
	-- CFrame jump alone, and re-enabling normal physics with that still set
	-- would launch the character on landing.
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	if character then
		setPlatformStand(character, false)
	end
end

local function startFlying()
	stopFlying() -- idempotent: a double /fly-on (e.g. after a respawn) must never stack loops

	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	setPlatformStand(character, true)

	renderConnection = RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if camera == nil or root.Parent == nil then
			return
		end

		local forward = if heldKeys[Enum.KeyCode.W] then 1 elseif heldKeys[Enum.KeyCode.S] then -1 else 0
		local strafe = if heldKeys[Enum.KeyCode.D] then 1 elseif heldKeys[Enum.KeyCode.A] then -1 else 0
		local vertical = if heldKeys[Enum.KeyCode.Space] then 1
			elseif heldKeys[Enum.KeyCode.LeftControl] or heldKeys[Enum.KeyCode.C] then -1
			else 0

		if forward == 0 and strafe == 0 and vertical == 0 then
			return
		end

		local look = camera.CFrame.LookVector
		local right = camera.CFrame.RightVector
		local direction = look * forward + right * strafe + Vector3.new(0, vertical, 0)
		if direction.Magnitude == 0 then
			return
		end
		direction = direction.Unit

		local speed = FLY_SPEED * (if heldKeys[Enum.KeyCode.LeftShift] then BOOST_MULTIPLIER else 1)
		local nextPosition = root.Position + direction * speed * dt
		root.CFrame = CFrame.lookAt(nextPosition, nextPosition + look)
	end)
end

local function syncToFlyMode()
	if LocalPlayer:GetAttribute("FlyMode") then
		startFlying()
	else
		stopFlying()
	end
end

function FlyController.start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed then
			heldKeys[input.KeyCode] = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		heldKeys[input.KeyCode] = false
	end)

	LocalPlayer:GetAttributeChangedSignal("FlyMode"):Connect(syncToFlyMode)

	-- A respawn replaces HumanoidRootPart out from under any live connection above
	-- (it closes over the old `root`), and PlatformStand resets to false on the new
	-- character regardless. Re-arm on the new character if the flag is still set.
	LocalPlayer.CharacterAdded:Connect(function()
		if LocalPlayer:GetAttribute("FlyMode") then
			task.defer(startFlying)
		end
	end)

	syncToFlyMode() -- covers the flag already being set before this controller loaded
end

return FlyController
