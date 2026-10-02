--!strict
--[[
	LeaderboardService.luau — two jobs, one set of numbers:

	1. The Roblox player list (top-right): each player's cash and trained walk speed
	   via the standard `leaderstats` folder. This server only.
	2. The global boards: Top Cash (lifetime `data.cashEarned`) and Top Speed (trained
	   walk speed) across every server, kept in two OrderedDataStores and drawn on two
	   boards against the brown shoulder wall right of the Stage 1 entrance.

	data.cash is mutated from many places (EconomyService, refunds on load, debug
	commands), not all of which go through EconomyService.pushCash, so instead of
	hooking every writer this mirrors the wallet on a short poll. Only writes the
	IntValue when the number actually changed, so replication stays quiet.

	THE BOARDS ARE BUILT HERE AT RUNTIME, not by build/*, so they ship with the code
	and need no Studio rebuild. They find the wall and floor by raycast and fall back
	to the numbers measured on 2026-10-01 if the world has moved.

	DEGRADES, NEVER BLOCKS: with no DataStore access (Studio without API access, or
	the service is down) the boards still draw, ranked from the players in this server,
	and say so in the footer. Players in this server always show their live numbers,
	merged over the last global read, so your own climb shows within seconds rather
	than at the next minute's read.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local DataService = require(script.Parent.DataService)
local Treadmill = require(ReplicatedStorage.Shared.Config.Treadmill)

local LeaderboardService = {}

local POLL = 0.5
local WRITE_EVERY = 120 -- seconds between a player's score writes (plus one on leave)
local READ_EVERY = 60 -- seconds between top-list reads
local RENDER_EVERY = 5 -- seconds between redraws with this server's live numbers
local TOP = 25
local MAX_SCORE = 2 ^ 53 -- OrderedDataStore takes integers; keep them exact

-- ── Board placement ──────────────────────────────────────────────────────────
-- Scenery.BaseWalls.ShoulderWallPos: plaza face at x = 96, runs z = 89..236, floor
-- (Plots.Apron tiles) top at y = -1.5. Boards face west, Cash on the left as you
-- face the wall (lower z), Speed on the right.
local WALL_X_FALLBACK = 96
local FLOOR_Y_FALLBACK = -1.5
local BOARD_Z = { 112, 131 }
local BOARD_W = 15 -- along the wall (world Z); was 20, "way too big"
local BOARD_H = 22.5 -- keep W:H at 2:3 so the canvas stays 800 x 1200
local BOARD_LIFT = 1.5 -- gap between floor and the board's bottom edge
local RIM = 0.4 -- ink rim showing round the face
local RIM_DEPTH = 0.5
local FACE_DEPTH = 0.5
-- The SurfaceGui layout is drawn on a fixed 800 x 1200 canvas; resizing the board
-- rescales it rather than reflowing it.
local PPS = 800 / BOARD_W

-- Style 1 "Dark slab" from the mockup round: the HUD's ink, green cash, blue speed.
local INK = Color3.fromHex("10141A")
local FACE = Color3.fromHex("161B22")
local INSET = Color3.fromHex("2C3440")
local SUBTLE = Color3.fromHex("8A95A3")
local WHITE = Color3.new(1, 1, 1)
local CASH = Color3.fromHex("7CF25A")
local SPEED = Color3.fromHex("9FE3FF")
local PODIUM = { Color3.fromHex("FFD24A"), Color3.fromHex("D9E2EC"), Color3.fromHex("E0955A") }

local FONT = Enum.Font.GothamBlack

--- $340, $5.2K, $1.4M, $2.1B -- the HUD's own short form.
local function shortCash(amount: number): string
	for _, unit in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if amount >= unit[1] then
			local s = string.format("%.1f", amount / unit[1])
			s = (string.gsub(s, "%.0$", ""))
			return `${s}{unit[2]}`
		end
	end
	return `${math.floor(amount)}`
end

type Board = {
	key: string,
	storeName: string,
	title: string,
	subtitle: string,
	color: Color3,
	format: (number) -> string,
	store: OrderedDataStore?,
	global: { { userId: number, value: number } },
	globalOk: boolean,
	rows: { any },
	empty: TextLabel?,
	footer: TextLabel?,
}

local BOARDS: { Board } = {
	{
		key = "cash",
		storeName = "LB_CashEarned_v1",
		title = "Top Cash",
		subtitle = "Lifetime cash earned",
		color = CASH,
		format = shortCash,
		global = {},
		globalOk = false,
		rows = {},
	},
	{
		key = "speed",
		storeName = "LB_Speed_v1",
		title = "Top Speed",
		subtitle = "Trained walk speed",
		color = SPEED,
		format = function(n: number): string
			return tostring(math.floor(n))
		end,
		global = {},
		globalOk = false,
		rows = {},
	},
}

local cashValues: { [Player]: IntValue } = {}
local speedValues: { [Player]: IntValue } = {}

-- Latest known scores per player in this server, and what was last written for them.
local scores: { [Player]: { [string]: number } } = {}
local written: { [number]: { [string]: number } } = {}
local names: { [number]: string } = {}
local storesOnline = false

local function setup(player: Player)
	if cashValues[player] then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = folder
	-- Trained walk speed (not the picker's cap), so the board shows what they've earned.
	local speed = Instance.new("IntValue")
	speed.Name = "Speed"
	speed.Value = Treadmill.START_WALK
	speed.Parent = folder
	folder.Parent = player
	cashValues[player] = cash
	speedValues[player] = speed
end

local function clampScore(n: number): number
	return math.clamp(math.floor(n), 0, MAX_SCORE)
end

-- ── Building the boards ──────────────────────────────────────────────────────

local function label(parent: Instance, props: { [string]: any }, stroke: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = WHITE
	l.TextScaled = false
	for k, v in props do
		(l :: any)[k] = v
	end
	if stroke then
		local s = Instance.new("UIStroke")
		s.Color = INK
		s.Thickness = stroke
		s.Parent = l
	end
	l.Parent = parent
	return l
end

local function wallAndFloorAt(z: number, exclude: { Instance }): (number, number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude

	local wallX = WALL_X_FALLBACK
	local hit = Workspace:Raycast(Vector3.new(WALL_X_FALLBACK - 30, 8, z), Vector3.new(60, 0, 0), params)
	if hit and math.abs(hit.Position.X - WALL_X_FALLBACK) < 12 then
		wallX = hit.Position.X
	end

	local floorY = FLOOR_Y_FALLBACK
	local down = Workspace:Raycast(Vector3.new(wallX - 6, 40, z), Vector3.new(0, -80, 0), params)
	if down and math.abs(down.Position.Y - FLOOR_Y_FALLBACK) < 10 then
		floorY = down.Position.Y
	end
	return wallX, floorY
end

local function buildBoard(board: Board, z: number, folder: Folder)
	local wallX, floorY = wallAndFloorAt(z, { folder })
	local centreY = floorY + BOARD_LIFT + BOARD_H / 2
	local west = Vector3.new(-1, 0, 0)

	local model = Instance.new("Model")
	model.Name = (string.gsub(board.title, " ", "")) .. "Board"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local rimPos = Vector3.new(wallX - RIM_DEPTH / 2, centreY, z)
	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Anchored = true
	rim.Material = Enum.Material.SmoothPlastic
	rim.Color = INK
	rim.Size = Vector3.new(BOARD_W + RIM * 2, BOARD_H + RIM * 2, RIM_DEPTH)
	rim.CFrame = CFrame.lookAt(rimPos, rimPos + west)
	rim.Parent = model

	local facePos = Vector3.new(wallX - RIM_DEPTH - FACE_DEPTH / 2, centreY, z)
	local face = Instance.new("Part")
	face.Name = "Face"
	face.Anchored = true
	face.Material = Enum.Material.SmoothPlastic
	face.Color = FACE
	face.Size = Vector3.new(BOARD_W, BOARD_H, FACE_DEPTH)
	face.CFrame = CFrame.lookAt(facePos, facePos + west)
	face.Parent = model

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	gui.ClipsDescendants = true
	gui.Parent = face

	local W, H = BOARD_W * PPS, BOARD_H * PPS

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = FACE
	root.BorderSizePixel = 0
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	-- The mockup's thin lighter line just inside the rim.
	local inset = Instance.new("Frame")
	inset.BackgroundTransparency = 1
	inset.Position = UDim2.fromOffset(8, 8)
	inset.Size = UDim2.new(1, -16, 1, -16)
	inset.Parent = root
	local insetStroke = Instance.new("UIStroke")
	insetStroke.Color = INSET
	insetStroke.Thickness = 6
	insetStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	insetStroke.Parent = inset

	label(root, {
		Name = "Title",
		Text = board.title,
		TextSize = 88,
		TextColor3 = board.color,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 92),
	}, 5)
	label(root, {
		Name = "Subtitle",
		Text = board.subtitle,
		TextSize = 32,
		TextColor3 = SUBTLE,
		Position = UDim2.fromOffset(0, 112),
		Size = UDim2.new(1, 0, 0, 36),
	}, 3)

	local ROW_TOP, ROW_H = 160, 40
	for i = 1, TOP do
		local row = Instance.new("Frame")
		row.Name = `Row{i}`
		row.BorderSizePixel = 0
		row.BackgroundColor3 = WHITE
		row.BackgroundTransparency = if i % 2 == 0 then 0.96 else 1
		row.Position = UDim2.fromOffset(16, ROW_TOP + (i - 1) * ROW_H)
		row.Size = UDim2.fromOffset(W - 32, ROW_H)
		row.Parent = root

		local podium = PODIUM[i]
		local rank = label(row, {
			Name = "Rank",
			Text = `#{i}`,
			TextSize = 34,
			TextColor3 = podium or WHITE,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(78, ROW_H),
		}, 3)

		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = INSET
		avatar.BorderSizePixel = 0
		avatar.Position = UDim2.fromOffset(90, 3)
		avatar.Size = UDim2.fromOffset(34, 34)
		avatar.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = avatar
		if podium then
			local ring = Instance.new("UIStroke")
			ring.Color = podium
			ring.Thickness = 3
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ring.Parent = avatar
		end

		local name = label(row, {
			Name = "PlayerName",
			Text = "",
			TextSize = 33,
			TextColor3 = podium or WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(138, 0),
			Size = UDim2.fromOffset(420, ROW_H),
		}, 3)

		local value = label(row, {
			Name = "Value",
			Text = "",
			TextSize = 34,
			TextColor3 = board.color,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(560, 0),
			Size = UDim2.fromOffset(W - 32 - 560 - 8, ROW_H),
		}, 3)

		board.rows[i] = { frame = row, rank = rank, avatar = avatar, name = name, value = value, shown = true }
	end

	board.empty = label(root, {
		Name = "Empty",
		Text = "No scores yet",
		TextSize = 40,
		TextColor3 = SUBTLE,
		Position = UDim2.fromOffset(0, ROW_TOP + 4 * ROW_H),
		Size = UDim2.new(1, 0, 0, 60),
		Visible = false,
	}, 3)

	board.footer = label(root, {
		Name = "Footer",
		Text = "Updates every minute",
		TextSize = 28,
		TextColor3 = SUBTLE,
		Position = UDim2.fromOffset(0, H - 40),
		Size = UDim2.new(1, 0, 0, 30),
	}, 2)

	model.PrimaryPart = face
	model.Parent = folder
end

-- ── Drawing ──────────────────────────────────────────────────────────────────

local function setText(l: TextLabel, text: string)
	if l.Text ~= text then
		l.Text = text
	end
end

local function render(board: Board)
	-- The global read, with this server's players laid over it at their live values.
	local merged: { [number]: number } = {}
	for _, entry in board.global do
		merged[entry.userId] = entry.value
	end
	local here: { [number]: Player } = {}
	for player, s in scores do
		local v = s[board.key]
		if v ~= nil then
			merged[player.UserId] = math.max(merged[player.UserId] or 0, v)
			here[player.UserId] = player
		end
	end

	local list = {}
	for userId, value in merged do
		table.insert(list, { userId = userId, value = value })
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)

	for i, row in board.rows do
		local entry = list[i]
		local show = entry ~= nil
		if row.shown ~= show then
			row.shown = show
			row.rank.Visible = show
			row.avatar.Visible = show
			row.name.Visible = show
			row.value.Visible = show
		end
		if entry then
			local player = here[entry.userId]
			setText(row.name, if player then player.DisplayName else (names[entry.userId] or "Player"))
			setText(row.value, board.format(entry.value))
			local image = if entry.userId > 0
				then `rbxthumb://type=AvatarHeadShot&id={entry.userId}&w=48&h=48`
				else ""
			if row.avatar.Image ~= image then
				row.avatar.Image = image
			end
		end
	end

	if board.empty then
		board.empty.Visible = #list == 0
	end
	if board.footer then
		setText(board.footer, if board.globalOk then "Updates every minute" else "This server only (global board offline)")
	end
end

local function renderAll()
	for _, board in BOARDS do
		render(board)
	end
end

-- ── DataStores ───────────────────────────────────────────────────────────────

local function resolveNames(userIds: { number })
	local missing = {}
	for _, id in userIds do
		if id > 0 and names[id] == nil then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			names[info.Id] = info.DisplayName or info.Username
		end
		return
	end
	-- One by one as a fallback; usernames rather than display names, but a name.
	for _, id in missing do
		local okName, username = pcall(Players.GetNameFromUserIdAsync, Players, id)
		if okName then
			names[id] = username
		end
	end
end

local function readBoard(board: Board)
	local store = board.store
	if not storesOnline or store == nil then
		board.globalOk = false
		return
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, TOP):GetCurrentPage()
	end)
	if not ok then
		warn(`[Leaderboard] reading {board.storeName} failed: {page}`)
		board.globalOk = false
		return
	end
	local list = {}
	local ids = {}
	for _, item in page do
		local userId = tonumber(item.key)
		if userId then
			table.insert(list, { userId = userId, value = item.value })
			table.insert(ids, userId)
		end
	end
	board.global = list
	board.globalOk = true
	resolveNames(ids)
end

--- Write this player's scores that changed since the last write. Safe to call from
--- anywhere: it reads the cached scores, never the profile, so it still works in
--- PlayerRemoving after DataService has let the profile go.
local function writeScores(userId: number, s: { [string]: number }?)
	if not storesOnline or s == nil or userId <= 0 then
		return
	end
	local last = written[userId] or {}
	written[userId] = last
	for _, board in BOARDS do
		local store = board.store
		local value = s[board.key]
		if store ~= nil and value ~= nil and last[board.key] ~= value then
			local ok, err = pcall(function()
				store:SetAsync(tostring(userId), value)
			end)
			if ok then
				last[board.key] = value
			else
				warn(`[Leaderboard] writing {board.storeName} for {userId} failed: {err}`)
			end
		end
	end
end

local function connectStores()
	-- Wait out ProfileStore's own probe rather than spending requests on a Studio
	-- session with API access off.
	local deadline = os.clock() + 15
	local state = DataService.dataStoreState()
	while state == "NotReady" and os.clock() < deadline do
		task.wait(0.25)
		state = DataService.dataStoreState()
	end
	if state ~= "Access" then
		return
	end
	for _, board in BOARDS do
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, board.storeName)
		if not ok then
			warn(`[Leaderboard] no OrderedDataStore {board.storeName}: {store}`)
			return
		end
		board.store = store
	end
	storesOnline = true
end

function LeaderboardService.init() end

function LeaderboardService.start()
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		cashValues[player] = nil
		speedValues[player] = nil
		local s = scores[player]
		scores[player] = nil
		task.spawn(writeScores, player.UserId, s)
	end)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	for i, board in BOARDS do
		buildBoard(board, BOARD_Z[i], folder)
	end
	folder.Parent = Workspace
	renderAll()

	task.spawn(function()
		while true do
			for player, value in cashValues do
				local data = DataService.data(player)
				if data ~= nil then
					local cash = math.floor(tonumber(data.cash) or 0)
					if value.Value ~= cash then
						value.Value = cash
					end
					local walk = Treadmill.walkSpeedFor((Treadmill.levelFor(data.speedPoints or 0)))
					local speedValue = speedValues[player]
					if speedValue ~= nil and speedValue.Value ~= walk then
						speedValue.Value = walk
					end
					scores[player] = {
						cash = clampScore(tonumber(data.cashEarned) or 0),
						speed = clampScore(walk),
					}
				end
			end
			task.wait(POLL)
		end
	end)

	task.spawn(function()
		connectStores()
		local lastRead, lastWrite = -math.huge, os.clock()
		while true do
			local now = os.clock()
			if storesOnline and now - lastWrite >= WRITE_EVERY then
				lastWrite = now
				for player, s in scores do
					task.spawn(writeScores, player.UserId, s)
				end
			end
			if now - lastRead >= READ_EVERY then
				lastRead = now
				for _, board in BOARDS do
					readBoard(board)
				end
			end
			renderAll()
			task.wait(RENDER_EVERY)
		end
	end)

	-- Last chance on shutdown: PlayerRemoving's writes may not finish before the
	-- server closes, so write everyone still cached and wait (bounded) for them.
	game:BindToClose(function()
		if not storesOnline then
			return
		end
		local pending = 0
		for player, s in scores do
			pending += 1
			task.spawn(function()
				writeScores(player.UserId, s)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return LeaderboardService
