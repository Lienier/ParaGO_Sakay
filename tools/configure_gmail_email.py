"""Run interactively on this PC. Never pass the App Password as an argument."""
from pathlib import Path
import getpass
import re
import subprocess

root = Path(__file__).resolve().parent.parent
target = root / '.env.gmail'
if subprocess.run(['git', 'check-ignore', '-q', str(target)], cwd=root).returncode != 0:
    raise SystemExit('Refusing to save: secret file is not ignored by Git.')
if target.exists() and input('Replace existing local Gmail configuration? [y/N] ').lower() != 'y':
    raise SystemExit('Unchanged.')
password = re.sub(r'\s+', '', getpass.getpass('Google App Password (hidden): '))
if not re.fullmatch(r'[A-Za-z]{16}', password):
    raise SystemExit('Expected a 16-letter Google App Password. Nothing saved.')
target.write_text('AUTH_EMAIL_PROVIDER=gmail\nAUTH_EMAIL_ENABLED=true\nSMTP_USER=sakaygaray.notifications@gmail.com\nSMTP_APP_PASSWORD=' + password + '\n', encoding='utf-8')
print('Saved to ignored .env.gmail. Treat this file as a secret; do not share or commit it. No email sent.')
