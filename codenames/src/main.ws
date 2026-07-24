// main.ws -- Codenames controller: ports, board-render state, declarative
// board push, occupancy + mode detection, game logic, HUD.
import {
  ROLE_RED, ROLE_BLUE, ROLE_NEUTRAL, ROLE_ASSASSIN, COV_RED, COV_BLUE, COV_NEUTRAL, COV_ASSASSIN,
  GUESS_CORRECT, other, coverColorOf, glyphHexOf, classifyGuess, buildRoles,
} from "key"
import { buildWords } from "words"
import {
  teamName, turnBanner, clueNumText, cluePrompt, guessPrompt, guessCountText, outcomeText, gridCell,
} from "hud"

// --- Seat inputs ---
@top in redSpy: character
@top in red0: character
@top in red1: character
@top in red2: character
@top in blueSpy: character
@top in blue0: character
@top in blue1: character
@top in blue2: character

// --- Press inputs (one per board cell) ---
@left in press0: character
@left in press1: character
@left in press2: character
@left in press3: character
@left in press4: character
@left in press5: character
@left in press6: character
@left in press7: character
@left in press8: character
@left in press9: character
@left in press10: character
@left in press11: character
@left in press12: character
@left in press13: character
@left in press14: character
@left in press15: character
@left in press16: character
@left in press17: character
@left in press18: character
@left in press19: character
@left in press20: character
@left in press21: character
@left in press22: character
@left in press23: character
@left in press24: character

// --- Board-render state ---
var coveredMask: int = 0 // bit i = cell i's cover is shown
var coversVisible: bool = true // global cover-visibility toggle
var boardStamp: int = 1 // ++ on every board reset; re-fires the LUT-get outputs
array chosen: string[] = [] // the 25 chosen words (filled at game start, later task)
array cellColorArr: color[] = []// each cell's cover color (filled later task)

// --- Declarative board outputs: text (LUT read from `chosen`) ---
@right out text0: string = chosen.get(0, exec = boardStamp).Value
@right out text1: string = chosen.get(1, exec = boardStamp).Value
@right out text2: string = chosen.get(2, exec = boardStamp).Value
@right out text3: string = chosen.get(3, exec = boardStamp).Value
@right out text4: string = chosen.get(4, exec = boardStamp).Value
@right out text5: string = chosen.get(5, exec = boardStamp).Value
@right out text6: string = chosen.get(6, exec = boardStamp).Value
@right out text7: string = chosen.get(7, exec = boardStamp).Value
@right out text8: string = chosen.get(8, exec = boardStamp).Value
@right out text9: string = chosen.get(9, exec = boardStamp).Value
@right out text10: string = chosen.get(10, exec = boardStamp).Value
@right out text11: string = chosen.get(11, exec = boardStamp).Value
@right out text12: string = chosen.get(12, exec = boardStamp).Value
@right out text13: string = chosen.get(13, exec = boardStamp).Value
@right out text14: string = chosen.get(14, exec = boardStamp).Value
@right out text15: string = chosen.get(15, exec = boardStamp).Value
@right out text16: string = chosen.get(16, exec = boardStamp).Value
@right out text17: string = chosen.get(17, exec = boardStamp).Value
@right out text18: string = chosen.get(18, exec = boardStamp).Value
@right out text19: string = chosen.get(19, exec = boardStamp).Value
@right out text20: string = chosen.get(20, exec = boardStamp).Value
@right out text21: string = chosen.get(21, exec = boardStamp).Value
@right out text22: string = chosen.get(22, exec = boardStamp).Value
@right out text23: string = chosen.get(23, exec = boardStamp).Value
@right out text24: string = chosen.get(24, exec = boardStamp).Value

