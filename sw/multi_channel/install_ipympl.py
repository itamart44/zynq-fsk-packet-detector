"""
install_ipympl.py
Installs ipympl on the PYNQ board (no internet required on the board).

Strategy:
  1. pip download on Windows  → wheels/ (pure-Python, so platform-neutral)
  2. Upload wheels to board   → ~/jupyter_notebooks/fsk_project/wheels/
  3. pip install --no-index   → via Jupyter kernel WebSocket

Requires on Windows:
    pip install requests websocket-client
"""

import base64
import glob
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid
from urllib.parse import urlparse

try:
    import requests
except ImportError:
    sys.exit("Run: pip install requests")
try:
    import websocket
except ImportError:
    sys.exit("Run: pip install websocket-client")

BOARD_IP   = "192.168.2.99"
PASSWORD   = "xilinx"
REMOTE_DIR = "fsk_project"
# Jupyter notebook root on PYNQ
JUPYTER_ROOT = "/home/xilinx/jupyter_notebooks"


# ── Jupyter helpers (shared with upload_to_pynq.py) ───────────────────────

def jurl(base, *parts):
    return base.rstrip("/") + "/" + "/".join(p.strip("/") for p in parts)

def current_xsrf(session):
    return session.cookies.get("_xsrf", "")

def find_jupyter(host):
    for port in [9090, 80, 8888]:
        base = f"http://{host}:{port}"
        try:
            r = requests.get(f"{base}/login", timeout=5, allow_redirects=False)
            if r.status_code == 200 and "password" in r.text.lower():
                print(f"Jupyter on port {port}")
                return base
        except requests.exceptions.ConnectionError:
            pass
    sys.exit("Jupyter not reachable on ports 9090, 80, 8888")

def authenticate(base, password):
    s = requests.Session()
    r = s.get(jurl(base, "login"), timeout=10)
    r.raise_for_status()
    tok = current_xsrf(s)
    r = s.post(
        jurl(base, "login?next=%2F"),
        data={"_xsrf": tok, "password": password},
        headers={"X-XSRFToken": tok, "Referer": jurl(base, "login")},
        allow_redirects=False,
        timeout=10,
    )
    if r.status_code != 302:
        sys.exit(f"Login failed (HTTP {r.status_code})")
    return s

def ensure_dir(session, base, remote_path):
    url = jurl(base, "api/contents", remote_path)
    if session.get(url, timeout=10).status_code == 200:
        return
    r = session.put(url,
        data=json.dumps({"type": "directory"}),
        headers={"X-XSRFToken": current_xsrf(session),
                 "Content-Type": "application/json"},
        timeout=10)
    if r.status_code not in (200, 201):
        print(f"  mkdir warning {r.status_code}: {r.text[:120]}", file=sys.stderr)

def upload_file(session, base, remote_dir, local_path, remote_name):
    print(f"  Uploading {remote_name} ...", end=" ", flush=True)
    with open(local_path, "rb") as fh:
        content_b64 = base64.b64encode(fh.read()).decode("ascii")
    payload = json.dumps({"type": "file", "format": "base64",
                          "content": content_b64, "name": remote_name})
    url = jurl(base, "api/contents", remote_dir, remote_name)
    r = session.put(url, data=payload,
        headers={"X-XSRFToken": current_xsrf(session),
                 "Content-Type": "application/json"},
        timeout=120)
    if r.status_code in (200, 201):
        print(f"OK ({len(content_b64)*3//4//1024} KB)")
    else:
        print(f"FAILED {r.status_code}: {r.text[:200]}", file=sys.stderr)
        sys.exit(1)


# ── Kernel execution helper ────────────────────────────────────────────────

