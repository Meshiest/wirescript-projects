@fold

import { ST_EMPTY, ST_DOWN, ST_UP, packCell, cellState, cellValue, cellColor, cellText } from "cards"
import { deckBuild, deckDraw, deckPop, discardPush, discardTop } from "deck"
import { columnClear, handAllUp, handSum } from "grid"
import { enderScore, lowestSeat } from "scoring"

// --- Phase codes (spec §5) ---
let PH_LOBBY = 0
let PH_SETUP = 1
let PH_TURN = 2
let PH_FINAL = 3
let PH_SCORE = 4
let PH_GAMEOVER = 5

let HELD_NONE = 0
let SRC_DECK = 1
let SRC_DISCARD = 2
let NO_CARD = -99

// --- Seat inputs (wired to each player.ws) ---
@right in seat0: character
@right in seat1: character
@right in seat2: character
@right in seat3: character
@right in seat4: character
@right in seat5: character
@right in seat6: character
@right in seat7: character
@right in press0: exec
@right in press1: exec
@right in press2: exec
@right in press3: exec
@right in press4: exec
@right in press5: exec
@right in press6: exec
@right in press7: exec
@right in slot0: int
@right in slot1: int
@right in slot2: int
@right in slot3: int
@right in slot4: int
@right in slot5: int
@right in slot6: int
@right in slot7: int
@top in drawBtn: character
@top in discardBtn: character

// --- Core state ---
array grid: int[] // 8*12 packed cells; sized to 96 on first tick
array cellVal: int[] // value mirror of grid: each cell's face-up score (0 for
                     // down/empty/cleared). Lets handSum be a slice+sum (2 gates)
                     // instead of decoding+adding 12 packed cells (~80 gates).
array sumTmp: int[]  // caller-owned scratch for handSum's slice+sum
array deck: int[]
array discard: int[]
array scoreTotal: int[] = [0, 0, 0, 0, 0, 0, 0, 0]
array roundScore: int[] = [0, 0, 0, 0, 0, 0, 0, 0]
var phase: int = 0
var turnSeat: int = 0
var heldCard: int = -99
var heldSource: int = 0
var mustFlip: bool = false
var readyMask: int = 0
var enderSeat: int = -1
var finalMask: int = 0
var playingMask: int = 0
array setupFlips: int[] = [0, 0, 0, 0, 0, 0, 0, 0] // per-seat setup flip count

array dirtyQ: int[]                              // seat slots pending a board push
array allSeats: int[] = [0, 1, 2, 3, 4, 5, 6, 7] // markAll appends this in one op
var turnPending: bool = false
var resetPending: bool = false
var gridReady: bool = false

// Free-running per-frame counter. `chip on tick` fires when `tick` changes, and
// the body reads `tick % 8` for round-robin HUD service — so this self-
// incrementing buffer is REQUIRED (there is no built-in `tick` symbol). Declared
// before `chip on tick` (WS021).
buffer tick: int = tick + 1

// --- Central outputs ---
var vDiscardColor: color = Color(0.133, 0.133, 0.133, 1.0)
var vDiscardText: string = ""
var vDeckCount: int = 0
@bottom out discardColor: color = vDiscardColor.Value
@bottom out discardText: string = vDiscardText.Value
@bottom out deckCount: int = vDeckCount.Value

// --- Per-seat card-state arrays pushed to each player.ws ---
// One shared scratch that pushSeat fills for whichever seat is being serviced;
// serviceBoardSeat then copies it into that seat's real buffer. This keeps the
// (expensive) 13-cell fill inlined ONCE instead of once per seat.
array boardScratch: int[]
array cardsBuf0: int[]
array cardsBuf1: int[]
array cardsBuf2: int[]
array cardsBuf3: int[]
array cardsBuf4: int[]
array cardsBuf5: int[]
array cardsBuf6: int[]
array cardsBuf7: int[]
@left out cards0: int[] = cardsBuf0
@left out cards1: int[] = cardsBuf1
@left out cards2: int[] = cardsBuf2
@left out cards3: int[] = cardsBuf3
@left out cards4: int[] = cardsBuf4
@left out cards5: int[] = cardsBuf5
@left out cards6: int[] = cardsBuf6
@left out cards7: int[] = cardsBuf7
@left out update0: exec
@left out update1: exec
@left out update2: exec
@left out update3: exec
@left out update4: exec
@left out update5: exec
@left out update6: exec
@left out update7: exec

// --- Occupancy (pure, port-derived) ---
// A character port coerces to 1 when occupied, 0 when empty (coup's idiom); no
// `none` literal is needed. hereMask is a pure `let`, recomputed continuously.
let hereMask = seat0 + seat1 * 2 + seat2 * 4 + seat3 * 8
  + seat4 * 16 + seat5 * 32 + seat6 * 64 + seat7 * 128