// --- Declarative board outputs: cover color (LUT read from `cellColorArr`) ---
@right out color0: color = cellColorArr.get(0, exec = boardStamp).Value
@right out color1: color = cellColorArr.get(1, exec = boardStamp).Value
@right out color2: color = cellColorArr.get(2, exec = boardStamp).Value
@right out color3: color = cellColorArr.get(3, exec = boardStamp).Value
@right out color4: color = cellColorArr.get(4, exec = boardStamp).Value
@right out color5: color = cellColorArr.get(5, exec = boardStamp).Value
@right out color6: color = cellColorArr.get(6, exec = boardStamp).Value
@right out color7: color = cellColorArr.get(7, exec = boardStamp).Value
@right out color8: color = cellColorArr.get(8, exec = boardStamp).Value
@right out color9: color = cellColorArr.get(9, exec = boardStamp).Value
@right out color10: color = cellColorArr.get(10, exec = boardStamp).Value
@right out color11: color = cellColorArr.get(11, exec = boardStamp).Value
@right out color12: color = cellColorArr.get(12, exec = boardStamp).Value
@right out color13: color = cellColorArr.get(13, exec = boardStamp).Value
@right out color14: color = cellColorArr.get(14, exec = boardStamp).Value
@right out color15: color = cellColorArr.get(15, exec = boardStamp).Value
@right out color16: color = cellColorArr.get(16, exec = boardStamp).Value
@right out color17: color = cellColorArr.get(17, exec = boardStamp).Value
@right out color18: color = cellColorArr.get(18, exec = boardStamp).Value
@right out color19: color = cellColorArr.get(19, exec = boardStamp).Value
@right out color20: color = cellColorArr.get(20, exec = boardStamp).Value
@right out color21: color = cellColorArr.get(21, exec = boardStamp).Value
@right out color22: color = cellColorArr.get(22, exec = boardStamp).Value
@right out color23: color = cellColorArr.get(23, exec = boardStamp).Value
@right out color24: color = cellColorArr.get(24, exec = boardStamp).Value

// --- Declarative board outputs: covered (pure, gated on coversVisible + bit) ---
@right out covered0: bool = coversVisible && ((coveredMask >> 0) & 1)
@right out covered1: bool = coversVisible && ((coveredMask >> 1) & 1)
@right out covered2: bool = coversVisible && ((coveredMask >> 2) & 1)
@right out covered3: bool = coversVisible && ((coveredMask >> 3) & 1)
@right out covered4: bool = coversVisible && ((coveredMask >> 4) & 1)
@right out covered5: bool = coversVisible && ((coveredMask >> 5) & 1)
@right out covered6: bool = coversVisible && ((coveredMask >> 6) & 1)
@right out covered7: bool = coversVisible && ((coveredMask >> 7) & 1)
@right out covered8: bool = coversVisible && ((coveredMask >> 8) & 1)
@right out covered9: bool = coversVisible && ((coveredMask >> 9) & 1)
@right out covered10: bool = coversVisible && ((coveredMask >> 10) & 1)
@right out covered11: bool = coversVisible && ((coveredMask >> 11) & 1)
@right out covered12: bool = coversVisible && ((coveredMask >> 12) & 1)
@right out covered13: bool = coversVisible && ((coveredMask >> 13) & 1)
@right out covered14: bool = coversVisible && ((coveredMask >> 14) & 1)
@right out covered15: bool = coversVisible && ((coveredMask >> 15) & 1)
@right out covered16: bool = coversVisible && ((coveredMask >> 16) & 1)
@right out covered17: bool = coversVisible && ((coveredMask >> 17) & 1)
@right out covered18: bool = coversVisible && ((coveredMask >> 18) & 1)
@right out covered19: bool = coversVisible && ((coveredMask >> 19) & 1)
@right out covered20: bool = coversVisible && ((coveredMask >> 20) & 1)
@right out covered21: bool = coversVisible && ((coveredMask >> 21) & 1)
@right out covered22: bool = coversVisible && ((coveredMask >> 22) & 1)
@right out covered23: bool = coversVisible && ((coveredMask >> 23) & 1)
@right out covered24: bool = coversVisible && ((coveredMask >> 24) & 1)

