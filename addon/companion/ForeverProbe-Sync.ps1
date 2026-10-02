# ForeverProbe Sync: sends what your addons noted to foreverrank.com, automatically.
#
# What it does, in full: finds SavedVariables\ForeverProbe.lua and SavedVariables\QuestBank.lua
# under your WoW game folders and, when either file changes (WoW writes them at logout and on
# /reload), uploads it to foreverrank.com's data endpoint. Nothing else is read, nothing runs
# inside the game, no account or login is involved, and you can read every line below.
# The site keeps no player names: only what the addons noted about quests, NPCs and XP.
#
# Install:   Install.bat (or: .\ForeverProbe-Sync.ps1 -Install)
# Running:   the sigil sits in your system tray and syncs every 30 minutes;
#            right-click it for Sync now / Status / Exit. Returns at login.
# Remove:    double-click Uninstall.bat (or: -Uninstall)

param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$SyncNow,
  [switch]$Tray,
  [string]$WowPath = "",
  [string]$Endpoint = ""
)

$DefaultEndpoint = "https://foreverrank.andustemme.workers.dev/api/probe"
$WatchFiles = @("ForeverProbe.lua", "QuestBank.lua")
$MaxBytes   = 6 * 1024 * 1024   # the endpoint's limit
$AddonVersion = "0.4.4"         # the ForeverProbe addon this companion ships with

$AppDir   = Join-Path $env:APPDATA "ForeverProbe"
$CfgFile  = Join-Path $AppDir "config.json"
$LogFile  = Join-Path $AppDir "sync.log"
$TaskName = "ForeverProbe Sync"   # older builds ran as a scheduled task

