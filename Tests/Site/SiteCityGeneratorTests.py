import contextlib
import importlib.util
import io
import json
import pathlib
import shutil
import tempfile
import sys
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("city_generator", ROOT / "scripts/generate_site_city_catalog.py")
generator = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(generator)


class CountryInputTests(unittest.TestCase):
    def test_validates_explicit_server_snapshot(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "response.json"
            for invalid in [
                {"code": 500, "data": [{"code": "FR", "name": "France"}]},
                {"code": 200, "data": []},
                {"code": 200, "data": [{"code": "fr", "name": "France"}]},
                {"code": 200, "data": [{"code": "FR", "name": "France"}] * 2},
                {"code": 200, "data": [{"code": "FR", "name": " "}]},
                {"code": 200, "data": [{"code": "FR", "name": "France", "names_json": "{}"}]},
            ]:
                path.write_text(json.dumps(invalid))
                with self.assertRaises(ValueError):
                    generator.read_country_codes(path)
            path.write_text(json.dumps({"code": 200, "data": [{"code": "FR", "name": "France"}]}))
            self.assertEqual(generator.read_country_codes(path), {"FR"})

    def test_generation_uses_only_supplied_countries(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            source, output = root / "source", root / "output"
            source.mkdir()
            (root / "SunSmart").mkdir()
            (root / "scripts").mkdir()
            (root / "SunSmart/all_utc_timezones.json").write_text('[{"ianaId":"Europe/Paris"}]')
            (root / "scripts/site_city_name_overrides.json").write_text("{}")
            shutil.copy(ROOT / "scripts/simplify_city_names.swift", root / "scripts")
            countries = root / "response.json"
            countries.write_text(json.dumps({"code": 200, "data": [{"code": "FR", "name": "France"}]}))
            rows = []
            for identifier, code in [(1, "FR"), (2, "US")]:
                row = [""] * 19
                for index, value in {0: str(identifier), 1: "City", 2: "City", 4: "48", 5: "2", 7: "PPL", 8: code, 17: "Europe/Paris"}.items():
                    row[index] = value
                rows.append("\t".join(row))
            with zipfile.ZipFile(source / "cities500.zip", "w") as archive:
                archive.writestr("cities500.txt", "\n".join(rows) + "\n")
            with zipfile.ZipFile(source / "alternateNamesV2.zip", "w") as archive:
                archive.writestr("alternateNamesV2.txt", "")
            for name in ["admin1CodesASCII.txt", "admin2Codes.txt", "tzdata2026e.tar.gz"]:
                (source / name).write_bytes(b"")
            previous = generator.ROOT
            try:
                generator.ROOT = root
                with contextlib.redirect_stdout(io.StringIO()):
                    generator.build(source, output, "2026-10-23", countries)
            finally:
                generator.ROOT = previous
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual(set(manifest["countries"]), {"FR"})
            self.assertEqual(manifest["totalCities"], 1)
            self.assertEqual(manifest["countriesResponseSHA256"], generator.digest(countries))
            self.assertFalse((output / "countries/US.json").exists())
            self.assertEqual(json.loads((output / "countries/FR.json").read_text())["cities"][0]["id"], 1)


if __name__ == "__main__":
    unittest.main()
