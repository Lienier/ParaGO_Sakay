const path = require('path');

const {
  loadStagingBoundary,
  rootDir,
  writeSecureJson,
} = require('./phase10-safety');

const appName = 'parago-capacity-staging';
const branch = 'realtime-capacity-remediation';
const repository = 'Lienier/ParaGO_Sakay';
const valkeyClusterName = 'parago-realtime-valkey';

const environmentEntry = (key, value, type = 'GENERAL') => ({
  key,
  value,
  scope: 'RUN_TIME',
  type,
});

const source = () => ({
  github: {
    repo: repository,
    branch,
    deploy_on_push: false,
  },
  source_dir: '/',
  environment_slug: 'node-js',
  build_command: 'npm ci',
});

const buildSpec = ({ staging }) => ({
  name: appName,
  region: 'sgp',
  egress: { type: 'DEDICATED_IP' },
  services: [
    {
      name: 'phase10-api',
      ...source(),
      run_command: 'npm start',
      instance_size_slug: 'apps-s-1vcpu-1gb-fixed',
      instance_count: 1,
      http_port: 8080,
      termination: { drain_seconds: 30, grace_period_seconds: 60 },
      health_check: {
        http_path: '/health',
        initial_delay_seconds: 20,
        period_seconds: 10,
        timeout_seconds: 5,
        success_threshold: 1,
        failure_threshold: 3,
      },
      alerts: [
        {
          rule: 'CPU_UTILIZATION',
          operator: 'GREATER_THAN',
          value: 75,
          window: 'FIVE_MINUTES',
        },
        {
          rule: 'MEM_UTILIZATION',
          operator: 'GREATER_THAN',
          value: 80,
          window: 'FIVE_MINUTES',
        },
      ],
      envs: [
        environmentEntry('RUN_API_JOBS', 'false'),
        environmentEntry('RUN_WORKER_JOBS', 'false'),
      ],
    },
  ],
  workers: [
    {
      name: 'phase10-worker',
      ...source(),
      run_command: 'npm run start:worker',
      instance_size_slug: 'apps-s-1vcpu-0.5gb',
      instance_count: 1,
      termination: { grace_period_seconds: 60 },
      alerts: [
        {
          rule: 'CPU_UTILIZATION',
          operator: 'GREATER_THAN',
          value: 75,
          window: 'FIVE_MINUTES',
        },
        {
          rule: 'MEM_UTILIZATION',
          operator: 'GREATER_THAN',
          value: 80,
          window: 'FIVE_MINUTES',
        },
      ],
      envs: [
        environmentEntry('RUN_API_JOBS', 'false'),
        environmentEntry('RUN_WORKER_JOBS', 'true'),
      ],
    },
  ],
  databases: [
    {
      name: 'phase10-valkey',
      engine: 'VALKEY',
      version: '8',
      production: true,
      cluster_name: valkeyClusterName,
    },
  ],
  envs: [
    environmentEntry('NODE_ENV', 'production'),
    environmentEntry('DEPLOYMENT_ENV', 'staging'),
    environmentEntry('MONGO_URI', staging.STAGING_MONGO_URI, 'SECRET'),
    environmentEntry('JWT_SECRET', staging.STAGING_JWT_SECRET, 'SECRET'),
    environmentEntry(
      'JWT_REFRESH_SECRET',
      staging.STAGING_JWT_REFRESH_SECRET,
      'SECRET'
    ),
    environmentEntry('JWT_EXPIRES_IN', '12h'),
    environmentEntry('JWT_REFRESH_EXPIRES_IN', '1d'),
    environmentEntry(
      'REDIS_URL',
      '${phase10-valkey.DATABASE_URL}',
      'SECRET'
    ),
    environmentEntry('REDIS_NAMESPACE', 'parago:staging:phase10:v1'),
    environmentEntry('ASYNC_LOCATION_PROCESSING_ENABLED', 'true'),
    environmentEntry('CORS_ALLOWED_ORIGINS', 'https://phase10-staging.invalid'),
    environmentEntry('GOOGLE_ROUTES_API_KEY', '', 'SECRET'),
    environmentEntry('TOMTOM_API_KEY', '', 'SECRET'),
    environmentEntry('FIREBASE_PROJECT_ID', ''),
    environmentEntry('FIREBASE_CLIENT_EMAIL', ''),
    environmentEntry('FIREBASE_PRIVATE_KEY', '', 'SECRET'),
    environmentEntry('SMSAPIPH_API_KEY', '', 'SECRET'),
    environmentEntry('RATE_LIMIT_AUTH_MAX', '3000'),
    environmentEntry('RATE_LIMIT_DRIVER_LOCATION_MAX', '120'),
    environmentEntry('RATE_LIMIT_PASSENGER_LOCATION_MAX', '30'),
    environmentEntry('RATE_LIMIT_ETA_MAX', '12'),
    environmentEntry('RATE_LIMIT_SUPPORT_MAX', '60'),
    environmentEntry('RATE_LIMIT_ADMIN_MAX', '120'),
    environmentEntry('RATE_LIMIT_GENERAL_MAX', '300'),
    environmentEntry('WORKER_LOCATION_FLUSH_INTERVAL_MS', '5000'),
    environmentEntry('WORKER_AUTOMATION_POLL_INTERVAL_MS', '1000'),
    environmentEntry('WORKER_MAX_BATCH_SIZE', '500'),
  ],
  ingress: {
    rules: [
      {
        match: { path: { prefix: '/' } },
        component: { name: 'phase10-api' },
      },
    ],
  },
  alerts: [
    { rule: 'DEPLOYMENT_FAILED' },
  ],
});

const main = () => {
  const { staging } = loadStagingBoundary();
  if (
    !staging.STAGING_JWT_SECRET ||
    !staging.STAGING_JWT_REFRESH_SECRET ||
    staging.STAGING_JWT_SECRET.length < 32 ||
    staging.STAGING_JWT_REFRESH_SECRET.length < 32
  ) {
    throw new Error('Strong staging JWT secrets are required');
  }
  const output = path.join(
    rootDir,
    '.secure-backups',
    'phase10-digitalocean-app-spec.json'
  );
  writeSecureJson(output, buildSpec({ staging }));
  console.log(`Secret-bearing staging spec written locally at ${output}.`);
  console.log('The generated file is ignored by Git and must not be shared.');
};

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(`Phase 10 app spec generation failed: ${error.message}`);
    process.exitCode = 1;
  }
}

module.exports = {
  appName,
  branch,
  buildSpec,
  repository,
  valkeyClusterName,
};
