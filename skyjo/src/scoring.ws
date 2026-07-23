// Whether ender stays strictly lowest against seat i: true unless i is a
// different participating seat whose score is <= the ender's.
mod keepsLowest(rs: int[], ender: int, i: int, base: int, mask: int) -> bool {
  if i == ender { return true }
  if ((mask >> i) & 1) == 0 { return true }
  return rs[i] > base
}

mod enderScore(roundScore: int[], enderSeat: int, playingMask: int) -> int {
  let base = roundScore[enderSeat]
  let strictlyLowest = keepsLowest(roundScore, enderSeat, 0, base, playingMask)
     && keepsLowest(roundScore, enderSeat, 1, base, playingMask)
     && keepsLowest(roundScore, enderSeat, 2, base, playingMask)
     && keepsLowest(roundScore, enderSeat, 3, base, playingMask)
     && keepsLowest(roundScore, enderSeat, 4, base, playingMask)
     && keepsLowest(roundScore, enderSeat, 5, base, playingMask)
     && keepsLowest(roundScore, enderSeat, 6, base, playingMask)
     && keepsLowest(roundScore, enderSeat, 7, base, playingMask)
  return if strictlyLowest then base else base * 2
}

mod maxOne(t: int[], i: int, mask: int, acc: int) -> int {
  if ((mask >> i) & 1) == 0 { return acc }
  return if t[i] > acc then t[i] else acc
}

mod maxTotal(scoreTotal: int[], playingMask: int) -> int {
  var m: int = -2147483648
  m = maxOne(scoreTotal, 0, playingMask, m)
  m = maxOne(scoreTotal, 1, playingMask, m)
  m = maxOne(scoreTotal, 2, playingMask, m)
  m = maxOne(scoreTotal, 3, playingMask, m)
  m = maxOne(scoreTotal, 4, playingMask, m)
  m = maxOne(scoreTotal, 5, playingMask, m)
  m = maxOne(scoreTotal, 6, playingMask, m)
  m = maxOne(scoreTotal, 7, playingMask, m)
  return m
}

// statement-if (NOT expression-if): an expression-if Select would evaluate the
// t[seat] arm even when seat<0, an out-of-bounds read.
mod valOr(t: int[], seat: int, fallback: int) -> int {
  if seat < 0 { return fallback }
  return t[seat]
}
mod lowStep(t: int[], i: int, mask: int, bestSeat: int, bestVal: int) -> int {
  if ((mask >> i) & 1) == 0 { return bestSeat }
  if bestSeat < 0 { return i }
  if t[i] < bestVal { return i }
  return bestSeat
}

// Best (lowest total) participating seat; ties resolve to the lowest index
// because a strictly-less test only replaces on a smaller value. bv trails bs:
// after each step it re-reads the current best seat's value (or stays at the
// sentinel while no seat has been seen).
mod lowestSeat(scoreTotal: int[], playingMask: int) -> int {
  var bs: int = -1
  var bv: int = 2147483647
  bs = lowStep(scoreTotal, 0, playingMask, bs, bv)  bv = valOr(scoreTotal, bs, bv)
  bs = lowStep(scoreTotal, 1, playingMask, bs, bv)  bv = valOr(scoreTotal, bs, bv)
  bs = lowStep(scoreTotal, 2, playingMask, bs, bv)  bv = valOr(scoreTotal, bs, bv)
  bs = lowStep(scoreTotal, 3, playingMask, bs, bv)  bv = valOr(scoreTotal, bs, bv)
  bs = lowStep(scoreTotal, 4, playingMask, bs, bv)  bv = valOr(scoreTotal, bs, bv)
  bs = lowStep(scoreTotal, 5, playingMask, bs, bv)  bv = valOr(scoreTotal, bs, bv)
  bs = lowStep(scoreTotal, 6, playingMask, bs, bv)  bv = valOr(scoreTotal, bs, bv)
  bs = lowStep(scoreTotal, 7, playingMask, bs, bv)  bv = valOr(scoreTotal, bs, bv)
  return bs
}
