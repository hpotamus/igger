require math

bitfield Cell
    holeMid
    goldPile
    diamond

let W = 15
let H = 10


var gnd : Cell[W * H]
var hlinks : int[H]
var vlinks : int[W]


def getCellMid(pos : float2)
    return float2(floor(pos.x + 0.5), floor(pos.y + 0.5))
def getCell(pos : float2)
    return int2(floori(pos.x + 0.5), floori(pos.y + 0.5))
def getCellIdx(cell : int2)
    return cell.y * W + cell.x
def getCellIdx(pos : float2)
    let cell = getCell(pos)
    return getCellIdx(cell)
def isIdxValid(idx : int)
    return idx >= 0 && idx < W * H


def hasLinkLeft(c : int2)
    return c.y >= 0 && c.y < H && c.x >= 1 && c.x < W && (hlinks[c.y] & (1 << (c.x - 1))) != 0
def hasLinkRight(c : int2)
    return c.y >= 0 && c.y < H && c.x >= 0 && c.x < W - 1 && (hlinks[c.y] & (1 << c.x)) != 0
def hasLinkUp(c : int2)
    return c.x >= 0 && c.x < W && c.y >= 1 && c.y < H && (vlinks[c.x] & (1 << (c.y - 1))) != 0
def hasLinkDown(c : int2)
    return c.x >= 0 && c.x < W && c.y >= 0 && c.y < H - 1 && (vlinks[c.x] & (1 << c.y)) != 0
def hasHole(c : int2)
    let idx = getCellIdx(c)
    return isIdxValid(idx) && gnd[idx].holeMid
def hasDiamond(c : int2)
    let idx = getCellIdx(c)
    return isIdxValid(idx) && gnd[idx].diamond
def hasGoldPile(c : int2)
    let idx = getCellIdx(c)
    return isIdxValid(idx) && gnd[idx].goldPile

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
def setHole(c : int2)
    let idx = getCellIdx(c)
    if isIdxValid(idx)
        gnd[idx] |= Cell holeMid
def toggleDiamond(c : int2)
    let idx = getCellIdx(c)
    if isIdxValid(idx)
        gnd[idx] ^= Cell diamond
def toggleGoldPile(c : int2)
    let idx = getCellIdx(c)
    if isIdxValid(idx)
        gnd[idx] ^= Cell goldPile

def clearBoard()
    for l in hlinks
        l = 0
    for l in vlinks
        l = 0
    for idx in range(0, W * H)
        gnd[idx] = bitfield(0)