// --- Occupancy + mode detection (pure, port-derived) ---
let redSpyHere = redSpy // char coerces to 1 when occupied, 0 when empty
let blueSpyHere = blueSpy
let redOps = red0 + red1 + red2
let blueOps = blue0 + blue1 + blue2
let seatedNow = redSpyHere + redOps + blueSpyHere + blueOps
let hereMask = redSpy + red0*2 + red1*4 + red2*8 + blueSpy*16 + blue0*32 + blue1*64 + blue2*128
let bottedRed = redSpyHere == 0 // a team with no spymaster is botted
let bottedBlue = blueSpyHere == 0
let startable = (redSpyHere != 0 || blueSpyHere != 0) && (redOps + blueOps) >= 1

// --- Phase + input-queue state ---
var phase: int = 0 // PH_LOBBY; real PH_* constants arrive in later tasks
var boardDirty: bool = false
array inputQueue: int[] = []
let KEY_W = 0
let KEY_A = 1
let KEY_D = 2
let KEY_SP = 3

let PH_LOBBY = 0
let PH_CLUE = 1
let PH_GUESS = 2
let PH_OVER = 3

let INF = 999

var botTimer: int = 0
array hidden: int[] = []

mod spySeatOf(team: int) -> int {
  return if team == ROLE_RED then 0 else 4
}

mod isBotTurn() -> bool {
  return (turnTeam == ROLE_RED && bottedRed) || (turnTeam == ROLE_BLUE && bottedBlue)
}

mod beginBotTurn() {
  phase = PH_GUESS
  botTimer = 40 // ~0.67s pacing before the bot reveals
  boardDirty = true
}

// --- Game state (lobby ready-up + key generation) ---
var turnTeam: int = 0
var clueNum: int = 1
var guessesLeft: int = 0
var winner: int = -1
var assassinLoss: bool = false
var redMask: int = 0
var blueMask: int = 0
var neutralMask: int = 0
var assassinBit: int = 0
var readyMask: int = 0
var wordsReady: bool = false
var wArm: bool = false // double-W arm: first W arms, second confirms (clue confirm / pass)
array roles: int[] = []
array words: string[] = []
array teamScratch: int[] = []
array readyCell: int[] = [23, 4, 14, 24, 21, 0, 10, 20] // seat-indexed: 0 redSpy..7 blue2

// --- Player input readers + previous-axis buffers (one per seat) ---
@label("Player Input") chip {
  let inp0 = InputReader(redSpy)
  let inp1 = InputReader(red0)
  let inp2 = InputReader(red1)
  let inp3 = InputReader(red2)
  let inp4 = InputReader(blueSpy)
  let inp5 = InputReader(blue0)
  let inp6 = InputReader(blue1)
  let inp7 = InputReader(blue2)
  buffer f0p: float = inp0.Forward
  buffer r0p: float = inp0.Right
  buffer j0p: bool = inp0.Jump
  buffer f1p: float = inp1.Forward
  buffer r1p: float = inp1.Right
  buffer j1p: bool = inp1.Jump
  buffer f2p: float = inp2.Forward
  buffer r2p: float = inp2.Right
  buffer j2p: bool = inp2.Jump
  buffer f3p: float = inp3.Forward
  buffer r3p: float = inp3.Right
  buffer j3p: bool = inp3.Jump
  buffer f4p: float = inp4.Forward
  buffer r4p: float = inp4.Right
  buffer j4p: bool = inp4.Jump
  buffer f5p: float = inp5.Forward
  buffer r5p: float = inp5.Right
  buffer j5p: bool = inp5.Jump
  buffer f6p: float = inp6.Forward
  buffer r6p: float = inp6.Right
  buffer j6p: bool = inp6.Jump
  buffer f7p: float = inp7.Forward
  buffer r7p: float = inp7.Right
  buffer j7p: bool = inp7.Jump
}

