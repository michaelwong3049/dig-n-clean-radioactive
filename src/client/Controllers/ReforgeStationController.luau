--!strict
--[[
	ReforgeStationController.luau — the Reforge Station doing things you can watch
	(build/ReforgeStation, Services/ReforgeService).

	THE SERVER NEVER MOVES A PART. A reforge bumps `ReforgeSeq` on the station model and
	writes ReforgeOutcome beside it ("roll", or "quality" when the forge added one);
	every client near the machine plays the same strike off those attributes:

	  flare    the embers in the furnace mouth turn Neon and light up (the only time
	           this prop glows -- Kit's matte rule holds while it idles)
	  strike   the hammer swings up off the anvil and comes down STRIKES times, sparks
	           flying off the face each time it lands
	  quality  a last, bigger burst of gold sparks and the rare-drop sting

	A forge that streams out mid-strike just stops; everything is put back per machine
	when the next strike starts or the model leaves.
]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Sfx = require(script.Parent.Parent.Sfx)

local ReforgeStation = {}

local TAG = "ReforgeStation"

local EMBER = Color3.fromHex("FF6A1A")
local SPARK = Color3.fromHex("FFB347")
local GOLD = Color3.fromHex("FFD24A")

local STRIKES = 3
local LIFT_TIME = 0.16
local DROP_TIME = 0.07
local LIFT_ANGLE = math.rad(55)

type Show = { token: number, bits: { Instance } }

local shows: { [Model]: Show } = {}
local tokens = 0

local function restHammer(machine: Model)
	local hammer = machine:FindFirstChild("Hammer")
	if hammer and hammer:IsA("Model") then
		local rest = hammer:GetAttribute("RestPivot")
		if typeof(rest) == "CFrame" then
			hammer:PivotTo(rest)
		end
	end
end

local function clear(machine: Model)
	local show = shows[machine]
	if show == nil then
		return
	end
	shows[machine] = nil
	for _, bit in show.bits do
		bit:Destroy()
	end
	local embers = machine:FindFirstChild("Embers")
	if embers and embers:IsA("BasePart") then
		embers.Material = Enum.Material.SmoothPlastic
		embers.Color = EMBER
	end
	restHammer(machine)
end

local function sparks(parent: BasePart, color: Color3, count: number, speed: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.3, 0.8)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Rate = 0
	emitter.Parent = parent
	emitter:Emit(count)
	task.delay(1.2, function()
		emitter:Destroy()
	end)
end

--- Swing the hammer from its rest pivot to `angle` (radians, head up) over `time`.
local function swing(hammer: Model, rest: CFrame, from: number, to: number, time: number, token: number, machine: Model)
	local started = os.clock()
	while os.clock() - started < time do
		local show = shows[machine]
		if show == nil or show.token ~= token or hammer.Parent == nil then
			return
		end
		local t = (os.clock() - started) / time
		hammer:PivotTo(rest * CFrame.Angles(0, 0, from + (to - from) * t))
		task.wait()
	end
	hammer:PivotTo(rest * CFrame.Angles(0, 0, to))
end

local function play(machine: Model)
	clear(machine)
	tokens += 1
	local token = tokens
	local show: Show = { token = token, bits = {} }
	shows[machine] = show

	local outcome = machine:GetAttribute("ReforgeOutcome")
	local hammer = machine:FindFirstChild("Hammer")
	local strike = machine:FindFirstChild("StrikePoint")
	local embers = machine:FindFirstChild("Embers")

	if embers and embers:IsA("BasePart") then
		embers.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = EMBER
		light.Range = 14
		light.Brightness = 0
		light.Parent = embers
		table.insert(show.bits, light)
		TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 3 }):Play()
	end

	if hammer and hammer:IsA("Model") then
		local rest = hammer:GetAttribute("RestPivot")
		if typeof(rest) ~= "CFrame" then
			rest = hammer:GetPivot()
			hammer:SetAttribute("RestPivot", rest)
		end
		for _ = 1, STRIKES do
			swing(hammer, rest :: CFrame, 0, LIFT_ANGLE, LIFT_TIME, token, machine)
			swing(hammer, rest :: CFrame, LIFT_ANGLE, 0, DROP_TIME, token, machine)
			if shows[machine] ~= show then
				return
			end
			if strike and strike:IsA("BasePart") then
				sparks(strike, SPARK, 18, 16)
				Sfx.playAt("dig", strike)
			end
			task.wait(0.12)
		end
	end

	if shows[machine] ~= show then
		return
	end
	if outcome == "quality" and strike and strike:IsA("BasePart") then
		sparks(strike, GOLD, 60, 26)
		Sfx.playAt("rareDrop", strike)
	elseif strike then
		Sfx.playAt("cleaned", strike)
	end
	task.delay(1.2, function()
		if shows[machine] == show then
			clear(machine)
		end
	end)
end

local function watch(machine: Instance)
	if not machine:IsA("Model") then
		return
	end
	machine:GetAttributeChangedSignal("ReforgeSeq"):Connect(function()
		task.spawn(function()
			local ok, err = pcall(play, machine)
			if not ok then
				warn(`[reforge] forge show failed: {err}`)
			end
		end)
	end)
	machine.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clear(machine)
		end
	end)
end

function ReforgeStation.start()
	for _, machine in CollectionService:GetTagged(TAG) do
		watch(machine)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
end

return ReforgeStation