// --- Central input append-queue (spec §2) ---
array inputQueue: int[]
mod enqueue(seat: int, slot: int) {
  if ((hereMask >> seat) & 1) == 0 { return }
  if inputQueue.length() < 32 {
    inputQueue.push(phase * 512 + seat * 16 + slot)
  }
}
on press0 { enqueue(0, slot0) }
on press1 { enqueue(1, slot1) }
on press2 { enqueue(2, slot2) }
on press3 { enqueue(3, slot3) }
on press4 { enqueue(4, slot4) }
on press5 { enqueue(5, slot5) }
on press6 { enqueue(6, slot6) }
on press7 { enqueue(7, slot7) }

// Central pile buttons: gated to the turn-holder, enqueued as slots 13/14.
let SLOT_DRAW = 13
let SLOT_TAKE = 14
let SLOT_W = 15   // ready/ack/reset (W key), routed through the same input queue
var drawPrevHeld: bool = false
var takePrevHeld: bool = false
mod seatOfTurn() -> character {
  if turnSeat == 0 { return seat0 }
  if turnSeat == 1 { return seat1 }
  if turnSeat == 2 { return seat2 }
  if turnSeat == 3 { return seat3 }
  if turnSeat == 4 { return seat4 }
  if turnSeat == 5 { return seat5 }
  if turnSeat == 6 { return seat6 }
  return seat7
}
mod turnHolderIs(c: character) -> bool {
  return (phase == PH_TURN || phase == PH_FINAL) && c == seatOfTurn()
}

// Flip a face-down grid cell to face-up. The value was assigned at deal time and
// already lives in grid; revealing only changes state DOWN -> UP.
mod flipCell(s: int, k: int) {
  let idx = s*12 + k
  let p = grid[idx]
  if cellState(p) != ST_DOWN { return }
  let v = cellValue(p)
  grid[idx] = packCell(ST_UP, v)
  cellVal[idx] = v            // mirror: now face-up, contributes its value
}

// Flip seat s's cell k IF it is face-down (mirrors cellVal exactly like flipCell);
// returns whether it flipped.
mod flipDownAt(s: int, k: int) -> bool {
  let idx = s*12 + k
  let p = grid[idx]
  if cellState(p) != ST_DOWN { return false }
  let v = cellValue(p)
  grid[idx] = packCell(ST_UP, v)
  cellVal[idx] = v
  return true
}
// Flip this seat's first remaining face-down cell -- the auto-flip penalty for a
// player who leaves mid-turn after drawing (they can't dodge the flip by bailing).
mod flipFirstDown(s: int) {
  if flipDownAt(s, 0) { return }
  if flipDownAt(s, 1) { return }
  if flipDownAt(s, 2) { return }
  if flipDownAt(s, 3) { return }
  if flipDownAt(s, 4) { return }
  if flipDownAt(s, 5) { return }
  if flipDownAt(s, 6) { return }
  if flipDownAt(s, 7) { return }
  if flipDownAt(s, 8) { return }
  if flipDownAt(s, 9) { return }
  if flipDownAt(s, 10) { return }
  if flipDownAt(s, 11) { return }
}

// > **Value model (faithful deck economy):** cards get their real values at deal
// > time (Task 8 `dealCell` draws 12/seat from the deck), so the 150-card economy
// > matches real Skyjo — 96 dealt + 1 discard seed leaves 53 in the draw pile for
// > an 8-player game. Hidden values live in `main`'s `grid` but are **masked to 0
// > on the wire** by `fillCellFor` (Task 10), so nothing leaks. Reveal / flip /
// > swap never redraw for an already-dealt card — they reuse the value in `grid`.

// Board-refresh queue: mark one seat (or every seat) as needing a card push. The
// tick pops one slot per frame and services just that seat.
mod markSeat(s: int) { dirtyQ.push(s) }
mod markAll() { dirtyQ.append(allSeats) }

mod seatFlips(i: int) -> int {
  if ((playingMask >> i) & 1) == 0 { return 2 } // non-playing counts as done
  if ((hereMask >> i) & 1) == 0 { return 2 } // playing-but-absent counts as done
  return setupFlips[i]
}

mod setupDone() -> bool {
  return seatFlips(0) >= 2 && seatFlips(1) >= 2 && seatFlips(2) >= 2 && seatFlips(3) >= 2
    && seatFlips(4) >= 2 && seatFlips(5) >= 2 && seatFlips(6) >= 2 && seatFlips(7) >= 2
}

