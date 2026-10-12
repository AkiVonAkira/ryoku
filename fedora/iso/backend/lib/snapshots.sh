#!/usr/bin/env bash

# The @snapshots subvolume is created and mounted; snapper and snapshot boot
# entries are not wired on Fedora yet.
fedora_snapshots() {
  if [[ ${RYOKU_SUBVOL_SNAPSHOTS:-1} != 1 ]]; then
    ryoku_snapshots_disabled
    return 0
  fi
  log 'snapshots: @snapshots is mounted at /.snapshots; snapper is not configured on Fedora yet'
}
