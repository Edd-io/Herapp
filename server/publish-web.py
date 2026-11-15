#!/usr/bin/env python3
"""Publish a built Herapp release through an existing Hermes dashboard's static server."""

import argparse
import os
from pathlib import Path
import re
import shutil
import tempfile


def publish(source: Path, dashboard: Path) -> None:
    source, dashboard = source.resolve(), dashboard.resolve()
    release_id = source.name
    if not re.fullmatch(r"[A-Za-z0-9_-]+", release_id):
        raise ValueError("Release directory must have a simple version name")
    for name in ("index.html", "flutter_bootstrap.js", "main.dart.js", "manifest.json"):
        if not (source / name).is_file():
            raise ValueError(f"Missing build artifact: {name}")
    if '<base href="/herapp/">' not in (source / "index.html").read_text():
        raise ValueError("Build with --base-href=/herapp/")
    if not (dashboard / "index.html").is_file():
        raise ValueError("Dashboard directory must already contain Hermes index.html")

    releases = dashboard / ".herapp-releases"
    current = dashboard / "herapp"
    if current.exists() or current.is_symlink():
        if not current.is_symlink() or not current.resolve().is_relative_to(releases.resolve()):
            raise ValueError("Refusing to replace an unrelated herapp path")
    releases.mkdir(exist_ok=True)
    destination = releases / release_id
    if destination.exists():
        raise ValueError(f"Release already published: {release_id}")
    # Keep the target within the dashboard tree: Hermes rejects symlinks outside its static root.
    staging = Path(tempfile.mkdtemp(prefix=".staging-", dir=releases))
    try:
        shutil.copytree(source, staging, dirs_exist_ok=True)
        os.replace(staging, destination)
    except BaseException:
        shutil.rmtree(staging)
        raise
    link = releases / f".next-{release_id}"
    link.symlink_to(Path(".herapp-releases") / release_id)
    previous = os.readlink(current) if current.is_symlink() else "none"
    os.replace(link, current)
    print(f"Published: {release_id}")
    print(f"Previous target: {previous}")
    print("Open /herapp/index.html on the Hermes dashboard origin")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release", type=Path)
    parser.add_argument("dashboard_dist", type=Path)
    args = parser.parse_args()
    publish(args.release, args.dashboard_dist)
