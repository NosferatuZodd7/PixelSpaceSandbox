# Runs the headless checks on Windows and fails if anything is wrong:
#   1. imports the project (fonts, textures, translations) — twice, because on a
#      fresh checkout the first pass reports the not-yet-imported translations
#      the project settings point to; only the second pass is checked, and an
#      asset that really fails to import fails again there;
#   2. runs every test (tests/run_tests.gd);
#   3. runs the game itself for a few hundred frames;
#   4. fails if Godot printed any error or warning in any step.
#
# Usage:
#   powershell -File tools\run_tests.ps1 [--filter=<text>]
#   $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $TestArgs)

$Godot = if ($env:GODOT) { $env:GODOT } else { "godot" }
$Root = Split-Path -Parent $PSScriptRoot
$Logs = Join-Path $Root "tests\output"
New-Item -ItemType Directory -Force -Path $Logs | Out-Null
$failed = $false

function Invoke-Step([string] $Name, [string[]] $Arguments) {
	Write-Host "== $Name"
	$log = Join-Path $Logs "$Name.log"
	& $Godot @Arguments *> $log
	if ($LASTEXITCODE -ne 0) {
		Write-Host "   exit code $LASTEXITCODE"
		$script:failed = $true
	}
}

Invoke-Step "import-first-pass" @("--headless", "--path", $Root, "--import")
Invoke-Step "import" @("--headless", "--path", $Root, "--import")
Invoke-Step "tests" (@("--headless", "--path", $Root, "--script", "res://tests/run_tests.gd", "--") + $TestArgs)
Select-String -Path (Join-Path $Logs "tests.log") -Pattern '^(PASS|FAIL|        )|passed,' | ForEach-Object { $_.Line }
Invoke-Step "game" @("--headless", "--path", $Root, "--quit-after", "300")

$pattern = '(^|[^A-Z_])(ERROR|WARNING):|SCRIPT ERROR|USER ERROR|USER WARNING'
$checked = @("import.log", "tests.log", "game.log") | ForEach-Object { Join-Path $Logs $_ }
$problems = Get-ChildItem -Path $checked | Select-String -Pattern $pattern -CaseSensitive
if ($problems) {
	Write-Host "== Godot reported errors or warnings:"
	$problems | ForEach-Object { Write-Host $_ }
	$failed = $true
}

if ($failed) {
	Write-Host "== FAILED (logs in tests\output\)"
	exit 1
}
Write-Host "== All checks passed"
