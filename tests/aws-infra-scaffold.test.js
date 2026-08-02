const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('AWS staging Terraform scaffold preserves deployment guardrails', () => {
  const backend = read('infra/aws/envs/staging/backend.hcl.example');
  const variables = read('infra/aws/envs/staging/variables.tf');
  const main = read('infra/aws/envs/staging/main.tf');
  const outputs = read('infra/aws/envs/staging/outputs.tf');
  const userData = read('infra/aws/envs/staging/user-data.sh');

  assert.match(backend, /use_lockfile = true/);
  assert.match(backend, /ap-southeast-1/);
  assert.match(variables, /default\s+= "ap-southeast-1"/);
  assert.match(main, /associate_public_ip_address\s+= false/);
  assert.doesNotMatch(main, /from_port\s+= 22/);
  assert.match(main, /AmazonSSMManagedInstanceCore/);
  assert.match(main, /aws_cloudfront_vpc_origin/);
  assert.match(main, /com\.amazonaws\.global\.cloudfront\.origin-facing/);
  assert.match(main, /prefix_list_ids\s+= \[data\.aws_ec2_managed_prefix_list\.cloudfront_origin_facing\.id\]/);
  assert.match(main, /viewer_protocol_policy\s+= "redirect-to-https"/);
  assert.match(main, /engine\s+= "valkey"/);
  assert.match(main, /transit_encryption_enabled = true/);
  assert.match(outputs, /parago:staging:aws:v1/);
  assert.match(userData, /proxy_set_header Upgrade \$http_upgrade/);
  assert.match(userData, /parago-aws-staging-v1/);
});

test('AWS bootstrap state bucket is encrypted, versioned, and public-blocked', () => {
  const bootstrap = read('infra/aws/bootstrap/main.tf');

  assert.match(bootstrap, /aws_s3_bucket_versioning/);
  assert.match(bootstrap, /aws_s3_bucket_public_access_block/);
  assert.match(bootstrap, /aws_s3_bucket_server_side_encryption_configuration/);
  assert.match(bootstrap, /aws_kms_key/);
  assert.match(bootstrap, /DenyInsecureTransport/);
  assert.match(bootstrap, /token\.actions\.githubusercontent\.com/);
  assert.match(bootstrap, /repo:\$\{var\.github_repository\}:ref:refs\/heads\/main/);
  assert.match(bootstrap, /parago-github-staging-deploy/);
});

test('AWS staging GitHub Actions deploy remains scoped to main and SSM', () => {
  const workflow = read('.github/workflows/aws-staging-deploy.yml');
  const deployScript = read('scripts/deploy-aws-staging.sh');

  assert.match(workflow, /branches:\s*\n\s+- main/);
  assert.match(workflow, /id-token: write/);
  assert.match(workflow, /aws-actions\/configure-aws-credentials@v4/);
  assert.match(workflow, /bash scripts\/deploy-aws-staging\.sh/);
  assert.match(deployScript, /aws ssm send-command/);
  assert.match(deployScript, /aws s3 presign/);
  assert.match(deployScript, /No AWS staging EC2 instance found\./);
  assert.match(deployScript, /aws ec2 start-instances/);
  assert.match(deployScript, /terraform apply -var ami_id=ami-0ed6a65b84536f6ce/);
  assert.match(deployScript, /systemctl restart parago-api parago-worker nginx/);
});