// --- Enqueue + edge detection + char->seat ---
// Key event raw = seat*4 + key (0..31). Cell event raw = 256 + cell*8 + seat (256..455).
// No overlap; both < 512, so the phase tag is `phase * 512 + raw`.
mod queueInput(seat: int, key: int) {
  if inputQueue.length() < 32 { inputQueue.push(phase * 512 + seat * 4 + key) }
}

mod seatOfChar(c: character) -> int {
  return if c == redSpy then 0
    else if c == red0 then 1
    else if c == red1 then 2
    else if c == red2 then 3
    else if c == blueSpy then 4
    else if c == blue0 then 5
    else if c == blue1 then 6
    else if c == blue2 then 7
    else -1
}

// Guard on GetUserId FIRST: `on pressN` also fires on release (char goes invalid),
// and two invalid chars can compare equal - so resolve the seat only for a real user.
mod queueCell(cell: int, presser: character) {
  if !presser { return } // skip release edges (invalid presser coerces to false)
  let s = seatOfChar(presser)
  if s < 0 { return }
  if inputQueue.length() < 32 { inputQueue.push(phase * 512 + 256 + cell * 8 + s) }
}

// Rising edges past the deadzone; jump is a bool edge. Empty seats' readers alias
// the local player, so drop edges from unoccupied seats.
mod readSeatInput(seat: int, fwd: float, rgt: float, jmp: bool, fPrev: float, rPrev: float, jPrev: bool) {
  if ((hereMask >> seat) & 1) == 0 { return }
  if fwd > 0.5 && fPrev <= 0.5 { queueInput(seat, KEY_W) }
  if rgt < -0.5 && rPrev >= -0.5 { queueInput(seat, KEY_A) }
  if rgt > 0.5 && rPrev <= 0.5 { queueInput(seat, KEY_D) }
  if jmp && !jPrev { queueInput(seat, KEY_SP) }
}

// --- Per-cell press handlers ---
on press0 { queueCell(0, press0) }
on press1 { queueCell(1, press1) }
on press2 { queueCell(2, press2) }
on press3 { queueCell(3, press3) }
on press4 { queueCell(4, press4) }
on press5 { queueCell(5, press5) }
on press6 { queueCell(6, press6) }
on press7 { queueCell(7, press7) }
on press8 { queueCell(8, press8) }
on press9 { queueCell(9, press9) }
on press10 { queueCell(10, press10) }
on press11 { queueCell(11, press11) }
on press12 { queueCell(12, press12) }
on press13 { queueCell(13, press13) }
on press14 { queueCell(14, press14) }
on press15 { queueCell(15, press15) }
on press16 { queueCell(16, press16) }
on press17 { queueCell(17, press17) }
on press18 { queueCell(18, press18) }
on press19 { queueCell(19, press19) }
on press20 { queueCell(20, press20) }
on press21 { queueCell(21, press21) }
on press22 { queueCell(22, press22) }
on press23 { queueCell(23, press23) }
on press24 { queueCell(24, press24) }

// --- Key generation ---
// One cell -> its mask bit + cover color. roles must be filled (25) and
// cellColorArr sized (25) before calling.
mod markCell(i: int) {
  let r = roles[i]
  cellColorArr[i] = coverColorOf(r)
  if r == ROLE_RED { redMask = redMask | (1 << i) } else if r == ROLE_BLUE { blueMask = blueMask | (1 << i) } else if r == ROLE_ASSASSIN { assassinBit = assassinBit | (1 << i) } else { neutralMask = neutralMask | (1 << i) }
}

mod deriveMasks() {
  redMask = 0
  blueMask = 0
  neutralMask = 0
  assassinBit = 0
  markCell(0) markCell(1) markCell(2) markCell(3) markCell(4)
  markCell(5) markCell(6) markCell(7) markCell(8) markCell(9)
  markCell(10) markCell(11) markCell(12) markCell(13) markCell(14)
  markCell(15) markCell(16) markCell(17) markCell(18) markCell(19)
  markCell(20) markCell(21) markCell(22) markCell(23) markCell(24)
}

