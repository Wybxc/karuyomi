# v3 控制协议运行证据

2026-11-03，固定项目提交 `6e08ec9` 的独立工作树，Node 24.15.0、Temurin JDK 25.0.5+8、TeaVM 0.16.0 JS backend。扩展上游固定 `efa93f5a3537856fe830450bbe33f69d21d28167`，原版 Arknights Comics 1.6.2，未修改扩展业务源码或原始 JAR。本次只验证该提交的材料，不代表后续 Native 或 graphics 改动已通过同一门。

## 构建身份

| 对象                 | 身份                                                                        |
| -------------------- | --------------------------------------------------------------------------- |
| 控制 / HTTP          | protocolVersion 2，host ABI `karuyomi-source-host-v3`，HTTP bridgeVersion 2 |
| buildId              | `ext-en.arknightscomics-23489f22c8a1d874d1a62ca1ecd743a3`                   |
| host 指纹            | `2229bb210e74c8def41cda1fcbc7bbce6937dd8ad92a8aa01fdb765430ea1508`          |
| Source ID            | `5973713386239249589`                                                       |
| 原版 JAR SHA-256     | `7c1f6b29ad3a8d6888a78483deafb38d08f8c790f9e5a120bcf7ea26022f849d`          |
| canonical JS SHA-256 | `9a59756093fc1da525790aeffdab9910101687b0e3eaacc94a95a3fa9897bafe`          |
| materials 版本       | `fba63bcd9b2a194131eb76a500c2e8f046d987b4650d510d6b6f5205bf32a9e8`          |

Gradle → TeaVM → gzip 成功，原始 JS 1,888,332 B，gzip 604,798 B。构建报告只记录编译；下面的实际浏览器验证另行执行。

## 实际浏览器与 Source

Codex 内置浏览器 Chromium 156 在正式 `verify-build.ts --serve` 通过真实字节下载/解压、Worker 初始化、IndexedDB 与清单 Source ID 一致性，无 Source 网络请求。随后通过独立的真实 workerd、隔离 D1、RS256 测试 JWT 和显式本地网络政策执行在线门；政策仅包括 `arknights.global` 与 `webusstatic.yo-star.com`。

热门返回 17 项；以首项标题搜索得到同名 1 项；详情、3 个章节及 DREAM 的 51 页列表成功。latest 依源声明跳过。原 Page 对象保留在 Java 会话中，图片经原 Source 的图片请求与产品 HTTP v2 / 受管 Blob 通道，没有直接读取原图 URL 绕过 Source。

| 章节页   |       编码字节 | 实际解码    |
| -------- | -------------: | ----------- |
| 第 1 页  | 39,602 B，JPEG | 1200 × 1691 |
| 第 26 页 | 719,916 B，PNG | 1200 × 1691 |
| 第 51 页 | 718,931 B，PNG | 1200 × 1691 |

三张图片均通过显示解码、重复释放和 Blob URL 撤销；Page 会话关闭 ACK 通过。原始报告留在该工作树忽略的 `.local/protocol-v3/`，没有将请求流水或临时 JSON 复制入库。

## Flutter Web 产品边界

同一冻结提交使用 Flutter 3.47.5 / Dart 3.13.4 构建 Web release，通过 Source harness 的 `SOURCE_PROBE_READER_DIR` 入口在上述内置浏览器实际操作。正式 Dart 应用经“浏览→扩展→Source→漫画详情→DREAM”进入 ReaderScreen，显示真实首图；双页翻到第 2/3 页、切换单页、缩放/重置、切换竖向连续、继续前进至第 3 页、打开/关闭图片放大层均通过。模式与放大层切换保留逻辑页；退出阅读器回到真实章节列表。原始网络摘要留在忽略的 `.local/protocol-v3/flutter-source.json`，未抓取 Cookie 或凭据。

## 复验与限制

按 [构建入口](../../runtime/teavm/README.md) 从当前固定输入生成 descriptor 与代表包，再运行：

```sh
pnpm --filter @karuyomi/runtime-host build
node tools/extensions/verify-build.ts --directory PATH_TO_OUTPUT --serve
SOURCE_PROBE_ALLOWED_HOSTS=arknights.global,webusstatic.yo-star.com \
SOURCE_PROBE_IMAGES=1 \
node apps/api/test/source-metadata-probe.ts PATH_TO_OUTPUT/manifest.json PATH_TO_OUTPUT/artifacts
```

用 Codex 内置浏览器打开各命令报告的本地地址，在 Source 页点击运行。实际操作合同见 [Source 门说明](../../apps/api/test/source-metadata-probe.md)。材料或 host 输入变化后应重新构建，不能混装该包与新材料。

这里没有验证生产 Access、真实 Native Source 图片、物理设备、整章逐页与下一章、进度持久化或进程/GPU 峰值；也没有完成这次新身份的运行中取消门。本次 Flutter 结果属于 v3；历史 v2 结果仍保持原身份。生产旧快照与固定 `022d828` 的初次全量保持独立，未因本次门通过而自动部署。
