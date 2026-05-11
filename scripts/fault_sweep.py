#!/usr/bin/env python3
import argparse
import subprocess


TOP = "tb_fault_compare"
HEX = "fault_campaign.boot.hex"


FAULTS = {
    "pc": 1,
    "state": 2,
    "regfile": 3,
    "pc_hard": 6,
    "state_hard": 7,
    "regfile_hard": 8,
}


def run_once(fault_kind: int, cycle: int) -> tuple[str, str]:
    cmd = [
        "ghdl",
        "-r",
        "--std=08",
        TOP,
        f"-gG_PROGRAM_FILE={HEX}",
        f"-gG_FAULT_KIND={fault_kind}",
        f"-gG_INJECT_AFTER_BOOT_CYCLES={cycle}",
        "-gG_PC_TMR=false",
        "-gG_STATE_TMR=false",
        "-gG_RF_TMR=false",
        "-gG_RF_SELF_HEAL=false",
        "-gG_IMEM_ECC=false",
        "-gG_DMEM_ECC=false",
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    output = (proc.stdout + proc.stderr).strip()
    verdict = "FAIL" if proc.returncode else "PASS"
    classification = "fail"
    for line in output.splitlines():
        if "RESULT PASS class=" in line:
            classification = line.split("RESULT PASS class=", 1)[1].split()[0].lower()
        elif "RESULT FAIL" in line:
            classification = "fail"
    return verdict, classification


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("fault", choices=FAULTS.keys())
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--stop", type=int, default=128)
    args = parser.parse_args()

    fault_kind = FAULTS[args.fault]
    print("cycle,result,class")
    for cycle in range(args.start, args.stop + 1):
        verdict, classification = run_once(fault_kind, cycle)
        print(f"{cycle},{verdict},{classification}")
        if verdict != "PASS" or classification != "masked":
            print(f"first_interesting_cycle={cycle}")
            return 0

    print("no_interesting_cycle_found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
