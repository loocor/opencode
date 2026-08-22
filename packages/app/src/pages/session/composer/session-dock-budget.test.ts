import { describe, expect, test } from "bun:test"
import { sessionDockBudgetFrom } from "./session-dock-budget"

describe("sessionDockBudgetFrom", () => {
  test("uses about half the viewport on a phone", () => {
    expect(sessionDockBudgetFrom(844)).toBe(439)
  })

  test("leaves room for chrome on a short viewport", () => {
    expect(sessionDockBudgetFrom(500)).toBe(260)
  })

  test("never goes below 200", () => {
    expect(sessionDockBudgetFrom(200)).toBe(200)
  })
})
