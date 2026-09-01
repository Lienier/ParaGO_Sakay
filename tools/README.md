# ParaGO AWS Staging Controller

This Windows Tkinter utility controls the disposable ParaGO AWS staging stack
through the existing AWS CLI profile and Terraform configuration. It stores no
AWS credentials.

## Run

From the repository root:

```powershell
python tools/aws_staging_controller.py
```

The configured AWS profile must already work:

```powershell
aws sts get-caller-identity --profile default
```

## Buttons

- **Start AWS** verifies the identity, refuses to proceed if Terraform is busy,
  then creates the base stack without attaching the custom API alias.
- **Prepare Domain** attaches the issued ACM certificate without claiming the
  custom alias, then checks which CloudFront resource currently owns it.
- **Apply Config** attaches `api.sakaygaray.com` only after the certificate is
  prepared and any reported domain conflict has been resolved.
- **Destroy Staging** requires confirmation and removes the disposable AWS
  resources managed by `infra/aws/envs/staging`.
- **Refresh Status** checks EC2, CloudFront, and the API health endpoint.
- **View Logs** opens the local controller log.

The controller also performs an automatic status check when it opens and every
30 seconds while it remains open. The live summary shows the EC2 state,
CloudFront deployment/enabled state, API health response, and the last check
time. Automatic checks pause while Start or Destroy is running.

The **Start AWS** button is disabled when Terraform already manages staging
resources. **Prepare Domain**, **Apply Config**, and **Destroy Staging** are
enabled only when their prerequisite state is detected. If AWS or Terraform
status cannot be verified, infrastructure-changing buttons are disabled
instead of guessing.

When CloudFront reports a domain conflict, the live status shows `Alias:
conflict`, the conflicting resource information is written to the log, and
**Apply Config** remains disabled so the same failing update is not repeated.

MongoDB Atlas is outside the staging Terraform root and is not destroyed by the
Destroy button. Driver license images are stored in a private bootstrap S3
bucket and are also preserved. Valkey/cache contents and EC2-local files are
temporary.

Before the first start after installing the driver-document feature, apply the
bootstrap Terraform once:

```powershell
& "C:\terraform\terraform.exe" -chdir="infra/aws/bootstrap" init
& "C:\terraform\terraform.exe" -chdir="infra/aws/bootstrap" apply
```

The controller checks for the persistent bucket and blocks **Start AWS** with a
clear message when this one-time bootstrap step is still required.

Destroying staging is the lowest-cost state for this setup because it removes
the metered EC2, Valkey, CloudFront, NAT Gateway, and related staging resources.
It does not make the total project cost zero: the domain, Terraform state
bucket, and any separately billed MongoDB Atlas resources remain outside this
disposable stack.

Terraform apply and destroy use the backend's native lock with a zero-second
timeout. The controller reports lock failures and never force-unlocks state.

The Namecheap registrar is intentionally not automated. The controller reads
the current ACM validation record from AWS and displays a copyable CNAME name
and value. Add that record at Namecheap, wait for ACM to become issued, then
click **Prepare Domain**. Resolve any conflict reported in the log, then click
**Apply Config**. The saved validation hostname in the JSON file is used only
as a destroy fallback when ACM details are unavailable.
