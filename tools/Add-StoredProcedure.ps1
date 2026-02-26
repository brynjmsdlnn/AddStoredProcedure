function global:Add-StoredProcedure {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$false)] [switch]$Help,
        [Parameter(Mandatory=$false)] [string]$Name,
        [Parameter(Mandatory=$false)] [string]$Schema,
        [Parameter(Mandatory=$true)] [string]$Table,
        [Parameter(Mandatory=$false)] [string]$Author,
        [Parameter(Mandatory=$false)] [switch]$Anon
    )

    # ----------------------------- 
    # Help
    # -----------------------------
    if ($Help) {
        Write-Host @"
Add-StoredProcedure -Name <string> -Schema <string> -Table <string> [-Author <string>] [-Anon]

Parameters:
  -Name     Required. Name of the stored procedure.
  -Schema   Required. Database schema (e.g., dbo, Admin).
  -Table    Required. Logical grouping folder inside schema.
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
    if (-not $Table)  { Write-Error "-Table is required.";  return }

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
    $folder = Join-Path $projectPath "Database\StoredProcedures\$Schema\$Table"

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
        # Register as EmbeddedResource in .csproj via DTE
        # -----------------------------
        # Note: DTE tracks the project item properties natively
        # 3 = EmbeddedResource
        $projectItem = $migrationProject.ProjectItems.AddFromFile($sqlFilePath)
        if ($projectItem) {
            $projectItem.Properties.Item("BuildAction").Value = 3
        }

        Write-Host "Created stored procedure file at: $sqlFilePath"
        Write-Host "Registered as EmbeddedResource in: $($migrationProject.FullName)"
    }
}