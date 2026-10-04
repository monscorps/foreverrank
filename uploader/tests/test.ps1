# Tests for QuestBank-Uploader.ps1, run in Docker by: python3 tools/build_uploader.py --test
# (pwsh 7.4 in mcr.microsoft.com/dotnet/sdk:8.0, no network). They work on the built zip as a player
# extracts it, define the script's own functions from its syntax tree, and stand in for what only
# Windows has: shortcuts, the tray, scheduled tasks, the folder picker, Y/N answers, game versions,
# running games and the upload (section I runs the real upload against a listener in the container).
# The tray and the Status window themselves (WinForms) can't run here.
$ErrorActionPreference = "Stop"
$PSStyle.OutputRendering = "PlainText"
$script:fails = 0; $script:checks = 0
function Check([string]$name, $cond) {
  $script:checks++
  if ($cond) { "  ok    " + $name } else { $script:fails++; "  FAIL  " + $name }
}
function Show([string]$title, [string]$text) {
  "  --- " + $title
  foreach ($l in ($text -split "`n")) { if ($l.Trim()) { "  | " + $l.TrimEnd() } }
}

# ---- the download, extracted as a player would ----------------------------------------------
Expand-Archive -LiteralPath /w/QuestBank-Uploader.zip -DestinationPath /tmp/dl
$src = "/tmp/dl/QuestBank Uploader/QuestBank-Uploader.ps1"
$BV = ((Get-Content "/tmp/dl/QuestBank/QuestBank.toc" | Where-Object { $_ -match '^## Version:' }) -replace '^## Version:\s*', '').Trim()
"bundled QuestBank: " + $BV

"=== static checks"
$bytes = [System.IO.File]::ReadAllBytes($src)
Check "the .ps1 is plain ASCII" (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0)
foreach ($n in "Install.bat", "Uninstall.bat", "QuestBank-Uploader.ps1", "README.txt") {
  $t = [System.IO.File]::ReadAllText("/tmp/dl/QuestBank Uploader/" + $n)
  Check ($n + " has CRLF line ends only") (($t -split "`r`n").Count -gt 3 -and -not ($t -replace "`r`n", "").Contains("`n"))
}
$text = [System.IO.File]::ReadAllText($src)
$code = @(($text -split "`r`n") | Where-Object { -not $_.TrimStart().StartsWith("#") })
Check "no version number written into the script's code" (@($code | Where-Object { $_ -match '\b\d+\.\d+\.\d+\b' }).Count -eq 0)
# every ForeverProbe mention sits in the legacy block, the migration/uninstall code or the one Status line
$fpLines = @(($text -split "`r`n") | Where-Object { $_ -match 'ForeverProbe' })
"  ForeverProbe lines in the script: " + $fpLines.Count
foreach ($l in $fpLines) { "    " + $l.Trim() }
$readme = [System.IO.File]::ReadAllText("/tmp/dl/QuestBank Uploader/README.txt")
Check "README never says ForeverProbe, Sync or a version" (-not ($readme -match 'ForeverProbe|Sync|\d+\.\d+\.\d+'))

$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tok, [ref]$err)
Check "parses without errors" ($err.Count -eq 0)
foreach ($e in $err) { "  line " + $e.Extent.StartLineNumber + ": " + $e.Message }
if ($err.Count -gt 0) { exit 1 }

# ---- the script's own settings and functions -------------------------------------------------
$env:APPDATA = "/tmp/appdata"; $env:USERPROFILE = "/tmp/home"; $env:OneDrive = "/tmp/home/OneDrive"
$funcs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Parent -eq $ast.EndBlock }, $false))
$firstFunc = ($funcs | ForEach-Object { $_.Extent.StartLineNumber } | Measure-Object -Minimum).Minimum
foreach ($st in $ast.EndBlock.Statements) {
  if ($st -is [System.Management.Automation.Language.AssignmentStatementAst] -and $st.Extent.StartLineNumber -lt $firstFunc) { . ([scriptblock]::Create($st.Extent.Text)) }
}
foreach ($f in $funcs) { . ([scriptblock]::Create($f.Extent.Text)) }
"functions: " + $funcs.Count
$Self = $src; $WowPath = ""; $Endpoint = ""; $Tray = $false
Check "AppDir is %APPDATA%\QuestBank Uploader" ($AppDir -eq "/tmp/appdata/QuestBank Uploader")

# ---- mocks for what only Windows has -----------------------------------------------------------
$script:calls = New-Object System.Collections.ArrayList
function Note($s) { [void]$script:calls.Add([string]$s) }
function Get-ShellFolder([string]$name) {
  switch ($name) { "Startup" { return "/tmp/home/Startup" } "Programs" { return "/tmp/home/Programs" } "Desktop" { return $script:shellDesktop } }
  return ""
}
function New-Shortcut([string]$path, [string]$arguments, [string]$description) { Set-Content -LiteralPath $path -Value ($arguments + "`n" + $description); Note ("lnk " + $path) }
function Stop-Tray { Note "stop-tray" }
function Test-TrayRunning([string]$mutexName) { return ($script:runningMutex -contains $mutexName) }
function Start-Tray { Note "start-tray" }
function Remove-LegacyTask { Note "legacy-task"; return [bool]$script:legacyTask }
function Ask-YesNo([string]$question) {
  Note ("ask " + $question.Trim())
  $a = $null
  if ($script:answers.Count -gt 0) { $a = $script:answers[0]; $script:answers = @($script:answers | Select-Object -Skip 1) }
  return ($a -eq "y")
}
function Get-GameInterface($game) { return $script:ifaces[(Split-Path $game -Leaf)] }
function Get-WowStart($game) { return $script:wowStart[(Split-Path $game -Leaf)] }
function Pick-WowFolder { Note "pick"; return $script:pickAnswer }
function Send-File {
  param([string]$Url, [string]$File)
  Note ("post " + $Url + " " + $File)
  if ($script:sendFails) { throw $script:sendFails }
  $script:posts++
  return [pscustomobject]@{ ok = $true; id = 100 + $script:posts; kind = "questbank-savedvars"; summary = [pscustomobject]@{ quests = 3 } }
}