// --- Lobby ready-up covers (rebuilt from `readyMask` so a leaver's cover clears) ---
mod markReady(seat: int) {
  if ((readyMask >> seat) & 1) == 1 {
    let rc = readyCell[seat]
    coveredMask = coveredMask | (1 << rc)
    cellColorArr[rc] = if seat < 4 then COV_RED else COV_BLUE
  }
}

// Lobby covers are EXACTLY the readied seats' ready cells - rebuild from scratch.
mod rebuildLobbyCovers() {
  coveredMask = 0
  markReady(0) markReady(1) markReady(2) markReady(3)
  markReady(4) markReady(5) markReady(6) markReady(7)
  boardStamp = boardStamp + 1
  boardDirty = true
}

mod toggleReady(seat: int) {
  readyMask = readyMask ^ (1 << seat)
  rebuildLobbyCovers()
}

// --- Start / reset / turn ---
mod beginTurn() {
  wArm = false
  if (turnTeam == ROLE_RED && bottedRed) || (turnTeam == ROLE_BLUE && bottedBlue) {
    beginBotTurn()
  } else {
    phase = PH_CLUE
    clueNum = 1
    boardDirty = true
  }
}

mod startGame() {
  teamScratch.clear()
  teamScratch.push(ROLE_RED)
  teamScratch.push(ROLE_BLUE)
  teamScratch.shuffle()
  let startTeam = teamScratch[0]
  buildRoles(roles, startTeam) // fills 25 in order
  roles.shuffle()
  cellColorArr.resize(25, COV_NEUTRAL)
  deriveMasks() // masks + per-cell cover colors
  words.shuffle()
  chosen.slice(words, 0, 25) // 25 random words
  coveredMask = 0
  readyMask = 0
  turnTeam = startTeam
  clueNum = 1
  winner = -1
  assassinLoss = false
  boardStamp = boardStamp + 1
  boardDirty = true
  beginTurn()
}

mod tryStart() {
  if phase == PH_LOBBY && startable && (readyMask & hereMask) == hereMask {
    startGame()
  }
}

mod resetToLobby() {
  phase = PH_LOBBY
  coveredMask = 0
  readyMask = 0
  coversVisible = true
  chosen.clear()
  chosen.resize(25, "")
  boardStamp = boardStamp + 1
  boardDirty = true
}

// --- Dispatch + phase-routing stubs ---
mod remaining(team: int) -> int {
  return BitCount((if team == ROLE_RED then redMask else blueMask) & ~coveredMask)
}

// Seat-bit set allowed to guess this turn: the turn team's own operatives if any
// are seated, else ALL seated operatives (covers solo-shared-guesser + lopsided).
mod guessersMask() -> int {
  let redOpsBits = hereMask & 14
  let blueOpsBits = hereMask & 224
  let allOpsBits = redOpsBits | blueOpsBits
  return if turnTeam == ROLE_RED then (if redOpsBits != 0 then redOpsBits else allOpsBits)
    else (if blueOpsBits != 0 then blueOpsBits else allOpsBits)
}

// Game over: leave the board as it ended (do NOT cover every word) and show the
// full key on every player's screen via the HUD grid. Covers stay toggleable
// (Space) so anyone can peek at the words. Freeze until all ack.
mod endGame(w: int, assassin: bool) {
  winner = w
  assassinLoss = assassin
  phase = PH_OVER
  readyMask = 0
  boardDirty = true
}

