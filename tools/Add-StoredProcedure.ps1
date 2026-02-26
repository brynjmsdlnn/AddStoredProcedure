function Add-StoredProcedure {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$false)] [switch]$Help,
        [Parameter(Mandatory=$false)] [string]$Name,
        [Parameter(Mandatory=$false)] [string]$Schema,
        [Parameter(Mandatory=$false)] [string]$Module,
        [Parameter(Mandatory=$false)] [string]$Author,
        [Parameter(Mandatory=$false)] [switch]$Anon
    )

    # ----------------------------- 
    # Help
    # -----------------------------
    if ($Help) {
        Write-Host @"
Add-StoredProcedure -Name <string> -Schema <string> [-Module <string>] [-Author <string>] [-Anon]

Parameters:
  -Name     Required. Name of the stored procedure.
  -Schema   Required. Database schema (e.g., WIRE, Admin).
  -Module   Optional. Logical grouping folder. Defaults to schema name.
  -Author   Optional. Explicit author name. Overrides smart detection.
  -Anon     Optional switch. Forces author to solution name.
  -Help     Optional switch. Show this usage info.

Behavior:
  - Default author detection: GitHub/Azure DevOps username -> Git config -> solution name
  - EF-style timestamp prefix: yyyyMMddHHmmss
  - SP files are created in Infrastructure project under Database\StoredProcedures\
"@
        return
    }

    # ----------------------------- 
    # Validate required params manually
    # -----------------------------
    if (-not $Name)   { Write-Error "-Name is required.";   return }
    if (-not $Schema) { Write-Error "-Schema is required."; return }

    if (-not $Module) { $Module = $Schema }

    # ----------------------------- 
    # Recursive project helper
    # -----------------------------
    function Get-AllProjects($projects) {
        foreach ($proj in $projects) {
            # GUID for solution folders
            if ($proj.Kind -eq "{66A26720-8FB5-11D2-AA7E-00C04F688DDE}") {
                Get-AllProjects $proj.ProjectItems | ForEach-Object { $_ }
            } else {
                $proj
            }
        }
    }

    # ----------------------------- 
    # Detect Infrastructure project with Migrations folder
    # FIX: renamed $dte -> $dteInstance to avoid clashing with PMC's read-only $DTE variable
    # -----------------------------
    $dteInstance = Get-Variable -Name DTE -ValueOnly -ErrorAction SilentlyContinue
    if (-not $dteInstance) { Write-Error "Cannot find DTE. Make sure this is running in PMC."; return }

    $solution = $dteInstance.Solution
    if (-not $solution.IsOpen) { Write-Error "No solution is open."; return }

    $migrationProject = $null
    foreach ($proj in (Get-AllProjects $solution.Projects)) {
        $projDir = Split-Path $proj.FullName
        if (Test-Path (Join-Path $projDir "Migrations")) {
            $migrationProject = $proj
            break
        }
    }

    if (-not $migrationProject) {
        Write-Error "Cannot find a project with a Migrations folder in the solution."
        return
    }

    $projectPath = Split-Path $migrationProject.FullName
    $folder = Join-Path $projectPath "Database\StoredProcedures\$Module"

    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
    }

    # ----------------------------- 
    # EF-style timestamp prefix
    # -----------------------------
    $timestamp   = Get-Date -Format "yyyyMMddHHmmss"
    $fileName    = "${timestamp}_$Name.sql"
    $sqlFilePath = Join-Path $folder $fileName

    if (Test-Path $sqlFilePath) {
        Write-Host "Stored procedure file already exists: $sqlFilePath"
        return
    }

    # ----------------------------- 
    # Determine Author
    # -----------------------------
    if ($Anon) {
        $Author = $solution.Name
    } elseif (-not $Author) {
        $gitUser = & git config user.name 2>&1
        if ($LASTEXITCODE -ne 0) { $gitUser = $null }

        if ($env:GITHUB_ACTOR) {
            $Author = $env:GITHUB_ACTOR
        } elseif ($env:BUILD_REQUESTEDFOR) {
            $Author = $env:BUILD_REQUESTEDFOR
        } elseif ($gitUser) {
            $Author = $gitUser.Trim()
        } else {
            $Author = $solution.Name
        }
    }

    $scriptDate = Get-Date -Format "MM/dd/yyyy"

    # ----------------------------- 
    # SP header comment
    # -----------------------------
    $header = @"
-- =============================================
-- Author:      $Author
-- Object:      StoredProcedure [$Schema].[$Name]
-- Script date: $scriptDate
-- Description:
-- =============================================

"@

    # ----------------------------- 
    # SP template body
    # -----------------------------
    $body = @"
CREATE OR ALTER PROCEDURE [$Schema].[$Name]
AS
BEGIN
    SET NOCOUNT ON;

    -- TODO: Add procedure logic

END
"@

    # ----------------------------- 
    # Write file (BOM-safe UTF-8)
    # -----------------------------
    $content   = $header + $body
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if ($PSCmdlet.ShouldProcess($sqlFilePath, "Create stored procedure file")) {
        [System.IO.File]::WriteAllText($sqlFilePath, $content, $utf8NoBom)

        # ----------------------------- 
        # Register as EmbeddedResource in .csproj
        # -----------------------------
        $csprojPath = $migrationProject.FullName
        $csprojContent = [System.IO.File]::ReadAllText($csprojPath)

        # Relative path for the csproj entry (e.g. Database\StoredProcedures\WIRE\Users\timestamp_Name.sql)
        $relativePath = "Database\StoredProcedures\$Module\$fileName"

        # The new EmbeddedResource line
        $newEntry = "    <EmbeddedResource Include=""$relativePath"" />"

        # Comment header for this Schema\Module group
        $groupComment = "    <!-- Stored Procedures - $Schema/$Module -->"

        if ($csprojContent -match [regex]::Escape($groupComment)) {
            # Group comment already exists — insert new entry after the last entry in that group
            $pattern = "(?<=$([regex]::Escape($groupComment))[\s\S]*?<EmbeddedResource Include=""Database\\StoredProcedures\\$([regex]::Escape("$Schema\$Module"))\\[^""]*"" \/>)"
            if ($csprojContent -match $pattern) {
                $csprojContent = $csprojContent -replace $pattern, "`$0`n$newEntry"
            } else {
                # Comment exists but no entries yet — insert after comment line
                $csprojContent = $csprojContent -replace [regex]::Escape($groupComment), "$groupComment`n$newEntry"
            }
        } else {
            # No group for this Schema\Module yet — find the closing </ItemGroup> or last EmbeddedResource and append a new group
            $insertBlock = "$groupComment`n$newEntry"
            if ($csprojContent -match '([ \t]*<EmbeddedResource Include="Database\\StoredProcedures\\[^"]*" \/>[\r\n]+)([ \t]*<!--)') {
                # Insert before the next group comment
                $csprojContent = $csprojContent -replace '([ \t]*<EmbeddedResource Include="Database\\StoredProcedures\\[^"]*" \/>[\r\n]+)([ \t]*<!--)', "`$1$insertBlock`n`$2"
            } else {
                # Fallback — insert before </ItemGroup> that contains EmbeddedResource entries
                $csprojContent = $csprojContent -replace '(\s*</ItemGroup>)', "`n$insertBlock`$1"
            }
        }

        [System.IO.File]::WriteAllText($csprojPath, $csprojContent, $utf8NoBom)

        Write-Host "Created stored procedure file at: $sqlFilePath"
        Write-Host "Registered as EmbeddedResource in: $csprojPath"
    }
}