"""Keep the independent Flutter clients' bundled legal pages identical."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'tools/legal/legal_pages.dart').read_bytes()
for app in ('parago_passenger', 'parago_mobile', 'parago_admin_web'):
    target = root / app / 'lib/widgets/legal_pages.dart'
    target.write_bytes(source)
    print(target.relative_to(root))