// Cover a cell and run the shared win/assassin checks. Does NOT decide turn
// continuation (the caller does).
mod reveal(cell: int, actorTeam: int) {
  let role = roles[cell]
  coveredMask = coveredMask | (1 << cell)
  cellColorArr[cell] = coverColorOf(role)
  boardDirty = true
  if role == ROLE_ASSASSIN { endGame(other(actorTeam), true) return }
  // A reveal can end EITHER team's game (a wrong guess flips the opponent's last agent).
  if remaining(actorTeam) == 0 { endGame(actorTeam, false) return }
  if remaining(other(actorTeam)) == 0 { endGame(other(actorTeam), false) return }
}

mod endTurn() {
  turnTeam = other(turnTeam)
  beginTurn()
}

mod maybeHidden(i: int) {
  // The bot flips one of ITS OWN agents per turn (a steady race to the finish),
  // never a neutral, the opponent's, or the assassin.
  let mine = if turnTeam == ROLE_RED then redMask else blueMask
  if ((coveredMask >> i) & 1) == 0 && ((mine >> i) & 1) != 0 { hidden.push(i) }
}

mod botReveal() {
  hidden.clear()
  maybeHidden(0) maybeHidden(1) maybeHidden(2) maybeHidden(3) maybeHidden(4)
  maybeHidden(5) maybeHidden(6) maybeHidden(7) maybeHidden(8) maybeHidden(9)
  maybeHidden(10) maybeHidden(11) maybeHidden(12) maybeHidden(13) maybeHidden(14)
  maybeHidden(15) maybeHidden(16) maybeHidden(17) maybeHidden(18) maybeHidden(19)
  maybeHidden(20) maybeHidden(21) maybeHidden(22) maybeHidden(23) maybeHidden(24)
  if hidden.length() > 0 {
    hidden.shuffle()
    reveal(hidden.get(0).Value, turnTeam)
    if phase != PH_OVER { endTurn() }
  }
}

mod tapKey(seat: int, key: int) {
  if key == KEY_SP { coversVisible = !coversVisible boardDirty = true return }
  if key == KEY_W && seatedNow <= 1 && phase != PH_LOBBY { resetToLobby() return }
  if phase == PH_LOBBY {
    if key == KEY_W { toggleReady(seat) tryStart() }
    return
  }
  if phase == PH_CLUE && seat == spySeatOf(turnTeam) {
    if key == KEY_W {
      if wArm {
        wArm = false
        guessesLeft = if clueNum == 0 || clueNum == 8 then INF else clueNum + 1
        phase = PH_GUESS
      } else { wArm = true }
      boardDirty = true
    } else {
      wArm = false // A/D changes the number and disarms
      if key == KEY_A { clueNum = clamp(clueNum - 1, 0, 8) } else { clueNum = clamp(clueNum + 1, 0, 8) }
      boardDirty = true
    }
    return
  }
  if phase == PH_GUESS && !isBotTurn() && ((guessersMask() >> seat) & 1) != 0 {
    if key == KEY_W {
      if wArm { wArm = false endTurn() } else { wArm = true boardDirty = true } // double-W to pass
    }
    return
  }
  if phase == PH_OVER {
    if key == KEY_W {
      readyMask = readyMask | (1 << seat)
      boardDirty = true
      if (readyMask & hereMask) == hereMask { resetToLobby() }
    }
    return
  }
} // Task 6: lobby branch; Task 7: clue branch; Task 8: guess branch; Task 10: space toggle + lone-reset + game-over ack
mod tapCell(cell: int, presserSeat: int) {
  if phase != PH_GUESS { return }
  if isBotTurn() { return }
  if ((guessersMask() >> presserSeat) & 1) == 0 { return } // not an active guesser
  if ((coveredMask >> cell) & 1) == 1 { return } // already revealed
  wArm = false // a guess disarms a pending pass-confirm
  let role = roles[cell]
  reveal(cell, turnTeam)
  if phase == PH_OVER { return } // reveal ended the game
  if classifyGuess(role, turnTeam) == GUESS_CORRECT {
    if guessesLeft < INF { guessesLeft = guessesLeft - 1 }
    if guessesLeft <= 0 { endTurn() } // used the last guess
  } else {
    endTurn() // neutral / opponent cell ends the turn
  }
}
let HUD_LIFE = 0.4 // short: HUD is redrawn every tick (round-robin), so a vacated seat's text expires
let TID_BANNER = 0
let TID_PROMPT = 1
let TID_GRID = 2

