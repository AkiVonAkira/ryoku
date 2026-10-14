#!/usr/bin/env bash

# build.sh bakes the release key, verified against its fingerprint, into the live image.
FEDORA_KEY_PATH=/etc/pki/rpm-gpg/RPM-GPG-KEY-ryoku

fedora_channel() {
  local channel=
  [[ -r $RYOKU_REPO/.payload ]] && channel=$(awk -F= '$1 == "channel" { print $2 }' "$RYOKU_REPO/.payload")
  printf '%s' "${channel:-stable}"
}

# Same URLs and override as ryoku-shell-installer's fedoraRepository.
fedora_ryoku_repo_url() {
  if [[ -n ${RYOKU_RPM_REPO:-} ]]; then
    printf '%s' "$RYOKU_RPM_REPO"
  elif [[ $(fedora_channel) == testing ]]; then
    printf '%s' 'https://repo.ryoku.dev/stable/fedora/$releasever/channels/testing/x86_64'
  else
    printf '%s' 'https://repo.ryoku.dev/stable/fedora/$releasever/x86_64'
  fi
}

fedora_repo_preflight() {
  local url
  url=$(fedora_ryoku_repo_url)
  url=${url//\$releasever/$RYOKU_FEDORA_RELEASEVER}
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    log 'preflight: would require %s, the Fedora %s mirrors, and %s before any disk write' \
      "$url" "$RYOKU_FEDORA_RELEASEVER" "$FEDORA_KEY_PATH"
    return 0
  fi
  [[ -r $FEDORA_KEY_PATH ]] \
    || die 'the live image carries no Ryoku release key at %s; the disk has not been touched' "$FEDORA_KEY_PATH"
  curl -fsS --max-time 20 -o /dev/null "$url/repodata/repomd.xml" \
    || die 'cannot reach the Ryoku RPM repository at %s; the disk has not been touched' "$url"
  curl -fsS --max-time 20 -o /dev/null \
    "https://mirrors.fedoraproject.org/metalink?repo=fedora-$RYOKU_FEDORA_RELEASEVER&arch=x86_64" \
    || die 'cannot reach the Fedora %s mirrors; the disk has not been touched' "$RYOKU_FEDORA_RELEASEVER"
  log 'preflight: Ryoku RPM repository and Fedora mirrors reachable'
}

fedora_repo_target() {
  local url channel
  url=$(fedora_ryoku_repo_url)
  channel=$(fedora_channel)
  log 'configuring the signed Ryoku RPM repository (%s channel) in the target' "$channel"
  run install -Dm644 "$FEDORA_KEY_PATH" "/mnt$FEDORA_KEY_PATH"
  run rpm --root /mnt --import "/mnt$FEDORA_KEY_PATH"
  run mkdir -p /mnt/etc/yum.repos.d
  write_file /mnt/etc/yum.repos.d/ryoku.repo <<EOF
[ryoku]
name=Ryoku
baseurl=$url
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://$FEDORA_KEY_PATH
EOF
  fedora_repo_coprs
  run mkdir -p /mnt/var/lib/ryoku
  write_file /mnt/var/lib/ryoku/channel-intent <<<"$channel"
}

# The restricted COPRs from fedora/packages/coprs.tsv, written as the converter writes them.
fedora_repo_coprs() {
  local table=$RYOKU_REPO/fedora/packages/coprs.tsv project includepkgs base slug
  [[ -r $table ]] || die 'Fedora COPR table is missing: %s' "$table"
  while IFS=$'\t' read -r project includepkgs _; do
    [[ -n $project && $project != \#* && $project != copr ]] || continue
    slug=${project//\//-}
    base=https://download.copr.fedorainfracloud.org/results/$project
    write_file "/mnt/etc/yum.repos.d/ryoku-copr-$slug.repo" <<EOF
[ryoku-copr-$slug]
name=Ryoku dependency: $project
baseurl=$base/fedora-\$releasever-\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=$base/pubkey.gpg
includepkgs=$includepkgs
skip_if_unavailable=1
EOF
  done <"$table"
}
