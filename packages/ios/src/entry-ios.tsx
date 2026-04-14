// @refresh reload
import { AppBaseProviders, AppInterface, type Platform, PlatformProvider, ServerConnection } from "@opencode-ai/app"
import { createResource, createSignal, onCleanup, onMount, Show } from "solid-js"
import { render } from "solid-js/web"
import pkg from "../../app/package.json"
import { bridge } from "./bridge"
import { createBridgeStorage } from "./ios-storage"
import { Onboarding } from "./onboarding"

const syncShellBackground = (() => {
  let timer: number | undefined
  let last = ""
  return () => {
    if (timer) window.clearTimeout(timer)
    timer = window.setTimeout(() => {
      timer = undefined
      if (!bridge.available()) return
      // Avoid syncing during theme preview/highlight: only send when the committed theme id
      // in localStorage matches the current dataset theme.
      const currentTheme = document.documentElement.dataset.theme
      const storedTheme = localStorage.getItem("opencode-theme-id")
      const normalize = (id: string | null) => (id === "oc-1" ? "oc-2" : id)
      if (currentTheme && storedTheme && currentTheme !== normalize(storedTheme)) return
      const bg = getComputedStyle(document.documentElement).backgroundColor
      if (!bg || bg === "rgba(0, 0, 0, 0)" || bg === "transparent") return
      if (bg === last) return
      last = bg
      try {
        bridge.send("setShellBackground", { color: bg })
      } catch {}
    }, 250)
  }
})()

window.__OPENCODE_SYNC_SHELL_BG__ = syncShellBackground

type ServerConfig = {
  url: string
  displayName?: string
  username?: string
  password?: string
}

const credentialStorage = createBridgeStorage("opencode.settings.dat")

const normalizeServerUrl = (input: string) => {
  const trimmed = input.trim()
  if (!trimmed) return
  const withProtocol = /^https?:\/\//.test(trimmed) ? trimmed : `http://${trimmed}`
  return withProtocol.replace(/\/+$/, "")
}

const root = document.getElementById("root")
if (import.meta.env.DEV && !(root instanceof HTMLElement)) {
  throw new Error("Root element not found")
}

