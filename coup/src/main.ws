@fold

import {
  CARD_DUKE, CARD_ASSASSIN, CARD_AMBASSADOR, CARD_CAPTAIN, CARD_CONTESSA, CARD_HIDDEN, cardText,
  cardTextColored,
} from "cards"
import { influenceOf, seatDead, slotValue, packSeat } from "hand"
import {
  ACT_COUNT, ACT_INCOME, ACT_COUP, ACT_FOREIGN_AID, ACT_TAX, ACT_ASSASSINATE, ACT_EXCHANGE,
  ACT_STEAL, actionName, actionCost, actionGain, actionTargeted, actionClaim, actionBlocker,
} from "actions"
import { deckCopies, deckBuild, deckDraw, deckReturn } from "deck"
import { LOG_LINES, sanitizeName, hudHand, hudBanner, hudPrompt, hudActivity } from "display"

// ---- Inputs (all @right per board layout) ----
// No start/reset ports: the game is driven entirely from the seats. On the
// six-seat board, player6..player9 are simply left unwired; an unwired
// character port reads 0, so those seats never enter hereMask.
@right in player0: character
@right in player1: character
@right in player2: character
@right in player3: character
@right in player4: character
@right in player5: character
@right in player6: character
@right in player7: character
@right in player8: character
@right in player9: character

// ---- Live occupancy (pure, never cached) ----
let seatedNow = player0 + player1 + player2 + player3 + player4
  + player5 + player6 + player7 + player8 + player9
let hereMask = player0 + player1 * 2 + player2 * 4 + player3 * 8
  + player4 * 16 + player5 * 32 + player6 * 64 + player7 * 128
  + player8 * 256 + player9 * 512

// ---- Phases ----
let PH_LOBBY = 0
let PH_TURN = 1
// PH_RESPOND: a targeted claim (Assassinate or Steal) pauses here until its
// target answers Block/Allow. Coup is targeted too but is unblockable and
// unchallengeable, so it never enters this phase -- it applies and advances
// immediately, same as any untargeted action. A declared Block (blockClaim,
// or declareBlock's retroactive Foreign Aid path) is itself a claim, so it
// re-enters (or, for Foreign Aid, first enters) this same phase with the
// wait handed to the actor instead of the target -- respondWaitSeat() is the
// single source of truth for which seat is currently being waited on.
let PH_RESPOND = 2
let PH_EXCHANGE = 3
let PH_LOSE = 4
let PH_GAMEOVER = 5

var phase: int = 0

