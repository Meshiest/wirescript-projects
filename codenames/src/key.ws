// key.ws -- Codenames key model: roles, cover colors, pure game logic.
let ROLE_RED = 0
let ROLE_BLUE = 1
let ROLE_NEUTRAL = 2
let ROLE_ASSASSIN = 3

let GUESS_CORRECT = 0
let GUESS_WRONG = 1
let GUESS_ASSASSIN = 2

// Linear-RGB cover colours (the board treats color inputs as linear, so these
// look darker in-game than the numbers suggest -- kept low on purpose).
let COV_RED: color = Color(0.16, 0.015, 0.015, 1.0)
let COV_BLUE: color = Color(0.015, 0.03, 0.17, 1.0)
let COV_NEUTRAL: color = Color(0.17, 0.13, 0.07, 1.0)
let COV_ASSASSIN: color = Color(0.008, 0.008, 0.008, 1.0)

mod other(team: int) -> int {
  return if team == ROLE_RED then ROLE_BLUE else ROLE_RED
}

mod coverColorOf(role: int) -> color {
  return if role == ROLE_RED then COV_RED
    else if role == ROLE_BLUE then COV_BLUE
    else if role == ROLE_ASSASSIN then COV_ASSASSIN
    else COV_NEUTRAL
}

// Hex for `<color="..">` grid markup: red, blue, assassin black, neutral tan.
mod glyphHexOf(role: int) -> string {
  return if role == ROLE_RED then "f44"
    else if role == ROLE_BLUE then "48f"
    else if role == ROLE_ASSASSIN then "000"
    else "ca8"
}

// The role VALUE at the guessed cell (caller reads roles[cell] on the exec chain).
mod classifyGuess(role: int, turnTeam: int) -> int {
  return if role == ROLE_ASSASSIN then GUESS_ASSASSIN
    else if role == turnTeam then GUESS_CORRECT
    else GUESS_WRONG
}

// Fill dst with the 25-card split IN ORDER (caller shuffles). resize fills new
// slots with the given value. Starting team gets 9.
mod buildRoles(dst: int[], startTeam: int) {
  dst.clear()
  let oth = if startTeam == ROLE_RED then ROLE_BLUE else ROLE_RED
  dst.resize(9, startTeam)       // 0..8   start team (9)
  dst.resize(17, oth)            // 9..16  other team (8)
  dst.resize(24, ROLE_NEUTRAL)   // 17..23 neutral (7)
  dst.push(ROLE_ASSASSIN)        // 24     assassin (1)
}
