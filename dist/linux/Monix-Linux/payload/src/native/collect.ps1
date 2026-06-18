$ErrorActionPreference = "SilentlyContinue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Inv([double]$value) {
  return $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function SafeText([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) {
    return ""
  }

  return $value.Replace("|", "/").Replace("`r", " ").Replace("`n", " ").Trim()
}

function BoolFlag([bool]$value) {
  if ($value) { return "1" }
  return "0"
}

$logicalProcessors = [Environment]::ProcessorCount
$allProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.ProcessName -ne "conhost" })
$procLookup = @{}

foreach ($proc in $allProcesses) {
  $priority = "NORMAL"
  $state = "ACTIVE"
  $displayName = $proc.ProcessName

  try {
    if ($proc.PriorityClass) {
      $priority = $proc.PriorityClass.ToString().ToUpperInvariant()
    }
  } catch {}

  switch -Regex ($displayName.ToLowerInvariant()) {
    "obs" { $state = "RECORDING"; break }
    "system|registry|smss|csrss|wininit|services|lsass" { $state = "KERNEL"; break }
    "explorer" { $state = "SYSTEM"; break }
    "game|monix|render" { $state = "RUNNING"; break }
  }

  $procLookup[$proc.Id] = [pscustomobject]@{
    name = [string]$displayName
    priority = [string]$priority
    state = [string]$state
  }
}

$cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor | Where-Object { $_.Name -eq "_Total" } | Select-Object -First 1
$os = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1
$disk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk | Where-Object { $_.Name -eq "_Total" } | Select-Object -First 1
$interfaces = @(Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface | Where-Object { $_.Name -notmatch "Loopback|isatap|Teredo" })
$connections = @(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -ne $PID })

$gpuByPid = @{}
$gpuTotal = 0.0
$gpuCounter = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction SilentlyContinue
if ($gpuCounter) {
  foreach ($sample in @($gpuCounter.CounterSamples | Where-Object { $_.InstanceName -match "engtype_" })) {
    $gpuTotal += [double]$sample.CookedValue
    if ($sample.InstanceName -match "pid_(\d+)") {
      $pid = [int]$Matches[1]
      if (-not $gpuByPid.ContainsKey($pid)) {
        $gpuByPid[$pid] = 0.0
      }
      $gpuByPid[$pid] += [double]$sample.CookedValue
    }
  }
}

$systemCounterPaths = @(
  '\System\Processor Queue Length',
  '\System\Context Switches/sec',
  '\System\System Calls/sec',
  '\Processor(_Total)\Interrupts/sec'
)
$counterSamples = @()
$counterRead = Get-Counter $systemCounterPaths -ErrorAction SilentlyContinue
if ($counterRead) {
  $counterSamples = @($counterRead.CounterSamples)
}

function FindCounterValue([array]$samples, [string]$suffix) {
  $sample = $samples | Where-Object { $_.Path -like "*$suffix" } | Select-Object -First 1
  if ($sample) {
    return [double]$sample.CookedValue
  }
  return 0.0
}

$processorQueueLength = [int][math]::Round((FindCounterValue $counterSamples 'Processor Queue Length'), 0)
$contextSwitchesPerSec = [int][math]::Round((FindCounterValue $counterSamples 'Context Switches/sec'), 0)
$systemCallsPerSec = [int][math]::Round((FindCounterValue $counterSamples 'System Calls/sec'), 0)
$interruptsPerSec = [int][math]::Round((FindCounterValue $counterSamples 'Interrupts/sec'), 0)

