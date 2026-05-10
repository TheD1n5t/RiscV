param(
  [int]$CampaignRuns = 20,
  [string]$VivadoBin = "C:\Xilinx\Vivado\2024.1\bin"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutDir = Join-Path $RepoRoot "fault_campaign_results"
$PrjFile = Join-Path $OutDir "fault_campaign_vhdl.prj"
$SummaryCsv = Join-Path $OutDir "summary.csv"
$SummaryByDomainCsv = Join-Path $OutDir "summary_by_domain.csv"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$sources = @(
  "RiscVTest.srcs/sources_1/new/alu.vhd",
  "RiscVTest.srcs/sources_1/new/fault_injector.vhd",
  "RiscVTest.srcs/sources_1/new/tmr_fault_voter.vhd",
  "RiscVTest.srcs/sources_1/new/decoder.vhd",
  "RiscVTest.srcs/sources_1/new/regfile.vhd",
  "RiscVTest.srcs/sources_1/new/csr_file.vhd",
  "RiscVTest.srcs/sources_1/new/load_store_unit.vhd",
  "RiscVTest.srcs/sources_1/new/cpu.vhd",
  "RiscVTest.srcs/sources_1/new/dmem.vhd",
  "RiscVTest.srcs/sources_1/new/imem_dp_ram.vhd",
  "RiscVTest.srcs/sources_1/new/uart_rx.vhd",
  "RiscVTest.srcs/sources_1/new/uart_tx.vhd",
  "RiscVTest.srcs/sources_1/new/simple_timer.vhd",
  "RiscVTest.srcs/sources_1/new/riscv_soc_boot.vhd",
  "RiscVTest.srcs/sim_1/new/tb_fault_campaign.vhd"
)

$projectLines = $sources | ForEach-Object {
  "vhdl work `"$((Join-Path $RepoRoot $_).Replace('\','/'))`""
}
$projectLines | Set-Content -Encoding ASCII -Path $PrjFile

$variants = @(
  @{
    Name = "baseline_fi"
    Generics = @{
      G_PC_TMR = "false"; G_STATE_TMR = "false"; G_RF_TMR = "false"; G_RF_SELF_HEAL = "false";
      G_IMEM_ECC = "false"; G_DMEM_ECC = "false"; G_FAULT_INJECT = "true"
    }
  },
  @{
    Name = "pc_state_fi"
    Generics = @{
      G_PC_TMR = "true"; G_STATE_TMR = "true"; G_RF_TMR = "false"; G_RF_SELF_HEAL = "false";
      G_IMEM_ECC = "false"; G_DMEM_ECC = "false"; G_FAULT_INJECT = "true"
    }
  },
  @{
    Name = "rf_tmr_fi"
    Generics = @{
      G_PC_TMR = "true"; G_STATE_TMR = "true"; G_RF_TMR = "true"; G_RF_SELF_HEAL = "false";
      G_IMEM_ECC = "false"; G_DMEM_ECC = "false"; G_FAULT_INJECT = "true"
    }
  },
  @{
    Name = "rf_self_heal_fi"
    Generics = @{
      G_PC_TMR = "true"; G_STATE_TMR = "true"; G_RF_TMR = "true"; G_RF_SELF_HEAL = "true";
      G_IMEM_ECC = "false"; G_DMEM_ECC = "false"; G_FAULT_INJECT = "true"
    }
  },
  @{
    Name = "mem_ecc_fi"
    Generics = @{
      G_PC_TMR = "true"; G_STATE_TMR = "true"; G_RF_TMR = "true"; G_RF_SELF_HEAL = "true";
      G_IMEM_ECC = "true"; G_DMEM_ECC = "true"; G_FAULT_INJECT = "true"
    }
  }
)

$workloads = @(
  @{
    Name = "regression13"
    Payload = (Join-Path $RepoRoot "hex_files\payload_big_regression.hex").Replace('\','/')
    Expected = (Join-Path $RepoRoot "hex_files\payload_big_regression.expected").Replace('\','/')
  },
  @{
    Name = "signature62"
    Payload = (Join-Path $RepoRoot "hex_files\payload_fault_campaign.hex").Replace('\','/')
    Expected = (Join-Path $RepoRoot "hex_files\payload_fault_campaign.expected").Replace('\','/')
  }
)

function Invoke-XilinxCommand {
  param(
    [string]$Command,
    [string]$LogPath
  )

  $cmd = "cd /d `"$RepoRoot`" && $Command"
  cmd.exe /c $cmd 2>&1 | Tee-Object -FilePath $LogPath
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE. See $LogPath"
  }
}

Push-Location $RepoRoot
try {
  Remove-Item -Force -ErrorAction SilentlyContinue "xsim.dir\work\*" | Out-Null

  Invoke-XilinxCommand `
    -Command "`"$VivadoBin\xvhdl.bat`" --incr --relax --2008 -prj `"$PrjFile`" -log `"$OutDir\xvhdl.log`"" `
    -LogPath (Join-Path $OutDir "compile_console.log")

  "workload,variant,total,injected,masked,corrected,uncorrectable,failures,timeouts,success,success_rate" |
    Set-Content -Encoding ASCII -Path $SummaryCsv
  "workload,variant,domain,injected,masked,corrected,uncorrectable,failures,timeouts,success,success_rate" |
    Set-Content -Encoding ASCII -Path $SummaryByDomainCsv

  foreach ($workload in $workloads) {
  foreach ($variant in $variants) {
    $workloadName = $workload.Name
    $name = $variant.Name
    $runName = "$workloadName`_$name"
    $snapshot = "tb_fault_campaign_$runName"
    $elabLog = Join-Path $OutDir "$runName`_elab.log"
    $simLog = Join-Path $OutDir "$runName`_sim.log"

    $genericArgs = @(
      "-generic_top `"CAMPAIGN_RUNS=$CampaignRuns`"",
      "-generic_top `"PAYLOAD_FILE=$($workload.Payload)`"",
      "-generic_top `"EXPECTED_FILE=$($workload.Expected)`""
    )
    foreach ($key in $variant.Generics.Keys) {
      $genericArgs += "-generic_top `"$key=$($variant.Generics[$key])`""
    }
    $genericText = $genericArgs -join " "

    Invoke-XilinxCommand `
      -Command "`"$VivadoBin\xelab.bat`" --debug typical --relax --mt 2 -L work -L secureip $genericText --snapshot $snapshot work.tb_fault_campaign -log `"$elabLog`"" `
      -LogPath (Join-Path $OutDir "$runName`_elab_console.log")

    Invoke-XilinxCommand `
      -Command "`"$VivadoBin\xsim.bat`" $snapshot --runall --log `"$simLog`"" `
      -LogPath (Join-Path $OutDir "$runName`_sim_console.log")

    $summary = Select-String -Path $simLog -Pattern "FAULT CAMPAIGN SUMMARY:" | Select-Object -Last 1
    if (-not $summary) {
      throw "No campaign summary found in $simLog"
    }

    $line = $summary.Line
    $values = @{}
    foreach ($field in @("total","injected","masked","corrected","uncorrectable","failures","timeouts")) {
      if ($line -match "$field=([0-9]+)") {
        $values[$field] = [int]$Matches[1]
      } else {
        $values[$field] = 0
      }
    }

    $referenceRuns = [Math]::Max($values.total - $values.injected, 0)
    $success = [Math]::Max([Math]::Min($values.masked + $values.corrected - $referenceRuns, $values.injected), 0)
    $successRate = if ($values.injected -gt 0) { [Math]::Round($success / $values.injected, 4) } else { 0 }
    "$workloadName,$name,$($values.total),$($values.injected),$($values.masked),$($values.corrected),$($values.uncorrectable),$($values.failures),$($values.timeouts),$success,$successRate" |
      Add-Content -Encoding ASCII -Path $SummaryCsv

    $runDomains = @{}
    foreach ($entry in Select-String -Path $simLog -Pattern "CAMPAIGN RUN ([0-9]+) domain=([^ ]+)") {
      if ($entry.Line -match "CAMPAIGN RUN ([0-9]+) domain=([^ ]+)") {
        $runId = [int]$Matches[1]
        $domain = $Matches[2].Trim()
        if ($domain -like "*-RND") {
          $domain = $domain.Substring(0, $domain.IndexOf("-"))
        }
        switch ($domain) {
          "ST" { $domain = "STATE" }
          "DM" { $domain = "DMEM" }
          "IM" { $domain = "IMEM" }
          default { }
        }
        $runDomains[$runId] = $domain
      }
    }

    $domainRows = @{}
    foreach ($domain in @("PC","STATE","RF","DMEM","IMEM","IMEM2")) {
      $domainRows[$domain] = @{
        injected = 0; masked = 0; corrected = 0; uncorrectable = 0; failures = 0; timeouts = 0
      }
    }

    foreach ($entry in Select-String -Path $simLog -Pattern "RUN ([0-9]+) outcome=([A-Z]+)") {
      if ($entry.Line -match "RUN ([0-9]+) outcome=([A-Z]+)") {
        $runId = [int]$Matches[1]
        $outcome = $Matches[2]
        if (-not $runDomains.ContainsKey($runId)) {
          continue
        }
        $domain = $runDomains[$runId]
        if ($domain -eq "REF") {
          continue
        }
        if (-not $domainRows.ContainsKey($domain)) {
          $domainRows[$domain] = @{
            injected = 0; masked = 0; corrected = 0; uncorrectable = 0; failures = 0; timeouts = 0
          }
        }

        $domainRows[$domain].injected += 1
        switch ($outcome) {
          "MASKED" { $domainRows[$domain].masked += 1 }
          "CORRECTED" { $domainRows[$domain].corrected += 1 }
          "UNCORRECTABLE" { $domainRows[$domain].uncorrectable += 1 }
          "FAILURE" { $domainRows[$domain].failures += 1 }
          "TIMEOUT" { $domainRows[$domain].timeouts += 1 }
          default { }
        }
      }
    }

    foreach ($domain in @("PC","STATE","RF","DMEM","IMEM","IMEM2")) {
      $row = $domainRows[$domain]
      if ($row.injected -eq 0) {
        continue
      }
      $domainSuccess = $row.masked + $row.corrected
      $domainSuccessRate = [Math]::Round($domainSuccess / $row.injected, 4)
      "$workloadName,$name,$domain,$($row.injected),$($row.masked),$($row.corrected),$($row.uncorrectable),$($row.failures),$($row.timeouts),$domainSuccess,$domainSuccessRate" |
        Add-Content -Encoding ASCII -Path $SummaryByDomainCsv
    }
  }
  }
}
finally {
  Pop-Location
}

Write-Host "Fault-campaign summary written to $SummaryCsv"
Write-Host "Fault-campaign domain summary written to $SummaryByDomainCsv"
