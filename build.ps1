param(
  [switch]$Package,
  [switch]$Tests
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$zig = Join-Path $root "tools\zig-dist\zig-x86_64-windows-0.16.0\zig.exe"
$monixRoot = Join-Path $root "Monix"
$source = Join-Path $monixRoot "UI\MainWindow\MainWindow.cpp"
$antivirusSource = Join-Path $monixRoot "Security\Antivirus\Antivirus.cpp"
$installerSource = Join-Path $root "src\native\installer.cpp"
$contextEngineSource = Join-Path $monixRoot "Security\Antivirus\Engine\ScanEngine.cpp"
$resourceFile = Join-Path $monixRoot "Assets\Icons\resources.rc"
$icoFile = Join-Path $root "ico.ico"
$rcedit = Join-Path $root "tools\rcedit\rcedit.exe"
$outputDir = Join-Path $root "build"
$output = Join-Path $outputDir "Monix.exe"
$installerOutput = Join-Path $outputDir "MonixInstaller.exe"
$resOutput = Join-Path $outputDir "resources.res"
$zigCacheDir = Join-Path $outputDir "zig-cache"
$distDir = Join-Path $root "dist"

if (-not (Test-Path $zig)) {
  throw "Zig toolchain not found at $zig"
}

if (-not (Test-Path $source)) {
  throw "Source file not found at $source"
}

if (-not (Test-Path $antivirusSource)) {
  throw "Antivirus source file not found at $antivirusSource"
}

if (-not (Test-Path $installerSource)) {
  throw "Installer source file not found at $installerSource"
}

if (-not (Test-Path $icoFile)) {
  throw "Icon file not found at $icoFile"
}

New-Item -ItemType Directory -Force $outputDir | Out-Null
New-Item -ItemType Directory -Force $zigCacheDir | Out-Null
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $zigCacheDir "local"
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $zigCacheDir "global"
New-Item -ItemType Directory -Force $env:ZIG_LOCAL_CACHE_DIR | Out-Null
New-Item -ItemType Directory -Force $env:ZIG_GLOBAL_CACHE_DIR | Out-Null

# Compile resources (icon + version info)
Write-Host "Compiling resources..."
$rcCmd = Get-Command rc.exe -ErrorAction SilentlyContinue
$windresCmd = Get-Command windres -ErrorAction SilentlyContinue
# Try explicit common Windows Kits x64 locations
$rcExplicit = $null
try {
  $kits = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName -ErrorAction SilentlyContinue
  foreach ($k in $kits) {
    $cand = Join-Path $k 'x64\rc.exe'
    if (Test-Path $cand) { $rcExplicit = $cand; break }
  }
} catch { }
if ($rcCmd) {
  & rc.exe /fo $resOutput $resourceFile
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: RC.exe failed, continuing without resources"
    $resOutput = ""
  }
} else {
  if ($rcExplicit) {
    Write-Host "Using explicit rc.exe at $rcExplicit"
    # derive SDK version from explicit path
    $sdkVer = $null
    try {
      $parts = $rcExplicit -split '\\'
      $binIndex = [Array]::IndexOf($parts,'bin')
      if ($binIndex -ge 0 -and $parts.Length -gt ($binIndex + 1)) { $sdkVer = $parts[$binIndex + 1] }
    } catch { }
    if ($sdkVer) {
      $includeRoot = Join-Path 'C:\Program Files (x86)\Windows Kits\10\Include' $sdkVer
      $inc1 = Join-Path $includeRoot 'um'
      $inc2 = Join-Path $includeRoot 'shared'
      $incArgs = @()
      if (Test-Path $inc1) { $incArgs += '/I'; $incArgs += $inc1 }
      if (Test-Path $inc2) { $incArgs += '/I'; $incArgs += $inc2 }
      Write-Host "Using include paths: $incArgs"
      & "$rcExplicit" @incArgs '/fo' $resOutput $resourceFile
    } else {
      & "$rcExplicit" /fo $resOutput $resourceFile
    }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Warning: rc.exe failed, continuing without resources"
      $resOutput = ""
    }
  } else {
  # Try to find rc.exe under Windows Kits folders (common install location)
  $possible = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter 'rc.exe' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like '*\\x64\\rc.exe' } | Select-Object -First 1
  if ($possible) {
    $rcPath = $possible.FullName
    Write-Host "Found rc.exe at $rcPath"
    # Try to derive SDK include paths from the rc.exe path (robust split)
    $sdkVer = $null
    try {
      $parts = $rcPath -split '\\'
      $binIndex = [Array]::IndexOf($parts,'bin')
      if ($binIndex -ge 0 -and $parts.Length -gt ($binIndex + 1)) { $sdkVer = $parts[$binIndex + 1] }
    } catch { }
    if ($sdkVer) {
      $includeRoot = Join-Path 'C:\Program Files (x86)\Windows Kits\10\Include' $sdkVer
      $inc1 = Join-Path $includeRoot 'um'
      $inc2 = Join-Path $includeRoot 'shared'
      $incArgs = @()
      if (Test-Path $inc1) { $incArgs += '/I'; $incArgs += $inc1 }
      if (Test-Path $inc2) { $incArgs += '/I'; $incArgs += $inc2 }
      Write-Host "Using include paths: $incArgs"
      & "$rcPath" @incArgs '/fo' $resOutput $resourceFile
    } else {
      & "$rcPath" /fo $resOutput $resourceFile
    }
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Warning: rc.exe failed, continuing without resources"
      $resOutput = ""
    }
  } elseif ($windresCmd) {
    & windres -i $resourceFile -o $resOutput
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Warning: windres failed, continuing without resources"
      $resOutput = ""
    }
  } else {
    Write-Host "Warning: RC.exe or windres not found, continuing without resources"
    $resOutput = ""
  }
  }
}