$now = Get-Date
$processTable = @(
  $allProcesses |
  Where-Object { $_.ProcessName -notin @("powershell", "pwsh") } |
  ForEach-Object {
    $elapsed = 0.0
    try {
      $elapsed = ($now - $_.StartTime).TotalSeconds
    } catch {}

    $cpuPct = 0.0
    if ($elapsed -gt 0 -and $_.CPU -ne $null) {
      $cpuPct = [math]::Min(100.0, (($_.CPU / $elapsed) * 100.0) / [math]::Max(1, $logicalProcessors))
    }

    [pscustomobject]@{
      pid = [int]$_.Id
      name = [string]$_.ProcessName
      cpuPct = [math]::Round($cpuPct, 1)
      ramBytes = [int64]$_.WorkingSet64
    }
  } |
  Sort-Object -Property @{ Expression = "cpuPct"; Descending = $true }, @{ Expression = "ramBytes"; Descending = $true }
)

$totalVisibleBytes = [int64]$os.TotalVisibleMemorySize * 1024
$freeBytes = [int64]$os.FreePhysicalMemory * 1024
$usedBytes = if ($totalVisibleBytes -gt $freeBytes) { $totalVisibleBytes - $freeBytes } else { 0 }

$upBytes = 0.0
$downBytes = 0.0
foreach ($iface in $interfaces) {
  $upBytes += [double]$iface.BytesSentPersec
  $downBytes += [double]$iface.BytesReceivedPersec
}

$established = @($connections | Where-Object { $_.State -eq "Established" })
$listening = @($connections | Where-Object { $_.State -eq "Listen" })
$dnsPseudo = [math]::Min(96, [math]::Max(0, [int]($established.Count / 2)))
$latencyMs = if ($established.Count -gt 0) { [math]::Max(10, [math]::Min(85, $established.Count + 8)) } else { 0 }

$pageFileUsedBytes = 0
$pageFileTotalBytes = 0
foreach ($pageFile in @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)) {
  $pageFileUsedBytes += [int64]$pageFile.CurrentUsage * 1MB
  $pageFileTotalBytes += [int64]$pageFile.AllocatedBaseSize * 1MB
}

$threadCount = 0
$handleCount = 0
foreach ($proc in $allProcesses) {
  try { $threadCount += $proc.Threads.Count } catch {}
  try { $handleCount += [int]$proc.HandleCount } catch {}
}

$uptimeSeconds = 0
try {
  $uptimeSeconds = [int64](($now - $os.LastBootUpTime).TotalSeconds)
} catch {}

$cpuTempC = 0.0
$cpuTempEstimated = $false
$thermalZones = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue)
$zoneTemps = @()
foreach ($zone in $thermalZones) {
  if ($zone.CurrentTemperature -gt 0) {
    $zoneTemps += (($zone.CurrentTemperature / 10.0) - 273.15)
  }
}
if ($zoneTemps.Count -gt 0) {
  $cpuTempC = [math]::Round(($zoneTemps | Measure-Object -Average).Average, 1)
} else {
  $cpuTempC = [math]::Round(31.0 + ([double]$cpu.PercentProcessorTime * 0.52), 1)
  $cpuTempEstimated = $true
}

$gpuTempC = [math]::Round(35.0 + ([math]::Min(100.0, $gpuTotal) * 0.58), 1)
$gpuTempEstimated = $true

$storageTempC = 0.0
$storageTempEstimated = $false
if (Get-Command Get-StorageReliabilityCounter -ErrorAction SilentlyContinue) {
  try {
    $diskTemps = @(Get-PhysicalDisk -ErrorAction SilentlyContinue | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue | Where-Object { $_.Temperature -gt 0 })
    if ($diskTemps.Count -gt 0) {
      $storageTempC = [math]::Round(($diskTemps | Measure-Object -Property Temperature -Average).Average, 1)
    }
  } catch {}
}
if ($storageTempC -le 0) {
  $diskLoadMbps = (([double]$disk.DiskReadBytesPersec) + ([double]$disk.DiskWriteBytesPersec)) / 1MB
  $storageTempC = [math]::Round(29.0 + [math]::Min(18.0, ($diskLoadMbps / 18.0)), 1)
  $storageTempEstimated = $true
}

