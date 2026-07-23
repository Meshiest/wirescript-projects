// Test: deck copy scaling, role-exact composition, draw/return. Pulse
// `start`; result to chat.

import { CARD_DUKE, CARD_ASSASSIN, CARD_AMBASSADOR, CARD_CAPTAIN, CARD_CONTESSA } from "cards"
import { deckCopies, deckBuild, deckDraw, deckReturn } from "deck"

array d: int[]
array e: int[]

in start: exec

// Removes exactly `copies` occurrences of `role` from arr, mirroring
// deckAddRole's own unconditional/guarded push shape. Returns false if the
// role is under- or over-represented, so a role-mapping or boundary bug in
// deckAddRole can't hide behind a correct total length.
mod expectRoleCount(arr: int[], role: int, copies: int) -> bool {
  let f1 = arr.find(role)
  if !f1.Found { return false }
  arr.remove(f1.Index)
  let f2 = arr.find(role)
  if !f2.Found { return false }
  arr.remove(f2.Index)
  let f3 = arr.find(role)
  if !f3.Found { return false }
  arr.remove(f3.Index)
  if copies >= 4 {
    let f4 = arr.find(role)
    if !f4.Found { return false }
    arr.remove(f4.Index)
  }
  if copies >= 5 {
    let f5 = arr.find(role)
    if !f5.Found { return false }
    arr.remove(f5.Index)
  }
  if arr.find(role).Found { return false }
  return true
}

on start {
  // copies scale with the table: 3 up to six players, 4 at seven, 5 at nine.
  // Pin both sides of both boundaries (6/7 and 8/9). Pure over constant
  // inputs, so these stay as independent `let`s.
  let c1 = if deckCopies(3) != 3 then "copies3=${deckCopies(3)} exp=3\n" else ""
  let c2 = if deckCopies(6) != 3 then "copies6=${deckCopies(6)} exp=3\n" else ""
  let c3 = if deckCopies(7) != 4 then "copies7=${deckCopies(7)} exp=4\n" else ""
  let c4 = if deckCopies(8) != 4 then "copies8=${deckCopies(8)} exp=4\n" else ""
  let c5 = if deckCopies(9) != 5 then "copies9=${deckCopies(9)} exp=5\n" else ""
  let c6 = if deckCopies(10) != 5 then "copies10=${deckCopies(10)} exp=5\n" else ""

  // Everything below mutates the shared `d`/`e` arrays (deckBuild, deckDraw,
  // deckReturn, and expectRoleCount are all side-effecting -- expectRoleCount
  // itself consumes the matching elements as it verifies them). Each check's
  // outcome depends on exactly which prior mutations already ran, so these
  // can't be reordered into independent `let`s; keep the original exec
  // sequence and accumulate into a `var` instead.
  var msg: string = "${c1}${c2}${c3}${c4}${c5}${c6}"

  // A 3-copy deck must have exactly 3 of EACH role, not just 15 total -- a
  // role swapped for another would still sum to 15.
  d.clear()
  deckBuild(d, 3)
  if d.length() != 15 { msg = "${msg}len3=${d.length()} exp=15\n" }
  if !expectRoleCount(d, CARD_DUKE, 3) { msg = "${msg}count3_duke=false exp=true\n" }
  if !expectRoleCount(d, CARD_ASSASSIN, 3) { msg = "${msg}count3_assassin=false exp=true\n" }
  if !expectRoleCount(d, CARD_AMBASSADOR, 3) { msg = "${msg}count3_ambassador=false exp=true\n" }
  if !expectRoleCount(d, CARD_CAPTAIN, 3) { msg = "${msg}count3_captain=false exp=true\n" }
  if !expectRoleCount(d, CARD_CONTESSA, 3) { msg = "${msg}count3_contessa=false exp=true\n" }
  if d.length() != 0 { msg = "${msg}remain3=${d.length()} exp=0\n" }

  // A 4-copy deck exercises the first guarded push only. Spot-check the
  // first and last role in deckBuild's call order: exactly 4, never 5.
  d.clear()
  deckBuild(d, 4)
  if d.length() != 20 { msg = "${msg}len4=${d.length()} exp=20\n" }
  if !expectRoleCount(d, CARD_DUKE, 4) { msg = "${msg}count4_duke=false exp=true\n" }
  if !expectRoleCount(d, CARD_CONTESSA, 4) { msg = "${msg}count4_contessa=false exp=true\n" }

  // A 5-copy deck exercises both guarded pushes: exactly 5 of EACH role.
  d.clear()
  deckBuild(d, 5)
  if d.length() != 25 { msg = "${msg}len5=${d.length()} exp=25\n" }
  if !expectRoleCount(d, CARD_DUKE, 5) { msg = "${msg}count5_duke=false exp=true\n" }
  if !expectRoleCount(d, CARD_ASSASSIN, 5) { msg = "${msg}count5_assassin=false exp=true\n" }
  if !expectRoleCount(d, CARD_AMBASSADOR, 5) { msg = "${msg}count5_ambassador=false exp=true\n" }
  if !expectRoleCount(d, CARD_CAPTAIN, 5) { msg = "${msg}count5_captain=false exp=true\n" }
  if !expectRoleCount(d, CARD_CONTESSA, 5) { msg = "${msg}count5_contessa=false exp=true\n" }
  if d.length() != 0 { msg = "${msg}remain5=${d.length()} exp=0\n" }

  // Rebuild a real deck for the draw/return checks below.
  d.clear()
  deckBuild(d, 3)

  // drawing shrinks the deck and yields a real role
  let before = d.length()
  let c = deckDraw(d)
  if d.length() != before - 1 { msg = "${msg}drawlen=${d.length()} exp=${before - 1}\n" }
  if c < 1 { msg = "${msg}draw_lo=${c} exp>=1\n" }
  if c > 5 { msg = "${msg}draw_hi=${c} exp<=5\n" }

  // returning restores the count
  deckReturn(d, CARD_DUKE)
  if d.length() != before { msg = "${msg}returnlen=${d.length()} exp=${before}\n" }

  // deckReturn puts back the SPECIFIC card given, not just any card. On a
  // fresh empty array, deckReturn pushes then shuffles a single element,
  // which is a no-op, so the result is deterministic.
  e.clear()
  deckReturn(e, CARD_CONTESSA)
  if e.length() != 1 { msg = "${msg}elen=${e.length()} exp=1\n" }
  let returned = e[0]
  if returned != CARD_CONTESSA { msg = "${msg}returned=${returned} exp=${CARD_CONTESSA}\n" }

  // an empty deck yields 0 rather than reading out of bounds
  d.clear()
  let emptyDraw = deckDraw(d)
  if emptyDraw != 0 { msg = "${msg}emptydraw=${emptyDraw} exp=0\n" }

  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("coup_deck: ${ok}")
}