# Build executable with icon embedded
Write-Host "Building Monix.exe with icon..."
$compileArgs = @(
  "c++"
  "-std=c++20"
  "-O2"
  "-w"
  "-DUNICODE"
  "-D_UNICODE"
  "-municode"
  "-Xlinker", "/subsystem:windows"
  "-I", (Join-Path $monixRoot "third_party")
  "-I", (Join-Path $monixRoot "UI")
  "-I", (Join-Path $monixRoot "UI\Modules")
  "-I", (Join-Path $monixRoot "Logging")
  $source
  $antivirusSource
  (Join-Path $monixRoot "Core\EventBus.cpp")
  (Join-Path $monixRoot "Core\Scheduler.cpp")
  (Join-Path $monixRoot "Logging\CategoryMapper.cpp")
  (Join-Path $monixRoot "Observability\Observability.cpp")
  (Join-Path $monixRoot "Recovery\RecoveryScanner.cpp")
  (Join-Path $monixRoot "UI\Modules\Hardware\HardwarePanel.cpp")
  (Join-Path $monixRoot "UI\UIManager.cpp")
  (Join-Path $monixRoot "UI\Modules\AudioManager\AudioManager.cpp")
  (Join-Path $monixRoot "UI\Modules\CursorRenderer\CursorRenderer.cpp")
  (Join-Path $monixRoot "UI\Modules\ViewportAnimator\ViewportAnimator.cpp")
  (Join-Path $monixRoot "UI\Modules\UIEnhancements\UIEnhancements.cpp")
  (Join-Path $monixRoot "UI\Modules\AnimationManager\AnimationManager.cpp")
  $contextEngineSource
  "-luser32"
  "-lgdi32"
  "-lpsapi"
  "-lcomdlg32"
  "-lshell32"
  "-lshlwapi"
  "-liphlpapi"
  "-lws2_32"
  "-lole32"
  "-lopengl32"
  "-lgdiplus"
  "-luuid"
  "-lwinmm"
)

# Add resource file if compilation succeeded
if ($resOutput -and (Test-Path $resOutput)) {
  $compileArgs += $resOutput
}

$compileArgs += "-o", $output

& $zig @compileArgs

if ($LASTEXITCODE -ne 0) {
  throw "Build failed with exit code $LASTEXITCODE"
}

