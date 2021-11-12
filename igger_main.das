require daslib/media
require strings

require levels

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
    fallenDist : float
    active : bool

struct Creature
    pos: float2
    lookDir: int2


var hero : Creature
var score  = 0
var lives  = 3
var curRun = 0
var curLevel = 0
var activeControl = 0
var bags : array<Goldbag>
var enemies : array<Creature>
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
var gndDirty : bool
var lastHolePos : float2
var hlinks : int[H]
var vlinks : int[W]

var tileImgData : array<uint>
var imgBack : Image


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
    gndDirty = true

def updateGnd()
    if gndDirty
        gndImg |> set_image_data(gndImgData)
        gndDirty = false


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

    for y in range(0, cellSize)
        for x in range(0, cellSize)
            tileImgData[y * cellSize + x] = (y < 2 || y >= cellSize - 2) && (x < 2 || x >= cellSize - 2) ? 0xff996600 : levels[curLevel].tileColor

    for y in range(-1, H + 1)
        for x in range(-1, W + 1)
            drawTile(x, y)

    winLine = 0
    imgBack <- create_image(levels[curLevel].fileBkg)
    diamondCount = 0
    bags |> clear()

    for l in hlinks
        l = 0
    for l in vlinks
        l = 0

    let level = replace(levels[curLevel].data, "\n", "")
    for y in range(0, H)
        for x in range(0, W)
            let cell = int2(x, y)
            let idx = getCellIdx(cell)
            let cellChar = character_at(level, idx)
            gnd[idx] = bitfield(0)
            if isDigged(level, x, y)
                gnd[idx] |= Cell holeMid
                cutHole(float2(x, y))
                if isDigged(level, x - 1, y) || isDigged(level, x + 1, y) || cellChar == 'S'
                    cutHole(float2(float(x) + 0.2, float(y)))
                    cutHole(float2(float(x) - 0.2, float(y)))
                    setLinkLeft(cell)
                    setLinkRight(cell)
                if isDigged(level, x, y - 1) || cellChar == 'S'
                    cutHole(float2(float(x), float(y) - 0.2))
                    setLinkUp(cell)
                if isDigged(level, x, y + 1) || cellChar == 'S'
                    cutHole(float2(float(x), float(y) + 0.2))
                    setLinkDown(cell)
            if cellChar == 'H'
                heroSpawner = float2(x, y)
            elif cellChar == 'S'
                enemySpawner = float2(x, y)
            elif cellChar == 'G'
                bags |> push([[Goldbag timeToFall = -1.0, pushTarget = float2(-1, -1), pos = float2(x, y), fallenDist = -1.0, active = true]])
            elif cellChar == 'D'
                gnd[idx] |= Cell diamond
                ++diamondCount
    updateGnd()

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


def hasLinkLeft(c : int2)
    return c.y >= 0 && c.y < H && c.x >= 1 && c.x < W && (hlinks[c.y] & (1 << (c.x - 1))) != 0

def hasLinkRight(c : int2)
    return c.y >= 0 && c.y < H && c.x >= 0 && c.x < W - 1 && (hlinks[c.y] & (1 << c.x)) != 0

def hasLinkUp(c : int2)
    return c.x >= 0 && c.x < W && c.y >= 1 && c.y < H && (vlinks[c.x] & (1 << (c.y - 1))) != 0

def hasLinkDown(c : int2)
    return c.x >= 0 && c.x < W && c.y >= 0 && c.y < H - 1 && (vlinks[c.x] & (1 << c.y)) != 0


def setLinkLeft(c : int2)
    if c.y >= 0 && c.y < H && c.x >= 1 && c.x < W
        hlinks[c.y] |= 1 << (c.x - 1)
def setLinkRight(c : int2)
    if c.y >= 0 && c.y < H && c.x >= 0 && c.x < W - 1
        hlinks[c.y] |= 1 << c.x
def setLinkUp(c : int2)
    if c.x >= 0 && c.x < W && c.y >= 1 && c.y < H
        vlinks[c.x] |= 1 << (c.y - 1)