// Highest revealed 2-card sum starts; tie -> lowest seat index. Each seat bids
// its hand sum ONCE; non-playing/absent seats bid a sentinel that never wins
// (also avoids reading grid for them). Real sums are >= -24 (12 x -2), so the
// INT_MIN sentinel is strictly below every real bid and below the initial `bv`.
mod starterBid(i: int) -> int {
  if (((playingMask & hereMask) >> i) & 1) == 0 { return -2147483648 }
  return handSum(cellVal, sumTmp, i*12)
}

mod pickStarter() {
  var bs: int = -1
  var bv: int = -2147483648
  let s0 = starterBid(0) if s0 > bv { bs = 0 bv = s0 }
  let s1 = starterBid(1) if s1 > bv { bs = 1 bv = s1 }
  let s2 = starterBid(2) if s2 > bv { bs = 2 bv = s2 }
  let s3 = starterBid(3) if s3 > bv { bs = 3 bv = s3 }
  let s4 = starterBid(4) if s4 > bv { bs = 4 bv = s4 }
  let s5 = starterBid(5) if s5 > bv { bs = 5 bv = s5 }
  let s6 = starterBid(6) if s6 > bv { bs = 6 bv = s6 }
  let s7 = starterBid(7) if s7 > bv { bs = 7 bv = s7 }
  turnSeat = if bs < 0 then 0 else bs
  phase = PH_TURN
  markAll()
}

mod setupFlipPress(s: int, slot: int) {
  if slot > 11 { return } // only grid cells flip in setup
  if setupFlips[s] >= 2 { return } // already flipped two
  if cellState(grid[s*12 + slot]) != ST_DOWN { return } // must be face-down
  flipCell(s, slot)
  setupFlips[s] = setupFlips[s] + 1
  markSeat(s)
  // pickStarter is NOT called here: the tick's setup watchdog is the single
  // call site (also catches setup completing by a seat leaving). One call site
  // keeps pickStarter inlined once, not twice.
}

mod swapInto(s: int, k: int) {
  let idx = s*12 + k
  // the replaced card's value is already known (assigned at deal); it goes to
  // the discard face-up, and the held card takes its place face-up.
  let oldVal = cellValue(grid[idx])
  grid[idx] = packCell(ST_UP, heldCard)
  cellVal[idx] = heldCard      // mirror: cell now holds the swapped-in card
  discardPush(discard, oldVal)
  heldCard = NO_CARD
  heldSource = HELD_NONE
}

// Resolve a hand after a card changes: clear completed columns, and if the seat is
// now all face-up, open the final lap. Shared by afterAction and the abandon
// auto-flip in advanceTurn (which resolves WITHOUT queueing another advance).
mod resolveHand(s: int) {
  columnClear(grid, cellVal, s*12, discard)
  if handAllUp(grid, s*12) && enderSeat < 0 {
    enderSeat = s
    finalMask = 0
    phase = PH_FINAL
  }
}

// Shared tail of every terminal action: resolve the hand, then queue the advance.
mod afterAction(s: int) {
  resolveHand(s)
  markSeat(s)
  turnPending = true
}

mod turnPress(s: int, slot: int) {
  if mustFlip {
    // Undo an accidental decline: clicking the discard pile reclaims the card just
    // discarded (it's on top) and returns to the drew-from-deck state, so a player
    // who didn't mean to discard isn't locked into flipping their last card.
    if slot == SLOT_TAKE {
      heldCard = discardTop(discard)
      discard.pop()
      heldSource = SRC_DECK
      mustFlip = false
      markSeat(s)
      return
    }
    if slot > 11 { return }
    if cellState(grid[s*12+slot]) != ST_DOWN { return }
    flipCell(s, slot)
    mustFlip = false
    afterAction(s)
    return
  }
  if heldCard == NO_CARD {
    if slot == SLOT_DRAW {
      heldCard = deckDraw(deck, discard)
      heldSource = SRC_DECK
      markSeat(s)
      return
    }
    if slot == SLOT_TAKE {
      heldCard = discardTop(discard)
      discard.pop() // remove the taken card
      heldSource = SRC_DISCARD
      markSeat(s)
      return
    }
    return // slot press with nothing held: ignore
  }
  // a card is held
  if slot <= 11 {
    // A cleared (column-removed) slot is EMPTY and not placeable — its physical
    // button still exists, so ignore the press and keep the held card rather than
    // resurrecting a dead cell + pushing a phantom 0 to the discard.
    if cellState(grid[s*12 + slot]) == ST_EMPTY { return }
    // swap: the replaced card goes face-up to the discard, held goes UP
    swapInto(s, slot)
    afterAction(s)
    return
  }
  if (slot == 12 || slot == SLOT_TAKE) && heldSource == SRC_DECK {
    // decline a deck draw -- either press the drawn card (12) OR the discard pile
    // (SLOT_TAKE): discard the held card, then must flip a face-down.
    discardPush(discard, heldCard)
    heldCard = NO_CARD
    heldSource = HELD_NONE
    mustFlip = true
    markSeat(s)
    return
  }
  // slot 12 / discard pile with a discard-sourced card: cannot re-discard -> ignore
}

