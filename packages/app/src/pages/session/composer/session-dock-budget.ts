export const sessionDockMaxVar = "--session-dock-max-height"
export const sessionDockListVar = "--session-dock-list-max"

export function sessionDockBudgetFrom(view: number) {
  return Math.max(200, Math.round(Math.min(view * 0.52, view - 160)))
}

export function sessionDockBudget() {
  return sessionDockBudgetFrom(window.visualViewport?.height ?? window.innerHeight)
}

export function applySessionDockBudget(el: HTMLElement) {
  const max = sessionDockBudget()
  el.style.setProperty(sessionDockMaxVar, `${max}px`)
  el.style.setProperty(sessionDockListVar, `${Math.max(120, max - 88)}px`)
}

export function bindSessionDockBudget(el: HTMLElement) {
  const apply = () => applySessionDockBudget(el)
  apply()
  const view = window.visualViewport
  view?.addEventListener("resize", apply)
  view?.addEventListener("scroll", apply)
  window.addEventListener("resize", apply)
  return () => {
    view?.removeEventListener("resize", apply)
    view?.removeEventListener("scroll", apply)
    window.removeEventListener("resize", apply)
  }
}
