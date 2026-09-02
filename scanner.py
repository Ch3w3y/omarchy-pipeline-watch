#!/usr/bin/env python3
"""
scanner.py - Data Science Pipeline & Training Job Watcher
Scans running Python, R, Quarto, and DuckDB workloads, computes resource usage,
and tracks completed jobs with notifications.
"""

import sys
import os
import json
import time
import subprocess
import re
from pathlib import Path

STATE_DIR = Path.home() / ".local" / "state" / "omarchy"
TRACKING_FILE = STATE_DIR / "pipeline-tracking.json"
HISTORY_FILE = STATE_DIR / "pipeline-history.json"

def format_bytes(kb_val):
    bytes_val = kb_val * 1024
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_val < 1024.0:
            return f"{bytes_val:.1f} {unit}" if unit != 'B' else f"{bytes_val} B"
        bytes_val /= 1024.0
    return f"{bytes_val:.1f} PB"

def is_ds_process(comm, args_str):
    """Determines if a process is a data science script/job and extracts a clean display name and type."""
    args_lower = args_str.lower()
    comm_lower = comm.lower()
    
    # Exclude system/agent daemons, games, and omarchy plugins
    exclusions = [
        "antigravity", "gemini", "scanner.py", "backend.py", "transform.py", 
        "omarchy-shell", "quickshell", "proton", "steam", "lutris", 
        ".config/omarchy", "display-ctl", "wallpaper-gallery"
    ]
    if any(k in args_lower for k in exclusions):
        return False, None, None

    # Quarto
    if "quarto" in comm_lower or "quarto" in args_lower:
        m = re.search(r'([a-zA-Z0-9_\-\.]+\.(?:qmd|ipynb|rmd))', args_str, re.IGNORECASE)
        name = m.group(1) if m else "Quarto Pipeline"
        return True, name, "quarto"

    # R / Rscript
    if "rscript" in comm_lower or comm_lower == "r" or "exec/r" in comm_lower or "r.bin" in comm_lower:
        m = re.search(r'([a-zA-Z0-9_\-\./]+\.[rR])', args_str)
        if m:
            name = Path(m.group(1)).name
            return True, name, "r"
        if "targets" in args_lower or "tar_make" in args_lower:
            return True, "targets::tar_make()", "r"
        if "ark" in args_lower or "positron" in args_lower:
            return True, "Positron R Kernel", "kernel"
        return True, "R Process", "r"

    # Python / Python3 / IPython
    if "python" in comm_lower or "ipython" in comm_lower:
        m = re.search(r'([a-zA-Z0-9_\-\./]+\.py)', args_str)
        if m:
            name = Path(m.group(1)).name
            return True, name, "python"
        if "ipykernel" in args_lower or "ark" in args_lower:
            return True, "Positron/Jupyter Kernel", "kernel"
        if "jupyter" in args_lower:
            return True, "Jupyter Server", "kernel"
        if any(k in args_lower for k in ["torch", "xgboost", "train", "fit", "polars", "duckdb", "pandas", "sklearn"]):
            return True, "Python ML/Data Job", "python"
        if not any(k in args_lower for k in ["/usr/lib", "/site-packages", "systemd", "xdg", "gnome"]):
            return True, "Python Script", "python"

    # DuckDB CLI
    if "duckdb" in comm_lower:
        m = re.search(r'([a-zA-Z0-9_\-\./]+\.(?:duckdb|parquet|csv|sql))', args_str)
        name = Path(m.group(1)).name if m else "DuckDB Query"
        return True, f"DuckDB ({name})", "duckdb"

    return False, None, None