// --- Dispatch (extended per-phase in Tasks 9-11) ---
mod dispatchPress(seat: int, slot: int) {
  if phase == PH_SETUP { setupFlipPress(seat, slot) return }
  if phase == PH_TURN || phase == PH_FINAL {
    if seat != turnSeat { return } // only the turn-holder acts
    turnPress(seat, slot)
  }
}

// --- InputReader for ready-up (W), one per seat (spec §2) ---
chip {
  let inp0 = InputReader(seat0)
  let inp1 = InputReader(seat1)
  let inp2 = InputReader(seat2)
  let inp3 = InputReader(seat3)
  let inp4 = InputReader(seat4)
  let inp5 = InputReader(seat5)
  let inp6 = InputReader(seat6)
  let inp7 = InputReader(seat7)
  buffer f0: float = inp0.Forward
  buffer f1: float = inp1.Forward
  buffer f2: float = inp2.Forward
  buffer f3: float = inp3.Forward
  buffer f4: float = inp4.Forward
  buffer f5: float = inp5.Forward
  buffer f6: float = inp6.Forward
  buffer f7: float = inp7.Forward
}

// W rising edge toggles this seat's ready bit while in lobby/gameover.
// Abandon the current game and return to the lobby (fresh scores). Used by the
// lone-survivor escape hatch below.
mod resetToLobby() {
  phase = PH_LOBBY
  readyMask = 0
  playingMask = 0
  heldCard = NO_CARD
  heldSource = HELD_NONE
  mustFlip = false
  enderSeat = -1
  finalMask = 0
  inputQueue.clear()
  scoreTotal.clear() scoreTotal.resize(8, 0)
  markAll()
}

// Leave the PH_SCORE review once everyone has acknowledged: to game over if a
// player reached 100, else back to the lobby for the next round.
mod finishScore() {
  readyMask = 0
  // Non-playing seats stay 0, so the array-wide max reaching 100 is equivalent to
  // a playing seat reaching 100 (one ArrayVar_Max gate vs the old 8x maxOne scan).
  if scoreTotal.max().Value >= 100 { phase = PH_GAMEOVER } else { phase = PH_LOBBY }
  markAll()
}

// PH_SCORE acknowledgement: set this seat's ack bit (readyMask reused). When
// every present, dealt-in seat has acknowledged, advance.
mod ackScore(i: int) {
  readyMask = readyMask | (1 << i)
  markSeat(i)
  let need = playingMask & hereMask
  if (readyMask & need) == need { finishScore() }
}

// W rising edge -> enqueue as SLOT_W. The queue's single dequeue routes it to
// handleW ONCE per tick, so the expensive ack / reset paths inline a single time
// rather than once per seat (8x). enqueue already gates on occupancy + queue cap.
mod readyEdge(i: int, fwd: float, fprev: float) {
  if fwd <= 0.5 || fprev > 0.5 { return }   // W rising edge only
  enqueue(i, SLOT_W)
}

// Phase logic for a dequeued W press (inlined once). Toggle ready in
// lobby/gameover, acknowledge the score screen, or -- mid-game with <= 1 dealt-in
// player still present -- bail the stuck game back to the lobby.
// (active & (active-1)) == 0 tests "0 or 1 bits set".
mod handleW(i: int) {
  if phase == PH_LOBBY || phase == PH_GAMEOVER {
    readyMask = readyMask ^ (1 << i)
    markSeat(i)
    return
  }
  if phase == PH_SCORE { ackScore(i) return }
  let active = playingMask & hereMask
  if (active & (active - 1)) == 0 { resetToLobby() }
}

// Reveal a seat's remaining face-down cells (assign real values, set UP).
mod revealCell(s: int, k: int) {
  let idx = s*12 + k
  let p = grid[idx]
  if cellState(p) == ST_DOWN {
    let v = cellValue(p)
    grid[idx] = packCell(ST_UP, v)
    cellVal[idx] = v
  }
}
mod revealAll(s: int) {
  revealCell(s, 0) revealCell(s, 1) revealCell(s, 2) revealCell(s, 3)
  revealCell(s, 4) revealCell(s, 5) revealCell(s, 6) revealCell(s, 7)
  revealCell(s, 8) revealCell(s, 9) revealCell(s, 10) revealCell(s, 11)
}

