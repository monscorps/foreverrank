# QuestBank Uploader: sends your QuestBank.lua to foreverrank.com, automatically.
#
# What it does, in full: finds WTF\Account\<account>\SavedVariables\QuestBank.lua in your WoW game
# folders and, when the file changes (WoW writes it at logout and on /reload), uploads it to
# foreverrank.com. Nothing else is read or sent, nothing runs inside the game, no account or login is
# involved, and you can read every line below. Uploads are stored privately and never published as they
# are (the file holds your characters' names); only what QuestBank noted about quests, NPCs, items,
# spells and XP goes into QuestBank's data releases.
#
# Install:   Install.bat (or: .\QuestBank-Uploader.ps1 -Install). It also puts the QuestBank addon that
#            came in the same download into your game folders: it updates the copy you have and asks
#            before adding one where there is none.
# Running:   the QuestBank Uploader icon sits in the system tray and sends every 30 minutes;
#            right-click it for Send now / Status / Exit. It comes back at every login.
# Remove:    Uninstall.bat (or: -Uninstall). The QuestBank addon and your saved files stay.

param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$SendNow,
  [switch]$Tray,
  [string]$WowPath = "",
  [string]$Endpoint = ""
)

$DefaultEndpoint = "https://foreverrank.andustemme.workers.dev/api/probe"
$WatchFile  = "QuestBank.lua"
$MaxBytes   = 6 * 1024 * 1024   # the endpoint's limit
$AppName    = "QuestBank Uploader"
$AppDir     = Join-Path $env:APPDATA $AppName
$CfgFile    = Join-Path $AppDir "config.json"
$CfgBak     = $CfgFile + ".bak"
$LogFile    = Join-Path $AppDir "uploader.log"
$ScriptFile = "QuestBank-Uploader.ps1"
$IconFile   = "QuestBank.ico"
$TrayMutex  = "QuestBankUploaderTray"
$Self       = $PSCommandPath

# The ForeverProbe Sync this replaces. Only the move-over at install and Uninstall use these names.
$LegacyDir    = Join-Path $env:APPDATA "ForeverProbe"
$LegacyName   = "ForeverProbe Sync"     # its shortcuts, and the scheduled task its oldest builds made
$LegacyScript = "ForeverProbe-Sync"
$LegacyMutex  = "ForeverProbeSyncTray"

# A path from its parts, with whatever separator this system uses
function PathOf { return [System.IO.Path]::Combine([string[]]$args) }

function Log([string]$msg) {
  $line = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $msg
  Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue
}

# The settings: wowPath (empty means the usual install folders), sent (each file's SHA-256 when it was
# last sent), declined (game folders the player said no to QuestBank in, so Install doesn't ask again)
# and, only when someone picked another one, endpoint. With no endpoint stored, a change to the site's
# own reaches every install.
function ConvertTo-Config($raw) {
  $cfg = @{ wowPath = ""; sent = @{}; declined = @(); endpointSet = ""; endpoint = $DefaultEndpoint }
  if ($raw) {
    if ($raw.PSObject.Properties["wowPath"] -and $raw.wowPath) { $cfg.wowPath = [string]$raw.wowPath }
    if ($raw.PSObject.Properties["sent"] -and $raw.sent) { $raw.sent.PSObject.Properties | ForEach-Object { $cfg.sent[$_.Name] = [string]$_.Value } }
    if ($raw.PSObject.Properties["declined"] -and $raw.declined) { $cfg.declined = @($raw.declined | ForEach-Object { [string]$_ }) }
    if ($raw.PSObject.Properties["endpoint"] -and $raw.endpoint -and [string]$raw.endpoint -ne $DefaultEndpoint) {
      $cfg.endpointSet = [string]$raw.endpoint
      $cfg.endpoint = $cfg.endpointSet
    }
  }
  return $cfg
}