def get_current_jobs():
    """Scans running processes and returns matching data science jobs."""
    cmd = ["ps", "-eo", "pid,user,%cpu,%mem,rss,etime,comm,args", "--sort=-%cpu"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        if res.returncode != 0:
            return []
    except Exception:
        return []

    lines = res.stdout.strip().split('\n')
    if len(lines) <= 1:
        return []

    jobs = []
    for line in lines[1:]:
        parts = line.strip().split(None, 7)
        if len(parts) < 8:
            continue
        pid_str, user, cpu_str, mem_str, rss_str, etime_str, comm, args_str = parts
        
        is_ds, display_name, job_type = is_ds_process(comm, args_str)
        if is_ds:
            try:
                pid = int(pid_str)
                cpu = float(cpu_str)
                rss_kb = int(rss_str)
            except ValueError:
                continue

            jobs.append({
                "pid": pid,
                "user": user,
                "name": display_name,
                "type": job_type,
                "cpu": cpu,
                "rss_kb": rss_kb,
                "memory": format_bytes(rss_kb),
                "runtime": etime_str,
                "cmd": args_str[:120]
            })
    return jobs

def load_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default

def save_json(path, data):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2))
    except Exception:
        pass

def send_notification(title, message, urgency="normal"):
    try:
        subprocess.run(["notify-send", "-a", "Omarchy Pipeline Watch", "-u", urgency, title, message], timeout=2)
    except Exception:
        pass

def update_tracking_and_history(current_jobs):
    tracked = load_json(TRACKING_FILE, {})
    history = load_json(HISTORY_FILE, [])
    now = time.time()

    current_pids = {j["pid"]: j for j in current_jobs}
    
    # Check for finished jobs
    for pid_str, info in list(tracked.items()):
        pid = int(pid_str)
        if pid not in current_pids:
            start_time = info.get("start_time", now)
            duration_sec = int(now - start_time)
            mins, secs = divmod(duration_sec, 60)
            dur_str = f"{mins}m {secs}s" if mins > 0 else f"{secs}s"
            
            job_name = info.get("name", "Data Job")
            peak_ram = format_bytes(info.get("peak_rss_kb", 0))
            
            if duration_sec >= 4:
                send_notification(
                    f"✓ Pipeline Finished: {job_name}",
                    f"Completed in {dur_str} • Peak RAM: {peak_ram}"
                )
            
            history.insert(0, {
                "name": job_name,
                "type": info.get("type", "script"),
                "duration": dur_str,
                "peakMemory": peak_ram,
                "completedAt": time.strftime("%H:%M:%S"),
                "status": "completed"
            })
            del tracked[pid_str]

    # Update or add current jobs in tracking
    for j in current_jobs:
        pid_str = str(j["pid"])
        if pid_str not in tracked:
            tracked[pid_str] = {
                "name": j["name"],
                "type": j["type"],
                "start_time": now,
                "peak_rss_kb": j["rss_kb"]
            }
        else:
            if j["rss_kb"] > tracked[pid_str].get("peak_rss_kb", 0):
                tracked[pid_str]["peak_rss_kb"] = j["rss_kb"]

    history = history[:20]
    save_json(TRACKING_FILE, tracked)
    save_json(HISTORY_FILE, history)
    
    return history

def kill_process(pid):
    # os.kill() reads non-positive pids as broadcasts, not as a process: 0 hits
    # the whole process group and -1 hits every process this user is allowed to
    # signal. Either one takes the session down, so only a real pid gets through.
    try:
        target = int(pid)
    except (TypeError, ValueError):
        return {"error": f"Invalid PID: {pid}"}
    if target <= 0:
        return {"error": f"Refusing to signal PID {target}"}
    try:
        os.kill(target, 9)
        return {"status": "ok", "message": f"Killed PID {target}"}
    except Exception as e:
        return {"error": str(e)}

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--kill":
        pid = sys.argv[2] if len(sys.argv) > 2 else ""
        print(json.dumps(kill_process(pid)))
        sys.exit(0)

    current_jobs = get_current_jobs()
    history = update_tracking_and_history(current_jobs)

    total_cpu = sum(j["cpu"] for j in current_jobs)
    total_rss_kb = sum(j["rss_kb"] for j in current_jobs)

    output = {
        "activeCount": len(current_jobs),
        "totalCpu": round(total_cpu, 1),
        "totalMemory": format_bytes(total_rss_kb),
        "jobs": current_jobs,
        "history": history
    }
    print(json.dumps(output, indent=2))

if __name__ == "__main__":
    main()
