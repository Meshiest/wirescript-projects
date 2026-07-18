// Secret Hitler - main orchestrator. Board contract + phase machine.
// Spec: docs/superpowers/specs/2026-07-17-secret-hitler-circuit-design.md
// The seat IS the player: all state is seat-indexed; the current occupant of
// player<i> acts for seat i (hot-swap supported, used for solo testing).

import { deckInit, deckDraw3, deckReshuffleIfLow, deckTopCard } from "deck"
import {
  PW_EXECUTE, PW_INVESTIGATE, PW_NONE, PW_PEEK, PW_SPECIAL, R_FASC, R_HITLER, R_LIB, POL_FASC,
  POL_LIB, HITLER_ZONE, VETO_AT, fascistCount, liberalCount, powerAt, powerName,
} from "powers"
import {
  TGT_ANY, TGT_INVESTIGATE, TGT_NOMINEE, isChaos, nextAlive, nextTarget, trackerNext,
} from "gov"
import { WIN_LIB, WIN_NONE, electionWinner, executionWinner, policyWinner } from "outcome"
import {
  cardFanText, hudActivity, hudBanner, hudPrompt, hudRole, hudTally, policyText, roleText,
  sanitizeName,
} from "display"

// Seat bit values (bit i = seat i), so masks read as BIT_3 not 1 << 3.
let BIT_0 = 1
let BIT_1 = 2
let BIT_2 = 4
let BIT_3 = 8
let BIT_4 = 16
let BIT_5 = 32
let BIT_6 = 64
let BIT_7 = 128
let BIT_8 = 256
let BIT_9 = 512

// ---- Phases ----
let PH_LOBBY = 0
let PH_NIGHT = 1
let PH_NOMINATE = 2
let PH_VOTE = 3
let PH_LEG_PRES = 4
let PH_LEG_CHANC = 5
let PH_VETO = 6
let PH_EXEC = 7
let PH_GAMEOVER = 8

// ---- Inputs (all @right per board layout) ----
// No start/reset ports: the game is driven entirely from the seats. In LOBBY,
// seated players tap W to ready up (Ja); when all 5-10 seated are ready it
// auto-starts. In any live phase, the last remaining seated player (or anyone
// at GAMEOVER) taps W to reset back to lobby.
@right in player0: character // seat occupants, wired from the board's seats
@right in player1: character
@right in player2: character
@right in player3: character
@right in player4: character
@right in player5: character
@right in player6: character
@right in player7: character
@right in player8: character
@right in player9: character

// ---- Game state (seat-indexed, 10 slots, literal-initialized so every read
// is in-bounds from the first tick, before any reset/start) ----
// Per-seat occupant identity, updated by the `on playerN` handlers on enter/leave.
array ids: string[] = ["", "", "", "", "", "", "", "", "", ""] // occupant userId ("" = empty seat)
array names: string[] = ["", "", "", "", "", "", "", "", "", ""] // sanitized display name
array players: character[] // occupant character (null-filled to 10 on first cacheSeat)
array seatRole: int[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] // R_LIB / R_FASC / R_HITLER
array drawPile: int[]
array discardPile: int[]
array hand: int[] // legislative hand (3 then 2 cards)
array dealt: int[] // role deal scratch
array scratchSeats: int[] // playing-seat list scratch (first-president draw)
array inputQueue: int[] // pending (seat*4+key) tap events; ONE dequeued per tick
// through a single dispatch site - the 30 edge checks
// only push ints, so the phase machine inlines ONCE
// instead of once per edge (this was the 300k-gate bug)

var phase: int = 0
var vPlayerCount: int = 0
var presidentSeat: int = -1
var chancellorSeat: int = -1
var nomineeSeat: int = -1
var lastPres: int = -1 // last ELECTED president (term limits)
var lastChanc: int = -1 // last ELECTED chancellor
var rotationSeat: int = -1 // normal placard rotation pointer
var specialNext: int = -1 // pending special-election president
var libEnacted: int = 0
var fascEnacted: int = 0
var tracker: int = 0
var vetoBlocked: int = 0 // 1 = veto refused this session, chancellor must enact
var execPower: int = 0 // active PW_* during PH_EXEC
var execPicked: int = -1 // confirmed target during PH_EXEC result stage (-1 = still picking)
var selHi: int = -1 // card-fan highlight (tap-again confirms)
var selTarget: int = -1 // target-picker highlight seat
var wArm: bool = false // NOMINATE/EXEC: first W arms, second W confirms (double-W)
var winner: int = 0
var votesLeft: int = 0
var votedMask: int = 0 // bit i = seat i has cast a ballot this vote
var votedYesMask: int = 0 // bit i = seat i voted Ja
var votePassed: bool = false // resolved outcome, awaiting acks (PH_VOTE, votesLeft==0)
var readyMask: int = 0 // bit i = seat i readied in LOBBY; cleared when seat empties
var playingMask: int = 0 // bit i = seat i captured into the game
var deadMask: int = 0 // bit i = seat i executed
var investigatedMask: int = 0 // bit i = seat i already investigated

// Living players = playing and not executed.
let aliveCount = BitCount(playingMask & ~deadMask)

// Deferred board refresh: mutation sites set this flag instead of calling
// refreshBoard() directly (18 call sites would each inline the whole body).
// The input tick runs the ONE real refreshBoard call when the flag is set,
// after the exec chains have settled - so the board also never sees
// mid-chain intermediate state.
var boardDirty: bool = false

// Deferred round advance, same trick as boardDirty: six sites set the flag,
// the input tick runs the ONE real nextRound() call - BEFORE the event
// dequeue, so the phase has always advanced before any queued event
// dispatches (a stale same-phase vote tap could otherwise re-trigger
// resolveVotes in the one-tick window).
var roundPending: bool = false

// Deferred reset (lone-survivor / post-game W): set by a tap
var resetPending: bool = false

// ---- Board output vars (recomputed by refreshBoard) ----
var vLib: int = 0
var vFasc: int = 0
var vDraw: int = 0
var vDiscard: int = 0
var vTracker: int = 0
var vIsPres: int = 0
var vIsChanc: int = 0
var vVoteYes: int = 0
var vVoteNo: int = 0
var vIsSelecting: int = 0
var vIsPlaying: int = 0
var vIsDead: int = 0
var vIsHitler: int = 0
var vIsLiberal: int = 0
var vIsFascist: int = 0
var vIsReady: int = 0 // bit i = seat i readied (lobby / rematch / vote-result ack)
var vIsAim: int = 0 // bit i = seat i is the current execute/investigate target

// ---- Board outputs (all @left per board layout) ----
@left out discardPileSize: int = vDiscard.Value
@left out drawPileSize: int = vDraw.Value

