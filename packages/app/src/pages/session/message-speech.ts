import type { Platform } from "@/context/platform"
import type { SpeechActions } from "@opencode-ai/ui/message-part"

export type MessageSpeechState = {
  speaking: boolean
  paused?: boolean
  partID?: string
}

export function createMessageSpeechActions(
  platform: Platform,
  state: MessageSpeechState,
): SpeechActions | undefined {
  const speak = platform.speak
  const stopSpeaking = platform.stopSpeaking
  const pauseSpeaking = platform.pauseSpeaking
  const resumeSpeaking = platform.resumeSpeaking
  if (platform.platform !== "ios" || !speak || !stopSpeaking || !pauseSpeaking || !resumeSpeaking) return

  return {
    activePartID: state.speaking ? state.partID : undefined,
    paused: state.paused,
    toggle(input) {
      if (state.speaking && state.partID === input.partID) {
        if (state.paused) {
          void resumeSpeaking(input.partID)
          return
        }
        void pauseSpeaking(input.partID)
        return
      }
      void speak(input)
    },
    stop(partID) {
      void stopSpeaking(partID)
    },
  }
}
