#!/usr/bin/env python3
# Simple rMLST species identification against the PubMLST kiosk endpoint
# Adds: CLI args, TSV output, supported-organism check, species label file
# No OAuth — uses the kiosk DB that does not require auth.
#
# Dependencies: requests (required), pyyaml (optional; only if --organism_file is used)
#
# Example:
#   ./rmlst_kiosk.py -f contigs.fasta \
#     -o results/rMLST.tsv \
#     -O supported_organisms.yaml \
#     -s results/species.txt \
#     --db pubmlst_rmlst_seqdef_kiosk

import sys
import os
import csv
import json
import base64
import argparse
from typing import Optional, List, Dict

import requests

try:
    import yaml  # only needed if --organism_file is used
except Exception:
    yaml = None


DEFAULT_DB = "pubmlst_rmlst_seqdef_kiosk"
BASE_URL = "https://rest.pubmlst.org"


def dbg(enabled: bool, msg: str) -> None:
    if enabled:
        print(f"[rMLST] {msg}", file=sys.stderr)


def load_supported(path: str, debug: bool = False) -> Optional[set]:
    """Load supported organisms from YAML. Accepts:
       - list of names
       - dict with top-level key 'amrfinder' containing a list
       - dict-of-lists (flattens values)
    """
    if not path:
        return None
    if yaml is None:
        raise RuntimeError("PyYAML is required to parse --organism_file (pip install pyyaml).")
    with open(path, "r") as fh:
        y = yaml.safe_load(fh) or {}
    if isinstance(y, dict) and isinstance(y.get("amrfinder"), list):
        sup = set(map(str, y["amrfinder"]))
    elif isinstance(y, list):
        sup = set(map(str, y))
    elif isinstance(y, dict):
        flat: List[str] = []
        for v in y.values():
            if isinstance(v, list):
                flat.extend(v)
        sup = set(map(str, flat))
    else:
        sup = set()
    dbg(debug, f"Loaded {len(sup)} supported labels")
    return sup


def abbreviate_taxon(taxon: str) -> str:
    parts = (taxon or "").strip().split()
    if len(parts) >= 2 and parts[0] and parts[1]:
        return f"{parts[0][0]}. {parts[1]}"
    return taxon or ""


def post_to_kiosk(db: str, fasta_text: str, timeout: int, debug: bool = False) -> requests.Response:
    """POST base64-encoded FASTA to /db/{db}/schemes/1/sequence (kiosk DB)."""
    url = f"{BASE_URL}/db/{db}/schemes/1/sequence"
    payload = {
        "base64": True,
        "details": True,
        "sequence": base64.b64encode(fasta_text.encode()).decode()
    }
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    dbg(debug, f"POST {url}")
    r = requests.post(url, json=payload, headers=headers, timeout=timeout)
    return r


