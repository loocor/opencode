import { describe, expect, test } from "bun:test"
import { compactAgentLabel } from "./agent-label"

describe("compactAgentLabel", () => {
  test("keeps only the display prefix for role-style names", () => {
    expect(compactAgentLabel("Atlas - Plan Executor")).toBe("Atlas")
  })

  test("keeps regular agent names unchanged", () => {
    expect(compactAgentLabel("Build Bot")).toBe("Build Bot")
  })
})
