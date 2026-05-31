# GIS 软件栈版本兼容性矩阵

## 已验证的版本组合

| 组件 | 版本 | 依赖 | 安装路径约定 |
|------|------|------|-------------|
| Proj | 8.2.1 | libsqlite3, libtiff, libcurl | `/postgresql/proj-8.2.1` |
| GEOS | 3.12.3 | (无特殊依赖) | `/postgresql/geos-3.12.3` |
| GDAL | 3.8.5 | Proj >= 8.0, GEOS >= 3.8 | `/postgresql/gdal-3.8.5` |
| PostgreSQL | 15.18 | OpenSSL, Readline, Zlib | `/postgresql/pg15` |
| PostGIS | 3.4.4 | Proj >= 8.0, GEOS >= 3.8, GDAL >= 3.5, PG >= 12 | 集成到 PG |
| pgRouting | 3.6.3 | PG >= 12, PostGIS >= 3.0, Boost >= 1.56 | 集成到 PG |
| pg_repack | 1.5.3 | PG >= 12 | 集成到 PG |
| pg_top | 3.7.0 | PG libpq, ncurses | `/postgresql/pg_top` |
| pgaudit | 1.7.1 | PG >= 15 | 集成到 PG |

## 编译安装顺序（按依赖关系）

```
1. Proj 8.2.1       → 基础库，无依赖
2. GEOS 3.12.3      → 基础库，无依赖
3. GDAL 3.8.5       → 依赖 Proj, GEOS
4. PG 15.18         → 依赖 OpenSSL, Readline 等
5. PostGIS 3.4.4    → 依赖 Proj + GEOS + GDAL + PG
6. pgRouting 3.6.3  → 依赖 PostGIS + PG + Boost
7. pg_repack 1.5.3  → 依赖 PG
8. pg_top           → 依赖 PG libpq
9. pgaudit          → 依赖 PG
```

## 关键环境变量

编译时需要设置的环境变量：

```bash
# 让 CMake/configure 找到自编译的库
export PKG_CONFIG_PATH="/postgresql/proj-8.2.1/lib/pkgconfig:/postgresql/geos-3.12.3/lib/pkgconfig:/postgresql/gdal-3.8.5/lib/pkgconfig"

# 运行时库搜索路径
export LD_LIBRARY_PATH="/postgresql/proj-8.2.1/lib:/postgresql/geos-3.12.3/lib:/postgresql/gdal-3.8.5/lib:/postgresql/pg15/lib"

# PostgreSQL 工具路径
export PATH="/postgresql/pg15/bin:$PATH"

# Proj 数据目录
export PROJ_LIB="/postgresql/proj-8.2.1/share/proj"
```

## PostgreSQL 扩展启用

启动 PostgreSQL 后，在数据库中执行：

```sql
-- 核心空间扩展
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;

-- 路径规划
CREATE EXTENSION pgrouting;

-- 表空间整理
CREATE EXTENSION pg_repack;

-- 审计日志
-- 注意: pgaudit 需要在 postgresql.conf 中配置
-- shared_preload_libraries = 'pgaudit'
-- pgaudit.log = 'all'
```

## 下载源清单

| 软件 | 官方源 | 华为镜像 | 清华镜像 |
|------|--------|----------|----------|
| Proj | https://download.osgeo.org/proj/ | https://mirrors.huaweicloud.com/proj/ | - |
| GEOS | https://download.osgeo.org/geos/ | https://mirrors.huaweicloud.com/geos/ | - |
| GDAL | https://download.osgeo.org/gdal/ | https://mirrors.huaweicloud.com/gdal/ | - |
| PostgreSQL | https://ftp.postgresql.org/pub/source/ | https://mirrors.huaweicloud.com/postgresql/ | https://mirrors.tuna.tsinghua.edu.cn/postgresql/ |
| PostGIS | https://download.osgeo.org/postgis/source/ | https://mirrors.huaweicloud.com/postgis/ | - |
| pgRouting | https://github.com/pgRouting/pgrouting/releases | - | - |
| pg_repack | https://github.com/reorg/pg_repack/releases | - | - |
| pgaudit | https://github.com/pgaudit/pgaudit | - | - |