@left out electionTracker: int = vTracker.Value
@left out playerCount: int = vPlayerCount.Value

@left out libPolicies: int = vLib.Value
@left out fascistPolicies: int = vFasc.Value

@left out isPlaying: int = vIsPlaying.Value
@left out isFascist: int = vIsFascist.Value
@left out isHitler: int = vIsHitler.Value
@left out isLiberal: int = vIsLiberal.Value
@left out isDead: int = vIsDead.Value
@left out voteYes: int = vVoteYes.Value
@left out voteNo: int = vVoteNo.Value
@left out isSelecting: int = vIsSelecting.Value
@left out isChancellor: int = vIsChanc.Value
@left out isPresident: int = vIsPres.Value
@left out isReady: int = vIsReady.Value
@left out isAim: int = vIsAim.Value

var logText: string = ""
@bottom out log: string = logText.Value

// ---- Seat identity cache ----
// Refresh one seat's occupant from its character port (called on enter/leave).
mod cacheSeat(i: int, ch: character) {
  let uid = ch.GetUserId()
  if players.length() < 10 { players.resize(10) } // one-time null-fill to length 10
  ids[i] = uid
  players[i] = ch
  names[i] = if uid != "" then sanitizeName(ch.GetDisplayName()) else ""
  boardDirty = true
}

// seatName is now a trivial array read (kept as a name for readability).
mod seatName(i: int) -> string {
  return names[i]
}

// Number of occupied seats - a pure sum of the character ports (empty = 0).
let seatedNow = player0 + player1 + player2 + player3 + player4
  + player5 + player6 + player7 + player8 + player9

// Occupancy bitmask straight off the ports (bit i = seat i occupied), pure so
// it never goes stale. An empty seat's InputReader aliases the local player's
// input, so edges must be gated on real occupancy.
let hereMask = player0 + player1 * 2 + player2 * 4 + player3 * 8 + player4 * 16
  + player5 * 32 + player6 * 64 + player7 * 128 + player8 * 256 + player9 * 512

// A seat's character port fires on occupant change (sit / stand / swap).
@label("Seat occupancy") chip {
  let changedPlayer0 = Change(player0)
  on changedPlayer0 { cacheSeat(0, player0) }
  let changedPlayer1 = Change(player1)
  on changedPlayer1 { cacheSeat(1, player1) }
  let changedPlayer2 = Change(player2)
  on changedPlayer2 { cacheSeat(2, player2) }
  let changedPlayer3 = Change(player3)
  on changedPlayer3 { cacheSeat(3, player3) }
  let changedPlayer4 = Change(player4)
  on changedPlayer4 { cacheSeat(4, player4) }
  let changedPlayer5 = Change(player5)
  on changedPlayer5 { cacheSeat(5, player5) }
  let changedPlayer6 = Change(player6)
  on changedPlayer6 { cacheSeat(6, player6) }
  let changedPlayer7 = Change(player7)
  on changedPlayer7 { cacheSeat(7, player7) }
  let changedPlayer8 = Change(player8)
  on changedPlayer8 { cacheSeat(8, player8) }
  let changedPlayer9 = Change(player9)
  on changedPlayer9 { cacheSeat(9, player9) }
}

// ---- Activity feed (replaces chat broadcasts) ----
// Rolling log of the last LOG_LINES public events, rendered bottom-right to
// every seated player by the service pass.
let LOG_LINES = 8
// Always exactly LOG_LINES slots so serviceSeat's fixed 8-slot render never
// reads an out-of-bounds index (a cleared array keeps stale backing strings,
// which showed the previous game's log). logLine keeps the length pinned.
array activityLog: string[] = ["", "", "", "", "", "", "", ""]

mod logLine(s: string) {
  activityLog.push(s)
  if activityLog.length() > LOG_LINES {
    activityLog.remove(0)
  }
}

mod appendLogAt(i: int, n: int, s: *string) {
  if i < n {
    s = s .. activityLog[i] .. "<br>"
  }
}

// Accumulate one seat's role into the reveal bit flags (GAMEOVER only).
// Callers must zero vIsHitler/vIsLiberal/vIsFascist before the 10-seat pass.
mod revealRolesAt(i: int) {
  if (playingMask & (1 << i)) {
    if seatRole[i] == R_HITLER { vIsHitler = vIsHitler | (1 << i) }
    if seatRole[i] == R_LIB { vIsLiberal = vIsLiberal | (1 << i) }
    if seatRole[i] == R_FASC { vIsFascist = vIsFascist | (1 << i) }
  }
}

/// Recompute EVERY board output after any state mutation, so the board never
/// sees intermediate values. Votes publish only when the last ballot lands.
chip refreshBoard() {
  vLib = libEnacted
  vFasc = fascEnacted
  vDraw = drawPile.length()
  vDiscard = discardPile.length()
  vTracker = tracker
  vIsPlaying = playingMask
  vIsDead = deadMask
  // Unified ready flag: lobby ready-up, GAMEOVER rematch, and the vote-result
  // acknowledgement all live in readyMask (0 during active play).
  vIsReady = readyMask
  // The seat the president is aiming at during an execute/investigate pick.
  vIsAim = (if phase == PH_EXEC && execPicked < 0 && selTarget >= 0
      && (execPower == PW_EXECUTE || execPower == PW_INVESTIGATE)
    then 1 << selTarget else 0)
  // A special election picks the NEXT president, so the president token itself
  // moves to the highlighted candidate rather than lighting the aim marker.
  let presSpecial = phase == PH_EXEC && execPower == PW_SPECIAL && execPicked < 0 && selTarget >= 0
  let inGov = phase >= PH_LEG_PRES && phase <= PH_EXEC
  vIsPres = (if presSpecial then 1 << selTarget
    else if presidentSeat >= 0 && phase >= PH_NOMINATE && phase < PH_GAMEOVER then 1 << presidentSeat
    else 0)
  // Chancellor placard: the CANDIDATE during nomination/vote (nomineeSeat once
  // picked, else the president's live A/D highlight), the elected chancellor
  // once the government is seated.
  let chancCand = if nomineeSeat >= 0 then nomineeSeat else selTarget
  vIsChanc = (if (phase == PH_NOMINATE || phase == PH_VOTE) && chancCand >= 0 then 1 << chancCand
    else if chancellorSeat >= 0 && inGov then 1 << chancellorSeat
    else 0)
  // Policy Peek lights the president too: they're looking at the top 3 policies,
  // same visual as the LEG_PRES draw.
  let presPeeking = phase == PH_EXEC && execPower == PW_PEEK
  vIsSelecting = (if presidentSeat >= 0 && (phase == PH_LEG_PRES || phase == PH_VETO || presPeeking) then 1 << presidentSeat
      else if chancellorSeat >= 0 && phase == PH_LEG_CHANC then 1 << chancellorSeat
      else 0)
  if votesLeft > 0 {
    // A vote is still collecting. Seats that HAVE voted show BOTH the ja and
    // nein bits ("voted", without revealing which way); unvoted seats show
    // neither. votesLeft hits 0 exactly when resolveVotes publishes the real
    // split (dropping each voter's losing bit) and stays 0 until the next
    // beginVote, so the published result persists even though the
    // failed-election path calls refreshBoard while phase is still PH_VOTE.
    vVoteYes = votedMask
    vVoteNo = votedMask
  }
  if phase == PH_LOBBY {
    // Ready shows via isReady now, not the ja/nein proxy - keep votes clear.
    vVoteYes = 0
    vVoteNo = 0
  }
  if phase == PH_GAMEOVER {
    @label("Reveal roles") chip {
      revealRolesAt(0) revealRolesAt(1) revealRolesAt(2) revealRolesAt(3) revealRolesAt(4)
      revealRolesAt(5) revealRolesAt(6) revealRolesAt(7) revealRolesAt(8) revealRolesAt(9)
    }
  } else {
    vIsHitler = 0
    vIsLiberal = 0
    vIsFascist = 0
  }
}

