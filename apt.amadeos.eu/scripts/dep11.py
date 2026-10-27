#!/usr/bin/env python3
"""Merges the catalog XML that `appstreamcli compose` wrote for each package into one catalog with package names.

Usage: dep11.py <origin> <out.xml> <package>=<catalog.xml.gz> ...

compose works on an unpacked directory and does not know which package it came from, but apt and Software need
the package name of every component (DEP-11 `Package:`), so it is added here as <pkgname>. The result is converted
to DEP-11 YAML with `appstreamcli convert` afterwards.
"""
import gzip
import sys
import xml.etree.ElementTree as ET


def main(args):
    if len(args) < 2:
        sys.exit(__doc__)
    origin, out = args[0], args[1]
    catalog = ET.Element("components", {"version": "1.0", "origin": origin})
    seen = set()
    for spec in args[2:]:
        package, path = spec.split("=", 1)
        with gzip.open(path) as f:
            root = ET.parse(f).getroot()
        for component in root.findall("component"):
            cid = component.findtext("id")
            if cid in seen:
                print(f"[dep11] {cid} of {package} is already in the catalog, skipped", file=sys.stderr)
                continue
            seen.add(cid)
            for old in component.findall("pkgname"):
                component.remove(old)
            pkgname = ET.Element("pkgname")
            pkgname.text = package
            # <pkgname> right after <id>, where compose writes it for packages it knows.
            component.insert(list(component).index(component.find("id")) + 1, pkgname)
            catalog.append(component)
    ET.indent(catalog)
    ET.ElementTree(catalog).write(out, encoding="utf-8", xml_declaration=True)
    print(f"[dep11] {len(seen)} components")


if __name__ == "__main__":
    main(sys.argv[1:])