Write-Output ("META|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}|{17}|{18}|{19}|{20}|{21}|{22}|{23}|{24}|{25}|{26}|{27}|{28}|{29}" -f @(
  (SafeText $env:COMPUTERNAME),
  (Inv ([math]::Round([double]$cpu.PercentProcessorTime, 1))),
  $usedBytes,
  $totalVisibleBytes,
  (Inv ([math]::Round([math]::Min(100.0, $gpuTotal), 1))),
  ([int64]$disk.DiskReadBytesPersec),
  ([int64]$disk.DiskWriteBytesPersec),
  ([int64][math]::Round($upBytes, 0)),
  ([int64][math]::Round($downBytes, 0)),
  $listening.Count,
  $established.Count,
  $dnsPseudo,
  $latencyMs,
  (Inv $cpuTempC),
  (BoolFlag $cpuTempEstimated),
  (Inv $gpuTempC),
  (BoolFlag $gpuTempEstimated),
  (Inv $storageTempC),
  (BoolFlag $storageTempEstimated),
  $allProcesses.Count,
  $threadCount,
  $handleCount,
  $pageFileUsedBytes,
  $pageFileTotalBytes,
  $processorQueueLength,
  $contextSwitchesPerSec,
  $systemCallsPerSec,
  $interruptsPerSec,
  $uptimeSeconds
))

$seenProcessIds = @{}
$processLimit = [math]::Min(36, $processTable.Count)
for ($index = 0; $index -lt $processLimit; $index++) {
  $process = $processTable[$index]
  $pid = [int]$process.pid
  if ($seenProcessIds.ContainsKey($pid)) { continue }
  $seenProcessIds[$pid] = $true
  $lookup = $procLookup[$pid]
  $displayName = SafeText([string]$process.name)
  $priority = "NORMAL"
  $state = "ACTIVE"

  if ($lookup) {
    if ($lookup.name) { $displayName = SafeText($lookup.name) }
    if ($lookup.priority) { $priority = SafeText($lookup.priority) }
    if ($lookup.state) { $state = SafeText($lookup.state) }
  }

  $gpuPct = 0.0
  if ($gpuByPid.ContainsKey($pid)) {
    $gpuPct = [math]::Round([math]::Min(100.0, [double]$gpuByPid[$pid]), 1)
  }

  Write-Output ("PROC|{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f @(
    $displayName,
    $pid,
    (Inv ([double]$process.cpuPct)),
    ([int64]$process.ramBytes),
    (Inv $gpuPct),
    $state,
    $priority
  ))
}

foreach ($group in ($connections | Group-Object OwningProcess | Sort-Object Count -Descending | Select-Object -First 10)) {
  $pid = 0
  [void][int]::TryParse([string]$group.Name, [ref]$pid)
  if ($pid -le 0) { continue }

  $displayName = "PID $pid"
  if ($procLookup.ContainsKey($pid) -and $procLookup[$pid].name) {
    $displayName = SafeText($procLookup[$pid].name)
  }
  if ($displayName -in @("powershell", "pwsh", "WmiPrvSE", "svchost")) { continue }

  $groupEstablished = @($group.Group | Where-Object { $_.State -eq "Established" })
  $preview = @(
    $groupEstablished | Select-Object -First 2 | ForEach-Object {
      if ([string]::IsNullOrWhiteSpace($_.RemoteAddress) -or $_.RemoteAddress -eq "0.0.0.0" -or $_.RemoteAddress -eq "::") {
        "local"
      } else {
        SafeText("$($_.RemoteAddress):$($_.RemotePort)")
      }
    }
  )

  $remote = if ($preview.Count -eq 0) {
    "local"
  } else {
    $preview -join ", "
  }

  $flowState = if ($groupEstablished.Count -gt 0) { "ACTIVE" } else { "IDLE" }
  Write-Output ("FLOW|{0}|{1}|{2}|{3}" -f @(
    $displayName,
    $groupEstablished.Count,
    (SafeText $remote),
    $flowState
  ))
}