mod revealPlaying() {
  if ((playingMask >> 0) & 1) == 1 { revealAll(0) }
  if ((playingMask >> 1) & 1) == 1 { revealAll(1) }
  if ((playingMask >> 2) & 1) == 1 { revealAll(2) }
  if ((playingMask >> 3) & 1) == 1 { revealAll(3) }
  if ((playingMask >> 4) & 1) == 1 { revealAll(4) }
  if ((playingMask >> 5) & 1) == 1 { revealAll(5) }
  if ((playingMask >> 6) & 1) == 1 { revealAll(6) }
  if ((playingMask >> 7) & 1) == 1 { revealAll(7) }
}

mod sumSeat(i: int) {
  if ((playingMask >> i) & 1) == 1 { roundScore[i] = handSum(cellVal, sumTmp, i*12) }
}

mod foldSeat(i: int) {
  if ((playingMask >> i) & 1) == 1 { scoreTotal[i] = scoreTotal[i] + roundScore[i] }
}

mod scoreRound() {
  revealPlaying()
  roundScore.clear()
  roundScore.resize(8, 0)
  sumSeat(0) sumSeat(1) sumSeat(2) sumSeat(3)
  sumSeat(4) sumSeat(5) sumSeat(6) sumSeat(7)
  // ender doubling
  if enderSeat >= 0 { roundScore[enderSeat] = enderScore(roundScore, enderSeat, playingMask) }
  // fold into cumulative totals
  foldSeat(0) foldSeat(1) foldSeat(2) foldSeat(3)
  foldSeat(4) foldSeat(5) foldSeat(6) foldSeat(7)
  // STAY in PH_SCORE showing the revealed board + final scores. Players press W
  // to acknowledge; finishScore (via ackScore) then advances to the next round's
  // lobby or to game over. readyMask is reused as the ack mask.
  phase = PH_SCORE
  readyMask = 0
  markAll()
}

// Advance to the next occupied seat; in PH_FINAL, stop after everyone else has
// had their one last turn.
// `from` is a RESERVED KEYWORD (import..from) — the param is `fromSeat`.
mod nextOccupied(fromSeat: int) -> int {
  let active = playingMask & hereMask
  var i = fromSeat
  i = (i + 1) % 8
  // unrolled scan of up to 8 seats for the next active (playing AND here) bit
  if ((active >> i) & 1) == 1 { return i }
  i = (i + 1) % 8 if ((active >> i) & 1) == 1 { return i }
  i = (i + 1) % 8 if ((active >> i) & 1) == 1 { return i }
  i = (i + 1) % 8 if ((active >> i) & 1) == 1 { return i }
  i = (i + 1) % 8 if ((active >> i) & 1) == 1 { return i }
  i = (i + 1) % 8 if ((active >> i) & 1) == 1 { return i }
  i = (i + 1) % 8 if ((active >> i) & 1) == 1 { return i }
  return fromSeat
}

mod advanceTurn() {
  // Abandon path (fires only when a turn-holder leaves mid-turn; normal completion
  // reaches here with no held card and no pending flip). A still-held card (drew,
  // didn't place) is discarded. And if they bailed after drawing from the DECK, or
  // while already owing a flip, they don't escape the flip -- auto-flip one of
  // their face-down cells and resolve it (column clear / round-end). Captured
  // before the state is cleared below.
  let oweFlip = (heldCard != NO_CARD && heldSource == SRC_DECK) || mustFlip
  if heldCard != NO_CARD { discardPush(discard, heldCard) heldCard = NO_CARD heldSource = HELD_NONE }
  mustFlip = false
  if oweFlip { flipFirstDown(turnSeat) resolveHand(turnSeat) }
  if phase == PH_FINAL {
    finalMask = finalMask | (1 << turnSeat)
    // everyone PRESENT except the ender has taken their last turn. Masking need
    // with hereMask drops departed seats (nextOccupied never lands on them, so
    // their finalMask bit would otherwise never be set and PH_FINAL would hang).
    let need = playingMask & hereMask & ~(1 << enderSeat)
    if (finalMask & need) == need {
      phase = PH_SCORE
      scoreRound() // added in Task 11
      return
    }
  }
  turnSeat = nextOccupied(turnSeat)
  // skip the ender during PH_FINAL (they already went all-up)
  if phase == PH_FINAL && turnSeat == enderSeat { turnSeat = nextOccupied(turnSeat) }
  markAll()
}

mod bitCount(m: int) -> int {
  return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1)
    + ((m >> 4) & 1) + ((m >> 5) & 1) + ((m >> 6) & 1) + ((m >> 7) & 1)
}

