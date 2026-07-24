// Test: HUD string builders. Pulse `start`; single-boolean result to chat.
import { ROLE_RED, ROLE_ASSASSIN, ROLE_NEUTRAL } from "key"
import { teamName, clueNumText, guessPrompt, gridCell } from "hud"
let start = ReadBrickGrid()
on start {
  let p1 = teamName(ROLE_RED) == "<color=\"f88\">Red</>" && clueNumText(0) == "∞" && clueNumText(8) == "∞" && clueNumText(3) == "3"
  let p2 = guessPrompt(999) == "∞ guesses<br>press a card, <b>W</> to pass" && guessPrompt(2) == "1 guess (+1 bonus)<br>press a card, <b>W</> to pass" && guessPrompt(1) == "bonus guess<br>press a card, <b>W</> to pass"
  let p3 = gridCell(ROLE_ASSASSIN, 0) == "<color=\"000\">█</>" && gridCell(ROLE_NEUTRAL, 1) == "<color=\"ca8\">░</>"
  let pass = p1 && p2 && p3
  BroadcastChatMessage("cn_hud: " .. (if pass then "ok" else "FAIL"))
}
