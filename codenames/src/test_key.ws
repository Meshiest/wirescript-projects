// Test: key model + roles split + classifyGuess. Pulse `start`; result to chat.
// One boolean (avoids FormatText's ~7-input cap that blanks big interpolations).
import {
  ROLE_RED, ROLE_BLUE, ROLE_NEUTRAL, ROLE_ASSASSIN,
  GUESS_CORRECT, GUESS_WRONG, GUESS_ASSASSIN,
  other, coverColorOf, glyphHexOf, classifyGuess, buildRoles,
} from "key"

let start = ReadBrickGrid()
array roles: int[] = []

on start {
  buildRoles(roles, ROLE_RED)
  let p1 = roles.length() == 25 && roles.get(0).Value == ROLE_RED && roles.get(8).Value == ROLE_RED
  let p2 = roles.get(9).Value == ROLE_BLUE && roles.get(16).Value == ROLE_BLUE
  let p3 = roles.get(17).Value == ROLE_NEUTRAL && roles.get(23).Value == ROLE_NEUTRAL && roles.get(24).Value == ROLE_ASSASSIN
  let p4 = classifyGuess(ROLE_RED, ROLE_RED) == GUESS_CORRECT && classifyGuess(ROLE_BLUE, ROLE_RED) == GUESS_WRONG
  let p5 = classifyGuess(ROLE_NEUTRAL, ROLE_RED) == GUESS_WRONG && classifyGuess(ROLE_ASSASSIN, ROLE_RED) == GUESS_ASSASSIN
  let p6 = other(ROLE_RED) == ROLE_BLUE && other(ROLE_BLUE) == ROLE_RED
  let p7 = coverColorOf(ROLE_RED).r != coverColorOf(ROLE_BLUE).r && glyphHexOf(ROLE_ASSASSIN) == "000"
  let pass = p1 && p2 && p3 && p4 && p5 && p6 && p7
  BroadcastChatMessage("cn_key: " .. (if pass then "ok" else "FAIL"))
}
