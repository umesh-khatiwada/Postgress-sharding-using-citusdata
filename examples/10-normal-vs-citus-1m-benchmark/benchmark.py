#!/usr/bin/env python3
"""
==============================================================================
Example 10: Normal PostgreSQL vs Citus Distributed PostgreSQL
1,000,000 Rows Comparative Benchmark Runner
==============================================================================
Benchmarks data ingestion throughput, shard distribution, and analytical
query performance across single-node PostgreSQL vs distributed Citus.
"""

import argparse
import json
import re
import statistics
import subprocess
import sys
import time

# Terminal color styling
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
MAGENTA = "\033[35m"
BOLD = "\033[1m"
RESET = "\033[0m"

QUERIES = [
    {
        "id": "Q1",
        "name": "Full Table Aggregation",
        "desc": "COUNT(*), SUM, AVG, MIN, MAX over 1M rows",
        "normal_sql": "SELECT count(*), round(sum(amount), 2), round(avg(amount), 2), min(amount), max(amount) FROM normal_transactions;",
        "citus_sql":  "SELECT count(*), round(sum(amount), 2), round(avg(amount), 2), min(amount), max(amount) FROM citus_transactions;",
    },
    {
        "id": "Q2",
        "name": "Grouped Dimension Aggregation",
        "desc": "GROUP BY transaction_type, status with SUM and AVG",
        "normal_sql": "SELECT transaction_type, status, count(*), round(sum(amount), 2), round(avg(amount), 2) FROM normal_transactions GROUP BY transaction_type, status ORDER BY round(sum(amount), 2) DESC;",
        "citus_sql":  "SELECT transaction_type, status, count(*), round(sum(amount), 2), round(avg(amount), 2) FROM citus_transactions GROUP BY transaction_type, status ORDER BY round(sum(amount), 2) DESC;",
    },
    {
        "id": "Q3",
        "name": "High-Cardinality Filtered Agg",
        "desc": "WHERE status='SUCCESS' AND date filter, GROUP BY 1k merchants",
        "normal_sql": "SELECT merchant_id, count(*), round(sum(amount), 2) FROM normal_transactions WHERE status = 'SUCCESS' AND created_at >= TIMESTAMP '2026-03-01 00:00:00Z' GROUP BY merchant_id ORDER BY round(sum(amount), 2) DESC LIMIT 10;",
        "citus_sql":  "SELECT merchant_id, count(*), round(sum(amount), 2) FROM citus_transactions WHERE status = 'SUCCESS' AND created_at >= TIMESTAMP '2026-03-01 00:00:00Z' GROUP BY merchant_id ORDER BY round(sum(amount), 2) DESC LIMIT 10;",
    },
    {
        "id": "Q4",
        "name": "Distributed Reference Table Join",
        "desc": "Zero-shuffle join between transactions & merchants reference table",
        "normal_sql": "SELECT m.category, count(t.transaction_id), round(sum(t.amount), 2), round(avg(t.amount), 2) FROM normal_transactions t JOIN merchants m ON t.merchant_id = m.merchant_id WHERE t.status = 'SUCCESS' GROUP BY m.category ORDER BY round(sum(t.amount), 2) DESC;",
        "citus_sql":  "SELECT m.category, count(t.transaction_id), round(sum(t.amount), 2), round(avg(t.amount), 2) FROM citus_transactions t JOIN merchants m ON t.merchant_id = m.merchant_id WHERE t.status = 'SUCCESS' GROUP BY m.category ORDER BY round(sum(t.amount), 2) DESC;",
    },
    {
        "id": "Q5",
        "name": "Point Router Query (Tenant Lookup)",
        "desc": "WHERE account_id = 4250 (Router planner targeted shard lookup)",
        "normal_sql": "SELECT transaction_id, account_id, created_at, amount, transaction_type, status FROM normal_transactions WHERE account_id = 4250 ORDER BY created_at DESC LIMIT 10;",
        "citus_sql":  "SELECT transaction_id, account_id, created_at, amount, transaction_type, status FROM citus_transactions WHERE account_id = 4250 ORDER BY created_at DESC LIMIT 10;",
    },
    {
        "id": "Q6",
        "name": "Distinct Count & Time Buckets",
        "desc": "Monthly volume with COUNT(DISTINCT account_id)",
        "normal_sql": "SELECT date_trunc('month', created_at) AS tx_month, count(DISTINCT account_id), count(*), round(sum(amount), 2) FROM normal_transactions GROUP BY date_trunc('month', created_at) ORDER BY tx_month;",
        "citus_sql":  "SELECT date_trunc('month', created_at) AS tx_month, count(DISTINCT account_id), count(*), round(sum(amount), 2) FROM citus_transactions GROUP BY date_trunc('month', created_at) ORDER BY tx_month;",
    },
    {
        "id": "Q7",
        "name": "Multi-Condition Analytical Scan",
        "desc": "Cross-border spend by country and type for amount > $700",
        "normal_sql": "SELECT m.country, t.transaction_type, count(*), round(sum(t.amount), 2), round(max(t.amount), 2) FROM normal_transactions t JOIN merchants m ON t.merchant_id = m.merchant_id WHERE t.amount > 700.00 AND t.status IN ('SUCCESS', 'PENDING') GROUP BY m.country, t.transaction_type ORDER BY round(sum(t.amount), 2) DESC LIMIT 10;",
        "citus_sql":  "SELECT m.country, t.transaction_type, count(*), round(sum(t.amount), 2), round(max(t.amount), 2) FROM citus_transactions t JOIN merchants m ON t.merchant_id = m.merchant_id WHERE t.amount > 700.00 AND t.status IN ('SUCCESS', 'PENDING') GROUP BY m.country, t.transaction_type ORDER BY round(sum(t.amount), 2) DESC LIMIT 10;",
    },
    {
        "id": "Q8",
        "name": "Statistical Percentiles",
        "desc": "Continuous percentiles: Median, P95, and P99 amount",
        "normal_sql": "SELECT round(percentile_cont(0.50) WITHIN GROUP (ORDER BY amount)::numeric, 2), round(percentile_cont(0.95) WITHIN GROUP (ORDER BY amount)::numeric, 2), round(percentile_cont(0.99) WITHIN GROUP (ORDER BY amount)::numeric, 2) FROM normal_transactions WHERE created_at >= TIMESTAMP '2026-03-01 00:00:00Z';",
        "citus_sql":  "SELECT round(percentile_cont(0.50) WITHIN GROUP (ORDER BY amount)::numeric, 2), round(percentile_cont(0.95) WITHIN GROUP (ORDER BY amount)::numeric, 2), round(percentile_cont(0.99) WITHIN GROUP (ORDER BY amount)::numeric, 2) FROM citus_transactions WHERE created_at >= TIMESTAMP '2026-03-01 00:00:00Z';",
    },
]