# One settings file as JSON, or $null when it is missing or broken
function Read-ConfigFile([string]$file) {
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  try { return (Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

# A config.json cut short (the tray ended mid-write, a logoff) falls back to config.json.bak, the
# settings before the last save, rather than to none: no WoW folder and no sent list would undo both
function Read-Config {
  if (-not (Test-Path -LiteralPath $CfgFile) -and -not (Test-Path -LiteralPath $CfgBak)) { return $null }
  $raw = Read-ConfigFile $CfgFile
  if (-not $raw) { $raw = Read-ConfigFile $CfgBak }
  return (ConvertTo-Config $raw)
}

# Written beside config.json and then swapped in, so config.json is whole at every moment; the one it
# replaces becomes config.json.bak (unless it was broken, so a good .bak stays good)
function Save-Config($cfg) {
  $out = [ordered]@{ wowPath = $cfg.wowPath; sent = $cfg.sent }
  if (@($cfg.declined).Count -gt 0) { $out.declined = @($cfg.declined) }
  if ($cfg.endpointSet) { $out.endpoint = $cfg.endpointSet }
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  $tmp = $CfgFile + "." + $PID + ".tmp"
  $out | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tmp -Encoding UTF8
  if (Read-ConfigFile $CfgFile) { [System.IO.File]::Replace($tmp, $CfgFile, $CfgBak) }
  else { Move-Item -LiteralPath $tmp -Destination $CfgFile -Force }
}

# The game's own executable in a game folder (Wow.exe, WowClassic.exe and their beta and test builds),
# never addon managers or launchers
function Get-GameExe($game) {
  $exe = @(Get-ChildItem -LiteralPath $game -File -Filter "Wow*.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^Wow(Classic)?(B|T|Beta)?(-64)?\.exe$' } | Select-Object -First 1)
  if ($exe.Count -gt 0) { return $exe[0].FullName }
  return $null
}

# Every WoW game folder: each _name_ folder (_classic_beta_ for the Forever beta, _classic_era_, _retail_
# and whatever comes next) under the chosen folder and the usual install folders, plus a chosen folder
# that is a game folder itself. A folder reached twice counts once.
function Get-GameFolders {
  param([string]$Root)
  $roots = @()
  if ($Root) { $roots += $Root }
  $roots += @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft")
  if ($env:USERPROFILE) { $roots += (Join-Path $env:USERPROFILE "World of Warcraft") }
  $seen = @{}
  $out = @()
  foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r -PathType Container)) { continue }
    $cands = @(Get-ChildItem -LiteralPath $r -Directory -Filter "_*_" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $cands += $r
    foreach ($g in $cands) {
      if ($g.Length -gt 3) { $g = $g.TrimEnd('\', '/') }
      if (-not ((Test-Path -LiteralPath (PathOf $g "WTF")) -or (Test-Path -LiteralPath (PathOf $g "Interface")) -or (Get-GameExe $g))) { continue }
      $key = (Resolve-Path -LiteralPath $g).Path.TrimEnd('\', '/').ToLowerInvariant()
      if ($seen[$key]) { continue }
      $seen[$key] = $true
      $out += $g
    }
  }
  return $out
}

# QuestBank.lua is account-wide, so only WTF\Account\<account>\SavedVariables counts (never a character's folder)
function Find-SavedVariables {
  param([string]$Root)
  foreach ($g in @(Get-GameFolders -Root $Root)) {
    $acct = PathOf $g "WTF" "Account"
    if (-not (Test-Path -LiteralPath $acct)) { continue }
    foreach ($a in @(Get-ChildItem -LiteralPath $acct -Directory -ErrorAction SilentlyContinue)) {
      $p = PathOf $a.FullName "SavedVariables" $WatchFile
      if (Test-Path -LiteralPath $p) { $p }
    }
  }
}

# One multipart POST: source=uploader, file=QuestBank.lua. The reply is JSON:
# { ok, id, kind, summary, message } or { ok, duplicate } or { error }.
function Send-File {
  param([string]$Url, [string]$File)
  $boundary = [System.Guid]::NewGuid().ToString()
  $LF = "`r`n"
  $bytes = [System.IO.File]::ReadAllBytes($File)
  $enc = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
  $name = [System.IO.Path]::GetFileName($File)
  $pre = "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"source`"$LF$LF" + "uploader" + $LF +
    "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"file`"; filename=`"$name`"$LF" +
    "Content-Type: text/plain$LF$LF"
  $post = "$LF--$boundary--$LF"
  # one byte array: PowerShell's + on two arrays makes an object[], which the web cmdlets would stringify
  [byte[]]$body = $enc.GetBytes($pre) + $bytes + $enc.GetBytes($post)
  try {
    return Invoke-RestMethod -Uri $Url -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body -TimeoutSec 60
  } catch {
    # the endpoint answers refusals with {"error": "..."}; show that sentence instead of the bare status
    $detail = ""
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
    elseif ($_.Exception.Response -and ($_.Exception.Response | Get-Member -Name GetResponseStream)) {
      try { $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $detail = $sr.ReadToEnd() } catch { }
    }
    try { $j = $detail | ConvertFrom-Json; if ($j.error) { $detail = [string]$j.error } } catch { }
    $code = ""
    try { if ($_.Exception.Response) { $code = [string][int]$_.Exception.Response.StatusCode } } catch { }
    # no answer at all: offline, or the site unreachable
    if (-not $code) { throw ("no answer from foreverrank.com (" + $_.Exception.Message.TrimEnd('.') + ")") }
    throw ("HTTP " + $code + ", " + $detail).TrimEnd(',', ' ')
  }
}

# One pass: every QuestBank.lua that changed since it was last sent goes up. Returns one sentence for the
# balloon or the Status box; $script:sentThisPass says whether anything went (quiet passes balloon only then).
function Send-Changes {
  $script:sentThisPass = 0
  $cfg = Read-Config
  if (-not $cfg) { return "QuestBank Uploader is not installed. Run Install.bat first." }
  if (-not $script:failedLast) { $script:failedLast = @{} }
  if (-not $script:fileState) { $script:fileState = @{} }
  $files = @(Find-SavedVariables -Root $cfg.wowPath)
  $watched = ($files -join "; ")
  if ($script:lastWatched -ne $watched) {
    if ($files.Count -eq 0) { Log "no QuestBank.lua found" } else { Log ("watching " + $files.Count + " file(s): " + $watched) }
    $script:lastWatched = $watched
  }
  if ($files.Count -eq 0) { return "No QuestBank.lua found yet. Log a character out once with QuestBank installed." }
  $posted = 0; $failed = 0; $why = ""
  foreach ($f in $files) {
    $hash = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
    if ($cfg.sent[$f] -eq $hash) { continue }
    $size = (Get-Item -LiteralPath $f).Length
    if ($size -gt $MaxBytes) {
      $failed++
      $script:failedLast[$f] = "over the 6 MB limit"
      if (-not $why) { $why = $script:failedLast[$f] }
      Log ("SKIPPED " + $f + " :: " + [math]::Round($size / 1MB, 1) + " MB is over the 6 MB limit")
      continue
    }
    try {
      $r = Send-File -Url $cfg.endpoint -File $f
      if ($r -and $r.ok) {
        $cfg.sent[$f] = $hash
        $script:failedLast.Remove($f)
        $posted++
        if ($r.duplicate) { Log ("already there: " + $f) }
        else {
          $bits = @()
          if ($r.summary -and $null -ne $r.summary.quests) { $bits += ($r.summary.quests.ToString() + " quests noted") }
          Log (("sent " + $f + " :: upload #" + $r.id + " " + ($bits -join ", ")).Trim())
        }
      } else {
        $failed++
        $script:failedLast[$f] = "no ok in the reply"
        Log ("FAILED " + $f + " :: " + ($r | ConvertTo-Json -Compress))
      }
    } catch {
      $failed++
      $script:failedLast[$f] = $_.Exception.Message
      Log ("FAILED " + $f + " :: " + $_.Exception.Message)
    }
    if ($failed -gt 0 -and -not $why) { $why = $script:failedLast[$f] }
  }
  Save-Config $cfg
  $script:sentThisPass = $posted
  # each file's state in the log when it changes (and once per tray start), never on every pass;
  # only the tray: a Status click or -SendNow is a process of its own and would log them all again
  if ($Tray) {
    foreach ($d in @($files | ForEach-Object { Describe-File $_ $cfg })) {
      if ($script:fileState[$d.path] -ne $d.key) {
        $script:fileState[$d.path] = $d.key
        Log ($d.flavor + ", " + $d.text)
      }
    }
  }
  if ($failed -gt 0 -and $posted -gt 0) { return "Sent $posted file(s); $failed could not go: see Status." }
  if ($failed -gt 0) { return "Could not send QuestBank.lua: " + $why + ". It tries again in 30 minutes." }
  if ($posted -eq 1) { return "Sent QuestBank.lua to foreverrank.com." }
  if ($posted -gt 1) { return "Sent $posted QuestBank.lua files to foreverrank.com." }
  return "Nothing new since the last upload."
}

# The QuestBank version that last wrote this file: QuestBank stamps its version into what it saves
# (each character's snapshot, the discoveries, the login note), and the highest is the one that ran last.
# Only those version fields are read, never names.
function Get-WriterVersion($f) {
  try {
    $body = [System.IO.File]::ReadAllText($f)
    $vs = @([regex]::Matches($body, '\["(?:version|qb|ver)"\]\s*=\s*"(\d+\.\d+\.\d+)"') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending)
    if ($vs.Count -gt 0) { return $vs[0].ToString() }
  } catch { }
  return $null
}

# One QuestBank.lua as Status shows it: the account it belongs to, its size, when the game last wrote
# it, which QuestBank wrote it, and whether that is what was sent last
function Describe-File($f, $cfg) {
  $item = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
  if (-not $item) { return @{ text = $f + ": gone"; key = "gone"; path = $f; game = ""; flavor = "" } }
  # <game folder>\WTF\Account\<account>\SavedVariables\QuestBank.lua
  $acctDir = Split-Path (Split-Path $f -Parent) -Parent
  $acct = Split-Path $acctDir -Leaf
  $game = Split-Path (Split-Path (Split-Path $acctDir -Parent) -Parent) -Parent
  $kb = [math]::Max(1, [math]::Round($item.Length / 1KB))
  $when = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm", [System.Globalization.CultureInfo]::InvariantCulture)
  $ver = Get-WriterVersion $f
  $writer = "an unknown QuestBank"
  if ($ver) { $writer = "QuestBank " + $ver }
  $state = "not sent yet"
  try {
    $hash = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
    if ($cfg.sent[$f] -eq $hash) { $state = "sent" } elseif ($cfg.sent[$f]) { $state = "changed since the last send, goes next" }
  } catch { }
  if ($script:failedLast -and $script:failedLast[$f]) { $state = "failed last time: " + $script:failedLast[$f] }
  $text = "QuestBank.lua, account " + $acct + ": " + $kb + " KB, written " + $when + " by " + $writer + "; " + $state
  return @{ text = $text; ver = $ver; when = $when; written = $item.LastWriteTime; acct = $acct; game = $game; flavor = (Split-Path $game -Leaf); path = $f; key = ($when + "|" + $writer + "|" + $state) }
}

# The Version and Interface lines of an addon's .toc; ifaces holds every interface number it lists
function Read-Toc($toc) {
  $lines = @(Get-Content -LiteralPath $toc -TotalCount 20 -ErrorAction SilentlyContinue)
  $ver = ($lines | Where-Object { $_ -match '^##\s*Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
  $ifc = ($lines | Where-Object { $_ -match '^##\s*Interface:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
  $ifaces = @()
  if ($ifc) { $ifaces = @([regex]::Matches($ifc, '\d+') | ForEach-Object { [int]$_.Value }) }
  return @{ ver = $ver; iface = $ifc; ifaces = $ifaces }
}

# -1, 0 or 1 as version a is older than, the same as or newer than b; $null when either isn't a version
function Compare-Version($a, $b) {
  try {
    if (-not $a -or -not $b) { return $null }
    $va = [string]$a; $vb = [string]$b
    if ($va -match '^\d+\.\d+$') { $va += ".0" }
    if ($vb -match '^\d+\.\d+$') { $vb += ".0" }
    return [math]::Sign(([version]$va).CompareTo([version]$vb))
  } catch { return $null }
}

# When the addon folder was put there: the latest of the folder's and the .toc's times, since an update
# over an old folder keeps the folder's date. A zip keeps each file's date in the packer's local time
# with no zone, so a time still to come says nothing about the install and is left out.
function Get-InstallTime($dir, $toc) {
  $times = @()
  try { $times += (Get-Item -LiteralPath $dir).CreationTime } catch { }
  try { $ti = Get-Item -LiteralPath $toc; $times += $ti.CreationTime; $times += $ti.LastWriteTime } catch { }
  $now = Get-Date
  $times = @($times | Where-Object { $_ -le $now })
  if ($times.Count -eq 0) { return $null }
  return ($times | Sort-Object -Descending | Select-Object -First 1)
}

# Whether a folder is a junction or symbolic link (a tester's AddOns\QuestBank pointing at a checkout, say)
function Test-Link([string]$p) {
  try { return [bool]((Get-Item -LiteralPath $p -Force -ErrorAction Stop).LinkType -match '^(Junction|SymbolicLink)$') } catch { return $false }
}

# Deletes a folder. A link loses only itself: Windows PowerShell 5.1's Remove-Item -Recurse goes through a
# junction or symbolic link and empties the folder it points to.
function Remove-Folder([string]$p) {
  if (Test-Link $p) { [System.IO.Directory]::Delete($p, $false); return }
  Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
}

# QuestBank in one game folder's Interface\AddOns: state ok, deep (AddOns\QuestBank\QuestBank), renamed
# (QuestBank.toc in a folder of another name), inside (AddOns\<other>\QuestBank) or missing; the version
# its .toc gives; when it was put there; whether AddOns\QuestBank is a link; and whether an old
# ForeverProbe folder is still beside it
function Get-QuestBankState($game) {
  $addons = PathOf $game "Interface" "AddOns"
  $r = @{ state = "missing"; ver = $null; installed = $null; where = $null; probe = $false; link = $false; addons = $addons }
  if (-not (Test-Path -LiteralPath $addons)) { return $r }
  $r.probe = Test-Path -LiteralPath (PathOf $addons "ForeverProbe")
  $dir = PathOf $addons "QuestBank"
  $r.link = Test-Link $dir
  $toc = PathOf $dir "QuestBank.toc"
  $deep = PathOf $dir "QuestBank" "QuestBank.toc"
  if (Test-Path -LiteralPath $toc) {
    $r.state = "ok"; $r.ver = (Read-Toc $toc).ver; $r.installed = Get-InstallTime $dir $toc
    return $r
  }
  if (Test-Path -LiteralPath $deep) { $r.state = "deep"; $r.ver = (Read-Toc $deep).ver; return $r }
  foreach ($d in @(Get-ChildItem -LiteralPath $addons -Directory -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath (PathOf $d.FullName "QuestBank.toc")) { $r.state = "renamed"; $r.where = $d.Name; return $r }
    if (Test-Path -LiteralPath (PathOf $d.FullName "QuestBank" "QuestBank.toc")) { $r.state = "inside"; $r.where = $d.Name; return $r }
  }
  return $r
}

function Describe-QuestBankState($st) {
  switch ($st.state) {
    "ok" {
      if ($st.ver) { return "QuestBank " + $st.ver }
      return "QuestBank (its .toc gives no version)"
    }
    "deep" { return "QuestBank " + $st.ver + " sits one folder too deep, in AddOns\QuestBank\QuestBank, so the game doesn't load it. Run Install.bat again, or move the inner QuestBank folder up into AddOns." }
    "renamed" { return "QuestBank sits in AddOns\" + $st.where + "; the game loads it only from a folder named exactly QuestBank. Run Install.bat again, or rename the folder." }
    "inside" { return "QuestBank sits inside AddOns\" + $st.where + "\QuestBank; the game doesn't look there. Run Install.bat again, or move that inner QuestBank folder into AddOns." }
  }
  return "QuestBank is not installed here."
}

# What to say about an old ForeverProbe folder in this game folder, or $null when there is none. QuestBank
# takes ForeverProbe's notes over at a login while ForeverProbe is still there and marks that in
# QuestBank.lua (["imported"] = true); once the folder is gone they can't be, so, like QuestBank's own chat
# line, "delete it" waits for that mark in every account that has a ForeverProbe.lua. An account with
# nothing to take over (no ForeverProbe.lua, or a QuestBank.lua the game stamped with an interface that
# isn't Forever's 16xxx) doesn't hold it up.
function Get-ProbeNote($game, $st) {
  if (-not $st.probe) { return $null }
  $waiting = $false; $boxOff = $false
  foreach ($a in @(Get-ChildItem -LiteralPath (PathOf $game "WTF" "Account") -Directory -ErrorAction SilentlyContinue)) {
    $sv = PathOf $a.FullName "SavedVariables"
    if (-not (Test-Path -LiteralPath (PathOf $sv "ForeverProbe.lua"))) { continue }
    $body = ""
    try { $body = [System.IO.File]::ReadAllText((PathOf $sv $WatchFile)) } catch { }
    if ($body -match '\["imported"\]\s*=\s*true') { continue }
    $other = @([regex]::Matches($body, '\["iface"\]\s*=\s*"?(\d+)') | Where-Object { $n = [int]$_.Groups[1].Value; $n -lt 16000 -or $n -gt 16999 })
    if ($other.Count -gt 0) { continue }
    $waiting = $true
    # the Settings box unticked: QuestBank takes nothing over (and says nothing in chat)
    if ($body -match '\["noteGame"\]\s*=\s*false') { $boxOff = $true }
  }
  if ($boxOff) { return "The ForeverProbe folder in Interface\AddOns: QuestBank takes over its notes only while ""Note items and spells you see, for foreverrank.com"" is ticked in QuestBank's Settings, Discoveries, and it is off. Delete the folder if you don't want them kept." }
  if ($waiting) { return "Keep the ForeverProbe folder in Interface\AddOns for now: QuestBank takes over its notes the next time you log in with both addons switched on, then says in chat that the folder can go." }
  return "The ForeverProbe folder in Interface\AddOns is no longer needed: you can delete it."
}

# Since when this game folder's client has been running, or $null. Only the game's own executables count,
# never addon managers such as WowUp, and only the one started from this game folder when Windows tells us
# the path.
function Get-WowStart($game) {
  try {
    $p = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^Wow(Classic)?(B|T|Beta)?(-64)?$' })
    if ($game) {
      $known = @($p | Where-Object { $path = $null; try { $path = $_.Path } catch { }; $path })
      if ($known.Count -gt 0) {
        # the executable sits in the game folder itself (_classic_ must not claim a game run from _classic_beta_)
        $p = @($known | Where-Object { (Split-Path -Parent $_.Path) -eq $game.TrimEnd('\', '/') })
      }
    }
    $p = @($p | Sort-Object StartTime)
    if ($p.Count -gt 0) { return $p[0].StartTime }
  } catch { }
  return $null
}

# What the Status box says: the WoW folder; per game folder the QuestBank there, an old ForeverProbe folder
# if one is left, whether the game still runs an older QuestBank, and each QuestBank.lua; the last log lines
function Get-StatusText($cfg) {
  $out = @()
  $where = "the usual install folders"
  if ($cfg.wowPath) { $where = $cfg.wowPath }
  $out += "WoW folder: " + $where
  $descs = @(Find-SavedVariables -Root $cfg.wowPath | ForEach-Object { Describe-File $_ $cfg })
  $shown = 0
  foreach ($g in @(Get-GameFolders -Root $cfg.wowPath)) {
    $st = Get-QuestBankState $g
    $saves = @($descs | Where-Object { $_.game -eq $g } | Sort-Object { $_.written } -Descending)
    # game folders where QuestBank never was are none of our business
    if ($st.state -eq "missing" -and -not $st.probe -and $saves.Count -eq 0) { continue }
    $out += ""
    $out += (Split-Path $g -Leaf) + ": " + (Describe-QuestBankState $st)
    $pn = Get-ProbeNote $g $st
    if ($pn) { $out += "   " + $pn }
    # a changed .toc (new files) loads only when WoW starts, so a running game keeps the old QuestBank
    $last = @($saves | Where-Object { $_.ver } | Select-Object -First 1)
    if ($st.state -eq "ok" -and $last.Count -gt 0 -and (Compare-Version $st.ver $last[0].ver) -eq 1) {
      $start = Get-WowStart $g
      if ($start -and (-not $st.installed -or $start -lt $st.installed)) {
        $out += "   WoW needs a restart to load QuestBank " + $st.ver + " (a /reload is not enough); the last save came from " + $last[0].ver + "."
      } elseif (-not $start) {
        $out += "   QuestBank " + $st.ver + " loads the next time you start WoW; the last save came from " + $last[0].ver + "."
      }
    }
    $hidden = 0
    foreach ($d in $saves) {
      if ($shown -lt 6) { $out += "   " + $d.text; $shown++ } else { $hidden++ }
    }
    if ($hidden -gt 0) { $out += "   ... and " + $hidden + " more" }
  }
  if ($descs.Count -eq 0) { $out += ""; $out += "No QuestBank.lua yet: log a character out once with QuestBank installed." }
  $tail = @()
  if (Test-Path -LiteralPath $LogFile) { $tail = @(Get-Content -LiteralPath $LogFile -Tail 5) }
  if ($tail.Count -eq 0) { $tail = @("none yet") }
  $out += ""
  $out += "Last activity:"
  $out += $tail
  $out += ""
  $out += "If your game lives elsewhere, right-click the QuestBank Uploader icon by the clock and pick Choose WoW folder."
  return ($out -join "`n")
}

function Show-Status {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $cfg = Read-Config
  if (-not $cfg) {
    [System.Windows.Forms.MessageBox]::Show("QuestBank Uploader is not installed. Run Install.bat first.", $AppName) | Out-Null
    return
  }
  $msg = (Get-StatusText $cfg) + "`n`nSend now?"
  $r = [System.Windows.Forms.MessageBox]::Show($msg, $AppName, [System.Windows.Forms.MessageBoxButtons]::YesNo)
  if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
    [System.Windows.Forms.MessageBox]::Show((Send-Changes), $AppName) | Out-Null
  }
}

# The folder picker, for the tray menu and for an install that finds no game folder; "" when cancelled
function Pick-WowFolder {
  try {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Pick your World of Warcraft folder, or the game folder inside it that holds WTF and Interface."
    $dlg.ShowNewFolderButton = $false
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $ok = ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK)
    $owner.Dispose()
    if ($ok) { return $dlg.SelectedPath }
  } catch { }
  return ""
}

# A folder as Windows' shell reports it (Startup, Programs, Desktop), "" when it has none
function Get-ShellFolder([string]$name) {
  try { return [Environment]::GetFolderPath($name) } catch { return "" }
}

# Where shortcuts live: Startup (the tray at every login), the Start menu, and the Desktop as Windows
# reports it (OneDrive's when OneDrive holds the Desktop). Every OneDrive Desktop is listed as well, so
# Uninstall finds the copies older installers left there.
function Get-ShortcutDirs {
  $d = @{ startup = (Get-ShellFolder "Startup"); programs = (Get-ShellFolder "Programs"); desktop = (Get-ShellFolder "Desktop"); desktops = @() }
  $desk = @()
  if ($d.desktop -and (Test-Path -LiteralPath $d.desktop)) { $desk += $d.desktop } else { $d.desktop = "" }
  $ods = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)
  if ($env:USERPROFILE) { $ods += (Join-Path $env:USERPROFILE "OneDrive") }
  foreach ($od in $ods) {
    if (-not $od) { continue }
    $p = PathOf $od "Desktop"
    if ((Test-Path -LiteralPath $p) -and -not ($desk -contains $p)) { $desk += $p }
  }
  # no Desktop answer at all: the first OneDrive Desktop is the one to use
  if (-not $d.desktop -and $desk.Count -gt 0) { $d.desktop = $desk[0] }
  $d.desktops = $desk
  return $d
}

# Every place a shortcut of this name may sit
function Get-ShortcutPaths([string]$name) {
  $d = Get-ShortcutDirs
  $out = @()
  foreach ($dir in @(@($d.startup, $d.programs) + $d.desktops)) {
    if ($dir) { $out += (PathOf $dir ($name + ".lnk")) }
  }
  return $out
}

function New-Shortcut([string]$path, [string]$arguments, [string]$description) {
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut($path)
  $lnk.TargetPath = "powershell.exe"
  $lnk.Arguments = $arguments
  $lnk.WorkingDirectory = $AppDir
  $ico = PathOf $AppDir $IconFile
  if (Test-Path -LiteralPath $ico) { $lnk.IconLocation = "$ico,0" }
  $lnk.Description = $description
  $lnk.Save()
}

# Ends any running tray, an old ForeverProbe Sync's included, so install and uninstall never leave a
# stale icon behind or two trays sending the same file
function Stop-Tray {
  try {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction Stop |
      Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '-Tray' -and ($_.CommandLine -match [regex]::Escape($ScriptFile) -or $_.CommandLine -match $LegacyScript) })
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    foreach ($p in $procs) { Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue }
  } catch { }
}

