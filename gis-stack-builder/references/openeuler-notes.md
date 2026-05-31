# openEuler 22.03 编译安装注意事项

## 系统差异

openEuler 22.03 基于 RPM 包管理，默认使用 yum/dnf 作为包管理器，与 Ubuntu 的 apt 有显著差异。

## 依赖包映射表

| 功能 | Ubuntu 24.04 包名 | openEuler 22.03 包名 |
|------|-------------------|---------------------|
| 编译工具链 | build-essential | gcc gcc-c++ make |
| CMake | cmake | cmake |
| 下载工具 | wget curl | wget curl |
| SQLite 开发 | libsqlite3-dev | sqlite-devel |
| TIFF 开发 | libtiff-dev | libtiff-devel |
| cURL 开发 | libcurl4-openssl-dev | libcurl-devel |
| JSON-C 开发 | libjson-c-dev | json-c-devel |
| XML2 开发 | libxml2-dev | libxml2-devel |
| Readline 开发 | libreadline-dev | readline-devel |
| Zlib 开发 | zlib1g-dev | zlib-devel |
| OpenSSL 开发 | libssl-dev | openssl-devel |
| Protobuf-C | libprotobuf-c-dev | protobuf-c-devel |
| PCRE 开发 | libpcre3-dev | pcre-devel |
| Boost 开发 | libboost-dev libboost-graph-dev | boost-devel boost-graph |
| LZMA 开发 | liblzma-dev | xz-devel |
| Zstd 开发 | libzstd-dev | libzstd-devel |
| Ncurses 开发 | libncurses5-dev | ncurses-devel |
| ICU 开发 | (通常不装) | libicu-devel |
| Flex/Bison | flex bison | flex bison |
| Git | git | git |
| Autoconf | autoconf automake libtool | autoconf automake libtool |

## openEuler 特有注意事项

### 1. 镜像源配置

华为云镜像加速：
```bash
sed -i 's|repo.openeuler.org|repo.huaweicloud.com/openeuler|g' /etc/yum.repos.d/*.repo
yum clean all && yum makecache
```

清华镜像：
```bash
sed -i 's|repo.openeuler.org|mirrors.tuna.tsinghua.edu.cn/openeuler|g' /etc/yum.repos.d/*.repo
```

### 2. PostgreSQL 编译选项差异

openEuler 22.03 自带 ICU 库，编译 PostgreSQL 时建议加上 `--with-icu`：
```bash
./configure --prefix=/postgresql/pg15 --with-openssl --with-readline --with-zlib --with-libxml --with-icu CFLAGS='-O2'
```

Ubuntu 24.04 可能没有 ICU 开发包，建议用 `--without-icu`。

### 3. GCC 版本差异

- openEuler 22.03 默认 GCC 10.x，与 Proj 8.2.1 兼容，通常不需要 cstdint 补丁
- Ubuntu 24.04 默认 GCC 13.x，Proj 8.2.1 需要 `#include <cstdint>` 补丁

### 4. 库路径差异

- Ubuntu: `/usr/lib/x86_64-linux-gnu/`
- openEuler: `/usr/lib64/`

### 5. pg_top 编译

openEuler 上 pg_top 可能需要额外依赖：
```bash
yum install -y ncurses-devel libtermcap-devel
```

### 6. SELinux

openEuler 默认启用 SELinux，可能阻止 PostgreSQL 访问某些文件。可临时关闭：
```bash
setenforce 0
# 或永久关闭
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
```

## 完整依赖安装命令 (openEuler 22.03)

```bash
yum groupinstall -y "Development Tools"
yum install -y \
    cmake wget curl \
    sqlite-devel libtiff-devel \
    libcurl-devel json-c-devel \
    libxml2-devel readline-devel \
    zlib-devel openssl-devel \
    protobuf-c-devel protobuf-c-compiler \
    pcre-devel boost-devel boost-graph \
    xz-devel libzstd-devel pkgconfig \
    libtool autoconf automake git \
    ncurses-devel libtermcap-devel \
    flex bison \
    perl-IPC-Run perl-ExtUtils-Embed \
    libicu-devel
```
