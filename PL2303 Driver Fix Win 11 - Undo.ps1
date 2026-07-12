#Requires -Version 5.1
<#
Reverses "PL2303 Driver Fix Win 11.ps1". Removes the pinned PL2303TA driver
(3.8.36.2) from the driver store and re-enables Windows Update driver delivery,
returning the machine to stock Windows behaviour.

What it does:
  1. Self-elevates (UAC prompt).
  2. Re-enables driver delivery via Windows Update (removes
     ExcludeWUDriversInQualityUpdate, restores SearchOrderConfig=1). This lifts
     the machine-wide block the forward script set, so ALL drivers can auto-
     install from WU again - not just Prolific.
  3. Removes 3.8.36.2 from the driver store so Windows no longer pins it.
  4. Rescans so the change takes effect immediately.

What it CANNOT undo: the forward script purged every OTHER Prolific "Ports"
driver from the store, and deleted drivers can't be resurrected. After this
script runs, a plugged-in PL2303 cable has NO Prolific driver staged, so on the
next Windows Update / rescan the machine will pull whatever WU offers - for a
PL2303TA that is the 3.9.x+ build that deliberately blocks the chip ("DO NOT
SUPPORT WINDOWS 11"). In other words: this genuinely un-fixes the fix. Re-run
the forward script to pin 3.8.36.2 again.

Safe to rerun. Cable does not need to be plugged in.
#>

$ErrorActionPreference = 'Stop'
$GoodVersion = '3.8.36.2'   # the pinned version the forward script added; this is what we remove

# --- Step 1: self-elevate ---------------------------------------------------
# Driver-store edits and HKLM policy writes both need admin. If we're not
# already elevated, relaunch this same script through a UAC prompt and exit the
# non-elevated instance.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    exit
}

try {
    # --- Step 2: re-enable Windows Update driver delivery --------------------
    # The forward script set these two values to stop WU from ever pushing a
    # driver. Undo them to Windows defaults so automatic driver delivery works
    # again (GPU/other vendor drivers included, not just Prolific).
    Write-Host 'Re-enabling driver delivery via Windows Update...'

    # ExcludeWUDriversInQualityUpdate: the forward script created this value and
    # set it to 1. Removing it = Windows default (drivers NOT excluded), the
    # same effect as setting it to 0. Ignore "not found" if it was never set.
    $wuPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    if (Test-Path $wuPolicy) {
        Remove-ItemProperty -Path $wuPolicy -Name 'ExcludeWUDriversInQualityUpdate' -ErrorAction SilentlyContinue
    }

    # SearchOrderConfig: 1 is the Windows default ("search Windows Update"). The
    # forward script set it to 0 to stop WU being searched; put it back to 1.
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -Name 'SearchOrderConfig' -Value 1 -Type DWord

    # --- Step 3: remove 3.8.36.2 from the driver store ----------------------
    # Find the pinned package (same Provider/Class filter the forward script
    # uses, but matching ON the good version instead of everything-but).
    Write-Host "Removing driver $GoodVersion from the store..."
    $pinned = Get-WindowsDriver -Online | Where-Object {
        $_.ProviderName -eq 'Prolific' -and $_.ClassName -eq 'Ports' -and $_.Version -eq $GoodVersion
    }
    $rebootNeeded = $false
    if ($pinned) {
        foreach ($d in $pinned) {
            Write-Host "Deleting $($d.Driver) ($(Split-Path $d.OriginalFileName -Leaf) $($d.Version))..."
            # /uninstall detaches it from any device using it; /force deletes even
            # if in use. After this, no Prolific "Ports" driver remains staged.
            $out = pnputil /delete-driver $d.Driver /uninstall /force
            if ($out -match 'reboot') { $rebootNeeded = $true }
        }
    } else {
        Write-Host "No $GoodVersion driver found in the store - nothing to remove."
    }

    # --- Step 4: rescan so the change takes effect now ----------------------
    pnputil /scan-devices | Out-Null
    Start-Sleep -Seconds 5

    # Report what the PL2303 device (VID_067B), if any, is now bound to.
    $dev = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -match 'VID_067B' }
    if ($dev) {
        $dev | ForEach-Object { Write-Host ("RESULT: {0} - driver {1}" -f $_.DeviceName, $_.DriverVersion) }
        Write-Warning 'The cable will now accept whatever Windows Update offers - for a PL2303TA that is the 3.9.x+ blocker. Re-run the forward script to re-pin 3.8.36.2.'
    } else {
        Write-Host 'RESULT: no PL2303 cable plugged in right now. WU driver delivery is re-enabled and 3.8.36.2 is unpinned.'
    }
    if ($rebootNeeded) { Write-Host 'Reboot recommended to flush remnants of the removed driver.' }
    Write-Host 'Done. The forward script''s fix has been reversed.'
}
catch {
    Write-Host "FAILED: $_" -ForegroundColor Red
}

# Keep the window open when launched via right-click > Run with PowerShell.
try { Read-Host 'Press Enter to close' | Out-Null } catch { }
