import { describe, expect, test } from "bun:test"
import type { FilePart } from "@opencode-ai/sdk/v2"
import { attached, imageAttachment, inline, kind, toolImages, typeLabel } from "./message-file"

function file(part: Partial<FilePart> = {}): FilePart {
  return {
    id: "part_1",
    sessionID: "ses_1",
    messageID: "msg_1",
    type: "file",
    mime: "text/plain",
    url: "file:///repo/README.txt",
    filename: "README.txt",
    ...part,
  }
}

describe("message-file", () => {
  test("treats data URLs as attachments", () => {
    expect(attached(file({ url: "data:text/plain;base64,SGVsbG8=" }))).toBe(true)
    expect(attached(file())).toBe(false)
  })

  test("keeps data-backed file mentions inline", () => {
    expect(
      inline(
        file({
          source: {
            type: "file",
            path: "/repo/README.txt",
            text: { value: "@README.txt", start: 0, end: 11 },
          },
        }),
      ),
    ).toBe(true)

    const mentioned = file({
      url: "data:text/plain;base64,SGVsbG8=",
      source: {
        type: "file",
        path: "/repo/README.txt",
        text: { value: "@README.txt", start: 0, end: 11 },
      },
    })
    expect(inline(mentioned)).toBe(true)
    expect(attached(mentioned)).toBe(false)
  })

  test("separates image and file attachment kinds", () => {
    expect(kind(file({ mime: "image/png" }))).toBe("image")
    expect(kind(file({ mime: "application/pdf" }))).toBe("file")
  })

  test("accepts displayable image attachment urls", () => {
    expect(imageAttachment(file({ mime: "image/png", url: "data:image/png;base64,AA" }))).toBe(true)
    expect(imageAttachment(file({ mime: "image/png", url: "https://example.com/a.png" }))).toBe(true)
    expect(imageAttachment(file({ mime: "image/png", url: "file:///tmp/a.png" }))).toBe(false)
    expect(imageAttachment(file({ mime: "application/pdf", url: "data:application/pdf;base64,AA" }))).toBe(false)
  })

  test("reads completed tool image attachments", () => {
    expect(
      toolImages({
        status: "completed",
        input: {},
        output: "Image read successfully",
        title: "read",
        metadata: {},
        time: { start: 0, end: 1 },
        attachments: [file({ mime: "image/png", url: "data:image/png;base64,AA" })],
      }).map((item) => item.url),
    ).toEqual(["data:image/png;base64,AA"])
    expect(toolImages({ status: "running", input: {}, time: { start: 0 } })).toEqual([])
  })

  test("labels attachment types from the basename extension", () => {
    expect(typeLabel("list.md", "text/plain", "File")).toBe("Markdown")
    expect(typeLabel("/repo/src/main.ts", "text/plain", "File")).toBe("TypeScript")
    expect(typeLabel("/tmp/report.pdf", "application/pdf", "File")).toBe("PDF")
    expect(typeLabel("notes.xyz", "text/plain", "File")).toBe("XYZ")
    expect(typeLabel("/home/user/my.project/Makefile", "text/plain", "File")).toBe("File")
    expect(typeLabel(".gitignore", "text/plain", "File")).toBe("File")
    expect(typeLabel("/repo/.env", "text/plain", "File")).toBe("File")
  })
})
