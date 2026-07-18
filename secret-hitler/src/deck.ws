// Secret Hitler - policy deck. Pure logic that fills the caller's arrays (mods
// inline, so `draw`/`discard` bind to main's own arrays). Tested by test_deck.ws.
// Convention: the END of the array is the TOP of the pile (pop = draw).

import { POL_FASC, POL_LIB } from "powers"

// Fresh 17-card deck: 6 liberal + 11 fascist, shuffled. Discard emptied.
mod deckInit(draw: int[], discard: int[]) {
  draw.clear()
  discard.clear()
  array libs: int[]
  libs.clear()
  libs.resize(6, POL_LIB)
  draw.append(libs)
  array fascs: int[]
  fascs.clear()
  fascs.resize(11, POL_FASC)
  draw.append(fascs)
  draw.shuffle()
}

// President draws the top three tiles into `hand`.
mod deckDraw3(draw: int[], hand: int[]) {
  hand.clear()
  hand.push(draw.pop())
  hand.push(draw.pop())
  hand.push(draw.pop())
}

// Rulebook: fewer than three tiles remaining -> shuffle them with the discard
// pile to make a new deck. Unused tiles are never placed back on top.
mod deckReshuffleIfLow(draw: int[], discard: int[]) {
  if draw.length() < 3 {
    draw.append(discard)
    discard.clear()
    draw.shuffle()
  }
}

// Pop the top card (election-tracker chaos enact).
mod deckTopCard(draw: int[]) -> int {
  return draw.pop()
}
