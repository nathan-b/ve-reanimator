# VoidExpanse reanimator

You're playing VoidExpanse, and you keep dying. It's super annoying because you just want to enjoy the game. Unfortunately, the lowest difficulty level is still too punishing. All you want is the ability to save your game and restore it when you die. Is that too much to ask?

This program is for you.

## What it does

It watches your save directory and keeps the latest 3 saves. If you die, it notices that too and puts the save somewhere else.

When you die, all you have to do is select "Save and Quit" in the game. Then switch to the Reanimator window and restore the latest good save.

## Configuring it

The program generally works without any configuration. To change its behavior, create a file named `ve-reanimator.yaml`. The program looks for it in the current directory first, then in `~/.config/ve-reanimator/`. Every option is optional.

  ```yaml
  saves_dir: ~/path/to/VoidExpanse/Saves   # game save directory (default: autodiscovered)
  max_saves: 3                             # normal saves to keep, 1-16
  archive_dir: ~/.cache/ve-reanimator      # where normal saves are kept
  death_dir: death                         # where death saves are kept
  max_death_saves: 1                       # death saves to keep, 1-16
  ```

  | Option | Default | Notes |
  |---|---|---|
  | `saves_dir` | autodiscovered | The folder containing `slot_0`, `slot_1`, and so on. |
  | `max_saves` | `3` | Rotation is per slot. The oldest save is deleted first. |
  | `archive_dir` | `~/.cache/ve-reanimator` | |
  | `death_dir` | `death` | A relative path is relative to `archive_dir`. |
  | `max_death_saves` | `1` | |

  - `~` is expanded. A relative `saves_dir` or `archive_dir` is relative to the config file's directory.
  - Unknown options and out-of-range values are reported as errors at startup.

  ### Finding the save directory

  The save directory is taken from the first of these that applies:

  1. The command-line argument: `ve-reanimator [--headless] [SAVES_DIR]`
  2. `saves_dir` in the config file
  3. Autodiscovery, which checks the usual Steam (Proton and Flatpak), native Linux, and Windows locations and uses the one with the newest save

  ## Does it work on Windows?

  IDK, if you try it and it does, let me know! If not, open an issue.
