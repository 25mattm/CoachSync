#!/bin/sh
# Fails when app code discards a save error with `try?`.
#
# A swallowed save looks like success to the coach: the form closes, the data is gone on
# relaunch, and the outbox never syncs it (the 2026-10-29 audit found eight of these). User
# actions must `try SyncStore.save` and show the error; background housekeeping should call
# `SyncStore.saveLoggingFailure`. A genuinely intentional `try?` save stays allowed when its
# line carries a `swallowed-save-ok: <reason>` comment.
#
# Usage: scripts/check-swallowed-saves.sh   (from the repo root; CI runs it on every push)

set -eu
cd "$(dirname "$0")/.."

hits=$(grep -rnE 'try\?[[:space:]]*([A-Za-z_][A-Za-z0-9_.]*\.)?save\(' \
           --include='*.swift' CoachSync CoachSyncMac \
       | grep -v 'swallowed-save-ok:' || true)

if [ -n "$hits" ]; then
    echo "Save errors discarded with try? (surface them, use SyncStore.saveLoggingFailure, or"
    echo "add a 'swallowed-save-ok: <reason>' comment):"
    echo "$hits"
    exit 1
fi
echo "No swallowed saves."
