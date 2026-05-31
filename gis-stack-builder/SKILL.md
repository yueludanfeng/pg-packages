---
name: gis-stack-builder
description: This skill should be used when the user needs to compile and install a GIS (Geographic Information System) software stack from source code on Linux servers. It covers the complete build process for Proj, GEOS, GDAL, PostgreSQL, PostGIS, pgRouting, pg_repack, pg_top, and pgaudit. Supports openEuler 22.03 and Ubuntu 24.04. Use this skill when setting up spatial database infrastructure, deploying PostGIS-enabled PostgreSQL servers, or installing geospatial libraries from source.
---

# GIS Stack Source Compilation Builder

## Overview

Provide a complete, reproducible workflow for source-compiling and installing a GIS software stack on Linux servers. The stack includes Proj (coordinate transformation), GEOS (geometry engine), GDAL (geospatial data abstraction), PostgreSQL (database), PostGIS (spatial extension), pgRouting (routing engine), pg_repack (table maintenance), pg_top (monitoring), and pgaudit (auditing). The skill handles OS detection, dependency installation, build order resolution, known compatibility patches, and post-install configuration.

## Build Order (Dependency-First)

The software must be built in the following order due to dependency relationships:

1. **Proj 8.2.1** → Coordinate transformation library (no GIS dependencies)
2. **GEOS 3.12.3** → Geometry engine (no GIS dependencies)
3. **GDAL 3.8.5** → Geospatial data abstraction (depends on Proj, GEOS)
4. **PostgreSQL 15.18** → Database server (depends on OpenSSL, Readline)
5. **PostGIS 3.4.4** → Spatial extension for PG (depends on Proj + GEOS + GDAL + PG)
6. **pgRouting 3.6.3** → Routing engine (depends on PostGIS + PG + Boost)
7. **pg_repack 1.5.3** → Table reorganization (depends on PG)
8. **pg_top** → PostgreSQL process monitor (depends on PG libpq)
9. **pgaudit** → Audit logging extension (depends on PG)

## Workflow

### Step 1: OS Detection and Dependency Installation

Detect the target OS and install build dependencies. The install script at `scripts/install_gis_stack.sh` auto-detects the OS.

**Ubuntu 24.04 dependencies:**
```bash
apt-get update -qq && apt-get install -y -qq \
    build-essential cmake wget curl \
    libsqlite3-dev sqlite3 libtiff-dev \
    libcurl4-openssl-dev libjson-c-dev \
    libpq-dev libxml2-dev libreadline-dev \
    zlib1g-dev libssl-dev libprotobuf-c-dev \
    protobuf-c-compiler libpcre3-dev \
    libboost-dev libboost-graph-dev \
    liblzma-dev libzstd-dev pkg-config \
    libtool autoconf automake git \
    libncurses5-dev libtermcap-dev flex bison
```

**openEuler 22.03 dependencies:**
```bash
yum groupinstall -y "Development Tools" && yum install -y \
    cmake wget curl sqlite-devel libtiff-devel \
    libcurl-devel json-c-devel libxml2-devel readline-devel \
    zlib-devel openssl-devel protobuf-c-devel protobuf-c-compiler \
    pcre-devel boost-devel boost-graph xz-devel libzstd-devel pkgconfig \
    libtool autoconf automake git ncurses-devel libtermcap-devel \
    flex bison perl-IPC-Run perl-ExtUtils-Embed libicu-devel
```

For detailed OS-specific notes, consult:
- `references/ubuntu-notes.md` — Ubuntu 24.04 known issues and workarounds
- `references/openeuler-notes.md` — openEuler 22.03 package mapping and SELinux notes

### Step 2: Compile and Install (In Dependency Order)

Execute the automated install script on the target server:

```bash
# Upload and run the script
scp scripts/install_gis_stack.sh root@<server>:/root/
ssh root@<server> "chmod +x /root/install_gis_stack.sh && bash /root/install_gis_stack.sh"
```

Or execute each build step manually following the script logic. Key considerations per component:

#### Proj 8.2.1 — GCC 13+ Compatibility Patch Required

On Ubuntu 24.04 (GCC 13+), Proj 8.2.1 fails to compile because `std::int64_t` / `std::uint64_t` are used without `#include <cstdint>`. Apply this patch before building:

```bash
for f in $(grep -rl 'std::int64_t\|std::uint64_t' /root/src/proj-8.2.1/src/ --include='*.cpp' --include='*.hpp'); do
    if ! grep -q '#include <cstdint>' "$f"; then
        sed -i '1i #include <cstdint>' "$f"
    fi
done
```

Affected files: `proj_json_streaming_writer.hpp`, `proj_json_streaming_writer.cpp`, `projections/s2.cpp`

On openEuler 22.03 (GCC 10.x), this patch is typically not needed.

#### GEOS 3.12.3 — Standard CMake Build

No known issues. Standard cmake build with `BUILD_TESTING=OFF`.

#### GDAL 3.8.5 — PKG_CONFIG_PATH Required

GDAL's CMake does NOT accept manual `-DPROJ_INCLUDE_DIR` / `-DGEOS_LIBRARY` variables. Instead, set `PKG_CONFIG_PATH` and `CMAKE_PREFIX_PATH`:

