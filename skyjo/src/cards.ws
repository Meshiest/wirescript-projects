// Grid-cell packing shared by main (encode) and player (decode). Face-down
// cells carry no real value on the wire, so nothing leaks even to the owner.
//   packed = state*16 + (value + 2)
// value in [-2,12] so value+2 in [0,14]; state in {0,1,2}, so packed <= 46.
// That keeps `state = p / 16` exact WITHOUT a `% 4` (p/16 is already <= 2), and
// `p % 16` recovers value+2 -- one fewer modulo at every decode site.
let ST_EMPTY = 0  // cleared column / undealt
let ST_DOWN = 1   // face-down
let ST_UP = 2     // face-up

mod packCell(state: int, value: int) -> int {
  return state * 16 + (value + 2)
}

mod cellState(p: int) -> int { return p / 16 }
mod cellValue(p: int) -> int { return (p % 16) - 2 }

// sRGB-direct band colours (do not gamma-darken).
let COL_RED: color = Color(0.560, 0.093, 0.093, 1.0)
let COL_YELLOW: color = Color(0.607, 0.560, 0.093, 1.0)
let COL_GREEN: color = Color(0.093, 0.513, 0.140, 1.0)
let COL_CYAN: color = Color(0.000, 0.560, 0.607, 1.0)
let COL_BLUE: color = Color(0.047, 0.140, 0.467, 1.0)
let COL_BACK: color = Color(0.333, 0.333, 0.333, 1.0)  // face-down "?"
let COL_OFF: color = Color(0.133, 0.133, 0.133, 1.0)   // empty / cleared

// Expression-if (not statement-if) so both decode fns can be called from a PURE
// output binding -- the player renders colour + text off the exec chain.
mod cellColor(p: int) -> color {
  let st = cellState(p)
  let v = cellValue(p)
  return if st == ST_EMPTY then COL_OFF
    else if st == ST_DOWN then COL_BACK
    else if v >= 9 then COL_RED
    else if v >= 5 then COL_YELLOW
    else if v >= 1 then COL_GREEN
    else if v == 0 then COL_CYAN
    else COL_BLUE
}

mod cellText(p: int) -> string {
  let st = cellState(p)
  let v = cellValue(p)
  // The string "0" gets cast to false by the sign's text input (blanking the
  // card), so render a value-0 card as the letter "O" rather than the digit "0".
  return if st == ST_EMPTY then ""
    else if st == ST_DOWN then "?"
    else if v == 0 then "O"
    else "${v}"
}
