#Requires -Version 5.1
<#
Pins the last PL2303TA-compatible Prolific driver (3.8.36.2) on Windows 11 and
stops Windows Update from reinstalling the 3.9.x+ versions that deliberately
block the chip ("DO NOT SUPPORT WINDOWS 11").

What it does:
  1. Self-elevates (UAC prompt).
  2. Uses the driver files sitting next to this script; if missing, downloads
     the WHQL-signed package from the Microsoft Update Catalog.
  3. Verifies the package signature and version before touching anything.
  4. Adds 3.8.36.2 to the driver store, then purges every other Prolific
     Ports driver so 3.8.36.2 is the only candidate Windows can pick.
  5. Blocks driver delivery via Windows Update (ExcludeWUDriversInQualityUpdate=1,
     SearchOrderConfig=0). Side effect: NO drivers auto-install from WU anymore
     on this machine; install GPU/other drivers manually or via vendor apps.
     Revert: set those two values to 0 and 1 respectively.
  6. Rescans so a plugged-in cable rebinds immediately.

Safe to rerun. Cable does not need to be plugged in — the store is prepped
either way. Caution: this removes ALL non-3.8.36.2 Prolific serial drivers;
if a machine also uses a newer PL2303G-series device, that device will lose
its driver.
#>

$ErrorActionPreference = 'Stop'
$GoodVersion = '3.8.36.2'
$CabUrl = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/driver/drvs/2020/08/6e68070b-8c5f-4ae5-b629-e41646f1604c_63674072f4783b1ac5fbc8e87a42634f1e1b127e.cab'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    exit
}

$here = Split-Path -Parent $PSCommandPath
$inf = Join-Path $here 'ser2pl.inf'

try {
    if (-not (Test-Path $inf)) {
        Write-Host 'Driver files not found next to script - downloading from Microsoft Update Catalog...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $cab = Join-Path $env:TEMP 'pl2303_38362.cab'
        Invoke-WebRequest -Uri $CabUrl -OutFile $cab -UseBasicParsing
        expand.exe $cab -F:* $here | Out-Null
    }

    $sig = Get-AuthenticodeSignature (Join-Path $here 'ser2pl.cat')
    if ($sig.Status -ne 'Valid') { throw "ser2pl.cat signature status is '$($sig.Status)' - aborting." }
    $ver = (Get-Item (Join-Path $here 'SER2PL64.sys')).VersionInfo.FileVersion
    if ($ver -ne $GoodVersion) { throw "Package is version $ver, expected $GoodVersion - aborting." }

    Write-Host "Adding driver $GoodVersion to the store..."
    pnputil /add-driver $inf | Select-String 'Published name|Driver package added|already' | ForEach-Object Line

    # Add first, purge second: the cable always has a valid fallback in the store.
    $bad = Get-WindowsDriver -Online | Where-Object {
        $_.ProviderName -eq 'Prolific' -and $_.ClassName -eq 'Ports' -and $_.Version -ne $GoodVersion
    }
    $rebootNeeded = $false
    if ($bad) {
        foreach ($d in $bad) {
            Write-Host "Removing $($d.Driver) ($(Split-Path $d.OriginalFileName -Leaf) $($d.Version))..."
            $out = pnputil /delete-driver $d.Driver /uninstall /force
            if ($out -match 'reboot') { $rebootNeeded = $true }
        }
    } else {
        Write-Host 'No other Prolific serial drivers in the store.'
    }

    Write-Host 'Blocking driver delivery via Windows Update...'
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name 'ExcludeWUDriversInQualityUpdate' -Value 1 -Type DWord
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'SearchOrderConfig' -Value 0 -Type DWord

    pnputil /scan-devices | Out-Null
    Start-Sleep -Seconds 5

    $dev = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -match 'VID_067B' }
    if ($dev) {
        $dev | ForEach-Object { Write-Host ("RESULT: {0} - driver {1}" -f $_.DeviceName, $_.DriverVersion) }
        $wrong = $dev | Where-Object { $_.DriverVersion -ne $GoodVersion }
        if ($wrong) { Write-Warning 'A Prolific device is not on 3.8.36.2 - reboot and rerun this script.' }
    } else {
        Write-Host 'RESULT: no PL2303 cable plugged in right now - store is prepped, it will bind to 3.8.36.2 on plug-in.'
    }
    if ($rebootNeeded) { Write-Host 'Reboot recommended to flush remnants of the removed driver.' }
    Write-Host 'Done.'
}
catch {
    Write-Host "FAILED: $_" -ForegroundColor Red
}

try { Read-Host 'Press Enter to close' | Out-Null } catch { }
