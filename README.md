# lc-toolkit (Lagana.Consulting.Toolkit)

Reusable PowerShell toolkit for consulting automation:
- logging
- safe CSV export
- tenant-pinned auth helpers (Graph)
- common utilities

## Install for dev
From repo root:

```powershell
Import-Module "$PWD\src\Lagana.Consulting.Toolkit" -Force
Get-Command -Module Lagana.Consulting.Toolkit
