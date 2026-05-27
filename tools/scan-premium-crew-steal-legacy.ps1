$ErrorActionPreference = "Stop"

$roots = @(
	"src",
	"build.rbxlx",
	"build-test.rbxlx"
) | Where-Object { Test-Path -LiteralPath $_ }

$legacyCodePatterns = @(
	'StealCrewMemberProduct',
	'STEAL_PRODUCTS',
	'TransferStandCrewMember',
	'StealOwnerUserId',
	'StealStandName',
	'StealCrewMemberName',
	'StealCrewMemberInstanceId',
	'StealProductId',
	'StealTime',
	'AllowNonOwnerCrewStealPrompts'
)

$legacyProductIdPatterns = @(
	'3512126073',
	'3512126373',
	'3512127278',
	'3512127790',
	'3512128038',
	'3512128716'
)

if ($roots.Count -eq 0) {
	Write-Output "[PremiumCrewStealLegacyGuard] no target roots found"
	exit 0
}

$files = foreach ($root in $roots) {
	if (Test-Path -LiteralPath $root -PathType Leaf) {
		Get-Item -LiteralPath $root
	} else {
		Get-ChildItem -Path $root -Recurse -Include *.lua,*.rbxlx
	}
}

$codeMatches = $files | Select-String -Pattern $legacyCodePatterns
$productFiles = Get-ChildItem -Path "src" -Recurse -Include *.lua
$productMatches = $productFiles | Select-String -Pattern $legacyProductIdPatterns | Where-Object {
	$_.Path -notlike "*src\ReplicatedStorage\Modules\Configs\Monetization.lua"
}

if ($codeMatches -or $productMatches) {
	Write-Output "[PremiumCrewStealLegacyGuard] legacy premium steal code or product IDs found:"
	@($codeMatches + $productMatches) | ForEach-Object {
		Write-Output ("{0}:{1}: {2}" -f $_.Path, $_.LineNumber, ($_.Line.Trim()))
	}
	exit 1
}

Write-Output "[PremiumCrewStealLegacyGuard] no legacy premium steal code found"
exit 0
