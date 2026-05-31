#!/usr/bin/env bash
set -Eeuo pipefail

# Build PolarDB for PostgreSQL plus GIS/utility extensions on openEuler 22.03.
# Defaults match the stack built on openeuler22:
#   PROJ 8.2.1, GEOS 3.12.3, GDAL 3.8.5, PolarDB v15.18.5.0,
#   PostGIS 3.4.4, pgRouting 3.6.3, pg_repack 1.5.3, pg_top 4.1.1,
#   pgaudit REL_15_STABLE.

PROJ_VERSION="${PROJ_VERSION:-8.2.1}"
GEOS_VERSION="${GEOS_VERSION:-3.12.3}"
GDAL_VERSION="${GDAL_VERSION:-3.8.5}"
POLARDB_TAG="${POLARDB_TAG:-v15.18.5.0}"
POSTGIS_VERSION="${POSTGIS_VERSION:-3.4.4}"
PGROUTING_VERSION="${PGROUTING_VERSION:-3.6.3}"
PG_REPACK_VERSION="${PG_REPACK_VERSION:-1.5.3}"
PG_TOP_TAG="${PG_TOP_TAG:-v4.1.1}"
PGAUDIT_REF="${PGAUDIT_REF:-REL_15_STABLE}"

PREFIX_ROOT="${PREFIX_ROOT:-/polardb}"
SRC_DIR="${SRC_DIR:-/root/src}"
LOG_DIR="${LOG_DIR:-/root/buildlogs}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
PORT="${PORT:-5432}"
INSTALL_DEPS="${INSTALL_DEPS:-0}"
BUILD_BASE_LIBS="${BUILD_BASE_LIBS:-auto}"

POLARDB_REPO="${POLARDB_REPO:-https://github.com/polardb/PolarDB-for-PostgreSQL.git}"
PG_TOP_REPO="${PG_TOP_REPO:-https://github.com/markwkm/pg_top.git}"
PGAUDIT_REPO="${PGAUDIT_REPO:-https://github.com/pgaudit/pgaudit.git}"

POLARDB_MAJOR="$(printf '%s\n' "$POLARDB_TAG" | sed -E 's/^v?([0-9]+).*/\1/')"
POLARDB_MINOR="$(printf '%s\n' "$POLARDB_TAG" | sed -E 's/^v?([0-9]+)\.([0-9]+).*/\2/')"
PG_PREFIX="${PG_PREFIX:-$PREFIX_ROOT/pgsql${POLARDB_MAJOR}.${POLARDB_MINOR}}"
PGHOME="$PG_PREFIX/tmp_polardb_pg_${POLARDB_MAJOR}_base"

PROJ_HOME="$PREFIX_ROOT/proj-$PROJ_VERSION"
GEOS_HOME="$PREFIX_ROOT/geos-$GEOS_VERSION"
GDAL_HOME="$PREFIX_ROOT/gdal-$GDAL_VERSION"

log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

