# ParaGO Tester APK Builds

Use `scripts/build-tester-apks.ps1` to create the passenger and driver APKs
used for private thesis testing.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build-tester-apks.ps1
```

The script produces universal APKs in the ignored `dist` directory. AWS is the
primary API endpoint. At application startup, DigitalOcean is selected when
the AWS custom domain or health endpoint is unavailable. The fallback health
probe allows for a cold service and retries before endpoint selection. When no
health probe succeeds, the app prefers the configured fallback instead of
returning to the already-failed AWS hostname.

The fallback assumes both deployments run compatible backend versions, use
the same intended MongoDB Atlas database, and share compatible authentication
configuration. Endpoint selection occurs at startup, so restart the app to
re-evaluate availability after an outage.

Generated APKs use the current development signing configuration and are for
private testing only. Do not publish them to an application store.
