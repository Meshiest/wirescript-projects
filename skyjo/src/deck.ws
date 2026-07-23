// The 150-card Skyjo deck: values -2..12. No loops -> the distribution is
// unrolled; deckAddCopies uses resize to add `copies` elements at once.
mod deckAddCopies(d: int[], value: int, copies: int) {
  static var pending: int[]
  pending.clear()
  pending.resize(copies, value)
  d.append(pending)
}

mod deckBuild(d: int[]) {
  d.clear()
  deckAddCopies(d, -2, 5)
  deckAddCopies(d, -1, 10)
  deckAddCopies(d, 0, 15)
  deckAddCopies(d, 1, 10)
  deckAddCopies(d, 2, 10)
  deckAddCopies(d, 3, 10)
  deckAddCopies(d, 4, 10)
  deckAddCopies(d, 5, 10)
  deckAddCopies(d, 6, 10)
  deckAddCopies(d, 7, 10)
  deckAddCopies(d, 8, 10)
  deckAddCopies(d, 9, 10)
  deckAddCopies(d, 10, 10)
  deckAddCopies(d, 11, 10)
  deckAddCopies(d, 12, 10)
  d.shuffle()
}

mod discardPush(discard: int[], value: int) { discard.push(value) }

mod discardTop(discard: int[]) -> int {
  if discard.length() == 0 { return 0 }
  let n = discard.length()
  return discard[n-1]
}

// Move all-but-top of the discard back into the deck and shuffle. Keeps the
// current top face-up on the pile so play continues from it.
mod reshuffleDiscard(d: int[], discard: int[]) {
  if discard.length() <= 1 { return }
  let top = discard.pop()
  d.append(discard)
  discard.clear()
  if !top.IsEmpty { discard.push(top.Value) }
  d.shuffle()
}

// Pop the deck top; refill from the discard first when the deck is empty.
// Returns 0 ("no drawable card") when the deck is empty AND the discard holds at
// most its single visible top (nothing to reshuffle). Unreachable in real play.
mod deckDraw(d: int[], discard: int[]) -> int {
  if d.length() == 0 { reshuffleDiscard(d, discard) }
  let popped = d.pop()
  return if popped.IsEmpty then 0 else popped.Value
}

// Bare pop, no reshuffle — for draws guaranteed non-empty (the initial deal +
// discard seed draw 97 of 150, so the deck can't empty). Using this instead of
// deckDraw at those 97 unrolled sites avoids inlining reshuffleDiscard's
// append/clear/shuffle block 97 times (~a third of the deck-op gates).
mod deckPop(d: int[]) -> int {
  let popped = d.pop()
  return if popped.IsEmpty then 0 else popped.Value
}
