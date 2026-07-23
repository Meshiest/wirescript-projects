// Role identifiers. These values double as the public card-slot encoding for a
// revealed influence, so they are fixed by the board's display and must not be
// renumbered.
let CARD_NONE = 0 // live influence, face-down
let CARD_DUKE = 1
let CARD_ASSASSIN = 2
let CARD_AMBASSADOR = 3
let CARD_CAPTAIN = 4
let CARD_CONTESSA = 5
let CARD_HIDDEN = 15 // not participating
let ROLE_COUNT = 5

// Indexed by role id. Index 0 is unused padding -- CARD_NONE and any
// out-of-range id are rejected by the guard below before the array read, so
// cardName/cardIcon return the same "?" / "" default the old if-chain did.
array CARD_NAMES: string[] = ["?", "Duke", "Assassin", "Ambassador", "Captain", "Contessa"]
array CARD_ICONS: string[] = ["", '<color="8800AA"><b><icon>star</></></>', '<color="222222"><b><icon>skull</></></>', '<color="DDDD00"><b><icon>arrows-to-dot</></></>', '<color="8888FF"><b><icon>anchor</></></>', '<color="FF0011"><b><icon>gem</></></>']
// Bare icon glyph names, indexed the same as CARD_ICONS but without any
// markup -- cardTextColored below needs the glyph on its own so it can wrap
// it in a caller-supplied colour instead of each role's fixed one.
array CARD_ICON_GLYPHS: string[] = ["", "star", "skull", "arrows-to-dot", "anchor", "gem"]

mod cardName(c: int) -> string {
  let v = CARD_NAMES[c]
  return if v.OutOfBounds then "?" else v
}

mod cardIcon(c: int) -> string {
  let v = CARD_ICONS[c]
  return if v.OutOfBounds then "" else v
}

mod cardText(c: int) -> string {
  return "${cardIcon(c)} ${cardName(c)}"
}

// Same icon+name as cardText, but rendered entirely in the supplied colour
// instead of the role's own fixed one, and as a single colour scope (icon and
// name share the one <color> tag rather than the icon nesting its own inside
// it). Callers that need to highlight a card -- overriding its role colour
// with a cursor colour -- must use this instead of wrapping cardText's output
// in a second <color> tag: nesting two <color> tags breaks the game's
// rich-text closer (the inner close consumes the outer one and the colour
// runs on into whatever text follows), which is exactly the bug this exists
// to avoid. See main.ws's cardFanEntryText for the caller.
mod cardTextColored(c: int, color: string) -> string {
  let glyph = CARD_ICON_GLYPHS[c]
  return '<color="${color}"><b><icon>${if glyph.OutOfBounds then "" else glyph}</></> ${cardName(c)}</>'
}
