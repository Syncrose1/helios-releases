# HELIOS

The always-there layer between you and your Linux desktop (Hyprland): a radial menu at your cursor,
push-to-talk dictation into any text field, an instant search and ask box, and point-at-the-screen
questions, all without leaving the workspace you're in.

## Install, update or uninstall

```
curl -fsSL https://raw.githubusercontent.com/Syncrose1/helios-releases/main/install/install.sh | bash
```

Run the same line again to update or uninstall. Without a terminal, or to skip the menu:
`... | bash -s -- install`, `... | bash -s -- uninstall`, `... | bash -s -- purge`.

Needs Linux x86_64 with Hyprland's Lua config (0.55+). The installer offers to install
[Kando](https://kando.menu) for the radial menu. For AI, sign in to Claude Code, Codex or Grok
Build, or run a local OpenAI-compatible model on port 8081.

By Syncra (Raahat Shah).
