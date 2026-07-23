@fold

import { COL_OFF, COL_BACK, COL_BLUE, COL_CYAN, COL_GREEN, COL_YELLOW, COL_RED } from "cards"

// --- Inputs (wired in-game) ---
// The 12 card buttons form a 3-row x 4-column grid (like real Skyjo). Wire each
// button's `Character` output (who is pressing) to the matching cardN port.
// Index = row*4 + col, so 0-3 is the TOP ROW and a column is a vertical triple
// {c, c+4, c+8} (column-clear fires on a matching vertical triple):
//
//     card0   card1   card2   card3     <- top row
//     card4   card5   card6   card7
//     card8   card9   card10  card11    <- bottom row
//
@left in card0: character // top-left ... (row 0, col 0)
@left in card1: character
@left in card2: character
@left in card3: character // top-right (row 0, col 3)
@left in card4: character // (row 1, col 0)
@left in card5: character
@left in card6: character
@left in card7: character
@left in card8: character // bottom-left (row 2, col 0)
@left in card9: character
@left in card10: character
@left in card11: character // bottom-right (row 2, col 3)
@left in cardDrawn: character // 13th (drawn-card) button's Character output
@bottom in seat: character // the Seat brick's occupant (gates every press)
@top in update: exec // main pulses this after writing `cards`
@top in cards: int[] // 13 packed cells from main: 0-11 grid, 12 = drawn card

// --- Colour + text lookup tables, indexed by the packed cell value p ---
// p/16 = state (0 EMPTY, 1 DOWN, 2 UP); p%16-2 = value (-2..12); player sees p in
// {2 empty, 18 down, 32..46 up}. Built once (on the first `update`, before the
// cells are decoded) with fill-runs; the `update` handler then reads them -- one
// ArrayVar_Get per cell, replacing the cellColor/cellText band chains.
array colorLUT: color[]
array textLUT: string[]
var lutReady: bool = false
mod buildLUTs() {
  colorLUT.resize(16, COL_OFF)     // p 0..15  EMPTY
  colorLUT.resize(32, COL_BACK)    // p 16..31 DOWN ("?")
  colorLUT.resize(34, COL_BLUE)    // p 32,33  value -2,-1
  colorLUT.push(COL_CYAN)          // p 34     value 0
  colorLUT.resize(39, COL_GREEN)   // p 35..38 value 1..4
  colorLUT.resize(43, COL_YELLOW)  // p 39..42 value 5..8
  colorLUT.resize(47, COL_RED)     // p 43..46 value 9..12
  textLUT.resize(16, "")           // EMPTY -> blank
  textLUT.resize(32, "?")          // DOWN  -> "?"
  textLUT.push("-2") textLUT.push("-1") textLUT.push("O")
  textLUT.push("1") textLUT.push("2") textLUT.push("3") textLUT.push("4")
  textLUT.push("5") textLUT.push("6") textLUT.push("7") textLUT.push("8")
  textLUT.push("9") textLUT.push("10") textLUT.push("11") textLUT.push("12")
}

