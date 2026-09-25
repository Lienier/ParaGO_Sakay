# Mobile app distribution and update controls

Prepared locally on 2026-09-16. Domain: `downloads.sakaygaray.com`. Downloads are public; upload and publication controls live inside the existing PC-only super-admin desktop.

## Operating policy

Normal updates are optional. Uploading creates a draft; publishing exposes its download and optional app notice. Neither action raises the minimum supported build. Only **Require major update**, with an explicit confirmation and reason, enables enforcement. **Make all updates optional** resets the minimum to zero without changing authentication or transportation records.

An outdated official app cannot create a new booking, create a trip or start a scheduled trip after a major update is required. Existing driver trips and passenger bookings/rides may finish, including boarding, transfer recovery, tracking, para alerts and unloading. The update screen remains dismissible during an existing journey. Read APIs, authentication, sign-out and support remain available. The update check runs on opening the authenticated interface, app resume and every 30 seconds. A failed optional-update check does not interrupt usage.

Build numbers come from Android's installed package metadata. The header is a compatibility signal, not device attestation: a modified client can forge its build number. Older APKs lack the update screen; distribute the first compatible version as optional before enforcing anything. Offline installed apps cannot be remotely disabled.

## Implementation

- Backend: public `GET /api/v1/mobile-updates/driver` and `/passenger` expose only the latest published release. Authenticated `/status` reports whether the update is required or deferred for a journey. No upload/publication HTTP endpoints exist.
- Desktop: `.tools/local-super-admin/app.py` now has **Mobile app releases**. Choose the selected database deliberately, reload, upload a draft, check its download/installation, then publish. Select a published release before requiring it. The latest 20 audit actions are displayed.
- Publisher: `scripts/lib/mobileReleasePublisher.cjs`. Validates the package name, non-debuggable build, universal Android ABIs, APK v2 signature and the existing signing certificate. It uploads an immutable copy and verifies S3's SHA-256 checksum and size. The maximum APK size is 250 MB. Versioned keys cannot be overwritten. Interrupted uploads may leave an unlisted object, but cannot replace the current release. No automatic destructive cleanup is performed.
- Publication: checks public download availability/size before a transaction updates the policy, publication date and audit record. An expected policy revision rejects competing/stale changes. Failed publication leaves the previous policy intact. The release source is validated with pinned app identities and the certificate of current build 9; certificate rotation requires an explicit migration, not editing the pin casually.
- Database: new `mobilereleases`, `mobilereleasepolicies` and `mobilereleaseaudits` collections. The local publisher initializes them and the unique app/build index. An absent policy means optional updates. Back up these collections with normal MongoDB backups.
- Hosting: private, encrypted, versioned S3 bucket behind CloudFront origin access control, read-only public distribution, HTTPS, immutable APK caching, short-lived page caching and a restrictive content security policy.

## Live activation — website and API active

AWS access was verified on 2026-09-16 for account `793140950230`, using `parago-terraform-admin`. Bootstrap created 12 resources; activation added the CloudFront distribution and updated only the new bucket policy. HTTPS is live at **https://downloads.sakaygaray.com**. CloudFront distribution `E3DAEWQQ4OL0GA` serves the private bucket using origin access control. No existing infrastructure was deleted.

The API was deployed from local commit `8cc6eff` through the existing SSM deployment script (command `af39e83c-190c-4c01-88c3-a04afcbe05f0`). API and worker activation, health and readiness passed. This deployment did not push the local commit to GitHub. Both live release catalogs return `latest: null` and `minimumBuild: 0`: **no APK is published and no required update is enabled**.

Verified: download page HTTPS 200, direct S3 object access 403, driver/passenger release API 200, CORS accepts the download website, MongoDB and Redis healthy, and the desktop Node AWS SDK can access the bucket. The current local AWS principal already has AdministratorAccess, so no additional grant was attached. The separate limited uploader policy is available for a future dedicated principal.

To publish the first apps: reopen the local super admin, sign in, select the intended database, open **Mobile app releases**, and reload. Upload the build-10 driver and passenger APKs listed below as drafts, check their versioned downloads and installation, then select each draft and choose **Publish optional**. The desktop's existing local sign-in is required; no password is needed in chat.

The following certificate record was added in Namecheap and verified by AWS (TTL Automatic):

| Field | Value |
| --- | --- |
| Type | CNAME |
| Host | `_4fb2c218ffa2863794a0c886531a8f3a.downloads` |
| Value | `_a922e18c3b6f587f115f14f32114670c.wzccmgtwzk.acm-validations.aws` |

The certificate ARN is `arn:aws:acm:us-east-1:793140950230:certificate/9ce46994-02b9-41d9-be02-f1123ba8e4c1` and its status is ISSUED. Keep the validation record for renewal. The separate **downloads** CNAME now points to **d3i5tdsa99vak8.cloudfront.net** and resolves publicly. The uploader configuration is saved in `.tools/local-super-admin/release-config.json`. The ignored local `deployment.auto.tfvars` keeps `certificate_ready=true` for subsequent Terraform operations.

