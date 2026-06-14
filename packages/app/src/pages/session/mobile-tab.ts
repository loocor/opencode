export type MobileSessionTab = "session" | "changes" | "context"

export function visibleMobileSessionTab(input: { selected: MobileSessionTab; activeTab?: string }): MobileSessionTab {
  if (input.activeTab === "context") return "context"
  if (input.selected === "context") return "session"
  return input.selected
}
