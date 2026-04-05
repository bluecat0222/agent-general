---
name: restart
description: Restart Claude Code by scheduling a restart and exiting the process
---

Restart Claude Code. Follow these steps exactly:

1. Save any important context to memory first
2. Detect the current tmux session name and project directory by running:
```bash
tmux display-message -p '#{session_name}'
```
3. Use the current working directory as the project directory
4. Call the restart script in **single** mode with the session name and project dir:
```bash
~/bin/cc-restart.sh single <session-name> <project-dir>
```
5. The script forks to background and returns immediately. After 10 seconds it will kill the claude process in this tmux pane and restart it.

Note: To restart ALL claude sessions at once, use:
```bash
~/bin/cc-restart.sh all
```
This scans all tmux sessions for running claude processes, kills them, and restarts each one.
