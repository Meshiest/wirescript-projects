// Test: influence/hand bit-math helpers. Pulse `start`; result to chat.

import { influenceOf, seatDead, slotValue, packSeat } from "hand"

in start: exec

on start {
  // seat 3 has lost its A card only
  let c1 = if influenceOf(3, 8, 0) != 1 then "influence_3_8_0=${influenceOf(3, 8, 0)} exp=1\n" else ""
  let c2 = if influenceOf(3, 0, 0) != 2 then "influence_3_0_0=${influenceOf(3, 0, 0)} exp=2\n" else ""
  let c3 = if influenceOf(3, 8, 8) != 0 then "influence_3_8_8=${influenceOf(3, 8, 8)} exp=0\n" else ""
  let c4 = if seatDead(3, 8, 0) then "seatDead_3_8_0=true exp=false\n" else ""
  let c5 = if !seatDead(3, 8, 8) then "seatDead_3_8_8=false exp=true\n" else ""
  // not playing reads 15 regardless of the rest
  let c6 = if slotValue(false, false, 4) != 15 then "slot_notplaying=${slotValue(false, false, 4)} exp=15\n" else ""
  // live influence is face-down
  let c7 = if slotValue(true, false, 4) != 0 then "slot_live=${slotValue(true, false, 4)} exp=0\n" else ""
  // lost influence reveals its role
  let c8 = if slotValue(true, true, 4) != 4 then "slot_lost=${slotValue(true, true, 4)} exp=4\n" else ""
  // coins saturate at 12
  let c9 = if packSeat(1, 4, 3) != (1 | (4 << 4) | (3 << 8)) then "pack=${packSeat(1, 4, 3)} exp=${1 | (4 << 4) | (3 << 8)}\n" else ""
  let c10 = if packSeat(0, 0, 20) != 12 << 8 then "pack_saturate=${packSeat(0, 0, 20)} exp=${12 << 8}\n" else ""
  let msg = "${c1}${c2}${c3}${c4}${c5}${c6}${c7}${c8}${c9}${c10}"
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("coup_hand: ${ok}")
}
