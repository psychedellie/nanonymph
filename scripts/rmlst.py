#!/usr/bin/env python3
"""
rMLST species identification via PubMLST (BIGSdb) REST API with OAuth 1.0a.

First-time auth (one-time per machine):
  ./rmlst.py --auth-only --consumer-key <KEY> --consumer-secret '<SECRET>'

Normal run (after first-time auth):
  ./rmlst.py -f assembly.fasta -o results/rMLST.tsv \
    -O supported_organisms.yaml -s results/species.txt

Dependencies: requests, requests-oauthlib, pyyaml, pandas
"""

import os
import sys
import json
import time
import base64
import argparse
import webbrowser
from urllib.parse import urlencode

import yaml
import pandas as pd
import requests
from requests_oauthlib import OAuth1

# ----- BIGSdb (PubMLST) constants -----
DB = "pubmlst_rmlst_seqdef"
BASE = f"https://rest.pubmlst.org/db/{DB}"
REQ_TOKEN_URL = f"{BASE}/oauth/get_request_token"
ACCESS_TOKEN_URL = f"{BASE}/oauth/get_access_token"
SESSION_TOKEN_URL = f"{BASE}/oauth/get_session_token"
AUTHORIZE_URL = f"https://pubmlst.org/bigsdb?db={DB}&page=authorizeClient"  # classic authorize page

# Protected rMLST Species ID endpoint
SPECIES_ID_URL = f"{BASE}/schemes/1/sequence"

# Where we store durable tokens
CONFIG_PATH = os.path.expanduser("~/.pubmlst_oauth.yaml")


# ---------------- Helpers ------------------

def load_cfg(path=CONFIG_PATH):
    if os.path.exists(path):
        with open(path, "r") as fh:
            return yaml.safe_load(fh) or {}
    return {}


def save_cfg(cfg, path=CONFIG_PATH):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, "w") as fh:
        yaml.safe_dump(cfg, fh, sort_keys=True)


def ensure_access_token(consumer_key, consumer_secret, cfg):
    """
    Ensure we have an ACCESS TOKEN saved. If not, run the interactive OAuth:
    request token -> browser authorize -> verifier -> access token.
    """
    if cfg.get("access_token") and cfg.get("access_token_secret"):
        return cfg

    if not consumer_key or not consumer_secret:
        print("ERROR: Missing --consumer-key / --consumer-secret for first-time auth.", file=sys.stderr)
        sys.exit(2)

    # Step 1: request token (OAuth params in QUERY)
    oauth_req = OAuth1(
        client_key=consumer_key,
        client_secret=consumer_secret,
        signature_method="HMAC-SHA1",
        callback_uri="oob",
        signature_type="QUERY",
    )
    r = requests.get(REQ_TOKEN_URL, auth=oauth_req, timeout=60)
    if r.status_code != 200:
        print("Failed to obtain request token:", r.text, file=sys.stderr)
        sys.exit(1)
    req = r.json()
    rtok, rtok_sec = req["oauth_token"], req["oauth_token_secret"]

    # Step 2: user authorize (get verifier)
    auth_url = f"{AUTHORIZE_URL}&{urlencode({'oauth_token': rtok})}"
    print("\n== PubMLST OAuth authorization ==")
    print("Open this URL, log in, authorize, then copy the verifier code:\n")
    print(auth_url, "\n")
    try:
        webbrowser.open(auth_url)
    except Exception:
        pass
    verifier = input("Paste verifier code: ").strip()

    # Step 3: exchange for access token (OAuth params in QUERY)
    oauth_acc = OAuth1(
        client_key=consumer_key,
        client_secret=consumer_secret,
        resource_owner_key=rtok,
        resource_owner_secret=rtok_sec,
        verifier=verifier,
        signature_method="HMAC-SHA1",
        signature_type="QUERY",
    )
    r2 = requests.get(ACCESS_TOKEN_URL, auth=oauth_acc, timeout=60)
    if r2.status_code != 200:
        print("Failed to obtain access token:", r2.text, file=sys.stderr)
        sys.exit(1)
    acc = r2.json()

    cfg.update({
        "consumer_key": consumer_key,
        "consumer_secret": consumer_secret,
        "access_token": acc["oauth_token"],
        "access_token_secret": acc["oauth_token_secret"],
    })
    cfg.pop("session_token", None)
    cfg.pop("session_token_secret", None)
    cfg.pop("session_token_time", None)
    save_cfg(cfg)
    print(f"Access token saved to {CONFIG_PATH}")
    return cfg