$iconStamped = $false
if (Test-Path $rcedit) {
  Write-Host "Applying embedded icon with rcedit..."
  & $rcedit $output --set-icon $icoFile
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: rcedit failed to stamp ico.ico into the executable"
  } else {
    $iconStamped = $true
  }
} else {
  Write-Host "Warning: rcedit not found, skipping post-build icon stamping"
}

Write-Host "Built $output"
if (($resOutput -and (Test-Path $resOutput)) -or $iconStamped) {
  Write-Host "Icon embedded successfully"
} else {
  Write-Host "Warning: No resource file linked; icon may not be embedded. Install Windows SDK rc.exe to embed icon."
}

# Build installer executable. It uses the same GDI visual language as Monix, but no OpenGL or shaders.
Write-Host "Building MonixInstaller.exe..."
$installerCompileArgs = @(
  "c++"
  "-std=c++20"
  "-O2"
  "-w"
  "-DUNICODE"
  "-D_UNICODE"
  "-municode"
  "-Xlinker", "/subsystem:windows"
  $installerSource
  "-luser32"
  "-lgdi32"
  "-lshell32"
  "-lshlwapi"
  "-lole32"
  "-luuid"
  "-o", $installerOutput
)

& $zig @installerCompileArgs

if ($LASTEXITCODE -ne 0) {
  throw "Installer build failed with exit code $LASTEXITCODE"
}

if (Test-Path $rcedit) {
  Write-Host "Applying embedded icon to installer with rcedit..."
  & $rcedit $installerOutput --set-icon $icoFile
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Warning: rcedit failed to stamp ico.ico into the installer"
  }
}

Write-Host "Built $installerOutput"

# Optional: Build test executable if requested
if ($Tests) {
  Write-Host "Building CoreModuleTests.exe..."
  $testOutput = Join-Path $outputDir "CoreModuleTests.exe"
  $testSource = Join-Path $monixRoot "Tests\CoreModuleTests.cpp"
  
  if (Test-Path $testSource) {
    $testCompileArgs = @(
      "c++"
      "-std=c++20"
      "-O2"
      "-w"
      "-DUNICODE"
      "-D_UNICODE"
      "-I", (Join-Path $monixRoot "third_party")
      "-I", (Join-Path $monixRoot "UI")
      "-I", (Join-Path $monixRoot "UI\Modules")
      "tests-main.cpp"
      $testSource
      (Join-Path $monixRoot "Core\EventBus.cpp")
      (Join-Path $monixRoot "Core\Scheduler.cpp")
      (Join-Path $monixRoot "Observability\Observability.cpp")
      (Join-Path $monixRoot "Recovery\RecoveryScanner.cpp")
      "-luser32"
      "-lgdi32"
      "-lpsapi"
      "-lwinmm"
      "-lgdiplus"
      "-lole32"
      "-luuid"
      "-o", $testOutput
    )
    
    & $zig @testCompileArgs
    
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Built $testOutput"
      Write-Host "Run tests: & '$testOutput'"
    } else {
      Write-Host "Warning: Test build failed (this is optional)"
    }
  } else {
    Write-Host "Warning: Test source not found at $testSource"
  }
}

