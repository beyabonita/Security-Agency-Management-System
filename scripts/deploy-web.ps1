[CmdletBinding()]
param(
    [string]$Project = 'security-agency-management-system',
    [string]$Scope = 'codex-a9d1'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$webSource = Join-Path $repositoryRoot 'web'
$tempRoot = [System.IO.Path]::GetTempPath()
$releaseDirectory = Join-Path $tempRoot ("security-agency-management-system-release-" + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath (Join-Path $webSource 'vercel.json'))) {
    throw "Could not find the web portal at '$webSource'."
}

$releaseItems = @(
    'admin',
    'assets',
    'css',
    'icons',
    'inspector',
    'it-admin',
    'js',
    'staff',
    'system-access-7d92a4',
    '.vercelignore',
    'favicon.png',
    'index.html',
    'manifest.json',
    'vercel.json'
)

New-Item -ItemType Directory -Path $releaseDirectory | Out-Null

try {
    foreach ($item in $releaseItems) {
        $source = Join-Path $webSource $item
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Required web release item is missing: '$source'."
        }

        Copy-Item -LiteralPath $source -Destination $releaseDirectory -Recurse -Force
    }

    Push-Location $releaseDirectory
    try {
        # This clean, non-Git directory avoids Vercel rejecting the local
        # development Git author when the account is not a Vercel team member.
        & npx --yes vercel@59.5.0 link --yes --project $Project --scope $Scope
        if ($LASTEXITCODE -ne 0) {
            throw 'Vercel project linking failed.'
        }

        & npx --yes vercel@59.5.0 --prod --yes --scope $Scope
        if ($LASTEXITCODE -ne 0) {
            throw 'Vercel production deployment failed.'
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    $normalizedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $normalizedReleaseDirectory = [System.IO.Path]::GetFullPath($releaseDirectory)
    if (
        $normalizedReleaseDirectory.StartsWith($normalizedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $releaseDirectory)
    ) {
        try {
            Remove-Item -LiteralPath $releaseDirectory -Recurse -Force -ErrorAction Stop
        }
        catch {
            # Vercel can briefly retain an upload handle after reporting a
            # successful deployment. The release is already complete, so do
            # not turn that harmless temporary-directory cleanup delay into a
            # failed deployment.
            Write-Warning "Deployment completed, but the temporary release directory could not be removed yet: '$releaseDirectory'."
        }
    }
}
