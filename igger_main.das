require daslib/media
require strings

require levels

/*
TODO:
Controls: priority of last pressed
*/

let W = 15
let H = 10

let HERO_SPD = 3.0
let PUSH_SPD = 2.0
let ENEMY_SPD = 3.5
let ENEMY_SPAWN_DELAY = 5.0

let SCORE_DIAMOND = 25
let SCORE_GOLDPILE = 500
let SCORE_KILL = 200

let GOLD_TIME_TO_FALL = 1.5
let GOLD_FALL_SPEED = 6.0


bitfield Cell
	holeMid
	goldPile
	diamond

struct Goldbag
	pos : float2
	pushTarget : float2
	timeToFall : float
	fallen : int
	active : bool = true

struct Object
	pos: float2
	lookDir: int2

var hero : Object
var score  = 0
var lives  = 3
var curRun = 0
var curLevel = 0

var bags : array<Goldbag>
var enemies : array<Object>
var diamondCount = 0
var winLine = 0
var drawDebug = false

var heroSpawner : float2
var enemySpawner : float2
var nextSpawn : float

var cellSize = 72

var gnd : Cell[W * H]
var gndImgData : array<uint>
var gndImg <- create_image(get_screen_width(), get_screen_height())
var lastHolePos : float2
var hlinks : int[H]
var vlinks : int[W]

var tileImgData : array<uint>
var imgBack : Image

var dbgCellNow : float2
var dbgCellNew : float2

def drawTile(cellX, cellY : int)
	let sw = get_screen_width()
	let sh = get_screen_height()

	let baseX = cellSize / 2 + cellSize * cellX
	let baseY = cellSize / 2 + cellSize * cellY

	for iy in range(0, cellSize)
		for ix in range(0, cellSize)
			let x = baseX + ix
			let y = baseY + iy
			if x > 0 && x < sw && y > 0 && y < sh
				gndImgData[y * sw + x] = tileImgData[cellSize * iy + ix]

def toScreen(cellCoord: float2)
	return (cellCoord + float2(1.0, 1.0)) * float(cellSize)

def cutHole(cellCoord: float2 = hero.pos + float2(hero.lookDir) * 0.2)
	let cs = float(cellSize)
	let sw = get_screen_width()
	let holeSize = 0.45 * cs
	let c = toScreen(cellCoord)
	let fromY = int(c.y - holeSize)
	let toY = int(c.y + holeSize)
	let fromX = int(c.x - holeSize)
	let toX = int(c.x + holeSize)

	for y in range (fromY, toY)
		for x in range (fromX, toX)
			if sqr(float(x) - c.x) + sqr(float(y) - c.y) < sqr(holeSize)
				gndImgData[y * sw + x] = 0x66000000

	lastHolePos = cellCoord


def isDigged(l : string; x, y : int)
	if x < 0 || x >= W || y < 0 || y >= H
		return false
	let cell = character_at(l, y * W + x)
	return cell == 'X' || cell == 'S' || cell == 'H'

def spawn()
	hero.pos = heroSpawner
	hero.lookDir = int2(-1, 0)
	nextSpawn = get_time_after_start() + ENEMY_SPAWN_DELAY
	enemies |> clear()

def respawn()
	if (lives > 0)
		spawn()
		--lives
	else
		startGame()

def loadLevel(i: int)
	curLevel = i
	for y in range(-1, H + 1)
		for x in range(-1, W + 1)
			drawTile(x, y)

	winLine = 0
	imgBack <- create_image(levels[curLevel].fileBkg)
	diamondCount = 0
	bags |> clear()

	var hlinksI : int[H] // FIXME
	hlinks <- hlinksI
	var vlinksI : int[W]
	vlinks <- vlinksI

	let level = replace(levels[curLevel].data, "\n", "")
	for y in range(0, H)
		for x in range(0, W)
			let idx = y * W + x
			let cell = character_at(level, idx)
			gnd[idx] = bitfield(0)
			if isDigged(level, x, y)
				gnd[idx] |= Cell holeMid
				cutHole(float2(x, y))
				if isDigged(level, x - 1, y) || isDigged(level, x + 1, y) || cell == 'S'
					cutHole(float2(float(x) + 0.2, float(y)))
					cutHole(float2(float(x) - 0.2, float(y)))
					hlinks[y] |= (1 << (x - 1)) | (1 << x)
				if isDigged(level, x, y - 1) || cell == 'S'
					cutHole(float2(float(x), float(y) - 0.2))
					vlinks[x] |= 1 << (y - 1)
				if isDigged(level, x, y + 1) || cell == 'S'
					cutHole(float2(float(x), float(y) + 0.2))
					vlinks[x] |= 1 << y
			if cell == 'H'
				heroSpawner = float2(x, y)
			elif cell == 'S'
				enemySpawner = float2(x, y)
			elif cell == 'G'
				bags |> push([[Goldbag timeToFall = -1.0, pushTarget = float2(-1, -1), pos = float2(x, y), fallen = -1, active = true]])
			elif cell == 'D'
				gnd[idx] |= Cell diamond
				++diamondCount

	gndImg |> set_image_data(gndImgData)

	spawn()


