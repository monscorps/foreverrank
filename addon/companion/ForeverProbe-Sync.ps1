# ForeverProbe Sync: ships your ForeverProbe data to the guild automatically.
#
# What it does, in full: finds ForeverProbeDB.lua under your WoW beta's
# SavedVariables and, when the file changes (WoW writes it at logout and on
# /reload), posts it to the guild's private Discord webhook. Nothing else is
# read, nothing runs inside the game, and you can read every line below.
#
# Install:   double-click Install.bat (or: .\ForeverProbe-Sync.ps1 -Install)
# Status:    click the ForeverProbe Sync icon (or: -Status)
# Remove:    double-click Uninstall.bat (or: -Uninstall)

param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$SyncNow,
  [string]$WowPath = ""
)

$AppDir   = Join-Path $env:APPDATA "ForeverProbe"
$CfgFile  = Join-Path $AppDir "config.json"
$LogFile  = Join-Path $AppDir "sync.log"
$TaskName = "ForeverProbe Sync"

function Log([string]$msg) {
  $line = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $msg
  Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Find-SavedVariables {
  param([string]$Root)
  $roots = @()
  if ($Root) { $roots += $Root }
  $roots += @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft", "$env:USERPROFILE\World of Warcraft")
  foreach ($r in $roots) {
    foreach ($flavor in @("_beta_", "_ptr_", "_retail_")) {
      $acct = Join-Path (Join-Path $r $flavor) "WTF\Account"
      if (Test-Path $acct) {
        Get-ChildItem -Path $acct -Recurse -Filter "ForeverProbeDB.lua" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
      }
    }
  }
}

function Send-ToWebhook {
  param([string]$Webhook, [string]$File, [string]$Mark)
  $boundary = [System.Guid]::NewGuid().ToString()
  $LF = "`r`n"
  $bytes = [System.IO.File]::ReadAllBytes($File)
  $enc = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
  $who = $env:USERNAME
  $tag = ""
  if ($Mark) { $tag = "[" + $Mark + "] " }
  $pre = "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"payload_json`"$LF$LF" +
    ('{"content":"' + $tag + 'ForeverProbe drop from **' + $who + '**, ' + (Get-Date -Format "yyyy-MM-dd HH:mm") + '"}') + $LF +
    "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"file`"; filename=`"ForeverProbeDB.lua`"$LF" +
    "Content-Type: application/octet-stream$LF$LF"
  $post = "$LF--$boundary--$LF"
  $body = $enc.GetBytes($pre) + $bytes + $enc.GetBytes($post)
  Invoke-RestMethod -Uri $Webhook -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body | Out-Null
}

function Run-Sync {
  if (-not (Test-Path $CfgFile)) { return "Not installed." }
  $cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json
  $sentHashes = @{}
  if ($cfg.sent) { $cfg.sent.PSObject.Properties | ForEach-Object { $sentHashes[$_.Name] = $_.Value } }
  $files = @(Find-SavedVariables -Root $cfg.wowPath)
  if ($files.Count -eq 0) { Log "no ForeverProbeDB.lua found"; return "No ForeverProbe data found yet. Log a character out once with the addon installed." }
  $posted = 0; $skipped = 0; $failed = 0
  foreach ($f in $files) {
    $hash = (Get-FileHash -Path $f -Algorithm SHA256).Hash
    if ($sentHashes[$f] -eq $hash) { $skipped++; continue }
    try {
      Send-ToWebhook -Webhook $cfg.webhook -File $f -Mark $cfg.mark
      $sentHashes[$f] = $hash
      $posted++
      Log ("sent " + $f)
    } catch {
      $failed++
      Log ("FAILED " + $f + " :: " + $_.Exception.Message)
    }
  }
  $cfg.sent = $sentHashes
  $cfg | ConvertTo-Json | Set-Content -Path $CfgFile
  if ($failed -gt 0) { return "Sent $posted, failed $failed. See sync.log in $AppDir." }
  if ($posted -gt 0) { return "Sent $posted update(s) to the guild." }
  return "Everything already sent. Nothing new since your last session."
}

if ($Uninstall) {
  schtasks /Delete /TN "$TaskName" /F 2>$null | Out-Null
  foreach ($lnk in @((Join-Path ([Environment]::GetFolderPath("Programs")) "ForeverProbe Sync.lnk"),
                     (Join-Path ([Environment]::GetFolderPath("Desktop")) "ForeverProbe Sync.lnk"))) {
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
  Write-Host "        foreverrank.com  ::  the guild sees what you see" -ForegroundColor DarkGray
  Write-Host ""
}

if ($Install) {
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  Show-Banner
  Write-Host "  Your play data ships to the guild automatically after each session."
  Write-Host ""
  # The guild key ships in the download; nobody types anything.
  $here = Split-Path $MyInvocation.MyCommand.Path
  $hook = ""; $mark = ""
  $keyFile = Join-Path $here "guild.key"
  $hookFile = Join-Path $here "webhook.txt"
  if (Test-Path $keyFile) {
    try {
      $raw = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Get-Content $keyFile -Raw).Trim()))
      $parts = $raw.Split("|")
      $hook = $parts[0]
      if ($parts.Count -gt 1) { $mark = $parts[1] }
      Write-Host "  Guild key found. No typing needed." -ForegroundColor Green
    } catch { }
  }
  if (-not $hook -and (Test-Path $hookFile)) {
    $hook = (Get-Content $hookFile -Raw).Trim()
    Write-Host "  Found webhook.txt. No typing needed." -ForegroundColor Green
  }
  if (-not $hook) { $hook = Read-Host "  Paste the guild's Discord webhook URL" }
  if (-not $hook.StartsWith("https://discord.com/api/webhooks/")) { Write-Host "  That does not look like a Discord webhook URL."; exit 1 }
  @{ webhook = $hook; mark = $mark; wowPath = $WowPath; sent = @{} } | ConvertTo-Json | Set-Content -Path $CfgFile
  $self = Join-Path $AppDir "ForeverProbe-Sync.ps1"
  Copy-Item -Force $MyInvocation.MyCommand.Path $self
  $srcIco = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "ForeverProbe.ico"
  $ico = Join-Path $AppDir "ForeverProbe.ico"
  if (Test-Path $srcIco) { Copy-Item -Force $srcIco $ico }
  $action = "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`""
  schtasks /Create /TN "$TaskName" /TR $action /SC MINUTE /MO 30 /F | Out-Null
  # A clickable face: Start Menu and Desktop shortcuts that open the status box.
  $ws = New-Object -ComObject WScript.Shell
  foreach ($dest in @((Join-Path ([Environment]::GetFolderPath("Programs")) "ForeverProbe Sync.lnk"),
                      (Join-Path ([Environment]::GetFolderPath("Desktop")) "ForeverProbe Sync.lnk"))) {
    $lnk = $ws.CreateShortcut($dest)
    $lnk.TargetPath = "powershell.exe"
    $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Status"
    if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
    $lnk.Description = "ForeverProbe Sync: click for status and a manual sync"
    $lnk.Save()
  }
  Log "installed"
  Write-Host ""
  Write-Host "  Installed." -ForegroundColor Green
  Write-Host "  It runs quietly every 30 minutes. Click the ForeverProbe Sync icon"
  Write-Host "  on your desktop any time to see status or push a sync right now."
  $found = @(Find-SavedVariables -Root $WowPath)
  if ($found.Count -eq 0) { Write-Host "  Note: no ForeverProbe data found yet; it appears after your first logout with the addon." }
  else { Write-Host ("  Watching: " + ($found -join ", ")) }
  Write-Host ""
  Read-Host "  Press Enter to close"
  exit
}

if ($Status) {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  if (-not (Test-Path $CfgFile)) {
    [System.Windows.Forms.MessageBox]::Show("ForeverProbe Sync is not installed. Run Install.bat first.", "ForeverProbe Sync") | Out-Null
    exit
  }
  $last = "never"
  if (Test-Path $LogFile) {
    $tail = Get-Content $LogFile -Tail 1
    if ($tail) { $last = $tail }
  }
  $files = @(Find-SavedVariables -Root ((Get-Content $CfgFile -Raw | ConvertFrom-Json).wowPath))
  $msg = "Watching " + $files.Count + " ForeverProbe file(s).`n`nLast activity:`n" + $last + "`n`nSync now?"
  $r = [System.Windows.Forms.MessageBox]::Show($msg, "ForeverProbe Sync", [System.Windows.Forms.MessageBoxButtons]::YesNo)
  if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
    $result = Run-Sync
    [System.Windows.Forms.MessageBox]::Show($result, "ForeverProbe Sync") | Out-Null
  }
  exit
}

# Default (and -SyncNow): one quiet sync pass; this is what the task runs.
Run-Sync | Out-Null
