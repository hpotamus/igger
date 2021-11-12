require daslib/media
require strings

require levels
require board


let HERO_SPD = 3.0
let PUSH_SPD = 2.0
let ENEMY_SPD = 3.5
let ENEMY_SPAWN_DELAY = 5.0

let SCORE_DIAMOND = 25
let SCORE_GOLDPILE = 500
let SCORE_KILL = 200

let GOLD_TIME_TO_FALL = 1.5
let GOLD_FALL_SPEED = 6.0

let dirUp = 0
let dirDown = 1
let dirLeft = 2
let dirRight = 3
let dirs = [[int2 int2(0, -1); int2(0, 1); int2(-1, 0); int2(1, 0)]]


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

var gndImgData : array<uint>
var gndImg <- create_image(get_screen_width(), get_screen_height())
var gndDirty : bool
var lastHolePos : float2

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

def drawHole(cellCoord: float2 = hero.pos + float2(hero.lookDir) * 0.2)
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


def spawn()
    hero.pos = heroSpawner
    hero.lookDir = dirs[dirLeft]
    nextSpawn = get_time_after_start() + ENEMY_SPAWN_DELAY
    enemies |> clear()

def respawn()
    if (lives > 0)
        spawn()
        --lives
    else
        startGame()


def isDigged(l : string; x, y : int)
    if x < 0 || x >= W || y < 0 || y >= H
        return false
    let cell = character_at(l, y * W + x)
    return cell == 'X' || cell == 'S' || cell == 'H'

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
    clearBoard()

    let level = replace(levels[curLevel].data, "\n", "")
    for y in range(0, H)
        for x in range(0, W)
            let cell = int2(x, y)
            let cellChar = character_at(level, getCellIdx(cell))
            if isDigged(level, x, y)
                setHole(cell)
                drawHole(float2(x, y))
                if isDigged(level, x - 1, y) || isDigged(level, x + 1, y) || cellChar == 'S'
                    setLinkLeft(cell)
                    setLinkRight(cell)
                    drawHole(float2(float(x) + 0.2, float(y)))
                    drawHole(float2(float(x) - 0.2, float(y)))
                if isDigged(level, x, y - 1) || cellChar == 'S'
                    setLinkUp(cell)
                    drawHole(float2(float(x), float(y) - 0.2))
                if isDigged(level, x, y + 1) || cellChar == 'S'
                    setLinkDown(cell)
                    drawHole(float2(float(x), float(y) + 0.2))
            if cellChar == 'H'
                heroSpawner = float2(x, y)
            elif cellChar == 'S'
                enemySpawner = float2(x, y)
            elif cellChar == 'G'
                bags |> push([[Goldbag timeToFall = -1.0, pushTarget = float2(-1, -1), pos = float2(x, y), fallenDist = -1.0, active = true]])
            elif cellChar == 'D'
                toggleDiamond(cell)
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


def getNextCellMid(c : Creature)
    var nextCell : float2
    nextCell.x = floor(clamp(c.pos.x + 0.5 + float(c.lookDir.x) * 0.5, 0.0, float(W - 1)))
    nextCell.y = floor(clamp(c.pos.y + 0.5 + float(c.lookDir.y) * 0.5, 0.0, float(H - 1)))
    return nextCell


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
        let nextCellMid = getNextCellMid(hero)
        let nextCell = int2(nextCellMid)
        let dist = nextCellMid - hero.pos
        var bump = false
        if (hero.lookDir.x != 0)
            if (dist.x < -0.5)
                setLinkRight(nextCell)
            elif (dist.x > 0.5)
                setLinkLeft(nextCell)
            else
                setHole(nextCell)
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
                setHole(nextCell)
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
                    drawHole()
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
                    drawHole()
                hero.lookDir = int2(0, activeControl == VK_UP ? -1 : 1)

        if !bump
            hero.pos += d * float2(hero.lookDir)
            hero.pos.x = clamp(hero.pos.x, 0.0, float(W - 1))
            hero.pos.y = clamp(hero.pos.y, 0.0, float(H - 1))
        else
            hero.pos = getCellMid(hero.pos)
        if length_sq(hero.pos + float2(hero.lookDir) * 0.3 - lastHolePos) > 0.3
            drawHole()
        if (hasDiamond(nextCell) && length_sq(nextCellMid - hero.pos) < sqr(0.5))
            toggleDiamond(nextCell)
            score += SCORE_DIAMOND
            --diamondCount
        if (hasGoldPile(nextCell) && length_sq(nextCellMid - hero.pos) < sqr(0.5))
            toggleGoldPile(nextCell)
            score += SCORE_GOLDPILE

        let aboveCell = nextCell + int2(0, -1)
        for gb in bags
            if (gb.active && gb.timeToFall < 0.0 && gb.fallenDist < 0.0 && getCell(gb.pos) == aboveCell)
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
                if hasHole(belowCell) || hasLinkUp(belowCell) || hasLinkDown(belowCell)
                    gb.timeToFall = 0.0
            gb.pos = nextPos

        if (gb.timeToFall >= 0.0)
            gb.timeToFall -= dt
            if (gb.timeToFall < 0.0)
                gb.fallenDist = 0.0;

        if (gb.fallenDist >= 0.0)
            gb.fallenDist += dt * GOLD_FALL_SPEED
            let nextPos = gb.pos + float2(0.0, dt * GOLD_FALL_SPEED)
            let cellNow = int2(floori(gb.pos.x + 0.5), floori(gb.pos.y) + 1)
            let cellNew = int2(floori(nextPos.x + 0.5), floori(nextPos.y) + 1)
            if cellNow != cellNew
                setLinkUp(cellNow)
                setHole(cellNow)
                drawHole(nextPos)
                if cellNew.y >= H || !hasHole(cellNew) && !hasLinkUp(cellNew) && !hasLinkDown(cellNew)
                    if (gb.fallenDist >= 1.5)
                        toggleGoldPile(cellNow)
                        gb.active = false
                    gb.fallenDist = -1.0
            if (gb.fallenDist >= 1.0)
                drawHole(nextPos)
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
    let curCell = getCell(e.pos)
    var rates : int[4]

    if hasHole(curCell + dirs[dirUp]) && hasLinkUp(curCell)
        rates[dirUp] += 16
    if hasHole(curCell + dirs[dirDown]) && hasLinkDown(curCell)
        rates[dirDown] += 16
    if hasHole(curCell + dirs[dirLeft]) && hasLinkLeft(curCell)
        rates[dirLeft] += 16
    if hasHole(curCell + dirs[dirRight]) && hasLinkRight(curCell)
        rates[dirRight] += 16

    for gb in bags
        if (!gb.active)
            continue
        let bagCell = getCell(gb.pos)
        for i in range(0, 4)
            if bagCell == curCell + dirs[i]
                rates[i] -= 8

    if e.lookDir.x < 0
        rates[dirRight] -= 4
        rates[dirLeft] += 1
    elif e.lookDir.x > 0
        rates[dirLeft] -= 4
        rates[dirRight] += 1
    elif e.lookDir.y < 0
        rates[dirDown] -= 4
        rates[dirUp] += 1
    elif e.lookDir.y > 0
        rates[dirUp] -= 4
        rates[dirDown] += 1

    if e.pos.x - hero.pos.x > 0.5
        rates[dirLeft] += 2
    elif e.pos.x - hero.pos.x < -0.5
        rates[dirRight] += 2
    if e.pos.y - hero.pos.y > 0.5
        rates[dirUp] += 2
    elif e.pos.y - hero.pos.y < -0.5
        rates[dirDown] += 2

    var maxEl = 0
    for i in range(1, 4)
        if rates[i] > rates[maxEl]
            maxEl = i

    e.lookDir = dirs[maxEl]


