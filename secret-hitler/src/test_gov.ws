// Test: eligibility matrix, rotation, target cycling. Pulse `start`; result to chat.

import { TGT_ANY, TGT_INVESTIGATE, TGT_NOMINEE, allowedTarget, nextAlive, nextTarget } from "gov"

in start: exec

// Seat sets as bitmasks (bit i = seat i).
var playing: int = 0
var dead: int = 0
var inv: int = 0

// 5 players in seats 0,2,4,6,8; nobody dead or investigated.
mod setup5() {
  playing = (1 << 0) | (1 << 2) | (1 << 4) | (1 << 6) | (1 << 8)
  dead = 0
  inv = 0
}

on start {
  setup5()

  // -- nextAlive walks occupied seats ascending with wrap --
  let n1 = nextAlive(0, playing, dead)
  let c1 = if n1 != 2 then "nextAlive(0)=${n1} exp=2\n" else ""
  let n2 = nextAlive(8, playing, dead)
  let c2 = if n2 != 0 then "nextAlive(8)=${n2} exp=0\n" else ""

  // -- nextAlive skips the dead --
  dead = dead | (1 << 2)
  let n3 = nextAlive(0, playing, dead)
  let c3 = if n3 != 4 then "nextAlive_dead(0)=${n3} exp=4\n" else ""
  dead = dead & ~(1 << 2)

  // -- Nominee term limits: last pres + last chanc barred (>5 alive... here 5 alive
  //    so ONLY last chanc barred; then with 6 alive both barred) --
  // 5 alive: lastPres=4, lastChanc=6. Seat 4 IS eligible (exception), 6 is not.
  let e1 = allowedTarget(4, TGT_NOMINEE, 0, playing, dead, inv, 4, 6, 5)
  let c4 = if !e1 then "elig5_lastPres=false exp=true\n" else ""
  let e2 = allowedTarget(6, TGT_NOMINEE, 0, playing, dead, inv, 4, 6, 5)
  let c5 = if e2 then "elig5_lastChanc=true exp=false\n" else ""
  // 6 alive: both barred.
  playing = playing | (1 << 9)
  let e3 = allowedTarget(4, TGT_NOMINEE, 0, playing, dead, inv, 4, 6, 6)
  let c6 = if e3 then "elig6_lastPres=true exp=false\n" else ""
  let e4 = allowedTarget(6, TGT_NOMINEE, 0, playing, dead, inv, 4, 6, 6)
  let c7 = if e4 then "elig6_lastChanc=true exp=false\n" else ""
  playing = playing & ~(1 << 9)

  // -- Never self, never dead, never empty seat --
  let e5 = allowedTarget(0, TGT_NOMINEE, 0, playing, dead, inv, -1, -1, 5)
  let c8 = if e5 then "elig_self=true exp=false\n" else ""
  dead = dead | (1 << 8)
  let e6 = allowedTarget(8, TGT_ANY, 0, playing, dead, inv, -1, -1, 4)
  let c9 = if e6 then "elig_dead=true exp=false\n" else ""
  dead = dead & ~(1 << 8)
  let e7 = allowedTarget(1, TGT_ANY, 0, playing, dead, inv, -1, -1, 5)
  let c10 = if e7 then "elig_empty=true exp=false\n" else ""

  // -- Investigate: already-investigated barred --
  inv = inv | (1 << 4)
  let e8 = allowedTarget(4, TGT_INVESTIGATE, 0, playing, dead, inv, -1, -1, 5)
  let c11 = if e8 then "elig_inv=true exp=false\n" else ""
  let e9 = allowedTarget(6, TGT_INVESTIGATE, 0, playing, dead, inv, -1, -1, 5)
  let c12 = if !e9 then "elig_notinv=false exp=true\n" else ""
  inv = inv & ~(1 << 4)

  // -- nextTarget cycles in both directions, skipping barred seats --
  let t1 = nextTarget(2, 1, TGT_NOMINEE, 0, playing, dead, inv, -1, 4, 5)
  let c13 = if t1 != 6 then "nextTgt(+1 from2 skip4)=${t1} exp=6\n" else ""
  let t2 = nextTarget(2, -1, TGT_ANY, 0, playing, dead, inv, -1, -1, 5)
  let c14 = if t2 != 8 then "nextTgt(-1 from2)=${t2} exp=8\n" else ""

  let msg = c1 .. c2 .. c3 .. c4 .. c5 .. c6 .. c7 .. c8 .. c9 .. c10 .. c11 .. c12 .. c13 .. c14
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("sh_gov: ${ok}")
}
