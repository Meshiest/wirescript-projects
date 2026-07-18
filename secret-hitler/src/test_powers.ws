// Test: fascist board power LUT + role distribution. Pulse `start`; result to chat.

import { PW_EXECUTE, PW_INVESTIGATE, PW_NONE, PW_PEEK, PW_SPECIAL, fascistCount, liberalCount, powerAt } from "powers"

in start: exec

// One slot check: "" when powerAt matches, else a mismatch line.
mod chk(pc: int, slot: int, want: int) -> string {
  let got = powerAt(pc, slot)
  return if got == want then "" else "powerAt(${pc},${slot})=${got} exp=${want}\n"
}

mod chkRoles(pc: int, wantF: int, wantL: int) -> string {
  let f = fascistCount(pc)
  let l = liberalCount(pc)
  let cf = if f != wantF then "fasc(${pc})=${f} exp=${wantF}\n" else ""
  let cl = if l != wantL then "lib(${pc})=${l} exp=${wantL}\n" else ""
  return cf .. cl
}

on start {
  // 5-6p board: -, -, Peek, Kill, Kill, (win)
  let b0 = chk(5, 1, PW_NONE) .. chk(5, 2, PW_NONE) .. chk(6, 3, PW_PEEK)
    .. chk(5, 4, PW_EXECUTE) .. chk(6, 5, PW_EXECUTE) .. chk(5, 6, PW_NONE)
  // 7-8p board: -, Investigate, Special Election, Kill, Kill, (win)
  let b1 = chk(7, 1, PW_NONE) .. chk(8, 2, PW_INVESTIGATE) .. chk(7, 3, PW_SPECIAL)
    .. chk(8, 4, PW_EXECUTE) .. chk(7, 5, PW_EXECUTE) .. chk(8, 6, PW_NONE)
  // 9-10p board: Investigate, Investigate, Special Election, Kill, Kill, (win)
  let b2 = chk(9, 1, PW_INVESTIGATE) .. chk(10, 2, PW_INVESTIGATE) .. chk(9, 3, PW_SPECIAL)
    .. chk(10, 4, PW_EXECUTE) .. chk(9, 5, PW_EXECUTE) .. chk(10, 6, PW_NONE)
  // Role distribution: 5:3L/1F, 6:4/1, 7:4/2, 8:5/2, 9:5/3, 10:6/3 (+Hitler each)
  let r = chkRoles(5, 1, 3) .. chkRoles(6, 1, 4) .. chkRoles(7, 2, 4)
    .. chkRoles(8, 2, 5) .. chkRoles(9, 3, 5) .. chkRoles(10, 3, 6)
  let msg = b0 .. b1 .. b2 .. r
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("sh_powers: ${ok}")
}
