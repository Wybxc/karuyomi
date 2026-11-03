# Web 数据库资源构建

2026-11-04。正式构建模块 `tools/reader/database-assets.ts` 为 Flutter Web 开发与 release 准备同一套官方 Drift 2.35.3 资源；项目不维护改写版 worker 或 WASM。

## 固定资源与入口

| 官方资源                                                                                            |  字节数 | SHA-256                                                            |
| --------------------------------------------------------------------------------------------------- | ------: | ------------------------------------------------------------------ |
| [sqlite3.wasm](https://github.com/simolus3/drift/releases/download/drift-2.35.3/sqlite3.wasm)       | 758,619 | `efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37` |
| [drift_worker.js](https://github.com/simolus3/drift/releases/download/drift-2.35.3/drift_worker.js) | 361,829 | `a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a` |

两文件均已通过正常 TLS 从以上官方 URL 实际下载并核对大小与摘要。默认下载缓存是忽略的 `.local/database-assets/drift-2.35.3/`，验证后生成到忽略的 `apps/reader/web/database/`。`ReaderDatabase.open()` 使用 `/database/sqlite3.wasm` 与 `/database/drift_worker.js`。

```sh
pnpm test:reader-assets
pnpm typecheck:tools
FLUTTER_ROOT=/tmp/karuyomi-flutter-sdk node scripts/flutter.ts build
node scripts/assemble-assets.ts
```

`scripts/flutter.ts` 的 build / run 分支在启动 Flutter 前准备资源，开发服务与 release 输出共用同一固定身份；最终 `scripts/assemble-assets.ts` 再校验实际发布文件。`dist/public/_headers` 为 WASM 设置 `application/wasm`，为 worker 设置 `application/javascript; charset=utf-8`，两者均设置 `nosniff` 和 `public, max-age=0, must-revalidate`，避免未改名的版本路径长期使用过期内容。

## 已执行回归与边界

Node 24.15.0 下四项正式回归和严格工具类型检查通过：缺失或同大小错误摘要的文件被拒绝；坏缓存下载不能覆盖现有 served 文件；下载非零退出会清理 partial / 临时目录；非普通缓存文件在下载前失败。测试用本地可执行 fixture 模拟错误下载，不访问网络；官方下载验证单独执行。

Flutter 3.47.5 / Dart 3.13.4 的正式 Web release 构建成功，随后正式组装输出 57 个文件，Native runtime 正文排除检查通过。`dist/public/database/` 的两文件大小与摘要均匹配上表，实际 `_headers` 包含上述 MIME 与缓存规则。日志保留在忽略的 `.local/reader-database-assets/{flutter-web-build,assemble-assets}.log`。

此次组装使用空扩展索引和既有 materials `fba63bcd9b2a194131eb76a500c2e8f046d987b4650d510d6b6f5205bf32a9e8`，只证明资源组装；没有将正在修改的 host 与旧 AOT 混合验证。最终 Flutter 输出包含服务切换时的待保存进度交接修复，`apps/reader/build/web/main.dart.js` 为 3,604,355 B，SHA-256 为 `80841b2a969e053ee0cf7c75a99ec1f9f278285a93a34b9a5e0e60029198eae7`。正式 Source / 产品运行需绑定各自固定构建另验。

资源构建不证明浏览器实际打开数据库、刷新后恢复或 Native 应用持久化。数据文件关闭重开的测试见[本地进度底座](local-progress.md)，Native 平台打包边界见[依赖验证](native-dependencies.md)。

2026-11-04，真实 Flutter Web 与原版 Source 已通过连续切章、关标签页重开后的章节/当前页/最远页/顺序恢复，见[Web 产品进度记录](reader-progress-web.md)；浏览器进程退出与 Native 应用重启仍待验收。
