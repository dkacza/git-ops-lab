#!/usr/bin/env python3
"""
Render CPU and memory usage graphs from a resource consumption CSV.
Usage: python3 render_graph.py <results_csv>
"""

import csv
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.dates as mdates


def parse_cpu(value: str) -> float:
    if value.endswith("m"):
        return float(value[:-1])
    return float(value) * 1000


def parse_memory(value: str) -> float:
    if value.endswith("Mi"):
        return float(value[:-2])
    if value.endswith("Gi"):
        return float(value[:-2]) * 1024
    if value.endswith("Ki"):
        return float(value[:-2]) / 1024
    return float(value) / (1024 * 1024)


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python3 render_graph.py <results_csv>", file=sys.stderr)
        sys.exit(1)

    csv_path = Path(sys.argv[1])

    # pod → scenario → {timestamps, cpu, memory}
    data: dict = defaultdict(lambda: defaultdict(lambda: {"timestamps": [], "cpu": [], "memory": []}))

    with csv_path.open() as f:
        for row in csv.DictReader(f):
            try:
                ts = datetime.fromisoformat(row["timestamp_utc"].replace("Z", "+00:00"))
                cpu = parse_cpu(row["cpu_millicores"])
                mem = parse_memory(row["memory_mib"])
            except (ValueError, KeyError):
                continue
            data[row["pod"]][row["scenario"]]["timestamps"].append(ts)
            data[row["pod"]][row["scenario"]]["cpu"].append(cpu)
            data[row["pod"]][row["scenario"]]["memory"].append(mem)

    if not data:
        print("[ERROR] No data found in CSV.", file=sys.stderr)
        sys.exit(1)

    # Aggregate total CPU and memory across all pods per (scenario, timestamp)
    agg_by_ts: dict = defaultdict(lambda: defaultdict(lambda: {"cpu": 0.0, "memory": 0.0}))
    for pod, scenarios in data.items():
        for scenario, values in scenarios.items():
            for ts, cpu, mem in zip(values["timestamps"], values["cpu"], values["memory"]):
                agg_by_ts[scenario][ts]["cpu"] += cpu
                agg_by_ts[scenario][ts]["memory"] += mem

    agg: dict = {}
    for scenario, ts_data in agg_by_ts.items():
        sorted_ts = sorted(ts_data)
        agg[scenario] = {
            "timestamps": sorted_ts,
            "cpu": [ts_data[ts]["cpu"] for ts in sorted_ts],
            "memory": [ts_data[ts]["memory"] for ts in sorted_ts],
        }

    fig, (ax_cpu, ax_mem) = plt.subplots(2, 1, figsize=(14, 8), sharex=True)
    fig.suptitle(f"Argo CD Resource Consumption — {csv_path.stem}", fontsize=13)

    colors = plt.rcParams["axes.prop_cycle"].by_key()["color"]
    for i, (scenario, values) in enumerate(sorted(agg.items())):
        color = colors[i % len(colors)]
        ax_cpu.plot(values["timestamps"], values["cpu"],
                    label=scenario, color=color, linewidth=2, linestyle="-")
        ax_mem.plot(values["timestamps"], values["memory"],
                    label=scenario, color=color, linewidth=2, linestyle="-")

    ax_cpu.set_ylabel("CPU (millicores)")
    ax_cpu.legend(loc="upper right", fontsize=8)
    ax_cpu.grid(True, alpha=0.3)

    ax_mem.set_ylabel("Memory (MiB)")
    ax_mem.set_xlabel("Time (UTC)")
    ax_mem.legend(loc="upper right", fontsize=8)
    ax_mem.grid(True, alpha=0.3)
    ax_mem.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))

    fig.autofmt_xdate()
    plt.tight_layout()

    output_path = csv_path.with_suffix(".png")
    plt.savefig(output_path, dpi=150)
    print(f"[INFO] Graph saved to {output_path}")


if __name__ == "__main__":
    main()
