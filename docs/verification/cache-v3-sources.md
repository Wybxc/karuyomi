# Cache v3 材料的三源在线复验

2026-11-04，主代理使用 Codex 内置浏览器 Chromium 156，验证固定提交 `31555e8e367405501b7f485f534f533e0299a6cd` 的 xkcd、Arknights Comics 与 CuuTruyen。三源均通过真实元数据、原 Source 图片处理、浏览器解码及资源释放门；这不是 Cache 冷热命中、运行中取消、完整连续阅读、生产 Access 或 Native 验收。

## 固定输入

独立受管树为 `/Users/wybxc/.codex/worktrees/cache-v3-source-validation/karuyomi`。安装 frozen lockfile、重新准备工具链并扫描完整计划：1448 包，0 discovery failure；仅本地构建本次三包，没有发布快照或部署。构建前后跟踪文件保持干净。

- host 输入指纹：`6510c9c1a8047174314ae76a50930cb14a976b27aaafb7283eb92f1b62d7f037`。
- 材料版本：`63a061a11e24d1bd9a27bbe453960768035229afe3665be96d3302182d887a9d`。
- Cache 桥 SHA-256：`7fc988f9937eaaf232c42a52e61e9a45112377e4d09be857386b356e77c36518`，与 [39 组 Cache 机制门](http-cache-runtime.md)的最终字节一致；不能把那些机制门当作本次 Source 的命中计数。
- 协议身份：`protocolVersion=2`、`hostAbi=karuyomi-source-host-v3`、`bridgeVersion=2`、`teavm-0.16.0-js-release9`。
- 上游 pin：extensions-source `efa93f5a3537856fe830450bbe33f69d21d28167`；Suwayomi `6b481e8b62938b9c060eb210b934e0fbfdfa466b`；TeaVM `e87d452e4bd70c77b9e19314a46c3d6971c148b6`。

沿用 debug keystore SHA-256 `996d5580381cab3931f72c95696f88c0fe1e5ad53356a336f0e73f0099cf0b75`，由官方 Gradle `assembleRelease` 重产未经适配的 Source 签名 JAR。下表均与既定原 JAR 基线严格一致，没有改业务源码或 JAR。

| Source           | 原 JAR                                    |   字节 | SHA-256                                                            |
| ---------------- | ----------------------------------------- | -----: | ------------------------------------------------------------------ |
| xkcd             | `tachiyomi-all.xkcd-v1.6.1.jar`           | 125470 | `4071fdc5b90c473938d33f7e94c71b2a1a79fb33a00a32d0baa035ac4697cc9d` |
| Arknights Comics | `tachiyomi-en.arknightscomics-v1.6.2.jar` |  88472 | `e1a706cc4b504af04bf2ebbb3046d36421a949fca0633e69166e34415d657cf3` |
| CuuTruyen        | `tachiyomi-vi.cuutruyen-v1.6.2.jar`       | 150434 | `5bdd45cd036c0be02097bd025d359293d33485848210fcd809ad063715e263ce` |

三包引用的 5 个桥和 1 个 WASM 与同树正式 runtime-host 构建逐字段一致；没有混入旧材料版本 `80c9e303…`。

| 本地目录    | buildId                                                   | canonical 字节 | gzip 字节 |
| ----------- | --------------------------------------------------------- | -------------: | --------: |
| `xkcd`      | `ext-all.xkcd-f7321a31dcfdb9d61c08decb2b525d28`           |        4035206 |    852496 |
| `arknights` | `ext-en.arknightscomics-8da1e05a92a687653cd85398c1991427` |        1899702 |    606976 |
| `cuutruyen` | `ext-vi.cuutruyen-68ae437c3bdd1bd1385285101a1bbd1d`       |        2105648 |    658342 |

| Source           | manifest SHA-256                                                   | canonical bundle SHA-256                                           |
| ---------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------ |
| xkcd             | `3f010a1451b5f84e2bd276bd6695e3f179cf05962cd9a6ae3e4a0b0dcc6dc6b4` | `9d3e21523c568bc178bcea8bb81c9833ce4edbd63cd0ec87e167e60b97ffc809` |
| Arknights Comics | `47d0cbf5dde7e1bc98de815cc6a34a2230677ccbee7320bd61acecf53c45ff2c` | `62c78b9473eb75ae3b181da49f3dec947edc14bdb6b9323a1dfc66ce7e3a7916` |
| CuuTruyen        | `c02b2edb09a4a13d6b623a5894633b7f5b3267980aac3127a7616de2a7ee8beb` | `c33f4b31626423fc21b0a8991f29775cabc54c3c362a09bf427869a84fad2ef6` |

## 真实执行结果

入口为该冻结树的正式 `apps/api/test/source-metadata-probe.ts`：产品 host/Worker、Static Assets gzip、真实 workerd HTTP v2、隔离的 policy-only D1，以及真实 RS256 校验的测试身份。loopback 代理仅给测试 API hop 提供签名和 origin alias；没有绕过产品鉴权，也没有证明真实生产 Access。网络政策是显式列出的精确主机，不根据请求自动扩张。

