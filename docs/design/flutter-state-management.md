# Flutter 状态与依赖装配

2026-11-12 按用户要求采用 Riverpod generator、flutter_hooks 和 riverpod_lint，集中迁移共享读状态与设置表单。实施与验收见[计划](../plan/post-prototype-flutter-state.md)。原型阶段直接删除旧装配，不维护双轨实现。

## 权威与作用域

Worker API + D1 是唯一业务权威。`BusinessStateClient` 继续负责 UUID、CAS、账户 epoch、串行化、精确重试和未确认草稿；repository 继续负责业务模型。Provider 只共享读取和派生状态，设置 Notifier 执行显式命令。创建、重建、失效和页面重挂载均不能自动提交业务写。

- `confirmedAccountProvider(catalog)` 只在地址和 subject 已确认后暴露仓储，随 Catalog 状态变更失效；已关闭的 Catalog 不再添加监听。
- `libraryViewProvider(repository)` 为书架和来源列表共用一份订阅。列表行从同一快照取得收藏标记，不逐项读取漫画。
- `mangaStateProvider(client, mangaKey)` 共享详情页的单作品状态。
- `settingsControllerProvider(catalog, repository, mangaKey: ...)` 由生成的 Notifier 直接持有不可变 `SettingsState`。全局设置、收藏源和扩展管理共用同一作用域；每个作品的覆盖设置另有作用域。repository 必须进入 family 的键，旧页面捕获的命令不能在 Catalog 换身份后写入新账户。

`SettingsState` 只包含已确认快照、未确认操作、可用/忙碌状态与错误。全局初始值复用 Catalog 已确认的安装设置；作品设置只在尚无快照时读取。全局确认通知会更新继承值，显式 AUTO、false 和 0 仍保留 presence。读流关闭 Riverpod 自动重试，刷新和写入重试均由明确用户动作或既有前台刷新触发。

Access 暂停后，旧作用域保留原账户的未确认操作供检查，禁用写入；同身份恢复仍由业务客户端保留原 UUID 和 CAS。换服务或身份后，界面改用新 repository 的 provider；迟到响应由原业务 epoch 与 Notifier generation 共同隔离。

## 组件与资源生命周期

Hooks 持有可丢弃的输入框、滚动、标签、筛选和本地表单草稿。全局与作品设置共用一套字段控件；未编辑的表单跟随新确认值，已编辑的表单保留打开时的 revision，遇到冲突必须明确重读。表单重建不是保存。

Catalog、Worker、Source、图片页会话和阅读进度仍由原有持有者管理。provider 退订仅取消它创建的读取订阅，不关闭 runtime，不丢弃业务客户端草稿，不替代异步资源关闭确认。Reader 的视口、手势、预取和逐帧状态保留在路由/组件；设置更新不能重置阅读进度。

扩展命令控制器继续负责下载准备、取消和清理等资源操作；它订阅共享设置 provider 并调用其 Notifier，不再创建和释放另一份设置控制器。

## 生成与检查

依赖精确版本写在 reader 的 pubspec 与 lock。所有项目 provider 采用 `@riverpod`；生成文件独立于手写代码计数，使用官方 build_runner 维护：

```sh
pnpm flutter:generate
pnpm flutter:generate:check
pnpm flutter:check
```

生成只覆盖 `apps/reader/lib`，使用 JIT builder，不运行常驻 watch。生成结果提交；一致性检查比较官方生成前后的文件集合和内容，并纳入 Flutter CI。`riverpod_lint` 使用 Dart analyzer plugin，随严格 `analyze --fatal-infos` 运行。

代码量验收以格式化后的生产手写 Dart 为准，计入新增的 provider、排除 `.g.dart` 和已有协议生成文件；测试、文档、依赖与生成物另列，不能靠压缩格式或把业务逻辑挪到生成目录获得削减。
