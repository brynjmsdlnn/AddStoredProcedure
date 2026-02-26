# AddStoredProcedure

A **Package Manager Console (PMC)** helper that scaffolds timestamped SQL stored procedure files directly into your Infrastructure project — with automatic `.csproj` registration as `EmbeddedResource`.

---

## Features

- EF-style timestamp prefix (`yyyyMMddHHmmss`) for ordered file naming
- Auto-detects the Infrastructure project by looking for a `Migrations` folder
- Registers the generated `.sql` file as `EmbeddedResource` in your `.csproj`, grouped by schema/module with a comment header
- Smart author detection: GitHub Actions → Azure DevOps → Git config → solution name fallback
- BOM-safe UTF-8 output
- Supports `-WhatIf`

---

## Requirements

- Visual Studio with Package Manager Console
- .NET Framework 4.8.1 project (targets `net481`)
- A project in your solution that contains a `Migrations` folder (Infrastructure project)

---

## Installation

### From nuget.org

In **Package Manager Console**:

```powershell
Install-Package AddStoredProcedure -ProjectName YourSolution.Infrastructure
```

### From a local source

```powershell
Install-Package AddStoredProcedure -Version 1.0.8 `
  -ProjectName YourSolution.Infrastructure `
  -Source "C:\path\to\nuget\AddStoredProcedure\artifacts"
```

> After installation, you should see:
> `Add-StoredProcedure command loaded. Use: Add-StoredProcedure -Help`

---

## Usage

### Syntax

```powershell
Add-StoredProcedure -Name <string> -Schema <string> [-Module <string>] [-Author <string>] [-Anon]
```

### Parameters

| Parameter  | Required | Description |
|------------|----------|-------------|
| `-Name`    | Yes      | Name of the stored procedure |
| `-Schema`  | Yes      | Database schema (e.g. `WIRE`, `PSGC`, `Admin`) |
| `-Module`  | No       | Logical subfolder grouping. Defaults to `-Schema` value |
| `-Author`  | No       | Explicit author name. Overrides auto-detection |
| `-Anon`    | No       | Forces author to the solution name |
| `-Help`    | No       | Displays usage information |

### Examples

**Basic usage — schema and module default to the same value:**
```powershell
Add-StoredProcedure -Name "usp_Users_GetAll" -Schema "WIRE"
```

**With a module subfolder:**
```powershell
Add-StoredProcedure -Name "usp_Users_GetAll" -Schema "WIRE" -Module "Users"
```

**With an explicit author:**
```powershell
Add-StoredProcedure -Name "usp_Roles_GetAll" -Schema "WIRE" -Module "Roles" -Author "John Doe"
```

**Preview without creating files (`-WhatIf`):**
```powershell
Add-StoredProcedure -Name "usp_Roles_GetAll" -Schema "WIRE" -Module "Roles" -WhatIf
```

### Output

Running the command generates a `.sql` file under your Infrastructure project:

```
Database\
  StoredProcedures\
    WIRE\
      Users\
        20260226150000_usp_Users_GetAll.sql
```

And registers it in your `.csproj` as:

```xml
<!-- Stored Procedures - WIRE/Users -->
<EmbeddedResource Include="Database\StoredProcedures\WIRE\Users\20260226150000_usp_Users_GetAll.sql" />
```

### Generated SQL template

```sql
-- =============================================
-- Author:      John Doe
-- Object:      StoredProcedure [WIRE].[usp_Users_GetAll]
-- Script date: 02/26/2026
-- Description:
-- =============================================

CREATE OR ALTER PROCEDURE [WIRE].[usp_Users_GetAll]
AS
BEGIN
    SET NOCOUNT ON;

    -- TODO: Add procedure logic

END
```

---

## Building & Publishing (maintainers)

### Prerequisites

- [`nuget.exe`](https://dist.nuget.org/win-x86-commandline/latest/nuget.exe) on your PATH or in the package folder

### Folder structure

```
AddStoredProcedure\
  AddStoredProcedure.nuspec
  lib\
    net481\
      _._
  tools\
    init.ps1
    Add-StoredProcedure.ps1
  artifacts\
```

### Build the package

In a terminal, navigate to the package folder and run:

```powershell
.\nuget pack AddStoredProcedure.nuspec -OutputDirectory artifacts -NoDefaultExcludes
```

### Publish to nuget.org

```powershell
.\nuget push "artifacts\AddStoredProcedure.1.0.8.nupkg" `
  -ApiKey YOUR_API_KEY `
  -Source https://api.nuget.org/v3/index.json
```

> Get your API key from https://www.nuget.org/account/apikeys

### Unlist a version

```powershell
.\nuget delete AddStoredProcedure 1.0.8 `
  -ApiKey YOUR_API_KEY `
  -Source https://api.nuget.org/v3/index.json
```

> Unlisting hides the package from search but does not delete it. Existing installs and direct version references still work.

---

## Troubleshooting

### `add-storedprocedure` is not recognized after install

The `init.ps1` did not run. This can happen on upgrades. Fix:

```powershell
Uninstall-Package AddStoredProcedure -ProjectName YourSolution.Infrastructure
Install-Package AddStoredProcedure -Version 1.0.8 -ProjectName YourSolution.Infrastructure
```

If the error persists, manually dot-source the function:

```powershell
. "C:\path\to\packages\AddStoredProcedure.1.0.8\tools\Add-StoredProcedure.ps1"
```

---

### `Cannot overwrite variable DTE because it is read-only`

You are running an older version of the script (`1.0.6` or earlier) that is still loaded in memory from a previous session. Reload the correct version:

```powershell
. "C:\path\to\packages\AddStoredProcedure.1.0.8\tools\Add-StoredProcedure.ps1"
```

---

### `Could not install package — no compatible framework`

Your package is missing the `lib\net481\_._` compatibility shim. Make sure the file exists on disk:

```powershell
New-Item -ItemType Directory -Path "lib\net481" -Force
New-Item -Path "lib\net481\_._" -ItemType File -Force
```

Then rebuild and reinstall.

---

### Package failed to uninstall — persists after restart

Manually clean up:

1. Close Visual Studio
2. Delete the package folder:
   ```powershell
   Remove-Item "C:\path\to\packages\AddStoredProcedure.1.0.x" -Recurse -Force
   ```
3. Remove the entry from `packages.config`:
   ```xml
   <package id="AddStoredProcedure" version="1.0.x" targetFramework="net481" />
   ```
4. Remove any related `<Import>` line from your `.csproj`
5. Reopen Visual Studio

---

### `init.ps1` runs but command is still not found

PMC executed `init.ps1` in a child scope. Dot-source manually as a workaround:

```powershell
. "C:\path\to\packages\AddStoredProcedure.1.0.8\tools\Add-StoredProcedure.ps1"
```

---

## Author

**brynjmsdlnn**

