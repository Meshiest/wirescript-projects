import { CARD_DUKE, CARD_ASSASSIN, CARD_AMBASSADOR, CARD_CAPTAIN, CARD_CONTESSA } from "cards"

// Copies of each role, scaled to the table so a three-player game is not
// drawing from a diluted deck. 3/4/5 copies gives a 15/20/25 card deck.
mod deckCopies(playerCount: int) -> int {
  return 3 + (playerCount > 6) + (playerCount > 8)
}

// There are no loops, so the copies beyond the guaranteed three are unrolled.
mod deckAddRole(d: int[], role: int, copies: int) {
  static var pending: int[]
  pending.clear()
  pending.resize(copies, role)
  d.append(pending)
}

mod deckBuild(d: int[], copies: int) {
  deckAddRole(d, CARD_DUKE, copies)
  deckAddRole(d, CARD_ASSASSIN, copies)
  deckAddRole(d, CARD_AMBASSADOR, copies)
  deckAddRole(d, CARD_CAPTAIN, copies)
  deckAddRole(d, CARD_CONTESSA, copies)
  d.shuffle()
}

// Returns 0 on an empty deck; callers treat 0 as "no card".
mod deckDraw(d: int[]) -> int {
  let popped = d.pop()
  return if popped.IsEmpty then 0 else popped.Value
}

mod deckReturn(d: int[], card: int) {
  d.push(card)
  d.shuffle()
}
