// Secret Hitler - win predicates. Pure logic, tested by test_outcome.ws.

import { FASC_WIN, HITLER_ZONE, LIB_WIN, R_HITLER } from "powers"

let WIN_NONE = 0
let WIN_LIB = 1
let WIN_FASC = 2

// Track win after any enactment (elected government or tracker chaos).
mod policyWinner(libEnacted: int, fascEnacted: int) -> int {
  return if libEnacted >= LIB_WIN then WIN_LIB
  else if fascEnacted >= FASC_WIN then WIN_FASC
  else WIN_NONE
}

// Fascists win the moment Hitler is elected chancellor in the Hitler zone.
mod electionWinner(fascEnacted: int, chancRole: int) -> int {
  return if fascEnacted >= HITLER_ZONE && chancRole == R_HITLER then WIN_FASC
  else WIN_NONE
}

// Liberals win the moment Hitler is executed.
mod executionWinner(targetRole: int) -> int {
  return if targetRole == R_HITLER then WIN_LIB
  else WIN_NONE
}
