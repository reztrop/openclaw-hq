# OpenClaw HQ

A native macOS dashboard for monitoring and managing your [OpenClaw](https://openclaw.com) AI agents.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6.0-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## ⚠️ Important Notice

**This app does NOT install OpenClaw.** You need OpenClaw installed and running on your machine (or a remote server) before this app is useful. OpenClaw HQ connects to your existing OpenClaw gateway to display real-time agent status, activity, usage, and to manage your agents.

---

## Features

- **First-run onboarding wizard** — connects to your gateway and imports your agents automatically
- **Agents tab** — live status, activity, token usage; gradient fallback avatars when no images are set
- **Agent management** — create, edit, and delete agents directly from the dashboard
- **Scan for missing agents** — discover agents registered with your gateway that aren't yet in the dashboard
- **Per-agent model selection** — change the AI model for any agent via `models.list`, persisted to the gateway
- **Tasks, Usage, Activity tabs** — kanban board, cost charts, and a live event log
- **macOS native** — SwiftUI, zero external dependencies, dark mode first

---

## Requirements

- **macOS 15 (Sequoia)** or later
- **OpenClaw** installed and running (gateway must be reachable at `ws://127.0.0.1:18789` by default, or a custom host/port)
- A **gateway operator token** (the onboarding wizard will help you get one)

---

## Installation

### Option A: Download the DMG (recommended)

1. Go to the [Releases](https://github.com/reztrop/OpenClawHQ/releases) page
2. Download `OpenClaw-HQ-v2.0.0.dmg`
3. Open the DMG and drag **OpenClaw HQ** to your Applications folder
4. Launch OpenClaw HQ — the onboarding wizard will guide you through setup

### Option B: Build from source

```bash
git clone https://github.com/reztrop/OpenClawHQ.git
cd OpenClawHQ
swift build -c release
bash build-app.sh
open ".build/release/OpenClaw HQ.app"
```

> **Note:** If you have Prism's active avatar at `~/.openclaw/workspace/avatars/avatar_pictures/Prism_active.png`, `build-app.sh` will use it as the app icon automatically.

---

## Getting Your Gateway Token

The onboarding wizard will try to find your token automatically by reading `~/.openclaw/openclaw.json`. If it's not there, it can generate one for you.

**Manual steps:**

1. Run this on the machine where OpenClaw is installed:
   ```bash
   openclaw doctor --generate-gateway-token --non-interactive --yes
   ```

2. Find the token in your config:
   ```bash
   cat ~/.openclaw/openclaw.json | grep -A2 '"auth"'
   ```
   The token is the value under `gateway.auth.token`.

3. Paste it into the onboarding wizard.

**Remote gateway:** If your OpenClaw gateway runs on a different machine, ask your main agent: *"Generate a gateway operator token for me."* Then use the Remote connection mode in the wizard.

---

## Architecture

- **SwiftUI + MVVM** — all `@MainActor`, Combine publishers for real-time events
- **WebSocket JSON gateway protocol** — custom challenge-response handshake with Ed25519 signing (CryptoKit)
- **Zero external dependencies** — pure Swift Package Manager
- **macOS 15+** — uses `symbolEffect`, `NavigationSplitView`, Swift 6 concurrency

---

## Project Structure

```
Sources/OpenClawDashboard/
  Models/          AppSettings, Agent, etc.
  Services/        GatewayService (WebSocket + RPC), AvatarService, SettingsService
  ViewModels/      AppViewModel, AgentsViewModel, UsageViewModel, etc.
  Views/
    Agents/        AgentManagementView, AddAgentView, EditAgentView, DeleteAgentConfirmView
    Components/    AgentAvatar, GradientAvatarView, ModelPickerView, ConnectionBanner
    Onboarding/    OnboardingView, OnboardingViewModel (5-step wizard)
    Tasks/         Kanban board
    Usage/         Cost charts
    ActivityLog/   Live event log
    Settings/      SettingsView
  Utilities/       Constants, Theme, Extensions
```

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

*Built with ❤️ for the OpenClaw community. Not affiliated with Anthropic.*
