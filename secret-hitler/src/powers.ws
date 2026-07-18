// Secret Hitler - board constants and LUTs. Pure logic, tested by test_powers.ws.
// Power layout verified against the official print-and-play boards; see
// docs/superpowers/specs/2026-07-17-secret-hitler-circuit-design.md.

// -- Roles --
let R_LIB = 0
let R_FASC = 1
let R_HITLER = 2

// -- Policy tiles --
let POL_LIB = 0
let POL_FASC = 1

// -- Track lengths / thresholds --
let LIB_WIN = 5     // liberal policies to win
let FASC_WIN = 6    // fascist policies to win
let HITLER_ZONE = 3 // fascist policies after which Hitler-as-Chancellor wins / not-Hitler confirms
let VETO_AT = 5     // fascist policies that unlock the veto power

// -- Presidential powers --
let PW_NONE = 0
let PW_INVESTIGATE = 1
let PW_SPECIAL = 2
let PW_PEEK = 3
let PW_EXECUTE = 4

// Ordinary fascists (excluding Hitler) for a starting player count.
mod fascistCount(playerCount: int) -> int {
  return if playerCount >= 9 then 3
  else if playerCount >= 7 then 2
  else 1
}

mod liberalCount(playerCount: int) -> int {
  return playerCount - fascistCount(playerCount) - 1
}

// Power granted when the `slot`-th fascist policy is enacted (slot 1..6).
// 5-6p:  -, -, Peek,        Kill, Kill, -
// 7-8p:  -, Investigate, Special,  Kill, Kill, -
// 9-10p: Investigate, Investigate, Special, Kill, Kill, -
// Slot 6 is the fascist win; it grants no power (outcome.ws ends the game first).
mod powerAt(playerCount: int, slot: int) -> int {
  return if slot == 4 || slot == 5 then PW_EXECUTE
  else if playerCount <= 6 then (if slot == 3 then PW_PEEK else PW_NONE)
  else if slot == 3 then PW_SPECIAL
  else if slot == 2 then PW_INVESTIGATE
  else if slot == 1 && playerCount >= 9 then PW_INVESTIGATE
  else PW_NONE
}

mod powerName(pw: int) -> string {
  return if pw == PW_INVESTIGATE then "Investigate Loyalty"
  else if pw == PW_SPECIAL then "Call Special Election"
  else if pw == PW_PEEK then "Policy Peek"
  else if pw == PW_EXECUTE then "Execution"
  else "None"
}