mod seatChar(seat: int) -> character {
  return if seat == 0 then redSpy
    else if seat == 1 then red0
    else if seat == 2 then red1
    else if seat == 3 then red2
    else if seat == 4 then blueSpy
    else if seat == 5 then blue0
    else if seat == 6 then blue1
    else blue2
}

// One 5-cell row of the key grid (a = first cell index).
mod gridRow(a: int) -> string {
  return "${gridCell(roles[a], (coveredMask >> a) & 1)} ${gridCell(roles[a + 1], (coveredMask >> (a + 1)) & 1)} ${gridCell(roles[a + 2], (coveredMask >> (a + 2)) & 1)} ${gridCell(roles[a + 3], (coveredMask >> (a + 3)) & 1)} ${gridCell(roles[a + 4], (coveredMask >> (a + 4)) & 1)}"
}

mod spyGrid() -> string {
  let grid = '<font="Iosevka">${gridRow(0)}<br>${gridRow(5)}<br>${gridRow(10)}<br>${gridRow(15)}<br>${gridRow(20)}</>'
  // How many of each are left, for the spymasters (6 inputs, one FormatText).
  let counts = '${teamName(ROLE_RED)} ${remaining(ROLE_RED)}   ${teamName(ROLE_BLUE)} ${remaining(ROLE_BLUE)}   <color="ca8">Neutral</> ${BitCount(neutralMask & ~coveredMask)}   Assassin ${BitCount(assassinBit & ~coveredMask)}'
  return '${grid}<br>${counts}'
}

mod bannerText() -> string {
  if phase == PH_LOBBY { return '<size="42"><font="MonaspaceArgon">CODENAMES</></><br>Sit down and tap <b>W</> to ready up (2-8 players)' }
  if phase == PH_OVER { return outcomeText(winner, assassinLoss) }
  // During a human guessing turn, show the guess count to EVERYONE.
  if phase == PH_GUESS && !isBotTurn() { return "${turnBanner(turnTeam)}, ${guessCountText(guessesLeft)}" }
  return turnBanner(turnTeam)
}

mod promptFor(seat: int) -> string {
  if phase == PH_LOBBY {
    let r = BitCount(readyMask)
    return if ((readyMask >> seat) & 1) == 1
      then 'You are <color="8f8">READY</> (${r}/${seatedNow})<br>Tap <b>W</> to unready'
      else 'You are <color="f66">NOT READY</> (${r}/${seatedNow})<br>Tap <b>W</> to ready up'
  }
  if phase == PH_OVER { return "Waiting to continue (${BitCount(readyMask)}/${seatedNow})" }
  if phase == PH_CLUE {
    if seat == spySeatOf(turnTeam) {
      return if wArm then "Confirm clue <b>${clueNumText(clueNum)}</>?<br>Press <b>W</> again" else cluePrompt(clueNum)
    }
    return "Waiting for the ${teamName(turnTeam)} spymaster..."
  }
  if isBotTurn() { return "The ${teamName(turnTeam)} bot is guessing..." }
  if ((guessersMask() >> seat) & 1) != 0 {
    return if wArm then "Pass the turn?<br>Press <b>W</> again" else guessPrompt(guessesLeft)
  }
  return "${teamName(turnTeam)} is guessing..."
}