def startGame()
	lives = 3
	score = 0
	curRun = 0
	loadLevel(0)


// 'initialize' runs once when game starts and every hot-reload
[export]
def initialize
	set_window_title("igger")

	let sw = get_screen_width()
	let sh = get_screen_height()

	cellSize = min(sw / (W + 1), sh / (H + 1))

	tileImgData |> resize(cellSize * cellSize)
	for y in range(0, cellSize)
		for x in range(0, cellSize)
			tileImgData[y * cellSize + x] = (y < 2 || y >= cellSize - 2) && (x < 2 || x >= cellSize - 2) ? 0xff996600 : 0xff663300

	gndImgData |> resize(sw * sh)

	startGame()

def updateWin(dt : float)
	let sw = get_screen_width()
	let sh = get_screen_height()
	let newLine = min(winLine + int(dt * float(sh)), sh)
	for y in range(winLine, newLine)
		for x in range(0, sw)
			gndImgData[y * sw + x] = 0x00000000
	gndImg |> set_image_data(gndImgData)
	winLine = newLine

	if winLine > sh /2 && (get_key(VK_LEFT) || get_key(VK_RIGHT) || get_key(VK_UP) || get_key(VK_DOWN) || get_key(VK_SPACE))
		if curLevel == levels |> length() - 1
			++curRun
		loadLevel((curLevel + 1) % levels |> length())

def hasLinkLeft(x, y : int)
	return y >= 0 && y < H && x >= 1 && x < W && (hlinks[y] & (1 << (x - 1))) != 0

def hasLinkRight(x, y : int)
	return y >= 0 && y < H && x >= 0 && x < W - 1 && (hlinks[y] & (1 << x)) != 0

def hasLinkUp(x, y : int)
	return x >= 0 && x < W && y >= 1 && y < H && (vlinks[x] & (1 << (y - 1))) != 0

def hasLinkDown(x, y : int)
	return x >= 0 && x < W && y >= 0 && y < H - 1 && (vlinks[x] & (1 << y)) != 0


