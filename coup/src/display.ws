// Private per-player text. Secrecy comes from targeting a character directly
// rather than from any port. The same textId overwrites in place, so each slot
// must be re-emitted faster than HUD_LIFE or it fades out.
let HUD_LIFE = 5.0
let TID_HAND = 2
let TID_BANNER = 3
let TID_PROMPT = 5
let TID_ACTIVITY = 6
let LOG_LINES = 8

// Slots are separated by ANCHOR band, not by small positionY offsets: 0.25 is
// the upper band, 0.5 the middle, 0.8 the lower-right. Packing several slots
// into one band with ~16 units between them only works while every slot is a
// single short line -- the multi-line lobby title overlapped the prompt that
// way. This mirrors the sibling project's proven layout.

// Your own hand: bottom centre, where you'd hold cards. Anchored to the bottom
// edge (1.0) rather than the lower band (0.8) the activity log uses, so the two
// cannot collide as either grows.
mod hudHand(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_HAND, positionX = 0.0, positionY = -40.0,
    fontSize = 20, lifetime = HUD_LIFE, justify = "Center", anchorY = 1.0)
}

// Public banner: upper band. Carries the multi-line lobby title, so nothing
// else may share this band.
mod hudBanner(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_BANNER, positionX = 0.0, positionY = -30.0,
    fontSize = 24, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.25)
}

// Prompt: middle band, well clear of the banner above it.
mod hudPrompt(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_PROMPT, positionX = 0.0, positionY = 60.0,
    fontSize = 20, lifetime = HUD_LIFE, justify = "Center", anchorY = 0.5)
}

// Activity log: lower right, above the hand.
mod hudActivity(ch: character, text: string) {
  ch.DisplayText(text, textId = TID_ACTIVITY, positionX = -20.0, positionY = -170.0,
    fontSize = 12, lifetime = HUD_LIFE, justify = "Right", anchorX = 1.0, anchorY = 0.8)
}

// Applied once at cache time so every downstream use of a player name is safe.
mod sanitizeName(s: string) -> string {
  return s.Replace(";", "&scl;").Replace("<", "&lt;")
}
