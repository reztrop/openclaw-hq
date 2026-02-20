# OpenClaw HQ — Lofi Cyberpunk Overhaul Execution Tasks

**Task ID:** 48283B83-97A9-4099-AFFE-13FE8F82CEB8  
**Status baseline:** Current visual pass already landed (theme + shell + chat foundation). This plan starts from the documented “Next Passes.”

## Delivery Model (Serial by Agent)
Each phase runs in strict order: **Atlas research/spec → Matrix implementation → Prism verification → Scope gate**.
No downstream phase starts until prior phase acceptance criteria are met.

---

## Phase 1 — Shared UI Primitive System
### 1A) Atlas — Design/Constraint Packet
**Work items**
- Define canonical spec for `HQPanel`, `HQBadge`, `HQButton`:
  - variants, states (default/hover/active/disabled/focus)
  - token usage (color, glow, border, radius, spacing, typography)
  - interaction behavior (animation durations/easing)
- Define accessibility constraints for each primitive:
  - minimum contrast by state
  - focus ring visibility rules
  - reduced-motion fallback behavior
- Produce migration mapping: which existing controls map to which primitive variant.

**Acceptance criteria**
- Single written spec exists covering all three primitives and all states.
- Each state includes explicit token references (no “use similar styling” ambiguity).
- Accessibility constraints are explicit and testable per component state.

### 1B) Matrix — Primitive Build + First Migrations
**Work items**
- Implement `HQPanel`, `HQBadge`, `HQButton` as reusable shared components.
- Integrate token-driven styling (no duplicated ad-hoc color literals in migrated surfaces).
- Migrate shell-level high-frequency surfaces first (sidebar cards, top-level callouts, common action buttons).
- Keep all existing action handlers/logic untouched.

**Acceptance criteria**
- Components compile and are consumed by at least 3 existing surfaces each (where applicable).
- Existing interactions remain functionally identical (click paths unchanged).
- Build passes (`swift build`) with no regressions.

### 1C) Prism — Primitive QA/Security Gate
**Work items**
- Validate state rendering for each primitive across interactive states.
- Verify no logic-layer diffs beyond view/theme/component boundaries.
- Run smoke regression on navigation + common actions.

**Acceptance criteria**
- QA checklist marks component states verified (default/hover/active/disabled/focus).
- Confirms no auth/network/command/config behavior changed.
- Gate result recorded: pass/fail with blocking defects listed.

---

## Phase 2 — Screen-by-Screen Migration and Polish
### 2A) Atlas — Per-Screen Visual Intent Brief
**Work items**
- Define per-screen visual hierarchy + emphasis map for:
  - Agents
  - Tasks
  - Usage
  - Activity
  - Settings
- Specify any screen-specific exceptions to primitive defaults.

**Acceptance criteria**
- Each screen has a short intent brief with primary/secondary emphasis zones.
- Exception rules are explicitly listed and justified.

### 2B) Matrix — Sequential Screen Implementation
**Work items**
- Migrate in order: **Agents → Tasks → Usage → Activity → Settings**.
- Replace legacy bespoke styling with primitives/tokens.
- Ensure each screen includes explicit empty/loading/error state styling consistency.

**Acceptance criteria (per screen before moving to next)**
- Screen fully migrated to primitive/token system (or documented exception).
- Empty/loading/error states are present and visually consistent.
- No behavioral regressions in core workflows on that screen.

### 2C) Prism — Per-Screen Regression Gates
**Work items**
- After each screen migration, run focused regression + visual consistency check.
- Validate keyboard navigation and focus visibility on key controls.

**Acceptance criteria**
- One gate decision per screen (5 total), with defects triaged before next screen starts.
- Keyboard usability remains intact for migrated controls.

---

## Phase 3 — Accessibility Hardening
### 3A) Atlas — A11y Final Spec
**Work items**
- Define reduced-motion policy and exact behavior changes (what animates vs what does not).
- Produce final contrast targets across critical UI states.

**Acceptance criteria**
- Reduced-motion behavior is documented at component and screen level.
- Contrast target matrix exists for critical text/background/status combinations.

### 3B) Matrix — Accessibility Implementation
**Work items**
- Add reduced-motion toggle/plumbing and apply it across animated surfaces.
- Adjust tokens/styles to satisfy approved contrast targets.

**Acceptance criteria**
- Reduced-motion toggle is functional and disables/reduces targeted motion consistently.
- Contrast fixes applied without reintroducing style divergence.
- Build passes after accessibility changes.

### 3C) Prism — Accessibility Verification Gate
**Work items**
- Validate reduced-motion behavior end-to-end.
- Perform contrast audit on critical states/screens.

**Acceptance criteria**
- Accessibility gate marked pass with evidence notes.
- Any remaining issues are documented as blockers or explicitly deferred with rationale.

---

## Phase 4 — Release Validation + Final Signoff
### 4A) Matrix — Build/Packaging Pass
**Work items**
- Run final build/package scripts and ensure release artifacts are produced cleanly.

**Acceptance criteria**
- `swift build` passes.
- `bash build-app.sh` passes.
- Application bundle runs with new theme in target environment.

### 4B) Prism — Final Ship Gate
**Work items**
- Execute full regression matrix across tabs and key workflows.
- Reconfirm security boundary: visual/UX-only changes.
- Produce final QA/security verdict doc.

**Acceptance criteria**
- Final report generated with explicit ship/no-ship recommendation.
- No unresolved P0/P1 blockers.

### 4C) Scope — Closure
**Work items**
- Verify all phase acceptance criteria were met in sequence.
- Record any deferred items as Phase 2+ backlog commitments.

**Acceptance criteria**
- Closure note includes completed phases, deferred items, and next optional enhancement queue.

---

## Dependency Chain
1. Phase 1 primitives must complete before broad screen migrations.
2. Phase 2 must complete before final accessibility hardening to avoid rework.
3. Phase 3 must complete before release gate.
4. Phase 4 signoff required for ship recommendation.

## Risk Controls
- **Scope creep risk:** New feature asks (logic changes, workflow changes) are out of scope; queue to later phase.
- **Style divergence risk:** Any ad-hoc per-screen styling must be documented exception or rejected.
- **Accessibility drift risk:** Contrast/reduced-motion checks must run after each major migration cluster, not only at end.
- **Regression risk:** Per-screen Prism gate prevents compounding defects.
