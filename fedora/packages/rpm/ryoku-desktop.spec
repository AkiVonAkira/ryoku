Name:           ryoku-desktop
Version:        0.1
Release:        1%{?dist}
Summary:        ryoku-desktop desktop component
License:        GPL-3.0-or-later
URL:            https://ryoku.dev
Source0:        ryoku-%{version}.tar.gz
%global debug_package %{nil}
BuildRequires:  bash
BuildRequires:  coreutils
BuildRequires:  findutils
BuildRequires:  gtk3-devel
BuildRequires:  webkit2gtk4.1-devel
BuildRequires:  golang >= 1.26.4
BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
Requires:       ryoku = %{version}-%{release}
Requires(post): ryoku = %{version}-%{release}
Requires:       ryoku-shell = %{version}-%{release}
Requires:       ryogami = %{version}-%{release}
Requires:       ryoku-hub = %{version}-%{release}
Requires:       ryoku-rashin = %{version}-%{release}
Requires:       ryoku-blobs = %{version}-%{release}
Requires:       ryoku-extras = %{version}-%{release}
Requires:       sddm-theme-ryoku = %{version}-%{release}
Requires:       ryoku-desktop-compositor
Requires:       dnf
Requires:       gpk
Requires:       quickshell >= 0.3.0
Requires:       gpu-screen-recorder
Requires:       wl-clip-persist
Requires:       ryoku-cursor-material
Requires:       xorg-x11-server-Xwayland
Requires:       qt6-qtwayland
Requires:       qt5-qtwayland
Requires:       qt6-qt5compat
Requires:       qt6-qtsvg
Requires:       qt6-qtimageformats
Requires:       qt6-qtmultimedia
Requires:       qt6-qtdeclarative
Requires:       gtk3
Requires:       webkit2gtk4.1
Requires:       weston
Requires:       xdg-desktop-portal-gtk
Requires:       adw-gtk3-theme
Requires:       papirus-icon-theme
Requires:       kf6-syntax-highlighting
Requires:       brightnessctl
Requires:       playerctl
Requires:       mpv
Requires:       mpv-mpris
Requires:       yt-dlp
Requires:       wl-clipboard
Requires:       cliphist
Requires:       grim
Requires:       slurp
Requires:       cava
Requires:       python3
Requires:       pipewire
Requires:       jq
Requires:       ImageMagick
Requires:       ffmpeg-free
Requires:       curl
Requires:       zenity
Requires:       iw
Requires:       nftables
Requires:       bluez
Requires:       pam-u2f
Requires:       rtkit
Requires:       rsms-inter-fonts
Requires:       google-noto-sans-fonts
Requires:       google-noto-serif-fonts
Requires:       google-noto-sans-mono-fonts
Requires:       google-noto-sans-cjk-fonts
Requires:       google-noto-emoji-fonts
Requires:       tesseract
Requires:       tesseract-langpack-eng
Requires:       zbar
Requires:       wtype
Requires:       libqalculate
Requires:       upower
Requires:       ppd-service
Requires:       ddcutil
Requires:       hypridle
Requires:       hyprpicker
Requires:       kernel-devel
Requires:       kernel-headers
Requires:       dkms

Recommends:     power-profiles-daemon
Suggests:       kitty
Suggests:       fish
Suggests:       blesh
Suggests:       zsh
Suggests:       zsh-autosuggestions
Suggests:       zsh-history-substring-search
Suggests:       zsh-syntax-highlighting
Suggests:       ryoku-oh-my-zsh
Suggests:       starship
Suggests:       fastfetch
Suggests:       yazi
Suggests:       neovim
Suggests:       nautilus
Suggests:       nautilus-python
Suggests:       ryotunes
Suggests:       waifu2x-ncnn-vulkan
Suggests:       pavucontrol
Suggests:       songrec
Suggests:       openrgb
Suggests:       gamescope
Suggests:       gamemode
Suggests:       mangohud
Suggests:       chromium
Suggests:       kdialog
Suggests:       plasma-integration
Suggests:       qemu
Suggests:       libvirt
Suggests:       edk2-ovmf
Suggests:       swtpm
Suggests:       quickemu
Suggests:       libisoburn
Suggests:       spice-gtk
Suggests:       spice-gtk-tools
Suggests:       picocom
Suggests:       telnet
Suggests:       freerdp
Suggests:       tigervnc
Suggests:       asusctl
Suggests:       ryoku-extras

Provides:       ryostore
Provides:       ryovm
Provides:       ryoku-ui = %{version}-%{release}
Obsoletes:      ryostore < 0.2
Obsoletes:      ryovm < 0.2
Obsoletes:      ryoku-ui < 0.2

%description
ryoku-desktop, built from the shared Ryoku source and package payload recipe.

%prep
%setup -q -n ryoku-%{version}

%build
export RYOKU_PKGVER=%{version}
bash fedora/packages/rpm/stage-package.sh %{name} "$PWD/stage" %{_libdir}

%install
cp -a stage/. %{buildroot}/
find %{buildroot} \( -type f -o -type l \) -print0 | python3 -c 'import os,sys; root=os.fsencode(sys.argv[1]); [print("\"" + os.fsdecode(p[len(root):]).replace("\\", "\\\\").replace("\"", "\\\"") + "\"") for p in sys.stdin.buffer.read().split(bytes([0])) if p]' %{buildroot} > rpm-files

%pre
[ -d /run/systemd/system ] || exit 0
systemd-detect-virt --quiet --chroot && exit 0
helper=/usr/bin/ryoku-power-cutover
[ -x "$helper" ] && exec "$helper" prepare-package
systemctl is-active --quiet ryoku-power-cutover-guard.service && exit 0
systemctl reset-failed ryoku-power-cutover-guard.service >/dev/null 2>&1 || :
systemd-run --quiet --collect --unit=ryoku-power-cutover-guard.service \
  --property=Type=exec --property=TimeoutStopSec=5s \
  /usr/bin/systemd-inhibit --what=sleep --mode=block \
  --who=ryoku-package-cutover \
  --why="keep sessions awake while packaged suspend owners are replaced" \
  /usr/bin/sleep infinity

%post
systemctl daemon-reload >/dev/null 2>&1 || :
RYOKU_HOST_INIT=systemd /usr/bin/ryoku-host svc reconcile --system >/dev/null 2>&1 || :
/usr/bin/ryoku-bluetooth-tune >/dev/null 2>&1 || :
/usr/bin/ryoku-wifi-regdom apply >/dev/null 2>&1 || :

%posttrans
[ -d /run/systemd/system ] || exit 0
systemd-detect-virt --quiet --chroot && exit 0
[ -x /usr/bin/ryoku-power-cutover ] || exit 0
if ! /usr/bin/ryoku-power-cutover package; then
  logger -t ryoku-power-cutover \
    "ryoku-desktop post-transaction cutover failed; package transaction continues" \
    >/dev/null 2>&1 || :
fi
exit 0

%preun
[ "$1" -eq 0 ] || exit 0
[ -d /run/systemd/system ] || exit 0
systemd-detect-virt --quiet --chroot && exit 0
[ -x /usr/bin/ryoku-power-cutover ] || exit 0
/usr/bin/ryoku-power-cutover prepare-package

%postun
[ "$1" -eq 0 ] || exit 0
if [ -x /run/ryoku-power-cutover ]; then
  /run/ryoku-power-cutover package
fi
if [ -d /run/systemd/system ]; then
  systemctl reload systemd-logind >/dev/null 2>&1 || :
fi

%files -f rpm-files
