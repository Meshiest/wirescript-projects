// Test: column-clear, all-up, sum. Pulse `start`; result to chat.
import { ST_EMPTY, ST_DOWN, ST_UP, packCell, cellState } from "cards"
import { columnClear, handAllUp, handSum } from "grid"

array g: int[]
array gv: int[]   // value mirror, exactly as main maintains cellVal
array scr: int[]  // handSum scratch (slice target)
array disc: int[]

let start = ReadBrickGrid()

// Fill a 12-cell hand at base 0 with all DOWN, value 0.
mod resetHand(a: int[]) {
  a.clear()
  a.resize(12, packCell(ST_DOWN, 0))
}
// Value mirror for a DOWN hand: every cell scores 0.
mod resetVals(a: int[]) {
  a.clear()
  a.resize(12, 0)
}

on start {
  disc.clear()
  resetHand(g) resetVals(gv)
  // column 0 = slots 0,4,8 all UP value 7 -> clears
  g[0] = packCell(ST_UP, 7) gv[0] = 7
  g[4] = packCell(ST_UP, 7) gv[4] = 7
  g[8] = packCell(ST_UP, 7) gv[8] = 7
  // column 1 = UP but not equal -> stays
  g[1] = packCell(ST_UP, 3) gv[1] = 3
  g[5] = packCell(ST_UP, 4) gv[5] = 4
  g[9] = packCell(ST_UP, 3) gv[9] = 3
  columnClear(g, gv, 0, disc)
  let c1 = if cellState(g[0]) != ST_EMPTY then "col0_not_cleared\n" else ""
  let c2 = if cellState(g[4]) != ST_EMPTY then "col0_mid_not_cleared\n" else ""
  let c3 = if cellState(g[1]) != ST_UP then "col1_wrongly_cleared\n" else ""
  let c4 = if disc.length() != 3 then "disc=${disc.length()} exp=3\n" else ""

  // handSum from the value mirror: col0 cleared -> 0, col1 sums 3+4+3 = 10.
  let c5 = if handSum(gv, scr, 0) != 10 then "sum=${handSum(gv, scr, 0)} exp=10\n" else ""

  // handAllUp: still DOWN cells remain -> false
  let c6 = if handAllUp(g, 0) then "allup_true exp=false\n" else ""
  // flip everything remaining up (or empty): make all 12 non-DOWN
  resetHand(g)
  g.fill(packCell(ST_UP, 1))
  let c7 = if !handAllUp(g, 0) then "allup_false exp=true\n" else ""

  // mixed column (2 equal UP + 1 DOWN) must NOT clear
  resetHand(g) resetVals(gv) disc.clear()
  g[3] = packCell(ST_UP, 5) gv[3] = 5
  g[7] = packCell(ST_UP, 5) gv[7] = 5
  // g[11] stays DOWN — column 3 is {3,7,11}
  columnClear(g, gv, 0, disc)
  let c8 = if cellState(g[3]) != ST_UP then "mixed_col_cleared\n" else ""
  let c9 = if disc.length() != 0 then "mixed_disc=${disc.length()} exp=0\n" else ""

  let msg = "${c1}${c2}${c3}${c4}${c5}${c6}${c7}${c8}${c9}"
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("skyjo_grid: ${ok}")
}
