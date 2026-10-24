# Store work UX audit: first delivery

Parent: #315. Workstream: #320. This records verified scenarios, not full UX sign-off.
Baseline: `02e0abb`; implementation and integration heads are recorded in the PR and issue evidence.
Local fixtures only; no production or billable notification checks.

## Reproduced findings and fixes

| Finding | Persona / observed behavior | Result |
| --- | --- | --- |
| #339 | Area opens My Tasks detail and reaches metadata without a route to the permitted monitor. | Area/HQ/custom monitors can open task progress at the relevant store anchor or the scoped checklist review. Stores keep execution links; mixed HQ/store memberships use HQ chrome. |
| #340 | One tap deletes the device's only queued proof copy; IndexedDB count changes 1→0 without a dialog. | Localized confirmation explains permanent loss of unsent answers/files. Cancel preserves the queue; confirming removes only the chosen record. |
| #344 | An inbox-only custom role can POST task completion (200, status completed); an execute-only role's My Tasks link redirects away from the task. | Inbox-local read/execute gates govern index, show and mutations. Read-only task controls are hidden, execute-only users can execute tasks without seeing news, and direct denied POSTs cannot attach files or write events. |

## Verification matrix

Browser: real installed Chromium, 390px phone, FR/AR (including RTL and no horizontal overflow).
Regression: isolated PostgreSQL test database, one worker.

| Source feature / goal | Persona and entry-to-result scenario | Evidence and observed outcome |
| --- | --- | --- |
| #35 comments | Store task → comment after completion → area monitor → threaded reply. | New browser handoff passes. Mentions remain subject to the existing focused comment regression; not a manual mention-notification sign-off. |
| #37 My Tasks | Area/HQ/store list → detail → authorized monitor or execution. | FR/AR browser passes; Rails covers scoped/custom monitors, feature gates, foreign IDs and mixed HQ/store memberships. |
| #38 Today's Tasks | Store home → daily work. | Home-priority/navigation audit belongs to #318. This pass verifies the receiving store task execution, not every home ordering/empty-state scenario. |
| #39 history | Complete with proof → area opens store-specific monitor → expand actor/history. | Browser passes; existing media regression also opens the audit evidence view. |
| #40 monitoring | HQ/area open task progress and receiving store evidence. | Browser handoff passes. Full analytics/percentage usability sign-off remains open. |
| #261 multi-file proof | Select files offline → queue/compress → mocked422 → retry once → persisted gallery. | Existing real-browser proof regression passes. |
| #262 signature/video | Sign/upload video offline → retain after failure/reload → sync → store, HQ and audit evidence. | Existing real-browser media regression passes. |
| #272 offline workspaces | Cache private task/inbox/KB → offline navigation → stale409 → account switch → restore/resubmit once. | Real service-worker browser regression passes, including tenant isolation. New discard test retains two records' answers/files across cancel/reload and deletes only the chosen record after confirmation. |
| Role boundaries | Read-only inbox versus execute-only task work; every inbox action; foreign store/tenant; HQ/area; disabled/legacy mode. | Focused Rails malicious-request and UI tests pass, including no partial attachments/events and retained critical-broadcast checks. All new permission and confirmation copy has FR/AR/EN/ES coverage. |

## Evidence reuse and remaining work

- Five browser flows pass: persona handoff, confirmed queue discard, private offline workspaces, signature/video and multi-file proof.
- Failed harness attempts were corrected: wait for Turbo navigation before inspecting a page, read dialog expectations before opening a blocking native confirmation, and do not assume IndexedDB UUID keys preserve insertion order. No application retry or security gate was weakened.
- Keep #320 open: complete the remaining persona/state checklist, especially Today ordering, full keyboard/focus recovery and monitoring comprehension. Approval rejection/resubmission is covered in the second delivery below. Passing implementation tests alone do not close those UX rows.


## Second delivery: review and correction recovery

Baseline: `36213e7`; final PR head records the tested implementation.

| Finding | Reproduced result | Fix and verification |
| --- | --- | --- |
| #351 multi-choice entry/correction | An unanswered multi-choice task returns500 before the completion form opens (`nil.include?`). After rejection, unchecking all optional choices leaves the old answer saved. | Nil-safe selection; explicit empty selection in Morocco/legacy forms; FR/AR label equivalence retains choices across language changes. Required choices still reject an empty correction without losing the previous answer. Unknown historical labels remain readable. |
| #352 pending answers | While waiting for approval, submitted text/choice/signature answers disappear although the proof gallery remains. | Submitted answers are visible read-only while pending, with question-labelled signature images; pending/completed tasks have no editable submission controls. |
| #353 read-only monitoring | A monitor-only area role is shown verdict buttons whose POST authorization denies access. | Target-store reviewer controls use the same combined verdict/escalate membership scope as the server. Read-only users retain evidence/history/comments and existing corrective links, without verdict or corrective-creation forms. |

Real Chromium FR and AR phone journeys now verify store submission with text, multi-choice, signature and a file; HQ/area rejection; opposite-language correction with retained text/selected choice/proof; clearing an optional choice; resubmission; approval by the other reviewer; and final store evidence plus actor/rejection history. Two new browser cases pass. A separate FR/AR390px read-only reviewer check verifies evidence/history/comments remain available, mutation controls are absent, and neither locale overflows.

Focused integration checks cover initial legacy/Morocco forms, four read-only answer locales, retained proof/signature IDs, explicit choice clearing and required-choice rejection, translated/unknown answer labels, pending/completed/rejected monitor states, split capability memberships, authorized HQ/area/acting platform admin, and rejected cross-store/tenant access. Existing approval/media/execution regression checks remain in the focused verification run. The server's reviewer authorization is unchanged.

#320 remains open for Today ordering, complete keyboard/focus/error recovery and monitoring comprehension. No production, user-research or paid-notification verification is claimed.
