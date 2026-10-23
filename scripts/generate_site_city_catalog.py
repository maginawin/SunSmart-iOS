#!/usr/bin/env python3
"""Build the bundled offline catalog from an explicitly supplied GeoNames snapshot.

No downloads are performed. Keep the large source files outside the repository.
Usage: python3 scripts/generate_site_city_catalog.py --source-dir /path/to/snapshot
"""
import argparse
import collections
import hashlib
import io
import json
import pathlib
import subprocess
import tempfile
import unicodedata
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FEATURES = {"PPL", "PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLA5", "PPLG"}
SOURCE_FILES = ("cities500.zip", "alternateNamesV2.zip", "admin1CodesASCII.txt", "admin2Codes.txt", "tzdata2026e.tar.gz")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def fold(text):
    return "".join(c for c in unicodedata.normalize("NFKD", text.casefold()) if not unicodedata.combining(c))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


def build(source, output, snapshot_date):
    hashes = {name: digest(source / name) for name in SOURCE_FILES}
    countries = json.loads((ROOT / "SunSmart/country_regions.json").read_text())["countries"]
    codes = {c["code"] for c in countries}
    timezones = {t["ianaId"] for t in json.loads((ROOT / "SunSmart/all_utc_timezones.json").read_text())}
    cities = {}
    by_country = {code: [] for code in sorted(codes)}
    excluded = collections.Counter()
    with zipfile.ZipFile(source / "cities500.zip") as z:
        for line in io.TextIOWrapper(z.open("cities500.txt"), encoding="utf-8"):
            row = line.rstrip("\n").split("\t")
            if row[7] not in FEATURES or row[8] not in codes:
                excluded[row[7] if row[8] in codes else "country:" + row[8]] += 1
                continue
            city_id = int(row[0])
            if city_id in cities:
                raise ValueError(f"Duplicate city ID {city_id}")
            latitude, longitude = float(row[4]), float(row[5])
            if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
                raise ValueError(f"Invalid coordinates {city_id}")
            if row[17] not in timezones:
                raise ValueError(f"City {city_id} needs missing App timezone {row[17]}")
            a1 = row[8] + "." + row[10] if row[10] else ""
            a2 = a1 + "." + row[11] if row[11] and a1 else ""
            item = {"id": city_id, "names": {"en": row[2] or row[1]}, "aliases": [],
                    "admin1": a1, "admin2": a2, "timezone": row[17],
                    "latitude": latitude, "longitude": longitude}
            cities[city_id] = item
            by_country[row[8]].append(item)
    admin = {}
    for filename in ["admin1CodesASCII.txt", "admin2Codes.txt"]:
        for line in (source / filename).read_text().splitlines():
            row = line.split("\t")
            if row[0].split(".")[0] in codes:
                admin[row[0]] = {"id": int(row[3]), "names": {"en": row[2] or row[1]}}
    needed_admin = {c[key] for c in cities.values() for key in ["admin1", "admin2"] if c[key] in admin}
    admin = {key: value for key, value in admin.items() if key in needed_admin}
    needed = set(cities) | {a["id"] for a in admin.values()}
    names = collections.defaultdict(lambda: collections.defaultdict(list))
    with zipfile.ZipFile(source / "alternateNamesV2.zip") as z:
        with io.TextIOWrapper(z.open("alternateNamesV2.txt"), encoding="utf-8") as stream:
            for line in stream:
                row = line.rstrip("\n").split("\t")
                if len(row) < 8 or row[2] not in {"en", "zh", "zh-CN", "zh-Hans"}:
                    continue
                identifier = int(row[1])
                if identifier not in needed or row[7] == "1" or row[6] == "1":
                    continue
                # Exclude ended names and future names. The snapshot is pinned, never today's clock.
                if len(row) > 9 and row[9] and row[9][:4].isdigit() and row[9][:4] <= snapshot_date[:4]:
                    continue
                if len(row) > 8 and row[8] and row[8][:4].isdigit() and row[8][:4] > snapshot_date[:4]:
                    continue
                text = row[3].strip()
                if text:
                    rank = (row[4] != "1", row[5] != "1", int(row[0]))
                    names[identifier][row[2]].append((rank, text))
    chinese = sorted({text for values in names.values() for lang, variants in values.items()
                      if lang.startswith("zh") for _, text in variants})
    # Use Apple's ICU conversion at generation time; no runtime or Python package dependency.
    with tempfile.TemporaryDirectory(prefix="city-names-") as d:
        path = pathlib.Path(d) / "names.json"
        write_json(path, chinese)
        result = subprocess.run(["xcrun", "swift", "-module-cache-path", str(path.parent / "module-cache"),
                                 str(ROOT / "scripts/simplify_city_names.swift"), str(path)],
                                capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)
        simplified = dict(zip(chinese, json.loads(result.stdout)))

    def localized(identifier, fallback):
        variants = names.get(identifier, {})
        english = sorted(variants.get("en", []))
        chosen = {"en": english[0][1] if english else fallback}
        zh = []
        for lang in ["zh-Hans", "zh-CN", "zh"]:
            zh.extend(sorted(variants.get(lang, [])))
        if zh:
            chosen["zh-Hans"] = simplified[zh[0][1]]
        return chosen

    for a in admin.values():
        a["names"] = localized(a["id"], a["names"]["en"])
    overrides_path = ROOT / "scripts/site_city_name_overrides.json"
    overrides = json.loads(overrides_path.read_text())
    if not set(map(int, overrides)).issubset(cities):
        raise ValueError("An explicitly reviewed name override no longer exists in this snapshot")
    for identifier, c in cities.items():
        fallback = c["names"]["en"]
        c["names"] = localized(identifier, fallback)
        aliases = {fallback} | set(c["names"].values())
        c["names"].update(overrides.get(str(identifier), {}).get("names", {}))
        for lang, variants in names.get(identifier, {}).items():
            for _, text in variants:
                aliases.add(text)
                if lang.startswith("zh"):
                    aliases.add(simplified[text])
        c["aliases"] = sorted(aliases - set(c["names"].values()), key=lambda x: (fold(x), x))
        if not c["names"]["en"].strip():
            raise ValueError(f"Empty English fallback {identifier}")
    output.mkdir(parents=True, exist_ok=True)
    (output / "countries").mkdir(exist_ok=True)
    stats = {}
    unresolved = collections.Counter()
    for code, rows in by_country.items():
        rows.sort(key=lambda c: (fold(c["names"]["en"]), c["admin1"], c["admin2"], c["id"]))
        used_admin = {}
        for c in rows:
            for key in ["admin1", "admin2"]:
                if c[key] in admin:
                    used_admin[c[key]] = admin[c[key]]["names"]
                elif c[key]:
                    unresolved[c[key]] += 1
                    c[key] = ""  # Missing admin metadata uses coordinate disambiguation, never an invented name.
        path = output / "countries" / (code + ".json")
        write_json(path, {"schemaVersion": 1, "countryCode": code,
                          "administrativeAreas": dict(sorted(used_admin.items())), "cities": rows})
        stats[code] = {"count": len(rows), "chineseCount": sum("zh-Hans" in c["names"] for c in rows),
                       "bytes": path.stat().st_size, "sha256": digest(path)}
    manifest = {"schemaVersion": 1, "snapshotDate": snapshot_date, "source": "https://download.geonames.org/export/dump/",
                "license": "CC BY 4.0", "timeZoneSource": "IANA tzdata 2026e",
                "nameOverridesSHA256": digest(overrides_path),
                "referenceSHA256": {name: digest(ROOT / "SunSmart" / name) for name in ["country_regions.json", "all_utc_timezones.json"]},
                "sourceSHA256": hashes, "featureCodes": sorted(FEATURES), "nameConversion": "Apple ICU Traditional-Simplified",
                "excluded": dict(sorted(excluded.items())), "unresolvedAdministrativeReferences": dict(sorted(unresolved.items())),
                "countries": stats, "totalCities": len(cities), "chineseNames": sum(v["chineseCount"] for v in stats.values())}
    write_json(output / "manifest.json", manifest)
    (output / "LICENSE.txt").write_text(
        "City catalog derived from GeoNames (https://www.geonames.org/).\n"
        "Source: https://download.geonames.org/export/dump/\n"
        "Licensed under Creative Commons Attribution 4.0 International.\n"
        "License: https://creativecommons.org/licenses/by/4.0/\n"
        "Changes: selected populated places, country partitions, selected language aliases,\n"
        "simplified Chinese conversion, administrative references and compact JSON encoding.\n"
        "Snapshot, filters and source SHA-256 digests are recorded in manifest.json.\n"
        "Names and coordinates are supplied as-is and do not guarantee coverage or accuracy.\n"
        "Time zone identifiers are cross-checked with IANA tzdata 2026e (public domain).\n", encoding="utf-8")
    print(json.dumps({"cities": len(cities), "chineseNames": manifest["chineseNames"],
                      "countries": len(stats), "emptyCountries": [k for k, v in stats.items() if not v["count"]],
                      "countryJSONBytes": sum(v["bytes"] for v in stats.values()),
                      "unresolvedAdminCodes": len(unresolved)}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "SunSmart/CityCatalog")
    parser.add_argument("--snapshot-date", default="2026-10-23")
    args = parser.parse_args()
    build(args.source_dir, args.output, args.snapshot_date)