def setLinkDown(c : int2)
    if c.x >= 0 && c.x < W && c.y >= 0 && c.y < H - 1
        vlinks[c.x] |= 1 << c.y


def getCellMid(pos : float2)
    return float2(floor(pos.x + 0.5), floor(pos.y + 0.5))

def getCell(pos : float2)
    return int2(floori(pos.x + 0.5), floori(pos.y + 0.5))

def getCellIdx(cell : int2)
    return cell.y * W + cell.x

def getCellIdx(pos : float2)
    let cell = getCell(pos)
    return getCellIdx(cell)

def getNextCellMid(c: Creature)
    var nextCell : float2
    nextCell.x = floor(clamp(c.pos.x + 0.5 + float(c.lookDir.x) * 0.5, 0.0, float(W - 1)))
    nextCell.y = floor(clamp(c.pos.y + 0.5 + float(c.lookDir.y) * 0.5, 0.0, float(H - 1)))
    return nextCell


def updateHero(dt : float)
    let controls = [[int VK_LEFT; VK_RIGHT; VK_UP; VK_DOWN]]
    for c in controls
        if get_key_press(c)
            activeControl = c
    if !get_key(activeControl)
        activeControl = 0
        for c in controls
            if get_key(c)
                activeControl = c

    if activeControl != 0
        var d = dt * HERO_SPD
        let curIdx = getCellIdx(hero.pos)
        let nextCellMid = getNextCellMid(hero)
        let nextCell = int2(nextCellMid)
        let nextIdx = getCellIdx(nextCellMid)
        let dist = nextCellMid - hero.pos
        var bump = false
        if (hero.lookDir.x != 0)
            if (dist.x < -0.5)
                setLinkRight(nextCell)
            elif (dist.x > 0.5)
                setLinkLeft(nextCell)
            else
                gnd[nextIdx] |= Cell holeMid
            let newPos = hero.pos + d * float2(hero.lookDir)
            for gb in bags
                if (gb.active && gb.fallenDist < 0.0)
                    if abs(gb.pos.x - nextCellMid.x) < 0.1 && abs(gb.pos.y - nextCellMid.y) < 0.1 && gb.pushTarget.x < 0.0
                        let target = nextCellMid + float2(hero.lookDir)
                        if target.x < 0.0 || target.x >= float(W)
                            bump = true
                        else
                            gb.pushTarget = target
                    if abs(gb.pos.x - newPos.x) < 0.7 && abs(gb.pos.y - newPos.y) < 0.7
                        d = dt * PUSH_SPD

        if (hero.lookDir.y != 0)
            if (dist.y < -0.5)
                setLinkDown(nextCell)
            elif (dist.y > 0.5)
                setLinkUp(nextCell)
            else
                gnd[nextIdx] |= Cell holeMid
            for gb in bags
                if (gb.active && gb.fallenDist < 0.0)
                    if abs(gb.pos.x - nextCellMid.x) < 0.1 && abs(gb.pos.y - nextCellMid.y) < 0.1
                        bump = true

        if activeControl == VK_LEFT || activeControl == VK_RIGHT
            let toY = hero.lookDir.y != 0 && !bump ? dist.y : 0.0
            if abs(toY) < d
                hero.pos.y += toY
                d -= abs(toY)
                if hero.lookDir.y != 0 && !bump
                    if hero.lookDir.y > 0
                        setLinkDown(nextCell)
                    else
                        setLinkUp(nextCell)
                    cutHole()
                hero.lookDir = int2(activeControl == VK_LEFT ? -1 : 1, 0)
        if activeControl == VK_UP || activeControl == VK_DOWN
            let toX = hero.lookDir.x != 0 && !bump ? dist.x : 0.0
            if abs(toX) < d
                hero.pos.x += toX
                d -= abs(toX)
                if hero.lookDir.x != 0 && !bump
                    if hero.lookDir.X > 0
                        setLinkRight(nextCell)
                    else
                        setLinkLeft(nextCell)
                    cutHole()
                hero.lookDir = int2(0, activeControl == VK_UP ? -1 : 1)

        if !bump
            hero.pos += d * float2(hero.lookDir)
            hero.pos.x = clamp(hero.pos.x, 0.0, float(W - 1))
            hero.pos.y = clamp(hero.pos.y, 0.0, float(H - 1))
        else
            hero.pos = getCellMid(hero.pos)
        if length_sq(hero.pos + float2(hero.lookDir) * 0.3 - lastHolePos) > 0.3
            cutHole()
        if (gnd[nextIdx].diamond && length_sq(nextCellMid - hero.pos) < sqr(0.5))
            gnd[nextIdx] ^= Cell diamond
            score += SCORE_DIAMOND
            --diamondCount
        if (gnd[nextIdx].goldPile && length_sq(nextCellMid - hero.pos) < sqr(0.5))
            gnd[nextIdx] ^= Cell goldPile
            score += SCORE_GOLDPILE

        let aboveIdx = (int(nextCellMid.y) - 1) * W + int(nextCellMid.x)
        for gb in bags
            if (gb.active && gb.timeToFall < 0.0 && gb.fallenDist < 0.0)
                let gbCellIdx = floori(gb.pos.y + 0.5) * W + floori(gb.pos.x + 0.5)
                if gbCellIdx == aboveIdx
                    gb.timeToFall = GOLD_TIME_TO_FALL

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
                let belowCell = getCell(gb.pos) + int2(0, 1)
                let idxNew = getCellIdx(belowCell)
                if gnd[idxNew].holeMid || hasLinkUp(belowCell) || hasLinkDown(belowCell)
                    gb.timeToFall = 0.0
            gb.pos = nextPos

        if (gb.timeToFall >= 0.0)
            gb.timeToFall -= dt
            if (gb.timeToFall < 0.0)
                gb.fallenDist = 0.0;

        if (gb.fallenDist >= 0.0)
            gb.fallenDist += dt * GOLD_FALL_SPEED
            let nextPos = gb.pos + float2(0.0, dt * GOLD_FALL_SPEED)
            let gbx = floori(gb.pos.x + 0.5)
            let cellNow = int2(gbx, floori(gb.pos.y) + 1)
            let cellNew = int2(gbx, floori(nextPos.y) + 1)
            if cellNow != cellNew
                let idxNow = getCellIdx(cellNow)
                let idxNew = getCellIdx(cellNew)
                cutHole(nextPos)
                setLinkUp(cellNow)
                gnd[idxNow] |= Cell holeMid
                if cellNew.y >= H || !gnd[idxNew].holeMid && !hasLinkUp(cellNew) && !hasLinkDown(cellNew)
                    if (gb.fallenDist >= 1.5)
                        gnd[idxNow] |= Cell goldPile
                        gb.active = false
                    gb.fallenDist = -1.0
            if (gb.fallenDist >= 1.0)
                cutHole(nextPos)
            gb.pos = nextPos
            if (length_sq(gb.pos - hero.pos) < sqr(0.7) && gb.fallenDist > 0.5)
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


