# RPM Build Environment and Build Wrapper

This directory contains a reusable RPM build environment and an automated build wrapper script for building RPM packages from git sources using mock.

## Features

- Automated source download and archive creation from git
- Automatic spec file updates with git metadata
- Integrated rpmlint validation
- Mock-based clean chroot builds
- Support for custom patches
- Out-of-source CMake builds
- Configurable build directory
- Reproducible builds with git hash tracking

## Directory Layout

```
.
  SPECS/
    <package>.spec           # RPM spec file for your package
  SOURCES/
    <source-archive>.tar.gz  # Generated source archive (created by --get)
    01-custom-settings.patch # Custom patches applied during build
  BUILD/                     # Build artifacts (created during build)
  RPMS/                      # Binary RPM output (created during build)
  SRPMS/                     # Source RPM output (created during build)
  build.sh                   # Main build wrapper script
```

## Quick Start

```bash
# Full build from scratch (clone, update spec, build RPM)
./build.sh --all

# Or step by step:
./build.sh --get
./build.sh --update
./build.sh --build
```

## Prerequisites

### Host System Requirements

These packages must be installed on the host system to run the build script:

```bash
# On Red OS
sudo dnf install git mock rpmlint rpm-build redos-rpm-config

# On Fedora / RHEL
sudo dnf install git mock rpmlint rpm-build redhat-rpm-config
```

**Package descriptions:**
- `git` - Required for `--get` mode to clone repositories and create archives
- `mock` - Required for `--build` mode to build RPMs in clean chroot
- `rpmlint` - Required for `--update` mode to validate spec files
- `rpm-build` - Provides `rpmbuild` and core RPM macros
- `redos-rpm-config` / `redhat-rpm-config` - Provides RPM macros like `%cmake`, `%cmake_build`, `%cmake_install`, `%_prefix`, `%_libdir`, etc.

### Mock Configuration

Ensure your mock configuration is set up for your target distribution:

```bash
# List available mock configs
ls /etc/mock/

# Common configs:
# redos-80-x86_64.cfg    - Red OS 8.0
# fedora-40-x86_64.cfg   - Fedora 40
# centos-stream-9-x86_64.cfg - CentOS Stream 9
```

### Build Dependencies

Build dependencies (`BuildRequires` in the spec) are automatically installed by mock inside the chroot. These include compilers, libraries, and tools needed to build the package itself.

If you need to add build dependencies, modify the `BuildRequires:` section in `SPECS/<package>.spec`.

## Build Script Usage

The `build.sh` script automates the entire RPM build process using mock.

### Default Build Directory

By default, the script uses its own directory as the RPM build root. This can be overridden with the `RPM_BUILD_DIR` environment variable.

```bash
# Uses current directory by default
./build.sh --all

# Use custom build directory
RPM_BUILD_DIR=/tmp/rpm-build ./build.sh --all
```

### Modes

#### `--get`

Downloads the source code from git, creates a source archive in `SOURCES/`, and preserves the git repository for later steps.

```bash
./build.sh --get
```

**What it does:**
1. Removes any previous git clone in `SOURCES/<package>-repo/`
2. Clones the repository from the specified URL
3. Checks out the specified ref (`--ref`)
4. Extracts version, git hash, git date, short id, and human-readable date
5. Creates source archive in `SOURCES/`
6. Preserves the git repo and stores metadata files

**Options:**
- `--ref <ref>` - Git ref to checkout (branch, tag, commit, or HEAD). Default: `HEAD`
- `--repo-url <url>` - Git repository URL

**Example:**
```bash
# Build from specific branch
./build.sh --get --ref master

# Build from specific tag
./build.sh --get --ref v1.0.0

# Build from specific commit
./build.sh --get --ref abc123def456

# Build from custom repository
./build.sh --get --repo-url https://github.com/example/project.git --ref develop
```

#### `--update`

Updates the spec file with git information and runs rpmlint validation.

```bash
./build.sh --update
```

**What it does:**
1. Reads git hash, date, short id, and human date from the preserved git repo
2. Updates `%define` macros in the spec file:
   - `git_hash` - full commit hash
   - `git_date` - unix timestamp
   - `git_short_id` - short commit hash
   - `git_human_date` - formatted date `YYYY.MM.DD.HH.MM`
3. Verifies all macros were updated successfully
4. Runs `rpmlint` on the spec file and aborts on errors

**Options:**
- `--no-rpmlint` - Skip rpmlint check

**Example:**
```bash
./build.sh --update
```

#### `--build`

Builds the source RPM (SRPM) and binary RPM using mock.

```bash
./build.sh --build
```

**What it does:**
1. Finds the source archive in `SOURCES/`
2. Verifies spec file macros are populated (aborts if not)
3. Builds SRPM with `mock --buildsrpm` using `--resultdir RPM_BUILD_DIR/SRPMS`
4. Rebuilds binary RPM from SRPM with `mock --rebuild` using `--resultdir RPM_BUILD_DIR/RPMS`
5. Reports built RPMs

