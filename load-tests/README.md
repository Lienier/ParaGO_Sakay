# ParaGO Phase 10 Load Tests

These tests may target only an isolated hostname containing `staging`, or
localhost. The known production DigitalOcean hostname is rejected.

## Preparation

1. Run `npm run phase10:fixtures` to create 100 synthetic drivers and 500
   synthetic passengers in `parago_staging`.
2. Keep `.secure-backups/phase10-load-manifest.json` private. It contains
   short-lived staging-only access tokens.
3. Create `artifacts/phase10` before running k6.

## REST Workload

Run k6 from the repository root. Example target profile:

```powershell
$env:BASE_URL='https://parago-capacity-staging.example'
$env:DRIVER_VUS='50'
$env:PASSENGER_VUS='200'
$env:DURATION='2h'
k6 run load-tests/k6/rest-capacity.js
```

Large runs never call Google Routes. A separately approved small live test must
set both `ALLOW_LIVE_GOOGLE=true` and `GOOGLE_BUDGET_APPROVED=true`.

## Socket.IO Workload

Run alongside the REST driver workload so route batches are generated:

```powershell
npm run phase10:socket -- --url=https://parago-capacity-staging.example --passengers=200 --duration=7200
```

Results are written under the ignored `artifacts/phase10` directory.
