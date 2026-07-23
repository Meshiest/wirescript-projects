// Test: action cost/gain/seatNamei/claim/blocker/name tables. Pulse `start`; result to chat.

import { CARD_DUKE, CARD_ASSASSIN, CARD_AMBASSADOR, CARD_CAPTAIN, CARD_CONTESSA } from "cards"
import { ACT_INCOME, ACT_FOREIGN_AID, ACT_COUP, ACT_TAX, ACT_ASSASSINATE,
  ACT_EXCHANGE, ACT_STEAL, ACT_COUNT, actionCost, actionGain, actionTargeted,
  actionClaim, actionBlocker, actionName } from "actions"

in start: exec

on start {
  let c1 = if ACT_COUNT != 7 then "ACT_COUNT=${ACT_COUNT} exp=7\n" else ""
  let c2 = if actionCost(ACT_COUP) != 7 then "cost_coup=${actionCost(ACT_COUP)} exp=7\n" else ""
  let c3 = if actionCost(ACT_ASSASSINATE) != 3 then "cost_assassinate=${actionCost(ACT_ASSASSINATE)} exp=3\n" else ""
  let c4 = if actionCost(ACT_INCOME) != 0 then "cost_income=${actionCost(ACT_INCOME)} exp=0\n" else ""
  let c5 = if actionCost(ACT_TAX) != 0 then "cost_tax=${actionCost(ACT_TAX)} exp=0\n" else ""
  let c6 = if actionCost(ACT_EXCHANGE) != 0 then "cost_exchange=${actionCost(ACT_EXCHANGE)} exp=0\n" else ""
  let c7 = if actionCost(ACT_STEAL) != 0 then "cost_steal=${actionCost(ACT_STEAL)} exp=0\n" else ""
  let c8 = if actionCost(ACT_FOREIGN_AID) != 0 then "cost_foreignaid=${actionCost(ACT_FOREIGN_AID)} exp=0\n" else ""
  let c9 = if actionGain(ACT_INCOME) != 1 then "gain_income=${actionGain(ACT_INCOME)} exp=1\n" else ""
  let c10 = if actionGain(ACT_FOREIGN_AID) != 2 then "gain_foreignaid=${actionGain(ACT_FOREIGN_AID)} exp=2\n" else ""
  let c11 = if actionGain(ACT_TAX) != 3 then "gain_tax=${actionGain(ACT_TAX)} exp=3\n" else ""
  let c12 = if actionGain(ACT_STEAL) != 2 then "gain_steal=${actionGain(ACT_STEAL)} exp=2\n" else ""
  let c13 = if actionGain(ACT_COUP) != 0 then "gain_coup=${actionGain(ACT_COUP)} exp=0\n" else ""
  let c14 = if actionGain(ACT_ASSASSINATE) != 0 then "gain_assassinate=${actionGain(ACT_ASSASSINATE)} exp=0\n" else ""
  let c15 = if actionGain(ACT_EXCHANGE) != 0 then "gain_exchange=${actionGain(ACT_EXCHANGE)} exp=0\n" else ""
  let c16 = if !actionTargeted(ACT_COUP) then "targeted_coup=false exp=true\n" else ""
  let c17 = if !actionTargeted(ACT_STEAL) then "targeted_steal=false exp=true\n" else ""
  let c18 = if !actionTargeted(ACT_ASSASSINATE) then "targeted_assassinate=false exp=true\n" else ""
  let c19 = if actionTargeted(ACT_TAX) then "targeted_tax=true exp=false\n" else ""
  // unclaimed actions cannot be challenged
  let c20 = if actionClaim(ACT_INCOME) != 0 then "claim_income=${actionClaim(ACT_INCOME)} exp=0\n" else ""
  let c21 = if actionClaim(ACT_COUP) != 0 then "claim_coup=${actionClaim(ACT_COUP)} exp=0\n" else ""
  let c22 = if actionClaim(ACT_FOREIGN_AID) != 0 then "claim_foreignaid=${actionClaim(ACT_FOREIGN_AID)} exp=0\n" else ""
  let c23 = if actionClaim(ACT_TAX) != CARD_DUKE then "claim_tax=${actionClaim(ACT_TAX)} exp=${CARD_DUKE}\n" else ""
  let c24 = if actionClaim(ACT_ASSASSINATE) != CARD_ASSASSIN then "claim_assassinate=${actionClaim(ACT_ASSASSINATE)} exp=${CARD_ASSASSIN}\n" else ""
  let c25 = if actionClaim(ACT_EXCHANGE) != CARD_AMBASSADOR then "claim_exchange=${actionClaim(ACT_EXCHANGE)} exp=${CARD_AMBASSADOR}\n" else ""
  let c26 = if actionClaim(ACT_STEAL) != CARD_CAPTAIN then "claim_steal=${actionClaim(ACT_STEAL)} exp=${CARD_CAPTAIN}\n" else ""
  let c27 = if actionBlocker(ACT_FOREIGN_AID) != CARD_DUKE then "blocker_foreignaid=${actionBlocker(ACT_FOREIGN_AID)} exp=${CARD_DUKE}\n" else ""
  let c28 = if actionBlocker(ACT_ASSASSINATE) != CARD_CONTESSA then "blocker_assassinate=${actionBlocker(ACT_ASSASSINATE)} exp=${CARD_CONTESSA}\n" else ""
  let c29 = if actionBlocker(ACT_STEAL) != CARD_CAPTAIN then "blocker_steal=${actionBlocker(ACT_STEAL)} exp=${CARD_CAPTAIN}\n" else ""
  let c30 = if actionBlocker(ACT_COUP) != 0 then "blocker_coup=${actionBlocker(ACT_COUP)} exp=0\n" else ""
  let c31 = if actionBlocker(ACT_TAX) != 0 then "blocker_tax=${actionBlocker(ACT_TAX)} exp=0\n" else ""
  let c32 = if actionBlocker(ACT_EXCHANGE) != 0 then "blocker_exchange=${actionBlocker(ACT_EXCHANGE)} exp=0\n" else ""
  let c33 = if actionName(ACT_INCOME) != "Income" then 'name_income="${actionName(ACT_INCOME)}" exp="Income"\n' else ""
  let c34 = if actionName(ACT_FOREIGN_AID) != "Foreign Aid" then 'name_foreignaid="${actionName(ACT_FOREIGN_AID)}" exp="Foreign Aid"\n' else ""
  let c35 = if actionName(ACT_COUP) != "Coup" then 'name_coup="${actionName(ACT_COUP)}" exp="Coup"\n' else ""
  let c36 = if actionName(ACT_TAX) != "Tax" then 'name_tax="${actionName(ACT_TAX)}" exp="Tax"\n' else ""
  let c37 = if actionName(ACT_ASSASSINATE) != "Assassinate" then 'name_assassinate="${actionName(ACT_ASSASSINATE)}" exp="Assassinate"\n' else ""
  let c38 = if actionName(ACT_EXCHANGE) != "Exchange" then 'name_exchange="${actionName(ACT_EXCHANGE)}" exp="Exchange"\n' else ""
  let c39 = if actionName(ACT_STEAL) != "Steal" then 'name_steal="${actionName(ACT_STEAL)}" exp="Steal"\n' else ""
  let msg = "${c1}${c2}${c3}${c4}${c5}${c6}${c7}${c8}${c9}${c10}${c11}${c12}${c13}${c14}${c15}${c16}${c17}${c18}${c19}${c20}${c21}${c22}${c23}${c24}${c25}${c26}${c27}${c28}${c29}${c30}${c31}${c32}${c33}${c34}${c35}${c36}${c37}${c38}${c39}"
  let ok = if msg == "" then "ok" else msg
  BroadcastChatMessage("coup_actions: ${ok}")
}
