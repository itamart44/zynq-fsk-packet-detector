"""
Upload bitstream + HWH to PYNQ-Z2 via Jupyter REST API (Contents API).

Usage:
    python upload_to_pynq.py [--password xilinx] [--port 80]

The Jupyter notebook root on PYNQ is ~/jupyter_notebooks/.
Files land in ~/jupyter_notebooks/fsk_project/ so that
BITSTREAM = 'fsk_project/design_1_wrapper.bit' in run_fpga.py resolves correctly.
"""

import argparse
import base64
import json
import os
import sys
from urllib.parse import urlparse
import requests

BOARD_IP   = "192.168.2.99"
REMOTE_DIR = "fsk_project"        # relative to Jupyter notebook root

LOCAL_FILES = [
    {
        "local":  r"C:\Users\User\fsk_signal_detection.runs\impl_1\design_1_wrapper.bit",
        "remote": "design_1_wrapper.bit",
    },
    {
        # Vivado names this design_1.hwh; PYNQ pairs HWH by matching the .bit stem
        "local":  r"C:\Users\User\fsk_signal_detection.srcs\sources_1\bd\design_1\hw_handoff\design_1.hwh",
        "remote": "design_1_wrapper.hwh",
    },
    {
        "local":  r"C:\Users\User\zynq-fsk-packet-detector\sw\multi_channel\run_fpga.py",
        "remote": "run_fpga.py",
    },
]


def jurl(base, *parts):
    return base.rstrip("/") + "/" + "/".join(p.strip("/") for p in parts)


def xsrf(session):
    """Always read the freshest XSRF token directly from the session cookies."""
    return session.cookies.get("_xsrf", "")


def get_session(base, password):
    s = requests.Session()

    # Step 1: Load login page to obtain the initial XSRF cookie
    r = s.get(jurl(base, "login"), timeout=10)
    r.raise_for_status()
    tok = xsrf(s)
    print(f"  Login page: {r.status_code}, XSRF: {tok[:20]}...")

    # Step 2: POST credentials — do NOT follow redirects.
    # Following redirects through nginx can break the cookie handshake because
    # nginx may intercept the redirect and turn the POST into a GET on /login.
    r = s.post(
        jurl(base, "login?next=%2F"),
        data={"_xsrf": tok, "password": password},
        headers={
            "X-XSRFToken": tok,
            "Referer": jurl(base, "login"),
        },
        allow_redirects=False,
        timeout=10,
    )
    print(f"  Login POST: {r.status_code}, Location: {r.headers.get('Location', 'none')}")

    if r.status_code not in (302, 200):
        print(f"ERROR: unexpected login response {r.status_code}", file=sys.stderr)
        sys.exit(1)
    if r.status_code == 302 and "login" in r.headers.get("Location", ""):
        print("ERROR: login redirected back to /login — wrong password?", file=sys.stderr)
        sys.exit(1)

    tok = xsrf(s)
    session_cookies = [c.name for c in s.cookies if "username" in c.name]
    print(f"  Session cookie(s): {session_cookies}")
    if not session_cookies:
        print("WARNING: no session cookie found — auth may have failed", file=sys.stderr)

    # Step 3: Verify with the API
    r = s.get(jurl(base, "api/contents"), timeout=10)
    print(f"  GET /api/contents: {r.status_code}")
    if r.status_code in (401, 403):
        print(f"ERROR: API access denied ({r.status_code}). Auth failed.", file=sys.stderr)
        sys.exit(1)

    return s, base


def ensure_directory(session, base, remote_dir):
    url = jurl(base, "api/contents", remote_dir)
    r = session.get(url, timeout=10)
    if r.status_code == 200:
        print(f"  Directory '{remote_dir}' already exists.")
        return

    payload = json.dumps({"type": "directory", "format": "json"})
    r = session.put(
        url,
        data=payload,
        headers={
            "X-XSRFToken": xsrf(session),
            "Content-Type": "application/json",
            "Referer": jurl(base, "tree"),
        },
        timeout=10,
    )
    if r.status_code in (200, 201):
        print(f"  Created directory '{remote_dir}'.")
    else:
        print(f"  WARNING: mkdir returned {r.status_code}: {r.text[:200]}", file=sys.stderr)


def upload_file(session, base, remote_dir, local_path, remote_name):
    print(f"  Uploading {os.path.basename(local_path)} -> {remote_dir}/{remote_name} ...", end=" ", flush=True)
    with open(local_path, "rb") as fh:
        content_b64 = base64.b64encode(fh.read()).decode("ascii")

    payload = json.dumps({
        "type": "file",
        "format": "base64",
        "content": content_b64,
        "name": remote_name,
    })

    url = jurl(base, "api/contents", remote_dir, remote_name)
    r = session.put(
        url,
        data=payload,
        headers={
            "X-XSRFToken": xsrf(session),
            "Content-Type": "application/json",
            "Referer": jurl(base, "tree"),
        },
        timeout=120,
    )
    if r.status_code in (200, 201):
        size_kb = len(content_b64) * 3 // 4 // 1024
        print(f"OK ({size_kb} KB)")
    else:
        print(f"FAILED {r.status_code}")
        print(f"    Response: {r.text[:400]}", file=sys.stderr)
        # Print current cookies for debugging
        print(f"    Cookies: {dict(session.cookies)}", file=sys.stderr)
        sys.exit(1)


def try_ports(base_host, ports):
    """Return the first port where Jupyter's /login page has a password form."""
    for port in ports:
        base = f"http://{base_host}:{port}"
        try:
            r = requests.get(f"{base}/login", timeout=5, allow_redirects=False)
            # Accept direct 200 (login form served here) not 302 (proxy redirect)
            if r.status_code == 200 and "password" in r.text.lower():
                print(f"Jupyter found on port {port}")
                return base
        except requests.exceptions.ConnectionError:
            pass
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--password", default="xilinx")
    parser.add_argument("--port",     default=0, type=int,
                        help="Jupyter port (0 = auto-detect from 80/9090/8888)")
    args = parser.parse_args()

    if args.port:
        base = f"http://{BOARD_IP}:{args.port}"
        print(f"Using specified port {args.port}")
    else:
        # Try Jupyter's native port first (9090 on PYNQ), then the nginx proxy (80)
        base = try_ports(BOARD_IP, [9090, 80, 8888])
        if base is None:
            print("ERROR: Could not reach Jupyter on ports 9090, 80, or 8888", file=sys.stderr)
            sys.exit(1)

    print(f"Connecting to {base}")
    session, base = get_session(base, args.password)
    print(f"Authentication OK. Using base: {base}")

    ensure_directory(session, base, REMOTE_DIR)

    for entry in LOCAL_FILES:
        if not os.path.isfile(entry["local"]):
            print(f"ERROR: local file not found: {entry['local']}", file=sys.stderr)
            sys.exit(1)
        upload_file(session, base, REMOTE_DIR, entry["local"], entry["remote"])

    print("\nAll files uploaded successfully.")
    print(f"On the board: ~/jupyter_notebooks/{REMOTE_DIR}/")


if __name__ == "__main__":
    main()
