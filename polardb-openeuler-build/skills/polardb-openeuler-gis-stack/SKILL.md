---
name: polardb-openeuler-gis-stack
description: 在 openEuler 22.03 上从源码编译 PolarDB for PostgreSQL GIS/工具扩展栈，包括 PROJ, GEOS, GDAL, PostGIS, pgRouting, pg_repack, pg_top, pgaudit，并保持固定版本。
---

# PolarDB openEuler GIS 扩展栈

当用户要求在 openEuler 22.03，尤其是 `openeuler22` 或类似 aarch64/x86_64 服务器上，源码编译或复现 PolarDB for PostgreSQL GIS/工具扩展栈时，使用这个 skill。

## 默认版本

- PROJ `8.2.1`
- GEOS `3.12.3`
- GDAL `3.8.5`
- PolarDB for PostgreSQL `v15.18.5.0`
- PostGIS `3.4.4`
- pgRouting `3.6.3`
- pg_repack `1.5.3`
- pg_top `v4.1.1`
- pgaudit `REL_15_STABLE`，对应 PG 15 的 `1.7.1` 扩展线

## 脚本

使用配套脚本：

```bash
scripts/build_polardb_gis_stack.sh
```

在远程服务器上运行时，将脚本复制过去，或通过 `ssh 'bash -s'` 输入执行。执行用户需要有权限写入 `/polardb`、`/root/src` 和 `/root/buildlogs`。

在 `openeuler22` 上的典型用法：

```bash
ssh openeuler22 'bash -s' < scripts/build_polardb_gis_stack.sh
```

如果需要先安装系统构建依赖：

```bash
ssh openeuler22 'INSTALL_DEPS=1 bash -s' < scripts/build_polardb_gis_stack.sh
```

如果 PROJ/GEOS/GDAL 已经编译好，只想重编 PolarDB 和扩展：

```bash
ssh openeuler22 'BUILD_BASE_LIBS=0 bash -s' < scripts/build_polardb_gis_stack.sh
```

## 重要路径

- 源码目录：`/root/src`
- 日志目录：`/root/buildlogs`
- 基础库安装目录：
  - `/polardb/proj-8.2.1`
  - `/polardb/geos-3.12.3`
  - `/polardb/gdal-3.8.5`
- `v15.18.5.0` 默认 PolarDB prefix：
  - `/polardb/pgsql15.18`
  - 实际二进制目录：`/polardb/pgsql15.18/tmp_polardb_pg_15_base/bin`

PolarDB 的 `build.sh --prefix=/polardb/pgsql15.18` 会把实际安装内容放到 `tmp_polardb_pg_15_base` 子目录下，这是预期行为。

## 版本覆盖

脚本通过环境变量控制版本和路径：

```bash
POLARDB_TAG=v15.17.5.0 PG_PREFIX=/polardb/pgsql15.17 bash build_polardb_gis_stack.sh
POLARDB_TAG=v15.18.5.0 bash build_polardb_gis_stack.sh
JOBS=16 bash build_polardb_gis_stack.sh
```

常用变量：

- `PROJ_VERSION`
- `GEOS_VERSION`
- `GDAL_VERSION`
- `POLARDB_TAG`
- `POSTGIS_VERSION`
- `PGROUTING_VERSION`
- `PG_REPACK_VERSION`
- `PG_TOP_TAG`
- `PGAUDIT_REF`
- `PREFIX_ROOT`
- `SRC_DIR`
- `LOG_DIR`
- `JOBS`
- `INSTALL_DEPS`
- `BUILD_BASE_LIBS`

## 编译顺序

1. 如果设置了 `INSTALL_DEPS=1`，先安装 RPM 构建依赖。
2. 下载并解压 release 源码包。
3. clone 或 fetch PolarDB、pg_top、pgaudit 的 Git 仓库。
4. 编译 PROJ、GEOS、GDAL；如果它们已存在且 `BUILD_BASE_LIBS=auto`，则复用已有安装。
5. 使用 `./build.sh --ni --port=5432 --debug=off --prefix=...` 编译 PolarDB，不初始化集群。
6. 将 PostGIS 编译到指定 PolarDB，并固定使用指定 PROJ/GEOS/GDAL 路径。
7. 将 pgRouting 编译到指定 PolarDB。
8. 使用 `USE_PGXS=1` 编译 pg_repack。
9. 使用 CMake 编译 pg_top。
10. 使用 `USE_PGXS=1` 编译 pgaudit。
11. 校验版本、扩展文件和关键动态链接。

## 已知注意点

- openEuler 22.03 的默认仓库里可能没有 `cgal-devel`；pgRouting `3.6.3` 的常规扩展仍可成功编译。
- `pg_top v4.1.1` 是 CMake 项目，不要用普通 PGXS `make` 方式编译。
- pgaudit 如果不在 PostgreSQL 源码树内编译，必须显式加 `USE_PGXS=1`。
- PROJ `8.2.1` 的 `projinfo` 不支持 `--version`；校验时用 `proj` 输出或检查库文件。
- 校验时设置 `LD_LIBRARY_PATH`，确保 PostGIS raster 解析到 `/polardb/gdal-3.8.5`、`/polardb/proj-8.2.1`、`/polardb/geos-3.12.3`。

## 校验命令

```bash
PGHOME=/polardb/pgsql15.18/tmp_polardb_pg_15_base
export LD_LIBRARY_PATH=$PGHOME/lib:/polardb/proj-8.2.1/lib:/polardb/geos-3.12.3/lib:/polardb/gdal-3.8.5/lib:$LD_LIBRARY_PATH

/polardb/proj-8.2.1/bin/proj 2>&1 | head -1
/polardb/geos-3.12.3/bin/geos-config --version
/polardb/gdal-3.8.5/bin/gdal-config --version
$PGHOME/bin/pg_config --version
$PGHOME/bin/pg_repack --version
$PGHOME/bin/pg_top --version

ls $PGHOME/share/extension/postgis--3.4.4.sql
ls $PGHOME/share/extension/postgis_raster--3.4.4.sql
ls $PGHOME/share/extension/pgrouting--3.6.3.sql
ls $PGHOME/share/extension/pg_repack--1.5.3.sql
ls $PGHOME/share/extension/pgaudit--1.7.1.sql
ldd $PGHOME/lib/postgis_raster-3.so | grep -E 'libgdal|libproj|libgeos'
```