function Log([string]$msg) {
  $line = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $msg
  Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Read-Config {
  if (-not (Test-Path $CfgFile)) { return $null }
  $cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json
  # older builds (0.3) posted to a guild webhook; that key is dropped, the endpoint is the site's
  $endpoint = $DefaultEndpoint
  if ($cfg.PSObject.Properties["endpoint"] -and $cfg.endpoint) { $endpoint = [string]$cfg.endpoint }
  $sent = @{}
  if ($cfg.PSObject.Properties["sent"] -and $cfg.sent) { $cfg.sent.PSObject.Properties | ForEach-Object { $sent[$_.Name] = $_.Value } }
  $wow = ""
  if ($cfg.PSObject.Properties["wowPath"] -and $cfg.wowPath) { $wow = [string]$cfg.wowPath }
  return @{ endpoint = $endpoint; wowPath = $wow; sent = $sent }
}

function Save-Config($cfg) {
  @{ endpoint = $cfg.endpoint; wowPath = $cfg.wowPath; sent = $cfg.sent } | ConvertTo-Json | Set-Content -Path $CfgFile
}

function Find-SavedVariables {
  param([string]$Root)
  $roots = @()
  if ($Root) { $roots += $Root }
  $roots += @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft", "$env:USERPROFILE\World of Warcraft")
  $seen = @{}
  foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    # every game folder (_classic_beta_ for the Forever beta, and whatever live Forever gets); the root
    # itself counts too, when it is a game folder. A chosen folder that is also under a default root is
    # scanned once.
    $flavors = @(Get-ChildItem -LiteralPath $r -Directory -Filter "_*_" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $flavors += $r
    foreach ($f in $flavors) {
      $acct = Join-Path $f "WTF\Account"
      if (-not (Test-Path -LiteralPath $acct)) { continue }
      $key = (Resolve-Path -LiteralPath $acct).Path
      if ($seen[$key]) { continue }
      $seen[$key] = $true
      # WoW names each file after the addon (ForeverProbe.lua, QuestBank.lua), not after the variable inside
      # it; both are account-wide, so only Account\<account>\SavedVariables counts (never a character's folder)
      foreach ($a in @(Get-ChildItem -LiteralPath $acct -Directory -ErrorAction SilentlyContinue)) {
        foreach ($w in $WatchFiles) {
          $p = Join-Path $a.FullName (Join-Path "SavedVariables" $w)
          if (Test-Path -LiteralPath $p) { $p }
        }
      }
    }
  }
}

# One multipart POST: source=companion, file=<the saved file>. The reply is JSON:
# { ok, id, kind, summary, message } or { ok, duplicate } or { error }.
function Send-ToForeverRank {
  param([string]$Url, [string]$File)
  $boundary = [System.Guid]::NewGuid().ToString()
  $LF = "`r`n"
  $bytes = [System.IO.File]::ReadAllBytes($File)
  $enc = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
  $name = [System.IO.Path]::GetFileName($File)
  $pre = "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"source`"$LF$LF" + "companion" + $LF +
    "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"file`"; filename=`"$name`"$LF" +
    "Content-Type: text/plain$LF$LF"
  $post = "$LF--$boundary--$LF"
  # one byte array: PowerShell's + on two arrays makes an object[], which the web cmdlets would stringify
  [byte[]]$body = $enc.GetBytes($pre) + $bytes + $enc.GetBytes($post)
  try {
    return Invoke-RestMethod -Uri $Url -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body -TimeoutSec 60
  } catch {
    # the endpoint answers refusals with a JSON error line; surface it instead of the bare status
    $detail = ""
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
    elseif ($_.Exception.Response -and ($_.Exception.Response | Get-Member -Name GetResponseStream)) {
      try { $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $detail = $sr.ReadToEnd() } catch { }
    }
    $code = ""
    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    throw ("HTTP " + $code + " " + $detail).Trim()
  }
}

function Run-Sync {
  $cfg = Read-Config
  if (-not $cfg) { return "Not installed." }
  if (-not $script:failedLast) { $script:failedLast = @{} }
  if (-not $script:fileState) {
    $script:fileState = @{}
    foreach ($line in @(Find-AddonInstalls -Root $cfg.wowPath)) { Log $line }
  }
  $files = @(Find-SavedVariables -Root $cfg.wowPath)
  if ($files.Count -eq 0) {
    Log "no SavedVariables\ForeverProbe.lua or QuestBank.lua found"
    return "No ForeverProbe or QuestBank data found yet. Log a character out once with either addon installed."
  }
  $watched = ($files -join "; ")
  if ($script:lastWatched -ne $watched) {
    Log ("watching " + $files.Count + " file(s): " + $watched)
    $script:lastWatched = $watched
  }
  $posted = 0; $skipped = 0; $failed = 0
  foreach ($f in $files) {
    $hash = (Get-FileHash -Path $f -Algorithm SHA256).Hash
    if ($cfg.sent[$f] -eq $hash) { $skipped++; continue }
    $size = (Get-Item $f).Length
    if ($size -gt $MaxBytes) { $failed++; $script:failedLast[$f] = "over the 6 MB limit"; Log ("SKIPPED " + $f + " :: " + [math]::Round($size / 1MB, 1) + " MB is over the 6 MB limit"); continue }
    try {
      $r = Send-ToForeverRank -Url $cfg.endpoint -File $f
      if ($r -and $r.ok) {
        $cfg.sent[$f] = $hash
        $script:failedLast.Remove($f)
        $posted++
        if ($r.duplicate) { Log ("already there: " + $f) }
        else {
          $bits = @()
          if ($r.summary -and $r.summary.quests -ne $null) { $bits += ($r.summary.quests.ToString() + " quests noted") }
          if ($r.summary -and $r.summary.level -ne $null) { $bits += ("level " + $r.summary.level) }
          Log ("sent " + $f + " :: upload #" + $r.id + " (" + $r.kind + ") " + ($bits -join ", "))
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
  }
  Save-Config $cfg
  # each file's state in the log when it changes (and once per tray start), never on every pass
  $descs = @($files | ForEach-Object { Describe-File $_ $cfg })
  # (the tray only: a Status click or -SyncNow is a process of its own and would log them all again)
  if ($Tray) {
    foreach ($d in $descs) {
      if ($script:fileState[$d.path] -ne $d.key) {
        $script:fileState[$d.path] = $d.key
        Log ($d.text -replace "`n\s*", " :: ")
      }
    }
  }
  $note = (Probe-Verdict $descs).note
  if ($failed -gt 0) { return "Sent $posted, failed $failed. See sync.log in $AppDir." }
  if ($posted -gt 0) { return "Sent $posted update(s) to foreverrank.com." + $note }
  if ($skipped -gt 0 -and $posted -eq 0) { return "Nothing new in $skipped file(s) since the last upload." + $note }
  return "Everything already sent. Nothing new since your last session."
}