def enemyChooseDirection(var e : Creature)
    let curCellMid = getCellMid(e.pos)
    let curCell = int2(curCellMid)
    let curIdx = getCellIdx(curCell)

    let dirs = [[int2 int2(0, -1); int2(0, 1); int2(-1, 0); int2(1, 0)]]
    var rates : int[4]

    let up = curCell + dirs[0]
    let upIdx = getCellIdx(up)
    if upIdx >= 0 && upIdx < W * H && gnd[upIdx].holeMid && hasLinkUp(curCell)
        rates[0] += 8

    let down = curCell + dirs[1]
    let downIdx = getCellIdx(down)
    if downIdx >= 0 && downIdx < W * H && gnd[downIdx].holeMid && hasLinkDown(curCell)
        rates[1] += 8

    let left = curCell + dirs[2]
    let leftIdx = getCellIdx(left)
    if leftIdx >= 0 && leftIdx < W * H && gnd[leftIdx].holeMid && hasLinkLeft(curCell)
        rates[2] += 8

    let right = curCell + dirs[3]
    let rightIdx = getCellIdx(right)
    if rightIdx >= 0 && rightIdx < W * H && gnd[rightIdx].holeMid && hasLinkRight(curCell)
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


def updateEnemies(dt : float)
    if enemies |> length() < levels[curLevel].enemyCount && get_time_after_start() >= nextSpawn
        enemies |> push([[Creature pos = enemySpawner, lookDir = int2(-1, 0)]])
        nextSpawn = get_time_after_start() + ENEMY_SPAWN_DELAY

    var heroDied = false
    for e in enemies
        var d = dt * ENEMY_SPD
        var nextPos = e.pos + float2(e.lookDir) * d
        if floori(e.pos.x) != floori(nextPos.x) || floori(e.pos.y) != floori(nextPos.y)
            enemyChooseDirection(e)
            let curCellMid = getCellMid(e.pos)
            nextPos = curCellMid + float2(e.lookDir) * (d - length(e.pos - curCellMid))
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
    updateGnd()

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
    enable_premultiplied_alpha_blend()
    imgBack |> draw_image(0, 0)

    if drawDebug && diamondCount > 0
        for y in range(0, H)
            for x in range(0, W)
                let c0 = float2(float(x) + 0.5, float(y) + 0.5) * cs
                let cell = int2(x,y)
                let cellIdx = getCellIdx(cell)
                fill_rect(c0.x, c0.y, cs, cs, 0x66000000)
                fill_rect(c0.x, c0.y, cs * 0.2, cs * 0.2, 0xff663300)
                fill_rect(c0.x + cs * 0.8, c0.y, cs * 0.2, cs * 0.2, 0xff663300)
                fill_rect(c0.x, c0.y + cs * 0.8, cs * 0.2, cs * 0.2, 0xff663300)
                fill_rect(c0.x + cs * 0.8, c0.y + cs * 0.8, cs * 0.2, cs * 0.2, 0xff663300)
                if !hasLinkLeft(cell)
                    fill_rect(c0.x, c0.y, cs * 0.2, cs, 0xff663300)
                if !hasLinkRight(cell)
                    fill_rect(c0.x + float(cellSize) * 0.8, c0.y, float(cellSize) * 0.2, float(cellSize), 0xff663300)
                if !hasLinkUp(cell)
                    fill_rect(c0.x, c0.y, float(cellSize), float(cellSize) * 0.2, 0xff663300)
                if !hasLinkDown(cell)
                    fill_rect(c0.x, c0.y + float(cellSize) * 0.8, float(cellSize), float(cellSize) * 0.2, 0xff663300)
                if !gnd[cellIdx].holeMid
                    fill_rect(c0.x + float(cellSize) * 0.2, c0.y + float(cellSize) * 0.2, float(cellSize) * 0.6, float(cellSize) * 0.6, 0xff663300)
    else
        gndImg |> draw_image(0, 0)

    disable_alpha_blend()

    text_out(float((W + 2) * cellSize), 10.0, curRun > 0 ? "LEVEL: {curLevel + 1} [{curRun}x]" : "LEVEL: {curLevel+1}", 0xffffffff)
    text_out(float((W + 2) * cellSize), 30.0, "SCORE: {score}", 0xffffffff)
    text_out(float((W + 2) * cellSize), 50.0, "LIVES: {lives}", 0xffffffff)

    if diamondCount > 0
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
                    fill_circle(c0.x, c0.y + cs * 0.2, cs * 0.1, 0xffffff00)
                    fill_circle(c0.x - cs * 0.2, c0.y + cs * 0.2, cs * 0.1, 0xffffff00)
                    fill_circle(c0.x + cs * 0.2, c0.y + cs * 0.2, cs * 0.1, 0xffffff00)

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
    else
        let hint = "PRESS SPACE"
        let l = get_text_size(hint)
        text_out(((W + 1)* cellSize - int(l.x)) / 2, get_screen_height() - 50, hint, 0xffffffff)

    return
