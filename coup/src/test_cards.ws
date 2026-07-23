// Test: card role table + name/icon/text lookups. Pulse `start`; result to chat.

import { CARD_NONE, CARD_DUKE, CARD_ASSASSIN, CARD_AMBASSADOR, CARD_CAPTAIN,
  CARD_CONTESSA, CARD_HIDDEN, ROLE_COUNT, cardName, cardText, cardIcon, cardTextColored } from "cards"

let start = ReadBrickGrid()

on start {
  let c1 = if CARD_NONE != 0 then "CARD_NONE=${CARD_NONE} exp=0\n" else ""
  let c2 = if CARD_HIDDEN != 15 then "CARD_HIDDEN=${CARD_HIDDEN} exp=15\n" else ""
  let c3 = if ROLE_COUNT != 5 then "ROLE_COUNT=${ROLE_COUNT} exp=5\n" else ""
  let c4 = if cardName(CARD_DUKE) != "Duke" then 'name_duke="${cardName(CARD_DUKE)}" exp="Duke"\n' else ""
  let c5 = if cardName(CARD_CONTESSA) != "Contessa" then 'name_contessa="${cardName(CARD_CONTESSA)}" exp="Contessa"\n' else ""
  let c6 = if cardName(CARD_ASSASSIN) != "Assassin" then 'name_assassin="${cardName(CARD_ASSASSIN)}" exp="Assassin"\n' else ""
  let c7 = if cardName(99) != "?" then 'name99="${cardName(99)}" exp="?"\n' else ""
  let c8 = if cardIcon(CARD_DUKE) != '<color="8800AA"><b><icon>star</></></>' then 'icon_duke="${cardIcon(CARD_DUKE)}" exp=star\n' else ""
  let c9 = if cardIcon(CARD_ASSASSIN) != '<color="222222"><b><icon>skull</></></>' then 'icon_assassin="${cardIcon(CARD_ASSASSIN)}" exp=skull\n' else ""
  let c10 = if cardIcon(CARD_AMBASSADOR) != '<color="DDDD00"><b><icon>arrows-to-dot</></></>' then 'icon_ambassador="${cardIcon(CARD_AMBASSADOR)}" exp=arrows-to-dot\n' else ""
  let c11 = if cardIcon(CARD_CAPTAIN) != '<color="8888FF"><b><icon>anchor</></></>' then 'icon_captain="${cardIcon(CARD_CAPTAIN)}" exp=anchor\n' else ""
  let c12 = if cardIcon(CARD_CONTESSA) != '<color="FF0011"><b><icon>gem</></></>' then 'icon_contessa="${cardIcon(CARD_CONTESSA)}" exp=gem\n' else ""
  let c13 = if cardIcon(99) != "" then 'icon99="${cardIcon(99)}" exp=""\n' else ""
  let c14 = if cardText(CARD_DUKE) != '<color="8800AA"><b><icon>star</></></> Duke' then 'text_duke="${cardText(CARD_DUKE)}" exp="star Duke"\n' else ""
  let c15 = if cardTextColored(CARD_DUKE, "ff0") != '<color="ff0"><b><icon>star</></> Duke</>' then 'textc_duke="${cardTextColored(CARD_DUKE, "ff0")}" exp="colored ff0 star Duke"\n' else ""
  let c16 = if cardTextColored(99, "ff0") != '<color="ff0"><b><icon></></> ?</>' then 'textc99="${cardTextColored(99, "ff0")}" exp="colored ff0 blank ?"\n' else ""
  let msg = "${c1}${c2}${c3}${c4}${c5}${c6}${c7}${c8}${c9}${c10}${c11}${c12}${c13}${c14}${c15}${c16}"
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("coup_cards: ${ok}")
}