def exec_psql(container: str, sql: str, parse_time: bool = True):
    """Executes SQL via docker exec psql, capturing execution time in milliseconds."""
    cmd = [
        "docker", "exec", container,
        "psql", "-U", "postgres", "-d", "postgres",
        "-c", "\\timing on",
        "-c", sql
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"PSQL Error ({container}): {proc.stderr.strip()}")
    
    if not parse_time:
        return proc.stdout.strip(), 0.0

    match = re.search(r"Time:\s+([0-9.]+)\s+ms", proc.stdout)
    if match:
        return proc.stdout.strip(), float(match.group(1))
    
    # Check for minutes format: Time: 1392.198 ms (00:01.392)
    match_sec = re.search(r"Time:\s+([0-9.]+)\s+ms\s+\([0-9:]+\)", proc.stdout)
    if match_sec:
        return proc.stdout.strip(), float(match_sec.group(1))
    
    return proc.stdout.strip(), 0.0

def get_row_count():
    """Gets total row count from normal_transactions."""
    try:
        out, _ = exec_psql("citus_coordinator", "SELECT count(*) FROM normal_transactions;", parse_time=False)
        m = re.search(r"(\d+)\s*\n+\(1 row\)", out)
        if m:
            return int(m.group(1))
    except Exception:
        pass
    return 1000000

def get_shard_distribution():
    """Queries Citus coordinator for shard placement across worker nodes."""
    sql = """
    SELECT 
        shardid,
        nodename,
        nodeport,
        pg_size_pretty(shard_size) AS size
    FROM citus_shards
    WHERE table_name::text = 'citus_transactions'
    ORDER BY shardid;
    """
    out, _ = exec_psql("citus_coordinator", sql, parse_time=False)
    return out