// ---- Reset ----
// A plain mod, NOT an exec signal: `on start` must be able to re-init state
// and keep going in the same handler (implicit emit-ordering is a known bug
// pattern - see the bug codex).
mod resetState() {
  phase = PH_LOBBY
  vPlayerCount = 0
  presidentSeat = -1 chancellorSeat = -1 nomineeSeat = -1
  lastPres = -1 lastChanc = -1 rotationSeat = -1 specialNext = -1
  libEnacted = 0 fascEnacted = 0 tracker = 0
  vetoBlocked = 0 execPower = 0 execPicked = -1 selHi = -1 selTarget = -1 wArm = false
  winner = 0 votesLeft = 0
  roundPending = false
  resetPending = false
  readyMask = 0 // ids/names/players/hereMask are live caches - NOT reset here
  playingMask = 0
  deadMask = 0
  seatRole.fill(0)
  votedMask = 0
  votedYesMask = 0
  votePassed = false
  investigatedMask = 0
  drawPile.clear() discardPile.clear() hand.clear() dealt.clear() scratchSeats.clear()
  inputQueue.clear()
  activityLog.fill("") // blank all 8 slots (keep the length; see the decl)
  logText = "" // wipe the feed (new game, or table emptied after a match)
  vVoteYes = 0 vVoteNo = 0 vIsHitler = 0 vIsLiberal = 0 vIsFascist = 0
  roleIntel.fill("")
  boardDirty = true
}

// ---- Game start ----
// Lock a seat into the game if its cache shows a live occupant. Returns 1 if so.
mod captureSeatAt(i: int) -> int {
  if ids[i] != "" {
    playingMask = playingMask | (1 << i)
    return 1
  }
  playingMask = playingMask & ~(1 << i)
  return 0
}

// ---- Role deal + night phase ----
// (Declaration order below follows WS021 declare-before-use: helper mods
// must precede the mods that call them, so the raw call chain
// dealRoles->assignRoleAt / fascistNames->fascNameAt / buildIntel->buildIntelAt
// is reordered callee-first below.)

mod assignRoleAt(i: int, k: *int) {
  if (playingMask & (1 << i)) {
    seatRole[i] = dealt[k]
    k = k + 1
  }
}

// Compose the role list for n players (1 Hitler + fascists + liberals), shuffle,
// then assign to playing seats in ascending order.
chip dealRoles() {
  dealt.clear()
  dealt.push(R_HITLER)
  array fs: int[]
  fs.clear()
  fs.resize(fascistCount(vPlayerCount), R_FASC)
  dealt.append(fs)
  array ls: int[]
  ls.clear()
  ls.resize(liberalCount(vPlayerCount), R_LIB)
  dealt.append(ls)
  dealt.shuffle()
  var k: int = 0
  assignRoleAt(0, k) assignRoleAt(1, k) assignRoleAt(2, k) assignRoleAt(3, k) assignRoleAt(4, k)
  assignRoleAt(5, k) assignRoleAt(6, k) assignRoleAt(7, k) assignRoleAt(8, k) assignRoleAt(9, k)
}

mod fascNameAt(i: int, includeHitler: bool, s: *string) {
  if (playingMask & (1 << i)) {
    if seatRole[i] == R_FASC {
      if s != "" { s = s .. ", " }
      s = s .. "<b>${seatName(i)}</>"
    }
    if includeHitler && seatRole[i] == R_HITLER {
      if s != "" { s = s .. ", " }
      s = s .. '<color="ff0"><b>${seatName(i)}</></> (Hitler)'
    }
  }
}

// Names of all fascists (optionally including Hitler), for intel lines.
mod fascistNames(includeHitler: bool) -> string {
  var s: string = ""
  fascNameAt(0, includeHitler, s) fascNameAt(1, includeHitler, s) fascNameAt(2, includeHitler, s)
  fascNameAt(3, includeHitler, s) fascNameAt(4, includeHitler, s) fascNameAt(5, includeHitler, s)
  fascNameAt(6, includeHitler, s) fascNameAt(7, includeHitler, s) fascNameAt(8, includeHitler, s)
  fascNameAt(9, includeHitler, s)
  return s
}

// One seat's intel = a pure select over the three precomputed variants.
mod setIntelAt(i: int, libIntel: string, fascIntel: string, hitlerIntel: string) {
  roleIntel[i] = if (playingMask & (1 << i)) == 0 then ""
    else if seatRole[i] == R_LIB then libIntel
    else if seatRole[i] == R_FASC then fascIntel
    else hitlerIntel
}

// Per-seat private role card + intel. 5-6p: fascist and Hitler know each other.
// 7-10p: fascists know each other + Hitler; Hitler knows nobody.
// The three role variants are built ONCE and dealt by select - the old shape
// called fascistNames (10 seatName chains) inside a per-seat mod, inlining it
// up to 20x.
chip buildIntel() {
  let team = fascistNames(true) // fascists: teammates + marked Hitler
  let lone = fascistNames(false) // Hitler at 5-6p: the lone fascist
  let libIntel = "You are ${roleText(R_LIB)}"
  let fascIntel = "You are ${roleText(R_FASC)}<br>Team: " .. team
  let hitlerIntel = if vPlayerCount <= 6
  then "You are ${roleText(R_HITLER)}<br>Your fascist: " .. lone
    else "You are ${roleText(R_HITLER)}"
  setIntelAt(0, libIntel, fascIntel, hitlerIntel) setIntelAt(1, libIntel, fascIntel, hitlerIntel)
  setIntelAt(2, libIntel, fascIntel, hitlerIntel) setIntelAt(3, libIntel, fascIntel, hitlerIntel)
  setIntelAt(4, libIntel, fascIntel, hitlerIntel) setIntelAt(5, libIntel, fascIntel, hitlerIntel)
  setIntelAt(6, libIntel, fascIntel, hitlerIntel) setIntelAt(7, libIntel, fascIntel, hitlerIntel)
  setIntelAt(8, libIntel, fascIntel, hitlerIntel) setIntelAt(9, libIntel, fascIntel, hitlerIntel)
}