# Whether a tray still holds its mutex (a tray Stop-Tray could not end)
function Test-TrayRunning([string]$mutexName) {
  $m = $null
  try {
    if ([System.Threading.Mutex]::TryOpenExisting($mutexName, [ref]$m)) { $m.Dispose(); return $true }
  } catch { }
  return $false
}

function Start-Tray {
  $target = PathOf $AppDir $ScriptFile
  # one argument string: Start-Process joins a list with spaces and would split the path at "QuestBank Uploader"
  Start-Process powershell -ArgumentList ("-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"" + $target + "`" -Tray") -WindowStyle Hidden
}

# The oldest ForeverProbe Sync builds ran as a scheduled task; $true when there was one to delete
function Remove-LegacyTask {
  try {
    schtasks /Query /TN "$LegacyName" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return $false }
    schtasks /Delete /TN "$LegacyName" /F 2>$null | Out-Null
    return $true
  } catch { return $false }
}

# What ForeverProbe Sync had: its WoW folder and what it had sent of QuestBank.lua (so nothing goes
# twice). Its endpoint is the site's own and its ForeverProbe.lua entries are no longer watched, so
# neither comes along. $null when it was never installed.
function Read-LegacyConfig {
  $file = Join-Path $LegacyDir "config.json"
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  $out = @{ wowPath = ""; sent = @{} }
  try {
    $raw = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    if ($raw.PSObject.Properties["wowPath"] -and $raw.wowPath) { $out.wowPath = [string]$raw.wowPath }
    if ($raw.PSObject.Properties["sent"] -and $raw.sent) {
      foreach ($p in $raw.sent.PSObject.Properties) {
        if ($p.Name -match '[\\/]QuestBank\.lua$') { $out.sent[$p.Name] = [string]$p.Value }
      }
    }
  } catch { }
  return $out
}

# Clears ForeverProbe Sync away once its settings are safe in ours: the scheduled task, every shortcut and
# its folder in AppData. The player's saved files stay. $true when anything of it was there.
function Remove-LegacyInstall {
  $found = Remove-LegacyTask
  foreach ($lnk in @(Get-ShortcutPaths $LegacyName)) {
    if (Test-Path -LiteralPath $lnk) {
      $found = $true
      Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
    }
  }
  if (Test-Path -LiteralPath $LegacyDir) {
    $found = $true
    try { Remove-Item -LiteralPath $LegacyDir -Recurse -Force -ErrorAction Stop }
    catch { Write-Host ("  Could not remove " + $LegacyDir + " :: " + $_.Exception.Message) -ForegroundColor Red }
  }
  return $found
}

function Ask-YesNo([string]$question) {
  for ($i = 0; $i -lt 3; $i++) {
    $a = Read-Host $question
    if ($null -eq $a) { return $false }
    if ($a -match '^\s*[yYjJ]') { return $true }
    if ($a -match '^\s*[nN]') { return $false }
  }
  return $false
}

# The QuestBank addon folder that came in the same download: next to this folder, or inside it
function Find-BundledQuestBank {
  if (-not $Self) { return $null }
  $here = Split-Path -Parent $Self
  foreach ($c in @((PathOf (Split-Path -Parent $here) "QuestBank"), (PathOf $here "QuestBank"))) {
    if (Test-Path -LiteralPath (PathOf $c "QuestBank.toc")) { return $c }
  }
  return $null
}

# The game's interface number from its executable's version (1.60.1.x is 16001), or $null
function Get-GameInterface($game) {
  try {
    $exe = Get-GameExe $game
    if (-not $exe) { return $null }
    $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
    if ($v.FileMajorPart -le 0 -and $v.FileMinorPart -le 0) { return $null }
    return ($v.FileMajorPart * 10000 + $v.FileMinorPart * 100 + $v.FileBuildPart)
  } catch { return $null }
}

# Whether the game in this folder can load the addon: its major version is one the .toc lists (1 for
# Forever's 1.60 and Era's 1.15 alike, so a Forever patch the .toc hasn't caught up with still counts;
# _retail_'s 11 doesn't). When the game's version can't be read, the answer is yes, and the player decides.
function Test-GameRunsAddon($game, $ifaces) {
  $i = Get-GameInterface $game
  if (-not $i -or -not $ifaces -or $ifaces.Count -eq 0) { return $true }
  foreach ($x in $ifaces) { if ([math]::Floor($x / 10000) -eq [math]::Floor($i / 10000)) { return $true } }
  return $false
}

# Whether any account in this game folder has a QuestBank.lua: QuestBank has run there
function Test-HasSaves($game) {
  foreach ($a in @(Get-ChildItem -LiteralPath (PathOf $game "WTF" "Account") -Directory -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath (PathOf $a.FullName "SavedVariables" $WatchFile)) { return $true }
  }
  return $false
}

# A game folder as config.json's declined list holds it
function Get-FolderKey($game) {
  $p = $game
  try { $p = (Resolve-Path -LiteralPath $game).Path } catch { }
  return $p.TrimEnd('\', '/').ToLowerInvariant()
}

# Swaps AddOns\QuestBank for a copy of $src without the game ever seeing half a folder: the copy is made
# in Interface\QuestBank.new, the old folder becomes Interface\QuestBank.bak (one backup, the previous one
# goes), then the new one moves in. Both moves stay on one drive, so each is a rename. Never elevates.
function Copy-QuestBank($src, $addons) {
  $iface = Split-Path -Parent $addons
  $dest = PathOf $addons "QuestBank"
  $stage = PathOf $iface "QuestBank.new"
  $bak = PathOf $iface "QuestBank.bak"
  try {
    if (-not (Test-Path -LiteralPath $addons)) { New-Item -ItemType Directory -Force -Path $addons -ErrorAction Stop | Out-Null }
    if (Test-Path -LiteralPath $stage) { Remove-Folder $stage }
    Copy-Item -LiteralPath $src -Destination $stage -Recurse -Force -ErrorAction Stop
    if (-not (Test-Path -LiteralPath (PathOf $stage "QuestBank.toc"))) { throw "the copy came out incomplete" }
    $backedUp = $false
    if (Test-Path -LiteralPath $dest) {
      if (Test-Path -LiteralPath $bak) { Remove-Folder $bak }
      Move-Item -LiteralPath $dest -Destination $bak -ErrorAction Stop
      $backedUp = $true
    }
    try {
      Move-Item -LiteralPath $stage -Destination $dest -ErrorAction Stop
    } catch {
      # put the old one back rather than leave no QuestBank at all
      if ($backedUp -and -not (Test-Path -LiteralPath $dest)) { Move-Item -LiteralPath $bak -Destination $dest -ErrorAction SilentlyContinue }
      throw
    }
    return @{ ok = $true; backup = $backedUp; bak = $bak }
  } catch {
    $msg = $_.Exception.Message
    if (Test-Path -LiteralPath $stage) { try { Remove-Folder $stage } catch { } }
    return @{ ok = $false; error = $msg }
  }
}

# Puts the QuestBank addon from this download into each game folder: an older or equal copy is replaced,
# a newer one is left alone (one sitting a folder too deep moves up), a linked AddOns\QuestBank is the
# player's own, and a game folder without QuestBank is asked about once (only where its game can load
# QuestBank). Only Interface\AddOns\QuestBank is written: never WTF, saved files or other addons.
function Install-QuestBankAddon($cfg) {
  $src = Find-BundledQuestBank
  if (-not $src) {
    Write-Host "  The QuestBank addon folder didn't come with this copy, so your addons are as they were."
    return
  }
  $toc = Read-Toc (PathOf $src "QuestBank.toc")
  $ver = $toc.ver
  $games = @(Get-GameFolders -Root $cfg.wowPath)
  if ($games.Count -eq 0) {
    Write-Host "  No WoW game folder found, so QuestBank was not put in. Copy the QuestBank folder"
    Write-Host "  from this download into your game's Interface\AddOns yourself."
    return
  }
  Write-Host ("  The QuestBank addon (" + $ver + ") in your game folders:")
  $changed = @()
  foreach ($g in $games) {
    $label = Split-Path $g -Leaf
    $st = Get-QuestBankState $g
    $dest = PathOf $st.addons "QuestBank"
    if ((Test-Path -LiteralPath $dest) -and ((Resolve-Path -LiteralPath $dest).Path -eq (Resolve-Path -LiteralPath $src).Path)) {
      Write-Host ("    " + $label + ": QuestBank " + $ver + " (this download sits in AddOns itself)")
      continue
    }
    if ($st.link) {
      Write-Host ("    " + $label + ": AddOns\QuestBank links to another folder, so it stays as it is.")
      continue
    }
    $from = $src; $fromVer = $ver; $was = $null
    if ($st.state -eq "ok" -or $st.state -eq "deep") {
      $was = $st.ver
      if (-not $was) { $was = "a copy with no version" }
      $cmp = Compare-Version $ver $st.ver
      if ($null -ne $cmp -and $cmp -lt 0) {
        if ($st.state -eq "ok") {
          Write-Host ("    " + $label + ": QuestBank " + $st.ver + " is newer than this download's, so it stays.")
          continue
        }
        # newer than this download, but where the game never loads it: that copy moves up
        $from = PathOf $dest "QuestBank"; $fromVer = $st.ver
      }
      # the game reads a .toc's file list only when it starts: a /reload or a logout before the restart
      # would run the new files the old list names and miss the new ones
      if ($st.state -eq "ok" -and $was -ne $ver -and (Get-WowStart $g)) {
        if (-not (Ask-YesNo ("    " + $label + ": WoW is running. Update QuestBank " + $was + " to " + $ver + " now and restart WoW right after? (Y/N)"))) {
          Write-Host ("    " + $label + ": QuestBank " + $was + " left as it is; run Install.bat again once WoW is closed.")
          continue
        }
      }
    } else {
      $key = Get-FolderKey $g
      if (@($cfg.declined) -contains $key) {
        Write-Host ("    " + $label + ": left without QuestBank, as you chose before.")
        continue
      }
      # past game folders whose game can't load QuestBank (_retail_ and the like), unless QuestBank or
      # ForeverProbe has been there
      if (-not (Test-GameRunsAddon $g $toc.ifaces) -and -not $st.probe -and -not (Test-HasSaves $g)) {
        Write-Host ("    " + $label + ": skipped, its game can't load QuestBank.")
        continue
      }
      if (-not (Ask-YesNo ("    " + $label + ": QuestBank isn't there. Put it in? (Y/N)"))) {
        Write-Host ("    " + $label + ": left without QuestBank, and Install won't ask again. To add it later, copy")
        Write-Host ("    the QuestBank folder from this download into that game's Interface\AddOns.")
        $cfg.declined = @(@($cfg.declined) + $key)
        Save-Config $cfg
        continue
      }
    }
    $r = Copy-QuestBank $from $st.addons
    if (-not $r.ok) {
      Write-Host ("    " + $label + ": could not write to " + $st.addons + " :: " + $r.error) -ForegroundColor Red
      Write-Host ("    Copy the QuestBank folder from this download there yourself.") -ForegroundColor Red
      Log ("could not put QuestBank " + $fromVer + " in " + $label + " :: " + $r.error)
      continue
    }
    # what the game loads at its next start is new, unless the same version was copied over itself
    if ($st.state -ne "ok" -or $was -ne $fromVer) { $changed += [pscustomobject]@{ game = $g; ver = $fromVer } }
    if ($from -ne $src) {
      Write-Host ("    " + $label + ": QuestBank " + $fromVer + " (newer than this download's) sat one folder too deep; moved up into AddOns (the folder as it was is in Interface\QuestBank.bak).") -ForegroundColor Green
      Log ("QuestBank " + $fromVer + " moved up a folder in " + $label)
    } elseif (-not $was) {
      Write-Host ("    " + $label + ": QuestBank " + $ver + " put in.") -ForegroundColor Green
      Log ("QuestBank " + $ver + " put in " + $label)
    } elseif ($was -eq $ver) {
      Write-Host ("    " + $label + ": QuestBank " + $ver + " copied in fresh (the one that was there is in Interface\QuestBank.bak).") -ForegroundColor Green
      Log ("QuestBank " + $ver + " copied fresh into " + $label)
    } else {
      Write-Host ("    " + $label + ": QuestBank " + $was + " updated to " + $ver + " (the old one is in Interface\QuestBank.bak).") -ForegroundColor Green
      Log ("QuestBank " + $was + " updated to " + $ver + " in " + $label)
    }
    if ($st.state -eq "renamed" -or $st.state -eq "inside") {
      Write-Host ("    The copy in AddOns\" + $st.where + " is one the game never loaded: you can delete it.")
    }
  }
  foreach ($g in $games) {
    $pn = Get-ProbeNote $g (Get-QuestBankState $g)
    if ($pn) { Write-Host ("    " + (Split-Path $g -Leaf) + ": " + $pn.Substring(0, 1).ToLowerInvariant() + $pn.Substring(1)) }
  }
  $restart = @($changed | Where-Object { Get-WowStart $_.game })
  if ($restart.Count -gt 0) {
    $vs = (@($restart | ForEach-Object { $_.ver } | Select-Object -Unique) -join " / ")
    Write-Host ("  WoW is running: restart it to load QuestBank " + $vs + " (a /reload is not enough).") -ForegroundColor Yellow
  }
}

function Show-Banner {
  Write-Host ""
  Write-Host "  Q U E S T B A N K   U P L O A D E R" -ForegroundColor Yellow
  Write-Host "  foreverrank.com/questbank" -ForegroundColor DarkGray
  Write-Host ""
}

function Install-Uploader {
  Show-Banner
  Write-Host "  Sends your QuestBank.lua to foreverrank.com after each session, so what"
  Write-Host "  you discover in game reaches everyone's QuestBank. No account, nothing to type."
  Write-Host ""
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  Stop-Tray

  # Settings: ours as they are (a reinstall keeps the WoW folder and what was sent), plus whatever the
  # old ForeverProbe Sync knew that ours doesn't
  $cfg = Read-Config
  if (-not $cfg) { $cfg = ConvertTo-Config $null }
  $legacy = Read-LegacyConfig
  if ($legacy) {
    if (-not $cfg.wowPath -and $legacy.wowPath) { $cfg.wowPath = $legacy.wowPath }
    foreach ($k in @($legacy.sent.Keys)) { if (-not $cfg.sent.ContainsKey($k)) { $cfg.sent[$k] = $legacy.sent[$k] } }
  }
  if ($WowPath) { $cfg.wowPath = $WowPath }
  if ($Endpoint) {
    if ($Endpoint -eq $DefaultEndpoint) { $cfg.endpointSet = "" } else { $cfg.endpointSet = $Endpoint }
  }
  Save-Config $cfg

  # (PowerShell names ignore case: $target, never $self, or $Self would be lost)
  $target = PathOf $AppDir $ScriptFile
  if ($Self -and -not ((Test-Path -LiteralPath $target) -and ((Resolve-Path -LiteralPath $target).Path -eq (Resolve-Path -LiteralPath $Self).Path))) {
    Copy-Item -LiteralPath $Self -Destination $target -Force
    $srcIco = PathOf (Split-Path -Parent $Self) $IconFile
    if (Test-Path -LiteralPath $srcIco) { Copy-Item -LiteralPath $srcIco -Destination (PathOf $AppDir $IconFile) -Force }
  }

  # only now that its settings are ours: the old uploader goes
  if (Remove-LegacyInstall) {
    $bits = "its tray icon and shortcuts are gone"
    $carried = 0
    if ($legacy) { $carried = $legacy.sent.Count }
    if ($carried -gt 0) { $bits += ", and what it already sent won't go again" }
    Write-Host ("  Replaced ForeverProbe Sync: " + $bits + ".")
    Log ("took over the old uploader's settings (" + $carried + " sent file(s))")
  }
  if (Test-TrayRunning $LegacyMutex) {
    Write-Host "  The old ForeverProbe Sync icon is still by the clock: right-click it and pick Exit." -ForegroundColor Yellow
  }
  if (Test-TrayRunning $TrayMutex) {
    Write-Host "  An older QuestBank Uploader icon is still by the clock: right-click it, pick Exit, then run Install.bat again." -ForegroundColor Yellow
  }

  if (-not $cfg.wowPath -and @(Get-GameFolders).Count -eq 0) {
    Write-Host "  No WoW game folder in the usual places. Pick your World of Warcraft folder"
    Write-Host "  in the window that opens (Cancel skips this; the tray menu can do it later)."
    $picked = Pick-WowFolder
    if ($picked) {
      $cfg.wowPath = $picked
      Save-Config $cfg
      Log ("WoW folder set to " + $picked)
      Write-Host ("  WoW folder: " + $picked)
    }
  }

  # Startup runs the tray at every login; the Start menu and Desktop icons open Status
  $dirs = Get-ShortcutDirs
  $trayArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"" + $target + "`" -Tray"
  $statusArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"" + $target + "`" -Status"
  $made = @()
  foreach ($s in @(
      @{ dir = $dirs.startup; args = $trayArgs; desc = "QuestBank Uploader in the tray" },
      @{ dir = $dirs.programs; args = $statusArgs; desc = "QuestBank Uploader: status and Send now" },
      @{ dir = $dirs.desktop; args = $statusArgs; desc = "QuestBank Uploader: status and Send now" })) {
    if (-not $s.dir -or -not (Test-Path -LiteralPath $s.dir)) { continue }
    $dest = PathOf $s.dir ($AppName + ".lnk")
    try {
      New-Shortcut $dest $s.args $s.desc
      $made += $dest
    } catch {
      Write-Host ("  Could not make the shortcut " + $dest + " :: " + $_.Exception.Message) -ForegroundColor Red
    }
  }

  Write-Host ""
  Install-QuestBankAddon $cfg
  Log "installed"
  Start-Tray

  Write-Host ""
  Write-Host "  Installed." -ForegroundColor Green
  Write-Host "  The QuestBank Uploader icon is in the system tray by the clock. It sends every"
  Write-Host "  30 minutes and comes back at every login; right-click it for Send now, Status"
  Write-Host "  and Exit. The desktop icon opens the same Status box."
  $found = @(Find-SavedVariables -Root $cfg.wowPath)
  if ($found.Count -eq 0) { Write-Host "  No QuestBank.lua yet: it appears after your first logout with QuestBank." }
  else { foreach ($f in $found) { Write-Host ("  Watching " + $f) } }
}

function Uninstall-Uploader {
  Stop-Tray
  Remove-LegacyTask | Out-Null
  foreach ($n in @($AppName, $LegacyName)) {
    foreach ($lnk in @(Get-ShortcutPaths $n)) {
      if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue }
    }
  }
  foreach ($d in @($AppDir, $LegacyDir)) {
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
  }
  Write-Host "QuestBank Uploader removed. The QuestBank addon and your saved files are as they were."
}

