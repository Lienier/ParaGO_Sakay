const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
const rawPath = path.join(
  rootDir,
  '.secure-backups',
  '.digitalocean-app-spec.raw.json',
);
const redactedPath = path.join(
  rootDir,
  'docs',
  'realtime-capacity',
  'digitalocean-app-spec.redacted.json',
);

function redactEnvironment(environment, location) {
  if (!Array.isArray(environment)) {
    throw new Error(`${location} environment is not an array.`);
  }

  return environment.map((entry, index) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new Error(`${location} environment entry ${index} is malformed.`);
    }
    if (typeof entry.key !== 'string' || !entry.key.trim()) {
      throw new Error(`${location} environment entry ${index} has no key.`);
    }

    return {
      ...entry,
      value: '<redacted>',
    };
  });
}

function redactComponent(component, location) {
  if (!component || typeof component !== 'object' || Array.isArray(component)) {
    throw new Error(`${location} component is malformed.`);
  }

  const redacted = { ...component };
  if ('envs' in redacted) {
    redacted.envs = redactEnvironment(redacted.envs, location);
  }
  return redacted;
}

function redactDestinations(destinations) {
  if (!destinations || typeof destinations !== 'object') {
    return destinations;
  }

  const redacted = { ...destinations };
  if (Array.isArray(redacted.emails)) {
    redacted.emails = redacted.emails.map(() => '<redacted>');
  }
  if (Array.isArray(redacted.slack_webhooks)) {
    redacted.slack_webhooks = redacted.slack_webhooks.map((webhook) => ({
      ...webhook,
      url: '<redacted>',
    }));
  }
  return redacted;
}

function redactSpec(spec) {
  if (!spec || typeof spec !== 'object' || Array.isArray(spec)) {
    throw new Error('App spec root is malformed.');
  }

  const redacted = { ...spec };
  if ('envs' in redacted) {
    redacted.envs = redactEnvironment(redacted.envs, 'app');
  }

  for (const group of [
    'services',
    'workers',
    'jobs',
    'static_sites',
    'functions',
  ]) {
    if (group in redacted) {
      if (!Array.isArray(redacted[group])) {
        throw new Error(`${group} is not an array.`);
      }
      redacted[group] = redacted[group].map((component, index) =>
        redactComponent(component, `${group}[${index}]`),
      );
    }
  }

  if (Array.isArray(redacted.alerts)) {
    redacted.alerts = redacted.alerts.map((alert) => ({
      ...alert,
      destinations: redactDestinations(alert.destinations),
    }));
  }

  return redacted;
}

if (!fs.existsSync(rawPath)) {
  throw new Error('Ignored raw DigitalOcean app spec is missing.');
}

const raw = JSON.parse(fs.readFileSync(rawPath, 'utf8').replace(/^\uFEFF/, ''));
const redacted = redactSpec(raw);
fs.writeFileSync(redactedPath, `${JSON.stringify(redacted, null, 2)}\n`, {
  encoding: 'utf8',
  flag: 'wx',
});

console.log('DigitalOcean app spec redacted without displaying environment values.');