chip beginNight() {
  dealRoles()
  buildIntel()
  readyMask = 0 // role-ack readies accumulate here, shown via isReady
  phase = PH_NIGHT
  boardDirty = true
}

// Capture the live roster and deal in. Called by maybeStart once the lobby has
// 5-10 all-ready seats. The count is checked from the cache BEFORE resetState,
// so an out-of-range attempt never wipes everyone's ready flags.
@label("Game Start") chip startGame() {
  let n = seatedNow
  if n < 5 || n > 10 { return }
  resetState()
  captureSeatAt(0) captureSeatAt(1) captureSeatAt(2) captureSeatAt(3) captureSeatAt(4)
  captureSeatAt(5) captureSeatAt(6) captureSeatAt(7) captureSeatAt(8) captureSeatAt(9)
  vPlayerCount = n
  deckInit(drawPile, discardPile)
  boardDirty = true
  logLine("<b>Secret Hitler</> - ${n} players. Dealing roles...")
  beginNight()
}

// ---- Lobby: ready-up + auto-start ----
// readyMask is cleared whenever a seat empties, so it stays a subset of the
// occupied seats: "all seated ready" is BitCount(readyMask) == seatedNow.

// Auto-start when 5-10 seated AND every seated player is ready. Works from the
// LOBBY and from a finished game's reveal (GAMEOVER) - a rematch.
mod maybeStart() {
  if phase != PH_LOBBY && phase != PH_GAMEOVER { return }
  if seatedNow >= 5 && seatedNow <= 10 && BitCount(readyMask) == seatedNow {
    startGame()
  }
}

// LOBBY W toggles the presser's ready flag.
mod toggleReady(i: int) {
  let bit = 1 << i
  readyMask = readyMask ^ bit
  players[i].ShowStatusMessage(if (readyMask & bit) then "Ready" else "Not ready")
  boardDirty = true
}

// LOBBY private prompt for the seat's occupant.
mod lobbyPrompt(i: int) -> string {
  let seated = seatedNow
  let ready = BitCount(readyMask)
  let need = if seated < 5 then " - need ${5 - seated} more seated"
    else if seated > 10 then " - too many (max 10)"
    else " - starts when all ready"
  return if (readyMask & (1 << i))
  then 'You are <color="8f8"><b>READY</></> (${ready}/${seated})<br>Tap <b>W</> to unready${need}'
    else 'You are <color="f66"><b>NOT READY</></> (${ready}/${seated})<br>Tap <b>W</> to ready up${need}'
}

// ---- Service loop: one seat per tick (occupancy watch + HUD re-emit) ----
array roleIntel: string[] = ["", "", "", "", "", "", "", "", "", ""] // per-seat private intel, built at deal time

buffer tick: int = tick + (seatedNow > 0)
// Public phase banner (same text for everyone; private bits go via promptFor).
mod phaseBanner() -> string {
  return if phase == PH_LOBBY then '<size="42"><font="Gotfridus">SECRET HITLER</></><br>Sit down and tap <b>W</> to ready up (5-10 players)'
    else if phase == PH_NIGHT then "<b>NIGHT PHASE</> - check your role, tap <b>W</> to continue (${vPlayerCount - BitCount(readyMask)} left)"
    else if phase == PH_NOMINATE then "President <b>${seatName(presidentSeat)}</> is nominating a Chancellor"
    else if phase == PH_VOTE then "Vote on President <b>${seatName(presidentSeat)}</> + Chancellor <b>${seatName(nomineeSeat)}</>"
    else if phase == PH_LEG_PRES then "President <b>${seatName(presidentSeat)}</> is legislating..."
    else if phase == PH_LEG_CHANC then "Chancellor <b>${seatName(chancellorSeat)}</> is legislating..."
    else if phase == PH_VETO then "Chancellor proposes a <b>VETO</> - President decides"
    else if phase == PH_EXEC then "President <b>${seatName(presidentSeat)}</>: ${powerName(execPower)}"
    else if winner == WIN_LIB then '<color="68f"><b>LIBERALS WIN</></>'
    else '<color="f66"><b>FASCISTS WIN</></>'
}