// Deal 12 face-down cards, each carrying its real (hidden) value drawn from the
// deck. The value stays in main's state; it is masked to 0 on the wire (see
// fillCellFor) so it never leaks, and revealed in place by flipping to UP.
mod dealCell(s: int, k: int) {
  grid[s*12 + k] = packCell(ST_DOWN, deckPop(deck))
}
mod dealSeat(s: int) {
  dealCell(s, 0) dealCell(s, 1) dealCell(s, 2) dealCell(s, 3)
  dealCell(s, 4) dealCell(s, 5) dealCell(s, 6) dealCell(s, 7)
  dealCell(s, 8) dealCell(s, 9) dealCell(s, 10) dealCell(s, 11)
}
mod dealPlayingSeats() {
  if ((playingMask >> 0) & 1) == 1 { dealSeat(0) }
  if ((playingMask >> 1) & 1) == 1 { dealSeat(1) }
  if ((playingMask >> 2) & 1) == 1 { dealSeat(2) }
  if ((playingMask >> 3) & 1) == 1 { dealSeat(3) }
  if ((playingMask >> 4) & 1) == 1 { dealSeat(4) }
  if ((playingMask >> 5) & 1) == 1 { dealSeat(5) }
  if ((playingMask >> 6) & 1) == 1 { dealSeat(6) }
  if ((playingMask >> 7) & 1) == 1 { dealSeat(7) }
}

mod dealRound() {
  if phase == PH_GAMEOVER || scoreTotal.length() != 8 {
    scoreTotal.clear()
    scoreTotal.resize(8, 0)
  }
  playingMask = hereMask
  deckBuild(deck)
  discard.clear()
  // grid holds 96 cells; make sure it is sized, then deal each playing seat.
  grid.clear()
  grid.resize(96, packCell(ST_EMPTY, 0))
  cellVal.clear()
  cellVal.resize(96, 0)
  dealPlayingSeats()
  // seed discard with one card from the deck
  discardPush(discard, deckPop(deck))
  setupFlips.clear()
  setupFlips.resize(8, 0)
  roundScore.clear()
  roundScore.resize(8, 0)
  enderSeat = -1
  finalMask = 0
  readyMask = 0
  heldCard = NO_CARD
  heldSource = HELD_NONE
  mustFlip = false
  phase = PH_SETUP
  markAll()
}

mod maybeStart() {
  // every occupied seat ready AND at least two seats present
  if bitCount(hereMask) < 2 { return }
  if (readyMask & hereMask) != hereMask { return }
  resetPending = true // deal happens after the dequeue, spec §9
}

// Push seat s's cell k to the wire buffer, masking a face-down card's real
// value to 0 so hidden cards never leak (a DOWN cell renders as "?").
mod fillCellFor(buf: int[], s: int, k: int) {
  let p = grid[s*12 + k]
  buf.push(if cellState(p) == ST_DOWN then packCell(ST_DOWN, 0) else p)
}

mod drawnCellFor(s: int) -> int {
  // only the turn-holder with a held card shows a drawn card; else empty
  if s == turnSeat && heldCard != NO_CARD {
    return packCell(ST_UP, heldCard)
  }
  return packCell(ST_EMPTY, 0)
}

// Pack seat s's 13-cell view (12 grid + drawn slot) into its cardsBuf.
mod pushSeat(s: int, buf: int[]) {
  buf.clear()
  // Lobby/gameover: show 12 face-down "backs" when this seat is readied (a
  // nonzero card state that confirms the ready toggle registered), else all
  // blank. The board isn't dealt yet, so we don't read grid here.
  if phase == PH_LOBBY || phase == PH_GAMEOVER {
    let back = if ((readyMask >> s) & 1) == 1 then packCell(ST_DOWN, 0) else packCell(ST_EMPTY, 0)
    buf.resize(12, back)              // 12 identical backs (buf was just cleared)
    buf.push(packCell(ST_EMPTY, 0))   // drawn slot: empty in lobby
    return
  }
  fillCellFor(buf, s, 0) fillCellFor(buf, s, 1) fillCellFor(buf, s, 2) fillCellFor(buf, s, 3)
  fillCellFor(buf, s, 4) fillCellFor(buf, s, 5) fillCellFor(buf, s, 6) fillCellFor(buf, s, 7)
  fillCellFor(buf, s, 8) fillCellFor(buf, s, 9) fillCellFor(buf, s, 10) fillCellFor(buf, s, 11)
  buf.push(drawnCellFor(s))
}

// Push ONE seat's board this tick. pushSeat fills the shared scratch (so its
// 13-cell fill inlines a single time regardless of seat); we then copy the
// scratch into that seat's real buffer and pulse its update. Only the cheap
// copy+emit is repeated per seat. `emit updateN` must fire from here (a mod
// inlined into `chip on tick`) -- an emit from a called *chip* wouldn't reach
// the outer output port.
mod serviceBoardSeat(s: int) {
  pushSeat(s, boardScratch)
  if s == 0 { cardsBuf0.copyFrom(boardScratch) emit update0 }
  if s == 1 { cardsBuf1.copyFrom(boardScratch) emit update1 }
  if s == 2 { cardsBuf2.copyFrom(boardScratch) emit update2 }
  if s == 3 { cardsBuf3.copyFrom(boardScratch) emit update3 }
  if s == 4 { cardsBuf4.copyFrom(boardScratch) emit update4 }
  if s == 5 { cardsBuf5.copyFrom(boardScratch) emit update5 }
  if s == 6 { cardsBuf6.copyFrom(boardScratch) emit update6 }
  if s == 7 { cardsBuf7.copyFrom(boardScratch) emit update7 }
}

