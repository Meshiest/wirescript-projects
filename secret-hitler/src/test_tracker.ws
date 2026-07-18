// Test: election tracker helpers. Pulse `start`; result to chat.

import { isChaos, trackerNext } from "gov"

in start: exec

on start {
  let c1 = if trackerNext(0) != 1 then "next0=${trackerNext(0)} exp=1\n" else ""
  let c2 = if trackerNext(2) != 3 then "next2=${trackerNext(2)} exp=3\n" else ""
  let c3 = if isChaos(0) then "chaos0=true exp=false\n" else ""
  let c4 = if isChaos(2) then "chaos2=true exp=false\n" else ""
  let c5 = if !isChaos(3) then "chaos3=false exp=true\n" else ""
  let msg = c1 .. c2 .. c3 .. c4 .. c5
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("sh_tracker: ${ok}")
}
