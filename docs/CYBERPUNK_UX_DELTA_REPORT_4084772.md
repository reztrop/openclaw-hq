# OpenClaw HQ — UX Regression Spot-Check + Prism Delta Report

- **Issue:** `4084772`
- **Task:** 1300 (UX regression spot-check + Prism delta)
- **Date:** 2026-02-19
- **Reviewer:** Prism

## 1) Partial Progress Check (resume)
Existing cyberpunk QA artifacts were present and reused as baseline:
- `docs/CYBERPUNK_QA_REPORT.md`
- `docs/CYBERPUNK_REGRESSION_SECURITY_MATRIX_763D8522.md`
- `docs/CYBERPUNK_TAB_MATRIX_61511BA6.md`

## 2) Delta Implemented in This Task
### UX layout policy hardening
Extracted window-layout behavior into a deterministic policy:
- `Sources/OpenClawDashboard/Views/ContentView.swift`
  - Added `ContentLayoutPolicy` + `WindowLayoutState`
  - `updateWindowLayoutFlags(for:)` now consumes policy output instead of inline branching

This removes ambiguous inline control flow and makes compact/default behavior testable and stable.

### Regression prevention validation added
Added unit coverage for compact/default breakpoint and sidebar visibility behavior:
- `Tests/OpenClawDashboardTests/ContentLayoutPolicyTests.swift`
  - compact + chat preserves collapse state
  - compact + non-chat forces sidebar visible
  - threshold width (`1300`) is not compact and forces sidebar visible

## 3) Concrete Evidence
- **EV-4084772-001 (PASS):** `swift test`
  - 8 tests executed, 0 failures
  - Includes new `ContentLayoutPolicyTests` (3/3 pass)
- **EV-4084772-002 (PASS):** `swift build`
  - Build completed successfully

## 4) Outcome
Issue `4084772` is resolved for this scope: UX layout regression risk is now covered by deterministic policy + automated tests, with passing build/test evidence.
