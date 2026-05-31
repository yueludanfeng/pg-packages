#!/bin/bash
###############################################################################
# GIS Stack Source Compilation Installer
# Supports: openEuler 22.03 / Ubuntu 24.04
# Software: Proj, GEOS, GDAL, PostgreSQL, PostGIS, pgRouting, pg_repack, pg_top, pgaudit
###############################################################################

set -euo pipefail

# ========================= Configuration =========================
SRC_DIR="${SRC_DIR:-/root/src}"
INSTALL_BASE="${INSTALL_BASE:-/postgresql}"
NPROC="$(nproc)"

# Software versions
PROJ_VER="8.2.1"
GEOS_VER="3.12.3"
GDAL_VER="3.8.5"
PG_VER="15.18"
PG_MAIN_VER="15"
POSTGIS_VER="3.4.4"
PGROUTING_VER="3.6.3"
PG_REPACK_VER="1.5.3"
PGAUDIT_VER="1.7.1"

# Install paths
PROJ_PREFIX="${INSTALL_BASE}/proj-${PROJ_VER}"
GEOS_PREFIX="${INSTALL_BASE}/geos-${GEOS_VER}"
GDAL_PREFIX="${INSTALL_BASE}/gdal-${GDAL_VER}"
PG_PREFIX="${INSTALL_BASE}/pg${PG_MAIN_VER}"
PGTOP_PREFIX="${INSTALL_BASE}/pg_top"

# ========================= Detect OS =========================
detect_os() {
    if [ -f /etc/openEuler-release ]; then
        OS_ID="openEuler"
        OS_VER=$(grep -oP 'release \K[\d.]+' /etc/openEuler-release | cut -d. -f1-2)
    elif [ -f /etc/os-release ]; then
        OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        OS_VER=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        echo "ERROR: Cannot detect OS" >&2
        exit 1
    fi
    echo "Detected OS: ${OS_ID} ${OS_VER}"
}

# ========================= Install Build Dependencies =========================
install_deps_ubuntu() {
    echo ">>> Installing build dependencies for Ubuntu..."
    apt-get update -qq
    apt-get install -y -qq \
        build-essential cmake wget curl \
        libsqlite3-dev sqlite3 libtiff-dev \
        libcurl4-openssl-dev libjson-c-dev \
        libpq-dev libxml2-dev libreadline-dev \
        zlib1g-dev libssl-dev libprotobuf-c-dev \
        protobuf-c-compiler libpcre3-dev \
        libboost-dev libboost-graph-dev \
        liblzma-dev libzstd-dev pkg-config \
        libtool autoconf automake git \
        libncurses5-dev libtermcap-dev \
        flex bison 2>&1 | tail -3
    echo ">>> Ubuntu dependencies installed."
}

