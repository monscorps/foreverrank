QuestBank Uploader (Windows, optional)
======================================

Sends what QuestBank (or Cute) noted in the world to foreverrank.com
after the game writes it (at logout and on /reload), so what you
discover in game reaches everyone's QuestBank. No account, no key,
nothing to type. Only the parts of QuestBank.lua and Cute_Quest.lua
that hold no name leave your PC; Cute.lua is never read. Once a day
it brings back what players' games found and agree on, in the
QuestBank_Finds addon.

Setup, once: double-click Install.bat in this folder. It also puts the
QuestBank addon from this download into your game's Interface\AddOns.
A copy you already have is updated (the old one is kept as
Interface\QuestBank.bak); where there is none, it asks once. The copy
that comes with Cute never puts QuestBank in: copy its Cute and
Cute_Quest folders into Interface\AddOns yourself, as with Cute alone.
QuestBank_Finds goes in beside QuestBank or Cute, also when you add
them after Install.

Then the QuestBank Uploader icon sits in the system tray by the clock.
It sends every 30 minutes and starts again with Windows. Right-click it:

  Send now            send right away
  Status              your game folders with the QuestBank in each,
                      every saved file it watches (size, when the
                      game wrote it, which QuestBank wrote it, sent or
                      not) and the last lines of its log
  Choose WoW folder   when WoW lives somewhere other than the usual
                      install folders
  Exit                stop it until the next login

The QuestBank Uploader icon on your desktop opens the same Status box.
Its log is %APPDATA%\QuestBank Uploader\uploader.log.

Remove it any time: double-click Uninstall.bat. The QuestBank addon and
your saved files stay.

Not on Windows? Upload QuestBank.lua by hand at
https://foreverrank.com/questbank/

Everything it does is readable in QuestBank-Uploader.ps1.
