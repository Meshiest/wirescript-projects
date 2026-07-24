// hud.ws -- Codenames HUD string builders (pure).
import { ROLE_RED, ROLE_BLUE, glyphHexOf } from "key"

mod teamName(team: int) -> string {
  return if team == ROLE_RED then "<color=\"f88\">Red</>" else "<color=\"88f\">Blue</>"
}

mod turnBanner(team: int) -> string {
  return "${teamName(team)}'s turn"
}

// 0 and 8 are "unlimited"; 1..7 print the digit.
mod clueNumText(n: int) -> string {
  return if n == 0 || n == 8 then "∞" else "${n}"
}

mod cluePrompt(n: int) -> string {
  return "Clue number: <b>${clueNumText(n)}</><br><b>A/D</> change, <b>W</> confirm"
}

// Shown to everyone in the banner. `left` = guessesLeft = intended + 1 bonus.
// Framed as "intended (+1 bonus)" so a clue of 1 doesn't read like 2 hints.
mod guessCountText(left: int) -> string {
  if left >= 999 { return "∞ guesses" }
  if left <= 1 { return "bonus guess" }
  let intended = left - 1
  let word = if intended == 1 then "guess" else "guesses"
  return "${intended} ${word} (+1 bonus)"
}

mod guessPrompt(left: int) -> string {
  return "${guessCountText(left)}<br>press a card, <b>W</> to pass"
}

mod outcomeText(winner: int, assassinLoss: bool) -> string {
  let w = teamName(winner)
  let l = teamName(if winner == ROLE_RED then ROLE_BLUE else ROLE_RED)
  return if assassinLoss then "${l} hit the assassin. ${w} wins!<br><b>W</> to continue"
    else "${w} wins!<br><b>W</> to continue"
}

// One 5×5-grid square: two block chars, hollow once covered. Caller wraps the
// whole grid in <font="Iosevka"> and joins rows with <br>.
mod gridCell(role: int, covered: int) -> string {
  return if covered != 0 then "<color=\"${glyphHexOf(role)}\">░</>"
    else "<color=\"${glyphHexOf(role)}\">█</>"
}
