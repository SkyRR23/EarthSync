"""Package existing attributed reference records for the standalone chat server."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
catalog_path = root / "data/crop-knowledge/v2/catalog.json"
catalog = json.loads(catalog_path.read_text())
sources = {s["id"]: s for s in catalog["sources"]}
claims = [c for c in catalog["claims"] if c.get("parameter") != "identity"]
pins = {str(catalog_path.relative_to(root)): hashlib.sha256(catalog_path.read_bytes()).hexdigest()}
for name in ("plant_health.json", "additional_evidence.json"):
    path = root / "server/earthsync/research" / name
    data = json.loads(path.read_text())
    sources.update({s["id"]: s for s in data["sources"]})
    claims.extend(data["claims"])
    pins[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
output = {"schema_version": 1, "recommendation_eligible": False,
          "source_hashes": pins, "crops": catalog["crops"],
          "sources": sources, "claims": claims}
(root / "server/earthsync/chat_references.json").write_text(
    json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")
