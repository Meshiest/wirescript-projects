// Test: ender doubling + game-end helpers. Pulse `start`; result to chat.
import { enderScore, maxTotal, lowestSeat } from "scoring"

array rs: int[]
array tot: int[]

let start = ReadBrickGrid()

on start {
  // 3 players (mask 0b111 = 7). Ender = seat 0.
  rs.clear()
  rs.resize(8, 0)
  rs[0] = 5 rs[1] = 9 rs[2] = 12
  // ender strictly lowest -> NOT doubled
  let c1 = if enderScore(rs, 0, 7) != 5 then "lowest=${enderScore(rs, 0, 7)} exp=5\n" else ""
  // ender tied for lowest -> doubled
  rs[1] = 5
  let c2 = if enderScore(rs, 0, 7) != 10 then "tie=${enderScore(rs, 0, 7)} exp=10\n" else ""
  // ender beaten -> doubled
  rs[1] = 3
  let c3 = if enderScore(rs, 0, 7) != 10 then "beaten=${enderScore(rs, 0, 7)} exp=10\n" else ""
  // non-participating seats (mask excludes them) never force a double: seats 1,2
  // are participating and HIGHER than the ender, so the ender IS strictly lowest;
  // seat 3's low score is out of mask 7 and must be ignored.
  rs.fill(0)
  rs[0] = 5 rs[1] = 9 rs[2] = 12 rs[3] = 1 // seat 3 not in mask 7 — its 1 must be ignored
  let c4 = if enderScore(rs, 0, 7) != 5 then "nonpart=${enderScore(rs, 0, 7)} exp=5\n" else ""

  tot.clear()
  tot.resize(8, 0)
  tot[0] = 40 tot[1] = 105 tot[2] = 30
  let c5 = if maxTotal(tot, 7) != 105 then "max=${maxTotal(tot, 7)} exp=105\n" else ""
  let c6 = if lowestSeat(tot, 7) != 2 then "low=${lowestSeat(tot, 7)} exp=2\n" else ""
  // tie for lowest -> lowest index
  tot[2] = 30 tot[0] = 30
  let c7 = if lowestSeat(tot, 7) != 0 then "lowtie=${lowestSeat(tot, 7)} exp=0\n" else ""

  let msg = "${c1}${c2}${c3}${c4}${c5}${c6}${c7}"
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("skyjo_scoring: ${ok}")
}
