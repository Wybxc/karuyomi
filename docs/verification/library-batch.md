# 书架批量操作验证

2026-11-06，本轮按功能完整性优先，接入正式书架多选、批量添加/移出分类和移出书架。继续使用已有单漫画权威 API，设计与停止/恢复语义见[批量操作设计](../design/library-batch.md)。以下客户端测试使用受控业务 supplier，不是独立浏览器、Native、生产 Access 或真机证据。

## 数据边界

新增 `library_snapshot_mutation_test.dart` 10 项通过，完整数据测试 82 项通过。

- 精确模式必须提供合法的已确认 revision；同会话在确认清单后推进的进度不能替旧书架提高 CAS。
- 新批次不隐式重发旧 favorite/progress 操作；旧精确操作不能被不同正文、revision 或非精确入口替换。
- 丢失移出 ACK 后重试原 UUID/正文，只执行一次；不覆写 Source 元数据，保留分类、resume、章节进度和书签。
- ACK 后因新目录补读书架失败仍保留原请求身份；错误的 revision、favorite 或分类 ACK 不算成功，原请求仍可恢复。

组件 supplier 原先对无 metadata 的 `SetFavorite` 无条件覆盖元数据，本轮修正为只在字段存在时替换，和正式 Worker 保持一致。没有修改服务端 API 或业务语义。

## 执行与正式 UI

执行层 `library_batch_test.dart` 6 项已通过，覆盖响应在途暂停、同客户端 wrapper 恢复、过期调用方的迟到 ACK、替换批次拒绝、目录/漫画冻结 CAS 冲突、分类集合操作，以及只在已尝试项全部确认后结束余项。静态检查无问题。正式书架页面新增 6 项组合回归全部通过；和原分类页面（含新增旧 pending 退出回归）集中运行共 21 项通过。覆盖以下路径：

- 当前可见全选/取消只处理可见作品，搜索、筛选和排序保留隐藏选择；确认窗口列完整目标与来源。
- 分类逐漫画取并集或差集；尚未发送项目不冒充已确认，原关联已经满足目标也取得对应 ACK。
- 暂停等待当前请求结算；会话过期后的迟到 ACK 不续发下一项。没有未确认项时，可以结束未发送余项。
- 首失败停止，只有原失败项精确重试，确认后明确继续余项；同客户端 wrapper 重建及窗口关闭后可恢复批次。
- 目录或漫画冲突只读刷新后结束旧批次，不抬 CAS；旧窗口永久失效，不能关闭新路由或污染新身份。
- 系统返回在等待 ACK 时不关闭，成功后与“完成”共用关闭出口，清除已确认选择；单项分类遇另一项未确认写入时可只读结束当前编辑，不重发或丢弃原请求。

## 集中工程检查

- `pnpm format` 与完整 `pnpm format:check` 通过，覆盖全部项目自有语言和结构化配置。
- `pnpm check` 完整通过：生成一致性、portable 格式、类型与依赖层级检查、372 项 Vitest、协议 golden 及全部工具回归通过。
- `pnpm flutter:check` 完整通过：reader_core 21、source_runtime 42、客户端 318 项；三个项目静态分析无问题。
- `pnpm build` 通过：正式 Web/Native runtime 资源、Flutter Web 和 Worker/Static Assets 构建成功。这没有构建或运行新的 iOS/Android App，也不作为设备验收。

本轮详细临时输出保留在忽略的 `.local/library-batch-*.log`，不将机器日志提交到文档或源码。

## 可复验入口与验收范围

```sh
cd apps/reader
flutter test test/data/library_snapshot_mutation_test.dart
flutter test test/library/library_batch_test.dart test/library/library_batch_page_test.dart
```

使用仓库固定的 Flutter SDK。完整工程入口为 `pnpm format`、`pnpm format:check`、`pnpm check`、`pnpm flutter:check` 和 `pnpm build`；集中检查只证明对应代码、组件与构建层级，不自动提升平台验收。

仍待两个独立客户端在真实 D1 下验证批量读回、部分提交、断网/丢响应恢复和并发冲突；Web/iOS/Android、生产 Access、设备交互与真机门分别记录。服务端单漫画原子性沿用既有 [D1 状态](server-state.md)和[分类数据证据](category-state-data.md)，本轮没有新增跨漫画事务。

后续核对发现正式 `SetFavorite` 合同无条件要求 metadata，上一里程碑的受控客户端通过没有覆盖无 metadata 移出被拒绝的路径。2026-11-06 已修复合同并补充独立真实 Worker/D1 回归，保留元数据、分类、resume、进度和书签等语义的结果见[章节状态记录](chapter-read-state.md#协议与真实-d1)。
