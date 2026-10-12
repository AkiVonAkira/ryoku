#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$PROFILE_DIR/../.." && pwd)
TUI_DIR=$REPO_ROOT/installation/tui
BACKEND_DIR=$PROFILE_DIR/backend
SHARED_BACKEND=$REPO_ROOT/installation/backend/lib
LIVE_FILES=$REPO_ROOT/installation/iso/airootfs

OUT_DIR=${RYOKU_FEDORA_ISO_OUT:-$PROFILE_DIR/out}
WORK_DIR=${RYOKU_FEDORA_ISO_WORK:-$PROFILE_DIR/work}
STAGE_DIR=${RYOKU_FEDORA_ISO_STAGE:-$WORK_DIR/staging}
DESCRIPTION=$STAGE_DIR/description
ROOTFS=$DESCRIPTION/root
CONTAINER_ENGINE=${RYOKU_CONTAINER_ENGINE:-docker}
CONTAINER_IMAGE=${RYOKU_FEDORA_ISO_IMAGE:-registry.fedoraproject.org/fedora:44}
# The frozen Fedora 44 release repository keeps this version installable; updates moves on.
KIWI_VERSION=${RYOKU_FEDORA_KIWI_VERSION:-10.3.0}
REPO_BASE=${RYOKU_FEDORA_ISO_REPO_BASE:-https://repo.ryoku.dev/stable/fedora/44}
KEY_URL=${RYOKU_FEDORA_ISO_KEY_URL:-https://repo.ryoku.dev/stable/ryoku-release-key.pub.asc}
KEY_FINGERPRINT=EB6D3C0F55A7B3CABA6B2838847B274F025DD6E3
ARCH=x86_64

log() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
die() { printf 'fedora ISO build: error: %s\n' "$*" >&2; exit 1; }

usage() {
	printf 'usage: %s [--stage-only]\n' "${0##*/}" >&2
	exit 2
}

STAGE_ONLY=0
case ${1:-} in
	'') ;;
	--stage-only) STAGE_ONLY=1 ;;
	*) usage ;;
esac
[[ $# -le 1 ]] || usage

for command in git go tar; do
	command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done
[[ -f $BACKEND_DIR/ryoku-install ]] || die "Fedora backend not found: $BACKEND_DIR/ryoku-install"
[[ -d $BACKEND_DIR/lib ]] || die "Fedora backend library not found: $BACKEND_DIR/lib"

if commit_epoch=$(git -C "$REPO_ROOT" log -1 --pretty=%ct 2>/dev/null) && [[ -n $commit_epoch ]]; then
	SOURCE_DATE_EPOCH=$commit_epoch
fi
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(date +%s)}
export SOURCE_DATE_EPOCH

PAYLOAD_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)
PAYLOAD_DATE=$(git -C "$REPO_ROOT" log -1 --pretty=%cI 2>/dev/null || date -Iseconds)
PAYLOAD_VERSION=$(tr -d '[:space:]' < "$REPO_ROOT/VERSION" 2>/dev/null || printf unknown)
PAYLOAD_NAME=$(tr -d '[:space:]' < "$REPO_ROOT/CODENAME" 2>/dev/null || printf unknown)
# testing until stable/fedora/44 is published.
case ${RYOKU_FEDORA_ISO_CHANNEL:-testing} in
	stable) PAYLOAD_CHANNEL=stable; RYOKU_REPO=$REPO_BASE/$ARCH ;;
	testing) PAYLOAD_CHANNEL=testing; RYOKU_REPO=$REPO_BASE/channels/testing/$ARCH ;;
	*) die "RYOKU_FEDORA_ISO_CHANNEL must be stable or testing" ;;
esac
RYOKU_REPO=${RYOKU_FEDORA_ISO_RYOKU_REPO:-$RYOKU_REPO}
ISO_NAME=ryoku-fedora-${PAYLOAD_VERSION}-${ARCH}.iso

