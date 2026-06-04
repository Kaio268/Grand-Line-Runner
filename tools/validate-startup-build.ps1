param(
	[string[]] $ArtifactPath = @()
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$oldBootPatterns = @(
	'script:GetAttribute("Data_Key")',
	"Data_Key attribute"
)

$sourceChecks = @(
	@{
		Path = "src/ServerScriptService/Data/DataManager/init.lua"
		Pattern = "DataEnvironment.ResolveDataKey"
		Label = "DataManager resolves datastore keys through DataEnvironment"
	},
	@{
		Path = "src/ServerScriptService/Data/DataEnvironment.lua"
		Pattern = "DataKeySecrets"
		Label = "DataEnvironment requires DataKeySecrets"
	}
)

$defaultArtifacts = @(
	"build.rbxlx",
	"afk-build.rbxlx",
	"build-test.rbxlx"
)

function Write-Matches($header, $matches) {
	Write-Output $header
	$matches | ForEach-Object {
		Write-Output ("{0}:{1}: {2}" -f $_.Path, $_.LineNumber, ($_.Line.Trim()))
	}
}

Push-Location -LiteralPath $repoRoot
try {
	$errors = New-Object System.Collections.Generic.List[string]

	foreach ($check in $sourceChecks) {
		if (-not (Test-Path -LiteralPath $check.Path -PathType Leaf)) {
			$errors.Add("[StartupBuildGuard] missing source file for check: $($check.Path)")
			continue
		}

		$match = Select-String -LiteralPath $check.Path -SimpleMatch -Pattern $check.Pattern -Quiet
		if (-not $match) {
			$errors.Add("[StartupBuildGuard] source check failed: $($check.Label)")
		}
	}

	$sourceFiles = @(
		"src/ServerScriptService/Data/DataManager/init.lua",
		"src/ServerScriptService/Data/DataEnvironment.lua"
	) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

	$oldSourceMatches = if ($sourceFiles.Count -gt 0) {
		Select-String -LiteralPath $sourceFiles -SimpleMatch -Pattern $oldBootPatterns
	} else {
		@()
	}

	if ($oldSourceMatches) {
		Write-Matches "[StartupBuildGuard] old Data_Key source boot code found:" $oldSourceMatches
		exit 1
	}

	if ($errors.Count -gt 0) {
		$errors | ForEach-Object { Write-Output $_ }
		exit 1
	}

	$artifactCandidates = if ($ArtifactPath.Count -gt 0) { $ArtifactPath } else { $defaultArtifacts }
	$artifacts = @()
	foreach ($artifact in $artifactCandidates) {
		if (Test-Path -LiteralPath $artifact -PathType Leaf) {
			$artifacts += Get-Item -LiteralPath $artifact
		} else {
			Write-Warning "[StartupBuildGuard] artifact not found, skipped: $artifact"
		}
	}

	if ($artifacts.Count -eq 0) {
		Write-Output "[StartupBuildGuard] source boot path is current; no artifacts found to scan"
		exit 0
	}

	$oldArtifactMatches = Select-String -LiteralPath $artifacts.FullName -SimpleMatch -Pattern $oldBootPatterns
	if ($oldArtifactMatches) {
		Write-Matches "[StartupBuildGuard] stale Data_Key boot code found in build artifacts:" $oldArtifactMatches
		exit 1
	}

	foreach ($artifact in $artifacts) {
		foreach ($pattern in @("ResolveDataKey", "DataKeySecrets")) {
			$found = Select-String -LiteralPath $artifact.FullName -SimpleMatch -Pattern $pattern -Quiet
			if (-not $found) {
				Write-Output ("[StartupBuildGuard] artifact missing current boot marker {0}: {1}" -f $pattern, $artifact.FullName)
				exit 1
			}
		}
	}

	Write-Output "[StartupBuildGuard] source and scanned artifacts use DataEnvironment/DataKeySecrets boot path"
	exit 0
} finally {
	Pop-Location
}
