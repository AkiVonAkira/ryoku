#!/usr/bin/env bash

# The same plan ryoku-shell-installer's readEditionPackages resolves when it
# converts an existing Fedora system.
fedora_desktop_install() {
  local -a args=(--lane desktop) drop_args=() packages=()
  local lane id lanes plan
  lanes=$(ryoku_profile_lanes) || exit 1
  while IFS= read -r lane; do args+=(--lane "$lane"); done <<<"$lanes"
  [[ $RYOKU_COMPOSITOR != hyprland ]] || args+=(--lane hyprland)
  for id in "${RYOKU_COMPOSITOR_CHOICES[@]}"; do
    [[ $id == "$RYOKU_COMPOSITOR" ]] || args+=(--drop "ryoku-desktop-$id")
  done
  mapfile -t drop_args < <(ryoku_resolver_drop_args)
  args+=("${drop_args[@]}")
  plan=$(fedora_resolve "${args[@]}") || die 'could not resolve the Ryoku desktop package plan'
  mapfile -t packages <<<"$plan"
  fedora_dedupe packages
  ((${#packages[@]})) || die 'the Ryoku desktop package plan is empty'

  log 'installing the Ryoku desktop (%d packages)' "${#packages[@]}"
  fedora_dnf install "${packages[@]}"
}

fedora_deploy_user() {
  local user=$RYOKU_USERNAME
  ryoku_seed_keymap
  ryoku_deploy_chown "$user"
  ryoku_deploy_materialize "$user"
  ryoku_seed_provisioned "$user"
  ryoku_deploy_seed "/mnt/home/$user"
  ryoku_deploy_chown "$user"
  ryoku_deploy_qylock
}
