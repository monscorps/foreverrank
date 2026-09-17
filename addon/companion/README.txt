ForeverProbe Sync (Windows companion, optional)
================================================

Sends your ForeverProbe play data to the guild automatically, so you
never have to export by hand. The game itself never sends anything;
this small script runs outside WoW, watches one file, and posts it to
the guild's private Discord when it changes.

Setup, once:
  Double-click "ForeverProbe Setup.exe" at the top of the zip, or
  Install.bat in this folder -- they are the same installer. The guild
  key ships in this folder (guild.key), so there is nothing to type.

After install the sigil sits in your system tray, by the clock. It
syncs every 30 minutes on its own, shows a balloon when an update
ships to the guild, and starts again with Windows. Right-click it:

  Sync now   push an update this second
  Status     what it watches and when it last ran
  Exit       stop it until the next login

The ForeverProbe Sync icon on your desktop opens the same status box.

Remove completely any time: double-click Uninstall.bat.

Everything the installer and tray do is readable in
ForeverProbe-Sync.ps1; the setup exe's whole source is Launcher.cs.
