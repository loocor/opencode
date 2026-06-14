import { Component, createSignal, Show, startTransition } from "solid-js"
import { createMediaQuery } from "@solid-primitives/media"
import { Dialog } from "@opencode-ai/ui/dialog"
import { Tabs } from "@opencode-ai/ui/tabs"
import { Icon } from "@opencode-ai/ui/icon"
import { Button } from "@opencode-ai/ui/button"
import { useLanguage } from "@/context/language"
import { usePlatform } from "@/context/platform"
import { useDialog } from "@opencode-ai/ui/context/dialog"
import { SettingsGeneral } from "./settings-general"
import { SettingsKeybinds } from "./settings-keybinds"
import { SettingsProviders } from "./settings-providers"
import { SettingsModels } from "./settings-models"
import { SettingsServers } from "./settings-servers"

export const DialogSettings: Component<{ defaultValue?: string }> = (props) => {
  const language = useLanguage()
  const platform = usePlatform()
  const dialog = useDialog()
  const mobile = createMediaQuery("(max-width: 767px)")
  const isIOS = platform.platform === "ios"
  const [tab, setTab] = createSignal(props.defaultValue ?? "general")

  const showProviders = () => {
    void dialog.show(() => <DialogSettings defaultValue="providers" />)
  }

  return (
    <Dialog size="x-large" transition class={isIOS ? "ios-fullscreen-dialog" : ""}>
      <Show when={isIOS}>
        <div class="absolute top-0 left-0 right-0 z-50 flex items-center justify-between px-4 py-3 bg-surface-base border-b border-border-base">
          <Button variant="ghost" size="small" onClick={() => dialog.close()} class="text-blue-500 hover:text-blue-600">
            {language.t("common.done")}
          </Button>
          <span class="text-16-medium text-text-strong">{language.t("settings.title")}</span>
          <div class="w-16" />
        </div>
      </Show>
      <Tabs
        orientation={mobile() ? "horizontal" : "vertical"}
        variant="settings"
        value={tab()}
        onChange={(value) => void startTransition(() => setTab(value))}
        class="h-full settings-dialog"
      >
        <Show
          when={!mobile()}
          fallback={
            <Tabs.List>
              <div class="flex flex-row gap-1 w-full p-2">
                <Tabs.Trigger value="general" class="flex-1">
                  <Icon name="sliders" />
                  <span class="sr-only">{language.t("settings.tab.general")}</span>
                </Tabs.Trigger>
                <Tabs.Trigger value="shortcuts" class="flex-1">
                  <Icon name="keyboard" />
                  <span class="sr-only">{language.t("settings.tab.shortcuts")}</span>
                </Tabs.Trigger>
                <Tabs.Trigger value="servers" class="flex-1">
                  <Icon name="server" />
                  <span class="sr-only">{language.t("status.popover.tab.servers")}</span>
                </Tabs.Trigger>
                <Tabs.Trigger value="providers" class="flex-1">
                  <Icon name="providers" />
                  <span class="sr-only">{language.t("settings.providers.title")}</span>
                </Tabs.Trigger>
                <Tabs.Trigger value="models" class="flex-1">
                  <Icon name="models" />
                  <span class="sr-only">{language.t("settings.models.title")}</span>
                </Tabs.Trigger>
              </div>
            </Tabs.List>
          }
        >
          <Tabs.List>
            <div class="flex flex-col justify-between h-full w-full gap-4">
              <div class="flex flex-col gap-3 w-full pt-3">
                <div class="flex flex-col gap-3">
                  <div class="flex flex-col gap-1.5">
                    <Tabs.SectionTitle>{language.t("settings.section.desktop")}</Tabs.SectionTitle>
                    <div class="flex flex-col gap-1.5 w-full">
                      <Tabs.Trigger value="general">
                        <Icon name="sliders" />
                        {language.t("settings.tab.general")}
                      </Tabs.Trigger>
                      <Tabs.Trigger value="shortcuts">
                        <Icon name="keyboard" />
                        {language.t("settings.tab.shortcuts")}
                      </Tabs.Trigger>
                      <Tabs.Trigger value="servers">
                        <Icon name="server" />
                        {language.t("status.popover.tab.servers")}
                      </Tabs.Trigger>
                    </div>
                  </div>

                  <div class="flex flex-col gap-1.5">
                    <Tabs.SectionTitle>{language.t("settings.section.server")}</Tabs.SectionTitle>
                    <div class="flex flex-col gap-1.5 w-full">
                      <Tabs.Trigger value="providers">
                        <Icon name="providers" />
                        {language.t("settings.providers.title")}
                      </Tabs.Trigger>
                      <Tabs.Trigger value="models">
                        <Icon name="models" />
                        {language.t("settings.models.title")}
                      </Tabs.Trigger>
                    </div>
                  </div>
                </div>
              </div>
              <div class="flex flex-col gap-1 pl-1 py-1 text-12-medium text-text-weak">
                <span>{language.t("app.name.desktop")}</span>
                <span class="text-11-regular">v{platform.version}</span>
              </div>
            </div>
          </Tabs.List>
        </Show>
        <Tabs.Content value="general" class="no-scrollbar">
          <SettingsGeneral />
        </Tabs.Content>
        <Tabs.Content value="shortcuts" class="no-scrollbar">
          <SettingsKeybinds />
        </Tabs.Content>
        <Tabs.Content value="servers" class="no-scrollbar">
          <SettingsServers />
        </Tabs.Content>
        <Tabs.Content value="providers" class="no-scrollbar">
          <SettingsProviders onBack={showProviders} />
        </Tabs.Content>
        <Tabs.Content value="models" class="no-scrollbar">
          <SettingsModels />
        </Tabs.Content>
      </Tabs>
    </Dialog>
  )
}
