# OpenClaw HQ — Lofi Cyberpunk Overhaul

## Empty State Consistency — Screenshot Checklist

> Note: Before shots already captured (see existing files in this folder). Add after shots with matching view/state names.

### Required States
- [ ] Empty states (Chat, Tasks columns, Projects, Skills, Usage, Activity Log, Agent Management, Settings provider empty)
- [ ] Loading states (e.g., progress spinners / in-flight operations)
- [ ] Error states (e.g., Tasks load error, update failure, gateway offline)
- [ ] Modal states (e.g., Task edit, Add/Edit Agent, Delete confirm)
- [ ] Hover states (buttons, cards, rows)
- [ ] Focus states (text fields, toggles)

### Accessibility
- [ ] Reduced Motion: ON (repeat above where applicable)
- [ ] Reduced Motion: OFF (repeat above where applicable)

### Naming Convention
Use the following pattern:
```
<screen>-<state>-<motion>.png
```
Examples:
- `chat-empty-motion-off.png`
- `tasks-empty-motion-on.png`
- `settings-providers-empty-motion-off.png`
