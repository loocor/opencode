import { bundledLanguagesInfo } from "shiki"
import { getFilename } from "@opencode-ai/core/util/path"
import type { FilePart, ToolPart } from "@opencode-ai/sdk/v2"

export function attached(part: FilePart) {
  return part.url.startsWith("data:") && !inline(part)
}

export function inline(part: FilePart) {
  return part.source?.text?.start !== undefined && part.source?.text?.end !== undefined
}

export function kind(part: FilePart) {
  return part.mime.startsWith("image/") ? "image" : "file"
}

export function imageAttachment(part: { mime?: string; url?: string }) {
  if (!part.url || !part.mime?.startsWith("image/")) return false
  return part.url.startsWith("data:") || part.url.startsWith("blob:") || /^https?:\/\//.test(part.url)
}

export function toolImages(state: ToolPart["state"] | undefined) {
  if (!state || state.status !== "completed") return []
  return (state.attachments ?? []).filter(imageAttachment)
}

// language metadata only; grammars stay behind shiki's lazy imports
const LANGUAGE_NAMES = new Map<string, string>(
  bundledLanguagesInfo.flatMap((info) =>
    [info.id, ...(info.aliases ?? [])].map((alias) => [alias, info.name] as [string, string]),
  ),
)

// attachments carry text/plain for all text files, so the label comes from the extension;
// filename may be an absolute path, so extract the basename before looking for one
export function typeLabel(filename: string, mime: string, fallback: string) {
  if (mime === "application/pdf") return "PDF"
  const base = getFilename(filename)
  // idx 0 is a dotfile like .gitignore, not an extension
  const idx = base.lastIndexOf(".")
  const suffix = idx <= 0 ? "" : base.slice(idx + 1).toLowerCase()
  if (!suffix) return fallback
  return LANGUAGE_NAMES.get(suffix) ?? suffix.toUpperCase()
}