**Options:**
- `--mock-config <cfg>` - Mock configuration name
- `--mock-config-path <path>` - Path to mock config file
- `--dist <tag>` - Distribution tag suffix. Auto-detected from mock config if not specified

**Example:**
```bash
# Build with default mock config
./build.sh --build

# Build with custom mock config
./build.sh --build --mock-config fedora-40-x86_64

# Build with explicit dist tag
./build.sh --build --dist .fc40
```

#### `--all`

Executes `--get`, `--update`, and `--build` in sequence. Stops if any step fails.

```bash
./build.sh --all
```

**Example:**
```bash
# Full build from scratch
./build.sh --all

# Full build with custom branch and mock config
./build.sh --all --ref master --mock-config redos-80-x86_64

# Full build from specific commit
./build.sh --all --ref abc123def456 --no-rpmlint
```

### All Options Summary

| Option | Description | Default |
|--------|-------------|---------|
| `--get` | Download sources and create archive | - |
| `--update` | Update spec with git info and run rpmlint | - |
| `--build` | Build SRPM and binary RPM with mock | - |
| `--all` | Execute all steps in sequence | - |
| `--ref <ref>` | Git ref to checkout | `HEAD` |
| `--repo-url <url>` | Git repository URL | - |
| `--mock-config <cfg>` | Mock configuration name | - |
| `--mock-config-path <path>` | Path to mock config file | - |
| `--dist <tag>` | Distribution tag suffix | Auto-detected |
| `--no-rpmlint` | Skip rpmlint check | `false` |
| `--help` | Show help message | - |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `RPM_BUILD_DIR` | RPM build root directory | Directory where script is located |

## Output

After a successful build, RPMs are placed in:

```
.
  SRPMS/
    <package>-<version>-<release>.src.rpm
  RPMS/
    <arch>/
      <package>-<version>-<release>.<dist>.<arch>.rpm
```

## Spec File Integration

To use this build system with your package, your spec file should include these git metadata macros:

```spec
%define git_hash <full-commit-hash>
%define git_date <unix-timestamp>
%define git_short_id <short-commit-hash>
%define git_human_date <YYYY.MM.DD.HH.MM>
```

The build script's `--update` mode will automatically populate these values.

### Version and Release Pattern

A common pattern for git-based builds:

```spec
Name:           <package-name>
Version:        <base-version>~git.%{git_human_date}
Release:        1.%{git_short_id}%{?dist}
Source0:        <package-name>-%{git_short_id}.tar.gz
```

### Patch Integration

Place custom patches directly in `SOURCES/` and reference them in the spec:

```spec
Patch0: 01-custom-settings.patch
```

The patch is automatically applied during `%prep` by `%autosetup -p1`.

## Customization

### Adapting for Your Project

1. **Copy the build script:**
   ```bash
   cp build.sh /path/to/your/project/
   ```

2. **Create your spec file** in `SPECS/` with the git metadata macros shown above.

3. **Add your patches** to `SOURCES/`.

4. **Update the spec file** with your package's:
   - Name, Version, Release
   - Summary, License, URL
   - BuildRequires and Requires
   - CMake or other build configuration

### Spec File Best Practices

- Use `%{cmake_build_dir}` macro for out-of-source builds
- Create build directory before `pushd`:
  ```spec
  %build
  mkdir -p %{cmake_build_dir}
  pushd %{cmake_build_dir}
  %{cmake} .. <options>
  %{cmake_build}
  popd
  ```
- Use `%autosetup -p1` to automatically apply patches
- Add `-DCMAKE_INSTALL_DO_STRIP=FALSE` for debug symbol preservation

## Troubleshooting

### Error: Source archive not found

Run `--get` first to download sources and create the archive.

### Error: Spec file macros are not fully populated

Run `--update` after `--get` to populate the git macros in the spec file.

### Error: build: No such file or directory

Ensure your spec file creates the build directory before `pushd`:
```spec
mkdir -p %{cmake_build_dir}
pushd %{cmake_build_dir}
```

### Mock build fails with missing dependencies

Update your mock configuration or install missing dependencies in the mock chroot.

```bash
# Install deps in mock chroot
mock -r <config> --install <package-name>
```

### rpmlint errors abort the build

Fix the reported issues or use `--no-rpmlint` to skip validation (not recommended for production builds).

## Example Workflows

### Full Build from Scratch

```bash
./build.sh --all --ref master
```

### Rebuild with Same Sources

If you already ran `--get` and `--update` previously:

```bash
./build.sh --build
```

### Build Specific Release

```bash
./build.sh --all --ref v1.0.0 --mock-config fedora-40-x86_64
```

### Build with Custom Patches

1. Create patch in `SOURCES/`
2. Add `PatchN:` line in spec
3. Run build:

```bash
./build.sh --all
```

## Notes

- The git repository is preserved in `SOURCES/<package>-repo/` between runs to avoid re-cloning
- Metadata files are stored in `SOURCES/.metadata/` for `--update` to read if the repo is missing
- The spec file is backed up before modification (`<package>.spec.bak`)
- `rpmlint` errors will abort the build; warnings are displayed but do not stop the build
- This build system is designed for CMake-based projects but can be adapted for other build systems
