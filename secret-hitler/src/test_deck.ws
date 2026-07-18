// Test: policy deck compose / draw / reshuffle. Pulse `start`; result to chat.

import { POL_FASC } from "powers"
import { deckDraw3, deckInit, deckReshuffleIfLow, deckTopCard } from "deck"

in start: exec

array draw: int[]
array discard: int[]
array hand: int[]

on start {
  // -- Composition: 17 cards, 11 fascist --
  deckInit(draw, discard)
  let c1 = if draw.length() != 17 then "init_len=${draw.length()} exp=17\n" else ""
  let fascN = draw.sum() // POL_LIB=0, POL_FASC=1, so sum == fascist count
  let c2 = if fascN != 11 then "init_fasc=${fascN} exp=11\n" else ""
  let c3 = if discard.length() != 0 then "init_discard=${discard.length()} exp=0\n" else ""

  // -- Draw 3: hand has 3, pile has 14 --
  deckDraw3(draw, hand)
  let c4 = if hand.length() != 3 then "draw_hand=${hand.length()} exp=3\n" else ""
  let c5 = if draw.length() != 14 then "draw_left=${draw.length()} exp=14\n" else ""

  // -- Reshuffle: not while >=3 remain --
  discard.push(POL_FASC)
  deckReshuffleIfLow(draw, discard)
  let c6 = if draw.length() != 14 then "noshuffle_len=${draw.length()} exp=14\n" else ""
  let c7 = if discard.length() != 1 then "noshuffle_discard=${discard.length()} exp=1\n" else ""

  // -- Reshuffle: fires below 3, merges discard, empties it --
  draw.clear()
  draw.push(POL_FASC) draw.push(POL_FASC)
  deckReshuffleIfLow(draw, discard)
  let c8 = if draw.length() != 3 then "shuffle_len=${draw.length()} exp=3\n" else ""
  let c9 = if discard.length() != 0 then "shuffle_discard=${discard.length()} exp=0\n" else ""

  // -- Top card pop --
  let before = draw.length()
  let top = deckTopCard(draw)
  let c10 = if draw.length() != before - 1 then "top_len=${draw.length()} exp=${before - 1}\n" else ""
  let c11 = if top < 0 || top > 1 then "top_val=${top} exp=0|1\n" else ""

  let msg = c1 .. c2 .. c3 .. c4 .. c5 .. c6 .. c7 .. c8 .. c9 .. c10 .. c11
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("sh_deck: ${ok}")
}
