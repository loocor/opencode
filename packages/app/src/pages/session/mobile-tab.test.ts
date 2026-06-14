import { expect, test } from "bun:test"
import { visibleMobileSessionTab } from "./mobile-tab"

test("shows context when the session tab state is active on context", () => {
  expect(visibleMobileSessionTab({ selected: "session", activeTab: "context" })).toBe("context")
})

test("falls back to session when context was selected locally but is no longer active", () => {
  expect(visibleMobileSessionTab({ selected: "context", activeTab: undefined })).toBe("session")
})

test("keeps explicit mobile changes selection outside context", () => {
  expect(visibleMobileSessionTab({ selected: "changes", activeTab: "empty" })).toBe("changes")
})
