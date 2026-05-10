$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$HexOut = Join-Path $RepoRoot "hex_files\payload_fault_campaign.hex"
$ExpectedOut = Join-Path $RepoRoot "hex_files\payload_fault_campaign.expected"

$script:Words = New-Object 'System.Collections.Generic.List[UInt32]'
$script:Expected = New-Object 'System.Collections.Generic.List[Object]'
$script:Labels = @{}
$script:Fixups = New-Object 'System.Collections.Generic.List[Object]'
$script:Reg = New-Object UInt64[] 32
$script:Mem = @{}

function U32([Int64]$Value) {
  return [UInt32]($Value -band 0xffffffffL)
}

function Emit([UInt32]$Word) {
  $script:Words.Add($Word) | Out-Null
}

function Pc {
  return [int]($script:Words.Count * 4)
}

function Set-Label([string]$Name) {
  $script:Labels[$Name] = Pc
}

function I-Type([int]$Imm, [int]$Rs1, [int]$Funct3, [int]$Rd, [int]$Opcode) {
  $imm12 = $Imm -band 0xfff
  return U32(($imm12 -shl 20) -bor ($Rs1 -shl 15) -bor ($Funct3 -shl 12) -bor ($Rd -shl 7) -bor $Opcode)
}

function R-Type([int]$Funct7, [int]$Rs2, [int]$Rs1, [int]$Funct3, [int]$Rd) {
  return U32(($Funct7 -shl 25) -bor ($Rs2 -shl 20) -bor ($Rs1 -shl 15) -bor ($Funct3 -shl 12) -bor ($Rd -shl 7) -bor 0x33)
}

function S-Type([int]$Imm, [int]$Rs2, [int]$Rs1) {
  $imm12 = $Imm -band 0xfff
  return U32((($imm12 -shr 5) -shl 25) -bor ($Rs2 -shl 20) -bor ($Rs1 -shl 15) -bor (2 -shl 12) -bor (($imm12 -band 0x1f) -shl 7) -bor 0x23)
}

function B-Type([int]$Offset, [int]$Rs2, [int]$Rs1, [int]$Funct3) {
  $imm = $Offset -band 0x1fff
  return U32((($imm -shr 12) -band 1) -shl 31 `
    -bor ((($imm -shr 5) -band 0x3f) -shl 25) `
    -bor ($Rs2 -shl 20) `
    -bor ($Rs1 -shl 15) `
    -bor ($Funct3 -shl 12) `
    -bor ((($imm -shr 1) -band 0xf) -shl 8) `
    -bor ((($imm -shr 11) -band 1) -shl 7) `
    -bor 0x63)
}

function U-Type([UInt32]$Imm20, [int]$Rd) {
  return U32(($Imm20 -shl 12) -bor ($Rd -shl 7) -bor 0x37)
}

function J-Type([int]$Offset, [int]$Rd) {
  $imm = $Offset -band 0x1fffff
  return U32((($imm -shr 20) -band 1) -shl 31 `
    -bor ((($imm -shr 1) -band 0x3ff) -shl 21) `
    -bor ((($imm -shr 11) -band 1) -shl 20) `
    -bor ((($imm -shr 12) -band 0xff) -shl 12) `
    -bor ($Rd -shl 7) `
    -bor 0x6f)
}

function Add-Fixup([string]$Kind, [string]$Label, [int]$Rd, [int]$Rs1, [int]$Rs2, [int]$Funct3) {
  $script:Fixups.Add([pscustomobject]@{
    Index = $script:Words.Count
    Kind = $Kind
    Label = $Label
    Rd = $Rd
    Rs1 = $Rs1
    Rs2 = $Rs2
    Funct3 = $Funct3
  }) | Out-Null
  Emit 0
}

function Li([int]$Rd, [UInt32]$Value) {
  $signed = if ($Value -ge 0x80000000) { [Int64]$Value - 0x100000000L } else { [Int64]$Value }
  if ($signed -ge -2048 -and $signed -le 2047) {
    Emit (I-Type $signed 0 0 $Rd 0x13)
  } else {
    $hi = [UInt32]((([UInt64]$Value + 0x800) -shr 12) -band 0xfffff)
    $lo = [Int64]$Value - ([Int64]$hi -shl 12)
    if ($lo -ge 2048) { $lo -= 4096 }
    Emit (U-Type $hi $Rd)
    if ($lo -ne 0) {
      Emit (I-Type ([int]$lo) $Rd 0 $Rd 0x13)
    }
  }
  if ($Rd -ne 0) { $script:Reg[$Rd] = [UInt64]$Value }
}

function Addi([int]$Rd, [int]$Rs1, [int]$Imm) {
  Emit (I-Type $Imm $Rs1 0 $Rd 0x13)
  if ($Rd -ne 0) { $script:Reg[$Rd] = [UInt64](U32([Int64]$script:Reg[$Rs1] + $Imm)) }
}

function Lw([int]$Rd, [int]$Offset, [int]$Rs1) {
  Emit (I-Type $Offset $Rs1 2 $Rd 0x03)
  $addr = U32([Int64]$script:Reg[$Rs1] + $Offset)
  if ($Rd -ne 0) {
    if ($script:Mem.ContainsKey($addr)) {
      $script:Reg[$Rd] = [UInt64]$script:Mem[$addr]
    } else {
      $script:Reg[$Rd] = 0
    }
  }
}