```bash
export PKG_CONFIG_PATH="/postgresql/proj-8.2.1/lib/pkgconfig:/postgresql/geos-3.12.3/lib/pkgconfig"
export LDFLAGS="-L/postgresql/proj-8.2.1/lib -L/postgresql/geos-3.12.3/lib -Wl,-rpath,..."
export CXXFLAGS="-I/postgresql/proj-8.2.1/include -I/postgresql/geos-3.12.3/include"
cmake <source> -DCMAKE_PREFIX_PATH="/postgresql/proj-8.2.1;/postgresql/geos-3.12.3"
```

#### PostgreSQL 15.18 — ICU Option

- Ubuntu 24.04: Use `--without-icu` unless `libicu-dev` is installed
- openEuler 22.03: Use `--with-icu` (ICU dev package available by default)

Always build contrib modules after the main build: `cd contrib && make && make install`

#### PostGIS 3.4.4 — Point to Custom Library Paths

Configure with explicit paths to custom-built Proj/GEOS/GDAL:
```bash
./configure \
    --with-pgconfig=/postgresql/pg15/bin/pg_config \
    --with-projdir=/postgresql/proj-8.2.1 \
    --with-geosconfig=/postgresql/geos-3.12.3/bin/geos-config \
    --with-gdalconfig=/postgresql/gdal-3.8.5/bin/gdal-config
```

#### pgRouting 3.6.3 — PATH-Based PG Discovery

pgRouting's CMake does NOT accept `-DPG_CONFIG`. Set `PATH` instead:
```bash
export PATH=/postgresql/pg15/bin:$PATH
cmake <source> -DCMAKE_INSTALL_PREFIX=/postgresql/pg15
```

#### pg_repack, pg_top, pgaudit

Standard builds. pg_top may need `autoreconf -fi` if `configure` is missing. pgaudit uses `git checkout` for version selection and `make install USE_PGXS=1`.

### Step 3: Post-Install Configuration

After all software is built and installed, configure:

1. **Environment variables** — Create `/etc/profile.d/postgresql.sh` with PATH, LD_LIBRARY_PATH, PKG_CONFIG_PATH, PROJ_LIB, PGDATA
2. **Dynamic library cache** — Create `/etc/ld.so.conf.d/postgresql.conf` and run `ldconfig`
3. **Verify** — Check each component's binary/library exists and reports correct version

### Step 4: Initialize and Start PostgreSQL

```bash
source /etc/profile.d/postgresql.sh
initdb -D ${PGDATA}
pg_ctl -D ${PGDATA} -l logfile start
```

### Step 5: Enable Extensions

```sql
CREATE EXTENSION postgis;
CREATE EXTENSION pgrouting;
CREATE EXTENSION pg_repack;
-- pgaudit requires shared_preload_libraries in postgresql.conf
-- shared_preload_libraries = 'pgaudit'
-- pgaudit.log = 'all'
```

## Download Sources (Chinese Mirror Priority)

| Software | Primary | Fallback |
|----------|---------|----------|
| Proj | `https://mirrors.huaweicloud.com/proj/` | `https://download.osgeo.org/proj/` |
| GEOS | `https://mirrors.huaweicloud.com/geos/` | `https://download.osgeo.org/geos/` |
| GDAL | `https://download.osgeo.org/gdal/` | GitHub releases |
| PostgreSQL | `https://mirrors.huaweicloud.com/postgresql/source/` | `https://mirrors.tuna.tsinghua.edu.cn/postgresql/source/` |
| PostGIS | `https://mirrors.huaweicloud.com/postgis/source/` | `https://download.osgeo.org/postgis/source/` |
| pgRouting | GitHub releases | - |
| pg_repack | GitHub releases | - |
| pgaudit | GitHub repository | - |

## Directory Layout Convention

```
/root/src/                          # Source tarballs and extracted sources
/postgresql/
├── proj-8.2.1/                     # Proj installation
├── geos-3.12.3/                    # GEOS installation
├── gdal-3.8.5/                     # GDAL installation
├── pg15/                           # PostgreSQL + extensions installation
│   ├── bin/                        # postgres, pg_ctl, psql, pg_repack, etc.
│   ├── lib/                        # postgis-3.so, libpgrouting-*.so, pgaudit.so, etc.
│   ├── share/extension/            # .control and .sql files
│   └── data/                       # PGDATA (after initdb)
└── pg_top/                         # pg_top installation
```

## Resources

### scripts/
- `install_gis_stack.sh` — Fully automated one-click install script supporting openEuler 22.03 and Ubuntu 24.04. Auto-detects OS, installs deps, builds all 9 components in correct order, patches known issues, and configures the environment.

### references/
- `ubuntu-notes.md` — Ubuntu 24.04 specific notes: GCC 13 compatibility patches, CMake variable issues, ICU options, disk management tips
- `openeuler-notes.md` — openEuler 22.03 specific notes: yum package name mapping, mirror configuration, SELinux, ICU support, GCC 10 compatibility
- `compatibility.md` — Version compatibility matrix, dependency graph, environment variable reference, download source list
