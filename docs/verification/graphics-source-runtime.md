# 有界图形宿主的真实 Source 分项

2026-11-03 至 04，固定主仓库 `15a3900f63f0023a491414e08cd040c0772f71ce`、扩展源码 `efa93f5a3537856fe830450bbe33f69d21d28167`。工具链/原 JAR 与 Source 业务源码未修改。新材料包含二进制有界 graphics 与 Worker lifetime Cache editor；不包含后续正在实现的 Cache 正文分块。

host 输入指纹 `5d83479c087a11e609b9b4234312e4647af9d612ea1d72c3113412a061b1a85d`，材料版本 `8c615d89210ff6a9d3d0d2846449da1489c82466c580f22134e3359a70a7728f`。控制身份为 host ABI v3 / protocolVersion 2，HTTP bridgeVersion 2。六包本地 AOT 与 gzip 完整性通过：

| 包           | buildId                                                   | JavaScript 字节 | gzip 字节 |
| ------------ | --------------------------------------------------------- | --------------: | --------: |
| arknights    | `ext-en.arknightscomics-207adfd84cc88f7e00d133a3b6ac8e72` |       1,888,333 |   604,821 |
| cuutruyen    | `ext-vi.cuutruyen-8a40b2fc094034095e3be8ba3b9eba15`       |       2,090,016 |   655,210 |
| littletyrant | `ext-pt.littletyrant-22aa6b9e1b28a9f3cb1ff4b34dcbb6e7`    |       4,282,476 |   880,508 |
| philiascans  | `ext-en.philiascans-7c656b9b517ec8edbe5df6ac6e6d85f7`     |       2,938,209 |   656,575 |
| mangadex     | `ext-all.mangadex-044c1d878e89853644e5a7bc2f3a7943`       |       3,876,531 |   821,995 |
| xkcd         | `ext-all.xkcd-a35d1fb61661593eacafc5ee4818f77a`           |       3,990,290 |   848,177 |

## 实际内置浏览器

Codex 内置浏览器 Chromium 156，正式 host、产品 Worker、隔离 D1、真实 workerd 与 RS256 **测试身份**。公开静态产物按当前材料加载；没有把测试身份称为生产 Access。所有请求使用显式站点白名单。

- Arknights Comics：热门 17 项，标题搜索 1 项，详情与 3 章成功，DREAM 返回 51 页。原 Source 首/中/末页 0/25/50 解码为 1200×1691，分别 39602/719916/718931 字节；释放幂等且 Blob URL 撤销。latest 按 Source 声明跳过。
- CuuTruyen：实际热门、第二页、标题搜索、latest、详情与 175 章成功；Spy x Family 的 Chương 142 返回 23 页，全部含非空 `drm_data`。首/中/末 0/11/22 经原 ImageInterceptor 的 Base64/XOR 映射、BitmapFactory、Canvas 条带重排与 JPEG95 返回，分别为 746910/493881/563725 字节，尺寸 2048×1152、1024×1606、2048×1223。原站 scrambled JPEG 经 `storage-bravo.cuutruyen.net` 正常取回；原 Source 拒绝非 v4 映射，三页成功确认实际走了处理分支。解码、释放和撤销通过。
- Little Tyrant：Worker 初始化与 Source ID 检查成功；`tiraninha.world/wp-admin/admin-ajax.php` 的热门、搜索、latest 均收到真实 403，未取得漫画/章节引用。特殊头/Cookie 与 XOR 图片链未测；不伪造引用或绕过拒绝。
- Philia Scans：Worker 初始化与 Source ID 检查成功；`philiascans.org/api/manga` 三项列表请求均为真实 403。未取得公开章，token、图片解密及重排未测，不绕过 `hasAccess` 或登录/付费检查。

- MangaDex：原包 61 个 Source 初始化并与清单匹配，明确选英文 `2499283573021220255`；热门、搜索、latest 均在约 10 秒后返回结构化 HTTP timeout，没有取得上游 HTTP 状态。未获得真实漫画/章节，后续详情、pages 与动态 MD@Home 图片未测；没有伪造引用、扩张域名政策或把超时写成 403。

- xkcd：原包五语言 Source 初始化成功，英文 `1538249443376436084` 的热门、详情、3318 章及两页列表成功；搜索按原实现返回空列表，latest 明确不支持。第 3319 章直图经原 Source 返回 106037 字节 PNG（607×716），释放和撤销通过；第二页由原 TextInterceptor 生成文字图片时遇到 `java.lang.RuntimeException: Stub!`。图片 gate 因此失败，不能把第一张成功视作完整章节通过；正在定位宿主缺失的 Android 适配，不修改 Source 或绕过文字页。

这只证明上述浏览器元数据、Source 图片分项和失败边界；尚无三至五源全部在线、完整连续阅读、Native、运行中取消、实际进程/GPU 峰值或新 Cache 正文的证据。编译检查报告继续保留 `compiled_unverified`，正式发布验证不会因本文自动提升。

## 复验

冻结 checkout 后安装锁定依赖、准备锁定运行时，从完整输入计划逐包构建，不复用其它 host 身份的产物。正式入口：

```sh
pnpm --filter @karuyomi/runtime-host build
SOURCE_PROBE_ALLOWED_HOSTS=cuutruyen.net,hetcuutruyen.net,storage-bravo.cuutruyen.net,storage-charlie.cuutruyen.net \
SOURCE_PROBE_IMAGES=1 \
SOURCE_PROBE_EVIDENCE=.local/cuutruyen-online.json \
node apps/api/test/source-metadata-probe.ts BUILD/manifest.json BUILD/artifacts
```

多 Source 包通过 `SOURCE_PROBE_SOURCE_ID` 指定清单内的准确 ID；本次 MangaDex 使用英文 ID。用内置浏览器点击 `Run real metadata operations`。探针只记录 header/Cookie 名称、图片 host 和处理 fragment 的计数，不保存 token、Cookie 值或 DRM key。原始报告、构建日志与本次扩展观测入口留在冻结工作树 ignored `.local/p0c/`，文档只保留可复验身份、必要结果与未通过门。
