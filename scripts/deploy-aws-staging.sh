#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
AWS_INSTANCE_TAG_NAME="${AWS_INSTANCE_TAG_NAME:-parago-staging-aws-api}"
AWS_RELEASE_BUCKET="${AWS_RELEASE_BUCKET:-}"
SECRET_PATH_PREFIX="${SECRET_PATH_PREFIX:-/parago/staging/aws/v1}"
RELEASE_PREFIX="${RELEASE_PREFIX:-parago/staging/releases}"
COMMIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD)}"
SHORT_SHA="${COMMIT_SHA:0:7}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="parago-aws-staging-${SHORT_SHA}.zip"

if [[ -z "${AWS_RELEASE_BUCKET}" ]]; then
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  AWS_RELEASE_BUCKET="parago-terraform-state-${ACCOUNT_ID}-${AWS_REGION}"
fi

INSTANCE_STATE_INFO="$(
  aws ec2 describe-instances \
    --region "${AWS_REGION}" \
    --filters \
      "Name=tag:Name,Values=${AWS_INSTANCE_TAG_NAME}" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[0].[InstanceId,State.Name] | [0]" \
    --output text
)"

INSTANCE_ID="$(awk '{print $1}' <<<"${INSTANCE_STATE_INFO}")"
INSTANCE_STATE="$(awk '{print $2}' <<<"${INSTANCE_STATE_INFO}")"

if [[ -z "${INSTANCE_ID}" || "${INSTANCE_ID}" == "None" ]]; then
  cat >&2 <<'EOF'
No AWS staging EC2 instance found.
Recreate staging with Terraform first:
  cd infra/aws/envs/staging
  terraform apply -var ami_id=ami-0ed6a65b84536f6ce
EOF
  exit 1
fi

case "${INSTANCE_STATE}" in
  running)
    ;;
  pending)
    echo "AWS staging EC2 instance ${INSTANCE_ID} is pending; waiting for it to become running." >&2
    aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}"
    ;;
  stopped)
    echo "AWS staging EC2 instance ${INSTANCE_ID} is stopped; starting it before deploy." >&2
    if ! aws ec2 start-instances --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}" >/dev/null 2>&1; then
      cat >&2 <<'EOF'
AWS staging can be found, but this deploy role cannot start it.
Re-apply the AWS bootstrap Terraform so the GitHub deploy role picks up ec2:StartInstances.
EOF
      exit 1
    fi
    aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${INSTANCE_ID}"
    ;;
  stopping)
    echo "AWS staging EC2 instance ${INSTANCE_ID} is stopping; wait for it to finish before deploying." >&2
    exit 1
    ;;
  *)
    echo "AWS staging EC2 instance ${INSTANCE_ID} is in unexpected state '${INSTANCE_STATE}'." >&2
    exit 1
    ;;
esac

mkdir -p artifacts/aws
git archive --format=zip --output "artifacts/aws/${ARCHIVE}" "${COMMIT_SHA}"

S3_KEY="${RELEASE_PREFIX}/${SHORT_SHA}/${ARCHIVE}"
aws s3 cp "artifacts/aws/${ARCHIVE}" "s3://${AWS_RELEASE_BUCKET}/${S3_KEY}" \
  --region "${AWS_REGION}" \
  --no-progress

RELEASE_URL="$(aws s3 presign "s3://${AWS_RELEASE_BUCKET}/${S3_KEY}" --region "${AWS_REGION}" --expires-in 3600)"

read -r -d '' REMOTE_SCRIPT <<REMOTE || true
set -euo pipefail
export AWS_REGION='${AWS_REGION}'
export SECRET_PATH_PREFIX='${SECRET_PATH_PREFIX}'
export RELEASE_URL='${RELEASE_URL}'
export RELEASE_SHA='${COMMIT_SHA}'
export RELEASE_SHORT_SHA='${SHORT_SHA}'
export RELEASE_STAMP='${STAMP}'

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl unzip jq python3

if ! command -v node >/dev/null 2>&1 || ! node -e "process.exit(Number(process.versions.node.split('.')[0]) >= 22 ? 0 : 1)"; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
fi

if ! command -v aws >/dev/null 2>&1; then
  tmpdir="\$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "\${tmpdir}/awscliv2.zip"
  unzip -q "\${tmpdir}/awscliv2.zip" -d "\${tmpdir}"
  "\${tmpdir}/aws/install" --update
  rm -rf "\${tmpdir}"
fi

if ! id parago >/dev/null 2>&1; then
  useradd --system --home /opt/parago --shell /usr/sbin/nologin parago
