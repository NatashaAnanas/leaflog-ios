#!/usr/bin/env python3
"""Собирает строки интерфейса из .stringsdata (результат сборки с SWIFT_EMIT_LOC_STRINGS=YES)
в Leaflog/Resources/Localizable.xcstrings. Исходный язык — русский, ключ = русский текст.
Использование: python3 Tools/extract_strings.py build/DD
"""
import json, sys, glob, os

root = sys.argv[1] if len(sys.argv) > 1 else "build/DD"
catalog_path = os.path.join(os.path.dirname(__file__), "..", "Leaflog", "Resources", "Localizable.xcstrings")
catalog = json.load(open(catalog_path))
strings = catalog.get("strings", {})
found = set()
for f in glob.glob(f"{root}/**/Leaflog.build/**/Objects-normal/arm64/*.stringsdata", recursive=True):
    try:
        data = json.load(open(f))
    except Exception:
        continue
    for entry in data.get("tables", {}).get("Localizable", []):
        key = entry["key"]
        found.add(key)
        if key not in strings:
            strings[key] = {
                "extractionState": "extracted_with_value",
                "localizations": {"ru": {"stringUnit": {"state": "translated", "value": key}}},
            }
catalog["strings"] = dict(sorted(strings.items()))
json.dump(catalog, open(catalog_path, "w"), ensure_ascii=False, indent=2)
print(f"{len(found)} строк извлечено, в каталоге {len(catalog['strings'])}")
