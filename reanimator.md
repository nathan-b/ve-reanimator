# Reanimator VoidExpanse helper

This project is a helper program for the game VoidExpanse, designed to remove player frustration around the
harsh penalties imposed upon death.

## Overview

The project will take a save directory for VoidExpanse. It will watch that save directory, and whenever the
game autosaves it will grab the save files and put them in an archive directory. This directory will contain
archives for the last N autosaves, rotated and pruned by timestamp. 

N will likely be configurable. We'll start with N = 3 as a default.

If the program notices that the new autosave has an empty inventory, it will begin storing saves in a different 
place (I'm going to call this 'respawn mode').

The intended behavior is that, upon death, the user chooses "save and exit" inside VoidExpanse to leave the 
game. This will produce another save, but that save will still have an empty inventory and will thus overwrite
the death save, not the primary save. The user can then select one of the primary autosaves to restore (likely the 
latest one) and recover their inventory. If the player chooses to continue playing, once they put something
in their inventory, the process will stop detecting death and start putting saves into the primary save storage
again.

## Design decisions

### Implementation language

Options:

**go**

I know that go has a robust, cross-platform filesystem monitoring library. It also has a few UI options, such as
wails, for a GUI if desired. As a general-purpose cross-platform programming language, go has the power to do
anything we want to do. It also might be overkill for something like this.

**ruby**

I'm more familiar with ruby than go, as I've been using it longer. Ruby integrates well with gtk3 for GUI programming,
and is a very mature scripting language. Ruby doesn't have native support for cross-platform filesystem monitoring,
but the popular Listen gem implements such support and is pretty robust and cross-platform.
 
**Decision**

Let's use ruby

## User interface

**gui**

A gui is generally more useable and discoverable for casual users. They can add a lot of complexity to the code, but
for a situation like managing game save backups it's easier for the user to specify intent and make sure that the
right actions are taken.

**tui**

Terminal UIs are becoming more popular. I personally feel like they're just as complicated code-wise as GUIs but
less usable. However, they don't require choosing a GUI framework, which is nice.

**cli**

Of course, it may be possible to implement the desired functionality just by using a command-line interface. This
approach is the least user-friendly, and it's still a bit complicated because it requires IPC between the CLI
process and a backgrounded daemon. I personally prefer CLIs to GUIs much of the time.

**Decision**

Leaning toward GUI

## Implementation phases

There are several phases to this project:

### Phase 0: Save file research

The VoidExpanse save file format is actually several files:

```
nathan@nathanb-dev ..icTorchStudio/VoidExpanse/Saves/slot_0 % ls
save.data  save_info.data  screenshot.jpg  world.data
```

The particularly relevant file is `world.data`, as that file contains (among many other things) the player's inventory.

We will need to research the save file to determine how inventory is represented. Note that we do not need to resolve
inventory to specific item names, just determine whether or not the inventory is empty.

Output will be a vesave.md file in `doc/` inside the project directory describing the results of the research.

### Phase 1: File system watcher

Implement the FS watcher portion of the program.

To simplify matters, we will only trigger on `world.data`.

To test the work, we will build a test harness that spins off a thread. The thread can receive a message that will
trigger a write to the simulated `world.data`.

### Phase 2: Save file archiver

Integrate into the FS watcher notification path to build the save file archive. 

For Phase 2, the save file archive can use a hard-coded path (`/tmp/ve-reanimator/`). A config system will come in 
a later phase.

This phase will include save file roation. The max number of saves will be 3, with a future path to configurability.
The entire save slot directory will be saved, and the directory will be timestamped. For instance, there might be
`/tmp/ve-reanimator/slot_0_20261006_180629/`, which would indicate that the file was created a bit after 6pm October 6.

The test harness will be extended to validate that every time a change is triggered, the save directory gets copied
into the archive path. Furthermore, it will determine that when triggered more than three times, the oldest entry is
victimized.

### Phase 3: Death detector

For phase 3, we will implement the death detector module.

The module itself is simple; it in fact is a single function which takes a save file and returns a boolean: is this a
"death" save or a normal save?

However, under the hood there's a decent amount of complexity: the module will need to decompress world.data (using
the thrice-accursed zip format rather than the much more reasonable gzip) and parse the significantly large JSON file
that results. Even using well-optimized command-line tools like `jq` make my fairly fast computer think for a noticeable
tick before producing results.

Once the JSON file is parsed, we will use the research conducted in Phase 0 to implement the detector module and wire it
up to the FS watcher notification. The result of the detector will determine whether the saves go to the primary
location or the secondary (death) location, which for now is hard-coded to `/tmp/ve-reanimator/death`.

The test harness will be extended to generate both death and non-death saves on command to test both the module
directly and also the end-to-end behavior.

### Phase 4: Configuration

Phase 4 introduces a config file. The config file is named ve-reanimator.yaml and can either exist in the current
directory or in `~/.config/ve-reanimator`. There are five configurable options:

1. Number of saves to back up. Valid values are 1 - 16. Default is 3.
2. Primary path for storing the saves. Default will become `~/.cache/ve-reanimator`. Can be absolute or relative.
3. Secondary path for storing death saves. Default is `death`. Can be absolute or relative.
4. Number of death saves. Valid values are 1 - 16. Default is 1.
5. Path to game save directory.

This phase will also implement autodiscovery of save file path. You can use `~/tmp/gamehax/sh/shtool/lib/gamedir_locator.rb`
and `~/src/x3_save_manager/pathfinder.rb` as reference material.

### Phase 5: GUI

Create the GUI. I envision a two-column layout. In the right-hand column is a tabbed ui. The main tab is labeled
"Good saves" and the secondary tab is labeled "Death saves". Both tabs contain a single list box listing the saves
of its respective type, newest at the top and descending from there. In the left-hand column is a stack of buttons. 
From top to bottom:
* Restore selected save
* Delete selected save
* Manual backup

Along the bottom is a status bar which indicates whether the program is watching the directory and which directory
it is watching.

