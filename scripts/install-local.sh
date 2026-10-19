#!/bin/sh
set -eu

task_source=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [maki-data-directory]" >&2
  exit 2
fi
if [ "$#" -eq 1 ]; then
  task_data=$1
elif [ -d "$HOME/.maki" ]; then
  task_data=$HOME/.maki
else
  task_data=${XDG_DATA_HOME:-$HOME/.local/share}/maki
fi
task_target=$task_data/site/pack/user/start/maki-auto-approve
if [ -e "$task_target" ] || [ -L "$task_target" ]; then
  echo "Refusing to replace existing package: $task_target" >&2
  exit 1
fi
mkdir -p -- "$(dirname -- "$task_target")"
ln -s -- "$task_source" "$task_target"
echo "Installed local package: $task_target -> $task_source"
echo "Restart Maki or run /reload. Existing chats reuse their recorded user instructions."