def run_on_kernel(session, base, code, timeout_s=180):
    """Start a kernel, execute code, stream output, delete kernel. Returns status."""
    # Start kernel
    r = session.post(jurl(base, "api/kernels"),
        data=json.dumps({"name": "python3"}),
        headers={"X-XSRFToken": current_xsrf(session),
                 "Content-Type": "application/json"},
        timeout=30)
    r.raise_for_status()
    kernel_id = r.json()["id"]
    print(f"Kernel {kernel_id} started.")

    status = None
    try:
        parsed = urlparse(base)
        ws_url = f"ws://{parsed.netloc}/api/kernels/{kernel_id}/channels"
        cookie_str = "; ".join(f"{c.name}={c.value}" for c in session.cookies)
        ws = websocket.create_connection(
            ws_url, header=[f"Cookie: {cookie_str}"], timeout=20)

        msg_id = str(uuid.uuid4())
        ws.send(json.dumps({
            "header": {"msg_id": msg_id, "msg_type": "execute_request",
                       "session": str(uuid.uuid4()), "username": "",
                       "date": "", "version": "5.3"},
            "parent_header": {}, "metadata": {},
            "content": {"code": code, "silent": False,
                        "store_history": False,
                        "user_expressions": {}, "allow_stdin": False},
            "channel": "shell", "buffers": [],
        }))

        deadline = time.time() + timeout_s
        while time.time() < deadline:
            try:
                ws.settimeout(5.0)
                msg = json.loads(ws.recv())
            except websocket.WebSocketTimeoutException:
                print(".", end="", flush=True)
                continue
            if msg.get("parent_header", {}).get("msg_id") != msg_id:
                continue
            mtype = msg.get("msg_type", "")
            if mtype == "stream":
                print(msg["content"].get("text", ""), end="", flush=True)
            elif mtype == "error":
                print("\n" + "\n".join(msg["content"].get("traceback", [])),
                      file=sys.stderr)
                status = "error"
                break
            elif mtype == "execute_reply":
                status = msg["content"].get("status", "unknown")
                break
        ws.close()
    finally:
        session.delete(jurl(base, "api/kernels", kernel_id),
                       headers={"X-XSRFToken": current_xsrf(session)},
                       timeout=10)
        print(f"\nKernel {kernel_id} deleted.")
    return status


# ── Main ──────────────────────────────────────────────────────────────────

def main():
    # ── Step 1: Download wheels on Windows ───────────────────────────────
    wheels_dir = os.path.join(tempfile.gettempdir(), "pynq_ipympl_wheels")
    os.makedirs(wheels_dir, exist_ok=True)

    print(f"Downloading ipympl wheels to {wheels_dir} ...")
    # ipympl and its direct deps are all pure-Python (py3-none-any),
    # so wheels downloaded on Windows install fine on Linux ARM.
    result = subprocess.run(
        [sys.executable, "-m", "pip", "download",
         "ipympl",
         "--dest", wheels_dir,
         "--prefer-binary",
         # Exclude packages almost certainly already on PYNQ
         "--no-deps"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        # Fall back: try with full dependency tree in case --no-deps is the issue
        print("--no-deps download failed, retrying with full deps...")
        result = subprocess.run(
            [sys.executable, "-m", "pip", "download",
             "ipympl", "--dest", wheels_dir, "--prefer-binary"],
            capture_output=True, text=True
        )
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit("pip download failed on Windows")

    wheel_files = glob.glob(os.path.join(wheels_dir, "*.whl")) + \
                  glob.glob(os.path.join(wheels_dir, "*.tar.gz"))
    if not wheel_files:
        sys.exit("No wheels downloaded — check pip output above")
    print(f"Downloaded: {[os.path.basename(f) for f in wheel_files]}")

    # ── Step 2: Authenticate ──────────────────────────────────────────────
    base = find_jupyter(BOARD_IP)
    session = authenticate(base, PASSWORD)
    print("Authenticated.")

    # ── Step 3: Upload wheels to board ────────────────────────────────────
    wheels_remote = f"{REMOTE_DIR}/wheels"
    ensure_dir(session, base, REMOTE_DIR)
    ensure_dir(session, base, wheels_remote)

    for wheel_path in wheel_files:
        upload_file(session, base, wheels_remote,
                    wheel_path, os.path.basename(wheel_path))

    # ── Step 4: Install from local wheels via kernel ──────────────────────
    wheels_fs = f"{JUPYTER_ROOT}/{wheels_remote}"
    install_code = "\n".join([
        "import subprocess, sys",
        f"r = subprocess.run(",
        f"    [sys.executable, '-m', 'pip', 'install',",
        f"     '--no-index', '--find-links', {wheels_fs!r}, 'ipympl'],",
        f"    stdout=subprocess.PIPE, stderr=subprocess.STDOUT",
        f")",
        "print(r.stdout.decode('utf-8', errors='replace'))",
        "sys.stdout.flush()",
    ])

    print("\nInstalling ipympl on board from local wheels ...")
    print("-" * 60)
    status = run_on_kernel(session, base, install_code, timeout_s=180)
    print("-" * 60)

    if status == "ok":
        print("ipympl installed successfully.")
        # ── Step 5: Verify ────────────────────────────────────────────────
        verify_code = "\n".join([
            "import ipympl",
            "print('ipympl version:', ipympl.__version__)",
        ])
        print("\nVerifying ...")
        run_on_kernel(session, base, verify_code, timeout_s=30)
    else:
        print(f"Installation may have failed (status={status!r}).", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