| Source                                 | 元数据与原章                                                                                           | 实际图片结果                                                                                            |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| xkcd 英文 `1538249443376436084`        | 热门 1 项；搜索按原实现返回 0；详情、3318 章、`3319: Elevators` 两页成功；latest 明确不支持            | 页 0：PNG 106037 B，607×716；页 1：原 TextInterceptor 生成 PNG 49246 B，1000×286                        |
| Arknights Comics `5973713386239249589` | 热门 17 项、标题搜索 1 项、详情和 3 章；`DREAM` 返回 51 页；latest 明确不支持                          | 首/中/末 0/25/50：39602/719916/718931 B，均 1200×1691；首图 JPEG，其余 PNG                              |
| CuuTruyen `8222087175453285202`        | 热门两页各 24 项、标题搜索 5 项、latest 30 项；详情及 175 章；`Chương 142` 返回 23 页，全部含 DRM 引用 | 首/中/末 0/11/22 经原 Source 解密重排输出 JPEG：746910/493881/563725 B，2048×1152、1024×1606、2048×1223 |

三个报告均为 `imageGate=passed`、`finished=true`；要求的 2/3/3 张图片全部成功。图片先从 DOM 撤下，再重复释放并确认 Blob URL 已撤销，最后确认 Page session 关闭，没有 `disposeError`。xkcd 的 `tachiyomi-lib-textinterceptor` 引用在原拦截器内处理，没有加入外部网络白名单。所有网络正文按正式 HTTP v2 读取到 END/EOF，本轮没有用原图 URL 绕过 Source。

## 复验入口与证据

从冻结树运行，使用 `.node-version` 固定的 Node 24.15.0；依赖和构建入口见 [扩展构建说明](../EXTENSIONS.md)。本次完整计划及三包输出位于 ignored `.local/cache-v3-source/`，目录各含 `manifest.json`、唯一 `artifacts/<canonicalSHA>.gz`、provenance、构建和完整性报告。

```sh
SOURCE_PROBE_SOURCE_ID=1538249443376436084 \
SOURCE_PROBE_ALLOWED_HOSTS=xkcd.com,imgs.xkcd.com \
SOURCE_PROBE_IMAGES=1 SOURCE_PROBE_PORT=8897 \
SOURCE_PROBE_EVIDENCE=.local/cache-v3-source/online/xkcd.json \
node apps/api/test/source-metadata-probe.ts \
  .local/cache-v3-source/xkcd/manifest.json \
  .local/cache-v3-source/xkcd/artifacts
```

在内置浏览器打开输出的 loopback URL，点击 `Run real metadata operations`。另外两源使用相同入口与各自目录/报告：

| Source           | Source ID             | `SOURCE_PROBE_ALLOWED_HOSTS`                                                               | 端口 |
| ---------------- | --------------------- | ------------------------------------------------------------------------------------------ | ---: |
| Arknights Comics | `5973713386239249589` | `arknights.global,webusstatic.yo-star.com`                                                 | 8898 |
| CuuTruyen        | `8222087175453285202` | `cuutruyen.net,hetcuutruyen.net,storage-bravo.cuutruyen.net,storage-charlie.cuutruyen.net` | 8899 |

ignored `build-summary.json` 保存完整 input/source 指纹、gzip 摘要与工件路径；`source-online-inputs.json`、`source-online-commands.md` 保存三源精确参数与命令。实际原始报告为 `online/xkcd.json`、`online/arknights.json`、`online/cuutruyen.json`。它们不保存 Cookie/授权值、正文或签名图片查询参数。

该冻结 probe 尚使用 `streamChunks` async generator；pending-read 取消传播的后续 main 修复不在本次证据中。本轮只验证正常完整 EOF，不证明断开或取消。公开接口没有 Java Cache 的 request/network/hit/write 计数，xkcd 自身也有一小时内存缓存；网络请求数量或减少不能作为 Cache 命中证明。

## 正式 Flutter 阅读与恢复中的限制

同树正式 Flutter Web release 的 `main.dart.js` 为 3604346 B，SHA-256 `1dfa8f750c829da2e3cd5ed727e36e9c619fd0137d802c8b8d51fa25a80d2663`；Drift 官方 WASM/worker 摘要匹配。Reader 模式命令保存在 ignored `reader-commands.md`。以 `SOURCE_PROBE_READER_DIR=apps/reader/build/web` 启动同一 probe，内置浏览器从正式“浏览→扩展→英文 Source→漫画详情”进入 xkcd，未使用测试 widget 或直接调用产品内部状态。

实际显示 `3319: Elevators` 的直图与原 TextInterceptor 文字图；末页经“读完本章”后显示本地进度已保存和本章已读完。在同一路由点击“下一章”进入 `3318: Earth Sized Planets`，两页和显式完成同样通过。实际截图保留正文与状态，没有仅凭资源计数或语义树宣称显示。

关闭标签页后重新打开相同 origin，从详情“继续阅读”恢复 `3318` 的末页 current/furthest/completed，界面显示 `2 / 2`、本地进度已保存、本章已读完。但首次恢复的内容区域为空黑，等待后仍未显示；无 console warning/error。点击上一页显示直图，再下一页文字图正常。故本轮**持久状态恢复分项成立，首次恢复视觉门失败**，整轮 UI 报告保持 `passed:false`，不能用翻页后的成功覆盖初始失败。

主树 ignored `.local/cache-v3-reader/` 保存 `xkcd-ui-report.json`、两章完成截图 `xkcd-{completed,next-completed}.png` 与首次空黑恢复图 `xkcd-restored.png`；冻结树 `online/xkcd-reader.json` 保留脱敏真实网络流水。完整浏览器进程重启、该视觉缺陷修复与后续材料仍需独立复验。

本记录不提升流水线的 `compiled_unverified/runtimeReady=false` 状态，不替代生产、Native 或设备资源验收。