if ($Uninstall) {
  Uninstall-Uploader
  exit
}

if ($Install) {
  Install-Uploader
  Write-Host ""
  Read-Host "  Press Enter to close" | Out-Null
  exit
}

if ($Status) {
  Show-Status
  exit
}

if ($Tray) {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  Add-Type -AssemblyName System.Drawing | Out-Null

  # One icon in the tray is plenty; a second launch bows out quietly.
  $fresh = $false
  $mutex = New-Object System.Threading.Mutex($true, $TrayMutex, [ref]$fresh)
  if (-not $fresh) { exit }

  $icoFile = PathOf $AppDir $IconFile
  if (-not (Test-Path -LiteralPath $icoFile)) { $icoFile = PathOf (Split-Path -Parent $Self) $IconFile }
  $script:notify = New-Object System.Windows.Forms.NotifyIcon
  if (Test-Path -LiteralPath $icoFile) { $script:notify.Icon = New-Object System.Drawing.Icon($icoFile) }
  else { $script:notify.Icon = [System.Drawing.SystemIcons]::Application }
  $script:notify.Text = $AppName

  # $loud shows every outcome (Send now); the timer's passes show a balloon only when something went.
  $script:doSend = {
    param([bool]$loud)
    $msg = Send-Changes
    if ($loud -or $script:sentThisPass -gt 0) {
      $script:notify.BalloonTipTitle = $AppName
      $script:notify.BalloonTipText  = $msg
      $script:notify.ShowBalloonTip(4000)
    }
  }

  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  [void]$menu.Items.Add("Send now", $null, { & $script:doSend $true })
  [void]$menu.Items.Add("Status", $null, { Show-Status })
  [void]$menu.Items.Add("Choose WoW folder...", $null, {
    $picked = Pick-WowFolder
    if ($picked) {
      $cfg = Read-Config
      if ($cfg) {
        $cfg.wowPath = $picked
        Save-Config $cfg
        Log ("WoW folder set to " + $picked)
        & $script:doSend $true
      }
    }
  })
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  [void]$menu.Items.Add("Exit", $null, {
    $script:timer.Stop()
    $script:notify.Visible = $false
    $script:notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
  })
  $script:notify.ContextMenuStrip = $menu
  $script:notify.Visible = $true

  # First pass shortly after the icon appears, then every 30 minutes.
  $script:timer = New-Object System.Windows.Forms.Timer
  $script:timer.Interval = 15000
  $script:timer.Add_Tick({
    $script:timer.Interval = 1800000
    & $script:doSend $false
  })
  $script:timer.Start()
  Log "tray up"

  [System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
  $mutex.ReleaseMutex()
  exit
}

# Default (and -SendNow): one quiet pass
$result = Send-Changes
if ($SendNow) { Write-Host $result }
