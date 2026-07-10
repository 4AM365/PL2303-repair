# PL2303TA driver 3.8.36.2 — do not update

Last Prolific driver that works with the PL2303TA on Windows 11. Versions 3.9.x+
deliberately block the chip ("DO NOT SUPPORT WINDOWS 11"). Prolific no longer
hosts this version; source was the Microsoft Update Catalog (WHQL-signed,
2020-08 cab).

To set up any machine: run `pin-pl2303ta-driver.ps1` (right-click > Run with
PowerShell, accept UAC). It installs this driver, purges the blocker versions,
and stops Windows Update from reinstalling them. The script re-downloads the
driver from the Update Catalog if the files beside it are missing.
