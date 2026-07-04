#!/usr/bin/env python3
"""
Render CPU and memory usage graphs from a Jenkins resource consumption CSV.
Produces two PNGs (cpu.png, memory.png) alongside the CSV.

CSV format: timestamp_utc,pod,cpu_percent,memory_mib

Usage: python3 render_graph.py <results_csv>
"""

import csv
import sys
from datetime import datetime
from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.dates as mdates


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 render_graph.py <results_csv>", file=sys.stderr)
        sys.exit(1)

    csv_path = Path(sys.argv[1])
    out_dir = csv_path.parent

    timestamps, cpu_series, mem_series = [], [], []

    with csv_path.open() as f:
        for row in csv.DictReader(f):
            try:
                ts  = datetime.fromisoformat(row["timestamp_utc"].replace("Z", "+00:00"))
                cpu = float(row["cpu_percent"])
                mem = float(row["memory_mib"])
            except (ValueError, KeyError):
                continue
            timestamps.append(ts)
            cpu_series.append(cpu)
            mem_series.append(mem)

    if not timestamps:
        print("[ERROR] No data found in CSV.", file=sys.stderr)
        sys.exit(1)

    title_base = csv_path.stem

    def make_chart(series, ylabel, filename, unit=""):
        fig, ax = plt.subplots(figsize=(14, 5))
        fig.suptitle(f"{ylabel} — {title_base}", fontsize=13)
        ax.plot(timestamps, series, color="#2a78d6", linewidth=1.5)
        ax.set_ylabel(f"{ylabel}{' (' + unit + ')' if unit else ''}")
        ax.set_xlabel("Time (UTC)")
        ax.grid(True, alpha=0.3)
        ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
        fig.autofmt_xdate()
        plt.tight_layout()
        out = out_dir / filename
        plt.savefig(out, dpi=150)
        plt.close(fig)
        print(f"[INFO] Graph saved to {out}")

    make_chart(cpu_series, "CPU Usage", "cpu.png", "%")
    make_chart(mem_series, "Memory Usage", "memory.png", "MiB")


if __name__ == "__main__":
    main()