const App = () => {
  const emitResume = () => {
    window.dispatchEvent(new Event("opencode:resume"))
  }

  const platform: Platform = {
    platform: "ios",
    os: "ios",
    version: pkg.version,
    openLink: (url: string) => bridge.send("openLink", { url }),
    notify: async (title, description, href) => {
      await bridge.sendAsync("notify", { title, description, href })
    },
    back: () => window.history.back(),
    forward: () => window.history.forward(),
    restart: async () => bridge.send("reload"),
    haptic: (style: "light" | "medium" | "heavy" | "success" | "warning" | "error") => {
      bridge.send("haptic", { style })
    },
    share: async (data: { text?: string; url?: string }) => {
      const result = await bridge.sendAsync<boolean>("share", data)
      return result ?? false
    },
    speak: async (input) => {
      await bridge.sendAsync("speak", input)
    },
    stopSpeaking: async (partID) => {
      await bridge.sendAsync("stopSpeaking", { partID })
    },
    pauseSpeaking: async (partID) => {
      await bridge.sendAsync("pauseSpeaking", { partID })
    },
    resumeSpeaking: async (partID) => {
      await bridge.sendAsync("resumeSpeaking", { partID })
    },
    onSpeechState: (cb) =>
      bridge.on("speechState", (payload) => {
        if (!payload || typeof payload !== "object") return
        const speaking = "speaking" in payload ? payload.speaking : undefined
        if (typeof speaking !== "boolean") return
        const paused = "paused" in payload ? payload.paused : undefined
        if (paused !== undefined && typeof paused !== "boolean") return
        const partID = "partID" in payload && typeof payload.partID === "string" ? payload.partID : undefined
        cb({ speaking, paused, partID })
      }),
    getDefaultServer: async () => {
      const result = await bridge.sendAsync<string | null>("getDefaultServerUrl")
      return result ? ServerConnection.Key.make(result) : null
    },
    setDefaultServer: async (key) => {
      await bridge.sendAsync("setDefaultServerUrl", {
        url: key ? String(key) : null,
      })
    },
    storage: (name?: string) => createBridgeStorage(name),
    // iOS 通知权限相关方法
    getPushState: async () => {
      return await bridge.sendAsync("getPushState")
    },
    requestPushPermission: async () => {
      return await bridge.sendAsync("requestPushPermission")
    },
    setNotificationBadge: async (count) => {
      await bridge.sendAsync("setNotificationBadge", { count })
    },
    openSystemSettings: () => {
      bridge.send("openSystemSettings")
    },
  }

  const [defaultConfig] = createResource(async () => {
    if (!platform.getDefaultServer) return null
    const key = await Promise.resolve(platform.getDefaultServer?.()).catch(() => null)
    if (!key) return null
    const url = String(key)
    const displayName = await credentialStorage.getItem("displayName").catch(() => null)
    const username = await credentialStorage.getItem("username").catch(() => null)
    const password = await credentialStorage.getItem("password").catch(() => null)
    return {
      url,
      displayName: displayName || undefined,
      username: username || undefined,
      password: password || undefined,
    } as ServerConfig
  })

  const [completedConfig, setCompletedConfig] = createSignal<ServerConfig | null>(null)

  const handleOnboardingComplete = async (server: {
    url: string
    displayName?: string
    username?: string
    password?: string
  }) => {
    const normalized = normalizeServerUrl(server.url)
    if (!normalized) return
    await platform.setDefaultServer?.(ServerConnection.Key.make(normalized))
    if (server.displayName) await credentialStorage.setItem("displayName", server.displayName)
    else await credentialStorage.removeItem("displayName")
    if (server.username) await credentialStorage.setItem("username", server.username)
    else await credentialStorage.removeItem("username")
    if (server.password) await credentialStorage.setItem("password", server.password)
    else await credentialStorage.removeItem("password")
    setCompletedConfig({
      url: normalized,
      displayName: server.displayName,
      username: server.username,
      password: server.password,
    })

    // Onboarding 完成后请求通知权限
    setTimeout(() => {
      bridge.sendAsync("requestPushPermission").catch(() => {
        // 忽略错误，用户可能拒绝权限
      })
    }, 500)
  }

  onMount(() => {
    document.documentElement.dataset.platform = "ios"
    requestAnimationFrame(() => syncShellBackground())

    const rootEl = document.documentElement
    const observer = new MutationObserver(() => {
      syncShellBackground()
    })
    // Theme dropdown selections often update `data-theme` frequently (preview/highlight/commit).
    // For stability, only react to the actual light/dark scheme flip (`data-color-scheme`).
    observer.observe(rootEl, { attributes: true, attributeFilter: ["data-color-scheme"] })

    const handleClick = (event: MouseEvent) => {
      const link = (event.target as HTMLElement | null)?.closest("a.external-link") as HTMLAnchorElement | null
      if (!link?.href) return
      event.preventDefault()
      platform.openLink(link.href)
    }

    const stopLifecycle = bridge.on("appLifecycle", (payload) => {
      const state =
        typeof payload === "string"
          ? payload
          : typeof payload === "object" && payload
            ? (payload as { state?: unknown }).state
            : undefined
      if (state !== "active") return
      emitResume()
    })

    // 如果已经配置过服务器（非首次启动），请求通知权限
    if (defaultConfig() && !defaultConfig.loading) {
      setTimeout(() => {
        bridge.sendAsync("requestPushPermission").catch(() => {
          // 忽略错误，用户可能拒绝权限
        })
      }, 1000)
    }

    document.addEventListener("click", handleClick)
    onCleanup(() => {
      observer.disconnect()
      document.removeEventListener("click", handleClick)
      stopLifecycle()
    })
  })

  return (
    <PlatformProvider value={platform}>
      <AppBaseProviders>
        <Show when={!defaultConfig.loading}>
          <Show
            when={defaultConfig() || completedConfig()}
            fallback={<Onboarding onComplete={handleOnboardingComplete} />}
          >
            {(cfg) => {
              const config = cfg()
              if (!config) return undefined
              const conn: ServerConnection.Http = {
                type: "http",
                displayName: config.displayName,
                http: {
                  url: config.url,
                  username: config.username,
                  password: config.password,
                },
              }
              return <AppInterface defaultServer={ServerConnection.key(conn)} servers={[conn]} />
            }}
          </Show>
        </Show>
      </AppBaseProviders>
    </PlatformProvider>
  )
}

if (root instanceof HTMLElement) {
  render(() => <App />, root)
}
