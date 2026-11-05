# 章节已读状态与范围操作验证

2026-11-06，章节标已读/标未读已从 Protobuf 合同、Worker API、现有 D1 进度表接入正式详情 UI。支持读状态筛选、多选及当前显示顺序的闭区间操作；标记不请求 Source `pages()` 或图片。状态与批次语义见[设计](../design/chapter-read-state.md)。以下区分真实 workerd/D1 回归与受控客户端 supplier；没有新增独立浏览器、Native、生产 Access 或真机证据。

## 协议与真实 D1

`business-state.test.ts` 9 项、官方 Cloudflare Vitest 的 `state-workerd.test.ts` 30 项通过。后者包含本轮新增的 6 项章节状态回归，使用正式 Worker 路由、隔离 D1 和测试 RSA 身份，覆盖：

- 未打开章节可直接标已读或未读，保留独立 epoch，不伪造页面锚；标记不创建 resume 或 Source 元数据。
- 标已读保留已有真实 current/furthest；标未读清除 current/furthest，重新阅读复位到实际首页，两者清除完成状态并提升 epoch。普通保存跨 manifest 保留章级已读状态。
- 收藏、分类、元数据、resume 和书签保留；并发 CAS 只有一个胜者，原 UUID 重试不重复提升 epoch，旧 ACK 不恢复已清除状态。
- 64 项分页包含未读 epoch，固定 account revision，验证身份隔离、游标与快照变化；事务失败回滚进度、revision 和幂等结果，epoch 达上限时明确拒绝。

本轮同时修复上一里程碑的正式合同缺口：`SetFavorite` 无条件要求 metadata，导致批量移出书架的无 metadata 请求在进入 store 前被拒绝。合同现仅在字段存在时校验，新增作品收藏仍由 store 要求可取得合法 metadata。独立真实 Worker/D1 的 `library-removal-worker.test.ts` 1 项通过，核对移出保留元数据、分类、resume、进度和书签，已有元数据可直接重新收藏，缺元数据的新作品收藏仍返回 400。此前 supplier 通过没有覆盖此正式 API 拒绝路径。

新增 `ChapterProgressPageResponse`、显式已读与默认 false 未读、无锚 ACK 和无 metadata 移出的 golden，使用正式 Protobuf-ES / Dart codec 完成双向 ProtoJSON 往返；协议 golden 10 项通过。

## Dart 数据与 Reader

新增 `chapter_read_repository_test.dart` 12 项、完整 `test/data` 94 项及进度/Reader 定向 30 项通过；这些集合存在交集，不相加作为独立测试数。相关静态分析无问题。客户端测试使用受控业务 supplier，覆盖：

- 无锚响应保留 epoch/已读值；Reader 用实际 manifest 首页建立锚，继承已确认状态。远端无锚更新可使旧 Reader 停止写入，用户明确重开后恢复。
- 完整分页遇写入重启，不拼接不同快照；未确认 mutation 经书架或进度读取仍保留，原 UUID、正文及 CAS 精确重试。
- 旧 ACK、错误 revision/章身份/已读值不算确认；未读只清目标章节锚，保留其它业务字段。只有读取成功的完整集合中缺失的章节才视为未读。
- 阅读器自然完成仍要求真实末页观察；详情人工标已读不伪造该观察。

## 正式详情组件

`chapter_read_navigation_test.dart` 7 项通过，目标静态分析、格式与 diff 检查通过。测试经正式应用浏览、详情与标记窗口，使用受控业务 supplier；前六项标记路径将 Source `pages()` 入口设置为失败并核对未被调用，第七项单独等待受控 Source pages 回调，核对旧详情失效后的清理。覆盖以下组合路径：

- 完整读取后缺失记录为未读；已读/未读筛选与书签、搜索取交集。
- 可见选择与反序范围保留重复 URL/标题的独立章节条目、Source 索引和隐藏选择，确认清单包含全部目标。
- 已读/未读不改变 resume；系统返回与完成按钮共用关闭出口，已确认选择清除，未完成选择保留。
- 首失败停止，只精确重试原未确认项，取得 ACK 后明确继续余项；不重复发送已确认项目。
- 旧批次保持原 revision，冲突经只读重取后结束；仓储替换使旧窗口永久失效，迟到 ACK 不续发或串入新身份。
- 同客户端重开详情后章节列表变化，未确认旧项仍使用原 key/正文；结束批次后明确提示不匹配数量，不把旧 key 转入新的章节选择。
- 同一详情 State 的作品参数被替换时，迟到的 Source pages 结果精确关闭旧会话，不打开混用新旧身份的 Reader。

旧进度导航及书架流程与新 UI 合计定向 15 项通过。全库回归发现旧测试在新增控件后直接定位尚未构建的章节，或在滚动后检查已离开构建范围的简介；本轮改为真实滚动及在离开前检查简介，保留原视口和全部业务断言。

## 复验与剩余门槛

仓库根目录执行：

```sh
pnpm exec vitest run packages/contracts/test/business-state.test.ts apps/api/test/state-workerd.test.ts apps/api/test/library-removal-worker.test.ts
```

客户端使用仓库固定 Flutter SDK：

```sh
cd apps/reader
flutter test test/data/chapter_read_repository_test.dart test/reader/reading_progress_controller_test.dart
flutter test test/browse/chapter_read_navigation_test.dart
```

集中工程检查通过：

- `pnpm format` 与完整 `pnpm format:check`，覆盖全部项目自有语言与结构化配置。
- `pnpm check`：生成一致性、portable 格式、严格类型、依赖层级、381 项 Vitest、10 项协议 golden 及全部工具回归。
- `pnpm flutter:check`：reader_core 21、source_runtime 42、客户端 337 项，三个项目静态分析无问题。
- `pnpm build`：正式 Web/Native runtime 资源、Flutter Web 与 Worker/Static Assets 构建成功；本轮没有编译或运行新的 iOS/Android App。

详细临时日志留在忽略的 `.local/chapter-read-*.log`，不提交机器输出。

仍须两个独立客户端在真实 D1 下核对已读/未读读回、Reader 与详情并发、部分提交及丢响应恢复；Web/iOS/Android、实际生命周期、生产 Access 与真机分别验收。本轮工程和组件证据不能提升完整 P1/P2 状态。
