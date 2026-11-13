# Cupertino UI 迁移验证

2026-11-13，应用壳、全部业务界面、阅读器、诊断与原生 Access 页面已完成 Cupertino 代码迁移。完整 CI / Web 构建、隔离浏览器和生产验收通过，已由主线自动发布。范围和未验门槛见[迁移计划](../plan/cupertino-ui.md)。原生现场验证继续按用户要求停止。

## 工程与交互回归

使用固定 Flutter 3.50.0 / Dart 3.14.0、Node 24.15.0 与 pnpm 12.6.0。`cupertino_ui: 1.1.6`、`cupertino_icons: 1.0.9` 通过正式 pub get 设为精确直接依赖并更新 reader lock；移除直接 `material_ui` 与 `uses-material-design`。自有 lib、test、integration_test 已无 Material 或旧 SDK Cupertino 导入、Material 图标引用。

`hooks_riverpod`、`flutter_hooks` 与 `flutter_inappwebview` 的传递 Material 导入仍保留。实际集成未要求 MaterialApp/Material Theme，三个项目严格分析及组件回归通过；原生插件现场仍待验，不把依赖扫描当作运行或包体证据。Riverpod generator、Hooks 和 riverpod_lint 保持启用。

单并发检查通过 reader_core 22 项、source_runtime 87 项、reader 633 项，共 **742 项**；三个项目严格分析无问题。Riverpod 与 Protobuf 生成一致性、全范围格式化及格式检查、依赖边界检查通过。回归包括权威读写、CAS 冲突、身份变化、未确认草稿、取消、迟到确认、generation 和资源关闭。普通页面继续遵守减少动态效果及禁用动画的既有策略。

新增选择流程回归覆盖少量菜单选择 null、禁用项、Escape、关闭后焦点返回、Tab/方向键/Enter、360px 下双倍字号的中文搜索，以及搜索页取消与选择的区别；已打开选择页后 owner 被禁用，不得回写。长分类名和忙碌编辑的迟到 ACK 保留原回归。阅读器显式返回汇入既有退出流程；书架、详情及重登恢复入口均等待阅读路由退场后关闭章节。

分类编辑另在 360px × 760px、底部键盘占用 320px 时回归：保存按钮仍位于键盘上方且可命中，中文重命名收到服务端确认后回到分类列表。该项使用 Flutter 视图 inset 模拟，只证明布局及业务交互，不计为真机软键盘验收。

当前缺失组件通过调整流程解决：分类选择当前范围，章节用分段筛选与书签开关，源偏好单选直接选择后等待确认，长选项和迁移章节复用可搜索选择页。多选及复杂编辑保留明确应用/取消和可见操作栏；通知改为持续业务状态。未额外引入第三方 UI 库，也未仿制一套 Material 控件。

可复验入口：

```sh
pnpm flutter:check --concurrency=1 --reporter=expanded
pnpm generate:check
pnpm format
pnpm format:check
pnpm check:dependencies
```

本机只做编辑、生成、分析与单并发测试；完整 Web 编译交给 CI，没有执行 AOT、模拟器或真机验证。原始输出留在 ignored `.local/cupertino-migration/`。

## 代码量

基线 `5352d8f7624a62258e74643e193963e335b8b875`，范围固定为 `apps/reader/lib`、`packages/reader_core/lib`、`packages/source_runtime/lib` 的生产 Dart，排除 `.g.dart` 与 `/src/pb/`，计入所有新增生产组件。正式格式化后由 **30,354 行降至 30,296 行，净减 58 行**。这是本次 UI 迁移的净变化；不将此前重构的削减重复计入，也不宣称已取得包体或性能收益。

删除来源包括重复选择确认层、卡片布局、编辑布局、普通监听装配，以及 43 个 Widget 的字段/构造参数重复声明。新增 `ChoiceField` / `ChoicePage`、`EditSheet` 与无障碍路由策略已计入；业务校验和生命周期约束保留。生成代码、测试与文档单独统计。

