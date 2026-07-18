// Secret Hitler - eligibility, rotation, election tracker. Pure logic over seat
// bitmasks (bit i = seat i). Tested by test_gov.ws + test_tracker.ws.

// -- Target-picker modes --
let TGT_NOMINEE = 0     // chancellor nomination (term limits apply)
let TGT_INVESTIGATE = 1 // investigate loyalty (once per player per game)
let TGT_ANY = 2         // special election / execution (any other living player)

// Playing and not dead.
mod isAlive(seat: int, playing: int, dead: int) -> bool {
  let bit = 1 << seat
  return (playing & bit) && (dead & bit) == 0
}

// Is `seat` a legal pick for `mode`? Common bars: empty seat, dead, the sitting
// president (self). Term limits (TGT_NOMINEE): the last ELECTED chancellor is
// always barred; the last elected president is barred only while >5 are alive.
mod allowedTarget(seat: int, mode: int, presSeat: int, playing: int, dead: int, investigated: int, lastPres: int, lastChanc: int, aliveCount: int) -> bool {
  let alive = isAlive(seat, playing, dead)
  let notSelf = seat != presSeat
  let termOk = mode != TGT_NOMINEE || (seat != lastChanc && (aliveCount <= 5 || seat != lastPres))
  let notInvestigated = mode != TGT_INVESTIGATE || (investigated & (1 << seat)) == 0
  return alive && notSelf && termOk && notInvestigated
}

// Next playing, living seat clockwise (ascending index, wrap at 10). Unrolled
// 9-step probe; returns `start` if no other living seat exists.
mod nextAlive(start: int, playing: int, dead: int) -> int {
  let s1 = (start + 1) % 10
  if isAlive(s1, playing, dead) { return s1 }
  let s2 = (start + 2) % 10
  if isAlive(s2, playing, dead) { return s2 }
  let s3 = (start + 3) % 10
  if isAlive(s3, playing, dead) { return s3 }
  let s4 = (start + 4) % 10
  if isAlive(s4, playing, dead) { return s4 }
  let s5 = (start + 5) % 10
  if isAlive(s5, playing, dead) { return s5 }
  let s6 = (start + 6) % 10
  if isAlive(s6, playing, dead) { return s6 }
  let s7 = (start + 7) % 10
  if isAlive(s7, playing, dead) { return s7 }
  let s8 = (start + 8) % 10
  if isAlive(s8, playing, dead) { return s8 }
  let s9 = (start + 9) % 10
  if isAlive(s9, playing, dead) { return s9 }
  return start
}

// Next allowed seat from `start` in direction `dir` (+1 or -1), wrapping; -1 if
// no seat is allowed. Unrolled 10-step probe (includes `start` itself last so a
// lone valid pick stays reachable).
mod nextTarget(start: int, dir: int, mode: int, presSeat: int, playing: int, dead: int, investigated: int, lastPres: int, lastChanc: int, aliveCount: int) -> int {
  let s1 = (start + dir + 10) % 10
  if allowedTarget(s1, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s1 }
  let s2 = (start + dir * 2 + 20) % 10
  if allowedTarget(s2, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s2 }
  let s3 = (start + dir * 3 + 30) % 10
  if allowedTarget(s3, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s3 }
  let s4 = (start + dir * 4 + 40) % 10
  if allowedTarget(s4, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s4 }
  let s5 = (start + dir * 5 + 50) % 10
  if allowedTarget(s5, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s5 }
  let s6 = (start + dir * 6 + 60) % 10
  if allowedTarget(s6, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s6 }
  let s7 = (start + dir * 7 + 70) % 10
  if allowedTarget(s7, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s7 }
  let s8 = (start + dir * 8 + 80) % 10
  if allowedTarget(s8, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s8 }
  let s9 = (start + dir * 9 + 90) % 10
  if allowedTarget(s9, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s9 }
  let s10 = (start + dir * 10 + 100) % 10
  if allowedTarget(s10, mode, presSeat, playing, dead, investigated, lastPres, lastChanc, aliveCount) { return s10 }
  return -1
}

// -- Election tracker --
// Advances on every failed election (majority nein or tie) and every agreed
// veto. At 3 the country is thrown into chaos: enact the top policy, ignore
// its power, reset the tracker, forget term limits (main.ws owns those effects).
mod trackerNext(t: int) -> int {
  return t + 1
}

mod isChaos(t: int) -> bool {
  return t >= 3
}
