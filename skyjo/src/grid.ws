import { ST_EMPTY, ST_UP, ST_DOWN, packCell, cellState, cellValue } from "cards"

// A column of three same-value face-up cells is discarded, its cells set EMPTY.
// Cleared cells count as resolved (not DOWN) for handAllUp.
mod clearColIfEqual(g: int[], cv: int[], base: int, c: int, discard: int[]) {
  let a = g[base + c]
  let b = g[base + c + 4]
  let d = g[base + c + 8]
  if cellState(a) == ST_UP && cellState(b) == ST_UP && cellState(d) == ST_UP {
    let va = cellValue(a)
    if cellValue(b) == va && cellValue(d) == va {
      let emptyCell = packCell(ST_EMPTY, 0)
      g[base + c] = emptyCell
      g[base + c + 4] = emptyCell
      g[base + c + 8] = emptyCell
      cv[base + c] = 0          // keep the value mirror in sync: cleared -> 0
      cv[base + c + 4] = 0
      cv[base + c + 8] = 0
      discard.push(va)
      discard.push(va)
      discard.push(va)
    }
  }
}

mod columnClear(g: int[], cv: int[], base: int, discard: int[]) {
  clearColIfEqual(g, cv, base, 0, discard)
  clearColIfEqual(g, cv, base, 1, discard)
  clearColIfEqual(g, cv, base, 2, discard)
  clearColIfEqual(g, cv, base, 3, discard)
}

// Sum a seat's 12-cell hand from the value mirror `vals` (each cell = its face-up
// score: value if UP, 0 if down/empty/cleared -- see main's cellVal). `scratch`
// is a caller-owned throwaway that receives the 12 sliced cells. slice + sum is
// 2 gates, versus ~80 to decode-and-add the packed grid at every call site.
mod handSum(vals: int[], scratch: int[], base: int) -> int {
  scratch.slice(vals, base, 12)
  return scratch.sum()
}

mod isDown(g: int[], k: int) -> int {
  return if cellState(g[k]) == ST_DOWN then 1 else 0
}

mod handAllUp(g: int[], base: int) -> bool {
  let n = isDown(g, base + 0) + isDown(g, base + 1) + isDown(g, base + 2)
        + isDown(g, base + 3) + isDown(g, base + 4) + isDown(g, base + 5)
        + isDown(g, base + 6) + isDown(g, base + 7) + isDown(g, base + 8)
        + isDown(g, base + 9) + isDown(g, base + 10) + isDown(g, base + 11)
  return n == 0
}