// Banner + prompt positions match secret-hitler / coup exactly.
mod hudBanner(ch: character, s: string) {
  ch.DisplayText(s, textId = TID_BANNER, positionX = 0.0, positionY = -30.0,
    fontSize = 24, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.25)
}
mod hudPrompt(ch: character, s: string) {
  ch.DisplayText(s, textId = TID_PROMPT, positionX = 0.0, positionY = 60.0,
    fontSize = 20, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.5)
}
// Spymaster key grid, bottom-center, monospace.
mod hudGrid(ch: character, s: string) {
  ch.DisplayText(s, textId = TID_GRID, positionX = 0.0, positionY = -250.0,
    fontSize = 24, lifetime = HUD_LIFE, justify = "Center", anchorY = 1.0)
}

mod drawSeat(seat: int) {
  if ((hereMask >> seat) & 1) == 0 { return }
  let ch = seatChar(seat)
  hudBanner(ch, bannerText())
  hudPrompt(ch, promptFor(seat))
  // Spymasters see the key during play; at game over EVERYONE sees the final key.
  let showGrid = phase == PH_OVER
    || ((phase == PH_CLUE || phase == PH_GUESS) && (seat == 0 || seat == 4))
  hudGrid(ch, if showGrid then spyGrid() else "")
}

// Round-robin: one seat per tick. Occupied seats stay lit (redrawn within
// HUD_LIFE); a vacated seat stops being drawn and its text expires.
mod refreshHud(t: int) {
  drawSeat(t % 8)
}

mod dispatch() {
  if inputQueue.length() > 0 {
    let ev = inputQueue[0]
    inputQueue.remove(0)
    if ev / 512 == phase { // stale-phase events drop
      let raw = ev % 512
      if raw >= 256 { tapCell((raw - 256) / 8, (raw - 256) % 8) } else { tapKey(raw / 4, raw % 4) }
    }
  }
}

// --- Tick clock ---
buffer tick: int = tick + 1
buffer prevHere: int = hereMask

@label("Tick") chip on tick {
  if !wordsReady {
    wordsReady = true
    buildWords(words)
    cellColorArr.resize(25, COV_NEUTRAL)
    chosen.resize(25, "")
  }
  @label("Input Reading") chip {
    readSeatInput(0, inp0.Forward, inp0.Right, inp0.Jump, f0p, r0p, j0p)
    readSeatInput(1, inp1.Forward, inp1.Right, inp1.Jump, f1p, r1p, j1p)
    readSeatInput(2, inp2.Forward, inp2.Right, inp2.Jump, f2p, r2p, j2p)
    readSeatInput(3, inp3.Forward, inp3.Right, inp3.Jump, f3p, r3p, j3p)
    readSeatInput(4, inp4.Forward, inp4.Right, inp4.Jump, f4p, r4p, j4p)
    readSeatInput(5, inp5.Forward, inp5.Right, inp5.Jump, f5p, r5p, j5p)
    readSeatInput(6, inp6.Forward, inp6.Right, inp6.Jump, f6p, r6p, j6p)
    readSeatInput(7, inp7.Forward, inp7.Right, inp7.Jump, f7p, r7p, j7p)
  }
  dispatch()
  if phase == PH_LOBBY {
    let nm = readyMask & hereMask // a seat that emptied loses its ready bit
    if nm != readyMask { readyMask = nm rebuildLobbyCovers() }
    tryStart()
  }
  if phase == PH_OVER {
    readyMask = readyMask & hereMask
    if (readyMask & hereMask) == hereMask { resetToLobby() }
  }
  if phase == PH_CLUE || phase == PH_GUESS {
    if bottedRed && bottedBlue {
      resetToLobby() // no spymasters left at all -> can't continue
    } else if isBotTurn() {
      if botTimer == 0 { beginBotTurn() } // active team lost its spymaster -> bot takes the turn
    } else if phase == PH_GUESS && guessersMask() == 0 {
      endTurn() // no valid guesser remains -> pass
    }
  }
  if botTimer > 0 { botTimer = botTimer - 1 if botTimer == 0 { botReveal() } }
  refreshHud(tick) // every tick (round-robin); not dirty-gated, so leavers' HUD expires
}
