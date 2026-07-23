// Test: packed-cell round-trip. Pulse `start`; result to chat.
import {
  ST_EMPTY, ST_DOWN, ST_UP, packCell, cellState, cellValue, cellColor, cellText,
} from "cards"

let start = ReadBrickGrid()

on start {
  let p = packCell(ST_UP, 7)
  let c1 = if cellState(p) != ST_UP then "state=${cellState(p)} exp=${ST_UP}\n" else ""
  let c2 = if cellValue(p) != 7 then "value=${cellValue(p)} exp=7\n" else ""
  // negative value round-trips
  let q = packCell(ST_UP, -2)
  let c5 = if cellValue(q) != -2 then "negv=${cellValue(q)} exp=-2\n" else ""
  // state and value are independent (no bleed across the nibble boundary)
  let r = packCell(ST_DOWN, 12)
  let c8 = if cellState(r) != ST_DOWN then "rstate=${cellState(r)} exp=${ST_DOWN}\n" else ""
  let c9 = if cellValue(r) != 12 then "rvalue=${cellValue(r)} exp=12\n" else ""
  // text: number, "?", ""
  let t1 = if cellText(packCell(ST_UP, 5)) != "5" then "t_up=${cellText(packCell(ST_UP, 5))} exp=5\n" else ""
  let t2 = if cellText(packCell(ST_DOWN, 5)) != "?" then "t_down exp=?\n" else ""
  let t3 = if cellText(packCell(ST_EMPTY, 0)) != "" then "t_empty exp=empty\n" else ""
  let t4 = if cellText(packCell(ST_UP, -2)) != "-2" then "t_neg exp=-2\n" else ""
  // color: a red-band cell differs from a green-band cell (sanity that bands map).
  // Compare the .r COMPONENT, not "${color}" -- a color interpolates to BLANK
  // in-game (FormatText prints nothing for a color), so string compare wrongly
  // reads both as "" and always matches. red band .r=0.8 vs green band .r=0.133.
  let redC = cellColor(packCell(ST_UP, 11))
  let grnC = cellColor(packCell(ST_UP, 2))
  let t5 = if redC.r == grnC.r then "bands_equal exp=diff\n" else ""
  let msg = "${c1}${c2}${c5}${c8}${c9}${t1}${t2}${t3}${t4}${t5}"
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("skyjo_cards: ${ok}")
}