def write_tsv(preds: List[Dict[str, str]], out_path: str) -> None:
    os.makedirs(os.path.dirname(out_path), exist_ok=True) if os.path.dirname(out_path) else None
    cols = ["Rank", "Taxon", "Support", "Taxonomy", "Genus", "Species", "Abbreviated"]
    with open(out_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        for p in preds:
            w.writerow({
                "Rank": p.get("rank", ""),
                "Taxon": p.get("taxon", ""),
                "Support": p.get("support", ""),
                "Taxonomy": p.get("taxonomy", ""),
                "Genus": p.get("genus", ""),
                "Species": p.get("species", ""),
                "Abbreviated": p.get("abbrev", ""),
            })


def main():
    ap = argparse.ArgumentParser(description="rMLST species ID via PubMLST kiosk API (no OAuth).")
    ap.add_argument("-f", "--file", default="contigs.fasta", help="Assembly contigs (FASTA)")
    ap.add_argument("-o", "--output", default="rMLST.tsv", help="Output TSV path (default: rMLST.tsv)")
    ap.add_argument("-O", "--organism_file", default=None,
                    help="YAML with supported organism labels (list, dict['amrfinder'], or dict-of-lists)")
    ap.add_argument("-s", "--species_file", default=None,
                    help="Write detected supported label (Genus or Taxon) to this file (one line)")
    ap.add_argument("--db", default=DEFAULT_DB, help=f"PubMLST DB (default: {DEFAULT_DB})")
    ap.add_argument("--timeout", type=int, default=120, help="HTTP timeout seconds (default: 120)")
    ap.add_argument("--debug", action="store_true", help="Verbose debug logging")
    args = ap.parse_args()

    # Read FASTA
    try:
        with open(args.file, "r") as fh:
            fasta = fh.read()
    except FileNotFoundError:
        print(f"ERROR: FASTA not found: {args.file}", file=sys.stderr)
        sys.exit(2)

    print("Encoding FASTA")

    # POST to kiosk endpoint
    resp = post_to_kiosk(args.db, fasta, timeout=args.timeout, debug=args.debug)

    if resp.status_code != 200:
        # Try to show structured error if present
        try:
            err = resp.json()
            print(json.dumps(err, indent=2))
        except Exception:
            print(resp.text)
        print("No taxon prediction returned; not writing TSV.")
        if args.species_file:
            print("No supported organism detected; not writing species file.")
        sys.exit(1)

    # Parse response
    try:
        data = resp.json()
    except Exception:
        print("ERROR: Server returned non-JSON.", file=sys.stderr)
        sys.exit(1)

    preds_raw = data.get("taxon_prediction")
    if not preds_raw:
        print("No match")
        # still write empty TSV header for pipeline sanity
        write_tsv([], args.output)
        if args.species_file:
            print("No supported organism detected; not writing species file.")
        sys.exit(0)

    # Tidy/enrich predictions
    preds: List[Dict[str, str]] = []
    for m in preds_raw:
        taxon = (m.get("taxon") or "").strip()
        parts = taxon.split()
        genus = parts[0] if len(parts) >= 1 else ""
        species = parts[1] if len(parts) >= 2 else ""
        preds.append({
            "rank": str(m.get("rank", "")),
            "taxon": taxon,
            "support": str(m.get("support", "")),
            "taxonomy": m.get("taxonomy", ""),
            "genus": genus,
            "species": species,
            "abbrev": abbreviate_taxon(taxon),
        })

    # Write TSV
    write_tsv(preds, args.output)
    print(f"Wrote: {args.output}")

    # Supported-organism labeling (optional)
    label_written = False
    if args.organism_file:
        try:
            supported = load_supported(args.organism_file, debug=args.debug) or set()
        except Exception as e:
            print(f"Warning: failed to read organism file: {e}", file=sys.stderr)
            supported = set()
        # Choose top-ranked prediction (lowest rank number)
        try:
            # Convert rank to numeric for robust ordering
            def rank_key(p):
                try:
                    return float(p["rank"])
                except Exception:
                    return float("inf")

            top = sorted(preds, key=rank_key)[0]
        except Exception:
            top = preds[0]

        # Consider both Genus and full Taxon (with underscore normalization)
        genus = top.get("genus", "").strip()
        taxon = top.get("taxon", "").strip()
        taxon_norm = taxon.replace(" ", "_") if taxon else ""

        chosen = None
        if genus and genus in supported:
            chosen = genus
        elif taxon_norm and taxon_norm in supported:
            chosen = taxon_norm

        if chosen and args.species_file:
            sd = os.path.dirname(args.species_file)
            if sd:
                os.makedirs(sd, exist_ok=True)
            with open(args.species_file, "w") as fh:
                fh.write(str(chosen))
            print(f"Wrote supported species label: {args.species_file}")
            label_written = True

    if args.species_file and not label_written and not args.organism_file:
        # If user asked for a species file but didn't provide supported set,
        # write the top taxon (abbreviated) for convenience.
        try:
            def rank_key(p):
                try:
                    return float(p["rank"])
                except Exception:
                    return float("inf")
            top = sorted(preds, key=rank_key)[0]
            label = top["abbrev"] or top["taxon"]
            sd = os.path.dirname(args.species_file)
            if sd:
                os.makedirs(sd, exist_ok=True)
            with open(args.species_file, "w") as fh:
                fh.write(label)
            print(f"Wrote species label: {args.species_file}")
        except Exception as e:
            print(f"Warning: failed to write species file: {e}", file=sys.stderr)

    sys.exit(0)


if __name__ == "__main__":
    main()
