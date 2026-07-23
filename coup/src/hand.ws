// Influence is stored as roles plus two lost-masks, so the private hand and the
// public reveal can never be confused. Everything here is bit math over those
// masks and takes them as arguments, keeping the module pure.

mod influenceOf(i: int, lostA: int, lostB: int) -> int {
  return 2 - ((lostA >> i) & 1) - ((lostB >> i) & 1)
}

mod seatDead(i: int, lostA: int, lostB: int) -> bool {
  return ((lostA & lostB) >> i) & 1
}

// The public card-slot value: 15 when the seat is not in the game, the revealed
// role once that influence is lost, otherwise 0 for a live face-down card.
mod slotValue(playing: bool, lost: bool, role: int) -> int {
  return if !playing then 15 else if lost then role else 0
}

mod packSeat(a: int, b: int, coins: int) -> int {
  return a | (b << 4) | (clamp(coins, 0, 12) << 8)
}
