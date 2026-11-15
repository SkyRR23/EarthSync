"""Package a small attributed subset of the existing chat corpus for Android."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'server/earthsync/chat_references.json'
raw = source.read_bytes()
corpus = json.loads(raw)
scientific = {'Oryza sativa', 'Zea mays', 'Vigna radiata', 'Sesamum indicum', 'Arachis hypogaea'}
crops = [c for c in corpus['crops'] if c['scientific_name'] in scientific]
ids = {c['id'] for c in crops}
claims = [c for c in corpus['claims'] if c['id'].startswith('health.') or
          (c.get('crop_id') in ids and c.get('parameter') in
           {'ecological_temperature', 'ecological_soil_ph', 'soil_drainage'})]
source_ids = {c['source_id'] for c in claims}
out = {'schema_version': 'earthsync.offline-help.v1',
       'source_sha256': hashlib.sha256(raw).hexdigest(), 'crops': crops,
       'claims': claims, 'sources': {k: v for k, v in corpus['sources'].items() if k in source_ids}}
(root / 'app/assets/fixtures/offline_help.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')) + '\n')
