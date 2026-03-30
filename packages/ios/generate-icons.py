#!/usr/bin/env python3
"""Copy OpenCode production app icon into the iOS asset catalog and web onboarding asset.

Source: packages/desktop-electron/icons/prod/ios/AppIcon-512@2x.png (1024×1024).
Run from repo root or packages/ios: python3 generate-icons.py
"""

from pathlib import Path


def main() -> None:
  root = Path(__file__).resolve().parent
  src = root.parent / "desktop-electron" / "icons" / "prod" / "ios" / "AppIcon-512@2x.png"
  if not src.is_file():
    raise SystemExit(f"missing OpenCode prod icon: {src}")

  out_set = root / "OpenCode" / "OpenCode" / "Assets.xcassets" / "AppIcon.appiconset"
  out_set.mkdir(parents=True, exist_ok=True)
  data = src.read_bytes()
  for name in ("AppIcon-light.png", "AppIcon-dark.png", "AppIcon-tinted.png"):
    path = out_set / name
    path.write_bytes(data)
    print(f"wrote {path.relative_to(root)} ({len(data)} bytes)")

  web = root / "src" / "app-icon.png"
  web.parent.mkdir(parents=True, exist_ok=True)
  web.write_bytes(data)
  print(f"wrote {web.relative_to(root)} ({len(data)} bytes)")


if __name__ == "__main__":
  main()