def updateEnemies(dt : float)
    if enemies |> length() < levels[curLevel].enemyCount && get_time_after_start() >= nextSpawn
        enemies |> push([[Creature pos = enemySpawner, lookDir = dirs[dirLeft]]])
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
                let cell = int2(x, y)
                let c0 = float2(float(x) + 0.5, float(y) + 0.5) * cs
                let col = levels[curLevel].tileColor
                fill_rect(c0.x, c0.y, cs, cs, 0x66000000)
                fill_rect(c0.x, c0.y, cs * 0.2, cs * 0.2, col)
                fill_rect(c0.x + cs * 0.8, c0.y, cs * 0.2, cs * 0.2, col)
                fill_rect(c0.x, c0.y + cs * 0.8, cs * 0.2, cs * 0.2, col)
                fill_rect(c0.x + cs * 0.8, c0.y + cs * 0.8, cs * 0.2, cs * 0.2, col)
                if !hasLinkLeft(cell)
                    fill_rect(c0.x, c0.y, cs * 0.2, cs, col)
                if !hasLinkRight(cell)
                    fill_rect(c0.x + cs * 0.8, c0.y, cs * 0.2, cs, col)
                if !hasLinkUp(cell)
                    fill_rect(c0.x, c0.y, cs, cs * 0.2, col)
                if !hasLinkDown(cell)
                    fill_rect(c0.x, c0.y + cs * 0.8, cs, cs * 0.2, col)
                if !hasHole(cell)
                    fill_rect(c0.x + cs * 0.2, c0.y + cs * 0.2, cs * 0.6, cs * 0.6, col)
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
                let cell = int2(x, y)
                let c0 = toScreen(float2(x, y))
                if hasDiamond(cell)
                    fill_circle(c0.x, c0.y, cs * 0.2, 0xffffffff)
                elif hasGoldPile(cell)
                    fill_circle(c0.x, c0.y + cs * 0.2, cs * 0.1, 0xffffff00)
                    fill_circle(c0.x - cs * 0.2, c0.y + cs * 0.2, cs * 0.1, 0xffffff00)
                    fill_circle(c0.x + cs * 0.2, c0.y + cs * 0.2, cs * 0.1, 0xffffff00)

        for gb in bags
            if (gb.active)
                let c0 = toScreen(gb.pos)
                let r = gb.timeToFall > 0.0 ? sin((GOLD_TIME_TO_FALL - gb.timeToFall) * 2.0 * PI / GOLD_TIME_TO_FALL) * cs * 0.05 : 0.0
                fill_circle(c0.x + r, c0.y, cs * 0.3, 0xffffff00)
                fill_circle(c0.x + r * 0.5 - cs * 0.05, c0.y - cs * 0.3 , cs * 0.1, 0xffffff00)
                fill_circle(c0.x + r * 0.5 + cs * 0.05, c0.y - cs * 0.3 , cs * 0.1, 0xffffff00)
                let l = get_text_size("$")
                text_out(c0.x + r - l.x * 0.5, c0.y - l.x * 0.5, "$", 0xff000000)

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
