#!/bin/bash
# Diagnostic capture for the unresolved install-finish auto-reboot. The reboot is
# a clean systemd reboot, so the boot journal records which process/unit requested
# it — but the live session's journal is volatile and gone after the reboot. This
# runs at the live session's shutdown (the service's ExecStop, before systemd
# pivots away) and copies this boot's journal onto the freshly-installed target's
# ESP (FAT, unencrypted, survives the reboot). After a real-hardware recurrence,
# read /boot/efi/shedos-reboot-journal.txt on the installed system. Best-effort;
# never blocks or fails the shutdown.
set +e

log=/run/shedos-reboot-journal.txt
{
    date -u
    echo "--- live-session shutdown/reboot; boot journal follows (look for the reboot requester) ---"
    journalctl -b -o short-monotonic --no-pager
} > "$log" 2>&1

esp_guid="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
while read -r dev parttype; do
    [ "${parttype,,}" = "$esp_guid" ] || continue
    m=$(mktemp -d) || continue
    if mount "$dev" "$m" 2>/dev/null; then
        # Only the freshly-installed target ESP carries the ShedOS boot chain;
        # skip the live USB's own ESP so we write to the installed system.
        if [ -d "$m/EFI/limine" ] || [ -d "$m/EFI/Linux" ]; then
            cp "$log" "$m/shedos-reboot-journal.txt" 2>/dev/null
            sync
        fi
        umount "$m" 2>/dev/null
    fi
    rmdir "$m" 2>/dev/null
done < <(lsblk -rno PATH,PARTTYPE 2>/dev/null)

exit 0
