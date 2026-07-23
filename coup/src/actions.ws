// Action ids are also the cycle order shown to the player.
let ACT_INCOME = 0
let ACT_FOREIGN_AID = 1
let ACT_COUP = 2
let ACT_TAX = 3
let ACT_ASSASSINATE = 4
let ACT_EXCHANGE = 5
let ACT_STEAL = 6
let ACT_COUNT = 7

// Coins the actor must pay up front, indexed by action id.
array ACT_COST: int[] = [0, 0, 7, 0, 3, 0, 0]

mod actionCost(a: int) -> int {
  let v = ACT_COST[a]
  return if v.OutOfBounds then 0 else v
}

// Coins the actor receives. This is also the amount reverted when a claim is
// successfully challenged.
array ACT_GAIN: int[] = [1, 2, 0, 3, 0, 0, 2]

mod actionGain(a: int) -> int {
  let v = ACT_GAIN[a]
  return if v.OutOfBounds then 0 else v
}

array ACT_TARGETED: bool[] = [false, false, true, false, true, false, true]

mod actionTargeted(a: int) -> bool {
  let v = ACT_TARGETED[a]
  return if v.OutOfBounds then false else v
}

// The role the actor claims, or 0 when the action claims nothing and so cannot
// be challenged. Values are role ids from cards.ws (Duke=1, Assassin=2,
// Ambassador=3, Captain=4, Contessa=5).
array ACT_CLAIM: int[] = [0, 0, 0, 1, 2, 3, 4]

mod actionClaim(a: int) -> int {
  let v = ACT_CLAIM[a]
  return if v.OutOfBounds then 0 else v
}

// The role that blocks this action, or 0 when it is unblockable. Steal is also
// blockable by the Ambassador; that second case is handled at the block site.
array ACT_BLOCKER: int[] = [0, 1, 0, 0, 5, 0, 4]

mod actionBlocker(a: int) -> int {
  let v = ACT_BLOCKER[a]
  return if v.OutOfBounds then 0 else v
}

array ACT_NAME: string[] = ["Income", "Foreign Aid", "Coup", "Tax", "Assassinate", "Exchange", "Steal"]

mod actionName(a: int) -> string {
  let v = ACT_NAME[a]
  return if v.OutOfBounds then "?" else v
}