// ---- Per-seat state ----
// Literal-initialised to ten slots so every read is in bounds from the first
// tick, before anything resets.
array handA: int[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
array handB: int[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
array coins: int[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
var lostAMask: int = 0
var lostBMask: int = 0
var playingMask: int = 0

// ---- Turn and claim state ----
var turnSeat: int = 0
var pendKind: int = 0
var pendSeat: int = -1
var pendTarget: int = -1
var pendCard: int = 0
var pendCoins: int = 0
var blockSeat: int = -1

// ---- Deck ----
array deck: int[]
var nDuke: int = 0
var nAssassin: int = 0
var nAmbassador: int = 0
var nCaptain: int = 0
var nContessa: int = 0

// ---- Deferred flags ----
var boardDirty: bool = false
var turnPending: bool = false
var resetPending: bool = false

// ---- Activity log: always exactly LOG_LINES slots so the fixed-index render
// never reads out of bounds. Reset with fill(""), never clear(). ----
array activityLog: string[] = ["", "", "", "", "", "", "", ""]

// ---- Published board state ----
var vP0: int = 255
var vP1: int = 255
var vP2: int = 255
var vP3: int = 255
var vP4: int = 255
var vP5: int = 255
var vP6: int = 255
var vP7: int = 255
var vP8: int = 255
var vP9: int = 255
var vTurn: int = 0
var vAim: int = 0
var vReady: int = 0
var vSelecting: int = 0
var vDiscarding: int = 0
var vPlaying: int = 0
var vBlock: int = 0
var vDeckCount: int = 0
var readyMask: int = 0
var aimMask: int = 0
var selectingMask: int = 0
// Paired with, and strictly narrower than, selectingMask: selecting alone is
// the exchange fan, selecting+discarding is the lose-influence prompt.
//   selecting | discarding | board renders
//   set       | clear      | exchange fan, 3-4 cards
//   set       | set        | choosing an influence to lose, 2 cards
//   clear     | clear      | normal hand
var discardingMask: int = 0

@left out p0: int = vP0.Value
@left out p1: int = vP1.Value
@left out p2: int = vP2.Value
@left out p3: int = vP3.Value
@left out p4: int = vP4.Value
@left out p5: int = vP5.Value
@left out p6: int = vP6.Value
@left out p7: int = vP7.Value
@left out p8: int = vP8.Value
@left out p9: int = vP9.Value
@left out turn: int = vTurn.Value
@left out aim: int = vAim.Value
@left out ready: int = vReady.Value
@left out selecting: int = vSelecting.Value
@left out discarding: int = vDiscarding.Value
@left out playing: int = vPlaying.Value
@left out block: int = vBlock.Value
@left out deckCount: int = vDeckCount.Value
@left out deckDukes: int = nDuke.Value
@left out deckAssassins: int = nAssassin.Value
@left out deckAmbassadors: int = nAmbassador.Value
@left out deckCaptains: int = nCaptain.Value
@left out deckContessas: int = nContessa.Value
// Not redundant with vSelecting/selectingMask: this is a distinct interface
// for the board prop, not a duplicate of the per-seat mask. The deck prop
// should visually look shorter whenever any cards are away from the deck in
// someone's selection fan (PH_LOSE, PH_EXCHANGE) -- a single bool driving a
// physical prop, separate from the int mask that drives per-seat displays.
@left out shortDeck: bool = selectingMask != 0

// Pack one seat's public integer. Slot 15 means the seat is not in the game;
// a live influence is face-down (0) and a lost one shows its revealed role.
mod seatPacked(i: int) -> int {
  let isPlaying = (playingMask >> i) & 1
  let isSelecting = (selectingMask >> i) & 1
  var a: int = slotValue(isPlaying, (lostAMask >> i) & 1, handA[i])
  var b: int = slotValue(isPlaying, (lostBMask >> i) & 1, handB[i])
  // While this seat is selecting (exchange fan or the lose-influence prompt),
  // a still-live slot is picked up off the table into the fan and publishes
  // hidden, same as an empty seat. A lost slot is revealed face-up and was
  // never picked up, so it keeps publishing its role even mid-selection --
  // that also keeps the elimination record visible to everyone else while an
  // exchange is in progress.
  if isSelecting && ((lostAMask >> i) & 1) == 0 { a = CARD_HIDDEN }
  if isSelecting && ((lostBMask >> i) & 1) == 0 { b = CARD_HIDDEN }
  // A seat not in playingMask (never dealt in, or left over from a reset)
  // must publish 0 coins, same as its card slots publish 15 -- otherwise a
  // spectator or a post-reset seat shows the previous occupant's coin count.
  var c: int = 0
  if isPlaying { c = coins[i] }
  return packSeat(a, b, c)
}

// Recompute EVERY board output after any state mutation, so the board never
// sees intermediate values. Deferred behind boardDirty: many mutation sites
// would each inline this whole body.
chip refreshBoard() {
  vP0 = seatPacked(0)
  vP1 = seatPacked(1)
  vP2 = seatPacked(2)
  vP3 = seatPacked(3)
  vP4 = seatPacked(4)
  vP5 = seatPacked(5)
  vP6 = seatPacked(6)
  vP7 = seatPacked(7)
  vP8 = seatPacked(8)
  vP9 = seatPacked(9)
  vDeckCount = deck.length()
  vTurn = if phase == PH_LOBBY || phase == PH_GAMEOVER then 0 else 1 << turnSeat
  vAim = aimMask
  vReady = readyMask
  vSelecting = selectingMask
  vDiscarding = discardingMask
  vPlaying = playingMask
  vBlock = if blockSeat < 0 then 0 else 1 << blockSeat
}

let KEY_W = 0
let KEY_A = 1
let KEY_D = 2
let KEY_S = 3
let KEY_SPACE = 4

// Pending taps as (phase*128 + seat*8 + key); ONE is dequeued per tick through
// a single dispatch site so the phase machine inlines once.
array inputQueue: int[]

// Three independent double-press latches so confirm, challenge and block
// cannot disarm each other. Each is a per-seat bitmask (bit i = seat i is
// armed), not a single shared bool: seat ownership lives in the bit position
// itself, so one seat's movement keys can only ever clear that seat's own
// bit, never another seat's armed confirm/challenge/block.
var wArmMask: int = 0
var spaceArmMask: int = 0
// S,S always means Block: a retroactive declareBlock on an outstanding
// Foreign Aid claim, or (for the PH_RESPOND target of an Assassinate or
// Steal) a direct shortcut straight to blockClaim. Exactly one of those two
// is ever reachable for a given press -- see canDeclareBlock and tapKey's
// shared S dispatch.
var sArmMask: int = 0
var lastTake: int = 0

mod logLine(s: string) {
  activityLog.push(s)
  if activityLog.length() > LOG_LINES { activityLog.remove(0) }
}

// Declared early, ahead of the whole mid-file mutation block: chip/mod calls
// must be declared before the point where they are used (WS021), and by now
// nextTurn's own "seat away" log line is among seatName's callers, not just
// checkWin/bannerText further down. `names` itself (an ordinary global array)
// has no such ordering requirement, so only this declaration's position
// matters -- check it again before adding any call site above this point.
mod seatName(i: int) -> string {
  let n = names[i]
  return if n == "" then "Seat ${i}" else n
}

mod queueInput(i: int, key: int) {
  if inputQueue.length() < 32 {
    inputQueue.push(phase * 128 + i * 8 + key)
  }
}

// An unoccupied seat's InputReader aliases the local player's input, so every
// edge is gated on live occupancy.
mod readSeatInput(i: int, fwd: float, rgt: float, jmp: bool,
  fprev: float, rprev: float, jprev: bool) {
  if (hereMask & (1 << i)) == 0 { return }
  if fwd > 0.5 && fprev <= 0.5 { queueInput(i, KEY_W) }
  if fwd < -0.5 && fprev >= -0.5 { queueInput(i, KEY_S) }
  if rgt < -0.5 && rprev >= -0.5 { queueInput(i, KEY_A) }
  if rgt > 0.5 && rprev <= 0.5 { queueInput(i, KEY_D) }
  if jmp && !jprev { queueInput(i, KEY_SPACE) }
}

mod toggleReady(i: int) {
  readyMask = readyMask ^ (1 << i)
  boardDirty = true
}

// LOBBY private prompt for the seat's occupant.
mod lobbyPrompt(i: int) -> string {
  let seated = seatedNow
  let ready = BitCount(readyMask)
  let need = if seated < 3 then " - need ${3 - seated} more seated"
    else if seated > 10 then " - too many (max 10)"
    else " - starts when all ready"
  return if (readyMask & (1 << i))
    then 'You are <color="8f8">READY</> (${ready}/${seated})<br>Tap <b>W</> to unready${need}'
    else 'You are <color="f66">NOT READY</> (${ready}/${seated})<br>Tap <b>W</> to ready up${need}'
}

var selAction: int = 0
var selTarget: int = -1
var selStage: int = 0 // 0 = picking action, 1 = picking target

mod countAdjust(role: int, delta: int) {
  nDuke += delta * (role == CARD_DUKE)
  nAssassin += delta * (role == CARD_ASSASSIN)
  nAmbassador += delta * (role == CARD_AMBASSADOR)
  nCaptain += delta * (role == CARD_CAPTAIN)
  nContessa += delta * (role == CARD_CONTESSA)
}

mod drawInto(i: int, slotB: bool) {
  let c = deckDraw(deck)
  if c == 0 { return }
  countAdjust(c, -1)
  if slotB { handB[i] = c } else { handA[i] = c }
}

// Ten unrolled probes; the first live seat at or after `fromSeat` wins.
// NOTE: the brief's parameter name `from` is a reserved keyword in this
// compiler (used by `import ... from "..."`) and fails to parse verbatim;
// renamed to `fromSeat` here. See task-8-report.md for details. The name is
// purely local (all call sites below pass positional args), so this is a
// syntax-only substitution with no semantic change.
mod nextAliveSeat(fromSeat: int) -> int {
  let alive = playingMask & ~(lostAMask & lostBMask)
  let s0 = (fromSeat + 0) % 10
  let s1 = (fromSeat + 1) % 10
  let s2 = (fromSeat + 2) % 10
  let s3 = (fromSeat + 3) % 10
  let s4 = (fromSeat + 4) % 10
  let s5 = (fromSeat + 5) % 10
  let s6 = (fromSeat + 6) % 10
  let s7 = (fromSeat + 7) % 10
  let s8 = (fromSeat + 8) % 10
  let s9 = (fromSeat + 9) % 10
  return if (alive & (1 << s0)) then s0
    else if (alive & (1 << s1)) then s1
    else if (alive & (1 << s2)) then s2
    else if (alive & (1 << s3)) then s3
    else if (alive & (1 << s4)) then s4
    else if (alive & (1 << s5)) then s5
    else if (alive & (1 << s6)) then s6
    else if (alive & (1 << s7)) then s7
    else if (alive & (1 << s8)) then s8
    else if (alive & (1 << s9)) then s9
    else fromSeat
}

// Same scan as nextAliveSeat, but excludes `actor` and, unlike nextAliveSeat,
// also requires hereMask: an away seat cannot answer Block/Allow or a
// challenge, so targeting one just burns the actor's coins on a seat no one
// is present to defend or contest. The scan simply skips absent seats the
// same way it already skips dead/non-playing ones -- no separate exclusion
// list, so a seat becomes targetable again the instant it reconnects.
mod nextTargetSeat(fromSeat: int, actor: int) -> int {
  let alive = playingMask & ~(lostAMask & lostBMask) & hereMask
  let s0 = (fromSeat + 0) % 10
  let s1 = (fromSeat + 1) % 10
  let s2 = (fromSeat + 2) % 10
  let s3 = (fromSeat + 3) % 10
  let s4 = (fromSeat + 4) % 10
  let s5 = (fromSeat + 5) % 10
  let s6 = (fromSeat + 6) % 10
  let s7 = (fromSeat + 7) % 10
  let s8 = (fromSeat + 8) % 10
  let s9 = (fromSeat + 9) % 10
  return if (alive & (1 << s0)) && s0 != actor then s0
    else if (alive & (1 << s1)) && s1 != actor then s1
    else if (alive & (1 << s2)) && s2 != actor then s2
    else if (alive & (1 << s3)) && s3 != actor then s3
    else if (alive & (1 << s4)) && s4 != actor then s4
    else if (alive & (1 << s5)) && s5 != actor then s5
    else if (alive & (1 << s6)) && s6 != actor then s6
    else if (alive & (1 << s7)) && s7 != actor then s7
    else if (alive & (1 << s8)) && s8 != actor then s8
    else if (alive & (1 << s9)) && s9 != actor then s9
    else fromSeat
}

// A seat this actor could actually pick: alive, in the game, present, not
// itself. Mirrors nextTargetSeat's own legality test exactly (read-only --
// selection itself still routes through nextTargetSeat, this is only used to
// decide what the fan renders, and by commitSelection to revalidate a
// previously-picked target at confirm time). Declared here, ahead of
// commitSelection, rather than down with the other fan-text helpers it was
// originally grouped with -- commitSelection is now among its callers too.
// `mask` is `playingMask & ~(lostAMask & lostBMask) & hereMask` -- the same
// term nextTargetSeat's own `alive` binds -- invariant across every probe in
// one scan or fan, so every caller that calls this more than once (or even
// once, since the signature is shared) computes it once and passes it down
// rather than this mod re-deriving it on every probe.
mod canTargetSeat(s: int, actor: int, mask: int) -> bool {
  return (mask & (1 << s)) && s != actor
}

// Whether `actor` has any legal target at all. Ten unrolled canTargetSeat
// probes (no loop), same convention as every other seat scan in this file.
// Feeds canAffordAction: a targeted action with nobody left to name it
// against (every other living player away, or eliminated) must never be
// selectable, and the forced-coup rule must lapse rather than wedge the
// player on an unnameable Coup -- see canAffordAction for the full case.
mod hasLegalTarget(actor: int) -> bool {
  // Algebraically equal to the ten unrolled canTargetSeat(s, actor) probes:
  // canTargetSeat tests (playingMask & ~(lostAMask & lostBMask) & hereMask &
  // (1 << s)) && s != actor for s in 0..9. playingMask/hereMask only ever
  // carry bits 0..9, so ANDing them zeroes any spurious high bits that
  // ~(lostAMask & lostBMask) sets -- the mask below only ever has bits 0..9
  // live, same as nextTargetSeat's identical mask term. Excluding bit `actor`
  // via ~(1 << actor) is then exactly "s != actor" for every s the old loop
  // ever probed, so "any bit set outside actor" is exactly "some legal
  // target exists".
  return (playingMask & ~(lostAMask & lostBMask) & hereMask & ~(1 << actor)) != 0
}

// Direction-aware target step for A/D cycling. Unlike nextTargetSeat (which
// answers "the first legal seat at or after this point", used for an initial
// pick), this answers "the next legal seat when stepping away from a seat
// that is already selected" -- it deliberately excludes offset 0 so a press
// always moves, and only revisits fromSeat itself at the final n = 10 probe
// (the "+ n*10" term keeps each offset non-negative for dir == -1), which is
// exactly the single-legal-target fallback: cycling stays put instead of
// spinning.
mod stepTargetSeat(fromSeat: int, dir: int, actor: int) -> int {
  // Invariant across all ten probes below -- computed once here rather than
  // by canTargetSeat on every probe.
  let mask = playingMask & ~(lostAMask & lostBMask) & hereMask
  let s1 = (fromSeat + dir * 1 + 10) % 10
  let s2 = (fromSeat + dir * 2 + 20) % 10
  let s3 = (fromSeat + dir * 3 + 30) % 10
  let s4 = (fromSeat + dir * 4 + 40) % 10
  let s5 = (fromSeat + dir * 5 + 50) % 10
  let s6 = (fromSeat + dir * 6 + 60) % 10
  let s7 = (fromSeat + dir * 7 + 70) % 10
  let s8 = (fromSeat + dir * 8 + 80) % 10
  let s9 = (fromSeat + dir * 9 + 90) % 10
  let s10 = (fromSeat + dir * 10 + 100) % 10
  return if canTargetSeat(s1, actor, mask) then s1
    else if canTargetSeat(s2, actor, mask) then s2
    else if canTargetSeat(s3, actor, mask) then s3
    else if canTargetSeat(s4, actor, mask) then s4
    else if canTargetSeat(s5, actor, mask) then s5
    else if canTargetSeat(s6, actor, mask) then s6
    else if canTargetSeat(s7, actor, mask) then s7
    else if canTargetSeat(s8, actor, mask) then s8
    else if canTargetSeat(s9, actor, mask) then s9
    else if canTargetSeat(s10, actor, mask) then s10
    else fromSeat
}

// Whether an actor with `myCoins` coins and `targetable` (whether they have
// any legal target at all, per hasLegalTarget) may currently select action
// `a`: enough coins for its cost, with the forced-coup override once coins
// reach 10 -- unless Coup itself has no legal target (every other living
// player is away or eliminated), in which case the forced-coup rule lapses
// instead of wedging the player on an action the target fan can never
// actually offer. A targeted action is never selectable at all without a
// legal target, forced or not, for the same reason. Income costs nothing and
// is never targeted, so it is always affordable -- a present, living
// turn-taker always has at least one selectable action. Single source of
// truth: commitSelection calls this directly (no separate mirrored backstop
// to fall out of sync), as does the fan's greyed-out state and the A/D skip
// (stepAction). myCoins/targetable are invariant across every probe a single
// caller makes for one actor (stepAction's seven probes, actionFanText's
// seven fan entries, commitSelection's one check) -- callers compute
// coins[actor]/hasLegalTarget(actor) once and pass them down, rather than
// this mod re-deriving them (and re-reading coins[]) on every call.
mod canAffordAction(a: int, myCoins: int, targetable: bool) -> bool {
  if actionTargeted(a) && !targetable { return false }
  if myCoins >= 10 && targetable { return a == ACT_COUP }
  return myCoins >= actionCost(a)
}

// Direction-aware action step for A/D cycling, skipping unaffordable actions.
// Same "probe n = 1..ACT_COUNT, wrap via + n*ACT_COUNT" convention as
// stepTargetSeat and for the same reason: offset 0 is excluded so a press
// always moves, and the final probe (n == ACT_COUNT) revisits fromAction
// itself. Income cost is 0, so at least one action is always affordable
// (Income below 10 coins, Coup at 10+) -- the fallback return is defensive,
// never actually reachable, but kept for the same reason every other scan in
// this file has one.
mod stepAction(fromAction: int, dir: int, actor: int) -> int {
  // Invariant across all seven probes below -- computed once here rather
  // than by canAffordAction on every probe.
  let targetable = hasLegalTarget(actor)
  let myCoins = coins[actor]
  let a1 = (fromAction + dir * 1 + ACT_COUNT * 1) % ACT_COUNT
  let a2 = (fromAction + dir * 2 + ACT_COUNT * 2) % ACT_COUNT
  let a3 = (fromAction + dir * 3 + ACT_COUNT * 3) % ACT_COUNT
  let a4 = (fromAction + dir * 4 + ACT_COUNT * 4) % ACT_COUNT
  let a5 = (fromAction + dir * 5 + ACT_COUNT * 5) % ACT_COUNT
  let a6 = (fromAction + dir * 6 + ACT_COUNT * 6) % ACT_COUNT
  let a7 = (fromAction + dir * 7 + ACT_COUNT * 7) % ACT_COUNT
  return if canAffordAction(a1, myCoins, targetable) then a1
    else if canAffordAction(a2, myCoins, targetable) then a2
    else if canAffordAction(a3, myCoins, targetable) then a3
    else if canAffordAction(a4, myCoins, targetable) then a4
    else if canAffordAction(a5, myCoins, targetable) then a5
    else if canAffordAction(a6, myCoins, targetable) then a6
    else if canAffordAction(a7, myCoins, targetable) then a7
    else fromAction
}

mod dealSeat(i: int) {
  if (playingMask & (1 << i)) == 0 { return }
  coins[i] = 2
  drawInto(i, false)
  drawInto(i, true)
}

chip dealCards() {
  dealSeat(0) dealSeat(1) dealSeat(2) dealSeat(3) dealSeat(4)
  dealSeat(5) dealSeat(6) dealSeat(7) dealSeat(8) dealSeat(9)
}

mod resetState() {
  phase = PH_LOBBY
  lostAMask = 0
  lostBMask = 0
  playingMask = 0
  readyMask = 0
  aimMask = 0
  selectingMask = 0
  discardingMask = 0
  blockSeat = -1
  pendKind = 0
  pendSeat = -1
  pendTarget = -1
  pendCard = 0
  pendCoins = 0
  turnSeat = 0
  winnerSeat = -1
  selAction = 0
  selTarget = -1
  selStage = 0
  // Exchange and lose-influence prompt state, so a fan or prompt abandoned
  // mid-flight (e.g. the lone-player escape hatch firing while PH_EXCHANGE or
  // PH_LOSE is open) cannot leak into the next game. In particular a stale
  // exKeptMask bit outside the next exchange's exCount would still count
  // toward exchangeFinalize's BitCount(exKeptMask) == influence check without
  // ever landing in firstKept/secondKept -- a card kept in hand AND returned
  // to the deck.
  exKeptMask = 0
  exchangeSeat = -1
  exCount = 0
  exHandCount = 0
  exHi = 0
  loseSeat = -1
  watchdogAbsentTicks = 0
  // The one deferred flag resetState previously missed: resolveChallenge's
  // self-challenge branch (loseTwoInfluence path) can leave this set right
  // before checkWin ends the game, and nextTurn's away-skip re-arms it on
  // every tick that lands on an unwired seat. If it survives into the next
  // game, the tick after startGame runs nextTurn before anyone has acted,
  // silently skipping seat 0's first turn.
  turnPending = false
  // Queued taps are tagged with the phase they were captured under
  // (queueInput's phase*128 encoding); a stale event surviving into the next
  // game could still match if that phase number recurs, so the whole queue
  // must be dropped rather than merely outrun. Read only via length()/[0]/
  // remove(0), never a fixed index, so losing its length here is safe.
  inputQueue.clear()
  deck.clear()
  // The per-role counters must be zeroed alongside the deck. resetState is
  // reachable standalone (the lone-survivor escape hatch, and an emptied table
  // at game over) with no guaranteed startGame() after it, so leaving them
  // would publish the previous game's role counts next to deckCount == 0.
  nDuke = 0
  nAssassin = 0
  nAmbassador = 0
  nCaptain = 0
  nContessa = 0
  // Latches, so a half-pressed confirm or challenge cannot survive into the
  // next game. Each mask clears all ten seats at once.
  wArmMask = 0
  spaceArmMask = 0
  sArmMask = 0
  // Same reasoning as the activity log: fill (never clear()) so every
  // seat-indexed coins[i] read stays in bounds from the first tick, and so a
  // reset seat's stale coin count cannot leak into seatPacked before the next
  // dealSeat.
  coins.fill(0)
  activityLog.fill("")
  boardDirty = true
}

chip startGame() {
  // Validate BEFORE destroying, so an out-of-range attempt never wipes ready
  // flags.
  let n = seatedNow
  if n < 3 || n > 10 { return }
  resetState()
  playingMask = hereMask
  let copies = deckCopies(n)
  deckBuild(deck, copies)
  nDuke = copies
  nAssassin = copies
  nAmbassador = copies
  nCaptain = copies
  nContessa = copies
  dealCards()
  turnSeat = nextAliveSeat(0)
  phase = PH_TURN
  logLine("Game start with ${n} players")
  boardDirty = true
}

mod maybeStart() {
  if BitCount(readyMask) == seatedNow && seatedNow >= 3 { startGame() }
}

// An absent player banks a coin and the turn moves on. Income stops at 10 so
// the forced-coup rule lapses rather than auto-couping a target on their
// behalf.
mod nextTurn() {
  // A deferred turnPending can still land here after the game itself has
  // ended (checkWin and this flag can both be set within the same tick --
  // see resolveChallenge's self-challenge branch). With no survivors,
  // nextAliveSeat((turnSeat+1)%10) just returns that seat unchanged, and if
  // it is unwired the away-skip branch below re-arms turnPending -- so an
  // unguarded call here walks every seat over the following ticks, each one
  // logging "away - skipped" (overrunning the fixed-size log and burying
  // "No survivors") and crediting income to seats outside playingMask. Bail
  // before any of that -- a fresh game starts turnSeat directly, via
  // startGame's own nextAliveSeat(0), never through here.
  if phase == PH_LOBBY || phase == PH_GAMEOVER { return }
  // The outstanding claim deliberately SURVIVES the turn advance: the next
  // player's selection time is the challenge window. commitSelection clears the
  // previous claim when the next action actually commits.
  selTarget = -1
  selStage = 0
  aimMask = 0
  wArmMask = 0
  turnSeat = nextAliveSeat((turnSeat + 1) % 10)
  // Land the cursor on a legal action from the first tick of the new turn.
  // Income (0) is wrong the instant the forced-coup rule applies -- coins can
  // already be at 10+ here from capped away-turn income accrued before this
  // player reconnected -- and leaving the cursor on Income would arm/confirm
  // straight into commitSelection's affordability backstop with no visible
  // feedback, exactly the "game ignores the player" symptom being fixed.
  // But the forced-coup rule itself lapses when Coup has no legal target
  // (every other living player away or eliminated) -- canAffordAction is the
  // single source of truth for that lapse, so mirror it here rather than
  // re-testing coins alone, or a lone present player at 10+ coins would start
  // their turn wedged on an uncommittable Coup with nothing else selectable.
  selAction = if coins[turnSeat] >= 10 && hasLegalTarget(turnSeat) then ACT_COUP else 0
  if (hereMask & (1 << turnSeat)) == 0 {
    if coins[turnSeat] < 10 { coins[turnSeat] = coins[turnSeat] + 1 }
    logLine("<b>${seatName(turnSeat)}</> is away - turn skipped")
    turnPending = true
  }
  boardDirty = true
}

var loseSeat: int = -1
var loseHi: int = 0
var losePrevPhase: int = 1

// phaseWatchdog debounce: a character port can read null for a single tick
// on death, respawn, or world streaming, and PH_RESPOND/PH_LOSE/PH_EXCHANGE
// each wait on exactly one seat, so acting on the very first absent tick
// would force-pay an influence, void a claim, or tear down an exchange fan
// over a blink. 180 ticks (3s at 60Hz) comfortably outlasts a respawn while
// still recovering a genuinely disconnected table quickly. Shared across all
// three phases -- only one can be waiting at a time -- and reset to 0 both
// whenever the current wait's seat is present, and explicitly at every site
// that opens a fresh wait (PH_RESPOND/PH_LOSE/PH_EXCHANGE entry), so a count
// built up against one seat's absence can never carry into an unrelated
// seat's wait. Elimination (seatDead) is a settled fact, not transient, and
// is never debounced -- phaseWatchdog acts on it immediately.
let WATCHDOG_ABSENT_TICKS = 180 // 3 seconds at 60 Hz
var watchdogAbsentTicks: int = 0

// The survivor named at game over, or -1 when the last two influence were
// lost simultaneously (a bluffed block costing two influence) and no one is
// left standing.
var winnerSeat: int = -1

mod holdsCard(i: int, role: int) -> bool {
  let liveA = ((lostAMask >> i) & 1) == 0 && handA[i] == role
  let liveB = ((lostBMask >> i) & 1) == 0 && handB[i] == role
  return liveA || liveB
}

// An eliminated seat's coins return to the treasury. Checked once here,
// never at each elimination site: a seat is eliminated exactly when it is
// dead in BOTH lostAMask and lostBMask, which is exactly what seatDead
// already tests, so a single unrolled scan covers every route to
// elimination by construction (loseInfluence's immediate branch,
// loseTwoInfluence, the PH_LOSE confirm arm, and phaseWatchdog's forced
// loss) instead of four separate assignments that could drift out of sync.
// Idempotent -- an already-zeroed dead seat is simply set to 0 again -- so
// calling this on every checkWin() rather than only on a fresh elimination
// costs nothing extra to reason about.
mod clearEliminatedCoins() {
  if seatDead(0, lostAMask, lostBMask) { coins[0] = 0 }
  if seatDead(1, lostAMask, lostBMask) { coins[1] = 0 }
  if seatDead(2, lostAMask, lostBMask) { coins[2] = 0 }
  if seatDead(3, lostAMask, lostBMask) { coins[3] = 0 }
  if seatDead(4, lostAMask, lostBMask) { coins[4] = 0 }
  if seatDead(5, lostAMask, lostBMask) { coins[5] = 0 }
  if seatDead(6, lostAMask, lostBMask) { coins[6] = 0 }
  if seatDead(7, lostAMask, lostBMask) { coins[7] = 0 }
  if seatDead(8, lostAMask, lostBMask) { coins[8] = 0 }
  if seatDead(9, lostAMask, lostBMask) { coins[9] = 0 }
}

mod checkWin() {
  // Runs before the game-over path below, so a final elimination that ends
  // the game still zeroes the eliminated seat's coins before playingMask is
  // read for the last time.
  clearEliminatedCoins()
  let alive = BitCount(playingMask & ~(lostAMask & lostBMask))
  if alive <= 1 {
    phase = PH_GAMEOVER
    readyMask = 0
    if alive == 1 {
      // Exactly one seat is alive, so the first live match nextAliveSeat(0)
      // finds by scanning all ten seats from 0 IS that seat, not merely "a"
      // seat.
      winnerSeat = nextAliveSeat(0)
      logLine("${seatName(winnerSeat)} wins!")
    } else {
      // A bluffed block can cost the same seat two influence at once and take
      // the last two players out together, leaving no survivor at all.
      winnerSeat = -1
      logLine("No survivors - table wipe")
    }
    boardDirty = true
  }
}

// Prompt seat i to give up an influence. With one card left there is no choice
// to make, so it resolves immediately. A second prompt must never open while
// one is already in flight -- that overwrite is what strands the first
// victim's selectingMask bit -- so a call arriving mid-prompt also resolves
// immediately: losing the choice is the correct trade, since a stranded
// prompt kills the whole table and a seat about to lose influence anyway has
// little to gain from picking which card goes.
mod loseInfluence(i: int) {
  let inf = influenceOf(i, lostAMask, lostBMask)
  if inf <= 1 || phase == PH_LOSE {
    if ((lostAMask >> i) & 1) == 0 { lostAMask = lostAMask | (1 << i) } else { lostBMask = lostBMask | (1 << i) }
    // Both arms of the ternary below evaluate (Select gate), so seatName(i)
    // would otherwise inline twice for the identical seat; hoisted once.
    let name = seatName(i)
    logLine(if inf <= 1 then "<b>${name}</> is out" else "<b>${name}</> loses an influence")
    checkWin()
    boardDirty = true
    return
  }
  losePrevPhase = phase
  loseSeat = i
  loseHi = 0
  selectingMask = selectingMask | (1 << i)
  discardingMask = discardingMask | (1 << i)
  phase = PH_LOSE
  // A stale W arm left over from whatever the table was doing before this
  // interrupt must never let the PH_LOSE seat's first press double as a
  // confirm.
  wArmMask = 0
  // Fresh wait, fresh seat: a count built up against whatever seat the
  // watchdog was previously tracking must not carry into this one.
  watchdogAbsentTicks = 0
  boardDirty = true
}

// Two losses for the same seat at once -- a bluffed block costs one
// influence for the lie and a second to the action it never legitimately
// blocked; a target who challenges their own honest Assassin claim costs one
// influence for the failed challenge and a second to the assassination it
// never actually stopped. Elimination either way -- with two influence both
// are revealed, with one the player was already on their last -- so there is
// nothing to choose and PH_LOSE, which tracks a single loss at a time, is
// bypassed entirely.
mod loseTwoInfluence(i: int, reason: string) {
  lostAMask = lostAMask | (1 << i)
  lostBMask = lostBMask | (1 << i)
  logLine("<b>${seatName(i)}</> ${reason}")
  checkWin()
  boardDirty = true
}

// A successful defence: reveal the card, shuffle it back, draw a replacement.
mod revealAndRedraw(i: int, role: int) {
  if ((lostAMask >> i) & 1) == 0 && handA[i] == role {
    deckReturn(deck, role)
    countAdjust(role, 1)
    drawInto(i, false)
    return
  }
  deckReturn(deck, role)
  countAdjust(role, 1)
  drawInto(i, true)
}

mod applyAction(actor: int, act: int, target: int) {
  coins[actor] = coins[actor] - actionCost(act)
  let gain = actionGain(act)
  if act == ACT_STEAL {
    let take = min(2, coins[target])
    coins[target] = coins[target] - take
    coins[actor] = coins[actor] + take
    lastTake = take
  } else {
    coins[actor] = coins[actor] + gain
    lastTake = gain
  }
  if act == ACT_COUP { loseInfluence(target) }
}

let EXCHANGE_TICKS = 600 // 10 seconds at 60 Hz
var exchangeLeft: int = 0
var exchangeSeat: int = -1
var exHi: int = 0
array exCards: int[] = [0, 0, 0, 0]
var exCount: int = 0
// Bit n = index n of exCards is kept in hand; the rest go back to the deck.
var exKeptMask: int = 0
// Number of exCards entries, counting from the front, that are copies still
// sitting in hand (handA[i]/handB[i] are deliberately never cleared when
// copied -- exchangeFinalize overwrites those slots with whatever is kept).
// Only entries at or after this index actually came off the deck; those are
// the only ones safe to return to it if the fan is torn down before
// exchangeFinalize runs (phaseWatchdog's PH_EXCHANGE recovery, and the
// defensive teardown in resolveChallenge). Set once, in resolveExchange, from
// the fan's own live-influence count at draw time -- not recomputed from
// influenceOf later, since influence can change while the fan is open.
var exHandCount: int = 0

// The exchange swap is the one genuinely irreversible act, so challenges must
// land before it happens. This is the only timer in the design.
mod beginExchange(i: int) {
  exchangeSeat = i
  exchangeLeft = EXCHANGE_TICKS
  phase = PH_EXCHANGE
  // Fresh wait, fresh seat: a count built up against whatever seat the
  // watchdog was previously tracking must not carry into this one.
  watchdogAbsentTicks = 0
  // The claimed role (Ambassador) is not named here -- see the Assassinate/
  // Steal/Tax lines for why.
  logLine("<b>${seatName(i)}</> exchanges cards with the deck")
  boardDirty = true
}

mod resolveExchange() {
  let i = exchangeSeat
  if i < 0 { return }
  // The claim survived: draw two, then the player keeps their influence count.
  exCount = 0
  exCards.fill(0)
  if ((lostAMask >> i) & 1) == 0 { exCards[exCount] = handA[i] exCount = exCount + 1 }
  if ((lostBMask >> i) & 1) == 0 { exCards[exCount] = handB[i] exCount = exCount + 1 }
  // Everything below this index is a hand copy, not a deck draw -- capture
  // the boundary now, before the two draws below push exCount past it.
  exHandCount = exCount
  let d1 = deckDraw(deck)
  if d1 != 0 { countAdjust(d1, -1) exCards[exCount] = d1 exCount = exCount + 1 }
  let d2 = deckDraw(deck)
  if d2 != 0 { countAdjust(d2, -1) exCards[exCount] = d2 exCount = exCount + 1 }
  exHi = 0
  // A fresh fan starts with nothing kept. Without this, a bit stranded by a
  // prior abandoned exchange (reset skips exchangeFinalize entirely) would
  // count toward this fan's BitCount(exKeptMask) == influence check even
  // though it was never among firstKept/secondKept -- a duplicated card.
  exKeptMask = 0
  selectingMask = selectingMask | (1 << i)
  // Defensive: discardingMask must never be set for an exchanging seat (the
  // render table has no entry for selecting+discarding meaning anything but
  // the lose-influence prompt), so it is forced clear here rather than
  // trusted to already be 0.
  discardingMask = discardingMask & ~(1 << i)
  // The countdown WAS the challenge window, and it just expired unchallenged:
  // the Ambassador claim is settled. Clear it exactly as commitSelection does
  // when a new action supersedes the previous claim, so tapKey's retroactive
  // challenge (which bails on pendKind == 0) can no longer reach the fan.
  pendKind = 0
  pendCard = 0
  blockSeat = -1
  // The claim just settled unchallenged: any half-armed challenge/block latch
  // was aimed at it and must not survive to fire against whatever comes next.
  spaceArmMask = 0
  sArmMask = 0
  boardDirty = true
}

mod exchangeTick() {
  if exchangeLeft > 0 {
    exchangeLeft = exchangeLeft - 1
    if exchangeLeft == 0 { resolveExchange() }
  }
}

// The player has kept exactly as many cards as they have influence. Write the
// kept cards back into their live slots, return everything else to the deck,
// and hand play back to the table. There are no loops, so exCards (at most 4
// entries) is unrolled throughout.
mod exchangeFinalize() {
  let i = exchangeSeat
  let liveA = ((lostAMask >> i) & 1) == 0
  let liveB = ((lostBMask >> i) & 1) == 0

  // Locate the kept cards in fan order.
  var firstKept: int = -1
  var secondKept: int = -1
  if exCount > 0 && (exKeptMask & 1) != 0 {
    if firstKept < 0 { firstKept = 0 } else { secondKept = 0 }
  }
  if exCount > 1 && (exKeptMask & 2) != 0 {
    if firstKept < 0 { firstKept = 1 } else { secondKept = 1 }
  }
  if exCount > 2 && (exKeptMask & 4) != 0 {
    if firstKept < 0 { firstKept = 2 } else { secondKept = 2 }
  }
  if exCount > 3 && (exKeptMask & 8) != 0 {
    if firstKept < 0 { firstKept = 3 } else { secondKept = 3 }
  }

  // Write kept cards into live slots only, first live slot first. A revealed
  // (lost) slot must never be resurrected.
  if firstKept >= 0 {
    if liveA { handA[i] = exCards[firstKept] } else if liveB { handB[i] = exCards[firstKept] }
  }
  if secondKept >= 0 && liveB { handB[i] = exCards[secondKept] }

  // Return everything not kept to the deck, keeping the published per-role
  // counters in sync with the real deck.
  if exCount > 0 && (exKeptMask & 1) == 0 { deckReturn(deck, exCards[0]) countAdjust(exCards[0], 1) }
  if exCount > 1 && (exKeptMask & 2) == 0 { deckReturn(deck, exCards[1]) countAdjust(exCards[1], 1) }
  if exCount > 2 && (exKeptMask & 4) == 0 { deckReturn(deck, exCards[2]) countAdjust(exCards[2], 1) }
  if exCount > 3 && (exKeptMask & 8) == 0 { deckReturn(deck, exCards[3]) countAdjust(exCards[3], 1) }

  // Otherwise the exchange completes invisibly -- no line ever announced it
  // finished. Which cards were kept stays private (that secrecy is the whole
  // point of the Ambassador), so this only announces that it happened.
  logLine("<b>${seatName(i)}</> finishes the exchange")
  // discardingMask never gets set for an exchange, but it is cleared here
  // anyway, in lockstep with selectingMask -- the two masks are meant to
  // move together at every clear site, not just the PH_LOSE ones.
  selectingMask = selectingMask & ~(1 << i)
  discardingMask = discardingMask & ~(1 << i)
  exKeptMask = 0
  exchangeSeat = -1
  exCount = 0
  exHandCount = 0
  exHi = 0
  phase = PH_TURN
  turnPending = true
  boardDirty = true
}

mod commitSelection(i: int) {
  let act = selAction
  let targeted = actionTargeted(act)
  let targetable = hasLegalTarget(i)
  let myCoins = coins[i]
  // Afford/target check first, before ever opening (or re-entering) the
  // target-selection stage below: selAction should already be kept legal by
  // stepAction/nextTurn (both now route through canAffordAction, which
  // itself requires a legal target for any targeted action), so this is a
  // defensive backstop against stale state -- but a load-bearing one, since
  // without it a targeted action whose only target vanished between picks
  // would fall into the stage-0-to-1 transition below and open an empty,
  // uncommittable target fan.
  if !canAffordAction(act, myCoins, targetable) { return }
  // A targeted action needs a actorName chosen first.
  if targeted && selStage == 0 {
    selStage = 1
    selTarget = nextTargetSeat((i + 1) % 10, i)
    aimMask = 1 << selTarget
    boardDirty = true
    return
  }
  // The actorName was picked earlier -- possibly several ticks ago -- and a
  // challenge resolving in between can have eliminated it, or its player can
  // have gone away, since. Re-validate before spending anything: a confirm
  // against a now-illegal actorName must not burn coins into loseInfluence's
  // silent no-op on an already-lost or unanswerable seat. Re-scan for a fresh
  // actorName and stay in the actorName stage rather than committing, the same way
  // the initial stage-0-to-1 pick above already works -- the player presses
  // W again to confirm the corrected actorName. canAffordAction above already
  // guarantees at least one legal target exists somewhere, so this re-scan is
  // guaranteed to land on one -- it only ever needs to skip past the one
  // specific seat that stopped being legal.
  let targetMask = playingMask & ~(lostAMask & lostBMask) & hereMask
  if targeted && selStage == 1 && !canTargetSeat(selTarget, i, targetMask) {
    selTarget = nextTargetSeat((i + 1) % 10, i)
    aimMask = 1 << selTarget
    boardDirty = true
    return
  }

  // The previous claim is now locked in and can no longer be challenged.
  pendKind = 0
  blockSeat = -1
  // The outstanding claim just changed: a half-armed challenge or block latch
  // was aimed at whatever claim existed before (or at nothing), and must not
  // silently resolve against whatever claim comes next. This only disarms --
  // it never reassigns seat ownership.
  spaceArmMask = 0
  sArmMask = 0
  let actorName = seatName(i)

  if act == ACT_ASSASSINATE {
    coins[i] = coins[i] - actionCost(act)
    pendKind = act
    pendSeat = i
    pendTarget = selTarget
    pendCard = actionClaim(act)
    pendCoins = 0
    phase = PH_RESPOND
    // Fresh wait, fresh seat: a count built up against whatever seat the
    // watchdog was previously tracking must not carry into this one.
    watchdogAbsentTicks = 0
    // The claimed role (Assassin) is not named here -- it is a challengeable
    // claim, not part of the verb, and the banner/challenge prompt already
    // name it for anyone deciding whether to challenge.
    logLine("<b>${actorName}</> assassinates <b>${seatName(selTarget)}</>")
    boardDirty = true
    return
  }
  // Steal is targeted and blockable (Captain or Ambassador), so it pauses in
  // PH_RESPOND exactly like Assassinate -- the victim must answer Block/Allow
  // before the turn advances, rather than the old retroactive S/Space window
  // that a next-in-order victim could close on themselves by committing their
  // own action first. The coin transfer happens now, at commit, via the same
  // applyAction path every non-paused action uses; a successful block undoes
  // it (blockClaim), a bluffed block re-applies it (resolveChallenge), and a
  // direct challenge against this live claim leaves it untouched either way
  // (already correct once moved, nothing further to do).
  if act == ACT_STEAL {
    applyAction(i, act, selTarget)
    pendKind = act
    pendSeat = i
    pendTarget = selTarget
    pendCard = actionClaim(act)
    pendCoins = lastTake
    phase = PH_RESPOND
    // Fresh wait, fresh seat: a count built up against whatever seat the
    // watchdog was previously tracking must not carry into this one.
    watchdogAbsentTicks = 0
    var coinWord: string = "coins"
    if pendCoins == 1 { coinWord = "coin" }
    // Same reasoning as Assassinate's line -- the claimed role lives in the
    // banner/challenge prompt, not here.
    logLine("<b>${actorName}</> steals ${pendCoins} ${coinWord} from <b>${seatName(selTarget)}</>")
    boardDirty = true
    return
  }
  if act == ACT_EXCHANGE {
    pendKind = act
    pendSeat = i
    pendTarget = -1
    pendCard = actionClaim(act)
    pendCoins = 0
    beginExchange(i)
    return
  }

  applyAction(i, act, selTarget)
  pendKind = act
  pendSeat = i
  pendTarget = selTarget
  pendCard = actionClaim(act)
  pendCoins = lastTake
  // Steal and Assassinate both return early above, before this point -- each
  // pauses in PH_RESPOND with its own bespoke claim line. Every other action
  // (Income, Foreign Aid, Tax, Coup -- today's full remaining set) falls
  // through here, so each gets its own sentence-shaped line instead of a
  // terse "actor ACTION" fragment ("X Income"). pendName is only used by the
  // Coup line (the only one of the four that is targeted), but is computed
  // unconditionally the same way the rest of this mod already does for
  // pendTarget-derived values.
  let pendName = seatName(pendTarget)
  var line: string = "<b>${actorName}</> ${actionName(act)}"
  if act == ACT_INCOME { line = "<b>${actorName}</> takes Income (+1 coin)" } else if act == ACT_FOREIGN_AID { line = "<b>${actorName}</> takes Foreign Aid (+2 coins)" }
  // The claimed role (Duke) is not named here -- see the Assassinate/Steal
  // lines above for why.
    else if act == ACT_TAX { line = "<b>${actorName}</> takes Tax (+3 coins)" } else if act == ACT_COUP { line = "<b>${actorName}</> coups <b>${pendName}</>" }
  logLine(line)
  turnPending = true
  boardDirty = true
}

// Space,Space from any living player who is not the claimant.
mod resolveChallenge(challenger: int) {
  let claimant = if blockSeat >= 0 then blockSeat else pendSeat
  let role = pendCard
  // A Steal block claims "a card that blocks stealing", which is true of
  // either Captain or Ambassador -- the outcome under challenge is identical
  // either way, so the defence succeeds if the blocker holds either one, and
  // whichever they actually hold is what gets revealed.
  let isStealBlock = blockSeat >= 0 && pendKind == ACT_STEAL
  var defends: bool = holdsCard(claimant, role)
  var revealRole: int = role
  if isStealBlock {
    let hasCaptain = holdsCard(claimant, CARD_CAPTAIN)
    let hasAmbassador = holdsCard(claimant, CARD_AMBASSADOR)
    defends = hasCaptain || hasAmbassador
    if hasCaptain { revealRole = CARD_CAPTAIN } else if hasAmbassador { revealRole = CARD_AMBASSADOR }
  }
  if defends {
    // Name the revealed card (public information in Coup, and specifically
    // how the table tells a Captain block from an Ambassador one) and say
    // what the challenger loses, instead of a bare "loses". The replacement
    // itself must stay hidden -- revealAndRedraw shuffles the revealed card
    // back and draws a new one -- but that a redraw happens is itself public
    // knowledge, so name the process even though its result stays secret.
    logLine("<b>${seatName(claimant)}</> reveals ${cardText(revealRole)}, shuffles it back and draws a new card - <b>${seatName(challenger)}</> loses an influence")
    revealAndRedraw(claimant, revealRole)
    // Capture before any reset below: the branch dispatch just beneath (T33's
    // Assassinate rule vs. a Steal's own outcome) needs to know which action
    // was live, and whether this challenge was against an outstanding block
    // (blockSeat >= 0) rather than the original claim -- both booleans read
    // state that the settle logic below is about to clear.
    let respondedKind = pendKind
    let wasBlockChallenge = blockSeat >= 0
    blockSeat = -1
    // A direct challenge against a live PH_RESPOND claim that fails costs the
    // challenger a card for the failed challenge, but does NOT also cancel
    // the action -- real Coup still resolves it, which is exactly why
    // Allow/Accept is worth pressing over Challenge. Settle it here, the same
    // way allowClaim/acceptBlock do when the claimant simply lets it stand.
    if phase == PH_RESPOND && !wasBlockChallenge {
      let respondTarget = pendTarget
      if respondedKind == ACT_ASSASSINATE {
        // A failed challenge only proves the Assassin claim was genuine --
        // it does NOT also settle the target's Contessa block, which is a
        // separate decision the target has not made yet. Real Coup lets the
        // assassination proceed to the block step, not past it. The one
        // exception is the target challenging their own claim: that IS their
        // response, so failing it forfeits the block outright and both
        // losses land on the same seat, same shape as a bluffed block.
        if respondTarget == challenger {
          // The claimant challenged their own honest Assassin claim: one loss
          // for the failed challenge, one for the assassination it didn't
          // stop, both on the same seat. loseTwoInfluence already models
          // exactly this "two losses always eliminate" case, bypassing
          // PH_LOSE's single-choice prompt the same way a bluffed block does.
          pendKind = 0
          phase = PH_TURN
          turnPending = true
          loseTwoInfluence(challenger, "failed the challenge and is out")
        } else {
          // A third party challenged: only the failed challenger loses
          // influence. The target never got a turn to answer, so their
          // Block/Allow prompt must survive exactly as if no one had
          // challenged -- phase (still PH_RESPOND) and pendKind (still
          // ACT_ASSASSINATE, so blockClaim/allowClaim keep working) both
          // stay put. Same shape as the Steal case below: the claim itself
          // is now vindicated and must not be challengeable a second time,
          // so pendCard is cleared instead -- canDeclareChallenge keys on
          // pendCard != 0, and blockClaim recomputes pendCard from pendKind
          // regardless of its current value, so this does not disturb
          // Block. If the challenger's own loss opens a PH_LOSE prompt (2+
          // influence), losePrevPhase captures PH_RESPOND (phase is left
          // untouched here), so PH_LOSE hands control straight back to the
          // target's still-live Block/Allow prompt once it resolves.
          loseInfluence(challenger)
          pendCard = 0
        }
      } else {
        // A Steal's own effect is a coin transfer, not an influence loss, and
        // it already moved at commit -- it simply stands once the claim
        // proves genuine. Only the failed challenger loses influence.
        // Unlike Assassinate, a failed Steal challenge never forfeits the
        // target's Block/Allow decision -- even when the target is the one
        // who challenged and lost. They pay one influence for the bad
        // challenge, but the coins are still theirs to fight for, so this
        // collapses to the third-party shape unconditionally: phase and
        // pendKind (blockClaim/allowClaim still need to know this is a
        // Steal) both stay put. The claim itself is now vindicated and must
        // not be challengeable a second time, so pendCard is cleared instead
        // -- canDeclareChallenge keys on pendCard != 0, and blockClaim
        // recomputes pendCard from pendKind regardless of its current value,
        // so this does not disturb Block. If the challenger's own loss opens
        // a PH_LOSE prompt (2+ influence, same seat as the target when they
        // challenged their own claim), losePrevPhase captures PH_RESPOND
        // (phase is left untouched here), so PH_LOSE hands control straight
        // back to this same seat's still-live Block/Allow prompt once it
        // resolves.
        loseInfluence(challenger)
        pendCard = 0
      }
    } else {
      // Either genuinely outside PH_RESPOND already (a retroactive Foreign
      // Aid block challenged well after that block itself already settled,
      // or after the block turns out to be the claim under fire once the
      // actor's own challenge window has fully lapsed) or -- the new case --
      // a challenge against an outstanding block (wasBlockChallenge) while
      // still in PH_RESPOND: either way the claim is now fully vindicated
      // and there is nothing further to wait on, so settle it completely and
      // hand play back to the table. Order matters: phase/turnPending are
      // set BEFORE loseInfluence(challenger) runs, so if that loss opens a
      // PH_LOSE prompt, losePrevPhase captures PH_TURN (the correct place to
      // land once PH_LOSE resolves) rather than the now-stale PH_RESPOND.
      // Clear pendCard alongside pendKind -- otherwise bannerText's
      // pendCard == 0 guard fails and keeps advertising the now-settled claim
      // until the next action commits.
      pendKind = 0
      pendCard = 0
      if phase == PH_RESPOND { phase = PH_TURN turnPending = true }
      loseInfluence(challenger)
    }
  } else {
    logLine("<b>${seatName(claimant)}</> was bluffing - <b>${seatName(challenger)}</> called it correctly")
    // Capture before blockSeat/pendKind are reset below: a bluffed Contessa
    // block on an assassination costs the blocker a second influence for the
    // assassination it never legitimately blocked.
    let wasAssassinBlock = blockSeat >= 0 && pendKind == ACT_ASSASSINATE
    // The claim is defeated, so the prompt or countdown it was gating must be
    // torn down. Otherwise losePrevPhase restores PH_RESPOND and the target is
    // still asked to answer a claim that no longer exists, and a challenged
    // Ambassador still receives the exchange.
    if phase == PH_RESPOND || phase == PH_EXCHANGE {
      // Defensive only -- NOT actually reachable with exCount > 0. A
      // challenge only ever reaches resolveChallenge while pendKind is still
      // nonzero (tapKey's space handler bails immediately once it is 0), and
      // resolveExchange zeroes pendKind/pendCard in the very same synchronous
      // call that builds the fan -- both happen within one tick, before any
      // later tick's dequeue can observe them apart. The input queue is also
      // dequeued ahead of exchangeTick every tick, so a challenge landing
      // during the countdown always finds exCount == 0 here (still counting
      // down makes this whole block inert), and a challenge that could ever
      // see the drawn fan can never be dequeued at all, because pendKind is
      // already 0 by the time one exists. Kept as a backstop in case that
      // ordering ever changes, and kept correct: only entries at or after
      // exHandCount actually came off the deck (the rest are copies still
      // sitting in hand, per resolveExchange), same guard as phaseWatchdog's
      // identical PH_EXCHANGE teardown below. Unrolled exactly like
      // exchangeFinalize -- no loops -- and each exCards[n] read is a
      // statement-if, never a ternary/Select, so it is never evaluated once
      // n >= exCount.
      if exCount > 0 && exHandCount <= 0 { deckReturn(deck, exCards[0]) countAdjust(exCards[0], 1) }
      if exCount > 1 && exHandCount <= 1 { deckReturn(deck, exCards[1]) countAdjust(exCards[1], 1) }
      if exCount > 2 && exHandCount <= 2 { deckReturn(deck, exCards[2]) countAdjust(exCards[2], 1) }
      if exCount > 3 && exHandCount <= 3 { deckReturn(deck, exCards[3]) countAdjust(exCards[3], 1) }
      // Guarded exactly like phaseWatchdog's identical PH_EXCHANGE teardown
      // below -- exchangeSeat is -1 whenever this fires for a plain
      // PH_RESPOND claim (no exchange in flight), and shifting by a negative
      // seat index is undefined. discardingMask is cleared in the same
      // breath as selectingMask -- the two masks always move together, and
      // this is the one clear site that used to touch only one of them.
      if exchangeSeat >= 0 && exchangeSeat < 10 {
        selectingMask = selectingMask & ~(1 << exchangeSeat)
        discardingMask = discardingMask & ~(1 << exchangeSeat)
      }
      exKeptMask = 0
      exCount = 0
      exHandCount = 0
      exHi = 0
      exchangeLeft = 0
      exchangeSeat = -1
      phase = PH_TURN
      turnPending = true
    }
    if blockSeat >= 0 {
      // The block was a lie: undo it and let the original action stand. A
      // Steal moved coins on both sides when it originally applied, so
      // re-applying it here must also move both sides back -- symmetric with
      // the direct-challenge branch below, just in the opposite direction.
      blockSeat = -1
      coins[pendSeat] = coins[pendSeat] + pendCoins
      if pendKind == ACT_STEAL && pendTarget >= 0 {
        coins[pendTarget] = coins[pendTarget] - pendCoins
      }
    } else {
      coins[pendSeat] = coins[pendSeat] - pendCoins
      if pendKind == ACT_STEAL && pendTarget >= 0 {
        coins[pendTarget] = coins[pendTarget] + pendCoins
      }
    }
    pendKind = 0
    if wasAssassinBlock {
      loseTwoInfluence(claimant, "bluffed the block and is out")
    } else {
      loseInfluence(claimant)
    }
  }
  // The claim (challenge or block) just settled: any half-armed challenge or
  // block latch, from this seat or any other, was aimed at it and must not
  // survive to fire against whatever comes next.
  spaceArmMask = 0
  sArmMask = 0
  boardDirty = true
}

// The target blocks the outstanding PH_RESPOND claim -- Contessa for an
// Assassinate, Captain/Ambassador for a Steal (resolveChallenge's
// isStealBlock already defends either). This converts the action into an
// ordinary deferred block claim owned by the blocker, which may itself be
// challenged before the next action -- same machinery either way.
mod blockClaim(i: int) {
  blockSeat = i
  pendCard = actionBlocker(pendKind)
  // Deliberately stays in PH_RESPOND rather than advancing to PH_TURN: a
  // block is itself a public claim, so the actor now gets the same
  // synchronous challenge-or-accept step the target just had --
  // respondWaitSeat() switches to pendSeat the instant blockSeat is set, and
  // acceptBlock/resolveChallenge/phaseWatchdog are what finally hand the
  // turn back.
  spaceArmMask = 0
  sArmMask = 0
  // A Steal already moved real coins when it applied at commit; the block
  // claims they were never owed, so reverse them here -- for Steal that means
  // paying the target back, not just debiting the actor. Same pattern as
  // declareBlock's own retroactive Foreign Aid path. Assassinate never moves
  // coins on commit (pendCoins is 0), so this is a no-op for it.
  coins[pendSeat] = coins[pendSeat] - pendCoins
  if pendKind == ACT_STEAL && pendTarget >= 0 {
    coins[pendTarget] = coins[pendTarget] + pendCoins
  }
  // Same seat in both branches -- hoisted once rather than inlined per
  // branch.
  let name = seatName(i)
  if pendKind == ACT_STEAL {
    logLine("<b>${name}</> blocks the steal (claims Captain or Ambassador)")
  } else {
    logLine("<b>${name}</> blocks the assassination (claims Contessa)")
  }
  // Fresh wait, fresh seat: watchdog recovery now tracks the actor
  // (respondWaitSeat), not whatever count it had built up against the
  // target.
  watchdogAbsentTicks = 0
  boardDirty = true
}

// The target allows the outstanding PH_RESPOND claim to stand. For an
// Assassinate the lost influence can never be un-lost; for a Steal the coins
// already moved at commit and simply stand. Either way there is nothing left
// to challenge.
mod allowClaim(i: int) {
  let wasAssassinate = pendKind == ACT_ASSASSINATE
  phase = PH_TURN
  // Allowing the claim consumes it. Settle it exactly like resolveExchange
  // does when its countdown expires unchallenged, before a victim's
  // loseInfluence prompt (Assassinate only) opens.
  pendKind = 0
  pendCard = 0
  blockSeat = -1
  // The claim just settled unchallenged: any half-armed challenge/block latch
  // was aimed at it and must not survive to fire against whatever comes next.
  spaceArmMask = 0
  sArmMask = 0
  // Same seat in both branches -- hoisted once rather than inlined per
  // branch.
  let name = seatName(i)
  if wasAssassinate {
    logLine("<b>${name}</> allows the assassination")
  } else {
    logLine("<b>${name}</> allows the steal")
  }
  if wasAssassinate { loseInfluence(i) }
  turnPending = true
  boardDirty = true
}

// The actor accepts the outstanding block (respondWaitSeat's post-block
// wait): nothing further to challenge, so the block simply stands as
// declared and play returns to the table. blockClaim/declareBlock already
// reversed whatever coins the blocked action had moved (a Steal or Foreign
// Aid; Assassinate never moves coins), so there is nothing left to undo
// here -- unlike allowClaim, accepting a block never costs influence.
mod acceptBlock(i: int) {
  phase = PH_TURN
  pendKind = 0
  pendCard = 0
  blockSeat = -1
  spaceArmMask = 0
  sArmMask = 0
  logLine("<b>${seatName(i)}</> accepts the block")
  turnPending = true
  boardDirty = true
}

// Whether seat i may right now declare a block on the outstanding claim.
// Foreign Aid is blockable by any other living player. Assassinate and Steal
// are both deliberately excluded -- they keep their own synchronous
// PH_RESPOND prompt (blockClaim/allowClaim) and must never be reachable
// through this retroactive path. A claim that is already blocked cannot be
// blocked again. Also excluded: the turn-taker's own S while they are mid
// target selection (selStage == 1) -- there, S is "back" and that control
// must win over a same-key retroactive block on someone else's still-live
// Foreign Aid, rather than racing it on key-press order in tapKey. Gating it
// here (not just in tapKey) keeps blockLineText's prompt line in sync for
// free: the "S to Block" hint disappears exactly when S stops meaning block,
// so it and "S back" never both show at once.
mod canDeclareBlock(i: int) -> bool {
  if (playingMask & (1 << i)) == 0 { return false }
  if seatDead(i, lostAMask, lostBMask) { return false }
  if pendKind != ACT_FOREIGN_AID { return false }
  if blockSeat >= 0 { return false }
  if i == pendSeat { return false }
  if phase == PH_TURN && i == turnSeat && selStage == 1 { return false }
  return true
}

// Whether seat i may right now retroactively challenge the outstanding claim.
// Same liveness guards as canDeclareBlock -- a dead or non-playing seat has
// no challenge to make -- plus the claimant can never challenge their own
// claim (or their own block).
mod canDeclareChallenge(i: int) -> bool {
  if (playingMask & (1 << i)) == 0 { return false }
  if seatDead(i, lostAMask, lostBMask) { return false }
  if pendKind == 0 || pendCard == 0 { return false }
  let claimant = if blockSeat >= 0 then blockSeat else pendSeat
  if i == claimant { return false }
  return true
}

// Any other living player blocks Foreign Aid -- the only action left on this
// retroactive path now that Assassinate and Steal both pause synchronously in
// PH_RESPOND (blockClaim) instead. This converts the outstanding claim into a
// block claim owned by the blocker, exactly like blockClaim, so the existing
// challenge machinery (resolveChallenge) understands it. Unlike blockClaim,
// pendCoins here is only ever the actor's own Foreign Aid gain -- Foreign Aid
// has no target -- and resolveChallenge's "block was a lie" branch needs that
// exact amount to restore the original action if this block is itself
// successfully challenged.
mod declareBlock(i: int) {
  if !canDeclareBlock(i) { return }
  let role = actionBlocker(pendKind)
  if role == 0 { return }

  blockSeat = i
  pendCard = role
  // This repoints the outstanding claim (blockSeat/pendCard) without writing
  // pendKind -- pendKind stays ACT_FOREIGN_AID both before and after -- so
  // any half-armed challenge/block latch was aimed at the pre-block claim and
  // must not silently resolve against this new block.
  spaceArmMask = 0
  sArmMask = 0
  // Reverse the coins Foreign Aid already moved when it applied.
  coins[pendSeat] = coins[pendSeat] - pendCoins
  logLine("<b>${seatName(i)}</> blocks the ${actionName(pendKind)} (claims ${cardText(role)})")
  // Same symmetry as blockClaim: this retroactive block is also a public
  // claim, so the actor now gets a synchronous challenge-or-accept step
  // (respondWaitSeat() -> pendSeat) before the table moves on, rather than
  // only the easy-to-miss retroactive Space window everyone else already
  // had.
  phase = PH_RESPOND
  watchdogAbsentTicks = 0
  boardDirty = true
}

// Whichever seat the outstanding PH_RESPOND claim is currently waiting on: the
// target, until they declare a Block (blockClaim/declareBlock set blockSeat
// but deliberately stay in, or move into, PH_RESPOND rather than handing off
// to PH_TURN) -- then the actor, who must challenge or accept that block
// before the turn can advance. Single source of truth for "whose turn is it
// to answer", shared by tapKey's PH_RESPOND dispatch, promptText, bannerText
// and phaseWatchdog's PH_RESPOND recovery, rather than each re-deriving the
// same blockSeat >= 0 test.
mod respondWaitSeat() -> int {
  return if blockSeat >= 0 then pendSeat else pendTarget
}

// General recovery for a class of freeze: PH_RESPOND, PH_LOSE and PH_EXCHANGE
// each wait synchronously on exactly one seat (pendTarget, loseSeat,
// exchangeSeat). If that seat becomes invalid -- eliminated, or simply gone
// because a player disconnected mid-prompt -- no other seat's tapKey branch
// can ever match again and the table freezes for good. Called every tick
// before the queue is dequeued, so a freshly-cleared phase is what the
// dequeue sees rather than spending this tick's input against a dead prompt.
mod phaseWatchdog() {
  if phase == PH_RESPOND {
    // Elimination (or a malformed seat index) is a settled fact -- act on it
    // immediately, same tick. Mere absence is not: it can be a single-tick
    // null read on death/respawn/streaming, so it only counts once it has
    // held for WATCHDOG_ABSENT_TICKS in a row. respondWaitSeat() is whoever
    // is currently being waited on -- the target before a block, the actor
    // once one is declared -- so this same recovery covers both without
    // knowing which case it is.
    let waitSeat = respondWaitSeat()
    var respondGone: bool = waitSeat < 0 || waitSeat >= 10
    if !respondGone { respondGone = seatDead(waitSeat, lostAMask, lostBMask) }
    var respondAway: bool = !respondGone && (hereMask & (1 << waitSeat)) == 0
    if respondAway { watchdogAbsentTicks = watchdogAbsentTicks + 1 } else { watchdogAbsentTicks = 0 }
    var respondStuck: bool = respondGone
      || (respondAway && watchdogAbsentTicks >= WATCHDOG_ABSENT_TICKS)
    if respondStuck {
      // No one is left to answer -- Block/Allow if the target vanished, or
      // Challenge/Accept if the actor did once a block was outstanding --
      // settle the claim exactly like allowClaim/acceptBlock would and hand
      // play back to the table. Coin-neutral either way: Assassinate never
      // moved coins, and a Steal's coins (or a blocked Foreign Aid's) already
      // sit wherever the last successful step left them, same as an
      // Allow/Accept. Log it: without this the claim just silently stops
      // being challengeable with no explanation on screen. waitSeat can be
      // out of range here (the respondGone branch also covers a malformed
      // index), so only name the seat when it is actually valid.
      if waitSeat >= 0 && waitSeat < 10 {
        logLine("<b>${seatName(waitSeat)}</> can't answer - claim stands unchallenged")
      } else {
        logLine("Claim stands unchallenged - no one left to answer")
      }
      pendKind = 0
      pendCard = 0
      blockSeat = -1
      // The claim just settled unanswered: any half-armed challenge/block
      // latch was aimed at it and must not survive to fire against whatever
      // comes next.
      spaceArmMask = 0
      sArmMask = 0
      phase = PH_TURN
      turnPending = true
      boardDirty = true
    }
  }
  if phase == PH_LOSE {
    var loseGone: bool = loseSeat < 0 || loseSeat >= 10
    if !loseGone { loseGone = seatDead(loseSeat, lostAMask, lostBMask) }
    var loseAway: bool = !loseGone && (hereMask & (1 << loseSeat)) == 0
    if loseAway { watchdogAbsentTicks = watchdogAbsentTicks + 1 } else { watchdogAbsentTicks = 0 }
    var loseStuck: bool = loseGone || (loseAway && watchdogAbsentTicks >= WATCHDOG_ABSENT_TICKS)
    if loseStuck {
      // The influence must still be paid even though the seat cannot choose:
      // reveal its first still-live slot, same order as loseInfluence's own
      // immediate branch. Log which card, same reasoning as the reveal log
      // in resolveChallenge -- otherwise a disconnected player's card just
      // flips face-up with no explanation.
      if loseSeat >= 0 && loseSeat < 10 {
        // Statement-if, never a ternary, around this conditional array index.
        var revealed: int = handA[loseSeat]
        if ((lostAMask >> loseSeat) & 1) == 0 {
          lostAMask = lostAMask | (1 << loseSeat)
        } else {
          revealed = handB[loseSeat]
          lostBMask = lostBMask | (1 << loseSeat)
        }
        selectingMask = selectingMask & ~(1 << loseSeat)
        discardingMask = discardingMask & ~(1 << loseSeat)
        logLine("<b>${seatName(loseSeat)}</> disconnected - ${cardText(revealed)} forced face-up")
      }
      loseSeat = -1
      // The watchdog is forcing an exit from PH_LOSE, same as a normal W,W
      // confirm would -- so it must leave the W latch disarmed too.
      wArmMask = 0
      // This counter is at or past WATCHDOG_ABSENT_TICKS -- that is exactly
      // why this branch fired. Left alone it carries straight into whatever
      // phase is restored next (PH_RESPOND or PH_EXCHANGE), tripping that
      // wait's own watchdog on its very first absent tick instead of
      // absorbing a single-tick blink the same way a fresh wait would.
      watchdogAbsentTicks = 0
      // Restore the prior phase BEFORE checkWin(), mirroring tapKey's own
      // PH_LOSE confirm handler -- so a game-ending elimination can override
      // back to PH_GAMEOVER instead of being clobbered by the restore.
      phase = losePrevPhase
      checkWin()
      boardDirty = true
    }
  }
  if phase == PH_EXCHANGE {
    var exGone: bool = exchangeSeat < 0 || exchangeSeat >= 10
    if !exGone { exGone = seatDead(exchangeSeat, lostAMask, lostBMask) }
    var exAway: bool = !exGone && (hereMask & (1 << exchangeSeat)) == 0
    if exAway { watchdogAbsentTicks = watchdogAbsentTicks + 1 } else { watchdogAbsentTicks = 0 }
    var exStuck: bool = exGone || (exAway && watchdogAbsentTicks >= WATCHDOG_ABSENT_TICKS)
    if exStuck {
      // Return only the cards that actually came off the deck -- entries at
      // or after exHandCount. Entries before it are copies still sitting in
      // hand (handA[i]/handB[i] were never cleared when the fan was built;
      // exchangeFinalize is what overwrites them, and it never runs on this
      // path), so returning those too would create a duplicate: one copy
      // still in hand, a second one now back in the deck. Keeps the per-role
      // counters and the real deck in sync, exactly like resolveChallenge's
      // own mid-exchange-challenge cleanup. Unrolled -- no loops -- each
      // exCards[n] read stays behind a statement-if so it is never evaluated
      // once n >= exCount.
      if exCount > 0 && exHandCount <= 0 { deckReturn(deck, exCards[0]) countAdjust(exCards[0], 1) }
      if exCount > 1 && exHandCount <= 1 { deckReturn(deck, exCards[1]) countAdjust(exCards[1], 1) }
      if exCount > 2 && exHandCount <= 2 { deckReturn(deck, exCards[2]) countAdjust(exCards[2], 1) }
      if exCount > 3 && exHandCount <= 3 { deckReturn(deck, exCards[3]) countAdjust(exCards[3], 1) }
      if exchangeSeat >= 0 && exchangeSeat < 10 {
        selectingMask = selectingMask & ~(1 << exchangeSeat)
        discardingMask = discardingMask & ~(1 << exchangeSeat)
        // Otherwise the exchange just vanishes with no explanation, same
        // reasoning as the other two watchdog branches above.
        logLine("<b>${seatName(exchangeSeat)}</> disconnected - exchange cancelled")
      }
      exKeptMask = 0
      exCount = 0
      exHandCount = 0
      exHi = 0
      exchangeLeft = 0
      exchangeSeat = -1
      // The Ambassador claim itself must settle here too, same as every
      // other pendKind write site -- otherwise it stays retroactively
      // challengeable via tapKey's space-space path after the claimant is
      // long gone.
      pendKind = 0
      pendCard = 0
      blockSeat = -1
      spaceArmMask = 0
      sArmMask = 0
      phase = PH_TURN
      turnPending = true
      boardDirty = true
    }
  }
  if phase == PH_TURN {
    // turnSeat is a fourth synchronous wait, exactly like pendTarget/loseSeat/
    // exchangeSeat above: tapKey's PH_TURN arm also requires i == turnSeat, so
    // a dead or permanently-absent turnSeat freezes the table the same way.
    // This is the case the reported soft lock fell through: a retroactive
    // challenge (available in any phase, including a player's own turn) can
    // eliminate the challenger outright via loseInfluence's immediate branch
    // with no PH_LOSE prompt to recover from, leaving phase == PH_TURN and
    // turnSeat pointed at a dead seat that tapKey's liveness guard rejects
    // forever. Keying on turnSeat's liveness rather than on how it died also
    // covers every other route to the same freeze by construction:
    // loseTwoInfluence eliminating the turn-taker outright, and this
    // watchdog's own PH_LOSE recovery restoring losePrevPhase to PH_TURN
    // while the (still merely absent, never fully eliminated by a single
    // force-pay) turn-taker remains away. Placed after the three blocks
    // above so a same-tick cascade -- PH_LOSE restoring PH_TURN onto a seat
    // already away long enough to have tripped loseStuck -- is caught
    // immediately instead of waiting a further debounce window.
    var turnGone: bool = turnSeat < 0 || turnSeat >= 10
    if !turnGone { turnGone = seatDead(turnSeat, lostAMask, lostBMask) }
    var turnAway: bool = !turnGone && (hereMask & (1 << turnSeat)) == 0
    if turnAway { watchdogAbsentTicks = watchdogAbsentTicks + 1 } else { watchdogAbsentTicks = 0 }
    var turnStuck: bool = turnGone || (turnAway && watchdogAbsentTicks >= WATCHDOG_ABSENT_TICKS)
    if turnStuck {
      // Never call nextTurn() directly -- the tick runs deferred turn
      // advancement in its own slot ahead of phaseWatchdog, so this just
      // hands recovery off to that slot next tick, same as every branch
      // above. nextTurn already clears selection/aim/arm state and re-derives
      // a legal cursor for whoever comes next, and deliberately leaves the
      // outstanding claim (pendKind/pendCard) untouched, so there is nothing
      // else to tear down here.
      turnPending = true
    }
  }
}

// Single phase dispatch for ALL keys. Per-key behaviour must arrive as a
// computed argument, never as separate call sites. Keep this the queue's only
// dispatch target.
mod tapKey(i: int, key: int) {
  if phase == PH_LOBBY || phase == PH_GAMEOVER {
    if key == KEY_W {
      // A lone player at a finished game: readying up cannot start anything
      // (maybeStart needs 3+ seated), so W resets the board instead. Checked
      // before toggleReady so it preempts the ready toggle; the lobby path
      // and the multi-player game-over ready-up path are untouched.
      if phase == PH_GAMEOVER && seatedNow <= 1 { resetPending = true return }
      toggleReady(i)
    }
    return
  }
  // Escape hatch for a stuck table.
  if key == KEY_W && seatedNow <= 1 { resetPending = true return }

  // Everything below acts on live players only.
  if (playingMask & (1 << i)) == 0 { return }
  if seatDead(i, lostAMask, lostBMask) { return }

  // The block-declare latch is independent of the other two; any key other
  // than S disarms seat i's own bit here so it cannot survive to a later,
  // unrelated claim -- and so a non-S key from a DIFFERENT seat can never
  // touch this seat's bit at all.
  if key != KEY_S { sArmMask = sArmMask & ~(1 << i) }

  // Retroactive challenge: available in any phase while a claim is outstanding.
  if key == KEY_SPACE {
    // Space is "another key" as far as the W confirm latch is concerned: an
    // excursion to challenge must never leave seat i's own stale W arm
    // behind. This only ever clears bit i.
    wArmMask = wArmMask & ~(1 << i)
    if pendKind == 0 || pendCard == 0 { spaceArmMask = spaceArmMask & ~(1 << i) return }
    let claimant = if blockSeat >= 0 then blockSeat else pendSeat
    if i == claimant { spaceArmMask = spaceArmMask & ~(1 << i) return }
    if (spaceArmMask & (1 << i)) { spaceArmMask = spaceArmMask & ~(1 << i) resolveChallenge(i) } else { spaceArmMask = spaceArmMask | (1 << i) boardDirty = true }
    return
  }
  // Any other key disarms seat i's own challenge bit only.
  spaceArmMask = spaceArmMask & ~(1 << i)

  // Retroactive block declaration: available in any phase while a Foreign
  // Aid claim is outstanding and eligible (Assassinate/Steal have their own
  // direct PH_RESPOND shortcut just below). Consumes the S press only when a
  // block is actually declarable one way or the other; otherwise falls
  // through so PH_TURN's own S ("back") still works for the current
  // turn-taker.
  if key == KEY_S {
    // S is "another key" as far as the W confirm latch is concerned: an
    // excursion to declare a block must never leave seat i's own stale W arm
    // behind.
    wArmMask = wArmMask & ~(1 << i)
    if canDeclareBlock(i) {
      if (sArmMask & (1 << i)) { sArmMask = sArmMask & ~(1 << i) declareBlock(i) } else { sArmMask = sArmMask | (1 << i) boardDirty = true }
      return
    }
    // S always means Block: the PH_RESPOND target's own direct shortcut,
    // same double-press arm/confirm as every other S declare above, just
    // resolving straight to blockClaim instead of a retroactive
    // declareBlock. canDeclareBlock is Foreign-Aid-only by design
    // (Assassinate/Steal never reach it), so exactly one of these two
    // branches can ever fire for a given press. Gated on blockSeat < 0 --
    // once the target has actually blocked, blockClaim moves the wait to the
    // actor (respondWaitSeat), and there is no blocking a block, so pendTarget
    // pressing S again must fall through to a no-op rather than re-declaring.
    if phase == PH_RESPOND && i == pendTarget && blockSeat < 0 {
      if (sArmMask & (1 << i)) { sArmMask = sArmMask & ~(1 << i) blockClaim(i) } else { sArmMask = sArmMask | (1 << i) boardDirty = true }
      return
    }
    sArmMask = sArmMask & ~(1 << i)
  }

  if phase == PH_LOSE && i == loseSeat {
    if key == KEY_A || key == KEY_D {
      loseHi = 1 - loseHi
      wArmMask = wArmMask & ~(1 << i)
      boardDirty = true
      return
    }
    if key == KEY_W {
      if (wArmMask & (1 << i)) {
        wArmMask = wArmMask & ~(1 << i)
        if loseHi == 0 { lostAMask = lostAMask | (1 << i) } else { lostBMask = lostBMask | (1 << i) }
        selectingMask = selectingMask & ~(1 << i)
        discardingMask = discardingMask & ~(1 << i)
        loseSeat = -1
        // Same reasoning as phaseWatchdog's PH_LOSE exit: whatever this
        // counter accrued against the losing seat's absence must not carry
        // into the restored phase's own wait on a different seat.
        watchdogAbsentTicks = 0
        phase = losePrevPhase
        checkWin()
        boardDirty = true
      } else {
        wArmMask = wArmMask | (1 << i)
        boardDirty = true
      }
      return
    }
    return
  }

  // Two direct keys, no cursor. Before a block: S blocks (handled above,
  // alongside every other S declare), W allows. After a block, the wait
  // shifts to the actor (respondWaitSeat): S has no meaning here (there is
  // no blocking a block, so it already fell through above), Space challenges
  // (the generic retroactive path earlier in this mod), and W accepts. A/D
  // do nothing in either case -- two options do not need a fan to move a
  // cursor across.
  if phase == PH_RESPOND && i == respondWaitSeat() {
    if key == KEY_W {
      if (wArmMask & (1 << i)) {
        wArmMask = wArmMask & ~(1 << i)
        if blockSeat >= 0 { acceptBlock(i) } else { allowClaim(i) }
      } else { wArmMask = wArmMask | (1 << i) boardDirty = true }
      return
    }
    return
  }

  if phase == PH_TURN && i == turnSeat {
    if key == KEY_S {
      if selStage == 1 { selStage = 0 selTarget = -1 aimMask = 0 }
      wArmMask = wArmMask & ~(1 << i)
      boardDirty = true
      return
    }
    if key == KEY_A || key == KEY_D {
      wArmMask = wArmMask & ~(1 << i)
      let dir = if key == KEY_A then -1 else 1
      if selStage == 0 {
        selAction = stepAction(selAction, dir, i)
      } else {
        selTarget = stepTargetSeat(selTarget, dir, i)
        aimMask = 1 << selTarget
      }
      boardDirty = true
      return
    }
    if key == KEY_W {
      if (wArmMask & (1 << i)) { wArmMask = wArmMask & ~(1 << i) commitSelection(i) } else { wArmMask = wArmMask | (1 << i) boardDirty = true }
      return
    }
    return
  }

  if phase == PH_EXCHANGE && i == exchangeSeat {
    // The countdown runs first and the fan is not dealt (exCount == 0) until
    // it expires. Any input before then must be a no-op -- otherwise A/D
    // divides by zero and W,W can fire exchangeFinalize on an empty fan.
    if exCount == 0 { return }
    if key == KEY_A || key == KEY_D {
      wArmMask = wArmMask & ~(1 << i)
      let dir = if key == KEY_A then -1 else 1
      exHi = (exHi + dir + exCount) % exCount
      boardDirty = true
      return
    }
    if key == KEY_W {
      if (wArmMask & (1 << i)) {
        wArmMask = wArmMask & ~(1 << i)
        exKeptMask = exKeptMask ^ (1 << exHi)
        if BitCount(exKeptMask) == influenceOf(i, lostAMask, lostBMask) { exchangeFinalize() } else { boardDirty = true }
      } else { wArmMask = wArmMask | (1 << i) boardDirty = true }
      return
    }
    wArmMask = wArmMask & ~(1 << i)
    return
  }
}

@label("Player Input")
chip {
  let inp0 = InputReader(player0)
  let inp1 = InputReader(player1)
  let inp2 = InputReader(player2)
  let inp3 = InputReader(player3)
  let inp4 = InputReader(player4)
  let inp5 = InputReader(player5)
  let inp6 = InputReader(player6)
  let inp7 = InputReader(player7)
  let inp8 = InputReader(player8)
  let inp9 = InputReader(player9)
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
  buffer f8p: float = inp8.Forward
  buffer r8p: float = inp8.Right
  buffer j8p: bool = inp8.Jump
  buffer f9p: float = inp9.Forward
  buffer r9p: float = inp9.Right
  buffer j9p: bool = inp9.Jump
}

buffer tick: int = tick + (seatedNow > 0)

array names: string[] = ["", "", "", "", "", "", "", "", "", ""]
array ids: string[] = ["", "", "", "", "", "", "", "", "", ""]
// Live seat occupants, one array write per port every tick (see serviceSeat).
// No character literal exists to pre-fill this at declaration, so it starts
// empty and is resized to 10 on first use.
array players: character[]
var logText: string = ""

mod cacheSeat(i: int, ch: character) {
  ids[i] = ch.GetUserId()
  names[i] = sanitizeName(ch.GetDisplayName())
}

// Shared three-state fan entry: normal (padded, no markup) / cursor (this is
// where you are -- bracketed, no colour) / armed (one W landed -- bracketed
// AND yellow, a second W commits). The bracket marks position, the colour
// marks armed; the bracket is present in BOTH the cursor and armed forms, and
// the unarmed (normal) form pads with the same two characters the bracket
// occupies on each side, so the line never reflows width across any of the
// three states -- same property cardFanText (secret-hitler/src/display.ws)
// preserves for its own bracket vs. blank-padded forms. No weight change
// (<b>) in any of the three: bold glyphs are wider than regular ones, which
// would shift every other entry sideways as the cursor moves, exactly what
// the space/bracket padding exists to prevent.
mod fanEntryText(name: string, isHi: bool, armed: bool, affordable: bool) -> string {
  if !affordable { return '  <color="666">${name}</>  ' }
  if isHi {
    if armed { return '[ <color="ff0">${name}</> ]' }
    return "[ ${name} ]"
  }
  return "  ${name}  "
}

// Card fan entries follow fanEntryText's exact normal/cursor/armed shape
// (same padding, same brackets, no added weight in any state) but cannot
// reuse fanEntryText directly: a card's own text (cardText) already carries
// its role colour, and wrapping that in fanEntryText's own <color="ff0">
// would nest two colour tags. The game's rich-text closer isn't a true stack
// -- the inner close consumes the outer one -- so the highlight colour would
// run on past the card into whatever text follows instead of stopping at the
// card's own closing tag. cardTextColored renders the icon+name in exactly
// one colour instead, so the armed state swaps the card's role colour for
// the cursor colour outright rather than nesting around it -- and it is only
// ever used for armed; the mere cursor keeps the card's own role colour,
// just bracketed, so cursor vs. armed differ by colour alone (both
// bracketed, same width, no bold). The <b> inside cardTextColored/cardIcon
// is the icon glyph's own solid-vs-outline selector, not selection styling,
// and stays either way -- it is not wrapping anything that already carries
// markup, so it does not nest. Cards are always affordable here, so there is
// no "unaffordable" branch to mirror.
mod cardFanEntryText(c: int, isHi: bool, armed: bool) -> string {
  if isHi {
    if armed { return "[ ${cardTextColored(c, "ff0")} ]" }
    return "[ ${cardText(c)} ]"
  }
  return "  ${cardText(c)}  "
}

// Exchange-fan-only: layers a "kept" indicator on top of cardFanEntryText's
// cursor/armed states as a third, independent channel. A card can be kept
// AND under the cursor AND armed at once (stepping back onto an
// already-kept card to un-toggle it), so kept cannot reuse the bracket
// (cursor) or the colour (armed) without becoming ambiguous, and a second
// colour would collide visually with armed's yellow. The marker is a plain
// CHARACTER, not a tag, so it sits outside any markup scope and cannot nest
// with (or be mistaken for) the bracket or the colour. It is exactly one
// character either way ("*" kept, " " not) so it never shifts the rest of
// the line -- same padding-by-character-count convention as every other
// fan entry in this file.
mod exchangeCardEntryText(c: int, isHi: bool, armed: bool, kept: bool) -> string {
  let marker = if kept then "*" else " "
  return "${marker}${cardFanEntryText(c, isHi, armed)}"
}

mod actionEntryText(a: int, hi: int, armed: bool, myCoins: int, targetable: bool) -> string {
  return fanEntryText(actionName(a), hi == a, armed, canAffordAction(a, myCoins, targetable))
}

mod targetEntryText(s: int, cur: int, armed: bool) -> string {
  return fanEntryText(seatName(s), cur == s, armed, true)
}

// All seven actions, unrolled (no loop) -- one actionName call per action,
// the minimum needed to show every name at once. All seven render on a
// single line -- width is controlled by promptText shrinking the
// cursor-detail line below the fan, not by wrapping the fan itself.
// myCoins/targetable are invariant across all seven entries and the caller's
// own detail/notice line -- computed once by promptText and passed down
// here, rather than re-derived from actor on every call.
mod actionFanText(hi: int, armed: bool, myCoins: int, targetable: bool) -> string {
  var s: string = actionEntryText(0, hi, armed, myCoins, targetable)
  s = "${s} ${actionEntryText(1, hi, armed, myCoins, targetable)}"
  s = "${s} ${actionEntryText(2, hi, armed, myCoins, targetable)}"
  s = "${s} ${actionEntryText(3, hi, armed, myCoins, targetable)}"
  s = "${s} ${actionEntryText(4, hi, armed, myCoins, targetable)}"
  s = "${s} ${actionEntryText(5, hi, armed, myCoins, targetable)}"
  s = "${s} ${actionEntryText(6, hi, armed, myCoins, targetable)}"
  return s
}

// Per-action detail for the fan's cursor entry ONLY -- cost, claim and risk,
// so the bluffing loop (e.g. Tax claims Duke, so a Tax challenge is a
// challenge of that claim) is readable from the screen instead of only
// discoverable by being challenged. Called once by promptText for whichever
// action is currently under the cursor, never per fan entry, so this never
// multiplies across the seven-entry fan.
mod actionDetailText(a: int) -> string {
  return if a == ACT_INCOME then "+1 coin"
    else if a == ACT_FOREIGN_AID then "+2 coins - claims nothing, blockable by Duke"
    else if a == ACT_COUP then "-7 coins - unblockable, unchallengeable"
    else if a == ACT_TAX then "+3 coins - claims Duke"
    else if a == ACT_ASSASSINATE then "-3 coins - claims Assassin, blockable by Contessa"
    else if a == ACT_EXCHANGE then "claims Ambassador - swap cards with the deck"
    else "up to +2 coins - claims Captain, blockable by Captain or Ambassador"
}

// All legal targets, unrolled over the ten seats (no loop). Each seat's entry
// text is built at most once (bound to `piece`) and only referenced again by
// the accumulator, so an eligible seat never inlines targetEntryText twice.
// Everything renders on a single line -- no wrap.
mod targetFanText(actor: int, cur: int, armed: bool) -> string {
  // Invariant across all ten probes below -- computed once here rather than
  // by canTargetSeat on every probe.
  let mask = playingMask & ~(lostAMask & lostBMask) & hereMask
  var s: string = ""
  var started: bool = false
  if canTargetSeat(0, actor, mask) {
    let piece = targetEntryText(0, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(1, actor, mask) {
    let piece = targetEntryText(1, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(2, actor, mask) {
    let piece = targetEntryText(2, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(3, actor, mask) {
    let piece = targetEntryText(3, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(4, actor, mask) {
    let piece = targetEntryText(4, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(5, actor, mask) {
    let piece = targetEntryText(5, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(6, actor, mask) {
    let piece = targetEntryText(6, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(7, actor, mask) {
    let piece = targetEntryText(7, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(8, actor, mask) {
    let piece = targetEntryText(8, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  if canTargetSeat(9, actor, mask) {
    let piece = targetEntryText(9, cur, armed)
    if !started { s = piece started = true } else { s = "${s} ${piece}" }
  }
  return s
}

// The PH_LOSE card choice: both live influence cards together. PH_LOSE only
// ever opens with two live cards (loseInfluence resolves a one-card seat
// immediately without a prompt), so handA[i]/handB[i] are always in range.
mod loseFanText(i: int, hi: int, armed: bool) -> string {
  let a = cardFanEntryText(handA[i], hi == 0, armed)
  let b = cardFanEntryText(handB[i], hi == 1, armed)
  return "${a} ${b}"
}

// The PH_EXCHANGE card choice: the drawn fan, horizontal like every other
// fan in this file (previously the one <br>-joined vertical exception), with
// a "kept" marker (exchangeCardEntryText) layered on top of the shared
// cursor/armed styling. Unrolled exactly like exchangeFinalize -- no loops --
// and each exCards[n] read stays behind a statement-if so it is never
// evaluated once n >= exCount. Rendered through promptText (the middle HUD
// band), same as every other selection fan -- not handText -- so card
// selection always lives in one place.
mod exchangeFanText(i: int) -> string {
  // This viewer's own armed bit -- i == exchangeSeat is guaranteed by every
  // caller, so this is always the seat this fan is being rendered for, never
  // any other seat's latch.
  let armed = (wArmMask & (1 << i)) != 0
  var fan: string = "Keep ${influenceOf(i, lostAMask, lostBMask)}: "
  if exCount > 0 { fan = "${fan}${exchangeCardEntryText(exCards[0], exHi == 0, armed, (exKeptMask & 1) != 0)}" }
  if exCount > 1 { fan = "${fan} ${exchangeCardEntryText(exCards[1], exHi == 1, armed, (exKeptMask & 2) != 0)}" }
  if exCount > 2 { fan = "${fan} ${exchangeCardEntryText(exCards[2], exHi == 2, armed, (exKeptMask & 4) != 0)}" }
  if exCount > 3 { fan = "${fan} ${exchangeCardEntryText(exCards[3], exHi == 3, armed, (exKeptMask & 8) != 0)}" }
  return fan
}

// The plain "Your cards: A, B" line, shared by the normal path below and the
// PH_EXCHANGE wait (exCount == 0 -- resolveExchange has not yet picked the
// real cards up into the fan, so they are still genuinely in hand and must
// still be shown, not replaced by "Coins: N").
mod cardsLine(i: int) -> string {
  var s: string = "Your cards: "
  // Tested twice below (whether to show card A, and whether to precede card B
  // with a separator) -- hoisted once.
  let aLive = ((lostAMask >> i) & 1) == 0
  if aLive { s = "${s}${cardText(handA[i])}" }
  if ((lostBMask >> i) & 1) == 0 {
    if aLive { s = "${s}, " }
    s = "${s}${cardText(handB[i])}"
  }
  return s
}

// Your own hand is private text, never a board output. Once the exchange fan
// is actually dealt (exCount > 0), the real cards are picked up into it
// (their slots already publish CARD_HIDDEN), so there are no cards left to
// list here -- show only the coin count rather than an empty "Your cards:"
// line. Before that (exCount == 0, still in the challenge-window countdown)
// the cards are still genuinely in hand, so they still show.
mod handText(i: int) -> string {
  if phase == PH_EXCHANGE && i == exchangeSeat {
    if exCount == 0 { return "${cardsLine(i)}   Coins: ${coins[i]}" }
    return "Coins: ${coins[i]}"
  }
  return "${cardsLine(i)}   Coins: ${coins[i]}"
}

// Load-bearing for retroactive challenge: every player must be able to see
// what is currently challengeable and whether it is still live.
// `viewer` is the seat this banner is being rendered for -- needed so the
// "whose turn is it" line can read "It's Your Turn" for the turn-taker
// themselves and "It's <name>'s turn" for everyone else.
// Keys on pendCard != 0 -- whether there is a challengeable claim -- rather
// than on pendKind == 0. A claim deliberately survives the turn advance (that
// survival is the challenge window), but Coup and Income both claim no role
// (pendCard stays 0) and are unchallengeable, so once either commits there is
// nothing left to advertise: the activity log already recorded what
// happened, and the banner should already be back to announcing the turn.
// The old pendKind == 0 check only happened to work for Income by
// coincidence -- ACT_INCOME's id is itself 0 -- and did not work for Coup,
// whose id is not, which is exactly why the banner stuck on "Name: Coup".
mod bannerText(viewer: int) -> string {
  if phase == PH_LOBBY { return '<size="42"><font="orbitron">coup</></><br>Sit down and tap <b>W</> to ready up (3-10 players) - ${BitCount(readyMask)}/${seatedNow} ready' }
  if phase == PH_GAMEOVER {
    // Same readyMask in both return arms below -- hoisted once.
    let readyCount = BitCount(readyMask)
    if winnerSeat < 0 { return "No survivors - ${readyCount}/${seatedNow} ready for a rematch" }
    return "${seatName(winnerSeat)} wins! - ${readyCount}/${seatedNow} ready for a rematch"
  }
  // PH_RESPOND's own claim stays live until whoever is currently being
  // waited on answers -- the target's Block/Allow before a block, then the
  // actor's Challenge/Accept once blockClaim/declareBlock sets blockSeat --
  // including after a failed challenge proves the claim genuine, which
  // clears pendCard so it cannot be challenged a second time
  // (resolveChallenge). Keying on pendCard here would then fall through to
  // the turn line while someone is still deciding, so PH_RESPOND is checked
  // first and unconditionally. The claimed card is reconstructed from
  // pendKind via actionClaim rather than read from pendCard, since pendCard
  // is exactly the field a proven challenge may have zeroed.
  if phase == PH_RESPOND {
    let who = if blockSeat >= 0 then blockSeat else pendSeat
    let respondCard = if pendCard != 0 then pendCard else actionClaim(pendKind)
    var s: string = "${seatName(who)}: ${actionName(pendKind)}"
    if blockSeat >= 0 { s = "${seatName(who)} BLOCKS" }
    return "${s} (claims ${cardText(respondCard)})"
  }
  if pendCard == 0 {
    if viewer == turnSeat { return "It's Your Turn" }
    return "It's <b>${seatName(turnSeat)}</>'s turn"
  }
  // blockSeat is always -1 here. blockClaim and declareBlock are the only two
  // sites that ever set it non-negative, and both either require phase to
  // already be PH_RESPOND (blockClaim) or set phase to PH_RESPOND themselves
  // in the same call (declareBlock) -- so blockSeat >= 0 implies phase ==
  // PH_RESPOND, which already returned above. Only a still-unblocked
  // retroactive Foreign Aid claim ever reaches here, so this is always the
  // actor's own claim, never a block -- the old blockSeat-aware "who/BLOCKS"
  // branch that used to mirror PH_RESPOND's shape here was unreachable and
  // has been removed.
  var s: string = "${seatName(pendSeat)}: ${actionName(pendKind)} (claims ${cardText(pendCard)})"
  // PH_EXCHANGE's countdown IS the challenge window, and it was otherwise
  // invisible to everyone -- actor and potential challengers alike -- with no
  // indication a window existed at all, let alone that it was closing.
  // Public (not just the actor's own prompt), since a challenger deciding
  // whether to act needs to see it too.
  if phase == PH_EXCHANGE {
    let secsLeft = (exchangeLeft + 59) / 60
    s = "${s} - ${secsLeft}s to challenge"
  }
  // The claim survives the turn advance (that survival IS the challenge
  // window), so it previously replaced the turn line entirely -- the banner
  // stuck on "claims Duke" for the whole of the next player's turn with no
  // way to tell whose turn it now was. Append rather than replace, so both
  // stay visible together.
  let turnLine = if viewer == turnSeat then "It's Your Turn" else "It's <b>${seatName(turnSeat)}</>'s turn"
  return "${s}<br>${turnLine}"
}

// The claim challenge/block window is retroactive and open in any phase --
// even to a seat that is also mid its own action-fan (a live claim survives
// the turn advance) or mid the PH_RESPOND Block/Allow fan (the target of an
// Assassinate or Steal may also challenge the claim itself, since the target
// is never the claimant). Composed with whatever phase-specific fan applies,
// rather than shadowed by it: previously a phase-specific branch returned
// before ever reaching the challenge/block lines below it, so a target saw
// the Block/Allow fan with no indication that challenging the claim was also
// on the table.
// When a block is outstanding (blockSeat >= 0), the thing being challenged is
// the BLOCK, not the original action -- naming actionName(pendKind) there
// used to read "challenge Bob's Assassinate" when Bob had actually blocked
// the assassination. Name the block and the claimed role instead. When no
// block is outstanding and the claim is targeted (Steal, Assassinate), also
// name the target: a bystander deciding whether to spend an influence on a
// challenge needs to know who is actually affected, not just whose claim it
// is. Keyed on actionTargeted(pendKind), not an action-id enumeration, so a
// targeted action added later is handled by default -- only the preposition
// word itself ("from" vs "on") is action-specific, since English has no
// generic preposition. Coup is targeted but claims nothing (pendCard stays
// 0), so canDeclareChallenge already rejects it before this line is reached
// -- no special case needed. The armed variant restates the same claim text
// so confirming and the original prompt never disagree about what is being
// challenged.
mod challengeLineText(i: int) -> string {
  if !canDeclareChallenge(i) { return "" }
  let claimant = if blockSeat >= 0 then blockSeat else pendSeat
  let name = seatName(claimant)
  var claimText: string = "block"
  if blockSeat < 0 {
    claimText = actionName(pendKind)
    if actionTargeted(pendKind) {
      var prep: string = "on"
      if pendKind == ACT_STEAL { prep = "from" }
      claimText = "${claimText} ${prep} <b>${seatName(pendTarget)}</>"
    }
  }
  let full = "${claimText} (claims ${cardText(pendCard)})"
  if (spaceArmMask & (1 << i)) {
    return "Press <b>Space</> again to confirm challenging <b>${name}</>'s ${full}<br>If you're wrong, you lose influence!"
  }
  return "<b>Space</> to challenge <b>${name}</>'s ${full}"
}

// Same shape as challengeLineText, and named the same way for consistency
// (both unarmed and armed restate who and what). canDeclareBlock only ever
// admits Foreign Aid now -- Assassinate and Steal both keep their own
// synchronous PH_RESPOND Block/Allow fan, never this retroactive path -- so
// the claimant here is always pendSeat, never a prior blockSeat, the
// blocking role is always the single Duke case, and Foreign Aid itself is
// never targeted, so there is no target clause to add here.
mod blockLineText(i: int) -> string {
  if !canDeclareBlock(i) { return "" }
  let name = seatName(pendSeat)
  let an = actionName(pendKind)
  if (sArmMask & (1 << i)) {
    return "Press <b>S</> again to confirm blocking <b>${name}</>'s ${an}<br>If you don't have the ${cardText(actionBlocker(pendKind))}, you lose influence!"
  }
  return "<b>S</> to Block <b>${name}</>'s ${an}"
}

// What promptText shows everyone mid a PH_RESPOND wait except waitSeat
// (respondWaitSeat) itself -- the target before a block, the actor once one
// is declared. A retroactive Foreign Aid block can yank the global phase out
// from under a completely unrelated seat's own PH_TURN fan (their queued
// input is dropped by the phase tag the same tick, per the input queue's own
// dispatch guard), so without this their prompt would otherwise just go
// blank with no explanation of why their keys stopped doing anything. Same
// "answering X's Y" shape either side of a block, keyed on blockSeat exactly
// like bannerText's own claim line: before one, waitSeat (the target) is
// answering the actor's claimed action; once declared, waitSeat (the actor)
// is answering the blocker's claimed block instead. Callers pass waitSeat in
// rather than this re-deriving it via respondWaitSeat(), since the caller
// already needs it for its own `i != waitSeat` guard.
mod respondWaitText(waitSeat: int) -> string {
  let waitName = seatName(waitSeat)
  if blockSeat >= 0 {
    return "<b>${waitName}</> is answering <b>${seatName(blockSeat)}</>'s block - ${actionName(pendKind)}"
  }
  return "<b>${waitName}</> is answering <b>${seatName(pendSeat)}</>'s ${actionName(pendKind)}"
}

mod promptText(i: int) -> string {
  if phase == PH_LOBBY { return lobbyPrompt(i) }
  if phase == PH_GAMEOVER {
    // Mirrors tapKey's own lone-player escape hatch: readying up cannot
    // start anything with only one seat, so tell them W resets instead.
    if seatedNow <= 1 { return "You are the last player - tap <b>W</> to reset." }
    return lobbyPrompt(i)
  }
  // Escape hatch for a stuck table, mirrors tapKey's own check.
  if seatedNow <= 1 { return "You are the last player - tap <b>W</> to reset." }
  // A seat that sat down mid-game was never dealt in: they have nothing to
  // act on, only the banner/activity feed to watch.
  if (playingMask & (1 << i)) == 0 { return "Watching - ready up when this game ends" }
  // An eliminated seat stays in playingMask (so its revealed hand still
  // publishes) but can no longer act -- say so instead of a dead-end prompt.
  if seatDead(i, lostAMask, lostBMask) { return "You are out - watching the rest of the game" }

  // The phase-specific part: whatever synchronous fan this seat's own prompt
  // is currently waiting on, if any. Every branch below follows the same
  // legend convention (secret-hitler/src/main.ws's promptFor, lines
  // 525-567): keys are shown inline with their meaning as "<b>KEY</> =
  // meaning" pairs rather than prose, and the armed legend REPLACES the
  // unarmed one instead of appending to it. Unlike that sibling, no legend
  // here ever says a key twice ("W twice") -- every legend names each key
  // once. A fan's cursor is always bracketed in place, so an explicit
  // "-> ..." line beneath it is only added when it carries information the
  // fan itself does not show (the action fan's cost/claim detail) -- never
  // as a bare restatement of what is already bracketed.
  var phasePart: string = ""
  if phase == PH_TURN && i == turnSeat {
    let armed = (wArmMask & (1 << i)) != 0
    if selStage == 0 {
      // myCoins/targetable feed both the fan and this cursor entry's detail
      // line/forced-coup notice -- computed once here and passed down,
      // rather than re-derived by actionFanText per entry.
      let myCoins = coins[i]
      let targetable = hasLegalTarget(i)
      var notice: string = ""
      if myCoins >= 10 && targetable { notice = '<br><color="f88">10+ coins forces Coup</>' }
      var legend: string = "<b>A/D</> = move  <b>W</> = select"
      if armed { legend = "<b>W</> = confirm  <b>A/D</> = change" }
      // This line carries information the fan itself does not show -- the
      // cost and the claimed role -- so it stays, unlike the target fan's
      // own selection line below. Rendered smaller than the fan so it
      // controls width instead of the fan wrapping.
      phasePart = '${actionFanText(selAction, armed, myCoins, targetable)}<br><size="14">-> ${actionName(selAction)}: ${actionDetailText(selAction)}</>${notice}<br>${legend}'
    } else {
      // No selection-restates-the-cursor line here: the fan already shows
      // the cursor bracketed around a bare seat name, so a separate "-> Name"
      // line beneath it would say nothing the fan doesn't already show.
      var legend: string = "<b>A/D</> = move  <b>W</> = select  <b>S</> = back"
      if armed { legend = "<b>W</> = confirm  <b>A/D</> = change  <b>S</> = back" }
      phasePart = "${targetFanText(i, selTarget, armed)}<br>${legend}"
    }
  }
  // Two direct keys, no fan and no cursor: S always blocks (Contessa for an
  // Assassinate, Captain/Ambassador for a Steal), W always allows -- same
  // double-press arm/confirm as everywhere else, with S's arm/confirm
  // itself handled in tapKey's shared S dispatch. A/D do nothing here.
  // blockSeat < 0 -- once the target has blocked, this prompt is done; the
  // wait (and the branch below) shifts to the actor.
  if phase == PH_RESPOND && i == pendTarget && blockSeat < 0 {
    let wArmed = (wArmMask & (1 << i)) != 0
    let sArmed = (sArmMask & (1 << i)) != 0
    let name = seatName(pendSeat)
    let an = actionName(pendKind)
    if sArmed {
      var blockRole: string = cardText(CARD_CONTESSA)
      if pendKind == ACT_STEAL { blockRole = "${cardText(CARD_CAPTAIN)} or ${cardText(CARD_AMBASSADOR)}" }
      phasePart = "Press <b>S</> again to confirm blocking <b>${name}</>'s ${an}<br>If you don't have the ${blockRole}, you lose influence!"
    } else if wArmed {
      phasePart = "Press <b>W</> again to confirm allowing <b>${name}</>'s ${an}"
    } else {
      var blockDetail: string = ""
      if pendKind == ACT_STEAL { blockDetail = " - refunds coins" }
      phasePart = "<b>S</> to Block <b>${name}</>'s ${an}${blockDetail}<br><b>W</> to Allow"
    }
  }
  // The actor's own symmetric step once a block is outstanding: no cursor,
  // no S (there is no blocking a block) -- Space challenges (rendered below
  // via the shared respPart/challengeLineText, same as any other viewer's
  // challenge line) and W accepts, both with the same double-press arm/
  // confirm shape as the target's Block/Allow prompt above.
  if phase == PH_RESPOND && i == pendSeat && blockSeat >= 0 {
    let wArmed = (wArmMask & (1 << i)) != 0
    let name = seatName(blockSeat)
    if wArmed {
      phasePart = "Press <b>W</> again to confirm accepting <b>${name}</>'s block"
    } else {
      phasePart = "<b>W</> to Accept <b>${name}</>'s block"
    }
  }
  // Every other seat mid this same PH_RESPOND wait -- the two branches above
  // are the only ones with a synchronous fan of their own right now, so
  // anyone else (a genuine bystander, the claimant waiting on their own
  // target's Block/Allow, or the blocker once the wait has moved on to the
  // actor) gets an explanation instead of a blank prompt or, worse, their own
  // now-dead PH_TURN fan appearing to still be live. respPart below still
  // adds the Space-challenge line on top of this for anyone who is not the
  // current claimant -- explanation and actionable option are independent
  // and both apply when both are true.
  if phase == PH_RESPOND {
    let waitSeat = respondWaitSeat()
    if i != waitSeat { phasePart = respondWaitText(waitSeat) }
  }
  if phase == PH_LOSE && i == loseSeat {
    // PH_LOSE is reached from several very different places -- a failed
    // challenge, a bluffed block, an assassination, a Coup, the watchdog
    // forcing the loss -- and looks identical from here regardless of which.
    // Say only that a card is being given up; the reason is already in the
    // activity log's line for whatever just happened. No "-> card" line
    // either: the fan already shows the cursored card bracketed, so a
    // restated line beneath it would be a pure repeat.
    let armed = (wArmMask & (1 << i)) != 0
    var legend: string = "<b>A/D</> = move  <b>W</> = select"
    if armed { legend = "<b>W</> = confirm  <b>A/D</> = change" }
    phasePart = "You are discarding a card<br>${loseFanText(i, loseHi, armed)}<br>${legend}"
  }
  // Everyone else while loseSeat is mid their own discard fan -- same class
  // of gap as the PH_RESPOND bystander branch above: PH_LOSE also waits on
  // exactly one seat, and nobody else has a key that does anything here
  // either.
  if phase == PH_LOSE && i != loseSeat {
    phasePart = "<b>${seatName(loseSeat)}</> is choosing a card to discard"
  }
  if phase == PH_EXCHANGE && i == exchangeSeat {
    // The countdown IS the challenge window and runs before the fan is dealt
    // (exCount == 0) -- previously this rendered an empty fan plus a legend
    // for keys tapKey explicitly ignores during the wait. Show the time
    // remaining instead; the public banner (bannerText) shows the same
    // countdown to everyone else deciding whether to challenge.
    if exCount == 0 {
      let secsLeft = (exchangeLeft + 59) / 60
      phasePart = "Waiting to challenge - your cards are drawn in ${secsLeft}s"
    } else {
      // Same reasoning as PH_LOSE above: the fan already shows the cursored
      // card bracketed (plus its own kept marker), so no restated "-> card"
      // line beneath it.
      let armed = (wArmMask & (1 << i)) != 0
      var legend: string = "<b>A/D</> = move  <b>W</> = toggle keep"
      if armed { legend = "<b>W</> = confirm toggle  <b>A/D</> = change" }
      phasePart = "${exchangeFanText(i)}<br>${legend}"
    }
  }
  // Everyone else during exchangeSeat's own card swap -- same class of gap
  // again. The countdown itself is already public (bannerText shows it to
  // every viewer), so it is not repeated here; this only names who.
  if phase == PH_EXCHANGE && i != exchangeSeat {
    phasePart = "<b>${seatName(exchangeSeat)}</> is exchanging cards"
  }

  // The response part: whether this viewer may challenge and/or block the
  // outstanding claim, independent of whatever phasePart above is showing.
  var respPart: string = challengeLineText(i)
  let blockLine = blockLineText(i)
  if blockLine != "" {
    if respPart != "" { respPart = "${respPart}<br>${blockLine}" } else { respPart = blockLine }
  }

  if phasePart != "" && respPart != "" { return "${phasePart}<br>${respPart}" }
  if phasePart != "" { return phasePart }
  return respPart
}

mod serviceSeatAt(i: int, ch: character) {
  if ch.GetUserId() != ids[i] { cacheSeat(i, ch) }
  hudActivity(ch, logText)
  hudBanner(ch, bannerText(i))
  hudPrompt(ch, promptText(i))
  if (playingMask & (1 << i)) { hudHand(ch, handText(i)) }
}

chip serviceSeat(i: int) {
  logText = '${activityLog[0]}<br>${activityLog[1]}<br>${activityLog[2]}<br>${activityLog[3]}<br>${activityLog[4]}<br>${activityLog[5]}<br>${activityLog[6]}<br>${activityLog[7]}'
  // One-time grow to 10 slots (the fill value is irrelevant -- every slot is
  // overwritten unconditionally below on this same pass, so even on the very
  // first tick no index is read before it holds a live port value).
  if players.length() < 10 { players.resize(10, player0) }
  // Refresh straight from the live ports every tick -- never cached off an
  // enter/leave event, so a seated player is never left without a HUD.
  players[0] = player0
  players[1] = player1
  players[2] = player2
  players[3] = player3
  players[4] = player4
  players[5] = player5
  players[6] = player6
  players[7] = player7
  players[8] = player8
  players[9] = player9
  // hereMask is the pure, port-derived occupancy bitmask -- gate on it, not
  // on players[i] truthiness, so a stale slot can never service the wrong
  // seat. Single call site: serviceSeatAt (and everything it reaches) now
  // inlines once instead of once per seat.
  if (hereMask & (1 << i)) { serviceSeatAt(i, players[i]) }
}

@label("Tick")
chip on tick {
  @label("Input Reading")
  chip {
    readSeatInput(0, inp0.Forward, inp0.Right, inp0.Jump, f0p, r0p, j0p)
    readSeatInput(1, inp1.Forward, inp1.Right, inp1.Jump, f1p, r1p, j1p)
    readSeatInput(2, inp2.Forward, inp2.Right, inp2.Jump, f2p, r2p, j2p)
    readSeatInput(3, inp3.Forward, inp3.Right, inp3.Jump, f3p, r3p, j3p)
    readSeatInput(4, inp4.Forward, inp4.Right, inp4.Jump, f4p, r4p, j4p)
    readSeatInput(5, inp5.Forward, inp5.Right, inp5.Jump, f5p, r5p, j5p)
    readSeatInput(6, inp6.Forward, inp6.Right, inp6.Jump, f6p, r6p, j6p)
    readSeatInput(7, inp7.Forward, inp7.Right, inp7.Jump, f7p, r7p, j7p)
    readSeatInput(8, inp8.Forward, inp8.Right, inp8.Jump, f8p, r8p, j8p)
    readSeatInput(9, inp9.Forward, inp9.Right, inp9.Jump, f9p, r9p, j9p)
  }

  if turnPending { turnPending = false nextTurn() }

  // Clear any phase stranded on a seat that is now invalid before the queue
  // below dispatches: phase-advancing deferred work (this and turnPending)
  // runs before the dequeue so a freshly-cleared phase is what this tick's
  // input is matched against, instead of the dequeue silently spending a tick
  // of input against a dead prompt that never matches any branch.
  phaseWatchdog()

  @label("Input queue")
  chip {
    if inputQueue.length() > 0 {
      let ev = inputQueue[0]
      inputQueue.remove(0)
      if ev / 128 == phase {
        tapKey((ev % 128) / 8, ev % 8)
      }
    }
  }

  if resetPending { resetPending = false resetState() }
  if phase == PH_EXCHANGE { exchangeTick() }

  if phase == PH_LOBBY || phase == PH_GAMEOVER {
    let prunedReady = readyMask & hereMask
    if prunedReady != readyMask {
      readyMask = prunedReady
      boardDirty = true
    }
    maybeStart()
  }

  if boardDirty { boardDirty = false refreshBoard() }
  serviceSeat(tick % 10)
}
