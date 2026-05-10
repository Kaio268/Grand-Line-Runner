$ErrorActionPreference = "Stop"

$roots = @(
	"src/StarterPlayer",
	"src/StarterGui",
	"src/ReplicatedStorage/UI",
	"src/ReplicatedFirst"
) | Where-Object { Test-Path -LiteralPath $_ }

$patterns = @(
	'Text\s*=.*Brainrot',
	'PlaceholderText\s*=.*Brainrot',
	'ActionText\s*=.*Brainrot',
	'ObjectText\s*=.*Brainrot',
	'Local_SendPopUp.*Brainrot',
	'Server_SendPopUp.*Brainrot',
	'hideGui\(.*Brainrot'
)

if ($roots.Count -eq 0) {
	Write-Output "[BrainrotTextGuard] no client/UI roots found"
	exit 0
}

$matches = Get-ChildItem -Path $roots -Recurse -Include *.lua |
	Select-String -Pattern $patterns

if ($matches) {
	Write-Output "[BrainrotTextGuard] player-facing Brainrot candidates found:"
	$matches | ForEach-Object {
		Write-Output ("{0}:{1}: {2}" -f $_.Path, $_.LineNumber, ($_.Line.Trim()))
	}
} else {
	Write-Output "[BrainrotTextGuard] no player-facing Brainrot string candidates found"
}

exit 0