## CI、浏览器与生产

`d6c7bdb` 的[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/43353599558)与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43353650403)通过，包含完整工程检查、Flutter 回归与 Web 构建。分支保留的正式 Web/runtime artifact 经官方 Vite 装配，复用 xkcd、Komiic 两份现有扩展，用 Wrangler 官方 harness 的隔离 D1 与 `acceptance-owner` 验收。没有在本机编译 Flutter Web。

Codex 内置浏览器已完成扩展安装的等待/账户确认/本机就绪、停用与重新启用、xkcd 热门列表、详情收藏、Dragonfly 两页真实图片和服务端进度确认。实际验收还发现三处集成问题：release 返回箭头缺字、章节搜索动态清空按钮使输入失焦，以及阅读标题与背景对比度/设置弹层背景及关闭入口遗漏。修复后的同一构建须重新验收，不能沿用旧构建通过的结论。

返回箭头的证据：`cupertino_ui` 1.1.6 的 `_BackChevron` 使用 `Text.rich` 绘制 U+F3CF；Flutter 3.50 默认为该字体保留的是旧 U+F3D2。官方 SDK `font-subset` 对 CI 裁剪字体提取 62415 返回 `Codepoint 62415 not found in font`，对固定 `cupertino_icons` 原字体提取成功。因此采用官方 `--no-tree-shake-icons`，后续须核对新 artifact 和浏览器可见字形。

章节搜索改用官方内置清空按钮；阅读/图片查看导航栏使用独立主题背景；设置复用已有 `EditSheet`，补充常驻保存/关闭及未保存/已确认状态。搜索/范围操作 16 项、阅读器 34 项、设置 19 项和分类 15 项定向回归通过；这些是既有测试的相关子集，不与 742 项重复相加。覆盖标题对比度、页位与资源驻留、设置草稿取消及保存。

### 修复后的隔离浏览器验收