install_deps_openeuler() {
    echo ">>> Installing build dependencies for openEuler..."
    # Use Huawei mirror for faster downloads
    sed -i 's|repo.openeuler.org|repo.huaweicloud.com/openeuler|g' /etc/yum.repos.d/*.repo 2>/dev/null || true
    yum clean all
    yum makecache
    yum groupinstall -y "Development Tools" 2>&1 | tail -3
    yum install -y \
        cmake wget curl \
        sqlite-devel libtiff-devel \
        libcurl-devel json-c-devel \
        libxml2-devel readline-devel \
        zlib-devel openssl-devel protobuf-c-devel \
        protobuf-c-compiler pcre-devel \
        boost-devel boost-graph \
        lz4-devel libzstd-devel pkgconfig \
        libtool autoconf automake git \
        ncurses-devel libtermcap-devel \
        flex bison \
        perl-IPC-Run perl-ExtUtils-Embed \
        libicu-devel 2>&1 | tail -3
    echo ">>> openEuler dependencies installed."
}

install_dependencies() {
    detect_os
    case "${OS_ID}" in
        ubuntu|debian) install_deps_ubuntu ;;
        openEuler|centos|rhel|fedora) install_deps_openeuler ;;
        *) echo "ERROR: Unsupported OS: ${OS_ID}" >&2; exit 1 ;;
    esac
}

# ========================= Mirror Helper =========================
# Try multiple download sources, prefer Chinese mirrors
smart_download() {
    local filename="$1"
    shift
    local urls=("$@")
    local target="${SRC_DIR}/${filename}"

    if [ -f "${target}" ]; then
        echo "    [SKIP] ${filename} already exists"
        return 0
    fi

    for url in "${urls[@]}"; do
        echo "    [TRY] ${url}"
        if wget -q "${url}" -O "${target}" 2>/dev/null; then
            echo "    [OK] Downloaded from ${url}"
            return 0
        fi
    done

    # Fallback with curl
    for url in "${urls[@]}"; do
        echo "    [TRY curl] ${url}"
        if curl -sL "${url}" -o "${target}" 2>/dev/null; then
            echo "    [OK] Downloaded from ${url}"
            return 0
        fi
    done

    echo "    [FAIL] Could not download ${filename}" >&2
    return 1
}

# ========================= 1. Proj =========================
build_proj() {
    echo "========================================="
    echo ">>> [1/9] Building Proj ${PROJ_VER}"
    echo "========================================="

    smart_download "proj-${PROJ_VER}.tar.gz" \
        "https://download.osgeo.org/proj/proj-${PROJ_VER}.tar.gz" \
        "https://mirrors.huaweicloud.com/proj/${PROJ_VER}/proj-${PROJ_VER}.tar.gz" \
        "https://github.com/OSGeo/PROJ/releases/download/${PROJ_VER}/proj-${PROJ_VER}.tar.gz"

    cd "${SRC_DIR}"
    tar xzf "proj-${PROJ_VER}.tar.gz"

    # Patch for GCC 13+ compatibility (cstdint missing)
    local proj_src="${SRC_DIR}/proj-${PROJ_VER}"
    for f in $(grep -rl 'std::int64_t\|std::uint64_t' "${proj_src}/src/" --include='*.cpp' --include='*.hpp' 2>/dev/null); do
        if ! grep -q '#include <cstdint>' "$f"; then
            sed -i '1i #include <cstdint>' "$f"
            echo "    [PATCH] Added cstdint to $(basename $f)"
        fi
    done

    mkdir -p "${PROJ_PREFIX}/build"
    cd "${PROJ_PREFIX}/build"
    cmake "${proj_src}" \
        -DCMAKE_INSTALL_PREFIX="${PROJ_PREFIX}" \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF
    make -j"${NPROC}"
    make install

    # Verify
    "${PROJ_PREFIX}/bin/proj" 2>&1 | head -1
    echo ">>> Proj ${PROJ_VER} installed at ${PROJ_PREFIX}"
}

# ========================= 2. GEOS =========================
build_geos() {
    echo "========================================="
    echo ">>> [2/9] Building GEOS ${GEOS_VER}"
    echo "========================================="

    smart_download "geos-${GEOS_VER}.tar.bz2" \
        "https://download.osgeo.org/geos/geos-${GEOS_VER}.tar.bz2" \
        "https://mirrors.huaweicloud.com/geos/${GEOS_VER}/geos-${GEOS_VER}.tar.bz2" \
        "https://github.com/libgeos/geos/releases/download/${GEOS_VER}/geos-${GEOS_VER}.tar.bz2"

    cd "${SRC_DIR}"
    tar xjf "geos-${GEOS_VER}.tar.bz2"

    mkdir -p "${GEOS_PREFIX}/build"
    cd "${GEOS_PREFIX}/build"
    cmake "${SRC_DIR}/geos-${GEOS_VER}" \
        -DCMAKE_INSTALL_PREFIX="${GEOS_PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF
    make -j"${NPROC}"
    make install

    echo ">>> GEOS ${GEOS_VER} installed at ${GEOS_PREFIX}"
}

# ========================= 3. GDAL =========================
build_gdal() {
    echo "========================================="
    echo ">>> [3/9] Building GDAL ${GDAL_VER}"
    echo "========================================="

    smart_download "gdal-${GDAL_VER}.tar.gz" \
        "https://github.com/OSGeo/gdal/releases/download/v${GDAL_VER}/gdal-${GDAL_VER}.tar.gz" \
        "https://download.osgeo.org/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.gz" \
        "https://mirrors.huaweicloud.com/gdal/${GDAL_VER}/gdal-${GDAL_VER}.tar.gz"

    cd "${SRC_DIR}"
    tar xzf "gdal-${GDAL_VER}.tar.gz"

    mkdir -p "${GDAL_PREFIX}/build"
    cd "${GDAL_PREFIX}/build"

    export PKG_CONFIG_PATH="${PROJ_PREFIX}/lib/pkgconfig:${GEOS_PREFIX}/lib/pkgconfig"
    export LDFLAGS="-L${PROJ_PREFIX}/lib -L${GEOS_PREFIX}/lib -Wl,-rpath,${PROJ_PREFIX}/lib:${GEOS_PREFIX}/lib"
    export CXXFLAGS="-I${PROJ_PREFIX}/include -I${GEOS_PREFIX}/include"

    cmake "${SRC_DIR}/gdal-${GDAL_VER}" \
        -DCMAKE_INSTALL_PREFIX="${GDAL_PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_TESTING=OFF \
        -DBUILD_APPS=ON \
        -DCMAKE_PREFIX_PATH="${PROJ_PREFIX};${GEOS_PREFIX}"

    make -j"${NPROC}"
    make install

    echo ">>> GDAL ${GDAL_VER} installed at ${GDAL_PREFIX}"
}

# ========================= 4. PostgreSQL =========================
build_postgresql() {
    echo "========================================="
    echo ">>> [4/9] Building PostgreSQL ${PG_VER}"
    echo "========================================="

    smart_download "postgresql-${PG_VER}.tar.gz" \
        "https://ftp.postgresql.org/pub/source/v${PG_VER}/postgresql-${PG_VER}.tar.gz" \
        "https://mirrors.huaweicloud.com/postgresql/source/v${PG_VER}/postgresql-${PG_VER}.tar.gz" \
        "https://mirrors.tuna.tsinghua.edu.cn/postgresql/source/v${PG_VER}/postgresql-${PG_VER}.tar.gz"

    cd "${SRC_DIR}"
    tar xzf "postgresql-${PG_VER}.tar.gz"
    cd "postgresql-${PG_VER}"

    local configure_opts="--prefix=${PG_PREFIX} --with-openssl --with-readline --with-zlib --with-libxml"
    
    # openEuler typically has ICU, Ubuntu may or may not
    if pkg-config --exists icu-uc 2>/dev/null; then
        configure_opts="${configure_opts} --with-icu"
    else
        configure_opts="${configure_opts} --without-icu"
    fi

    ./configure ${configure_opts} CFLAGS='-O2'
    make -j"${NPROC}"
    make install

    # Build and install contrib modules
    cd contrib
    make -j"${NPROC}"
    make install

    "${PG_PREFIX}/bin/postgres" --version
    echo ">>> PostgreSQL ${PG_VER} installed at ${PG_PREFIX}"
}

# ========================= 5. PostGIS =========================
build_postgis() {
    echo "========================================="
    echo ">>> [5/9] Building PostGIS ${POSTGIS_VER}"
    echo "========================================="

    smart_download "postgis-${POSTGIS_VER}.tar.gz" \
        "https://download.osgeo.org/postgis/source/postgis-${POSTGIS_VER}.tar.gz" \
        "https://mirrors.huaweicloud.com/postgis/source/postgis-${POSTGIS_VER}.tar.gz" \
        "https://mirrors.tuna.tsinghua.edu.cn/postgis/source/postgis-${POSTGIS_VER}.tar.gz"

    cd "${SRC_DIR}"
    tar xzf "postgis-${POSTGIS_VER}.tar.gz"
    cd "postgis-${POSTGIS_VER}"

    export PKG_CONFIG_PATH="${PROJ_PREFIX}/lib/pkgconfig:${GEOS_PREFIX}/lib/pkgconfig:${GDAL_PREFIX}/lib/pkgconfig"
    export LD_LIBRARY_PATH="${PROJ_PREFIX}/lib:${GEOS_PREFIX}/lib:${GDAL_PREFIX}/lib"
    export PATH="${PG_PREFIX}/bin:${PATH}"

    ./configure \
        --with-pgconfig="${PG_PREFIX}/bin/pg_config" \
        --with-projdir="${PROJ_PREFIX}" \
        --with-geosconfig="${GEOS_PREFIX}/bin/geos-config" \
        --with-gdalconfig="${GDAL_PREFIX}/bin/gdal-config" \
        --without-raster \
        --without-topology \
        --without-address-standardizer \
        --without-gui

    make -j"${NPROC}"
    make install

    echo ">>> PostGIS ${POSTGIS_VER} installed"
}

# ========================= 6. pgRouting =========================
build_pgrouting() {
    echo "========================================="
    echo ">>> [6/9] Building pgRouting ${PGROUTING_VER}"
    echo "========================================="

    smart_download "pgrouting-${PGROUTING_VER}.tar.gz" \
        "https://github.com/pgRouting/pgrouting/releases/download/v${PGROUTING_VER}/pgrouting-${PGROUTING_VER}.tar.gz" \
        "https://mirrors.huaweicloud.com/pgrouting/v${PGROUTING_VER}/pgrouting-${PGROUTING_VER}.tar.gz"

    cd "${SRC_DIR}"
    tar xzf "pgrouting-${PGROUTING_VER}.tar.gz"

    mkdir -p "${INSTALL_BASE}/pgrouting-${PGROUTING_VER}/build"
    cd "${INSTALL_BASE}/pgrouting-${PGROUTING_VER}/build"

    export PKG_CONFIG_PATH="${PROJ_PREFIX}/lib/pkgconfig:${GEOS_PREFIX}/lib/pkgconfig:${GDAL_PREFIX}/lib/pkgconfig"
    export PATH="${PG_PREFIX}/bin:${PATH}"

    cmake "${SRC_DIR}/pgrouting-${PGROUTING_VER}" \
        -DCMAKE_INSTALL_PREFIX="${PG_PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release

    make -j"${NPROC}"
    make install

    echo ">>> pgRouting ${PGROUTING_VER} installed"
}

# ========================= 7. pg_repack =========================
build_pg_repack() {
    echo "========================================="
    echo ">>> [7/9] Building pg_repack ${PG_REPACK_VER}"
    echo "========================================="

    smart_download "pg_repack-${PG_REPACK_VER}.tar.gz" \
        "https://github.com/reorg/pg_repack/archive/refs/tags/ver_${PG_REPACK_VER}.tar.gz"

    cd "${SRC_DIR}"
    tar xzf "pg_repack-${PG_REPACK_VER}.tar.gz"
    cd "pg_repack-ver_${PG_REPACK_VER}"

    export PATH="${PG_PREFIX}/bin:${PATH}"
    make
    make install

    echo ">>> pg_repack ${PG_REPACK_VER} installed"
}

# ========================= 8. pg_top =========================
build_pg_top() {
    echo "========================================="
    echo ">>> [8/9] Building pg_top"
    echo "========================================="

    smart_download "pg_top-3.7.0.tar.gz" \
        "https://github.com/markwkm/pg_top/archive/refs/tags/v3.7.0.tar.gz"

    cd "${SRC_DIR}"
    tar xzf "pg_top-3.7.0.tar.gz"
    cd "pg_top-3.7.0"

    # Generate configure if missing
    if [ ! -f configure ]; then
        autoreconf -fi
    fi

    ./configure --prefix="${PGTOP_PREFIX}"
    make
    make install

    echo ">>> pg_top installed at ${PGTOP_PREFIX}"
}

# ========================= 9. pgaudit =========================
build_pgaudit() {
    echo "========================================="
    echo ">>> [9/9] Building pgaudit ${PGAUDIT_VER}"
    echo "========================================="

    cd "${SRC_DIR}"
    if [ ! -d pgaudit ]; then
        git clone https://github.com/pgaudit/pgaudit.git
    fi
    cd pgaudit
    git checkout "${PGAUDIT_VER}" 2>/dev/null || git checkout "refs/tags/${PGAUDIT_VER}"

    export PATH="${PG_PREFIX}/bin:${PATH}"
    make install USE_PGXS=1

    echo ">>> pgaudit ${PGAUDIT_VER} installed"
}

# ========================= Post-Install Configuration =========================
post_install_config() {
    echo "========================================="
    echo ">>> Post-install configuration"
    echo "========================================="

    # Create environment profile
    cat > /etc/profile.d/postgresql.sh << 'ENVEOF'
# PostgreSQL & GIS Stack Environment
export PATH="__PG_PREFIX__/bin:__GDAL_PREFIX__/bin:__PROJ_PREFIX__/bin:__GEOS_PREFIX__/bin:__PGTOP_PREFIX__/bin:$PATH"
export LD_LIBRARY_PATH="__PROJ_PREFIX__/lib:__GEOS_PREFIX__/lib:__GDAL_PREFIX__/lib:__PG_PREFIX__/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="__PROJ_PREFIX__/lib/pkgconfig:__GEOS_PREFIX__/lib/pkgconfig:__GDAL_PREFIX__/lib/pkgconfig:$PKG_CONFIG_PATH"
export PROJ_LIB="__PROJ_PREFIX__/share/proj"
export PGDATA="__PG_PREFIX__/data"
ENVEOF

    sed -i "s|__PG_PREFIX__|${PG_PREFIX}|g" /etc/profile.d/postgresql.sh
    sed -i "s|__GDAL_PREFIX__|${GDAL_PREFIX}|g" /etc/profile.d/postgresql.sh
    sed -i "s|__PROJ_PREFIX__|${PROJ_PREFIX}|g" /etc/profile.d/postgresql.sh
    sed -i "s|__GEOS_PREFIX__|${GEOS_PREFIX}|g" /etc/profile.d/postgresql.sh
    sed -i "s|__PGTOP_PREFIX__|${PGTOP_PREFIX}|g" /etc/profile.d/postgresql.sh

    chmod +x /etc/profile.d/postgresql.sh

    # Create ld.so.conf entry
    cat > /etc/ld.so.conf.d/postgresql.conf << LDEOF
${PROJ_PREFIX}/lib
${GEOS_PREFIX}/lib
${GDAL_PREFIX}/lib
${PG_PREFIX}/lib
LDEOF

    ldconfig

    echo ">>> Environment configured: /etc/profile.d/postgresql.sh"
    echo ">>> Library paths configured: /etc/ld.so.conf.d/postgresql.conf"
}

# ========================= Verify Installation =========================
verify_installation() {
    echo ""
    echo "========================================="
    echo ">>> Verification"
    echo "========================================="

    echo "1. Proj ${PROJ_VER}:"
    "${PROJ_PREFIX}/bin/proj" 2>&1 | head -1 || echo "   [FAIL]"

    echo "2. GEOS ${GEOS_VER}:"
    "${GEOS_PREFIX}/bin/geos-config" --version || echo "   [FAIL]"

    echo "3. GDAL ${GDAL_VER}:"
    "${GDAL_PREFIX}/bin/gdal-config" --version || echo "   [FAIL]"

    echo "4. PostgreSQL ${PG_VER}:"
    "${PG_PREFIX}/bin/postgres" --version || echo "   [FAIL]"

    echo "5. PostGIS ${POSTGIS_VER}:"
    ls "${PG_PREFIX}/lib/postgis-3.so" 2>/dev/null && echo "   postgis-3.so OK" || echo "   [FAIL]"

    echo "6. pgRouting ${PGROUTING_VER}:"
    ls "${PG_PREFIX}/lib/libpgrouting-"*.so 2>/dev/null && echo "   pgrouting OK" || echo "   [FAIL]"

    echo "7. pg_repack ${PG_REPACK_VER}:"
    ls "${PG_PREFIX}/bin/pg_repack" 2>/dev/null && echo "   pg_repack OK" || echo "   [FAIL]"

    echo "8. pg_top:"
    ls "${PGTOP_PREFIX}/bin/pg_top" 2>/dev/null && echo "   pg_top OK" || echo "   [FAIL]"

    echo "9. pgaudit ${PGAUDIT_VER}:"
    ls "${PG_PREFIX}/lib/pgaudit.so" 2>/dev/null && echo "   pgaudit OK" || echo "   [FAIL]"

    echo ""
    echo "========================================="
    echo ">>> All done! To start using:"
    echo "    source /etc/profile.d/postgresql.sh"
    echo "    initdb -D \${PGDATA}"
    echo "    pg_ctl -D \${PGDATA} -l logfile start"
    echo "========================================="
}

# ========================= Cleanup Build Artifacts =========================
cleanup() {
    echo ">>> Cleaning up build directories to save space..."
    rm -rf "${PROJ_PREFIX}/build" 2>/dev/null
    rm -rf "${GEOS_PREFIX}/build" 2>/dev/null
    rm -rf "${GDAL_PREFIX}/build" 2>/dev/null
    rm -rf "${INSTALL_BASE}/pgrouting-${PGROUTING_VER}/build" 2>/dev/null
    echo ">>> Cleanup done. Disk usage:"
    df -h /
}

# ========================= Main =========================
main() {
    echo "========================================="
    echo "  GIS Stack Source Compilation Installer"
    echo "  OS: auto-detect"
    echo "  Jobs: ${NPROC}"
    echo "  Source: ${SRC_DIR}"
    echo "  Install: ${INSTALL_BASE}"
    echo "========================================="

    mkdir -p "${SRC_DIR}" "${INSTALL_BASE}"

    # Step 0: Dependencies
    install_dependencies

    # Step 1-9: Build in dependency order
    build_proj
    build_geos
    build_gdal
    build_postgresql
    build_postgis
    build_pgrouting
    build_pg_repack
    build_pg_top
    build_pgaudit

    # Post-install
    post_install_config
    verify_installation
    cleanup
}

main "$@"