# ---- a fake machine -------------------------------------------------------------------------------
$beta = "/tmp/wow/_classic_beta_"; $era = "/tmp/wow/_classic_era_"; $retail = "/tmp/wow/_retail_"
$betaSV = "$beta/WTF/Account/ACC1/SavedVariables/QuestBank.lua"
function Save-Lua($path, $ver, [int]$iface = 16001, [string]$extra = "") {
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  # the game writes no indentation; versions sit in the snapshots, the discoveries and the login note;
  # $extra goes into the game block (["imported"] = true,) or the settings (["noteGame"] = false,)
  Set-Content -LiteralPath $path -Value ("QuestBankDB = {`n[`"chars`"] = {`n[`"Old-Realm`"] = {`n[`"version`"] = `"3.1.1`",`n},`n[`"New-Realm`"] = {`n[`"version`"] = `"" + $ver + "`",`n},`n},`n[`"disc`"] = {`n[`"ver`"] = `"" + $ver + "`",`n[`"build`"] = `"70170`",`n[`"iface`"] = " + $iface + ",`n},`n[`"diag`"] = {`n[`"addons`"] = {`n[`"iface`"] = " + $iface + ",`n[`"probe`"] = {`n[`"iface`"] = 16001,`n},`n},`n},`n[`"game`"] = {`n[`"client`"] = `"1.60.1`",`n[`"iface`"] = 16001,`n" + $extra + "`n},`n}")
}
function Put-Toc($dir, $ver) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Set-Content -LiteralPath (Join-Path $dir "QuestBank.toc") -Value ("## Interface: 16001, 11507`n## Title: QuestBank`n## Version: " + $ver + "`n`nCore.lua")
}
function Toc-Ver($dir) { $l = Get-Content -LiteralPath (Join-Path $dir "QuestBank.toc") | Where-Object { $_ -match '^## Version:' }; return ($l -replace '^## Version:\s*', '').Trim() }
function New-Wow {
  Remove-Item -Recurse -Force /tmp/wow -ErrorAction SilentlyContinue
  foreach ($g in $beta, $era, $retail) { New-Item -ItemType Directory -Force -Path "$g/Interface/AddOns" | Out-Null }
  Save-Lua $betaSV "3.5.10"
  # a character's own SavedVariables: never watched
  Save-Lua "$beta/WTF/Account/ACC1/SomeRealm/SomeChar/SavedVariables/QuestBank.lua" "3.5.10"
  New-Item -ItemType Directory -Force -Path "$beta/Interface/AddOns/ForeverProbe", "$beta/Interface/AddOns/Questie" | Out-Null
  Set-Content "$beta/Interface/AddOns/ForeverProbe/ForeverProbe.toc" "## Version: 0.4.8"
  Set-Content "$beta/WTF/Account/ACC1/SavedVariables/ForeverProbe.lua" "ForeverProbeDB = {}"
  Set-Content "$beta/Interface/AddOns/Questie/Questie.toc" "## Version: 9.9.9"
}
function Reset-App {
  Remove-Item -Recurse -Force /tmp/appdata, /tmp/home -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path /tmp/appdata, /tmp/home/Startup, /tmp/home/Programs, /tmp/home/Desktop, /tmp/home/OneDrive/Desktop | Out-Null
  $script:shellDesktop = "/tmp/home/Desktop"
  $script:calls.Clear(); $script:answers = @(); $script:legacyTask = $false; $script:runningMutex = @()
  $script:ifaces = @{ "_classic_beta_" = 16001; "_classic_era_" = 11507; "_retail_" = 110200 }
  $script:wowStart = @{}; $script:pickAnswer = ""; $script:posts = 0; $script:sendFails = $null
  $script:failedLast = $null; $script:fileState = $null; $script:lastWatched = $null
  $script:WowPath = ""; $script:Endpoint = ""; $script:Self = $src
}
function Cfg { return (Get-Content -LiteralPath $CfgFile -Raw | ConvertFrom-Json) }
function Hash($p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Asked { return @($script:calls | Where-Object { $_ -like "ask *" }) }
function Run-Install { return (Install-Uploader 6>&1 | Out-String) }

"`n=== A. fresh install: no settings, WoW not in the usual places, picks the folder"
Reset-App; New-Wow
$script:pickAnswer = "/tmp/wow"; $script:answers = @("y", "n")
$o = Run-Install; Show "install" $o
$c = Cfg
Check "asked for the WoW folder" ($script:calls -contains "pick")
Check "config keeps the picked folder" ($c.wowPath -eq "/tmp/wow")
Check "config stores no endpoint" (-not $c.PSObject.Properties["endpoint"])
Check "config starts with nothing sent" (@($c.sent.PSObject.Properties).Count -eq 0)
Check "script copied to AppDir" ((Hash "$AppDir/QuestBank-Uploader.ps1") -eq (Hash $src))
Check "icon copied to AppDir" (Test-Path "$AppDir/QuestBank.ico")
$lnkS = "/tmp/home/Startup/QuestBank Uploader.lnk"
Check "Startup shortcut runs the tray, path quoted" ((Test-Path $lnkS) -and ((Get-Content $lnkS -Raw) -match '-File "/tmp/appdata/QuestBank Uploader/QuestBank-Uploader.ps1" -Tray'))
Check "Start menu shortcut opens Status" ((Get-Content "/tmp/home/Programs/QuestBank Uploader.lnk" -Raw) -match '-Status')
Check "Desktop shortcut opens Status" ((Get-Content "/tmp/home/Desktop/QuestBank Uploader.lnk" -Raw) -match '-Status')
Check "no second copy on a OneDrive Desktop that isn't the shell's" (-not (Test-Path "/tmp/home/OneDrive/Desktop/QuestBank Uploader.lnk"))
Check "asked about _classic_beta_ and _classic_era_ only (not _retail_)" ((Asked).Count -eq 2 -and -not ((Asked) -match '_retail_'))
Check "QuestBank put in _classic_beta_" ((Toc-Ver "$beta/Interface/AddOns/QuestBank") -eq $BV)
Check "every bundled file is there" ((Get-ChildItem /tmp/dl/QuestBank).Count -eq (Get-ChildItem "$beta/Interface/AddOns/QuestBank").Count)
Check "_classic_era_ left without QuestBank (answered N)" (-not (Test-Path "$era/Interface/AddOns/QuestBank"))
Check "_retail_ untouched" (-not (Test-Path "$retail/Interface/AddOns/QuestBank"))
Check "no backup and no staging folder on a fresh install" (-not (Test-Path "$beta/Interface/QuestBank.bak") -and -not (Test-Path "$beta/Interface/QuestBank.new"))
Check "other addons untouched" ((Test-Path "$beta/Interface/AddOns/Questie/Questie.toc") -and (Test-Path "$beta/Interface/AddOns/ForeverProbe/ForeverProbe.toc"))
Check "ForeverProbe folder: keep it until QuestBank has run (no imported mark yet)" ($o -match '_classic_beta_: keep the ForeverProbe folder in Interface\\AddOns for now: QuestBank takes over its notes the next time you log in with both addons switched on, then says in chat that the folder can go\.' -and -not ($o -match 'no longer needed'))
Check "_retail_ named as skipped" ($o -match "_retail_: skipped, its game can't load QuestBank\.")
Check "the N for _classic_era_ is kept" (@((Cfg).declined) -contains "/tmp/wow/_classic_era_" -and @((Cfg).declined).Count -eq 1)
Check "no restart note (WoW not running)" (-not ($o -match 'restart'))
Check "tray stopped before and started after" ($script:calls.IndexOf("stop-tray") -ge 0 -and $script:calls.IndexOf("stop-tray") -lt $script:calls.IndexOf("start-tray"))
Check "watching the account file only" ($o -match [regex]::Escape("Watching $betaSV") -and -not ($o -match 'SomeChar'))
Check "no ForeverProbe Sync message on a machine that never had it" (-not ($o -match 'Replaced'))
$r1 = Send-Changes; "  send 1: " + $r1
Check "first pass sends it" ($r1 -eq "Sent QuestBank.lua to foreverrank.com." -and $script:posts -eq 1)
Check "to the site's endpoint" (($script:calls -match '^post ') -match [regex]::Escape($DefaultEndpoint))
$r2 = Send-Changes; "  send 2: " + $r2
Check "second pass sends nothing" ($r2 -eq "Nothing new since the last upload." -and $script:posts -eq 1)
$s = Get-StatusText (Read-Config); Show "status" $s
Check "status: WoW folder" ($s -match 'WoW folder: /tmp/wow')
Check "status: installed version" ($s -match ("_classic_beta_: QuestBank " + [regex]::Escape($BV)))
Check "status: ForeverProbe line says keep it for now" ($s -match '   Keep the ForeverProbe folder in Interface\\AddOns for now: QuestBank takes over its notes the next time you log in with both addons switched on' -and -not ($s -match 'no longer needed'))
Check "status: file line" ($s -match 'QuestBank\.lua, account ACC1: \d+ KB, written \d{4}-\d\d-\d\d \d\d:\d\d by QuestBank 3\.5\.10; sent')
Check "status: loads next start (WoW not running)" ($s -match ("QuestBank " + [regex]::Escape($BV) + " loads the next time you start WoW; the last save came from 3\.5\.10\."))
Check "status: no game folder without QuestBank or saves" (-not ($s -match '_classic_era_|_retail_'))
Check "status: last activity lines" ($s -match 'Last activity:' -and $s -match 'sent .*upload #101')

"`n=== B. reinstall keeps the settings"
$hashBefore = (Cfg).sent.$betaSV
$script:calls.Clear(); $script:answers = @("n"); $script:pickAnswer = "/wrong"
$o = Run-Install; Show "install again" $o
$c = Cfg
Check "WoW folder kept, no picker" ($c.wowPath -eq "/tmp/wow" -and -not ($script:calls -contains "pick"))
Check "sent hash kept" ($c.sent.$betaSV -eq $hashBefore -and $hashBefore)
Check "same version copied in fresh, one backup made" ($o -match 'copied in fresh' -and (Toc-Ver "$beta/Interface/QuestBank.bak") -eq $BV)
Check "the folder answered N isn't asked about again" ((Asked).Count -eq 0 -and $o -match '_classic_era_: left without QuestBank, as you chose before\.')
Check "declined list kept by the reinstall" (@((Cfg).declined) -contains "/tmp/wow/_classic_era_")
$r = Send-Changes
Check "nothing re-sent after the reinstall" ($r -eq "Nothing new since the last upload." -and $script:posts -eq 1)
$script:Endpoint = "http://127.0.0.1:8787/api/probe"; $script:answers = @("n")
$o = Run-Install
Check "-Endpoint stores an override" ((Cfg).endpoint -eq "http://127.0.0.1:8787/api/probe")
$script:Endpoint = ""; $script:answers = @("n")
$o = Run-Install
Check "a reinstall keeps the override" ((Cfg).endpoint -eq "http://127.0.0.1:8787/api/probe")
Save-Lua $betaSV "3.5.10"; Add-Content $betaSV "-- changed"
$r = Send-Changes
Check "the override is where it posts" ($r -like "Sent*" -and ($script:calls[-1] -match '^post http://127\.0\.0\.1:8787'))
$script:Endpoint = $DefaultEndpoint; $script:answers = @("n")
$o = Run-Install
Check "-Endpoint with the default clears the override" (-not (Cfg).PSObject.Properties["endpoint"])
$script:Endpoint = ""

"`n=== C. migration from ForeverProbe Sync"
Reset-App; New-Wow
Put-Toc "$beta/Interface/AddOns/QuestBank" "3.5.10"; Set-Content "$beta/Interface/AddOns/QuestBank/Old.lua" "-- gone in the new one"
Put-Toc "$beta/Interface/QuestBank.bak" "3.4.0"; Set-Content "$beta/Interface/QuestBank.bak/older.txt" "x"
New-Item -ItemType Directory -Force -Path $LegacyDir | Out-Null
$fpPath = "$beta/WTF/Account/ACC1/SavedVariables/ForeverProbe.lua"
Set-Content $fpPath "ForeverProbeDB = {}"
@{ endpoint = "https://foreverrank.andustemme.workers.dev/api/probe"; wowPath = "/tmp/wow"; sent = @{ $betaSV = (Hash $betaSV); $fpPath = (Hash $fpPath) } } | ConvertTo-Json | Set-Content "$LegacyDir/config.json"
foreach ($n in "sync.log", "ForeverProbe-Sync.ps1", "ForeverProbe.ico") { Set-Content "$LegacyDir/$n" "old" }
$legacyLnks = @("/tmp/home/Startup", "/tmp/home/Programs", "/tmp/home/Desktop", "/tmp/home/OneDrive/Desktop") | ForEach-Object { "$_/ForeverProbe Sync.lnk" }
foreach ($l in $legacyLnks) { Set-Content $l "old shortcut" }
$script:legacyTask = $true; $script:answers = @("y", "n")
$script:wowStart = @{ "_classic_beta_" = (Get-Date).AddHours(-1) }
$o = Run-Install; Show "install over ForeverProbe Sync" $o
$c = Cfg
Check "its WoW folder came over (no picker)" ($c.wowPath -eq "/tmp/wow" -and -not ($script:calls -contains "pick"))
Check "only the QuestBank.lua hash came over" (@($c.sent.PSObject.Properties).Count -eq 1 -and $c.sent.$betaSV -eq (Hash $betaSV))
Check "its endpoint did not come over" (-not $c.PSObject.Properties["endpoint"])
Check "%APPDATA%\ForeverProbe removed" (-not (Test-Path $LegacyDir))
Check "all four old shortcuts removed (Startup, Start menu, Desktop, OneDrive Desktop)" (@($legacyLnks | Where-Object { Test-Path $_ }).Count -eq 0)
Check "old scheduled task asked to go" ($script:calls -contains "legacy-task")
Check "tray stopped before the old folder went" ($script:calls.IndexOf("stop-tray") -eq 0)
Check "says it replaced ForeverProbe Sync" ($o -match "Replaced ForeverProbe Sync: its tray icon and shortcuts are gone, and what it already sent won't go again\.")
Check "ForeverProbe.lua itself left alone" (Test-Path $fpPath)
Check "update 3.5.10 to bundled" ($o -match ("QuestBank 3\.5\.10 updated to " + [regex]::Escape($BV)) -and (Toc-Ver "$beta/Interface/AddOns/QuestBank") -eq $BV)
Check "old file gone from the new copy" (-not (Test-Path "$beta/Interface/AddOns/QuestBank/Old.lua"))
Check "backup holds the 3.5.10 copy" ((Toc-Ver "$beta/Interface/QuestBank.bak") -eq "3.5.10" -and (Test-Path "$beta/Interface/QuestBank.bak/Old.lua"))
Check "only one backup (the older one replaced)" (-not (Test-Path "$beta/Interface/QuestBank.bak/older.txt") -and @(Get-ChildItem "$beta/Interface" -Directory).Count -eq 2)
Check "no staging folder left" (-not (Test-Path "$beta/Interface/QuestBank.new"))
Check "WoW running: asked before the swap" (((Asked)[0]) -match ('^ask _classic_beta_: WoW is running\. Update QuestBank 3\.5\.10 to ' + [regex]::Escape($BV) + ' now and restart WoW right after\? \(Y/N\)$'))
Check "WoW running: restart note" ($o -match ("WoW is running: restart it to load QuestBank " + [regex]::Escape($BV) + " \(a /reload is not enough\)"))
$r = Send-Changes
Check "nothing re-sent after the move" ($r -eq "Nothing new since the last upload." -and $script:posts -eq 0)
Check "log notes the move without the old name" ((Get-Content $LogFile -Raw) -match "took over the old uploader's settings \(1 sent file\(s\)\)")
$s = Get-StatusText (Read-Config); Show "status, WoW started before the update" $s
Check "status: WoW needs a restart" ($s -match ("WoW needs a restart to load QuestBank " + [regex]::Escape($BV) + " \(a /reload is not enough\); the last save came from 3\.5\.10\."))
$script:wowStart = @{ "_classic_beta_" = (Get-Date).AddMinutes(10) }
$s = Get-StatusText (Read-Config); Show "status, WoW started after the update" $s
Check "status: WoW started after the update: no restart line" (-not ($s -match 'restart|next time you start'))

"`n=== C2. both an old ForeverProbe Sync and our own settings"
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir, $LegacyDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{ "/x/QuestBank.lua" = "AAA" } } | ConvertTo-Json | Set-Content $CfgFile
@{ endpoint = "https://elsewhere.invalid/api"; wowPath = "/elsewhere"; sent = @{ $betaSV = "BBB" } } | ConvertTo-Json | Set-Content "$LegacyDir/config.json"
$script:answers = @("y", "n"); $script:runningMutex = @($LegacyMutex)
$o = Run-Install; Show "install" $o
$c = Cfg
Check "our WoW folder wins" ($c.wowPath -eq "/tmp/wow")
Check "sent lists merged" ($c.sent."/x/QuestBank.lua" -eq "AAA" -and $c.sent.$betaSV -eq "BBB")
Check "a custom old endpoint is not carried" (-not $c.PSObject.Properties["endpoint"])
Check "old tray still running: says how to close it" ($o -match 'The old ForeverProbe Sync icon is still by the clock: right-click it and pick Exit\.')

"`n=== C3. WoW running and the player says not now"
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
Put-Toc "$beta/Interface/AddOns/QuestBank" "3.5.10"
$script:wowStart = @{ "_classic_beta_" = (Get-Date).AddHours(-1) }; $script:answers = @("n", "n")
$o = Run-Install; Show "WoW running, N" $o
Check "N: the running game's QuestBank is left alone" ((Toc-Ver "$beta/Interface/AddOns/QuestBank") -eq "3.5.10" -and -not (Test-Path "$beta/Interface/QuestBank.bak"))
Check "N: says to run Install again once WoW is closed" ($o -match '_classic_beta_: QuestBank 3\.5\.10 left as it is; run Install\.bat again once WoW is closed\.')
Check "N: no restart note" (-not ($o -match 'restart it'))
Check "N to an update isn't remembered as a decline" (-not (Cfg).PSObject.Properties["declined"] -or -not (@((Cfg).declined) -contains "/tmp/wow/_classic_beta_"))
Put-Toc "$beta/Interface/AddOns/QuestBank" $BV
$script:calls.Clear(); $script:answers = @()
$o = Run-Install
Check "same version with WoW running: no question, no restart note" (-not ((Asked) -match 'WoW is running') -and -not ($o -match 'restart it'))

"`n=== D. addon cases"
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
Put-Toc "$beta/Interface/AddOns/QuestBank" "99.0.0"
Put-Toc "$era/Interface/AddOns/QuestBank/QuestBank" "3.5.0"
$script:ifaces["_retail_"] = $null; $script:answers = @("n")
$o = Run-Install; Show "newer stays, deep fixed, unknown game asked" $o
Check "a newer QuestBank stays" ((Toc-Ver "$beta/Interface/AddOns/QuestBank") -eq "99.0.0" -and $o -match '_classic_beta_: QuestBank 99\.0\.0 is newer than this download''s, so it stays\.')
Check "one folder too deep: replaced" ((Toc-Ver "$era/Interface/AddOns/QuestBank") -eq $BV -and $o -match ('_classic_era_: QuestBank 3\.5\.0 updated to ' + [regex]::Escape($BV)))
Check "deep copy kept as the backup" (Test-Path "$era/Interface/QuestBank.bak/QuestBank/QuestBank.toc")
Check "a game whose version can't be read is asked about" (((Asked) -match '_retail_').Count -eq 1)

# a newer QuestBank one folder too deep moves up instead of staying where the game never loads it
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
Put-Toc "$beta/Interface/AddOns/QuestBank/QuestBank" "99.1.0"; Set-Content "$beta/Interface/AddOns/QuestBank/QuestBank/New.lua" "-- only in 99.1.0"
$script:wowStart = @{ "_classic_beta_" = (Get-Date).AddHours(-1) }; $script:answers = @("n")
$o = Run-Install; Show "newer, one folder too deep" $o
Check "deep and newer: moved up into AddOns" ((Toc-Ver "$beta/Interface/AddOns/QuestBank") -eq "99.1.0" -and (Test-Path "$beta/Interface/AddOns/QuestBank/New.lua") -and -not (Test-Path "$beta/Interface/AddOns/QuestBank/QuestBank"))
Check "deep and newer: says so" ($o -match "_classic_beta_: QuestBank 99\.1\.0 \(newer than this download's\) sat one folder too deep; moved up into AddOns")
Check "deep and newer: the folder as it was is the backup" (Test-Path "$beta/Interface/QuestBank.bak/QuestBank/QuestBank.toc")
Check "deep and newer: not asked (the game never loaded it), restart note names its version" (-not ((Asked) -match 'WoW is running') -and $o -match 'restart it to load QuestBank 99\.1\.0 ')
$s = Get-StatusText (Read-Config)
Check "deep and newer: status no longer says it's too deep" ($s -match '_classic_beta_: QuestBank 99\.1\.0' -and -not ($s -match 'too deep'))

# AddOns\QuestBank linked to a checkout: left alone; a linked QuestBank.bak loses only the link
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
Remove-Item -Recurse -Force /tmp/checkout -ErrorAction SilentlyContinue
Put-Toc "/tmp/checkout/QuestBank" "3.5.0"; Set-Content "/tmp/checkout/QuestBank/Work.lua" "-- a tester's work"
New-Item -ItemType SymbolicLink -Path "$beta/Interface/AddOns/QuestBank" -Target "/tmp/checkout/QuestBank" | Out-Null
Put-Toc "$era/Interface/AddOns/QuestBank" "3.5.0"
Put-Toc "/tmp/checkout/OldBak" "3.4.0"; Set-Content "/tmp/checkout/OldBak/Keep.lua" "-- not ours to delete"
New-Item -ItemType SymbolicLink -Path "$era/Interface/QuestBank.bak" -Target "/tmp/checkout/OldBak" | Out-Null
$script:answers = @("n")
$o = Run-Install; Show "linked folders" $o
Check "linked AddOns\QuestBank: left as it is, and said so" ((Test-Link "$beta/Interface/AddOns/QuestBank") -and (Toc-Ver "/tmp/checkout/QuestBank") -eq "3.5.0" -and (Test-Path "/tmp/checkout/QuestBank/Work.lua") -and $o -match '_classic_beta_: AddOns\\QuestBank links to another folder, so it stays as it is\.')
Check "linked QuestBank.bak: only the link went, its folder kept every file" ((Test-Path "/tmp/checkout/OldBak/Keep.lua") -and (Test-Path "/tmp/checkout/OldBak/QuestBank.toc") -and -not (Test-Link "$era/Interface/QuestBank.bak") -and (Toc-Ver "$era/Interface/QuestBank.bak") -eq "3.5.0")
Check "and the update went in beside it" ((Toc-Ver "$era/Interface/AddOns/QuestBank") -eq $BV)

# which game folders are asked about
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
$script:ifaces["_classic_beta_"] = 16100
Save-Lua "$retail/WTF/Account/ACC1/SavedVariables/QuestBank.lua" "3.5.10"
$script:answers = @("n", "n", "n")
$o = Run-Install; Show "a later Forever patch, retail with a QuestBank.lua" $o
Check "a Forever patch the .toc hasn't caught up with is still asked about" (((Asked) -match '_classic_beta_').Count -eq 1)
Check "a game folder with a QuestBank.lua is asked about whatever its game" (((Asked) -match '_retail_').Count -eq 1 -and -not ($o -match 'skipped'))

Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
New-Item -ItemType Directory -Force -Path "$beta/Interface/AddOns/QuestBank-main" | Out-Null
Put-Toc "$beta/Interface/AddOns/QuestBank-main" "3.5.9"
$s = Get-StatusText (Read-Config); Show "status, renamed folder" $s
Check "status: renamed folder explained" ($s -match '_classic_beta_: QuestBank sits in AddOns\\QuestBank-main; the game loads it only from a folder named exactly QuestBank\.')
$script:answers = @("y", "n")
$o = Run-Install; Show "renamed folder" $o
Check "renamed: asked, put in, and told the stray copy can go" ((Toc-Ver "$beta/Interface/AddOns/QuestBank") -eq $BV -and $o -match 'The copy in AddOns\\QuestBank-main is one the game never loaded: you can delete it\.')

# a move that fails half way puts the old QuestBank back
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
Put-Toc "$beta/Interface/AddOns/QuestBank" "3.5.10"
$script:failMoves = 1
function Move-Item {
  [CmdletBinding()] param([string]$LiteralPath, [string]$Destination)
  if ($Destination -like "*/AddOns/QuestBank" -and $script:failMoves -gt 0) { $script:failMoves--; throw "Access to the path is denied." }
  Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}
$script:answers = @("n")
$o = Run-Install; Show "write fails" $o
Remove-Item function:Move-Item
Check "failure reported with the folder" ($o -match '_classic_beta_: could not write to /tmp/wow/_classic_beta_/Interface/AddOns :: Access to the path is denied\.')
Check "old QuestBank put back" ((Toc-Ver "$beta/Interface/AddOns/QuestBank") -eq "3.5.10")
Check "no staging folder left after the failure" (-not (Test-Path "$beta/Interface/QuestBank.new"))

# the uploader folder on its own, without the addon beside it
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path "/tmp/lonely/QuestBank Uploader" | Out-Null
Copy-Item $src "/tmp/lonely/QuestBank Uploader/"
$script:Self = "/tmp/lonely/QuestBank Uploader/QuestBank-Uploader.ps1"; $script:WowPath = "/tmp/wow"
$o = Run-Install
Check "-WowPath sets the folder" ((Cfg).wowPath -eq "/tmp/wow")
Check "no bundled addon: says so, touches nothing" ($o -match "The QuestBank addon folder didn't come with this copy" -and -not (Test-Path "$beta/Interface/AddOns/QuestBank") -and (Asked).Count -eq 0)

# the whole download extracted into AddOns by mistake: the addon is already where it belongs
Reset-App; New-Wow
Expand-Archive -LiteralPath /w/QuestBank-Uploader.zip -DestinationPath "$beta/Interface/AddOns"
$script:Self = "$beta/Interface/AddOns/QuestBank Uploader/QuestBank-Uploader.ps1"; $script:WowPath = "/tmp/wow"; $script:answers = @("n")
$o = Run-Install; Show "extracted into AddOns" $o
Check "download inside AddOns: left as it is" ($o -match '_classic_beta_: QuestBank .* \(this download sits in AddOns itself\)' -and -not (Test-Path "$beta/Interface/QuestBank.bak"))

"`n=== E. status and sending"
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
Put-Toc "$beta/Interface/AddOns/QuestBank" $BV
Save-Lua $betaSV $BV
Save-Lua "$era/WTF/Account/ACC1/SavedVariables/QuestBank.lua" "3.5.10"
Put-Toc "$retail/Interface/AddOns/QuestBank/QuestBank" "3.5.0"
$s = Get-StatusText (Read-Config); Show "status: not sent yet, era without QuestBank, retail too deep" $s
Check "status: not sent yet" ($s -match ('by QuestBank ' + [regex]::Escape($BV) + '; not sent yet'))
Check "status: same version, no restart line" (-not ($s -match 'restart|next time you start'))
Check "status: saves where QuestBank is missing" ($s -match '_classic_era_: QuestBank is not installed here\.')
Check "status: one folder too deep" ($s -match '_retail_: QuestBank 3\.5\.0 sits one folder too deep, in AddOns\\QuestBank\\QuestBank, so the game doesn''t load it\.')
Check "status: never says Sync" (-not ($s -match 'Sync'))
Send-Changes | Out-Null
Add-Content $betaSV "-- played again"
$s = Get-StatusText (Read-Config)
Check "status: changed since the last send" ($s -match 'changed since the last send, goes next')
$script:sendFails = "HTTP 413 {`"error`":`"too large`"}"
$r = Send-Changes; "  failing send: " + $r
Check "failed send says why and when it tries again" ($r -eq ("Could not send QuestBank.lua: HTTP 413 {`"error`":`"too large`"}. It tries again in 30 minutes."))
$s = Get-StatusText (Read-Config)
Check "status (tray): failed last time" ($s -match 'failed last time: HTTP 413')
Check "status: the failure is in the last log lines" ($s -match 'FAILED .*HTTP 413')
$script:sendFails = $null
$big = "$beta/WTF/Account/BIG/SavedVariables/QuestBank.lua"
New-Item -ItemType Directory -Force -Path (Split-Path $big) | Out-Null
$fs = [System.IO.File]::Create($big); $fs.SetLength(7MB); $fs.Close()
$r = Send-Changes; "  with a 7 MB file: " + $r
Check "over 6 MB: the others still go, the big one is reported" ($r -eq "Sent 1 file(s); 1 could not go: see Status.")
Remove-Item -Recurse (Split-Path (Split-Path $big))
$script:Tray = $true; $script:fileState = $null
foreach ($i in 1..7) { Save-Lua "$beta/WTF/Account/ACC$($i + 1)/SavedVariables/QuestBank.lua" "3.5.10" }
$r = Send-Changes; "  eight accounts: " + $r
$script:Tray = $false
Check "several files: counted" ($r -eq "Sent 7 QuestBank.lua files to foreverrank.com.")
Check "tray logs each file's state once" (@((Get-Content $LogFile) -match '_classic_beta_, QuestBank\.lua, account ACC').Count -eq 8)
$s = Get-StatusText (Read-Config); Show "status: many accounts" $s
Check "status: at most six files, then a count under each folder" ($s -match 'account ACC\d[^\n]*\n   \.\.\. and 2 more\n\n_classic_era_: QuestBank is not installed here\.\n   \.\.\. and 1 more')
Reset-App; New-Wow
Remove-Item -Recurse "$beta/WTF"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
$s = Get-StatusText (Read-Config); Show "status: no saves" $s
Check "status: no QuestBank.lua yet" ($s -match 'No QuestBank\.lua yet: log a character out once with QuestBank installed\.')
Check "send: no QuestBank.lua yet" ((Send-Changes) -eq "No QuestBank.lua found yet. Log a character out once with QuestBank installed.")
Remove-Item -Recurse $AppDir
Check "send: not installed" ((Send-Changes) -eq "QuestBank Uploader is not installed. Run Install.bat first.")

"`n=== F. uninstall"
Reset-App; New-Wow
$script:WowPath = "/tmp/wow"; $script:answers = @("y", "n")
Run-Install | Out-Null
New-Item -ItemType Directory -Force -Path $LegacyDir | Out-Null
Set-Content "/tmp/home/OneDrive/Desktop/ForeverProbe Sync.lnk" "left by the old installer"
Set-Content "/tmp/home/OneDrive/Desktop/QuestBank Uploader.lnk" "a copy somewhere"
$script:calls.Clear()
$o = (Uninstall-Uploader 6>&1 | Out-String); Show "uninstall" $o
Check "AppDir gone" (-not (Test-Path $AppDir))
Check "old AppDir gone too" (-not (Test-Path $LegacyDir))
Check "every shortcut of both names gone, OneDrive Desktop included" (@(Get-ChildItem -Recurse /tmp/home -Filter "*.lnk").Count -eq 0)
Check "tray stopped, old task asked to go" ($script:calls -contains "stop-tray" -and $script:calls -contains "legacy-task")
Check "QuestBank addon and saved files stay" ((Test-Path "$beta/Interface/AddOns/QuestBank/QuestBank.toc") -and (Test-Path $betaSV))

"`n=== G. OneDrive holds the Desktop"
Reset-App; New-Wow
$script:shellDesktop = ""; $script:WowPath = "/tmp/wow"; $script:answers = @("n", "n")
Run-Install | Out-Null
Check "no shell Desktop answer: the OneDrive Desktop gets the icon" (Test-Path "/tmp/home/OneDrive/Desktop/QuestBank Uploader.lnk")

"`n=== H. which game is running (the script's own Get-WowStart, with made-up processes)"
. ([scriptblock]::Create(($funcs | Where-Object { $_.Name -eq "Get-WowStart" }).Extent.Text))
$t0 = (Get-Date).AddHours(-2)
function Get-Process {
  return @(
    [pscustomobject]@{ ProcessName = "WowClassicB"; Path = "/tmp/wow/_classic_beta_/WowClassicB.exe"; StartTime = $t0 },
    [pscustomobject]@{ ProcessName = "WowUp"; Path = "/tmp/wow/_classic_/WowUp.exe"; StartTime = $t0.AddHours(-1) })
}
Check "the beta's game counts as running in _classic_beta_" ((Get-WowStart "/tmp/wow/_classic_beta_") -eq $t0)
Check "and not in _classic_ (a prefix of the name)" ($null -eq (Get-WowStart "/tmp/wow/_classic_"))
Check "an addon manager is never the game" ($null -eq (Get-WowStart "/tmp/wow/_classic_/"))
Remove-Item function:Get-Process

"`n=== I. the real upload, against a stand-in endpoint on this machine"
$mockSend = ${function:Send-File}
. ([scriptblock]::Create(($funcs | Where-Object { $_.Name -eq "Send-File" }).Extent.Text))
$job = Start-ThreadJob {
  $l = [System.Net.HttpListener]::new(); $l.Prefixes.Add("http://127.0.0.1:8787/"); $l.Start()
  $got = @()
  foreach ($reply in @(@{ code = 200; body = '{"ok":true,"id":7,"kind":"questbank-savedvars","summary":{"quests":12}}' }, @{ code = 413; body = '{"error":"too large once compressed"}' })) {
    $ctx = $l.GetContext()
    $ms = [System.IO.MemoryStream]::new(); $ctx.Request.InputStream.CopyTo($ms)
    $got += [pscustomobject]@{ ct = $ctx.Request.ContentType; body = $ms.ToArray() }
    $ctx.Response.StatusCode = $reply.code; $ctx.Response.ContentType = "application/json"
    $b = [Text.Encoding]::UTF8.GetBytes($reply.body); $ctx.Response.OutputStream.Write($b, 0, $b.Length); $ctx.Response.Close()
  }
  $l.Stop()
  return $got
}
Start-Sleep -Milliseconds 800
# a file with bytes past ASCII (a name like Bjoern written with o-slash, in UTF-8): they must arrive as they are
$up = "/tmp/up/QuestBank.lua"; New-Item -ItemType Directory -Force /tmp/up | Out-Null
[System.IO.File]::WriteAllBytes($up, [byte[]](@(0x51, 0x42, 0x20, 0x3d, 0x20, 0x22, 0x42, 0x6a, 0xc3, 0xb8, 0x72, 0x6e, 0x22, 0x0d, 0x0a, 0x00, 0xff)))
$r = Send-File -Url "http://127.0.0.1:8787/api/probe" -File $up
Check "a 200 reply comes back as the object" ($r.ok -and $r.id -eq 7 -and $r.summary.quests -eq 12)
$e = $null; try { Send-File -Url "http://127.0.0.1:8787/api/probe" -File $up | Out-Null } catch { $e = $_.Exception.Message }
"  refused: " + $e
Check "a refusal reads as the Worker's sentence" ($e -eq "HTTP 413, too large once compressed")
$got = @(Receive-Job $job -Wait -AutoRemoveJob)
$req = $got[0]
$latin = [Text.Encoding]::GetEncoding("ISO-8859-1")
$body = $latin.GetString($req.body)
Check "multipart with source=uploader" ($req.ct -match '^multipart/form-data; boundary=' -and $body.Contains("name=`"source`"`r`n`r`nuploader`r`n"))
Check "the file goes as QuestBank.lua" ($body.Contains('name="file"; filename="QuestBank.lua"'))
$fileBytes = [System.IO.File]::ReadAllBytes($up)
$head = "Content-Type: text/plain`r`n`r`n"
$at = $body.IndexOf($head) + $head.Length
Check "the file's bytes arrive exactly" ([Convert]::ToBase64String($req.body[$at..($at + $fileBytes.Length - 1)]) -eq [Convert]::ToBase64String($fileBytes) -and $body.Substring($at + $fileBytes.Length).StartsWith("`r`n--"))
$e = $null; try { Send-File -Url "http://127.0.0.1:9/api/probe" -File $up | Out-Null } catch { $e = $_.Exception.Message }
"  offline: " + $e
Check "no answer at all reads as such" ($e -like "no answer from foreverrank.com (*)")
Set-Item function:Send-File $mockSend

"`n=== J. the WoW folder picked is a game folder itself (with a trailing slash)"
Reset-App; New-Wow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow/_classic_beta_/"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
$s = Get-StatusText (Read-Config); Show "status" $s
Check "its file is found and listed under it" ($s -match '_classic_beta_: QuestBank is not installed here\.' -and $s -match 'account ACC1' -and -not ($s -match '_classic_era_'))
Check "and sent" ((Send-Changes) -eq "Sent QuestBank.lua to foreverrank.com.")

"`n=== K. when the ForeverProbe folder can go"
function Probe-Note { return (Get-ProbeNote $beta (Get-QuestBankState $beta)) }
Reset-App; New-Wow
$fp2 = "$beta/WTF/Account/ACC2/SavedVariables"
Check "ForeverProbe.lua, no imported mark: keep it" ((Probe-Note) -like "Keep the ForeverProbe folder*")
Save-Lua $betaSV $BV 16001 "[`"imported`"] = true,"
Check "imported mark: it can go" ((Probe-Note) -eq "The ForeverProbe folder in Interface\AddOns is no longer needed: you can delete it.")
Save-Lua "$fp2/QuestBank.lua" $BV; Set-Content "$fp2/ForeverProbe.lua" "ForeverProbeDB = {}"
Check "a second account with ForeverProbe.lua and no mark: keep it" ((Probe-Note) -like "Keep the ForeverProbe folder*")
Remove-Item "$fp2/QuestBank.lua"
Check "an account with ForeverProbe.lua and no QuestBank.lua yet: keep it" ((Probe-Note) -like "Keep the ForeverProbe folder*")
Remove-Item -Recurse "$beta/WTF/Account/ACC2"
Save-Lua $betaSV $BV 11507
Check "a QuestBank.lua from a game that isn't Forever: nothing to take over, it can go" ((Probe-Note) -like "*no longer needed: you can delete it.")
Save-Lua $betaSV $BV 16001 "[`"noteGame`"] = false,"
Check "the Settings box off: says why it isn't taken and leaves it to the player" ((Probe-Note) -eq "The ForeverProbe folder in Interface\AddOns: QuestBank takes over its notes only while ""Note items and spells you see, for foreverrank.com"" is ticked in QuestBank's Settings, Discoveries, and it is off. Delete the folder if you don't want them kept.")
Remove-Item "$beta/WTF/Account/ACC1/SavedVariables/ForeverProbe.lua"
Check "no ForeverProbe.lua at all: it can go" ((Probe-Note) -like "*no longer needed: you can delete it.")
Remove-Item -Recurse "$beta/Interface/AddOns/ForeverProbe"
Check "no ForeverProbe folder: nothing to say" ($null -eq (Probe-Note))
Reset-App; New-Wow
Save-Lua $betaSV $BV 16001 "[`"imported`"] = true,"
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
@{ wowPath = "/tmp/wow"; sent = @{} } | ConvertTo-Json | Set-Content $CfgFile
$s = Get-StatusText (Read-Config)
Check "status: imported, so it can go" ($s -match '   The ForeverProbe folder in Interface\\AddOns is no longer needed: you can delete it\.')
$script:answers = @("n", "n")
$o = Run-Install
Check "install: imported, so it can go" ($o -match '_classic_beta_: the ForeverProbe folder in Interface\\AddOns is no longer needed: you can delete it\.')

"`n=== L. config.json is never left half written"
Reset-App
$c = ConvertTo-Config $null; $c.wowPath = "/tmp/wow"; $c.sent["/x/QuestBank.lua"] = "AAA"
Save-Config $c
Check "first save: config.json, no backup, no temporary file" ((Test-Path $CfgFile) -and -not (Test-Path $CfgBak) -and @(Get-ChildItem $AppDir -Filter "*.tmp").Count -eq 0)
$c.sent["/y/QuestBank.lua"] = "BBB"; Save-Config $c
Check "next save keeps the one before as config.json.bak" ((Read-ConfigFile $CfgBak).wowPath -eq "/tmp/wow" -and -not (Read-ConfigFile $CfgBak).sent."/y/QuestBank.lua" -and (Cfg).sent."/y/QuestBank.lua" -eq "BBB")
Set-Content -LiteralPath $CfgFile -Value '{"wowPath": "/tmp/w' -NoNewline
$c2 = Read-Config
Check "a config.json cut short: the backup's settings, not none" ($c2.wowPath -eq "/tmp/wow" -and $c2.sent["/x/QuestBank.lua"] -eq "AAA")
Save-Config $c2
Check "saving over a broken config.json keeps the good backup" ((Cfg).wowPath -eq "/tmp/wow" -and (Read-ConfigFile $CfgBak).wowPath -eq "/tmp/wow")
Set-Content -LiteralPath $CfgFile -Value "" -NoNewline; Remove-Item $CfgBak
Check "both broken or gone: defaults, still installed" ((Read-Config).wowPath -eq "" -and $null -ne (Read-Config))

"`n" + ($script:checks - $script:fails) + " of " + $script:checks + " checks passed"
if ($script:fails -gt 0) { exit 1 }
