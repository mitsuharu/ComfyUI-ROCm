#!/usr/bin/env python3
"""Build, submit, and wait for a MiniMax H3 video generation job on the local
ComfyUI + ROCm install. Defaults to C:\\Users\\mitsuharu\\ComfyUI-ROCm; set the
COMFYUI_ROCM_ROOT environment variable to point at a different checkout.

Handles the one real operational wrinkle discovered running this pipeline:
the ComfyUI server process sometimes dies mid-generation (suspected Windows
ROCm driver/TDR issue). This script detects that (connection failures, not
just an empty "{}" history response) and restarts the server + resubmits the
same job automatically, up to --max-restarts times, rather than hanging.

Usage:
  python generate_video.py --prompt "..." --width 864 --height 480 \
      --length 124 --steps 20 --seed 12345 --name my_video

Prints the final .mp4 path on success (last line, prefixed with OUTPUT:),
or a non-zero exit with an error message on failure.
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Override with the environment variable if your checkout lives somewhere
# other than this default (e.g. a different user, or a project-scoped copy of
# this skill living inside the repo itself rather than the machine-wide
# ~/.claude/skills install).
ROOT = Path(os.environ.get("COMFYUI_ROCM_ROOT", r"C:\Users\mitsuharu\ComfyUI-ROCm"))
VENV_PYTHON = ROOT / ".venv" / "Scripts" / "python.exe"
COMFY_MAIN = ROOT / "ComfyUI" / "main.py"
TEMPLATE = ROOT / "workflow_template.json"
OUTPUT_DIR = ROOT / "ComfyUI" / "output" / "video"
SERVER_LOG = ROOT / "server_autostart.log"
BASE_URL = "http://localhost:8188"


def http_get(path, timeout=5):
    with urllib.request.urlopen(BASE_URL + path, timeout=timeout) as r:
        return r.read()


def http_post_json(path, payload, timeout=15):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        BASE_URL + path, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def is_server_up(timeout=12):
    # A generous timeout matters here: ComfyUI's HTTP server is effectively
    # single-threaded and blocks while synchronously loading multi-GB model
    # files from disk (the text encoder alone is ~25GB), so a short timeout
    # during that window looks identical to "process is dead" even though
    # it's just busy. A short timeout here is the main source of false
    # "server is down" positives observed while building this script.
    try:
        http_get("/system_stats", timeout=timeout)
        return True
    except Exception:
        return False


def _launch_once():
    logf = open(SERVER_LOG, "a", encoding="utf-8")
    creationflags = 0
    if sys.platform == "win32":
        creationflags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    # --disable-dynamic-vram is required on ROCm 10: ComfyUI's dynamic VRAM
    # loader maps memory with cuMemMap, which fails there with "unspecified
    # launch failure" as soon as a model is loaded. Harmless on ROCm 7.2.1,
    # which simply falls back to the same estimate-based loading path.
    return subprocess.Popen(
        [str(VENV_PYTHON), str(COMFY_MAIN), "--disable-dynamic-vram"],
        cwd=str(ROOT),
        stdout=logf,
        stderr=logf,
        stdin=subprocess.DEVNULL,
        creationflags=creationflags,
    )


def _log_tail(lines=12):
    """Last few lines of the server log, for explaining a failed launch."""
    try:
        with open(SERVER_LOG, encoding="utf-8", errors="replace") as f:
            return "".join(f.readlines()[-lines:]).rstrip()
    except OSError:
        return "(server log unavailable)"


def start_server(wait_s=180, launch_attempts=3):
    """Launch ComfyUI as a detached background process and wait for it to answer.

    Retries the launch itself a few times: a launch can fail for reasons that
    clear on a retry — Windows briefly holding port 8188 after a previous
    instance died, or Smart App Control blocking an unsigned native extension
    on load (see SETUP.md's known issues).

    The wait loop watches the child process as well as the port, because those
    two failure modes look completely different: a server that is merely slow
    to start is still running and worth waiting on (loading ComfyUI plus its
    custom nodes legitimately takes a minute or more), whereas a server that
    already exited will never answer no matter how long we wait. Polling the
    process means a hard startup failure is retried in seconds instead of
    burning the full window first.
    """
    for attempt in range(1, launch_attempts + 1):
        print(
            f"[generate_video] starting ComfyUI server (attempt {attempt}/{launch_attempts}, "
            f"log: {SERVER_LOG}) ...",
            file=sys.stderr,
        )
        proc = _launch_once()
        deadline = time.time() + wait_s
        while time.time() < deadline:
            if is_server_up():
                print("[generate_video] server is up.", file=sys.stderr)
                return True
            if proc.poll() is not None:
                print(
                    f"[generate_video] server process exited during startup "
                    f"(code {proc.returncode}). Last log lines:\n{_log_tail()}",
                    file=sys.stderr,
                )
                break
            time.sleep(3)
        else:
            print(f"[generate_video] no response after {wait_s}s, will retry launch ...", file=sys.stderr)
        time.sleep(5)
    return False


def ensure_server():
    if is_server_up():
        return
    if not start_server():
        raise RuntimeError(
            "ComfyUI server did not come up after repeated attempts. "
            f"Check {SERVER_LOG} for errors."
        )


def build_workflow(prompt, width, height, length, steps, seed, name):
    with open(TEMPLATE, encoding="utf-8") as f:
        wf = json.load(f)
    nodes = wf["prompt"]
    nodes["5"]["inputs"]["prompt"] = prompt
    nodes["5"]["inputs"]["width"] = width
    nodes["5"]["inputs"]["height"] = height
    nodes["5"]["inputs"]["length"] = length
    nodes["7"]["inputs"]["steps"] = steps
    nodes["8"]["inputs"]["noise_seed"] = seed
    nodes["14"]["inputs"]["filename_prefix"] = f"video/{name}"
    wf["client_id"] = f"skill-{name}-{seed}"
    return wf


def submit(workflow):
    resp = http_post_json("/prompt", workflow)
    if resp.get("node_errors"):
        raise RuntimeError(f"Workflow validation errors: {resp['node_errors']}")
    return resp["prompt_id"]


def check_history(prompt_id, timeout=30):
    """Returns (done, status_str) or (False, None) if not finished yet.

    timeout is generous for the same reason as is_server_up: the server can
    go quiet for a while during model loading without actually being down.
    """
    try:
        raw = http_get(f"/history/{prompt_id}", timeout=timeout)
    except (urllib.error.URLError, ConnectionError, TimeoutError):
        return "server_down", None
    text = raw.decode("utf-8").strip()
    if text in ("{}", ""):
        return False, None
    data = json.loads(text)
    entry = data.get(prompt_id, {})
    status = entry.get("status", {})
    if status.get("completed"):
        return True, status.get("status_str")
    return False, None


def wait_for_result(workflow, name, poll_s=15, timeout_s=1800, max_restarts=3):
    prompt_id = submit(workflow)
    print(f"[generate_video] submitted prompt_id={prompt_id}", file=sys.stderr)
    restarts = 0
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        state, status_str = check_history(prompt_id)
        if state == "server_down":
            # One slow/failed check isn't proof of a crash (model loading can
            # legitimately block the server for a while) - confirm with a
            # second check after a short pause before restarting anything.
            print("[generate_video] history check failed, confirming before restarting ...", file=sys.stderr)
            time.sleep(10)
            state2, status_str2 = check_history(prompt_id)
            if state2 != "server_down":
                state, status_str = state2, status_str2
                if state is True:
                    if status_str != "success":
                        raise RuntimeError(f"Generation finished with status={status_str!r}, expected success")
                    break
                time.sleep(poll_s)
                continue
            restarts += 1
            if restarts > max_restarts:
                raise RuntimeError(
                    f"ComfyUI server kept going down (tried restarting {max_restarts} times). "
                    "Giving up. It may be a Windows ROCm driver crash under sustained load."
                )
            print(
                f"[generate_video] server appears down, restarting "
                f"(attempt {restarts}/{max_restarts}) and resubmitting job ...",
                file=sys.stderr,
            )
            ensure_server()
            prompt_id = submit(workflow)
            print(f"[generate_video] resubmitted prompt_id={prompt_id}", file=sys.stderr)
            continue
        if state is True:
            if status_str != "success":
                raise RuntimeError(f"Generation finished with status={status_str!r}, expected success")
            break
        time.sleep(poll_s)
    else:
        raise RuntimeError(f"Timed out after {timeout_s}s waiting for prompt_id={prompt_id}")

    # SaveVideo writes <prefix>_NNNNN_.mp4 with an auto-incrementing counter;
    # find the newest matching file rather than assuming _00001_.
    matches = sorted(OUTPUT_DIR.glob(f"{name}_*.mp4"), key=lambda p: p.stat().st_mtime)
    if not matches:
        raise RuntimeError(f"Job reported success but no output file found matching {name}_*.mp4 in {OUTPUT_DIR}")
    return matches[-1]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--prompt", required=True, help="English description: style, subject, action, camera, audio")
    ap.add_argument("--width", type=int, default=864)
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--length", type=int, default=124, help="frame count, 24fps, must satisfy n%%17==5 (see generate_video.md table)")
    ap.add_argument("--steps", type=int, default=20)
    ap.add_argument("--seed", type=int, default=int(time.time()))
    ap.add_argument("--name", required=True, help="output filename prefix (no spaces), e.g. anime_dance")
    ap.add_argument("--timeout", type=int, default=1800, help="max seconds to wait for the job")
    args = ap.parse_args()

    if args.length % 17 != 5:
        print(
            f"[generate_video] warning: length={args.length} does not satisfy n%17==5; "
            "ComfyUI/MiniMax H3 will round it up internally.",
            file=sys.stderr,
        )

    ensure_server()
    workflow = build_workflow(args.prompt, args.width, args.height, args.length, args.steps, args.seed, args.name)
    out_path = wait_for_result(workflow, args.name, timeout_s=args.timeout)
    print(f"OUTPUT:{out_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[generate_video] ERROR: {e}", file=sys.stderr)
        sys.exit(1)
