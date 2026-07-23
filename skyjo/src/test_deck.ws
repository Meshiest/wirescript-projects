// Test: deck distribution + draw/reshuffle. Pulse `start`; result to chat.
import { deckBuild, deckDraw, discardPush, discardTop } from "deck"

array d: int[]
array disc: int[]

let start = ReadBrickGrid()

mod drainOne(arr: int[], value: int) -> int {
  let f = arr.find(value)
  if !f.Found { return 0 }
  arr.remove(f.Index)
  return 1
}

// Count occurrences of `value` in arr without mutating it (find+remove on a copy).
mod countVal(arr: int[], value: int) -> int {
  static var tmp: int[]
  tmp.clear()
  tmp.append(arr)
  var n: int = 0
  // bounded unroll: at most 15 of any value exist
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  n = n + drainOne(tmp, value)
  return n
}

on start {
  deckBuild(d)
  let c1 = if d.length() != 150 then "len=${d.length()} exp=150\n" else ""
  let c2 = if countVal(d, -2) != 5 then "n-2=${countVal(d, -2)} exp=5\n" else ""
  let c3 = if countVal(d, -1) != 10 then "n-1=${countVal(d, -1)} exp=10\n" else ""
  let c4 = if countVal(d, 0) != 15 then "n0=${countVal(d, 0)} exp=15\n" else ""
  let c5 = if countVal(d, 1) != 10 then "n1=${countVal(d, 1)} exp=10\n" else ""
  let c6 = if countVal(d, 12) != 10 then "n12=${countVal(d, 12)} exp=10\n" else ""
  let c7 = if countVal(d, 13) != 0 then "n13=${countVal(d, 13)} exp=0\n" else ""

  // draw shrinks the deck
  let before = d.length()
  disc.clear()
  let drawn = deckDraw(d, disc)
  let c8 = if d.length() != before - 1 then "drawlen=${d.length()} exp=${before-1}\n" else ""

  // reshuffle: empty deck + a discard of >1 refills from all-but-top
  d.clear()
  disc.clear()
  discardPush(disc, 4) // will become the kept top
  discardPush(disc, 5)
  discardPush(disc, 6) // current top
  let refilled = deckDraw(d, disc) // triggers reshuffle, then pops one
  let c9 = if disc.length() != 1 then "disc_after=${disc.length()} exp=1\n" else ""
  let c10 = if discardTop(disc) != 6 then "kept_top=${discardTop(disc)} exp=6\n" else ""
  // 3 cards, top kept, other 2 moved to deck, one popped -> deck has 1 left
  let c11 = if d.length() != 1 then "deck_after=${d.length()} exp=1\n" else ""

  // edge: deck AND discard both empty -> 0 (no drawable card). Unreachable in
  // real play (150 cards can never all fit in <=96 hand slots), pinned anyway.
  d.clear() disc.clear()
  let bothEmpty = deckDraw(d, disc)
  let c12 = if bothEmpty != 0 then "bothempty=${bothEmpty} exp=0\n" else ""
  // edge: deck empty, discard = only its top (1 card) -> 0, and the top is KEPT
  // (reshuffle no-ops on a <=1 pile, so nothing is drawn and the top stays).
  d.clear() disc.clear() discardPush(disc, 7)
  let onlyTop = deckDraw(d, disc)
  let c13 = if onlyTop != 0 then "onlytop=${onlyTop} exp=0\n" else ""
  let c14 = if discardTop(disc) != 7 then "onlytop_kept=${discardTop(disc)} exp=7\n" else ""

  let msg = "${c1}${c2}${c3}${c4}${c5}${c6}${c7}${c8}${c9}${c10}${c11}${c12}${c13}${c14}"
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("skyjo_deck: ${ok}")
}
