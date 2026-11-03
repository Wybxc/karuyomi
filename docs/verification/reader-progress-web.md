# Web 真实 Source 阅读与进度恢复

2026-11-04，Codex 内置浏览器 Chromium 156，真实 Flutter Web release、官方 Drift 2.35.3 WASM/worker、原版 Arknights Comics 1.6.2。产品界面通过隔离 workerd/D1 与 RS256 测试身份访问真实 Source；本次身份不是生产 Access 登录。

## 固定输入与复验

Source 宿主与 AOT 固定 `b6b5f47`，共享 materials 为 `9eb2f18fff6e404078a3b8ef9f83aac882ba8dad5066bc971d556d9c88115706`，扩展指纹为 `f84adfbf3b83d33ef45bdc0284c76718e47e1b4399a1efa274467f0bbfea56de`。Flutter 输出来自随后实现的正式进度接线，`main.dart.js` 为 3,604,355 B，SHA-256 为 `80841b2a969e053ee0cf7c75a99ec1f9f278285a93a34b9a5e0e60029198eae7`；运行前复制到冻结验证目录，未混入仍在开发的文字宿主。

复验先固定提交准备同版宿主与扩展，再构建客户端。使用[正式 Source 集成入口](../../apps/api/test/source-metadata-probe.md)：

```sh
SOURCE_PROBE_PORT=53325 \
SOURCE_PROBE_ALLOWED_HOSTS=arknights.global,webusstatic.yo-star.com \
SOURCE_PROBE_READER_DIR=PATH_TO_FROZEN_FLUTTER_WEB \
node apps/api/test/source-metadata-probe.ts \
  PATH_TO_ARKNIGHTS/manifest.json PATH_TO_ARKNIGHTS/artifacts
```

在输出的根页面使用正常的浏览、扩展与 Source 选择、漫画详情和 Reader 控件；独立元数据门位于 `/probe`。不注入应用内部状态，不直接请求原图 URL。原始请求摘要留在验证树 ignored `.local/p0c/reader-online.json`，不保存 Cookie、JWT 或图片正文。

## 实际通过

- 浏览真实热门列表后打开 `Prelude Suite: The Lone Walker` 的 `DREAM`，正式图片链显示本章 51 页中的真实图片；UI 明确显示本地进度已保存。
- 通过正常翻页与 End 到章尾。导航刚完成时最远页保持旧值，图片显示后才到第 51 页，读完控件才可用。回看至第 48 页时最远仍为第 51 页；回到章尾再点下一章，同一路由进入 `HEARTBEAT` 并能翻页。
- 在 `HEARTBEAT` 第 2 页显示实际第 2、3 页，最远为第 3 页；改为反向来源顺序后等待保存，正常返回详情，继续阅读入口可用。
- 关闭该标签页，创建同 origin 的新标签页，重新通过正式扩展/Source/漫画详情选择继续阅读；恢复 `HEARTBEAT` 第 2 页、最远第 3 页和反向章节顺序，真实图片再次显示，UI 仍报告本地进度已保存。

- 恢复后使用重新阅读本章，当前页与最远页回到第 1 页，真实首页仍能显示并报告保存；没有复用已经关闭的图片会话。

以上与[真实 SQLite 文件关闭重开](local-progress.md)及[组件生命周期回归](reader-continuity.md)互相独立。这里验证关标签页重开，没有关闭整个浏览器进程，也没有验证 Native 应用重启、跨设备同步、物理设备性能或生产 Access 动态请求。现场只观察到章尾后额外的 Source 元数据请求，没有逐会话跟踪，不据此声称测得后台准备的精确会话数量。P0/P1 完整范围继续待验收。