stage_repo() {
	local destination=$1
	mkdir -p "$destination"
	if [[ ${RYOKU_FEDORA_ISO_WORKTREE:-0} == 1 ]]; then
		log "Baking tracked and untracked, non-ignored working-tree files"
		(
			cd "$REPO_ROOT"
			git ls-files -co --exclude-standard -z \
				| LC_ALL=C sort -z \
				| tar --null --no-recursion --ignore-failed-read --files-from=- -cf -
		) | tar -C "$destination" -xf -
	else
		git -C "$REPO_ROOT" archive --format=tar HEAD | tar -C "$destination" -xf -
	fi
}

log "Staging kiwi description at $DESCRIPTION"
rm -rf "$STAGE_DIR"
mkdir -p "$ROOTFS"
cp -a "$PROFILE_DIR/kiwi"/. "$DESCRIPTION/"

# Fedora boots with systemd like the Arch image, so the Arch live session files apply unchanged.
log "Staging the shared live session"
for file in \
	etc/hostname \
	etc/motd \
	etc/NetworkManager/conf.d/wifi-backend.conf \
	etc/systemd/system/getty@tty1.service.d/autologin.conf \
	root/.bash_profile \
	root/.zlogin \
	usr/local/bin/ryoku-install \
	usr/local/bin/ryoku-installer-session; do
	mode=0644
	[[ $file == usr/local/bin/* ]] && mode=0755
	install -D -m"$mode" "$LIVE_FILES/$file" "$ROOTFS/$file"
done
sed -i \
	-e "s|@RYOKU_NAME@|$PAYLOAD_NAME|g" \
	-e "s|@RYOKU_VERSION@|$PAYLOAD_VERSION|g" \
	-e "s|@RYOKU_COMMIT@|${PAYLOAD_COMMIT:0:12}|g" \
	"$ROOTFS/etc/motd"

log "Building static ryoku-tui"
install -d "$ROOTFS/usr/local/bin"
(
	cd "$TUI_DIR"
	CGO_ENABLED=0 go build -trimpath -ldflags '-s -w -buildid=' \
		-o "$ROOTFS/usr/local/bin/ryoku-tui" .
)

log "Staging Fedora installer backend"
install -d "$ROOTFS/usr/local/lib/ryoku/backend/lib" "$ROOTFS/usr/local/lib/ryoku/backend/shared"
install -m0755 "$BACKEND_DIR/ryoku-install" "$ROOTFS/usr/local/lib/ryoku/backend/ryoku-install"
cp -a "$BACKEND_DIR/lib"/. "$ROOTFS/usr/local/lib/ryoku/backend/lib/"
for library in common i18n choices preflight disk resize luks filesystem snapshots network deploy; do
	install -m0644 "$SHARED_BACKEND/$library.sh" \
		"$ROOTFS/usr/local/lib/ryoku/backend/shared/$library.sh"
done

log "Baking repository payload"
stage_repo "$ROOTFS/usr/share/ryoku"
cat > "$ROOTFS/usr/share/ryoku/.payload" <<EOF
commit=$PAYLOAD_COMMIT
date=$PAYLOAD_DATE
version=$PAYLOAD_VERSION
name=$PAYLOAD_NAME
channel=$PAYLOAD_CHANNEL
EOF
printf 'fedora\n' > "$ROOTFS/usr/share/ryoku/variant"

log "Installing translation catalog"
install -d "$ROOTFS/usr/share/ryoku/i18n"
install -m0644 "$REPO_ROOT"/ryoku/i18n/catalog/*.json "$ROOTFS/usr/share/ryoku/i18n/"
install -m0644 "$REPO_ROOT/ryoku/i18n/langs.json" "$ROOTFS/usr/share/ryoku/i18n/langs.json"

log "Staged kiwi description at $DESCRIPTION"
if ((STAGE_ONLY)); then
	log "--stage-only: skipping kiwi-ng"
	exit 0
fi

command -v "$CONTAINER_ENGINE" >/dev/null 2>&1 \
	|| die "$CONTAINER_ENGINE is required for the privileged kiwi-ng build"

mkdir -p "$OUT_DIR" "$WORK_DIR"
OUT_DIR=$(cd "$OUT_DIR" && pwd -P)
WORK_DIR=$(cd "$WORK_DIR" && pwd -P)
STAGE_DIR=$(cd "$STAGE_DIR" && pwd -P)
rm -f "$OUT_DIR/$ISO_NAME" "$OUT_DIR/SHA256SUMS"

run=("$CONTAINER_ENGINE" run --rm --platform linux/amd64 --privileged
	-v /dev:/dev
	-v "$WORK_DIR:/work"
	-v "$OUT_DIR:/out"
	-v "$STAGE_DIR:/stage"
	-w /work
	-e "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
	-e "RYOKU_KIWI_VERSION=$KIWI_VERSION"
	-e "RYOKU_REPO=$RYOKU_REPO"
	-e "RYOKU_KEY_URL=$KEY_URL"
	-e "RYOKU_KEY_FINGERPRINT=$KEY_FINGERPRINT"
	-e "RYOKU_ISO_NAME=$ISO_NAME"
	-e "HOST_UID=$(id -u)"
	-e "HOST_GID=$(id -g)"
	"$CONTAINER_IMAGE")

inner=$(cat <<'INNER'
set -euo pipefail
restore_owner() {
	chown -R "$HOST_UID:$HOST_GID" /out /work /stage 2>/dev/null || true
}
trap restore_owner EXIT

dnf -y -q install \
	"kiwi-cli-$RYOKU_KIWI_VERSION" \
	"kiwi-systemdeps-iso-media-$RYOKU_KIWI_VERSION" \
	"kiwi-systemdeps-filesystems-$RYOKU_KIWI_VERSION" \
	"kiwi-systemdeps-bootloaders-$RYOKU_KIWI_VERSION" \
	distribution-gpg-keys gnupg2 >/dev/null

rm -rf /work/key /work/kiwi-target /work/tmp
install -d -m0700 /work/key /work/key/gnupg
curl -fsSL --retry 3 --proto =https -o /work/key/release-key.asc "$RYOKU_KEY_URL"
GNUPGHOME=/work/key/gnupg gpg --batch --quiet --import /work/key/release-key.asc
primary=$(GNUPGHOME=/work/key/gnupg gpg --batch --with-colons --fingerprint \
	| awk -F: '$1 == "pub" { want = 1; next } want && $1 == "fpr" { print $10; want = 0 }')
[[ $primary == "$RYOKU_KEY_FINGERPRINT" ]] \
	|| { printf 'fedora ISO build: release key must be exactly %s\n' "$RYOKU_KEY_FINGERPRINT" >&2; exit 1; }

# kiwi copies SELinux-labelled files through its temp dir; the container's
# overlay /var/tmp cannot store those labels, the mounted /work can.
install -d /work/tmp
kiwi-ng --temp-dir /work/tmp --type iso system build \
	--description /stage/description \
	--target-dir /work/kiwi-target \
	--add-repo "$RYOKU_REPO,rpm-md,ryoku,90" \
	--signing-key /work/key/release-key.asc

iso=$(find /work/kiwi-target -maxdepth 1 -name '*.iso' -print -quit)
[[ -n $iso ]] || { printf 'fedora ISO build: kiwi-ng produced no ISO\n' >&2; exit 1; }
mv "$iso" "/out/$RYOKU_ISO_NAME"
rm -rf /work/kiwi-target /work/key /work/tmp
INNER
)

log "Building the live ISO with kiwi-ng $KIWI_VERSION in $CONTAINER_IMAGE"
"${run[@]}" bash -euo pipefail -c "$inner"

[[ -s $OUT_DIR/$ISO_NAME ]] || die "ISO build did not produce $OUT_DIR/$ISO_NAME"
(
	cd "$OUT_DIR"
	sha256sum -- "$ISO_NAME" > SHA256SUMS
)
log "ISO and SHA256SUMS written to $OUT_DIR"
