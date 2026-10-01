%define cmake_build_dir build
%define sname vacuum
%define libname libvacuumutils37
%define git_hash 50338b2b07ad9179bf486230a05e61794b1181d2
%define git_date 1789587446
%define git_human_date 2026.09.16.22.37
%define git_short_id 50338b2b

Name:           vacuum-im
Version:        1.3.0~git.%{git_human_date}
Release:        1.%{git_short_id}%{?dist}
Summary:        Client application for the Jabber network
License:        GPLv3+
URL:            http://www.vacuum-im.org
Source0:        vacuum-im-%{git_short_id}.tar.gz
Patch0:         01-custom-settings.patch

# Build dependencies
BuildRequires:  cmake >= 3.7
BuildRequires:  qt5-qtbase-devel
BuildRequires:  qt5-qttools-devel
BuildRequires:  qt5-qtsvg-devel
BuildRequires:  qt5-qtmultimedia-devel
#BuildRequires:  qt5-qtwebkit-devel
BuildRequires:  qt5-qtx11extras-devel
BuildRequires:  openssl-devel
BuildRequires:  libXScrnSaver-devel
BuildRequires:  zlib-devel
BuildRequires:  libidn-devel
BuildRequires:  hunspell-devel
BuildRequires:  desktop-file-utils

# Runtime dependencies
Requires:       qt5-qtbase
Requires:       qt5-qtmultimedia
Requires:       qt5-qtsvg
#Requires:       qt5-qtwebkit
Requires:       qt5-qtx11extras
Requires:       openssl-libs
Requires:       libidn
Requires:       zlib
Requires:       hunspell
Requires:       libX11
Requires:       libXext
Requires:       libXrender
Requires:       libXScrnSaver
Requires:       libSM
Requires:       libICE
Requires:       fontconfig

%description
Vacuum-IM is a full-featured cross-platform Jabber/XMPP client.
The core program is just a plugin loader, all functionality is made available
via plugins. This enforces modularity and ensures well defined component
interaction via interfaces.

%prep
%autosetup -p1 -n %{name}-%{git_short_id}

%build
# Configure CMake build in a separate build directory
mkdir -p %{cmake_build_dir}
pushd %{cmake_build_dir}
%{cmake} \
    -DCMAKE_INSTALL_PREFIX=%{_prefix} \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_DO_STRIP=FALSE \
    -DINSTALL_APP_DIR=%{name} \
    -DINSTALL_LIB_DIR=%{_lib} \
    -DINSTALL_DOC_DIR=%{_defaultdocdir} \
    -DINSTALL_DOCS=YES \
    -DINSTALL_SDK=YES \
    -DRUN_FROM_BUILD_DIR=NO \
    -DSPELLCHECKER_BACKEND=HUNSPELL \
    -DPLUGIN_adiummessagestyle=OFF \
    -DGIT_HASH=%{git_hash} \
    -DGIT_DATE=%{git_date} \
    ..

%{cmake_build}
popd

%install
mkdir -p %{cmake_build_dir}
pushd %{cmake_build_dir}
%{cmake_install}
popd

install -D -m644 %{buildroot}%{_datadir}/%{name}/resources/menuicons/shared/mainwindowlogo128.png %{buildroot}%{_datadir}/icons/hicolor/128x128/apps/%{name}.png
install -D -m644 %{buildroot}%{_datadir}/%{name}/resources/menuicons/shared/mainwindowlogo96.png %{buildroot}%{_datadir}/icons/hicolor/96x96/apps/%{name}.png
install -D -m644 %{buildroot}%{_datadir}/%{name}/resources/menuicons/shared/mainwindowlogo64.png %{buildroot}%{_datadir}/icons/hicolor/64x64/apps/%{name}.png
install -D -m644 %{buildroot}%{_datadir}/%{name}/resources/menuicons/shared/mainwindowlogo48.png %{buildroot}%{_datadir}/icons/hicolor/48x48/apps/%{name}.png
install -D -m644 %{buildroot}%{_datadir}/%{name}/resources/menuicons/shared/mainwindowlogo32.png %{buildroot}%{_datadir}/icons/hicolor/32x32/apps/%{name}.png
install -D -m644 %{buildroot}%{_datadir}/%{name}/resources/menuicons/shared/mainwindowlogo24.png %{buildroot}%{_datadir}/icons/hicolor/24x24/apps/%{name}.png
install -D -m644 %{buildroot}%{_datadir}/%{name}/resources/menuicons/shared/mainwindowlogo16.png %{buildroot}%{_datadir}/icons/hicolor/16x16/apps/%{name}.png
sed -i "s/Exec=%{sname}/Exec=%{name}/;s/Icon=%{sname}/Icon=%{name}/" %{buildroot}%{_datadir}/applications/%{sname}.desktop
mv %{buildroot}%{_datadir}/applications/%{sname}.desktop %{buildroot}%{_datadir}/applications/%{name}.desktop
mv %{buildroot}%{_datadir}/pixmaps/%{sname}.png %{buildroot}%{_datadir}/pixmaps/%{name}.png
mv %{buildroot}%{_bindir}/%{sname} %{buildroot}%{_bindir}/%{name}

%check
# Validate desktop file
desktop-file-validate %{buildroot}%{_datadir}/applications/vacuum-im.desktop

%files
# Main binary
%{_bindir}/vacuum-im

# Shared library
%{_libdir}/libvacuumutils.so.*

# SDK
%{_includedir}/%{name}
%{_libdir}/libvacuumutils.so

# Plugins
%{_libdir}/vacuum-im/plugins/*.so

# Resources
%{_datadir}/vacuum-im/resources/*

# Translations
%{_datadir}/vacuum-im/translations/*

# Desktop integration
%{_datadir}/applications/vacuum-im.desktop
%{_datadir}/pixmaps/vacuum-im.png
%{_datadir}/icons/hicolor/*/apps/*.png
%{_datadir}/metainfo/vacuum-im.metainfo.xml

# Documentation
%doc %{_defaultdocdir}/%{name}/AUTHORS
%doc %{_defaultdocdir}/%{name}/CHANGELOG
%doc %{_defaultdocdir}/%{name}/README
%doc %{_defaultdocdir}/%{name}/COPYING
%doc %{_defaultdocdir}/%{name}/TRANSLATORS

%license COPYING

%changelog
* Sun Sep 06 2026 Alexey Ivanov <alexey.ivanes@gmail.com> - 1.3.0-git-1
- Initial RPM package for Vacuum-IM
- Built with CMake and Qt5 using RelWithDebInfo build type
- Includes all default plugins, resources, translations, and desktop integration
- Changed install paths to use vacuum-im as app directory name
- Note: debug_package removed for compatibility with Red OS rpmlint
