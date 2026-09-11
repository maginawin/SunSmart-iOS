#!/usr/bin/env python3
"""Prepare byte-identical JSON/gzip cases locally; never send a request."""
import argparse
import gzip
import hashlib
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("request_json", type=Path, help="Complete, resolved test upload request body")
    parser.add_argument("output_directory", type=Path, help="New local directory outside the repository")
    args = parser.parse_args()
    raw = args.request_json.read_bytes()
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        parser.error("Expected the complete JSON request object")
    if re.search(rb"\{\{[^{}]+\}\}", raw):
        parser.error("Resolve Apifox variables before creating binary files")
    if isinstance(payload.get("site"), dict) and isinstance(payload.get("user"), dict):
        endpoint = "/sitespace/sync/siteprops"
    elif all(key in payload for key in ("siteId", "spaceId", "spaces", "userId")) and isinstance(payload["spaces"], list):
        endpoint = "/sitespace/sync/spaceprops"
    else:
        parser.error("Expected a siteUpload or spaceUpload request envelope, not a get response or bare Space")
    compressed = gzip.compress(raw, compresslevel=1, mtime=0)
    assert compressed[:2] == b"\x1f\x8b" and gzip.decompress(compressed) == raw
    fixtures = {
        "identity.json": raw,
        "request.json.gz": compressed,
        "truncated.json.gz": compressed[:-8],
        "invalid-json.json.gz": gzip.compress(b'{"incomplete":', compresslevel=1, mtime=0),
    }
    # Refuse an existing destination so fixture evidence is never overwritten.
    args.output_directory.mkdir(parents=True, exist_ok=False, mode=0o700)
    manifest = {"endpoint": endpoint, "gzipRoundTripEqual": True, "files": {}}
    for name, data in fixtures.items():
        path = args.output_directory / name
        with path.open("xb") as output:
            path.chmod(0o600)
            output.write(data)
        manifest["files"][name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    (args.output_directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(args.output_directory)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