def get_table_sizes():
    """Returns size of normal table and total distributed size of citus table."""
    sql = """
    SELECT
        pg_size_pretty(pg_total_relation_size('normal_transactions')) AS normal_size,
        pg_size_pretty(citus_total_relation_size('citus_transactions')) AS citus_size;
    """
    out, _ = exec_psql("citus_coordinator", sql, parse_time=False)
    return out

def run_benchmark(iterations: int):
    row_count = get_row_count()
    scale_label = f"{row_count / 1_000_000:.1f}M".replace(".0M", "M") if row_count >= 1_000_000 else f"{row_count:,}"

    print(f"\n{BOLD}{CYAN}================================================================================{RESET}")
    print(f"{BOLD}{CYAN} CITUS vs NORMAL POSTGRESQL {row_count:,} ROWS ({scale_label}) BENCHMARK SUITE{RESET}")
    print(f"{BOLD}{CYAN}================================================================================{RESET}")
    print(f"Iterations per query: {BOLD}{iterations}{RESET} (warm cache)\n")

    # 1. Print Shard Distribution
    print(f"{BOLD}{YELLOW}--> Citus Shard Topology & Placement:{RESET}")
    print(get_shard_distribution())
    print()

    # 2. Print Storage Footprint
    print(f"{BOLD}{YELLOW}--> Storage Footprint (Heap + Indexes):{RESET}")
    print(get_table_sizes())
    print()

    # 3. Benchmark Queries
    print(f"{BOLD}{YELLOW}--> Executing Analytical Benchmark Queries...{RESET}\n")

    results = []

    for q in QUERIES:
        q_id = q["id"]
        q_name = q["name"]
        print(f"[{BOLD}{q_id}{RESET}] {BOLD}{q_name}{RESET} ({q['desc']})")
        
        # Warm-up run
        exec_psql("citus_coordinator", q["normal_sql"])
        exec_psql("citus_coordinator", q["citus_sql"])

        normal_times = []
        citus_times = []

        for _ in range(iterations):
            _, t_norm = exec_psql("citus_coordinator", q["normal_sql"])
            _, t_citus = exec_psql("citus_coordinator", q["citus_sql"])
            normal_times.append(t_norm)
            citus_times.append(t_citus)

        med_norm = statistics.median(normal_times)
        med_citus = statistics.median(citus_times)
        
        # Speedup factor
        if med_citus > 0:
            speedup = med_norm / med_citus
        else:
            speedup = 1.0

        results.append({
            "id": q_id,
            "name": q_name,
            "normal_ms": med_norm,
            "citus_ms": med_citus,
            "speedup": speedup
        })

        print(f"    Normal PG : {med_norm:8.2f} ms")
        print(f"    Citus PG  : {med_citus:8.2f} ms   ==> Speedup: {BOLD}{GREEN if speedup >= 1.0 else YELLOW}{speedup:.2f}x{RESET}\n")

    # 4. Summary Table
    print(f"\n{BOLD}{CYAN}================================================================================{RESET}")
    print(f"{BOLD}{CYAN} BENCHMARK SUMMARY (Median Latencies across {iterations} Runs){RESET}")
    print(f"{BOLD}{CYAN}================================================================================{RESET}")
    header = f"{'Query ID':<10} | {'Query Archetype':<32} | {'Normal PG':<12} | {'Citus PG':<12} | {'Speedup'}"
    print(f"{BOLD}{header}{RESET}")
    print("-" * 80)

    for r in results:
        speedup_str = f"{r['speedup']:.2f}x"
        color = GREEN if r['speedup'] >= 1.05 else (YELLOW if r['speedup'] >= 0.95 else RESET)
        print(f"{r['id']:<10} | {r['name']:<32} | {r['normal_ms']:8.2f} ms  | {r['citus_ms']:8.2f} ms  | {color}{speedup_str}{RESET}")

    print("-" * 80)
    print(f"\n{BOLD}{GREEN}Benchmark completed successfully.{RESET}\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Normal PostgreSQL vs Citus 1M Benchmark")
    parser.add_argument("--iterations", type=int, default=3, help="Number of iterations per query (default: 3)")
    args = parser.parse_args()

    run_benchmark(args.iterations)
