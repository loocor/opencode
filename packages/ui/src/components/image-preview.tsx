import { Dialog as Kobalte } from "@kobalte/core/dialog"
import { createStore } from "solid-js/store"
import { onCleanup } from "solid-js"
import { useI18n } from "../context/i18n"
import { IconButton } from "./icon-button"

export interface ImagePreviewProps {
  src: string
  alt?: string
}

export function ImagePreview(props: ImagePreviewProps) {
  const i18n = useI18n()
  const [store, setStore] = createStore({ x: 0, y: 0, scale: 1 })
  const pointers = new Map<number, { x: number; y: number }>()
  let pinch: { dist: number; scale: number } | undefined
  let drag: { x: number; y: number; px: number; py: number } | undefined
  let lastTap = 0

  const transform = () => `translate(${store.x}px, ${store.y}px) scale(${store.scale})`

  const reset = () => {
    pinch = undefined
    drag = undefined
    pointers.clear()
  }

  const releasePointer = (id: number, settle: boolean) => {
    pointers.delete(id)
    if (pointers.size < 2) pinch = undefined
    if (pointers.size !== 0) return
    drag = undefined
    if (settle && store.scale <= 1) setStore({ x: 0, y: 0 })
  }

  onCleanup(reset)

  return (
    <div data-component="image-preview">
      <div data-slot="image-preview-container">
        <Kobalte.Content data-slot="image-preview-content">
          <div data-slot="image-preview-header">
            <Kobalte.CloseButton
              data-slot="image-preview-close"
              as={IconButton}
              icon="close"
              variant="ghost"
              aria-label={i18n.t("ui.common.close")}
            />
          </div>
          <div
            data-slot="image-preview-body"
            onPointerDown={(event) => {
              event.currentTarget.setPointerCapture(event.pointerId)
              pointers.set(event.pointerId, { x: event.clientX, y: event.clientY })
              if (pointers.size === 2) {
                const [a, b] = Array.from(pointers.values())
                pinch = { dist: distance(a, b), scale: store.scale }
                drag = undefined
                return
              }
              if (store.scale > 1) {
                drag = { x: store.x, y: store.y, px: event.clientX, py: event.clientY }
              }
              const now = Date.now()
              if (now - lastTap < 280) {
                lastTap = 0
                if (store.scale !== 1) {
                  setStore({ x: 0, y: 0, scale: 1 })
                  return
                }
                setStore({ x: 0, y: 0, scale: 2.5 })
                return
              }
              lastTap = now
            }}
            onPointerMove={(event) => {
              if (!pointers.has(event.pointerId)) return
              pointers.set(event.pointerId, { x: event.clientX, y: event.clientY })
              if (pointers.size >= 2 && pinch) {
                const [a, b] = Array.from(pointers.values())
                const next = pinch.dist > 0 ? pinch.scale * (distance(a, b) / pinch.dist) : pinch.scale
                setStore({ scale: clamp(next, 0.5, 8) })
                return
              }
              if (!drag || pointers.size !== 1) return
              setStore({
                x: drag.x + event.clientX - drag.px,
                y: drag.y + event.clientY - drag.py,
              })
            }}
            onPointerUp={(event) => releasePointer(event.pointerId, true)}
            onPointerCancel={(event) => releasePointer(event.pointerId, false)}
            onWheel={(event) => {
              event.preventDefault()
              const next = event.deltaY < 0 ? store.scale * 1.12 : store.scale / 1.12
              const scale = clamp(next, 0.5, 8)
              setStore({
                scale,
                x: scale <= 1 ? 0 : store.x,
                y: scale <= 1 ? 0 : store.y,
              })
            }}
          >
            <img
              src={props.src}
              alt={props.alt ?? i18n.t("ui.imagePreview.alt")}
              data-slot="image-preview-image"
              draggable={false}
              style={{ transform: transform() }}
            />
          </div>
        </Kobalte.Content>
      </div>
    </div>
  )
}

function distance(a: { x: number; y: number }, b: { x: number; y: number }) {
  return Math.hypot(a.x - b.x, a.y - b.y)
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value))
}