function Sw([int]$Rs2, [int]$Offset, [int]$Rs1) {
  Emit (S-Type $Offset $Rs2 $Rs1)
  $addr = U32([Int64]$script:Reg[$Rs1] + $Offset)
  $data = U32([Int64]$script:Reg[$Rs2])
  $script:Mem[$addr] = $data
  $script:Expected.Add([pscustomobject]@{ Addr = $addr; Data = $data }) | Out-Null
}

function SwNoExpect([int]$Rs2, [int]$Offset, [int]$Rs1) {
  Emit (S-Type $Offset $Rs2 $Rs1)
}

function Op([string]$Name, [int]$Rd, [int]$Rs1, [int]$Rs2) {
  switch ($Name) {
    "add"  { $funct7 = 0x00; $funct3 = 0x0; $val = [Int64]$script:Reg[$Rs1] + [Int64]$script:Reg[$Rs2] }
    "sub"  { $funct7 = 0x20; $funct3 = 0x0; $val = [Int64]$script:Reg[$Rs1] - [Int64]$script:Reg[$Rs2] }
    "xor"  { $funct7 = 0x00; $funct3 = 0x4; $val = [Int64]($script:Reg[$Rs1] -bxor $script:Reg[$Rs2]) }
    "or"   { $funct7 = 0x00; $funct3 = 0x6; $val = [Int64]($script:Reg[$Rs1] -bor $script:Reg[$Rs2]) }
    "and"  { $funct7 = 0x00; $funct3 = 0x7; $val = [Int64]($script:Reg[$Rs1] -band $script:Reg[$Rs2]) }
    "sltu" { $funct7 = 0x00; $funct3 = 0x3; $val = if ($script:Reg[$Rs1] -lt $script:Reg[$Rs2]) { 1 } else { 0 } }
    "mul"  { $funct7 = 0x01; $funct3 = 0x0; $val = [Int64]$script:Reg[$Rs1] * [Int64]$script:Reg[$Rs2] }
  }
  Emit (R-Type $funct7 $Rs2 $Rs1 $funct3 $Rd)
  if ($Rd -ne 0) { $script:Reg[$Rd] = [UInt64](U32 $val) }
}

function Slli([int]$Rd, [int]$Rs1, [int]$Shamt) {
  Emit (I-Type $Shamt $Rs1 1 $Rd 0x13)
  if ($Rd -ne 0) { $script:Reg[$Rd] = [UInt64](U32([Int64]$script:Reg[$Rs1] -shl $Shamt)) }
}

function Srli([int]$Rd, [int]$Rs1, [int]$Shamt) {
  Emit (I-Type $Shamt $Rs1 5 $Rd 0x13)
  if ($Rd -ne 0) { $script:Reg[$Rd] = [UInt64](U32([Int64]$script:Reg[$Rs1] -shr $Shamt)) }
}

Li 1 0

$Seeds = @(
  0x10203040, 0x89abcdef, 0x0f0f0f0f, 0x33333333, 0x5555aaaa,
  0x80000001, 0x7fffffff, 0x13572468, 0x24681357, 0xdeadbeef,
  0xcafebabe, 0x00010001, 0x00ff00ff, 0xff00ff00, 0xa5a5a5a5,
  0x5a5a5a5a, 0x00000011, 0x00000022, 0x00000044, 0x00000088,
  0x01010101, 0x02020202, 0x04040404, 0x08080808, 0x11111111,
  0x22222222, 0x44444444
)

for ($i = 0; $i -lt $Seeds.Count; $i++) {
  $rd = 5 + $i
  Li $rd (U32 $Seeds[$i])
  Sw $rd ($i * 4) 1
}

$Ops = @("add", "sub", "xor", "or", "and", "sltu", "mul")
for ($i = 0; $i -lt 32; $i++) {
  $a = ($i * 3) % $Seeds.Count
  $b = ($i * 5 + 7) % $Seeds.Count
  Lw 10 ($a * 4) 1
  Lw 11 ($b * 4) 1
  Op $Ops[$i % $Ops.Count] 12 10 11
  if (($i % 4) -eq 1) {
    Slli 12 12 (($i % 5) + 1)
  } elseif (($i % 4) -eq 2) {
    Srli 12 12 (($i % 7) + 1)
  }
  Sw 12 (0x80 + $i * 4) 1
}

Li 20 36
Sw 20 0x100 1

Li 22 0x600d0000
Li 23 0x0000600d
Op "add" 24 22 23
Sw 24 0x104 1

Li 25 0x13579bdf
Sw 25 0x108 1

Set-Label "done"
Add-Fixup "jal" "done" 0 0 0 0

foreach ($fixup in $script:Fixups) {
  $offset = [int]$script:Labels[$fixup.Label] - [int]($fixup.Index * 4)
  if ($fixup.Kind -eq "branch") {
    $script:Words[$fixup.Index] = B-Type $offset $fixup.Rs2 $fixup.Rs1 $fixup.Funct3
  } else {
    $script:Words[$fixup.Index] = J-Type $offset $fixup.Rd
  }
}

$hexLines = New-Object 'System.Collections.Generic.List[String]'
foreach ($word in $script:Words) {
  foreach ($shift in @(0, 8, 16, 24)) {
    $hexLines.Add(("{0:X2}" -f (($word -shr $shift) -band 0xff))) | Out-Null
  }
}
$hexLines | Set-Content -Encoding ASCII -Path $HexOut

$expectedLines = $script:Expected | ForEach-Object {
  "{0:X8} {1:X8}" -f $_.Addr, $_.Data
}
$expectedLines | Set-Content -Encoding ASCII -Path $ExpectedOut

Write-Host "wrote $HexOut ($($script:Words.Count) words)"
Write-Host "wrote $ExpectedOut ($($script:Expected.Count) expected stores)"