function Stop-Tray {
  # Ends any running tray instance (an older build's included) so install and
  # uninstall never leave a stale sigil behind.
  try {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match "ForeverProbe-Sync" -and $_.CommandLine -match "-Tray" -and $_.ProcessId -ne $PID } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
}

# What each watched file is: which account, how big, when the game last wrote it, which addon version wrote
# it, and whether it changed since it was last sent. Only version fields and dates are read; never names.
# ForeverProbe.lua written by a ForeverProbe older than 0.4 is stale: 0.4 has not saved on that account since.
function Describe-File($f, $cfg) {
  $item = Get-Item -LiteralPath $f -ErrorAction SilentlyContinue
  if (-not $item) { return @{ text = $f + "`n   gone"; old = $false; key = "gone"; path = $f } }
  # <game folder>\WTF\Account\<account>\SavedVariables\<file>: the names after WTF\Account, never a character's
  $acctDir = Split-Path (Split-Path $f -Parent) -Parent
  $acct = Split-Path $acctDir -Leaf
  $flavor = Split-Path (Split-Path (Split-Path (Split-Path $acctDir -Parent) -Parent) -Parent) -Leaf
  $kb = [math]::Max(1, [math]::Round($item.Length / 1KB))
  $inv = [System.Globalization.CultureInfo]::InvariantCulture
  $when = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm", $inv)
  $writer = "an unknown version"
  $old = $false
  try {
    $body = [System.IO.File]::ReadAllText($f)
    if ($item.Name -eq "ForeverProbe.lua") {
      if ($body -match '\["cleu"\]|\["c_namespaces"\]') { $writer = "the beta-day probe (0.1.0)"; $old = $true }
      elseif ($body -match '\["schema"\]') {
        # 0.4 sets schema on first use but writes its version only with a snapshot (and 0.4.3 when it greets)
        $writer = "ForeverProbe 0.4 or newer (no snapshot saved yet)"
        if ($body -match '\["greeted"\]\s*=\s*"(\d+\.\d+\.\d+)"') { $writer = "ForeverProbe " + $Matches[1] }
        elseif ($body -match '\["addon"\]\s*=\s*"(\d+\.\d+\.\d+)"' -and [version]$Matches[1] -ge [version]"0.4.0") { $writer = "ForeverProbe " + $Matches[1] }
      }
      elseif ($body -match '\["addon"\]\s*=\s*"([^"]+)"') { $writer = "ForeverProbe 0.3 or older (it called itself " + $Matches[1] + ")"; $old = $true }
    } else {
      # QuestBank keeps the version in every snapshot it saved; the highest is the one that wrote the file
      $vs = @([regex]::Matches($body, '\["(?:version|qb)"\]\s*=\s*"(\d+\.\d+\.\d+)"') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending)
      if ($vs.Count -gt 0) { $writer = "QuestBank " + $vs[0].ToString() }
    }
  } catch { }
  $state = "not sent yet"
  try {
    $hash = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
    if ($cfg.sent[$f] -eq $hash) { $state = "sent, unchanged since" } elseif ($cfg.sent[$f]) { $state = "changed since the last send" }
  } catch { }
  if ($script:failedLast -and $script:failedLast[$f]) { $state = "failed last time: " + $script:failedLast[$f] }
  $text = $item.Name + " (" + $flavor + ", account " + $acct + ")`n   " + $kb + " KB, written " + $when + " by " + $writer + "; " + $state
  return @{ text = $text; old = $old; name = $item.Name; when = $when; written = $item.LastWriteTime; writer = $writer; acct = $acct; flavor = $flavor; path = $f; dir = (Split-Path $f -Parent); key = ($when + "|" + $writer + "|" + $state) }
}

