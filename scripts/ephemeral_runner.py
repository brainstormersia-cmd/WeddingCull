#!/usr/bin/env python3
import os
import sys
import json
import time
import shutil
import zipfile
import subprocess
import urllib.request

REPO = "brainstormersia-cmd/WeddingCull"
RUNNER_DIR = "X:/temp_actions_runner"
CACHE_ZIP = "X:/WeddingCullDatasets/transfer/actions-runner-win-x64-2.337.0.zip"
RUNNER_URL = "https://github.com/actions/runner/releases/download/v2.337.0/actions-runner-win-x64-2.337.0.zip"

def get_token():
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        try:
            token = subprocess.check_output(["git", "config", "--get", "user.token"]).decode().strip()
        except Exception:
            pass
    if not token:
        token_file = os.path.join(os.path.dirname(__file__), "..", ".github_token")
        if os.path.exists(token_file):
            with open(token_file) as f:
                token = f.read().strip()
    return token

TOKEN = get_token()
if not TOKEN:
    print("❌ ERROR: GitHub Token not found in GITHUB_TOKEN, git config, or .github_token")
    sys.exit(1)

HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Accept": "application/vnd.github+json",
    "User-Agent": "WeddingCull-Ephemeral-Runner"
}

def api_post(endpoint):
    url = f"https://api.github.com/repos/{REPO}/{endpoint}"
    req = urllib.request.Request(url, data=b"", headers=HEADERS, method="POST")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))

def dispatch_workflow(workflow_file="export-authentic-features.yml", ref="main"):
    url = f"https://api.github.com/repos/{REPO}/actions/workflows/{workflow_file}/dispatches"
    data = json.dumps({"ref": ref}).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=HEADERS, method="POST")
    with urllib.request.urlopen(req) as resp:
        print(f"Dispatched {workflow_file} on {ref}, status: {resp.status}")

def setup_runner(run_dir):
    os.makedirs(os.path.dirname(CACHE_ZIP), exist_ok=True)
    if not os.path.exists(CACHE_ZIP):
        print(f"Downloading runner from {RUNNER_URL}...")
        req = urllib.request.Request(RUNNER_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req) as resp, open(CACHE_ZIP, "wb") as out_f:
            shutil.copyfileobj(resp, out_f)
        print("Download complete.")

    if os.path.exists(run_dir):
        try:
            cleanup_runner(run_dir)
        except Exception:
            pass
        shutil.rmtree(run_dir, ignore_errors=True)

    os.makedirs(run_dir, exist_ok=True)
    print(f"Extracting runner to {run_dir}...")
    with zipfile.ZipFile(CACHE_ZIP, "r") as z:
        z.extractall(run_dir)

    print("Fetching registration token...")
    reg_data = api_post("actions/runners/registration-token")
    reg_token = reg_data["token"]
    print(f"Got registration token (expires: {reg_data.get('expires_at')})")

    print("Configuring runner...")
    config_cmd = [
        os.path.join(run_dir, "config.cmd"),
        "--url", f"https://github.com/{REPO}",
        "--token", reg_token,
        "--name", "local-dataset-host",
        "--labels", "self-hosted,windows,dataset-host",
        "--unattended",
        "--replace"
    ]
    res = subprocess.run(config_cmd, cwd=run_dir, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Config failed: {res.stderr}\n{res.stdout}")
        sys.exit(res.returncode)
    print("Runner configured successfully.")

def run_once(run_dir):
    print("Starting runner with --once...")
    run_cmd = [os.path.join(run_dir, "run.cmd"), "--once"]
    proc = subprocess.Popen(run_cmd, cwd=run_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(5)
    print("Dispatching export-authentic-features.yml...")
    dispatch_workflow()
    print("Waiting for runner to execute job...")
    while True:
        line = proc.stdout.readline()
        if not line and proc.poll() is not None:
            break
        if line:
            print("[RUNNER]", line.strip())
    ret = proc.poll()
    print(f"Runner process finished with code {ret}")
    return ret

def cleanup_runner(run_dir):
    print("Cleaning up runner registration...")
    try:
        rem_data = api_post("actions/runners/remove-token")
        rem_token = rem_data["token"]
        rem_cmd = [os.path.join(run_dir, "config.cmd"), "remove", "--token", rem_token]
        subprocess.run(rem_cmd, cwd=run_dir, capture_output=True, text=True)
        print("Runner removed from GitHub.")
    except Exception as e:
        print(f"Warning during runner removal: {e}")
    time.sleep(2)
    shutil.rmtree(run_dir, ignore_errors=True)
    print("Runner directory cleaned.")

if __name__ == "__main__":
    run_dir = RUNNER_DIR
    action = sys.argv[1] if len(sys.argv) > 1 else "run"
    if action == "run":
        try:
            setup_runner(run_dir)
            ret = run_once(run_dir)
        finally:
            cleanup_runner(run_dir)
    elif action == "clean":
        cleanup_runner(run_dir)