def updateHero(dt : float)
	if get_key(VK_LEFT) || get_key(VK_RIGHT) || get_key(VK_UP) || get_key(VK_DOWN)
		var d = dt * HERO_SPD
		let curCell = float2(floor(hero.pos.x + 0.5), floor(hero.pos.y + 0.5))
		let curIdx = int(curCell.y) * W + int(curCell.x)
		var nextCell : float2
		nextCell.x = floor(clamp(hero.pos.x + 0.5 + float(hero.lookDir.x) * 0.5, 0.0, float(W - 1)))
		nextCell.y = floor(clamp(hero.pos.y + 0.5 + float(hero.lookDir.y) * 0.5, 0.0, float(H - 1)))
		let nextIdx = int(nextCell.y) * W + int(nextCell.x)
		let dist = nextCell - hero.pos
		var bump = false
		if (hero.lookDir.x != 0)
			if (dist.x < -0.5)
				hlinks[int(nextCell.y)] |= 1 << int(nextCell.x)
			elif (dist.x > 0.5)
				hlinks[int(nextCell.y)] |= 1 << int(nextCell.x) - 1
			else
				gnd[nextIdx] |= Cell holeMid
			let newPos = hero.pos + d * float2(hero.lookDir)
			for gb in bags
				if (gb.active && gb.fallen < 0)
					if abs(gb.pos.x - nextCell.x) < 0.1 && abs(gb.pos.y - nextCell.y) < 0.1
						gb.pushTarget = nextCell + float2(hero.lookDir)
					if abs(gb.pos.x - newPos.x) < 0.7 && abs(gb.pos.y - newPos.y) < 0.7
						d = dt * PUSH_SPD

		if (hero.lookDir.y != 0)
			if (dist.y < -0.5)
				vlinks[int(nextCell.x)] |= 1 << int(nextCell.y)
			elif (dist.y > 0.5)
				vlinks[int(nextCell.x)] |= 1 << int(nextCell.y) - 1
			else
				gnd[nextIdx] |= Cell holeMid
			for gb in bags
				if (gb.active && gb.fallen < 0)
					if abs(gb.pos.x - nextCell.x) < 0.1 && abs(gb.pos.y - nextCell.y) < 0.1
						bump = true

		if get_key(VK_LEFT) || get_key(VK_RIGHT)
			let toY = hero.lookDir.y != 0 && !bump? dist.y : 0.0
			if abs(toY) < d
				hero.pos.y += toY
				d -= abs(toY)
				if hero.lookDir.y != 0 && !bump
					vlinks[int(nextCell.x)] |= 1 << (int(nextCell.y) + (hero.lookDir.y > 0 ? 0 : -1))
					cutHole()
				hero.lookDir = int2(get_key(VK_LEFT) ? -1 : 1, 0)
		if get_key(VK_UP) || get_key(VK_DOWN)
			let toX = hero.lookDir.x != 0 ? dist.x : 0.0
			if abs(toX) < d
				hero.pos.x += toX
				d -= abs(toX)
				if hero.lookDir.x != 0
					hlinks[int(nextCell.y)] |= 1 << (int(nextCell.x) + (hero.lookDir.x > 0 ? 0 : -1))
					cutHole()
				hero.lookDir = int2(0, get_key(VK_UP) ? -1 : 1)

		if !bump
			hero.pos += d * float2(hero.lookDir)
			hero.pos.x = clamp(hero.pos.x, 0.0, float(W - 1))
			hero.pos.y = clamp(hero.pos.y, 0.0, float(H - 1))
		else
			hero.pos = float2(floor(hero.pos.x + 0.5), floor(hero.pos.y + 0.5))
		if true //length_sq(hero.pos + float2(hero.lookDir) * 0.3 - lastHolePos) > 0.3
			cutHole()
		if (gnd[nextIdx].diamond && length_sq(nextCell - hero.pos) < sqr(0.5))
			gnd[nextIdx] ^= Cell diamond
			score += SCORE_DIAMOND
			--diamondCount
		if (gnd[nextIdx].goldPile && length_sq(nextCell - hero.pos) < sqr(0.5))
			gnd[nextIdx] ^= Cell goldPile
			score += SCORE_GOLDPILE

		let aboveIdx = (int(nextCell.y) - 1) * W + int(nextCell.x)
		for gb in bags
			if (gb.active && gb.timeToFall < 0.0 && gb.fallen < 0)
				let gbCellIdx = floori(gb.pos.y + 0.5) * W + floori(gb.pos.x + 0.5)
				if gbCellIdx == aboveIdx
					gb.timeToFall = GOLD_TIME_TO_FALL

		gndImg |> set_image_data(gndImgData)


def updateGold(dt : float)
	var heroDied = false
	for gb in bags
		if (!gb.active)
			continue
		if (gb.pushTarget.x >= 0.0)
			let dirX = sign(gb.pushTarget.x - gb.pos.x)
			var nextPos = gb.pos + float2(dirX, 0.0) * dt * PUSH_SPD
			if (dirX * nextPos.x > dirX * gb.pushTarget.x)
				nextPos.x = gb.pushTarget.x
				gb.pushTarget.x = -1.0
				let cx = floori(gb.pos.x + 0.5)
				let cy = floori(gb.pos.y + 0.5) + 1
				let idxNew = cy * W + cx
				if gnd[idxNew].holeMid || hasLinkUp(cx, cy) || hasLinkDown(cx, cy)
					gb.timeToFall = 0.01

			gb.pos = nextPos
		if (gb.timeToFall > 0.0)
			gb.timeToFall -= dt
			if (gb.timeToFall <= 0.0)
				gb.fallen = 0;
		if (gb.fallen >= 0)
			let nextPos = gb.pos + float2(0.0, dt * GOLD_FALL_SPEED)
			let gbx = floori(gb.pos.x + 0.5)
			let cellNow = floori(gb.pos.y) + 1
			let cellNew = floori(nextPos.y) + 1
			let idxNow = cellNow * W + gbx
			let idxNew = cellNew * W + gbx
			if cellNow != cellNew
				vlinks[gbx] |= 1 << (cellNow - 1)
				gnd[idxNow] |= Cell holeMid
				++gb.fallen
				dbgCellNow = float2(gbx, cellNow)
				dbgCellNew = float2(gbx, cellNew)
				if cellNew >= H || !gnd[idxNew].holeMid && !hasLinkUp(gbx, cellNew) && !hasLinkDown(gbx, cellNew)
					if (gb.fallen > 1)
						gnd[idxNow] |= Cell goldPile
						gb.active = false
					gb.fallen = -1
			if (gb.fallen >= 1)
				cutHole(nextPos)
				gndImg |> set_image_data(gndImgData)
			gb.pos = nextPos
			if (length_sq(gb.pos - hero.pos) < sqr(0.7))
				heroDied = true
			var ie = 0
			while ie < enemies |> length()
				if (length_sq(gb.pos - enemies[ie].pos) < sqr(0.7))
					enemies |> erase(ie)
					score += SCORE_KILL
				else
					++ie
	if (heroDied)
		respawn()