// Central discard/deck displays -- cheap, refreshed every tick.
mod updateCentral() {
  if discard.length() == 0 {
    vDiscardColor = Color(0.133, 0.133, 0.133, 1.0)
    vDiscardText = ""
  } else {
    let top = discardTop(discard)
    vDiscardColor = cellColor(packCell(ST_UP, top))
    vDiscardText = cellText(packCell(ST_UP, top))   // 0 -> "O", same as the cards
  }
  vDeckCount = deck.length()
}
mod seatOfIndex(i: int) -> character {
  if i == 0 { return seat0 }
  if i == 1 { return seat1 }
  if i == 2 { return seat2 }
  if i == 3 { return seat3 }
  if i == 4 { return seat4 }
  if i == 5 { return seat5 }
  if i == 6 { return seat6 }
  return seat7
}

mod sanitizeName(s: string) -> string {
  return s.Replace(";", "&scl;").Replace("<", "&lt;")
}

// The occupant's sanitized display name, or "Seat N" when the seat is empty.
// serviceSeat is round-robin (one seat/tick) and this is called once per service
// for the turn-holder, so calling GetDisplayName directly is cheap -- no name
// cache needed. Sanitized so a "<" or ";" in a name can't break the HUD markup.
mod seatName(i: int) -> string {
  if ((hereMask >> i) & 1) == 0 { return "Seat ${i + 1}" }
  return sanitizeName(seatOfIndex(i).GetDisplayName())
}

// The action prompt (middle slot). Ready state is green/red here; the title,
// ready count, and whose-turn live in the banner (top slot) via bannerText.
mod promptFor(i: int) -> string {
  if phase == PH_GAMEOVER {
    return if ((readyMask >> i) & 1) == 1
      then 'You are <color="8f8"><b>READY</></> - tap <b>W</> to unready'
      else 'Tap <b>W</> to start a new game'
  }
  if phase == PH_LOBBY {
    let seated = bitCount(hereMask)
    let ready = bitCount(readyMask & hereMask)
    return if ((readyMask >> i) & 1) == 1
      then 'You are <color="8f8"><b>READY</></> (${ready}/${seated}) - tap <b>W</> to unready'
      else 'You are <color="f66"><b>NOT READY</></> (${ready}/${seated}) - tap <b>W</> to ready up'
  }
  if phase == PH_SETUP { return "Flip 2 cards to start (${setupFlips[i]}/2)" }
  if phase == PH_SCORE {
    return if ((readyMask >> i) & 1) == 1
      then 'Ready for next round (${bitCount(readyMask & playingMask & hereMask)}/${bitCount(playingMask & hereMask)}) - waiting...'
      else 'Round over - tap <b>W</> to continue'
  }
  if i != turnSeat { return "Waiting for ${seatName(turnSeat)}" }
  if mustFlip { return "Flip a face-down card" }
  if heldCard != NO_CARD {
    return if heldSource == SRC_DECK
      then "Press a card to swap, or the discard pile / drawn card to discard & flip"
      else "Press a card to swap it in"
  }
  return "Draw a card, or take the discard"
}

// Banner (top slot): styled title + ready count in the lobby, the winner at
// game over, and whose-turn during play (stolen from coup/secret-hitler).
mod bannerText(i: int) -> string {
  if phase == PH_LOBBY {
    return '<size="42"><font="orbitron">SKYJO</></><br>Sit and tap <b>W</> to ready (2-8 players) - ${bitCount(readyMask & hereMask)}/${bitCount(hereMask)} ready'
  }
  if phase == PH_GAMEOVER {
    let w = lowestSeat(scoreTotal, playingMask)
    return '<size="42"><font="orbitron">SKYJO</></><br><color="8f8">Winner: ${seatName(w)}</> with ${scoreTotal[w]} points'
  }
  if phase == PH_SETUP {
    return '<size="36"><font="orbitron">SKYJO</></><br>Flip 2 cards to begin'
  }
  if phase == PH_SCORE {
    return '<size="36"><font="orbitron">ROUND OVER</></><br>Final scores below - tap <b>W</> to continue'
  }
  if phase == PH_FINAL {
    return if i == turnSeat
      then '<size="34"><color="ff8"><b>YOUR LAST TURN!</></></>'
      else '<size="28"><color="ff8">Final round</> - ${seatName(turnSeat)} takes their last turn'
  }
  if i == turnSeat { return '<size="34"><color="8f8"><b>YOUR TURN</></></>' }
  return '<size="28">${seatName(turnSeat)} to play</>'
}