// Context prompt for seat i (private). Selection UIs are drawn inline here so a
// hot-swapped occupant immediately sees the seat's pending action.
mod promptFor(i: int) -> string {
  if phase == PH_GAMEOVER { return "" } // reveal banner says it all; dead may talk again
  if (deadMask & (1 << i)) { return '<color="888">You are dead. No talking.</>' }
  // During the legislative session only the president and chancellor may not
  // talk (they could otherwise signal each other) - private to them, not public.
  let inLeg = phase == PH_LEG_PRES || phase == PH_LEG_CHANC || phase == PH_VETO
  let govHere = i == presidentSeat || i == chancellorSeat
  let noTalk = if inLeg && govHere then '<color="f66"><b>No talking!</></><br>' else ""
  if phase == PH_NIGHT {
    return if (readyMask & (1 << i)) then "Waiting for others..." else "Tap <b>W</> to acknowledge your role"
  }
  if phase == PH_NOMINATE && i == presidentSeat {
    return if wArm then "Nominate <b>${seatName(selTarget)}</>?<br>Press <b>W</> again to confirm (or <b>A/D</> to change)"
      else "Nominate a Chancellor: <b>A/D</> cycle, <b>W</> twice to confirm<br>-> <b>${seatName(selTarget)}</>"
  }
  if phase == PH_VOTE {
    if votesLeft > 0 {
      return if (votedMask & (1 << i)) == 0 then 'Vote: tap <b>A</> = <color="8f8">Ja</> / <b>D</> = <color="f88">Nein</>'
        else "Vote recorded (${votesLeft} outstanding) - tap A/D to change it"
    }
    let outcome = if votePassed then '<color="8f8">Ja - government elected</>' else '<color="f88">Nein - election fails</>'
    return if (readyMask & (1 << i)) then "${outcome}<br>Waiting for others..."
      else "${outcome}<br>Tap <b>W</> to continue"
  }
  if phase == PH_LEG_PRES && i == presidentSeat {
    return noTalk .. "Discard one policy (<b>A/W/D</>, tap the same again to confirm):<br>"
      .. cardFanText(hand, 3, selHi)
  }
  if phase == PH_LEG_CHANC && i == chancellorSeat {
    let veto = if fascEnacted >= VETO_AT && vetoBlocked == 0 then "<br><b>W</> = propose VETO" else ""
    return noTalk .. "Pass one policy to enact (<b>A/D</>, tap again to confirm):<br>"
      .. cardFanText(hand, 2, selHi)
      .. veto
  }
  if phase == PH_VETO && i == presidentSeat {
    let hi = if selHi == 0 then "[ AGREE ]  REFUSE" else if selHi == 1 then "AGREE  [ REFUSE ]" else "AGREE / REFUSE"
    return noTalk .. "Chancellor wishes to veto. <b>A</>=agree <b>D</>=refuse (tap again to confirm)<br>"
      .. hi
  }
  if phase == PH_EXEC && i == presidentSeat {
    let contW = if wArm then "Press <b>W</> again to continue" else "Tap <b>W</> twice to continue"
    if execPicked >= 0 && execPower == PW_INVESTIGATE {
      let party = if seatRole[execPicked] == R_LIB then '<color="68f">LIBERAL</>' else '<color="f66">FASCIST</>'
      return "<b>${seatName(execPicked)}</> is party: ${party}<br>${contW} (you may lie)"
    }
    if execPicked >= 0 && execPower == PW_PEEK {
      let n = drawPile.length()
      return "Top of deck (next drawn first):<br>${policyText(drawPile[n - 1])} ${policyText(drawPile[n - 2])} ${policyText(drawPile[n - 3])}<br>${contW}"
    }
    return if wArm then "${powerName(execPower)} <b>${seatName(selTarget)}</>?<br>Press <b>W</> again to confirm (or <b>A/D</> to change)"
      else "${powerName(execPower)}: <b>A/D</> cycle, <b>W</> twice to confirm<br>-> <b>${seatName(selTarget)}</>"
  }
  // The waiting government member (e.g. chancellor while the president acts)
  // still gets the no-talk reminder.
  if inLeg && govHere { return noTalk }
  return ""
}

// The seat's live character port (one 10-way select; used once/tick).
mod seatCharAt(i: int) -> character {
  return if i == 0 then player0
    else if i == 1 then player1
    else if i == 2 then player2
    else if i == 3 then player3
    else if i == 4 then player4
    else if i == 5 then player5
    else if i == 6 then player6
    else if i == 7 then player7
    else if i == 8 then player8
    else player9
}

// Full HUD redraw for one seat, targeting its occupant character.
mod drawSeatHud(i: int, ch: character) {
  hudBanner(ch, phaseBanner())
  hudActivity(ch, logText) // rolling event feed, every seat occupant
  if phase == PH_LOBBY {
    hudPrompt(ch, lobbyPrompt(i))
    return
  }
  // GAMEOVER: reveal stays up; players ready up for a rematch (lobbyPrompt).
  if phase == PH_GAMEOVER {
    if (playingMask & (1 << i)) { hudRole(ch, roleIntel[i]) }
    hudPrompt(ch, lobbyPrompt(i))
    return
  }
  // Stuck live game (one player left): offer the reset.
  if seatedNow <= 1 {
    if (playingMask & (1 << i)) { hudRole(ch, roleIntel[i]) }
    hudPrompt(ch, "You are the last player - tap <b>W</> to reset.")
    return
  }
  if (playingMask & (1 << i)) {
    hudRole(ch, roleIntel[i])
    hudPrompt(ch, promptFor(i))
  }
  if phase == PH_VOTE {
    hudTally(ch, if votesLeft > 0 then "${aliveCount - votesLeft}/${aliveCount} votes in"
      else "${BitCount(readyMask)}/${aliveCount} ready to continue")
  }
}

// Reconcile the seat's identity cache from LIVE occupancy, then redraw its HUD.
// Reading live occupancy here (not just the on-playerN cache) is what guarantees
// a seated player always gets their HUD, even if the port event never fired.
chip serviceSeat(i: int) {
  logText = '${activityLog[0]}<br>${activityLog[1]}<br>${activityLog[2]}<br>${activityLog[3]}<br>${activityLog[4]}<br>${activityLog[5]}<br>${activityLog[6]}<br>${activityLog[7]}'
  let ch = seatCharAt(i)
  let uid = ch.GetUserId()
  if uid != ids[i] { cacheSeat(i, ch) }
  if (hereMask & (1 << i)) { drawSeatHud(i, ch) } // pure occupancy - never draws an empty seat
}

// (Seat servicing happens at the end of the single `on tick` below, after
// input processing, so the HUD always draws post-input state.)

// ---- First-president pick + STUBS (filled by Tasks 9-12; keep signatures
// exact) declared here, ahead of pickFirstPresident/tapW/tapA/tapD, to
// satisfy WS021 declare-before-use. ----
mod pushPlayingAt(i: int) {
  if (playingMask & (1 << i)) {
    scratchSeats.push(i)
  }
}

// New round entry: president is set by the caller (rotation / special election).
mod beginNominate() {
  nomineeSeat = -1
  chancellorSeat = -1
  selHi = -1
  wArm = false
  vetoBlocked = 0
  readyMask = 0 // clears the night role-ack (or any) readies as play begins
  selTarget = nextTarget(presidentSeat, 1, TGT_NOMINEE, presidentSeat, playingMask, deadMask, investigatedMask, lastPres, lastChanc, aliveCount)
  phase = PH_NOMINATE
  boardDirty = true
  logLine("President <b>${seatName(presidentSeat)}</> must nominate a Chancellor.")
}
mod nominateCycle(dir: int) {
  selTarget = nextTarget(selTarget, dir, TGT_NOMINEE, presidentSeat, playingMask, deadMask, investigatedMask, lastPres, lastChanc, aliveCount)
  boardDirty = true // move the chancellor placard as the president cycles
}
mod beginVote() {
  votedMask = 0
  votedYesMask = 0
  readyMask = 0 // cleared so the post-vote acknowledgement starts fresh
  votesLeft = aliveCount
  phase = PH_VOTE
  boardDirty = true
  logLine("Vote: President <b>${seatName(presidentSeat)}</> + Chancellor <b>${seatName(nomineeSeat)}</>. Tap A = Ja, D = Nein.")
}