def updateEnemies(dt : float)
	if enemies |> length() < levels[curLevel].enemyCount && get_time_after_start() >= nextSpawn
		enemies |> push([[Object pos = enemySpawner, lookDir = int2(-1, 0)]])
		nextSpawn = get_time_after_start() + ENEMY_SPAWN_DELAY

	var heroDied = false
	for e in enemies
		var d = dt * ENEMY_SPD
		var nextPos = e.pos + float2(e.lookDir) * d
		if floori(e.pos.x) != floori(nextPos.x) || floori(e.pos.y) != floori(nextPos.y)
			let curCell = float2(floor(e.pos.x + 0.5), floor(e.pos.y + 0.5))
			let curIdx = int(curCell.y) * W + int(curCell.x)

			let dirs = [[int2 int2(0, -1); int2(0, 1); int2(-1, 0); int2(1, 0)]]
			var rates : int[4]

			let up = curCell + float2(dirs[0])
			let upIdx = int(up.y) * W + int(up.x)
			if upIdx >= 0 && upIdx < W * H && gnd[upIdx].holeMid && hasLinkUp(int(curCell.x), int(curCell.y))
				rates[0] += 8

			let down = curCell + float2(0, 1)
			let downIdx = int(down.y) * W + int(down.x)
			if downIdx >= 0 && downIdx < W * H && gnd[downIdx].holeMid && hasLinkDown(int(curCell.x), int(curCell.y))
				rates[1] += 8

			let left = curCell + float2(-1, 0)
			let leftIdx = int(left.y) * W + int(left.x)
			if leftIdx >= 0 && leftIdx < W * H && gnd[leftIdx].holeMid && hasLinkLeft(int(curCell.x), int(curCell.y))
				rates[2] += 8

			let right = curCell + float2(1, 0)
			let rightIdx = int(right.y) * W + int(right.x)
			if rightIdx >= 0 && rightIdx < W * H && gnd[rightIdx].holeMid && hasLinkRight(int(curCell.x), int(curCell.y))
				rates[3] += 8

			if e.lookDir.x < 0
				rates[3] -= 4
				rates[2] += 1
			elif e.lookDir.x > 0
				rates[2] -= 4
				rates[3] += 1
			elif e.lookDir.y < 0
				rates[1] -= 4
				rates[0] += 1
			elif e.lookDir.y > 0
				rates[0] -= 4
				rates[1] += 1

			if e.pos.x - hero.pos.x > 0.5
				rates[2] += 2
			elif e.pos.x - hero.pos.x < -0.5
				rates[3] += 2
			if e.pos.y - hero.pos.y > 0.5
				rates[0] += 2
			elif e.pos.y - hero.pos.y < -0.5
				rates[1] += 2

			var maxEl = 0
			for i in range(1, 4)
				if rates[i] > rates[maxEl]
					maxEl = i

			e.lookDir = dirs[maxEl]
			nextPos = curCell + float2(e.lookDir) * (d - length(e.pos - curCell))
		e.pos = nextPos
		if (length_sq(e.pos - hero.pos) < sqr(0.7))
			heroDied = true

	if heroDied
		respawn()


// this function is called to update game data,
// dt - time elapsed since the previous update (in seconds)
[export]
def act(dt: float)
	if get_key(VK_ESCAPE)
		schedule_quit_game()

	if (diamondCount == 0)
		updateWin(dt)
		return

	updateHero(dt)
	updateGold(dt)
	updateEnemies(dt)

	if (get_key_press(VK_1))
		drawDebug = !drawDebug

	if (get_key_press(VK_2))
		nextSpawn = 0.0

	if (get_key(VK_9))
		diamondCount = 0

	return

// this function will be called every frame after 'act',
// you can draw anything in this function
[export]
def draw
	let cs = float(cellSize)
