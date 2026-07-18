// Test: win predicates. Pulse `start`; result to chat.

import { R_FASC, R_HITLER, R_LIB } from "powers"
import { WIN_FASC, WIN_LIB, WIN_NONE, electionWinner, executionWinner, policyWinner } from "outcome"

in start: exec

on start {
  // -- Policy track wins --
  let c1 = if policyWinner(4, 5) != WIN_NONE then "pol_4_5 exp=none\n" else ""
  let c2 = if policyWinner(5, 3) != WIN_LIB then "pol_5_3 exp=lib\n" else ""
  let c3 = if policyWinner(2, 6) != WIN_FASC then "pol_2_6 exp=fasc\n" else ""

  // -- Hitler elected chancellor: only at >=3 fascist policies --
  let c4 = if electionWinner(2, R_HITLER) != WIN_NONE then "elect_2_hitler exp=none\n" else ""
  let c5 = if electionWinner(3, R_HITLER) != WIN_FASC then "elect_3_hitler exp=fasc\n" else ""
  let c6 = if electionWinner(5, R_LIB) != WIN_NONE then "elect_5_lib exp=none\n" else ""
  let c7 = if electionWinner(4, R_FASC) != WIN_NONE then "elect_4_fasc exp=none\n" else ""

  // -- Execution: shooting Hitler ends it, anyone else doesn't --
  let c8 = if executionWinner(R_HITLER) != WIN_LIB then "exec_hitler exp=lib\n" else ""
  let c9 = if executionWinner(R_FASC) != WIN_NONE then "exec_fasc exp=none\n" else ""
  let c10 = if executionWinner(R_LIB) != WIN_NONE then "exec_lib exp=none\n" else ""

  let msg = c1 .. c2 .. c3 .. c4 .. c5 .. c6 .. c7 .. c8 .. c9 .. c10
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("sh_outcome: ${ok}")
}
