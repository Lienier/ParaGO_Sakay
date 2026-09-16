async function load(app) {
  const panel = document.getElementById(app);
  panel.replaceChildren(Object.assign(document.createElement('h2'), { textContent: app === 'driver' ? 'Driver' : 'Passenger' }));
  const status = Object.assign(document.createElement('p'), { textContent: 'Checking the latest version…' });
  status.setAttribute('role', 'status'); panel.append(status);
  try {
    const response = await fetch(`https://api.sakaygaray.com/api/v1/mobile-updates/${app}`, { cache: 'no-store', signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error();
    const release = (await response.json()).data?.latest;
    if (!release) { status.textContent = 'No release is published yet. Please check again later.'; return; }
    const url = new URL(release.url);
    if (url.origin !== location.origin || !url.pathname.startsWith('/releases/')) throw new Error();
    status.textContent = `Version ${release.version} · Build ${release.build} · ${(release.size / 1048576).toFixed(1)} MB`;
    panel.append(Object.assign(document.createElement('a'), { textContent: 'Download for Android', href: url.href }));
    panel.append(Object.assign(document.createElement('p'), { className: 'notes', textContent: release.notes || '' }));
    panel.append(Object.assign(document.createElement('small'), { textContent: `Released ${new Date(release.publishedAt).toLocaleDateString()} · SHA-256: ${release.sha256}` }));
  } catch (_) { status.textContent = 'Downloads are temporarily unavailable. Please check again.'; }
}
async function refresh() { const button = document.getElementById('retry'); button.disabled = true; await Promise.all(['passenger', 'driver'].map(load)); button.disabled = false; }
document.getElementById('retry').addEventListener('click', refresh);
refresh();