//	enable_alpha_blend()
	enable_premultiplied_alpha_blend()
	imgBack |> draw_image(0, 0)

	if drawDebug && diamondCount > 0
		for y in range(0, H)
			for x in range(0, W)
				let c0 = float2(float(x) + 0.5, float(y) + 0.5) * cs
				let c:Cell = gnd[y * W + x]
				fill_rect(c0.x, c0.y, cs, cs, 0x66000000)
				fill_rect(c0.x, c0.y, cs * 0.2, cs * 0.2, 0xff663300)
				fill_rect(c0.x + cs * 0.8, c0.y, cs * 0.2, cs * 0.2, 0xff663300)
				fill_rect(c0.x, c0.y + cs * 0.8, cs * 0.2, cs * 0.2, 0xff663300)
				fill_rect(c0.x + cs * 0.8, c0.y + cs * 0.8, cs * 0.2, cs * 0.2, 0xff663300)
//				if !c.holeLeft
				if !hasLinkLeft(x, y)
					fill_rect(c0.x, c0.y, cs * 0.2, cs, 0xff663300)
//				if !c.holeRight
				if !hasLinkRight(x, y)
					fill_rect(c0.x + float(cellSize) * 0.8, c0.y, float(cellSize) * 0.2, float(cellSize), 0xff663300)
//				if !c.holeUp
				if !hasLinkUp(x, y)
					fill_rect(c0.x, c0.y, float(cellSize), float(cellSize) * 0.2, 0xff663300)
//				if !c.holeDown
				if !hasLinkDown(x, y)
					fill_rect(c0.x, c0.y + float(cellSize) * 0.8, float(cellSize), float(cellSize) * 0.2, 0xff663300)
				if !c.holeMid
					fill_rect(c0.x + float(cellSize) * 0.2, c0.y + float(cellSize) * 0.2, float(cellSize) * 0.6, float(cellSize) * 0.6, 0xff663300)
	else
		gndImg |> draw_image(0, 0)

	disable_alpha_blend()

	text_out(float((W + 2) * cellSize), 10.0, curRun > 0 ? "LEVEL: {curLevel + 1} [{curRun}x]" : "LEVEL: {curLevel+1}", 0xffffffff)
	text_out(float((W + 2) * cellSize), 30.0, "SCORE: {score}", 0xffffffff)
	text_out(float((W + 2) * cellSize), 50.0, "LIVES: {lives}", 0xffffffff)

	if diamondCount > 0
		let X = hero.pos.x
		let Y = hero.pos.y
		let nextX = floor(clamp(hero.pos.x + 0.5 + float(hero.lookDir.x) * 0.5, 0.5, float(W) - 0.5))
		let nextY = floor(clamp(hero.pos.y + 0.5 + float(hero.lookDir.y) * 0.5, 0.5, float(H) - 0.5))
		let targetX = float(nextX) - X
		let targetY = float(nextY) - Y
		text_out(0, 0, "{X},{Y} -> {targetX},{targetY} {nextX},{nextY}", 0xffffff)

		let c = toScreen(hero.pos)
		let cEye = toScreen(hero.pos + float2(hero.lookDir) * 0.2)
		fill_circle(c.x, c.y, cs * 0.4, 0xffff99ff)
		fill_circle(cEye.x, cEye.y, cs * 0.1, 0xff000000)

		for y in range(0, H)
			for x in range(0, W)
				let idx = y * W + x
				let c0 = toScreen(float2(x, y))
				if gnd[idx].diamond
					fill_circle(c0.x, c0.y, cs * 0.2, 0xffffffff)
				elif gnd[idx].goldPile
					fill_circle(c0.x, c0.y, cs * 0.1, 0xffffff00)

		for gb in bags
			if (gb.active)
				let c0 = toScreen(gb.pos)
				let r = gb.timeToFall > 0.0 ? (GOLD_TIME_TO_FALL - gb.timeToFall) * 0.1 * cs : 0.0
				fill_circle(c0.x, c0.y, cs * 0.3 + r, 0xffffff00)

		for e in enemies
			let ce = toScreen(e.pos)
			let ceEye = toScreen(e.pos + float2(e.lookDir) * 0.2)
			fill_circle(ce.x, ce.y, cs * 0.4, 0xffff3333)
			fill_circle(ceEye.x, ceEye.y, cs * 0.1, 0xffffff33)

		var dbgcn = toScreen(dbgCellNew)
		rect(dbgcn.x - cs * 0.5, dbgcn.y - cs * 0.5, cs, cs, 0xffffff00)
		dbgcn = toScreen(dbgCellNow)
		rect(dbgcn.x - cs * 0.45, dbgcn.y - cs * 0.45, cs * 0.9, cs * 0.9, 0xff00ffff)
	else
		let hint = "PRESS SPACE"
		let l = get_text_size(hint)
		text_out(((W + 1)* cellSize - int(l.x)) / 2, get_screen_height() - 50, hint, 0xffffffff)

	return