// --- Render cache: LUT-decode each cell's colour + text on `update`, cache them,
// and let the pure output bindings below read the caches. A value output can't
// sample an exec-only array-get directly (the game rejects that wiring at load),
// so the get runs here on the exec chain. Still one ArrayVar_Get per cell -- no
// cellColor/cellText band chain. ---
var vC0: color = Color(0.133, 0.133, 0.133, 1.0)  var vT0: string = ""
var vC1: color = Color(0.133, 0.133, 0.133, 1.0)  var vT1: string = ""
var vC2: color = Color(0.133, 0.133, 0.133, 1.0)  var vT2: string = ""
var vC3: color = Color(0.133, 0.133, 0.133, 1.0)  var vT3: string = ""
var vC4: color = Color(0.133, 0.133, 0.133, 1.0)  var vT4: string = ""
var vC5: color = Color(0.133, 0.133, 0.133, 1.0)  var vT5: string = ""
var vC6: color = Color(0.133, 0.133, 0.133, 1.0)  var vT6: string = ""
var vC7: color = Color(0.133, 0.133, 0.133, 1.0)  var vT7: string = ""
var vC8: color = Color(0.133, 0.133, 0.133, 1.0)  var vT8: string = ""
var vC9: color = Color(0.133, 0.133, 0.133, 1.0)  var vT9: string = ""
var vC10: color = Color(0.133, 0.133, 0.133, 1.0) var vT10: string = ""
var vC11: color = Color(0.133, 0.133, 0.133, 1.0) var vT11: string = ""
var vC12: color = Color(0.133, 0.133, 0.133, 1.0) var vT12: string = ""
on update {
  if !lutReady { lutReady = true buildLUTs() }   // one-time LUT build, before the reads
  let p0 = cards[0]   vC0 = colorLUT.get(p0).Value   vT0 = textLUT.get(p0).Value
  let p1 = cards[1]   vC1 = colorLUT.get(p1).Value   vT1 = textLUT.get(p1).Value
  let p2 = cards[2]   vC2 = colorLUT.get(p2).Value   vT2 = textLUT.get(p2).Value
  let p3 = cards[3]   vC3 = colorLUT.get(p3).Value   vT3 = textLUT.get(p3).Value
  let p4 = cards[4]   vC4 = colorLUT.get(p4).Value   vT4 = textLUT.get(p4).Value
  let p5 = cards[5]   vC5 = colorLUT.get(p5).Value   vT5 = textLUT.get(p5).Value
  let p6 = cards[6]   vC6 = colorLUT.get(p6).Value   vT6 = textLUT.get(p6).Value
  let p7 = cards[7]   vC7 = colorLUT.get(p7).Value   vT7 = textLUT.get(p7).Value
  let p8 = cards[8]   vC8 = colorLUT.get(p8).Value   vT8 = textLUT.get(p8).Value
  let p9 = cards[9]   vC9 = colorLUT.get(p9).Value   vT9 = textLUT.get(p9).Value
  let p10 = cards[10] vC10 = colorLUT.get(p10).Value vT10 = textLUT.get(p10).Value
  let p11 = cards[11] vC11 = colorLUT.get(p11).Value vT11 = textLUT.get(p11).Value
  let p12 = cards[12] vC12 = colorLUT.get(p12).Value vT12 = textLUT.get(p12).Value
}

@right out press: exec
@right out seatOut: character = seat
@right out pressedSlot: int

// Report which button the seat occupant pressed. Each of the 13 per-button
// handlers sets the slot var and fires the shared `fire` signal -- they UNION
// into it. The single `on fire` consumer below then does the var-GET and emits
// pressedSlot + press ONCE. That single emit-value site is essential: emitting the
// value from inside `hit` (13 inlined sites) gave the output 13 separate value
// sources, of which only the first (slot 0) ever reached it. And a plain
// `out pressedSlot = vPressed.Value` binding is also wrong -- it samples the var
// in PURE context, before the Set, returning the PREVIOUS slot.
var vPressed: int = -1
let fire: exec
mod hit(slot: int) {
  vPressed = slot
  emit fire
}
on seat && card0 == seat { hit(0) }
on seat && card1 == seat { hit(1) }
on seat && card2 == seat { hit(2) }
on seat && card3 == seat { hit(3) }
on seat && card4 == seat { hit(4) }
on seat && card5 == seat { hit(5) }
on seat && card6 == seat { hit(6) }
on seat && card7 == seat { hit(7) }
on seat && card8 == seat { hit(8) }
on seat && card9 == seat { hit(9) }
on seat && card10 == seat { hit(10) }
on seat && card11 == seat { hit(11) }
on seat && cardDrawn == seat { hit(12) }

// The single union consumer: all 13 handlers set vPressed then `emit fire`; here
// one Var_Get reads it (after the Set) and drives the pressedSlot value + press.
// One emit-value site, so the output has exactly one source.
on fire {
  emit pressedSlot = vPressed
  emit press
}

// --- Outputs (read the LUT-decoded caches -- pure var reads, no exec-gate wiring) ---
@left out color0: color = vC0.Value
@left out color1: color = vC1.Value
@left out color2: color = vC2.Value
@left out color3: color = vC3.Value
@left out color4: color = vC4.Value
@left out color5: color = vC5.Value
@left out color6: color = vC6.Value
@left out color7: color = vC7.Value
@left out color8: color = vC8.Value
@left out color9: color = vC9.Value
@left out color10: color = vC10.Value
@left out color11: color = vC11.Value
@left out colorDrawn: color = vC12.Value
@left out text0: string = vT0.Value
@left out text1: string = vT1.Value
@left out text2: string = vT2.Value
@left out text3: string = vT3.Value
@left out text4: string = vT4.Value
@left out text5: string = vT5.Value
@left out text6: string = vT6.Value
@left out text7: string = vT7.Value
@left out text8: string = vT8.Value
@left out text9: string = vT9.Value
@left out text10: string = vT10.Value
@left out text11: string = vT11.Value
@left out textDrawn: string = vT12.Value