run() {
  log "$*"
  "$@"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

download() {
  local url="$1"
  local out="$2"
  if [[ -s "$out" ]]; then
    log "Using existing source package: $out"
    return
  fi
  run wget -O "$out" "$url"
}

extract_clean() {
  local archive="$1"
  local dir="$2"
  rm -rf "$SRC_DIR/$dir"
  run tar xf "$SRC_DIR/$archive" -C "$SRC_DIR"
}

maybe_install_deps() {
  if [[ "$INSTALL_DEPS" != "1" ]]; then
    return
  fi
  run dnf install -y \
    git wget curl tar gzip bzip2 make gcc gcc-c++ cmake bison flex perl \
    sqlite-devel libtiff-devel libcurl-devel libxml2-devel libxslt-devel \
    json-c-devel protobuf-c-devel boost-devel eigen3-devel readline-devel \
    zlib-devel openssl-devel pam-devel openldap-devel krb5-devel libicu-devel \
    python3-devel perl-devel tcl-devel llvm-devel lz4-devel libzstd-devel \
    libunwind-devel gettext
}

prepare_sources() {
  run mkdir -p "$SRC_DIR" "$LOG_DIR"
  cd "$SRC_DIR"

  download "https://download.osgeo.org/proj/proj-$PROJ_VERSION.tar.gz" \
    "proj-$PROJ_VERSION.tar.gz"
  download "https://download.osgeo.org/geos/geos-$GEOS_VERSION.tar.bz2" \
    "geos-$GEOS_VERSION.tar.bz2"
  download "https://download.osgeo.org/gdal/$GDAL_VERSION/gdal-$GDAL_VERSION.tar.gz" \
    "gdal-$GDAL_VERSION.tar.gz"
  download "https://download.osgeo.org/postgis/source/postgis-$POSTGIS_VERSION.tar.gz" \
    "postgis-$POSTGIS_VERSION.tar.gz"
  download "https://github.com/pgRouting/pgrouting/releases/download/v$PGROUTING_VERSION/pgrouting-$PGROUTING_VERSION.tar.gz" \
    "pgrouting-$PGROUTING_VERSION.tar.gz"
  download "https://github.com/reorg/pg_repack/archive/refs/tags/ver_$PG_REPACK_VERSION.tar.gz" \
    "pg_repack-$PG_REPACK_VERSION.tar.gz"

  extract_clean "proj-$PROJ_VERSION.tar.gz" "proj-$PROJ_VERSION"
  extract_clean "geos-$GEOS_VERSION.tar.bz2" "geos-$GEOS_VERSION"
  extract_clean "gdal-$GDAL_VERSION.tar.gz" "gdal-$GDAL_VERSION"
  extract_clean "postgis-$POSTGIS_VERSION.tar.gz" "postgis-$POSTGIS_VERSION"
  extract_clean "pgrouting-$PGROUTING_VERSION.tar.gz" "pgrouting-$PGROUTING_VERSION"
  rm -rf "$SRC_DIR/pg_repack-ver_$PG_REPACK_VERSION"
  run tar xf "$SRC_DIR/pg_repack-$PG_REPACK_VERSION.tar.gz" -C "$SRC_DIR"

  if [[ ! -d "$SRC_DIR/PolarDB-for-PostgreSQL/.git" ]]; then
    run git clone "$POLARDB_REPO" "$SRC_DIR/PolarDB-for-PostgreSQL"
  else
    run git -C "$SRC_DIR/PolarDB-for-PostgreSQL" remote set-url origin "$POLARDB_REPO"
    run git -C "$SRC_DIR/PolarDB-for-PostgreSQL" fetch --tags origin
  fi

  if [[ ! -d "$SRC_DIR/pg_top/.git" ]]; then
    run git clone "$PG_TOP_REPO" "$SRC_DIR/pg_top"
  else
    run git -C "$SRC_DIR/pg_top" fetch --tags origin
  fi

  if [[ ! -d "$SRC_DIR/pgaudit/.git" ]]; then
    run git clone "$PGAUDIT_REPO" "$SRC_DIR/pgaudit"
  else
    run git -C "$SRC_DIR/pgaudit" fetch --tags origin
  fi
}

base_libs_are_ready() {
  [[ -x "$PROJ_HOME/bin/proj" ]] &&
    [[ -x "$GEOS_HOME/bin/geos-config" ]] &&
    [[ -x "$GDAL_HOME/bin/gdal-config" ]]
}

build_proj() {
  log "Building PROJ $PROJ_VERSION"
  cd "$SRC_DIR/proj-$PROJ_VERSION"
  rm -rf build
  cmake -S . -B build \
    -DCMAKE_INSTALL_PREFIX="$PROJ_HOME" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF >"$LOG_DIR/proj-$PROJ_VERSION.log" 2>&1
  cmake --build build --parallel "$JOBS" >>"$LOG_DIR/proj-$PROJ_VERSION.log" 2>&1
  cmake --install build >>"$LOG_DIR/proj-$PROJ_VERSION.log" 2>&1
}

build_geos() {
  log "Building GEOS $GEOS_VERSION"
  cd "$SRC_DIR/geos-$GEOS_VERSION"
  rm -rf build
  cmake -S . -B build \
    -DCMAKE_INSTALL_PREFIX="$GEOS_HOME" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF >"$LOG_DIR/geos-$GEOS_VERSION.log" 2>&1
  cmake --build build --parallel "$JOBS" >>"$LOG_DIR/geos-$GEOS_VERSION.log" 2>&1
  cmake --install build >>"$LOG_DIR/geos-$GEOS_VERSION.log" 2>&1
}

build_gdal() {
  log "Building GDAL $GDAL_VERSION"
  export PATH="$PROJ_HOME/bin:$PATH"
  export LD_LIBRARY_PATH="$PROJ_HOME/lib:${LD_LIBRARY_PATH:-}"
  export PKG_CONFIG_PATH="$PROJ_HOME/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

  cd "$SRC_DIR/gdal-$GDAL_VERSION"
  rm -rf build
  cmake -S . -B build \
    -DCMAKE_INSTALL_PREFIX="$GDAL_HOME" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DPROJ_ROOT="$PROJ_HOME" \
    -DGDAL_USE_PROJ=ON \
    -DBUILD_TESTING=OFF >"$LOG_DIR/gdal-$GDAL_VERSION.log" 2>&1
  cmake --build build --parallel "$JOBS" >>"$LOG_DIR/gdal-$GDAL_VERSION.log" 2>&1
  cmake --install build >>"$LOG_DIR/gdal-$GDAL_VERSION.log" 2>&1
}

build_base_libs() {
  if [[ "$BUILD_BASE_LIBS" == "0" ]]; then
    log "Skipping base library builds because BUILD_BASE_LIBS=0"
    return
  fi
  if [[ "$BUILD_BASE_LIBS" == "auto" ]] && base_libs_are_ready; then
    log "Reusing existing PROJ/GEOS/GDAL installations"
    return
  fi
  build_proj
  build_geos
  build_gdal
}

build_polardb() {
  log "Building PolarDB $POLARDB_TAG"
  cd "$SRC_DIR/PolarDB-for-PostgreSQL"
  run git fetch --tags origin
  run git checkout "$POLARDB_TAG"
  ./build.sh --ni --port="$PORT" --debug=off --prefix="$PG_PREFIX" \
    >"$LOG_DIR/polardb-${POLARDB_TAG#v}.log" 2>&1
}

set_pg_env() {
  export PATH="$PGHOME/bin:$PROJ_HOME/bin:$GEOS_HOME/bin:$GDAL_HOME/bin:$PATH"
  export LD_LIBRARY_PATH="$PGHOME/lib:$PROJ_HOME/lib:$GEOS_HOME/lib:$GDAL_HOME/lib:${LD_LIBRARY_PATH:-}"
  export PKG_CONFIG_PATH="$PROJ_HOME/lib/pkgconfig:$GEOS_HOME/lib/pkgconfig:$GDAL_HOME/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
}

build_postgis() {
  log "Building PostGIS $POSTGIS_VERSION"
  set_pg_env
  cd "$SRC_DIR/postgis-$POSTGIS_VERSION"
  make clean >/dev/null 2>&1 || true
  ./configure \
    --prefix="$PGHOME" \
    --with-pgconfig="$PGHOME/bin/pg_config" \
    --with-geosconfig="$GEOS_HOME/bin/geos-config" \
    --with-gdalconfig="$GDAL_HOME/bin/gdal-config" \
    --with-projdir="$PROJ_HOME" >"$LOG_DIR/postgis-$POSTGIS_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
  make -j"$JOBS" >>"$LOG_DIR/postgis-$POSTGIS_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
  make install >>"$LOG_DIR/postgis-$POSTGIS_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
}

build_pgrouting() {
  log "Building pgRouting $PGROUTING_VERSION"
  set_pg_env
  cd "$SRC_DIR/pgrouting-$PGROUTING_VERSION"
  rm -rf "build-pg${POLARDB_MAJOR}.${POLARDB_MINOR}"
  cmake -S . -B "build-pg${POLARDB_MAJOR}.${POLARDB_MINOR}" \
    -DCMAKE_INSTALL_PREFIX="$PGHOME" \
    -DCMAKE_BUILD_TYPE=Release \
    -DPOSTGRESQL_PG_CONFIG="$PGHOME/bin/pg_config" \
    -DBUILD_TESTING=OFF >"$LOG_DIR/pgrouting-$PGROUTING_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
  cmake --build "build-pg${POLARDB_MAJOR}.${POLARDB_MINOR}" --parallel "$JOBS" \
    >>"$LOG_DIR/pgrouting-$PGROUTING_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
  cmake --install "build-pg${POLARDB_MAJOR}.${POLARDB_MINOR}" \
    >>"$LOG_DIR/pgrouting-$PGROUTING_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
}

build_pg_repack() {
  log "Building pg_repack $PG_REPACK_VERSION"
  set_pg_env
  cd "$SRC_DIR/pg_repack-ver_$PG_REPACK_VERSION"
  make USE_PGXS=1 PG_CONFIG="$PGHOME/bin/pg_config" clean \
    >"$LOG_DIR/pg_repack-$PG_REPACK_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1 || true
  make USE_PGXS=1 PG_CONFIG="$PGHOME/bin/pg_config" -j"$JOBS" \
    >>"$LOG_DIR/pg_repack-$PG_REPACK_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
  make USE_PGXS=1 PG_CONFIG="$PGHOME/bin/pg_config" install \
    >>"$LOG_DIR/pg_repack-$PG_REPACK_VERSION-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
}

build_pg_top() {
  log "Building pg_top $PG_TOP_TAG"
  set_pg_env
  cd "$SRC_DIR/pg_top"
  run git checkout "$PG_TOP_TAG"
  rm -rf "build-pg${POLARDB_MAJOR}.${POLARDB_MINOR}"
  cmake -S . -B "build-pg${POLARDB_MAJOR}.${POLARDB_MINOR}" \
    -DCMAKE_INSTALL_PREFIX="$PGHOME" \
    -DPostgreSQL_ROOT="$PGHOME" >"$LOG_DIR/pg_top-${PG_TOP_TAG#v}-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
  cmake --build "build-pg${POLARDB_MAJOR}.${POLARDB_MINOR}" --parallel "$JOBS" \
    >>"$LOG_DIR/pg_top-${PG_TOP_TAG#v}-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
  cmake --install "build-pg${POLARDB_MAJOR}.${POLARDB_MINOR}" \
    >>"$LOG_DIR/pg_top-${PG_TOP_TAG#v}-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
}

build_pgaudit() {
  log "Building pgaudit $PGAUDIT_REF"
  set_pg_env
  cd "$SRC_DIR/pgaudit"
  run git fetch origin "$PGAUDIT_REF"
  run git checkout "$PGAUDIT_REF"
  make USE_PGXS=1 PG_CONFIG="$PGHOME/bin/pg_config" clean \
    >"$LOG_DIR/pgaudit-$PGAUDIT_REF-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1 || true
  make USE_PGXS=1 PG_CONFIG="$PGHOME/bin/pg_config" -j"$JOBS" \
    >>"$LOG_DIR/pgaudit-$PGAUDIT_REF-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
  make USE_PGXS=1 PG_CONFIG="$PGHOME/bin/pg_config" install \
    >>"$LOG_DIR/pgaudit-$PGAUDIT_REF-pg${POLARDB_MAJOR}.${POLARDB_MINOR}.log" 2>&1
}

verify_stack() {
  log "Verifying installed stack"
  set_pg_env
  "$PROJ_HOME/bin/proj" 2>&1 | head -1
  "$GEOS_HOME/bin/geos-config" --version
  "$GDAL_HOME/bin/gdal-config" --version
  "$PGHOME/bin/pg_config" --version
  "$PGHOME/bin/postgres" --version
  "$PGHOME/bin/pg_repack" --version
  "$PGHOME/bin/pg_top" --version

  for f in \
    postgis--"$POSTGIS_VERSION".sql \
    postgis_raster--"$POSTGIS_VERSION".sql \
    pgrouting--"$PGROUTING_VERSION".sql \
    pg_repack--"$PG_REPACK_VERSION".sql \
    pgaudit.control \
    postgis.control \
    pgrouting.control \
    pg_repack.control; do
    test -f "$PGHOME/share/extension/$f"
    echo "OK $f"
  done

  ldd "$PGHOME/lib/postgis_raster-3.so" | grep -E 'libgdal|libproj|libgeos' || true
}

main() {
  need_cmd git
  need_cmd wget
  need_cmd cmake
  need_cmd make
  need_cmd gcc

  maybe_install_deps
  prepare_sources
  build_base_libs
  build_polardb
  build_postgis
  build_pgrouting
  build_pg_repack
  build_pg_top
  build_pgaudit
  verify_stack

  log "Done. PGHOME=$PGHOME LOG_DIR=$LOG_DIR"
}

main "$@"
