// Secret Hitler - screen-space HUD via per-character DisplayText. Each mod
// draws for ONE viewer; secrecy is per-character targeting. Slots (textId):
//   2 banner (top center) | 4 tally | 5 action prompt (center) | 90 role card.
// Re-emit each slot faster than HUD_LIFE or it fades (service cursor in main).

import { POL_LIB, R_FASC, R_LIB } from "powers"

let HUD_LIFE = 5.0
let TID_BANNER = 2
let TID_TALLY = 4
let TID_PROMPT = 5
let TID_ROLE = 90
let TID_ACTIVITY = 6

// User text must not smuggle markup into rich text.
mod sanitizeName(s: string) -> string {
  return s.Replace(";", "&scl;").Replace("<", "&lt;")
}

mod policyText(p: int) -> string {
  return if p == POL_LIB then '<color="68f"><b>LIBERAL</></>'
    else '<color="f66"><b>FASCIST</></>'
}

mod roleText(role: int) -> string {
  return if role == R_LIB then '<color="68f"><b>LIBERAL</></>'
    else if role == R_FASC then '<color="f66"><b>FASCIST</></>'
    else '<color="f00"><b>HITLER</></>'
}

mod hudBanner(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_BANNER, positionX = 0.0, positionY = -30.0,
    fontSize = 24, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.25)
}

mod hudTally(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_TALLY, positionX = 0.0, positionY = 40.0,
    fontSize = 18, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.25)
}

mod hudPrompt(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_PROMPT, positionX = 0.0, positionY = 60.0,
    fontSize = 20, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.5)
}

mod hudRole(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_ROLE, positionX = -20.0, positionY = -40.0,
    fontSize = 18, lifetime = HUD_LIFE, justify = "Right", anchorX = 1.0, anchorY = 0.8)
}

// Rolling activity feed (replaces chat broadcasts): bottom-right, above the
// role card, semi-small text. Fed the pre-joined line block by main's service.
mod hudActivity(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_ACTIVITY, positionX = -20.0, positionY = -170.0,
    fontSize = 12, lifetime = HUD_LIFE, justify = "Right", anchorX = 1.0, anchorY = 0.8)
}

// 2-3 card fan with the highlighted card bracketed: "[FASCIST]  LIBERAL ...".
// Exec-only (reads `hand`). hi = -1 for no highlight. The third card uses a
// statement-if, NOT an expression-if: expression-if compiles to a Select gate
// where BOTH arms evaluate, which would read hand[2] out of bounds on the
// chancellor's 2-card fan.
// The current highlight shows in [ ], everything else bare.
mod cardFanText(hand: int[], count: int, hi: int) -> string {
  let c0 = if hi == 0 then "[ ${policyText(hand[0])} ]" else "  ${policyText(hand[0])}  "
  let c1 = if hi == 1 then "[ ${policyText(hand[1])} ]" else "  ${policyText(hand[1])}  "
  var c2: string = ""
  if count >= 3 {
    c2 = if hi == 2 then "[ ${policyText(hand[2])} ]" else "  ${policyText(hand[2])}  "
  }
  return c0 .. " " .. c1 .. " " .. c2
}
