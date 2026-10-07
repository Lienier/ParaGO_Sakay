# System flow audit

This is a diagnostic suite. Its assertions describe safeguards that should hold. It currently **fails intentionally because it reproduces application problems**, not because failures are marked as expected or hidden.

No application source is changed. All Node application tests disable `.env` loading. MongoDB 8.2.6 runs in temporary local instances; Redis uses the dedicated nonpersistent instance described in [the Playwright setup](../playwright-system/README.md). Existing tests that request MongoDB 8.0.28 are run with the cached 8.2.6 executable, with version mismatch checking disabled. This version choice is recorded in the report. Node used for the audit was 24.13.1; the repository declares Node 22.x.

Run from the repository root:

```powershell
node tools/system-flow-audit/run-backend.cjs
node tools/system-flow-audit/run-rechecks.cjs
node .tools/playwright/node_modules/playwright/cli.js test --config tools/system-flow-audit/playwright.config.cjs
node tools/system-flow-audit/summarize.cjs
```

`run-backend.cjs` executes all 28 existing Node test files plus `test.js`, placing its generated CSV in the audit folder. The raw run retains number-coding failures on Tuesday October 6. `run-rechecks.cjs` reruns only the two affected test files, seeding a holiday after their database reset hooks. This isolates unrelated workflow checks from real weekday restrictions. It does not disable the application number-coding logic or change the original tests. Operating-rule unit checks run separately in the full backend run.

Flutter checks, from each app directory, were:

```powershell
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
```

Logs, the detailed audit, observations, traces, HTML reports and scenario inventory are in `artifacts/system_flow_audit_2026-10-06`. Use `--grep A02` with the audit Playwright command to reproduce invalid GPS unloading, or select another case ID. Selected runs overwrite the Playwright report; copy reports first if preserving an earlier full run matters. The ordinary main-flow suite remains under `tools/playwright-system`.

Fault tests temporarily reject `Notification.create` inside the local test process and restore it in `finally`. A22 accelerates TTL monitoring only in its temporary MongoDB process. Neither change affects another application instance.

See the audit report for scope: native device UI, actual GPS hardware, real cloud delivery, production failure recovery and load capacity are not validated here.