function Reset-DistDirectory {
  param([string]$Path)

  $distFull = [System.IO.Path]::GetFullPath($distDir)
  $targetFull = [System.IO.Path]::GetFullPath($Path)
  if (-not $targetFull.StartsWith($distFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to reset directory outside dist: $targetFull"
  }

  if (Test-Path $targetFull) {
    Remove-Item -LiteralPath $targetFull -Recurse -Force
  }
  New-Item -ItemType Directory -Force $targetFull | Out-Null
}

function Copy-PayloadFile {
  param(
    [string]$RelativePath,
    [string]$PayloadRoot,
    [string]$SourceOverride = ""
  )

  $sourcePath = if ($SourceOverride) { $SourceOverride } else { Join-Path $root $RelativePath }
  if (-not (Test-Path $sourcePath)) {
    throw "Missing payload file: $sourcePath"
  }

  $destinationPath = Join-Path $PayloadRoot $RelativePath
  $destinationDirectory = Split-Path -Parent $destinationPath
  New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
  Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

function Copy-PayloadDirectory {
  param(
    [string]$RelativePath,
    [string]$PayloadRoot
  )

  $sourcePath = Join-Path $root $RelativePath
  if (-not (Test-Path $sourcePath)) {
    throw "Missing payload directory: $sourcePath"
  }

  $destinationPath = Join-Path $PayloadRoot $RelativePath
  New-Item -ItemType Directory -Force (Split-Path -Parent $destinationPath) | Out-Null
  Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse -Force
}

function Copy-MonixPayload {
  param([string]$PayloadRoot)

  New-Item -ItemType Directory -Force $PayloadRoot | Out-Null
  Copy-PayloadFile -RelativePath "Monix.exe" -PayloadRoot $PayloadRoot -SourceOverride $output
  Copy-PayloadFile -RelativePath "crt-lottes-fast.glsl" -PayloadRoot $PayloadRoot
  Copy-PayloadFile -RelativePath "monix.ini" -PayloadRoot $PayloadRoot
  Copy-PayloadFile -RelativePath "intro.wav" -PayloadRoot $PayloadRoot
  Copy-PayloadFile -RelativePath "ico.ico" -PayloadRoot $PayloadRoot
  Copy-PayloadFile -RelativePath "tools\vhs-gothic.ttf" -PayloadRoot $PayloadRoot
  Copy-PayloadFile -RelativePath "src\native\collect.ps1" -PayloadRoot $PayloadRoot
  Copy-PayloadDirectory -RelativePath "Sound" -PayloadRoot $PayloadRoot
}

function New-ZipPackage {
  param(
    [string]$SourceDirectory,
    [string]$ZipPath
  )

  if (Test-Path $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
  }
  Compress-Archive -Path (Join-Path $SourceDirectory "*") -DestinationPath $ZipPath -Force
}

if ($Package) {
  Write-Host "Creating release packages..."
  New-Item -ItemType Directory -Force $distDir | Out-Null

  $windowsPackage = Join-Path $distDir "windows\Monix-Windows"
  $windowsPayload = Join-Path $windowsPackage "payload"
  Reset-DistDirectory -Path $windowsPackage
  Copy-Item -LiteralPath $installerOutput -Destination (Join-Path $windowsPackage "MonixInstaller.exe") -Force
  Copy-MonixPayload -PayloadRoot $windowsPayload
  $windowsReadme = Join-Path $root "packaging\windows\README.md"
  if (Test-Path $windowsReadme) {
    Copy-Item -LiteralPath $windowsReadme -Destination (Join-Path $windowsPackage "README.md") -Force
  }
  Set-Content -Path (Join-Path $windowsPackage "install-monix.bat") -Encoding ASCII -Value @(
    "@echo off"
    "start MonixInstaller.exe"
  )
  New-ZipPackage -SourceDirectory $windowsPackage -ZipPath (Join-Path $distDir "Monix-Windows.zip")

  $linuxPackage = Join-Path $distDir "linux\Monix-Linux"
  $linuxPayload = Join-Path $linuxPackage "payload"
  Reset-DistDirectory -Path $linuxPackage
  Copy-MonixPayload -PayloadRoot $linuxPayload
  $linuxInstaller = Join-Path $root "packaging\linux\install-monix.sh"
  $linuxReadme = Join-Path $root "packaging\linux\README.md"
  if (-not (Test-Path $linuxInstaller)) {
    throw "Missing Linux installer script at $linuxInstaller"
  }
  Copy-Item -LiteralPath $linuxInstaller -Destination (Join-Path $linuxPackage "install-monix.sh") -Force
  if (Test-Path $linuxReadme) {
    Copy-Item -LiteralPath $linuxReadme -Destination (Join-Path $linuxPackage "README.md") -Force
  }
  New-ZipPackage -SourceDirectory $linuxPackage -ZipPath (Join-Path $distDir "Monix-Linux.zip")

  Write-Host "Packages ready:"
  Write-Host "  $windowsPackage"
  Write-Host "  $(Join-Path $distDir "Monix-Windows.zip")"
  Write-Host "  $linuxPackage"
  Write-Host "  $(Join-Path $distDir "Monix-Linux.zip")"
}