fi

mkdir -p /etc/parago /opt/parago/releases /opt/parago/shared /var/log/parago
chown -R parago:parago /opt/parago /var/log/parago
chmod 0750 /etc/parago /opt/parago /opt/parago/releases /opt/parago/shared

release_dir="/opt/parago/releases/\${RELEASE_STAMP}-\${RELEASE_SHORT_SHA}"
mkdir -p "\${release_dir}"
curl -fsSL "\${RELEASE_URL}" -o /tmp/parago-release.zip
unzip -q /tmp/parago-release.zip -d "\${release_dir}"
chown -R parago:parago "\${release_dir}"

cd "\${release_dir}"
npm install --omit=dev --no-audit --no-fund

aws ssm get-parameters-by-path \
  --region "\${AWS_REGION}" \
  --path "\${SECRET_PATH_PREFIX}" \
  --with-decryption \
  --recursive \
  --output json >/tmp/parago-params.json

python3 - <<'PY'
import json
import shlex
from pathlib import Path
from urllib.parse import quote

params = json.loads(Path('/tmp/parago-params.json').read_text())['Parameters']
values = {item['Name'].rstrip('/').split('/')[-1]: item.get('Value', '') for item in params}
skip = {'redis_auth_token', 'RUN_API_JOBS', 'RUN_WORKER_JOBS'}
lines = []
for key in sorted(values):
    if key in skip:
        continue
    lines.append(f'{key}={shlex.quote(values[key])}')

redis_host = values.get('REDIS_HOST', '').strip()
redis_token = values.get('redis_auth_token', '')
if redis_host and redis_token:
    lines.append(f'REDIS_URL={shlex.quote("rediss://:" + quote(redis_token, safe="") + "@" + redis_host + ":6379")}')

Path('/etc/parago/parago.env').write_text('\n'.join(lines) + '\n')
PY

chmod 0600 /etc/parago/parago.env
ln -sfn "\${release_dir}" /opt/parago/current

install -m 0644 deploy/systemd/parago-api.service /etc/systemd/system/parago-api.service
install -m 0644 deploy/systemd/parago-worker.service /etc/systemd/system/parago-worker.service
systemctl daemon-reload
systemctl enable parago-api parago-worker
systemctl restart parago-api parago-worker nginx

sleep 5
systemctl is-active parago-api parago-worker nginx
curl -fsS http://127.0.0.1:5000/health
curl -fsS http://127.0.0.1:5000/ready
REMOTE

PARAMETERS_FILE="$(mktemp)"
export REMOTE_SCRIPT
python3 - <<'PY' >"${PARAMETERS_FILE}"
import json
import os
import shlex

command = "bash -lc " + shlex.quote(os.environ["REMOTE_SCRIPT"])
print(json.dumps({"commands": [command]}))
PY

AWS_PARAMETERS_FILE="${PARAMETERS_FILE}"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    AWS_PARAMETERS_FILE="$(cygpath -m "${PARAMETERS_FILE}")"
    ;;
esac

COMMAND_ID="$(
  aws ssm send-command \
    --region "${AWS_REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --document-name AWS-RunShellScript \
    --comment "Deploy ParaGO ${SHORT_SHA} from GitHub Actions" \
    --parameters "file://${AWS_PARAMETERS_FILE}" \
    --query "Command.CommandId" \
    --output text
)"
rm -f "${PARAMETERS_FILE}"

echo "SSM command: ${COMMAND_ID}"

for _ in {1..90}; do
  STATUS="$(
    aws ssm get-command-invocation \
      --region "${AWS_REGION}" \
      --command-id "${COMMAND_ID}" \
      --instance-id "${INSTANCE_ID}" \
      --query Status \
      --output text 2>/dev/null || true
  )"

  case "${STATUS}" in
    Success)
      aws ssm get-command-invocation \
        --region "${AWS_REGION}" \
        --command-id "${COMMAND_ID}" \
        --instance-id "${INSTANCE_ID}" \
        --query StandardOutputContent \
        --output text
      exit 0
      ;;
    Failed|Cancelled|TimedOut|Cancelling)
      aws ssm get-command-invocation \
        --region "${AWS_REGION}" \
        --command-id "${COMMAND_ID}" \
        --instance-id "${INSTANCE_ID}" \
        --query "{stdout:StandardOutputContent,stderr:StandardErrorContent}" \
        --output json
      exit 1
      ;;
  esac

  sleep 10
done

echo "Timed out waiting for SSM deploy command ${COMMAND_ID}" >&2
exit 1