let TID_BANNER = 4
let TID_PROMPT = 5
let TID_SCORE = 6
let HUD_LIFE = 5.0

mod serviceSeat(i: int) {
  if ((hereMask >> i) & 1) == 0 { return }
  let ch = seatOfIndex(i)
  ch.DisplayText(bannerText(i), textId = TID_BANNER, positionX = 0.0, positionY = -30.0,
    fontSize = 24, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.25)
  ch.DisplayText(promptFor(i), textId = TID_PROMPT, positionX = 0.0, positionY = 60.0,
    fontSize = 20, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.5)
  ch.DisplayText("Round ${roundScore[i]}  Total ${scoreTotal[i]}", textId = TID_SCORE,
    positionX = 0.0, positionY = -40.0, fontSize = 18, lifetime = HUD_LIFE,
    justify = "Center", anchorY = 0.8)
}

@label("Tick")
chip on tick {
  // One-time sizing: grid holds 96 cells; sized here so a lobby-phase board push
  // (before any deal) reads in bounds.
  if !gridReady { gridReady = true grid.resize(96, packCell(ST_EMPTY, 0)) cellVal.resize(96, 0) markAll() }

  @label("Ready input")
  chip {
    readyEdge(0, inp0.Forward, f0)
    readyEdge(1, inp1.Forward, f1)
    readyEdge(2, inp2.Forward, f2)
    readyEdge(3, inp3.Forward, f3)
    readyEdge(4, inp4.Forward, f4)
    readyEdge(5, inp5.Forward, f5)
    readyEdge(6, inp6.Forward, f6)
    readyEdge(7, inp7.Forward, f7)
  }

  // Skip an absent turn-holder: if the current player has left their seat, force
  // an advance (nextOccupied skips absent seats; advanceTurn marks their PH_FINAL
  // bit). Guarded on active != 0 so an all-absent table idles instead of spinning.
  if (phase == PH_TURN || phase == PH_FINAL) && ((hereMask >> turnSeat) & 1) == 0 && (playingMask & hereMask) != 0 { turnPending = true }

  // Setup can complete by the last blocking seat LEAVING (seatFlips counts an
  // absent seat done, but no flip event fires to re-check setupDone), so
  // re-evaluate it every tick to avoid a stall. pickStarter's phase=PH_TURN
  // makes this self-clearing.
  if phase == PH_SETUP && setupDone() { pickStarter() }

  if turnPending { turnPending = false advanceTurn() }

  // Central pile buttons -> queue (turn-holder rising edge only). Runs AFTER
  // advanceTurn so a same-tick pile press attributes to the CURRENT (post-
  // advance) turn-holder. Plain vars (not buffers) so the prev-state update is
  // explicit.
  let drawNow = turnHolderIs(drawBtn)
  if drawNow && !drawPrevHeld { inputQueue.push(phase * 512 + turnSeat * 16 + SLOT_DRAW) }
  drawPrevHeld = drawNow
  let takeNow = turnHolderIs(discardBtn)
  if takeNow && !takePrevHeld { inputQueue.push(phase * 512 + turnSeat * 16 + SLOT_TAKE) }
  takePrevHeld = takeNow

  @label("Input queue")
  chip {
    if inputQueue.length() > 0 {
      let ev = inputQueue[0]
      inputQueue.remove(0)
      if ev / 512 == phase {
        let s = (ev % 512) / 16
        let sl = ev % 16
        if sl == SLOT_W { handleW(s) } else { dispatchPress(s, sl) }
      }
    }
  }

  if resetPending { resetPending = false dealRound() }

  // Leaving a seat un-readies that player: prune ready/ack bits against live
  // occupancy every tick. readyMask is 0 during active play, so this is a no-op
  // then; in the lobby / gameover / score wait it drops a departed player's bit.
  let prunedReady = readyMask & hereMask
  if prunedReady != readyMask { readyMask = prunedReady markAll() }

  if phase == PH_LOBBY || phase == PH_GAMEOVER { maybeStart() }

  // Central piles every tick (cheap); pop one queued seat and push its board.
  updateCentral()
  // Service one queued seat. NOTE: pop()'s IsEmpty means "empty AFTER the pop", so
  // it's true when you pop the LAST element -- guarding on it drops that element
  // (the lone W-press case). Gate on length() BEFORE popping instead. Order is
  // irrelevant for dirty seats; LIFO services the seat marked this tick first.
  if dirtyQ.length() > 0 {
    let ds = dirtyQ.pop()
    serviceBoardSeat(ds.Value)
  }
  serviceSeat(tick % 8)
}
