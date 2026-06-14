import { expect, test } from "bun:test"
import type { Platform } from "@/context/platform"
import { createMessageSpeechActions, type MessageSpeechState } from "./message-speech"

function speechPlatform(calls: string[]): Platform {
  return {
    platform: "ios",
    os: "ios",
    openLink() {},
    restart: async () => {},
    back() {},
    forward() {},
    notify: async () => {},
    speak: async (input) => {
      calls.push(`speak:${input.partID}:${input.text}`)
    },
    stopSpeaking: async (partID) => {
      calls.push(`stop:${partID ?? ""}`)
    },
    pauseSpeaking: async (partID) => {
      calls.push(`pause:${partID ?? ""}`)
    },
    resumeSpeaking: async (partID) => {
      calls.push(`resume:${partID ?? ""}`)
    },
  }
}

function actions(state: MessageSpeechState) {
  const calls: string[] = []
  const result = createMessageSpeechActions(speechPlatform(calls), state)
  expect(result).toBeDefined()
  return { calls, result: result! }
}

test("starts speaking an inactive text part", () => {
  const { calls, result } = actions({ speaking: false })

  result.toggle?.({ partID: "part-1", text: "hello" })

  expect(calls).toEqual(["speak:part-1:hello"])
})

test("pauses the active text part", () => {
  const { calls, result } = actions({ speaking: true, partID: "part-1" })

  result.toggle?.({ partID: "part-1", text: "hello" })

  expect(calls).toEqual(["pause:part-1"])
})

test("resumes the paused active text part", () => {
  const { calls, result } = actions({ speaking: true, paused: true, partID: "part-1" })

  result.toggle?.({ partID: "part-1", text: "hello" })

  expect(calls).toEqual(["resume:part-1"])
})

test("stops the active text part", () => {
  const { calls, result } = actions({ speaking: true, partID: "part-1" })

  result.stop?.("part-1")

  expect(calls).toEqual(["stop:part-1"])
})