def get_new_session_token(cfg):
    """Get a new 12h SESSION TOKEN using the durable access token. (OAuth params in QUERY)"""
    oauth = OAuth1(
        client_key=cfg["consumer_key"],
        client_secret=cfg["consumer_secret"],
        resource_owner_key=cfg["access_token"],
        resource_owner_secret=cfg["access_token_secret"],
        signature_method="HMAC-SHA1",
        signature_type="QUERY",
    )
    r = requests.get(SESSION_TOKEN_URL, auth=oauth, timeout=60)
    if r.status_code != 200:
        raise RuntimeError(f"Failed to obtain session token: {r.text}")
    ses = r.json()
    cfg["session_token"] = ses["oauth_token"]
    cfg["session_token_secret"] = ses["oauth_token_secret"]
    cfg["session_token_time"] = int(time.time())
    save_cfg(cfg)
    return cfg


def post_species_id_with_session(cfg, fasta_text, timeout=120):
    """Always fetch a fresh 12h session token, then POST signed via QUERY."""
    # Always refresh session token before protected call
    cfg = get_new_session_token(cfg)

    payload = {
        "base64": True,
        "details": True,
        "sequence": base64.b64encode(fasta_text.encode()).decode()
    }
    headers = {"Content-Type": "application/json", "Accept": "application/json"}

    def _post():
        # Use QUERY signing for POST too (PubMLST/BIGSdb friendly)
        oauth = OAuth1(
            client_key=cfg["consumer_key"],
            client_secret=cfg["consumer_secret"],
            resource_owner_key=cfg["session_token"],
            resource_owner_secret=cfg["session_token_secret"],
            signature_method="HMAC-SHA1",
            signature_type="QUERY",
        )
        return requests.post(SPECIES_ID_URL, json=payload, headers=headers, auth=oauth, timeout=timeout)

    resp = _post()

    # If something still invalidates the session, fetch a new one and retry once
    if resp.status_code == 401:
        cfg = get_new_session_token(cfg)
        resp = _post()

    return resp


def parse_predictions(json_obj):
    """Return tidy DataFrame with: Genus, Species, Taxon, Abbreviated, Rank, Percentage"""
    cols = ["Genus", "Species", "Taxon", "Abbreviated", "Rank", "Percentage"]
    df = pd.DataFrame(columns=cols)
    for res in (json_obj.get("taxon_prediction") or []):
        taxon = (res.get("taxon") or "").strip()
        parts = taxon.split()
        genus = parts[0] if len(parts) >= 1 else ""
        species = parts[1] if len(parts) >= 2 else ""
        abbreviated = (f"{genus[0]}. {species}").strip() if genus and species else taxon
        df.loc[len(df)] = [
            genus,
            species,
            taxon,
            abbreviated,
            res.get("rank", ""),
            res.get("support", ""),
        ]
    return df


def load_supported(path):
    with open(path, "r") as fh:
        y = yaml.safe_load(fh) or {}
    if isinstance(y, dict) and isinstance(y.get("amrfinder"), list):
        return set(map(str, y["amrfinder"]))
    if isinstance(y, list):
        return set(map(str, y))
    flat = []
    if isinstance(y, dict):
        for v in y.values():
            if isinstance(v, list):
                flat.extend(v)
    return set(map(str, flat))


