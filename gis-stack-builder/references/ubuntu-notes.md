# Ubuntu 24.04 编译安装注意事项

## 已验证的已知问题与解决方案

### 1. Proj 8.2.1 与 GCC 13 的兼容性问题

**问题**: Ubuntu 24.04 默认使用 GCC 13.3.0，Proj 8.2.1 的源码中 `proj_json_streaming_writer.hpp` 和 `s2.cpp` 使用了 `std::int64_t` / `std::uint64_t` 但缺少 `#include <cstdint>`，导致编译失败。

**错误信息**:
```
error: 'int64_t' in namespace 'std' does not name a type
error: 'uint64_t' in namespace 'std' does not name a type; did you mean 'wint_t'?
```

**修复方法**:
```bash
# 自动检测并修补所有受影响文件
for f in $(grep -rl 'std::int64_t\|std::uint64_t' /root/src/proj-8.2.1/src/ --include='*.cpp' --include='*.hpp'); do
    if ! grep -q '#include <cstdint>' "$f"; then
        sed -i '1i #include <cstdint>' "$f"
    fi
done
```

**受影响文件**:
- `src/proj_json_streaming_writer.hpp`
- `src/proj_json_streaming_writer.cpp`
- `src/projections/s2.cpp`

### 2. PostgreSQL 编译时 ICU 选项

Ubuntu 24.04 默认安装了 ICU 库但可能缺少开发头文件。建议使用 `--without-icu` 编译 PostgreSQL，除非明确需要 ICU 排序规则支持。

如需 ICU 支持：
```bash
apt-get install -y libicu-dev
./configure --prefix=/postgresql/pg15 --with-openssl --with-icu ...
```

### 3. CMake 配置 GDAL 时变量名问题

GDAL 3.8.5 的 CMake 配置不直接接受 `-DPROJ_INCLUDE_DIR` / `-DGEOS_LIBRARY` 等变量。正确做法是通过 `PKG_CONFIG_PATH` 和 `CMAKE_PREFIX_PATH` 让 CMake 自动发现：

```bash
export PKG_CONFIG_PATH="/postgresql/proj-8.2.1/lib/pkgconfig:/postgresql/geos-3.12.3/lib/pkgconfig"
export LDFLAGS="-L/postgresql/proj-8.2.1/lib -L/postgresql/geos-3.12.3/lib -Wl,-rpath,/postgresql/proj-8.2.1/lib:/postgresql/geos-3.12.3/lib"
export CXXFLAGS="-I/postgresql/proj-8.2.1/include -I/postgresql/geos-3.12.3/include"

cmake /root/src/gdal-3.8.5 \
    -DCMAKE_INSTALL_PREFIX=/postgresql/gdal-3.8.5 \
    -DCMAKE_PREFIX_PATH="/postgresql/proj-8.2.1;/postgresql/geos-3.12.3"
```

### 4. pgRouting CMake 配置

pgRouting 的 CMake 不识别 `-DPG_CONFIG` 参数，需要通过 `PATH` 环境变量让 CMake 找到 `pg_config`：

```bash
export PATH=/postgresql/pg15/bin:$PATH
cmake /root/src/pgrouting-3.6.3 -DCMAKE_INSTALL_PREFIX=/postgresql/pg15
```

### 5. 磁盘空间管理

编译过程需要大量临时空间。建议：
- 每个软件编译安装完成后，删除 build 目录释放空间
- 源码 tar 包可保留便于重新编译
- 监控磁盘使用：`df -h /`

### 6. 下载源选择

国内服务器推荐下载源优先级：
1. 华为云镜像: `https://mirrors.huaweicloud.com/`
2. 清华大学镜像: `https://mirrors.tuna.tsinghua.edu.cn/`
3. 网易镜像: `https://mirrors.163.com/`
4. 官方源 (备选): OSGeo / GitHub

### 7. 完整依赖安装命令 (Ubuntu 24.04)

```bash
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
    flex bison
```