mod nominateConfirm() {
  if selTarget < 0 { return }
  nomineeSeat = selTarget
  beginVote()
}
// Random first president: shuffle the playing-seat list, take the first.
mod pickFirstPresident() {
  scratchSeats.clear()
  pushPlayingAt(0) pushPlayingAt(1) pushPlayingAt(2) pushPlayingAt(3) pushPlayingAt(4)
  pushPlayingAt(5) pushPlayingAt(6) pushPlayingAt(7) pushPlayingAt(8) pushPlayingAt(9)
  scratchSeats.shuffle()
  rotationSeat = scratchSeats[0]
  presidentSeat = rotationSeat
  beginNominate()
}

mod nightAck(i: int) {
  toggleReady(i) // sets isReady; beginNominate clears it once everyone's in
  if BitCount(readyMask) >= vPlayerCount {
    pickFirstPresident()
  }
}

// ---- Legislative session (Task 11) ----
// (Declared here, ahead of the "Per-seat W/A/D taps" section below, because
// tapA/tapD/tapW call legPresPick/legChancPick/chancVetoPropose/vetoPick
// directly - those mods must precede their callers per WS021. Those four in
// turn reach endGame/chaosEnact/nextRound/applyEnact/beginExec, so those had
// to move up here too (callee-first, same resolution Task 10 used for
// resolveVotes's callees). endGame/chaosEnact/nextRound were relocated from
// their prior post-dispatch position - see the note in the "---- Voting ----"
// section further down for what's left there.)
mod beginLegislate() {
  deckDraw3(drawPile, hand)
  selHi = -1
  phase = PH_LEG_PRES
  boardDirty = true
}

// President taps A/W/D (0/1/2). First tap highlights; same card again DISCARDS it.
// President discards ONE of the three policies: press A/W/D to highlight, press
// the same again to confirm the discard; the remaining two pass to the chancellor.
mod legPresPick(idx: int) {
  if selHi != idx {
    selHi = idx // first press highlights
    boardDirty = true
    return
  }
  discardPile.push(hand[idx])
  hand.remove(idx)
  selHi = -1
  phase = PH_LEG_CHANC
  boardDirty = true
}

mod revealNameAt(i: int, s: *string) {
  if (playingMask & (1 << i)) {
    let dead = if (deadMask & (1 << i)) then " (dead)" else ""
    s = s .. "${seatName(i)}: ${roleText(seatRole[i])}${dead}  "
  }
}

mod rosterReveal() -> string {
  var s: string = ""
  revealNameAt(0, s) revealNameAt(1, s) revealNameAt(2, s) revealNameAt(3, s) revealNameAt(4, s)
  revealNameAt(5, s) revealNameAt(6, s) revealNameAt(7, s) revealNameAt(8, s) revealNameAt(9, s)
  return s
}

// ---- Game over ----
// Reveal flags publish via refreshBoard's PH_GAMEOVER branch. State stays
// frozen for post-game discussion until the reset chain fires.
mod endGame(w: int) {
  winner = w
  phase = PH_GAMEOVER
  readyMask = 0 // reveal stays up; players ready up again for a rematch
  vIsHitler = 0
  vIsLiberal = 0
  vIsFascist = 0
  boardDirty = true
  let side = if w == WIN_LIB then '<color="68f"><b>LIBERALS WIN</></>' else '<color="f66"><b>FASCISTS WIN</></>'
  logLine(side)
  logLine("Roles: " .. rosterReveal())
}

// ---- Executive actions ----
// PEEK needs no target: execPicked goes straight to the "result shown, W to
// continue" stage. Target powers start in picking stage (execPicked = -1).
mod beginExec(pw: int) {
  execPower = pw
  execPicked = -1
  wArm = false
  phase = PH_EXEC
  if pw == PW_PEEK {
    execPicked = presidentSeat // any >=0 value = result stage
  } else {
    let mode = if pw == PW_INVESTIGATE then TGT_INVESTIGATE else TGT_ANY
    selTarget = nextTarget(presidentSeat, 1, mode, presidentSeat, playingMask, deadMask, investigatedMask, lastPres, lastChanc, aliveCount)
  }
  boardDirty = true
  logLine("Presidential power: <b>${powerName(pw)}</>")
}

// Three failed governments: the populace enacts the top policy. No power, the
// tracker resets, term limits are forgotten.
mod chaosEnact() {
  let card = deckTopCard(drawPile)
  tracker = 0
  lastPres = -1
  lastChanc = -1
  logLine("<b>CHAOS</> - the populace enacts ${policyText(card)}!")
  if card == POL_LIB {
    libEnacted = libEnacted + 1
  } else {
    fascEnacted = fascEnacted + 1
  }
  deckReshuffleIfLow(drawPile, discardPile)
  boardDirty = true
  let w = policyWinner(libEnacted, fascEnacted)
  if w != WIN_NONE {
    endGame(w)
  }
}

/// Advance the presidency: pending special election wins, else normal rotation.
chip nextRound() {
  if specialNext >= 0 {
    presidentSeat = specialNext
    specialNext = -1
  } else {
    rotationSeat = nextAlive(rotationSeat, playingMask, deadMask)
    presidentSeat = rotationSeat
  }
  beginNominate()
}

/// Shared enactment path (elected governments; chaos has its own in chaosEnact).
/// A `mod`, NOT a `chip`: it's called from `legChancPick` which runs inside the
/// input-dispatch anon chip, and a chip-instance call doesn't thread its exec
/// across that nested-chip boundary (the discard ran but the enact never fired).
mod applyEnact(card: int) {
  if card == POL_LIB {
    libEnacted = libEnacted + 1
  } else {
    fascEnacted = fascEnacted + 1
  }
  tracker = 0
  deckReshuffleIfLow(drawPile, discardPile)
  boardDirty = true
  logLine("Government enacts ${policyText(card)} (${libEnacted}L / ${fascEnacted}F)")
  let w = policyWinner(libEnacted, fascEnacted)
  if w != WIN_NONE {
    endGame(w)
    return
  }
  if card == POL_FASC {
    let pw = powerAt(vPlayerCount, fascEnacted)
    if pw != PW_NONE {
      beginExec(pw)
      return
    }
  }
  roundPending = true
}

// Chancellor taps A/D (0/1). First tap highlights; same card again ENACTS it.
mod legChancPick(idx: int) {
  if selHi != idx {
    selHi = idx
    return
  }
  let card = hand[idx]
  hand.remove(idx)
  discardPile.push(hand[0])
  hand.clear()
  applyEnact(card)
}

// W in the chancellor fan: propose a veto (only once the power is unlocked and
// not already refused this session).
mod chancVetoPropose() {
  if fascEnacted < VETO_AT || vetoBlocked == 1 { return }
  selHi = -1
  phase = PH_VETO
  boardDirty = true
  logLine("Chancellor <b>${seatName(chancellorSeat)}</> wishes to veto this agenda.")
}

