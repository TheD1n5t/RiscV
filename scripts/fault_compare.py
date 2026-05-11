#!/usr/bin/env python3
import subprocess
import sys


ROOT_HEX = "fault_campaign.boot.hex"
TOP = "tb_fault_compare"
WORKLOAD_PRESETS = {
    "default": ("fault_campaign.boot.hex", "D146879D"),
    "branch_fsm": ("branch_fsm_campaign.boot.hex", "DCC4D493"),
}


def run_case(
    name: str,
    workload_hex: str,
    expected_signature: str,
    toggles: dict[str, bool],
    fault_kind: int,
    inject_cycle: int,
) -> tuple[bool, str, str]:
    cmd = [
        "ghdl",
        "-r",
        "--std=08",
        TOP,
        f"-gG_PROGRAM_FILE={workload_hex}",
        f"-gG_EXPECTED_SIGNATURE_HEX={expected_signature}",
        f"-gG_FAULT_KIND={fault_kind}",
        f"-gG_INJECT_AFTER_BOOT_CYCLES={inject_cycle}",
        f"-gG_PC_TMR={'true' if toggles['pc'] else 'false'}",
        f"-gG_STATE_TMR={'true' if toggles['state'] else 'false'}",
        f"-gG_RF_TMR={'true' if toggles['rf'] else 'false'}",
        f"-gG_RF_SELF_HEAL={'true' if toggles['rf_heal'] else 'false'}",
        f"-gG_IMEM_ECC={'true' if toggles['imem'] else 'false'}",
        f"-gG_DMEM_ECC={'true' if toggles['dmem'] else 'false'}",
    ]

    proc = subprocess.run(cmd, capture_output=True, text=True)
    output = (proc.stdout + proc.stderr).strip()
    passed = proc.returncode == 0
    classification = "fail"
    for line in output.splitlines():
        if "RESULT PASS class=" in line:
            fragment = line.split("RESULT PASS class=", 1)[1]
            classification = fragment.split()[0].lower()
        elif "RESULT FAIL" in line:
            classification = "fail"
    return passed, output, classification


def main() -> int:
    workload_hex, expected_signature = WORKLOAD_PRESETS["default"]
    configs = {
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

    faults = [
        ("control", 0, 64),
        ("pc", 1, 64),
        ("state", 2, 64),
        ("regfile", 3, 64),
        ("imem", 4, 64),
        ("dmem", 5, 64),
        ("pc_hard", 6, 0),
        ("state_hard", 7, 3),
        ("regfile_hard", 8, 78),
    ]

    rows: list[tuple[str, str, str, str]] = []
    for cfg_name, toggles in configs.items():
        for fault_name, fault_kind, inject_cycle in faults:
            passed, output, classification = run_case(
                f"{cfg_name}:{fault_name}",
                workload_hex,
                expected_signature,
                toggles,
                fault_kind,
                inject_cycle,
            )
            verdict = "PASS" if passed else "FAIL"
            rows.append((cfg_name, fault_name, verdict, classification))
            print(f"[{cfg_name}/{fault_name}] {verdict} ({classification})")
            if output:
                tail = output.splitlines()[-1]
                print(f"  {tail}")

    print("\nSummary")
    print("variant          fault      result  class")
    print("------------------------------------------")
    for cfg_name, fault_name, verdict, classification in rows:
        print(f"{cfg_name:<16} {fault_name:<10} {verdict:<7} {classification}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
