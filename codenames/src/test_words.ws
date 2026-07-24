// Test: word list fills + first word. Pulse `start`; single-boolean result to chat.
import { buildWords } from "words"
let start = ReadBrickGrid()
array words: string[] = []
on start {
  buildWords(words)
  let pass = words.length() == 400 && words.get(0).Value == "AFRICA"
  BroadcastChatMessage("cn_words: " .. (if pass then "ok" else "FAIL"))
}
