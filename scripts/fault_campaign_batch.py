#!/usr/bin/env python3
import argparse
import csv
import random
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


TOP = "tb_fault_compare"
DEFAULT_HEX = "fault_campaign.boot.hex"
DEFAULT_OUT = Path("fault_campaign_results/current_campaign.csv")
WORKLOAD_PRESETS = {
    "default": {
        "hex": "fault_campaign.boot.hex",
        "signature": "D146879D",
    },
    "branch_fsm": {
        "hex": "branch_fsm_campaign.boot.hex",
        "signature": "DCC4D493",
    },
}


VARIANTS = {
    "baseline": {
        "pc": False,
        "state": False,
        "rf": False,
        "rf_heal": False,
        "imem": False,
        "dmem": False,
    },
    "full_hardening": {
        "pc": True,
        "state": True,
        "rf": True,
        "rf_heal": True,
        "imem": True,
        "dmem": True,
    },
}


FAULT_PROFILES = {
    "control": {"kind": 0, "cycle_range": (64, 64)},
    "pc_soft": {"kind": 1, "cycle_range": (0, 128)},
    "state_soft": {"kind": 2, "cycle_range": (0, 128)},
    "regfile_soft": {"kind": 3, "cycle_range": (0, 128)},
    "imem_soft": {"kind": 4, "cycle_range": (0, 128)},
    "dmem_soft": {"kind": 5, "cycle_range": (0, 128)},
    "pc_hard": {"kind": 6, "cycle_range": (0, 32)},
    "state_hard": {"kind": 7, "cycle_range": (0, 32)},
    "regfile_hard": {"kind": 8, "cycle_range": (0, 128)},
}


def parse_result(output: str, returncode: int) -> tuple[str, str]:
    verdict = "FAIL" if returncode else "PASS"
    classification = "fail"
    for line in output.splitlines():
        if "RESULT PASS class=" in line:
            classification = line.split("RESULT PASS class=", 1)[1].split()[0].lower()
        elif "RESULT FAIL" in line:
            classification = "fail"
    return verdict, classification


def run_case(
    workload_hex: str,
    expected_signature: str,
    variant_name: str,
    toggles: dict[str, bool],
    fault_kind: int,
    cycle: int,
) -> tuple[str, str]:
    cmd = [
        "ghdl",
        "-r",
        "--std=08",
        TOP,
        f"-gG_PROGRAM_FILE={workload_hex}",
        f"-gG_EXPECTED_SIGNATURE_HEX={expected_signature}",
        f"-gG_FAULT_KIND={fault_kind}",
        f"-gG_INJECT_AFTER_BOOT_CYCLES={cycle}",
        f"-gG_PC_TMR={'true' if toggles['pc'] else 'false'}",
        f"-gG_STATE_TMR={'true' if toggles['state'] else 'false'}",
        f"-gG_RF_TMR={'true' if toggles['rf'] else 'false'}",
        f"-gG_RF_SELF_HEAL={'true' if toggles['rf_heal'] else 'false'}",
        f"-gG_IMEM_ECC={'true' if toggles['imem'] else 'false'}",
        f"-gG_DMEM_ECC={'true' if toggles['dmem'] else 'false'}",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    output = (proc.stdout + proc.stderr).strip()
    return parse_result(output, proc.returncode)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a larger FI campaign on the current fault-compare testbench.")
    parser.add_argument("--workload", default=None, help="Boot hex workload to run.")
    parser.add_argument("--workload-preset", default="default", choices=sorted(WORKLOAD_PRESETS.keys()))
    parser.add_argument("--expected-signature", default=None, help="Expected 32-bit hex signature without 0x prefix.")
    parser.add_argument("--variants", nargs="+", default=["baseline", "full_hardening"], choices=sorted(VARIANTS.keys()))
    parser.add_argument("--profiles", nargs="+", default=["pc_soft", "state_soft", "regfile_soft", "imem_soft", "dmem_soft", "pc_hard", "state_hard", "regfile_hard"], choices=sorted(FAULT_PROFILES.keys()))
    parser.add_argument("--runs", type=int, default=32, help="Runs per variant/profile.")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--output", default=str(DEFAULT_OUT))
    args = parser.parse_args()

    rng = random.Random(args.seed)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    preset = WORKLOAD_PRESETS[args.workload_preset]
    workload_hex = args.workload if args.workload is not None else preset["hex"]
    expected_signature = args.expected_signature if args.expected_signature is not None else preset["signature"]

    rows: list[dict[str, str | int]] = []
    summary: dict[tuple[str, str], Counter] = defaultdict(Counter)

    for variant_name in args.variants:
      toggles = VARIANTS[variant_name]
      for profile_name in args.profiles:
        profile = FAULT_PROFILES[profile_name]
        cycle_lo, cycle_hi = profile["cycle_range"]
        for run_idx in range(args.runs):
            cycle = rng.randint(cycle_lo, cycle_hi)
            verdict, classification = run_case(
                workload_hex, expected_signature, variant_name, toggles, profile["kind"], cycle
            )
            rows.append(
                {
                    "variant": variant_name,
                    "profile": profile_name,
                    "run": run_idx,
                    "cycle": cycle,
                    "fault_kind": profile["kind"],
                    "result": verdict,
                    "class": classification,
                }
            )
            summary[(variant_name, profile_name)][verdict] += 1
            summary[(variant_name, profile_name)][classification] += 1
            print(f"[{variant_name}/{profile_name}/{run_idx}] cycle={cycle} {verdict} ({classification})")

    with out_path.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["variant", "profile", "run", "cycle", "fault_kind", "result", "class"],
        )
        writer.writeheader()
        writer.writerows(rows)

    print("\nSummary")
    print(f"workload={workload_hex}")
    print(f"expected_signature={expected_signature}")
    print("variant          profile         runs  pass  fail  masked  corrected")
    print("--------------------------------------------------------------------")
    for variant_name in args.variants:
        for profile_name in args.profiles:
            counter = summary[(variant_name, profile_name)]
            runs = counter["PASS"] + counter["FAIL"]
            print(
                f"{variant_name:<16} {profile_name:<15} {runs:<5} "
                f"{counter['PASS']:<5} {counter['FAIL']:<5} "
                f"{counter['masked']:<7} {counter['corrected']}"
            )

    print(f"\nCSV written to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