# Where the ForeverProbe addon itself sits in each game folder: right, out of date, one folder too deep, under
# another folder name, or missing. Reads only the .toc's Version and Interface lines.
function Read-Toc($toc) {
  $lines = @(Get-Content -LiteralPath $toc -TotalCount 12 -ErrorAction SilentlyContinue)
  $ver = ($lines | Where-Object { $_ -match '^##\s*Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
  $ifc = ($lines | Where-Object { $_ -match '^##\s*Interface:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
  $older = $false
  try { if ($ver -and [version]$ver -lt [version]"0.4.0") { $older = $true } } catch { }
  return @{ ver = $ver; iface = $ifc; older = $older }
}

function Find-AddonInstalls {
  param([string]$Root)
  $out = @()
  $roots = @()
  if ($Root) { $roots += $Root }
  $roots += @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft", "$env:USERPROFILE\World of Warcraft")
  $seen = @{}
  foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    $flavors = @(Get-ChildItem -LiteralPath $r -Directory -Filter "_*_" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $flavors += $r
    foreach ($fl in $flavors) {
      $addons = Join-Path $fl "Interface\AddOns"
      if (-not (Test-Path -LiteralPath $addons)) { continue }
      $full = (Resolve-Path -LiteralPath $addons).Path
      if ($seen[$full]) { continue }
      $seen[$full] = $true
      $label = Split-Path $fl -Leaf
      $toc = Join-Path $addons "ForeverProbe\ForeverProbe.toc"
      $deep = Join-Path $addons "ForeverProbe\ForeverProbe\ForeverProbe.toc"
      if (Test-Path -LiteralPath $toc) {
        $t = Read-Toc $toc
        $line = "ForeverProbe addon " + $t.ver + " (interface " + $t.iface + ") in " + $label
        if ($t.older) { $line += ": out of date, install " + $AddonVersion + " over it" }
        if (Test-Path -LiteralPath $deep) {
          $d = Read-Toc $deep
          $line += ". A copy (" + $d.ver + ") also sits one folder too deep, in AddOns\ForeverProbe\ForeverProbe; the game loads the outer one. Replace the outer folder with the inner one."
        }
        $out += $line
      } elseif (Test-Path -LiteralPath $deep) {
        $d = Read-Toc $deep
        $out += ("ForeverProbe addon " + $d.ver + " in " + $label + " is one folder too deep: AddOns\ForeverProbe\ForeverProbe. Move the inner ForeverProbe folder up one level, into AddOns.")
      } else {
        $hit = $null; $nested = $false
        foreach ($dir in @(Get-ChildItem -LiteralPath $addons -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "ForeverProbe" })) {
          if (Test-Path -LiteralPath (Join-Path $dir.FullName "ForeverProbe.toc")) { $hit = $dir; break }
          if (Test-Path -LiteralPath (Join-Path $dir.FullName "ForeverProbe\ForeverProbe.toc")) { $hit = $dir; $nested = $true; break }
        }
        if ($hit -and $nested) {
          $out += ("ForeverProbe addon in " + $label + " sits inside AddOns\" + $hit.Name + "\ForeverProbe. Move that inner ForeverProbe folder into AddOns.")
        } elseif ($hit) {
          $out += ("ForeverProbe addon in " + $label + " sits in AddOns\" + $hit.Name + ". The game only loads it from a folder named exactly ForeverProbe: rename it.")
        } else {
          # "missing" only where QuestBank or ForeverProbe has saved: other game folders are none of our business
          $saves = @(Get-ChildItem -LiteralPath (Join-Path $fl "WTF\Account") -Directory -ErrorAction SilentlyContinue |
            Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName "SavedVariables\QuestBank.lua")) -or (Test-Path -LiteralPath (Join-Path $_.FullName "SavedVariables\ForeverProbe.lua")) })
          if ($saves.Count -gt 0) { $out += ("ForeverProbe addon: not found in " + $label + "\Interface\AddOns") }
        }
      }
    }
  }
  return $out
}

# Why ForeverProbe.lua isn't uploading, if something looks wrong: @{ hint = the sentence for Status; note = the
# few words for the balloon }. An old-format file can be stale (written long ago) or fresh (an old ForeverProbe
# still loaded and saving); a stale file is moot when a newer 0.4 file exists elsewhere.
function Probe-Verdict($descs) {
  $fp = @($descs | Where-Object { $_.name -eq "ForeverProbe.lua" } | Sort-Object { $_.written } -Descending)
  $qb = @($descs | Where-Object { $_.name -eq "QuestBank.lua" })
  $now = Get-Date
  $where = { param($d) $d.flavor + ", account " + $d.acct }
  $check = "In game, type /qb probe: it says whether ForeverProbe is missing, switched off or out of date."
  if ($qb.Count -eq 0) { $check = "When ForeverProbe loads it says ""ForeverProbe " + $AddonVersion + " is running"" in chat; /probe opens its panel. If you never see that, check the AddOns list at the character screen." }
  $modern = @($fp | Where-Object { -not $_.old })
  foreach ($d in $fp) {
    if (-not $d.old) { continue }
    $beside = @($qb | Where-Object { $_.dir -eq $d.dir })
    $fresh = (($now - $d.written).TotalDays -lt 3) -or ($beside.Count -gt 0 -and [math]::Abs(($beside[0].written - $d.written).TotalDays) -lt 1)
    if ($fresh) {
      return @{ hint = ("ForeverProbe.lua in " + (& $where $d) + " was written " + $d.when + " by " + $d.writer + ": an old ForeverProbe is still loaded there and saving. Install ForeverProbe " + $AddonVersion + " from foreverrank.com/addon over it."); note = (" An old ForeverProbe is loaded in " + $d.flavor + ": install " + $AddonVersion + ".") }
    }
    if (@($modern | Where-Object { $_.written -gt $d.written }).Count -gt 0) { continue } # left behind; a newer one saves elsewhere
    return @{ hint = ("ForeverProbe.lua in " + (& $where $d) + " was last written " + $d.when + " by " + $d.writer + ". ForeverProbe " + $AddonVersion.Substring(0, 3) + " has not saved there since, so there is nothing new to send. " + $check + " If you no longer use ForeverProbe there, delete that file and this note goes away."); note = (" ForeverProbe.lua in " + $d.flavor + " hasn't changed since " + $d.when.Substring(0, 10) + ": right-click the sigil, Status.") }
  }
  foreach ($d in $modern) {
    foreach ($q in @($qb | Where-Object { $_.dir -eq $d.dir })) {
      if (($q.written - $d.written).TotalDays -gt 3) {
        return @{ hint = ("ForeverProbe.lua in " + (& $where $d) + " was last written " + $d.when + ", " + [math]::Floor(($q.written - $d.written).TotalDays) + " days before QuestBank.lua next to it: QuestBank has saved since, ForeverProbe has not. " + $check); note = "" }
      }
    }
  }
  if ($fp.Count -eq 0 -and $qb.Count -gt 0) {
    return @{ hint = ("No ForeverProbe.lua anywhere: ForeverProbe has never saved. That's fine if you don't run it; QuestBank.lua uploads on its own."); note = "" }
  }
  return @{ hint = ""; note = "" }
}

function Show-Status {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $cfg = Read-Config
  if (-not $cfg) {
    [System.Windows.Forms.MessageBox]::Show("ForeverProbe Sync is not installed. Run Install.bat first.", "ForeverProbe Sync") | Out-Null
    return
  }
  $files = @(Find-SavedVariables -Root $cfg.wowPath)
  $where = "the usual install folders"
  if ($cfg.wowPath) { $where = $cfg.wowPath }
  $list = "none found yet: log a character out once with ForeverProbe or QuestBank installed"
  $hint = ""
  if ($files.Count -gt 0) {
    $descs = @($files | Select-Object -First 6 | ForEach-Object { Describe-File $_ $cfg })
    $list = (@($descs | ForEach-Object { $_.text })) -join "`n"
    $v = Probe-Verdict $descs
    if ($v.hint) { $hint = "`n`n" + $v.hint }
  }
  if ($files.Count -gt 6) { $list = $list + "`n... and " + ($files.Count - 6) + " more" }
  $installs = @(Find-AddonInstalls -Root $cfg.wowPath)
  $addonLines = ""
  if ($installs.Count -gt 0) { $addonLines = "`n`n" + ($installs -join "`n") }
  $tail = "never"
  if (Test-Path $LogFile) {
    $t = @(Get-Content $LogFile -Tail 5)
    if ($t.Count -gt 0) { $tail = $t -join "`n" }
  }
  $msg = "WoW folder: " + $where + "`n`nWatching " + $files.Count + " saved file(s), every account under WTF\Account:`n" + $list + $hint + $addonLines +
    "`n`nLast activity:`n" + $tail + "`n`nIf your game lives elsewhere, right-click the sigil and pick Choose WoW folder.`n`nSync now?"
  $r = [System.Windows.Forms.MessageBox]::Show($msg, "ForeverProbe Sync", [System.Windows.Forms.MessageBoxButtons]::YesNo)
  if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
    $result = Run-Sync
    [System.Windows.Forms.MessageBox]::Show($result, "ForeverProbe Sync") | Out-Null
  }
}

if ($Uninstall) {
  schtasks /Delete /TN "$TaskName" /F 2>$null | Out-Null
  Stop-Tray
  foreach ($lnk in @((Join-Path ([Environment]::GetFolderPath("Programs")) "ForeverProbe Sync.lnk"),
                     (Join-Path ([Environment]::GetFolderPath("Desktop")) "ForeverProbe Sync.lnk"),
                     (Join-Path ([Environment]::GetFolderPath("Startup")) "ForeverProbe Sync.lnk"))) {
    if (Test-Path $lnk) { Remove-Item -Force $lnk }
  }
  if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
  Write-Host "ForeverProbe Sync removed completely."
  exit
}

function Show-Banner {
  $sigil = @'

           ..o000o..           ..o000o..
        o0'         '0o     o0'         '0o
       0               '0o0'              0
       0               .o0o.              0
        o0.         .0o     o0.         .0o
           ''o000o''           ''o000o''

        F O R E V E R P R O B E   S Y N C
'@
  Write-Host $sigil -ForegroundColor Yellow
  Write-Host "        foreverrank.com  ::  what you see, everyone learns" -ForegroundColor DarkGray
  Write-Host ""
}

if ($Install) {
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  Show-Banner
  Write-Host "  What ForeverProbe and QuestBank note in game ships to foreverrank.com"
  Write-Host "  automatically after each session. Nothing to type, no account."
  Write-Host ""
  $ep = $DefaultEndpoint
  if ($Endpoint) { $ep = $Endpoint }
  Save-Config @{ endpoint = $ep; wowPath = $WowPath; sent = @{} }
  $self = Join-Path $AppDir "ForeverProbe-Sync.ps1"
  Copy-Item -Force $MyInvocation.MyCommand.Path $self
  $srcIco = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "ForeverProbe.ico"
  $ico = Join-Path $AppDir "ForeverProbe.ico"
  if (Test-Path $srcIco) { Copy-Item -Force $srcIco $ico }
  # The tray replaced the scheduled task; retire one an older build left behind.
  schtasks /Delete /TN "$TaskName" /F 2>$null | Out-Null
  Stop-Tray
  $trayArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Tray"
  # A clickable face: Start Menu and Desktop shortcuts that open the status box.
  # The shell's own folder answers are used, so OneDrive-redirected Desktops work.
  $ws = New-Object -ComObject WScript.Shell
  # The tray at every login: a shortcut in the Startup folder.
  try {
    $startupDir = [string]$ws.SpecialFolders.Item("Startup")
    if ($startupDir) {
      $lnk = $ws.CreateShortcut((Join-Path $startupDir "ForeverProbe Sync.lnk"))
      $lnk.TargetPath = "powershell.exe"
      $lnk.Arguments = $trayArgs
      $lnk.WorkingDirectory = $AppDir
      if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
      $lnk.Description = "ForeverProbe Sync tray"
      $lnk.Save()
    }
  } catch {
    Write-Host ("  Could not add the Startup entry :: " + $_.Exception.Message) -ForegroundColor Red
  }
  $spots = @()
  try { $spots += [string]$ws.SpecialFolders.Item("Programs") } catch { }
  try { $spots += [string]$ws.SpecialFolders.Item("Desktop") } catch { }
  $od = Join-Path $env:USERPROFILE "OneDrive\Desktop"
  if ((Test-Path $od) -and ($spots -notcontains $od)) { $spots += $od }
  foreach ($dir in $spots) {
    if (-not $dir -or -not (Test-Path $dir)) { continue }
    $dest = Join-Path $dir "ForeverProbe Sync.lnk"
    try {
      $lnk = $ws.CreateShortcut($dest)
      $lnk.TargetPath = "powershell.exe"
      $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Status"
      $lnk.WorkingDirectory = $AppDir
      if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
      $lnk.Description = "ForeverProbe Sync: click for status and a manual sync"
      $lnk.Save()
      Write-Host ("  Icon created: " + $dest) -ForegroundColor Green
    } catch {
      Write-Host ("  Could not create icon at " + $dest + " :: " + $_.Exception.Message) -ForegroundColor Red
    }
  }
  Log "installed"
  Start-Process powershell -ArgumentList "-NoProfile","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",$self,"-Tray" -WindowStyle Hidden
  Write-Host ""
  Write-Host "  Installed." -ForegroundColor Green
  Write-Host "  The sigil is in your system tray by the clock. It syncs every 30"
  Write-Host "  minutes and shows a balloon when an update ships; right-click it"
  Write-Host "  for Sync now, Status and Exit. It comes back at every login, and"
  Write-Host "  the desktop icon opens the same status box."
  $found = @(Find-SavedVariables -Root $WowPath)
  if ($found.Count -eq 0) { Write-Host "  Note: no ForeverProbe or QuestBank data found yet; it appears after your first logout with either addon." }
  else { Write-Host ("  Watching: " + ($found -join ", ")) }
  Write-Host ""
  Read-Host "  Press Enter to close"
  exit
}

if ($Status) {
  Show-Status
  exit
}

if ($Tray) {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  Add-Type -AssemblyName System.Drawing | Out-Null

  # One sigil in the tray is plenty; a second launch bows out quietly.
  $fresh = $false
  $mutex = New-Object System.Threading.Mutex($true, "ForeverProbeSyncTray", [ref]$fresh)
  if (-not $fresh) { exit }

  $icoFile = Join-Path $AppDir "ForeverProbe.ico"
  if (-not (Test-Path $icoFile)) { $icoFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "ForeverProbe.ico" }
  $script:notify = New-Object System.Windows.Forms.NotifyIcon
  if (Test-Path $icoFile) { $script:notify.Icon = New-Object System.Drawing.Icon($icoFile) }
  else { $script:notify.Icon = [System.Drawing.SystemIcons]::Application }
  $script:notify.Text = "ForeverProbe Sync"

  # $loud balloons every outcome (manual sync); quiet passes balloon only sends.
  $script:doSync = {
    param([bool]$loud)
    $msg = Run-Sync
    if ($loud -or $msg -like "Sent *") {
      $script:notify.BalloonTipTitle = "ForeverProbe Sync"
      $script:notify.BalloonTipText  = $msg
      $script:notify.ShowBalloonTip(4000)
    }
  }

  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  [void]$menu.Items.Add("Sync now", $null, { & $script:doSync $true })
  [void]$menu.Items.Add("Status", $null, { Show-Status })
  [void]$menu.Items.Add("Choose WoW folder...", $null, {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Pick your World of Warcraft folder (the one holding _classic_beta_), or the _classic_beta_ folder itself."
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
      $cfg = Read-Config
      if ($cfg) {
        $cfg.wowPath = $dlg.SelectedPath
        Save-Config $cfg
        Log ("WoW folder set to " + $dlg.SelectedPath)
        & $script:doSync $true
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

  # First pass shortly after the sigil appears, then every 30 minutes.
  $script:timer = New-Object System.Windows.Forms.Timer
  $script:timer.Interval = 15000
  $script:timer.Add_Tick({
    $script:timer.Interval = 1800000
    & $script:doSync $false
  })
  $script:timer.Start()
  Log "tray up"

  [System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
  $mutex.ReleaseMutex()
  exit
}

# Default (and -SyncNow): one quiet sync pass, for shortcuts and old tasks.
$result = Run-Sync
if ($SyncNow) { Write-Host $result }