// President: 0 = agree (discard both, tracker advances), 1 = refuse.
mod vetoPick(idx: int) {
  if selHi != idx {
    selHi = idx
    return
  }
  selHi = -1
  if idx == 1 {
    vetoBlocked = 1
    phase = PH_LEG_CHANC
    boardDirty = true
    logLine("President <b>${seatName(presidentSeat)}</> refuses the veto. The Chancellor must enact.")
    return
  }
  discardPile.push(hand[0])
  discardPile.push(hand[1])
  hand.clear()
  deckReshuffleIfLow(drawPile, discardPile)
  logLine("President <b>${seatName(presidentSeat)}</> agrees to the veto. Both policies discarded.")
  tracker = trackerNext(tracker)
  if isChaos(tracker) {
    chaosEnact()
    if phase == PH_GAMEOVER { return }
  }
  boardDirty = true
  roundPending = true
}

mod execCycle(dir: int) {
  if execPicked >= 0 { return } // result stage: only W advances
  let mode = if execPower == PW_INVESTIGATE then TGT_INVESTIGATE else TGT_ANY
  selTarget = nextTarget(selTarget, dir, mode, presidentSeat, playingMask, deadMask, investigatedMask, lastPres, lastChanc, aliveCount)
  boardDirty = true // move the target highlight as the president cycles
}

mod execConfirm() {
  // Result stage (peek shown / investigation shown): W continues the game.
  if execPicked >= 0 {
    execPicked = -1
    roundPending = true
    return
  }
  if selTarget < 0 { return }
  if execPower == PW_INVESTIGATE {
    execPicked = selTarget
    investigatedMask = investigatedMask | (1 << selTarget)
    logLine("President <b>${seatName(presidentSeat)}</> investigates <b>${seatName(selTarget)}</>.")
    // Result is rendered privately by promptFor; stay in PH_EXEC result stage.
    return
  }
  if execPower == PW_SPECIAL {
    specialNext = selTarget
    logLine("Special Election: <b>${seatName(selTarget)}</> will be the next Presidential Candidate.")
    roundPending = true
    return
  }
  if execPower == PW_EXECUTE {
    deadMask = deadMask | (1 << selTarget)
    logLine("President <b>${seatName(presidentSeat)}</> formally executes <b>${seatName(selTarget)}</>.")
    boardDirty = true
    let w = executionWinner(seatRole[selTarget])
    if w != WIN_NONE {
      logLine("<b>${seatName(selTarget)}</> was <b>HITLER</>!")
      endGame(w)
      return
    }
    roundPending = true
    return
  }
}

// ---- Voting (via InputReader A/D taps - the seat readers ARE the ballot) ----
// Count + publish. Votes reveal simultaneously here and only here. The board
// then HOLDS the revealed ballots (still PH_VOTE, votesLeft==0) until every
// living player taps W to acknowledge - voteAck() hides them and runs the
// deferred transition (legislate on Ja, next round on Nein).
mod resolveVotes() {
  vVoteYes = votedYesMask
  vVoteNo = votedMask & ~votedYesMask
  let yes = BitCount(votedYesMask)
  let passed = yes * 2 > aliveCount
  votePassed = passed
  readyMask = 0 // reuse readyMask for the result acknowledgement
  if passed {
    chancellorSeat = nomineeSeat
    logLine("<b>Ja!</> (${yes}/${aliveCount}) Government elected.")
    let w = electionWinner(fascEnacted, seatRole[chancellorSeat])
    if w != WIN_NONE {
      logLine("Chancellor <b>${seatName(chancellorSeat)}</> is <b>HITLER</>.")
      endGame(w) // game over reveals immediately - no acknowledgement gate
      return
    }
    if fascEnacted >= HITLER_ZONE {
      logLine("Chancellor <b>${seatName(chancellorSeat)}</> is confirmed NOT Hitler.")
    }
    lastPres = presidentSeat
    lastChanc = chancellorSeat
  } else {
    logLine("<b>Nein.</> (${yes}/${aliveCount}) Election fails.")
    tracker = trackerNext(tracker)
    if isChaos(tracker) {
      chaosEnact()
      if phase == PH_GAMEOVER { return }
    }
  }
  boardDirty = true
}

// One living player toggles ready on the revealed result (shown via isReady,
// same readyMask as the lobby). The last ready clears the ballots and advances.
mod voteAck(i: int) {
  toggleReady(i)
  if BitCount(readyMask & playingMask & ~deadMask) >= aliveCount {
    readyMask = 0
    vVoteYes = 0
    vVoteNo = 0
    if votePassed { beginLegislate() } else { roundPending = true }
  }
}

// A ballot arrives from the seat's own InputReader, so the presser IS the seat
// occupant by construction - no identity check needed. Last tap wins until the
// final outstanding ballot lands; then everything publishes at once.
mod castVote(i: int, v: int) {
  if phase != PH_VOTE { return }
  if (playingMask & (1 << i)) == 0 || (deadMask & (1 << i)) { return }
  let bit = 1 << i
  if (votedMask & bit) == 0 {
    votesLeft = votesLeft - 1
  }
  votedMask = votedMask | bit
  votedYesMask = if v == 1 then votedYesMask | bit else votedYesMask & ~bit
  players[i].ShowStatusMessage(if v then "Vote recorded: Ja" else "Vote recorded: Nein")
  // Publish the "has voted" both-bits indicator for this seat immediately;
  // resolveVotes overwrites with the real split when the last ballot lands.
  boardDirty = true
  if votesLeft <= 0 {
    resolveVotes()
  }
}

@label("Player Input")
chip {
  // ---- Per-seat W/A/D taps (InputReader rising edges past the 0.5 deadzone) ----
  // Readers are fed the seat ports directly, so they follow the occupant.
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
  // One-tick-delayed raw axes per seat; the threshold + edge logic lives in
  // seatEdges below, so each seat is one buffer pair + one call, not six
  // booleans + six buffers + three edge checks.
  buffer f0p: float = inp0.Forward
  buffer f1p: float = inp1.Forward
  buffer f2p: float = inp2.Forward
  buffer f3p: float = inp3.Forward
  buffer f4p: float = inp4.Forward
  buffer f5p: float = inp5.Forward
  buffer f6p: float = inp6.Forward
  buffer f7p: float = inp7.Forward
  buffer f8p: float = inp8.Forward
  buffer f9p: float = inp9.Forward
  buffer r0p: float = inp0.Right
  buffer r1p: float = inp1.Right
  buffer r2p: float = inp2.Right
  buffer r3p: float = inp3.Right
  buffer r4p: float = inp4.Right
  buffer r5p: float = inp5.Right
  buffer r6p: float = inp6.Right
  buffer r7p: float = inp7.Right
  buffer r8p: float = inp8.Right
  buffer r9p: float = inp9.Right
}

