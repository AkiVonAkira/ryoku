%global debug_package %{nil}
%global hyprland_evr %(rpm -q --qf '%%{EVR}' hyprland)
Name:           ryoku-keysounds
Version:        0.1
Release:        1%{?dist}
Summary:        Keyboard sound plugin for Hyprland
License:        GPL-3.0-or-later AND MIT
URL:            https://ryoku.dev
Source0:        ryoku-%{version}.tar.gz
BuildRequires:  bash
BuildRequires:  coreutils
BuildRequires:  ffmpeg-free
BuildRequires:  findutils
BuildRequires:  gcc-c++
BuildRequires:  libcanberra-devel
BuildRequires:  libdrm-devel
BuildRequires:  make
BuildRequires:  pkgconf-pkg-config
BuildRequires:  pixman-devel
BuildRequires:  python3
BuildRequires:  hyprland-devel
Requires:       hyprland%{?_isa} = %{hyprland_evr}
Requires:       libcanberra

%description
Ryoku's Hyprland key sound plugin and switch recording profiles, built against
the exact compositor ABI.

%prep
%setup -q -n ryoku-%{version}

%build
export RYOKU_PKGVER=%{version}
bash fedora/packages/rpm/stage-package.sh %{name} "$PWD/stage" %{_libdir}

%install
cp -a stage/. %{buildroot}/
find %{buildroot} -type f -o -type l | sed 's|^%{buildroot}||' > rpm-files

%files -f rpm-files