def check_supported(supported, df):
    if df is None or df.empty:
        return None
    top = df.sort_values(by="Rank", ascending=True).iloc[0]
    genus = str(top.get("Genus", "")).strip()
    taxon = str(top.get("Taxon", "")).strip().replace(" ", "_")
    if genus and genus in supported:
        return genus
    if taxon and taxon in supported:
        return taxon
    return None


# ------------------ CLI ------------------

def main():
    ap = argparse.ArgumentParser(
        description="PubMLST rMLST species ID with OAuth (stores tokens in ~/.pubmlst_oauth.yaml)"
    )
    ap.add_argument("-f", "--file", help="Assembly FASTA (required unless --auth-only)")
    ap.add_argument("-o", "--output", default="rMLST.tsv", help="Output TSV path (default: rMLST.tsv)")
    ap.add_argument("-O", "--organism_file", default=None,
                    help="YAML of supported organisms (optionally under 'amrfinder')")
    ap.add_argument("-s", "--species_file", default=None,
                    help="Write detected supported species/Genus to this file")
    ap.add_argument("--consumer-key", help="PubMLST OAuth consumer key (first run only)")
    ap.add_argument("--consumer-secret", help="PubMLST OAuth consumer secret (first run only)")
    ap.add_argument("--auth-only", action="store_true",
                    help="Run OAuth setup/verification only (no FASTA upload)")
    ap.add_argument("--timeout", type=int, default=120, help="HTTP timeout seconds (default: 120)")
    args = ap.parse_args()

    # Load existing config and merge any provided key/secret
    cfg = load_cfg()
    if args.consumer_key:
        cfg["consumer_key"] = args.consumer_key
    if args.consumer_secret:
        cfg["consumer_secret"] = args.consumer_secret

    # Ensure durable ACCESS TOKEN exists (one-time interactive if missing)
    cfg = ensure_access_token(cfg.get("consumer_key"), cfg.get("consumer_secret"), cfg)

    # If auth-only, optionally fetch a session token to verify and exit
    if args.auth_only:
        try:
            cfg = get_new_session_token(cfg)
            print("Authentication OK. Session token acquired.")
        except Exception as e:
            print(f"Authentication failed: {e}", file=sys.stderr)
            sys.exit(1)
        sys.exit(0)

    # Require FASTA for species ID calls
    if not args.file:
        print("ERROR: --file FASTA is required unless you use --auth-only.", file=sys.stderr)
        sys.exit(2)

    # Read FASTA
    with open(args.file, "r") as fh:
        fasta = fh.read()

    print("Encoding FASTA", flush=True)
    resp = post_species_id_with_session(cfg, fasta, timeout=args.timeout)

    if resp.status_code != 200:
        # Show server message and exit gracefully
        try:
            print(json.dumps(resp.json(), indent=2))
        except Exception:
            print(resp.text)
        print("No taxon prediction returned; not writing TSV.")
        if args.species_file:
            print("No supported organism detected; not writing species file.")
        sys.exit(0)

    data = resp.json()
    preds = parse_predictions(data)

    # Optional supported-organism tagging
    if args.organism_file:
        try:
            supported = load_supported(args.organism_file)
        except Exception as e:
            print(f"Warning: failed to read organism file: {e}", file=sys.stderr)
            supported = set()
        label = check_supported(supported, preds)
        if label and args.species_file:
            sd = os.path.dirname(args.species_file)
            if sd:
                os.makedirs(sd, exist_ok=True)
            with open(args.species_file, "w") as fh:
                fh.write(str(label))
            print(f"Wrote supported species label: {args.species_file}")
        elif args.species_file:
            print("No supported organism detected; not writing species file.")

    # Write TSV if we have predictions
    if preds.empty:
        print("No taxon prediction returned; not writing TSV.")
    else:
        od = os.path.dirname(args.output)
        if od:
            os.makedirs(od, exist_ok=True)
        preds.to_csv(args.output, sep="\t", index=False)
        print(f"Wrote: {args.output}")


if __name__ == "__main__":
    main()
