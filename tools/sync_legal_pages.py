"""Keep the independent Flutter clients' bundled legal pages identical."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'tools/legal/legal_pages.dart').read_bytes()
for app in ('parago_passenger', 'parago_mobile', 'parago_admin_web'):
    target = root / app / 'lib/widgets/legal_pages.dart'
    content = source.decode('utf-8')
    if app == 'parago_admin_web':
        content = content.replace("'SakayGaray',\n                      style: Theme.of(context).textTheme.headlineSmall,", "privacy ? 'Privacy Policy' : 'Terms & Conditions',\n                      style: Theme.of(context).textTheme.headlineMedium,")
        content = content.replace('const SizedBox(height: 24)', 'const SizedBox(height: 32)')
        content = content.replace('copyWith(height: 1.5)', 'copyWith(height: 1.7)')
    target.write_text(content, encoding='utf-8')
    print(target.relative_to(root))