The following steps document the activation/recovery procedure; infrastructure, DNS, uploader configuration and API deployment steps are complete:

1. Authenticate AWS CLI on this PC. Verify `aws sts get-caller-identity` identifies account `793140950230`. Do not paste access keys or tokens into chat.
2. From `infra/aws/downloads`, run `terraform init`, then `terraform plan`. Review and apply the initial plan with `certificate_ready=false`. Keep this stack's state separate from staging; protect/back up its local state or migrate it to the established private Terraform backend before operational use.
3. Read `terraform output certificate_dns_records`. In Namecheap Advanced DNS, create the exact ACM CNAME record shown. Its value cannot be known until AWS issues the certificate request. Keep this validation record for renewals.
4. After ACM shows **Issued** in **us-east-1**, run `terraform plan -var=certificate_ready=true`, review and apply with the same flag. Keep `certificate_ready=true` for subsequent operations; destruction protection prevents accidental removal if the flag is forgotten.
5. Read `terraform output download_cname_target`. Create the Namecheap CNAME **Host: downloads**, **Value: the returned CloudFront hostname**, automatic TTL. Do not use a URL or the S3 bucket as the CNAME target.
6. Attach the output uploader IAM policy to the AWS principal used on this PC. It permits only upload/read under this dedicated bucket's `releases/` prefix and grants no delete access. The desktop does not need Terraform administrator privileges for routine releases. The IAM policy does not itself restrict the principal to a physical PC; protect its credentials and use short-lived AWS sessions.
7. Save the output `local_uploader_configuration` as `.tools/local-super-admin/release-config.json`, using `.tools/local-super-admin/release-config.example.json` as a template. The file contains bucket/region/origin, never AWS credentials. AWS credentials come from the standard local credential chain.
8. Deploy the API changes and verify both public catalog routes and authenticated status. The API CORS list now permits the download domain. Upload a draft using the desktop, test its versioned download and update installation over build 9, then publish as **optional**.
9. Verify the public site, phone downloads, resumed app notices, para/boarding/unloading flow and recovery controls before any required major update. A first release of `1.0.3+10` includes update support and the preceding driver count feedback changes.

This workflow uses AWS's documented [CloudFront origin access control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html) and [S3 conditional writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html).

## Recovery

For a broken mandatory release, select its application and choose **Make all updates optional**, provide a reason and confirm. Connected apps pick up the relaxed policy on their next check; **Check again** requests it immediately. Do not delete release or security/session collections. Publish a higher, repaired build instead of overwriting an APK or downgrading Android's version code. Existing sessions that were revoked remain revoked.

Restoring an older API that lacks the release gate would remove enforcement. Use the optional-policy control to recover while keeping the repaired authentication/session implementation deployed.

## Verification

Run `npm run test:mobile-releases`, `npm test`, both Flutter suites, both Flutter analyzers, `.tools/local-super-admin/test.cjs`, `.tools/local-super-admin/test_ui.py` and `terraform validate` in the download stack. Physical Android download/install and live AWS/DNS checks remain release blockers until completed with controlled accounts. Local test results are recorded at the end of this document after the verification run.

### Local results

- Existing backend: 62 unit and 155 integration tests passed.
- Release tests: 7 passed, covering draft visibility, optional publication, required-policy recovery, stale revisions, competing publications, ongoing journeys, authentication/HTTP 426, checksum failures and retrying a previously uploaded object after a lost response.
- Driver: all 38 tests passed; analysis clean.
- Passenger: update-screen tests passed; full suite executed. Analysis reports the same eight pre-existing unused-code warnings, with no new errors.
- Local desktop: 8 database tests and 1 fake-data UI control test passed. No real account mutations were performed.
- Terraform: configuration validated successfully using the existing local Windows AWS provider. The generated lockfile currently records the Windows platform only; run `terraform providers lock -platform=windows_amd64 -platform=linux_amd64` before using this stack on another platform.
- Both universal release APKs built successfully as **1.0.3 (build 10)**. The new native integration compiled. The uploader verified package identity, signing certificate, v2 signature and ABI coverage on both finished APKs.
- Driver APK: `parago_mobile/build/app/outputs/flutter-apk/app-release.apk`, SHA-256 `48f527d8c0650d251236f8faa2d762e26faf2ea720b9e4afa4d799a5bbb38664`.
- Passenger APK: `parago_passenger/build/app/outputs/flutter-apk/app-release.apk`, SHA-256 `ccad447912330b430817bf67a0b7ff7a3efcb028d89958e0fd3f88a348c60b0f`.

AWS/DNS and API activation have now passed the live checks described above. Actual APK upload, public APK download and physical-device installation/update checks remain outstanding until the first draft releases are uploaded through the signed-in local super admin. No mandatory policy has been activated.
