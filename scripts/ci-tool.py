import urllib.request
import json
import os
import sys
import zipfile

TOKEN = os.environ.get("GITHUB_TOKEN", "")
if not TOKEN:
    # Try git config
    import subprocess
    try:
        TOKEN = subprocess.check_output(["git", "config", "--get", "user.token"]).decode().strip()
    except Exception:
        pass
    if not TOKEN:
        # Fallback to local .token file if present (gitignored)
        token_file = os.path.join(os.path.dirname(__file__), "..", ".github_token")
        if os.path.exists(token_file):
            with open(token_file) as f:
                TOKEN = f.read().strip()
REPO = "brainstormersia-cmd/WeddingCull"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Accept": "application/vnd.github+json",
    "User-Agent": "WeddingCull-Release-Validator"
}

def get_runs():
    url = f"https://api.github.com/repos/{REPO}/actions/runs?per_page=10"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    for run in data.get("workflow_runs", []):
        print(f"ID: {run['id']} | Name: {run['name']} | Event: {run['event']} | Status: {run['status']} | Conclusion: {run['conclusion']} | SHA: {run['head_sha'][:7]}")

def get_run_details(run_id):
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        run = json.loads(resp.read().decode("utf-8"))
    print(f"Run {run_id}: {run['name']}")
    print(f"  Status: {run['status']}, Conclusion: {run['conclusion']}, Branch: {run['head_branch']}, SHA: {run['head_sha'][:7]}")
    
    # Check jobs
    jobs_url = run["jobs_url"]
    req = urllib.request.Request(jobs_url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        jobs_data = json.loads(resp.read().decode("utf-8"))
    for job in jobs_data.get("jobs", []):
        name = job['name'].encode('ascii', errors='replace').decode('ascii')
        print(f"    Job: {name} (ID: {job['id']}) : {job['status']} ({job['conclusion']})")
        if job['conclusion'] == 'failure':
            print(f"      Failed Job Steps:")
            for step in job.get('steps', []):
                sname = step['name'].encode('ascii', errors='replace').decode('ascii')
                print(f"        Step: {sname} : {step['status']} ({step['conclusion']})")

def get_job_log(job_id):
    url = f"https://api.github.com/repos/{REPO}/actions/jobs/{job_id}/logs"
    class NoAuthRedirectHandler(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return urllib.request.Request(newurl)

    opener = urllib.request.build_opener(NoAuthRedirectHandler())
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with opener.open(req) as resp:
            lines = resp.read().decode('utf-8', errors='replace').splitlines()
            print(f"=== Last 100 lines of job {job_id} ===")
            for line in lines[-100:]:
                print(line.encode('ascii', errors='replace').decode('ascii'))
    except Exception as e:
        print(f"Error fetching log: {e}")

def list_and_download_artifacts(run_id, out_dir="artifacts_download"):
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/artifacts"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    
    os.makedirs(out_dir, exist_ok=True)
    artifacts = data.get("artifacts", [])
    print(f"Found {len(artifacts)} artifacts for run {run_id}:")
    for a in artifacts:
        print(f"  Artifact: {a['name']} ({a['size_in_bytes']} bytes)")
        download_url = a["archive_download_url"]
        dl_req = urllib.request.Request(download_url, headers=HEADERS)
        zip_path = os.path.join(out_dir, f"{a['name']}.zip")
        try:
            with urllib.request.urlopen(dl_req) as dl_resp, open(zip_path, "wb") as out_f:
                out_f.write(dl_resp.read())
            extract_dir = os.path.join(out_dir, a["name"])
            os.makedirs(extract_dir, exist_ok=True)
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(extract_dir)
            print(f"    Extracted to {extract_dir}")
        except Exception as e:
            print(f"    Error downloading {a['name']}: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "list":
            get_runs()
        elif cmd == "details" and len(sys.argv) > 2:
            get_run_details(sys.argv[2])
        elif cmd == "download" and len(sys.argv) > 2:
            out = sys.argv[3] if len(sys.argv) > 3 else "artifacts_download"
            list_and_download_artifacts(sys.argv[2], out)
        elif cmd == "log" and len(sys.argv) > 2:
            get_job_log(sys.argv[2])
        else:
            get_run_details(cmd)
    else:
        get_runs()
