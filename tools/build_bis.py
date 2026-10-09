#!/usr/bin/env python3
"""Retired 2026-10-08. The BiS page is now built by tools/build_bis.mjs.

This script used to compile bis/bis.json from ForeverChanges' hand-picked BiS
lists (and tools/build_bis_items.py read their item pages into
bis/bis-items.json). ForeverChanges' terms, updated 2 October 2026, ask that
their compiled data not be copied wholesale to republish, and their BiS
rankings are their own picks. So /bis/ now ranks every slot itself, with The
Forge's weights over our own item database, and links their lists instead of
copying them. Nothing here fetches their pages any more.

Rebuild the page's data from the repo root with:  node tools/build_bis.mjs
"""
import sys

sys.exit(__doc__.strip())