`9273d7806a61575749c15ee5a3ccf77d23d66f85` 的[分支 CI](https://github.com/Wybxc/karuyomi/actions/runs/43360761480)与 [PR CI](https://github.com/Wybxc/karuyomi/actions/runs/43360767332)通过；分支的 `check`、`wasm` 均成功。正式 `web-build-9273d7806a61575749c15ee5a3ccf77d23d66f85` artifact 的字体包含 U+F3CF，官方 `font-subset` 提取成功；返回箭头在浏览器中实际可见。

同一 artifact 经正式 Vite 装配并由官方 harness 提供，隔离 D1 与身份仍为 `acceptance-owner`。在 Codex 内置浏览器分别使用默认 1280px 宽屏和显式 360px × 800px 视口完成：

- 空书架与浏览入口、xkcd 扩展安装/停用/重新启用的服务端确认、真实热门列表及详情收藏。
- 章节连续键入 `Dragonfly` 保持焦点，替换为中文 `蜻蜓` 后显示空结果，官方清空按钮恢复完整章节列表。
- Dragonfly 的两页真实图片、放大/重置、翻页、清晰标题栏与显式返回；退出后可再打开阅读。
- 本漫画设置使用不透明背景和常驻保存/关闭按钮。将背景草稿改为白色后关闭，再打开仍为继承；明确保存后界面显示已确认，并在阅读中生效。
- 独立新文档从书架续读到第 2 页，同时读回白色背景与章节书签。旧文档仍占有 Source 时，新文档先显示明确占用提示；关闭旧文档并连接后恢复正常，没有并行抢占。
- 360px 的底部三入口、中文分类创建及漫画归类、全局主题深色→浅色→跟随系统的确认保存。主题草稿不提前改变应用主题，保存后才生效。

通过独立 HTTP 客户端读取相同 harness 的正式 API，并携带身份绑定头 `X-App-Subject: acceptance-owner`；不提取浏览器 token，不改写 API 或 D1 结果。`/api/library`、`/api/categories`、`/api/settings`、作品设置、进度和书签分别核对收藏、分类关联、白色覆盖、第 2 页及书签为真。最终账户 revision 为 15，全局 revision 为 6 / `APP_THEME_SYSTEM`，作品设置 revision 为 1；分类及主题操作后当前/最远页仍为 `pageIndexHint=1`。日志和完整响应保留于 ignored `.local/cupertino-migration/`，不作为受维护源码提交。

该轮浏览器没有 error/warn 日志，临时视口已恢复，专用验收服务已关闭。测试仍是桌面 Web 视口与 Flutter 组件模拟；没有执行原生设备、物理触屏或真实软键盘验收。

### 生产发布

[PR #5](https://github.com/Wybxc/karuyomi/pull/5) 已合并，主线提交 `f4643e0cb235ccc911795936bbc5691219d52a0a` 的 [CI](https://github.com/Wybxc/karuyomi/actions/runs/43370279052) 全部成功，包括 `check`、`wasm` 和 `deploy`。按既有流程自动发布至 [karuyomi.wybxc.cc](https://karuyomi.wybxc.cc)，复用当前 runtime 与 190 包扩展快照，revision 为 `6bf6597462c449d58b73a48512c9aca2`，没有重做 AOT。扩展清单的 `compiled_unverified/runtimeReady=false` 语义未改变，不将可分发数量当作本轮实际运行覆盖。

同一提交的正式 `web-release` artifact 记录 46 条公开资源的字节、SHA-256 和缓存头核对通过；匿名 API 返回 302 到 Access。验证时间为 `2026-11-13T05:21:40.995Z`。入口实际加载 `main.dart.aced948e.js`，Cupertino 字体哈希为 `67c44fe9183b002e79dde7f6977e2988661c9a3e4a3c5fce968787efdbed823c`。这些自动门与已登录业务验收分别记录。

Codex 内置浏览器使用既有生产 Access 测试账号会话，明确重新加载发布后的页面，完成：

- 宽屏书架的三个入口与 Cupertino 页面，返回箭头及阅读标题均正常显示。
- 从现有书架续读 Dragonfly 第 2 页真实图片，翻到第 1 页再回第 2 页，每次分别等待服务端确认。
- 本漫画阅读背景从“跟随全局”改为白色，先显示未保存，再显式保存并收到确认；退出编辑后白色在真实阅读中生效。随后恢复“跟随全局”并确认保存。
- 显式退出阅读并关闭旧文档后，独立新文档在 360px × 800px 视口直接恢复第 2 页真实图片，读回继承的黑色背景及已保存状态；恢复正常宽屏后标题、图片和控件仍正常。没有重用旧文档内存作为续读证据。

通过 Wrangler 正式只读查询独立核对生产 D1，身份由正式 `/api/bootstrap` 与现有测试账号确认，不提取浏览器 token。上线前 xkcd revision 为 25；两次翻页确认后为 27，最终验收结束为 28，当前/最远位置均为 `pageIndexHint=1`、同一 Dragonfly manifest，当前横向视口锚点为 `viewportX=0.13669143356643354`。全局设置保持 revision 10、`APP_THEME_SYSTEM` 与黑色背景；作品设置 revision 1 为白色，恢复继承后 revision 2、背景覆盖为空，最终独立读回一致。

生产两份文档的浏览器 warn/error 日志均为空，临时视口已恢复，最终显式退出并释放阅读会话。release/verification、D1 查询结果和成功截图保存在 ignored `.local/cupertino-migration/`；详细临时输出不提交。后续仅提交本次证据与状态文档，产品源码及协议不再变化。

本轮 Web 交付通过；没有测量新的包体或性能收益。原生共享代码和 integration_test 的迁移不能代替 iOS/Android 实际运行证据；原生现场、物理触屏、真实软键盘、安全区及系统手势仍待验，按用户要求继续停止，不阻塞本次 Web 上线。
