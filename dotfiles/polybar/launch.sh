#!/bin/sh
# Kill any running polybar instances, then launch on the primary monitor.
# Called from i3 config via exec_always so it re-runs on every reload.
pkill -x polybar || true
polybar main 2>/dev/null &
