# PL2303TA driver 3.8.36.2 — do not update

Last Prolific driver that works with the PL2303TA on Windows 11. Versions 3.9.x+
deliberately block the chip ("DO NOT SUPPORT WINDOWS 11"). Prolific no longer
hosts this version; source was the Microsoft Update Catalog (WHQL-signed,
2020-08 cab).

## Fix a machine

Run `PL2303 Driver Fix Win 11.ps1` (right-click > Run with PowerShell, accept
UAC). It installs this driver, purges the blocker versions, and stops Windows
Update from reinstalling them. The script re-downloads the driver from the
Update Catalog if the files beside it are missing.

### What the fix script does, step by step

1. **Self-elevates.** Driver-store edits and registry policy writes need admin,
   so the script relaunches itself through a UAC prompt if it isn't already
   running elevated.
2. **Gets the driver files.** Uses `ser2pl.inf` / `.cat` / `.sys` sitting next
   to the script. If they're missing, it downloads the WHQL-signed cab from the
   Microsoft Update Catalog and expands it in place.
3. **Verifies before touching anything.** Aborts unless `ser2pl.cat`'s signature
   is `Valid` *and* `SER2PL64.sys` really is version 3.8.36.2 — a guard against a
   tampered or wrong-version package.
4. **Adds 3.8.36.2 to the driver store, then purges the rest.** `pnputil
   /add-driver` stages the good version first (so a plugged-in cable always has a
   valid fallback), then every *other* Prolific "Ports" driver is deleted with
   `/uninstall /force`, leaving 3.8.36.2 as the only version Windows can pick.
5. **Blocks driver delivery via Windows Update.** Sets
   `ExcludeWUDriversInQualityUpdate = 1` and `SearchOrderConfig = 0` so WU can't
   re-push the 3.9.x+ blocker. **Side effect:** this is machine-wide — *no*
   drivers auto-install from Windows Update afterward, so install GPU/other
   drivers manually or via vendor apps.
6. **Rescans devices.** `pnputil /scan-devices` so a plugged-in cable rebinds to
   3.8.36.2 immediately, then reports which driver the PL2303 device (if any) is
   on.

Safe to rerun. The cable does not need to be plugged in — the store is prepped
either way.

> **Caution:** step 4 removes *all* non-3.8.36.2 Prolific serial drivers. A
> machine that also uses a newer PL2303G-series device will lose that device's
> driver.

## Undo the fix

Run `PL2303 Driver Fix Win 11 - Undo.ps1` (same right-click > Run with
PowerShell, accept UAC) to reverse the fix and return to stock Windows behaviour.
It re-enables Windows Update driver delivery (removes
`ExcludeWUDriversInQualityUpdate`, restores `SearchOrderConfig = 1`) and removes
3.8.36.2 from the driver store.

> **Note:** the undo can't resurrect the other Prolific drivers the fix purged.
> Once WU delivery is re-enabled and 3.8.36.2 is unpinned, a PL2303TA cable will
> pull the 3.9.x+ blocker on the next update — i.e. it genuinely un-fixes the
> fix. Re-run the fix script to pin 3.8.36.2 again.