// Phase dispatch for the three keys. Later tasks fill the per-phase mods.
// ---- Input event queue ----
// The 30 edge checks only PUSH a small int - they never call into the phase
// machine. One event is dequeued per tick through dispatchInput's single call
// site, so tapW/tapA/tapD (and everything they reach) instantiate exactly once
// in the compiled graph instead of once per edge. Events survive bursts (two
// players tapping the same tick) by queueing; 60 events/second drain rate.
let KEY_W = 0
let KEY_A = 1
let KEY_D = 2

// Events are tagged with the phase they were meant for: a tap enqueued during
// NIGHT must not execute a tick later in NOMINATE (stale-intent bleed - e.g. a
// W-spamming president insta-confirming the default nominee). Dequeue drops
// any event whose phase no longer matches.
mod queueInput(i: int, key: int) {
  if inputQueue.length() < 32 {
    inputQueue.push(phase * 64 + i * 4 + key)
  }
}

// Per-seat edge detection: rising edge on Forward -> W, Right -> A/D past the
// deadzone, gated on live occupancy (empty seats' InputReaders alias the local
// player, so their edges must be dropped). `fprev`/`rprev` are last tick's
// buffered axes.
mod readSeatInput(i: int, fwd: float, rgt: float, fprev: float, rprev: float) {
  if (hereMask & (1 << i)) == 0 { return }
  if fwd > 0.5 && fprev <= 0.5 { queueInput(i, KEY_W) }
  if rgt < -0.5 && rprev >= -0.5 { queueInput(i, KEY_A) }
  if rgt > 0.5 && rprev <= 0.5 { queueInput(i, KEY_D) }
}

// Single dispatch site - keep it that way.
// Single phase dispatch for ALL keys - merged from the old tapW/tapA/tapD so
// every phase mod inlines exactly ONCE: the per-key variants (legPresPick
// 0/1/2, cycle -1/+1, vote ja/nein) are computed arguments, not three
// separately inlined call sites. Keep this the queue's only dispatch target.
mod tapKey(i: int, key: int) {
  // LOBBY and GAMEOVER: W readies / unreadies. All-ready starts a (new) game;
  // the post-game reveal stays up until then (or until everyone leaves).
  if phase == PH_LOBBY || phase == PH_GAMEOVER {
    if key == KEY_W { toggleReady(i) }
    return
  }
  // Stuck live game (everyone but one left): the last player resets to lobby.
  if key == KEY_W && seatedNow <= 1 {
    resetPending = true
    return
  }
  if (playingMask & (1 << i)) == 0 || (deadMask & (1 << i)) { return }
  if phase == PH_NIGHT {
    if key == KEY_W { nightAck(i) }
    return
  }
  if phase == PH_VOTE {
    // While ballots are outstanding, A/D cast; once revealed (votesLeft==0) W
    // acknowledges the result.
    if votesLeft > 0 {
      if key != KEY_W { castVote(i, if key == KEY_A then 1 else 0) }
    } else if key == KEY_W {
      voteAck(i)
    }
    return
  }
  if phase == PH_NOMINATE && i == presidentSeat {
    // Double-W: first W arms, second confirms; A/D moves and disarms.
    if key == KEY_W {
      if wArm { wArm = false nominateConfirm() } else { wArm = true boardDirty = true }
    } else {
      wArm = false
      nominateCycle(if key == KEY_A then -1 else 1)
    }
    return
  }
  if phase == PH_LEG_PRES && i == presidentSeat {
    legPresPick(if key == KEY_A then 0 else if key == KEY_W then 1 else 2)
    return
  }
  if phase == PH_LEG_CHANC && i == chancellorSeat {
    if key == KEY_W { chancVetoPropose() } else { legChancPick(if key == KEY_A then 0 else 1) }
    return
  }
  if phase == PH_VETO && i == presidentSeat {
    if key != KEY_W { vetoPick(if key == KEY_A then 0 else 1) }
    return
  }
  if phase == PH_EXEC && i == presidentSeat {
    // Double-W: first W arms, second confirms; A/D moves and disarms.
    if key == KEY_W {
      if wArm { wArm = false execConfirm() } else { wArm = true boardDirty = true }
    } else {
      wArm = false
      execCycle(if key == KEY_A then -1 else 1)
    }
    return
  }
}

@label("Tick") chip on tick {
  @label("Input Reading") chip {
    readSeatInput(0, inp0.Forward, inp0.Right, f0p, r0p)
    readSeatInput(1, inp1.Forward, inp1.Right, f1p, r1p)
    readSeatInput(2, inp2.Forward, inp2.Right, f2p, r2p)
    readSeatInput(3, inp3.Forward, inp3.Right, f3p, r3p)
    readSeatInput(4, inp4.Forward, inp4.Right, f4p, r4p)
    readSeatInput(5, inp5.Forward, inp5.Right, f5p, r5p)
    readSeatInput(6, inp6.Forward, inp6.Right, f6p, r6p)
    readSeatInput(7, inp7.Forward, inp7.Right, f7p, r7p)
    readSeatInput(8, inp8.Forward, inp8.Right, f8p, r8p)
    readSeatInput(9, inp9.Forward, inp9.Right, f9p, r9p)
  }

  // Pending round advance runs BEFORE the dequeue: by the time any queued
  // event dispatches, the phase has moved on and stale tags drop it.
  if roundPending {
    roundPending = false
    nextRound()
  }

  @label("Input queue") chip {
    if inputQueue.length() > 0 {
      let ev = inputQueue[0]
      inputQueue.remove(0)
      if ev / 64 == phase {
        tapKey((ev % 64) / 4, ev % 4)
      }
    }
  }

  // A tap this tick may have requested a reset - flush it (and pulse downstream).
  if resetPending {
    resetPending = false
    resetState()
  }
  // Lobby / post-game: drop ready bits for emptied seats, then auto-start when
  // 5-10 seated are all ready. A finished game's reveal only clears once
  // everyone has left (-> lobby) or everyone readies up (-> new game).
  if phase == PH_LOBBY || phase == PH_GAMEOVER {
    readyMask = readyMask & hereMask
    if phase == PH_GAMEOVER && seatedNow == 0 { resetPending = true }
    maybeStart()
  }

  if boardDirty {
    boardDirty = false
    refreshBoard()
  }
  serviceSeat(tick % 10) // occupancy watch + HUD; the tick counter IS the cursor
}

// (Voting now lives above the input section: ballots arrive as A/D taps from
// the per-seat InputReaders and flow through the same event queue as every
// other input - there are no separate ja/nein ports.)
