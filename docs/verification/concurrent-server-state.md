# 双 Web 会话的阅读状态一致性验证

2026-11-05：两个真实 Flutter Web 阅读文档保持打开，在本地真实 workerd/D1 和同一受验签测试身份下，已通过远端位置/epoch 更新时保持旧画面、停止旧视图写入、明确重开采用权威位置，以及未先刷新时正常写路径进入 revision 冲突的分项。业务操作按下表顺序执行，未测试两个写请求同时到达；本记录不代表完整并发、恢复或 P2 验收。

## 输入与边界

- 使用正式 Flutter Web 入口、原版 xkcd 1.6.1、v4 材料及 `3319: Elevators` 两页，扩展、材料与稳定身份沿用[三端配对记录](android-server-state.md)。没有替换 runtime、图片 supplier 或业务数据库。
- 当前文档提交为 `c7b0deb`。`git diff --exit-code 86fc43d -- apps/reader packages/source_runtime packages/reader_core packages/runtime-host apps/api/src protocol` 无差异，正式产品代码与已验证输入相同；测试代理使用 `307a372` 的逐请求真实 RS256 签名，subject 为 `probe-owner`，由正式校验逻辑验证。
- Codex 内置浏览器的 A 为 `http://127.0.0.1:8897`，B 为 `http://localhost:8897`。两条明确的测试 origin 别名连接同一个测试代理、workerd 和隔离 D1；不同 origin 的存储空间避免 Source namespace 执行互斥。它不证明同 origin 多标签可同时执行同一 Source，也不证明生产 Access、Cookie 共享或真实身份切换。
- 两端都通过正式浏览、书架、详情和阅读控制操作；业务状态另经只读 API 确认。详情刷新和正常打开章节会产生业务写入，revision 不等于翻页次数。

## 已通过的实际结果

| 操作                                            | 实际 UI 与服务端结果                                                                                                                                                                                                                                                         |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A 正常浏览、收藏 xkcd，打开指定章节并选择单页   | 第 1 页真实原图显示，UI 确认已保存。`a-initial.json` 为 account/manga revision=3，current/furthest 均为第 1 页、epoch=0。                                                                                                                                                    |
| B 从服务端书架进入详情并继续阅读，再翻到第 2 页 | 第 2 页保存确认后，`b-page-two.json` 为 account/manga revision=6，current/furthest 均为第 2 页、epoch=0。                                                                                                                                                                    |
| A 手动“刷新进度”                                | 仍显示 `1 / 2` 及第 1 页真实图片，明确提示“阅读进度已在其他设备更新，当前阅读位置保持不变。请重新打开本章后继续保存。”；按钮改为“重新打开本章”，“重新阅读本章”和完成操作禁用。                                                                                               |
| A 正常翻到第 2 页，再回到第 1 页                | 阅读仍可继续，冲突提示保持。`a-conflicted-reading.json` 与 `b-page-two.json` 经 `cmp` 逐字节相同，revision 仍为6，current/furthest 仍为第 2 页；旧视图没有覆盖服务端状态。                                                                                                   |
| A 明确“重新打开本章”                            | 首次显示 `2 / 2` 及真实文字图，确认已保存。`a-reopened.json` 为 revision=7、epoch=0、current/furthest 均为第 2 页。                                                                                                                                                          |
| B 刷新、重新打开后“重新阅读本章”                | 刷新先提示“此作品已在其他设备更新”且保持第 2 页；明确重开后再重新阅读，实际显示第 1 页并保存。`b-reset.json` 为 revision=10、epoch=1、current/furthest 均为第 1 页。新 epoch 首图实际显示后已产生观察进度，furthest 不再为空。                                               |
| A 刷新后继续在旧视图翻页                        | 原画面保持 `2 / 2`，提示“本章进度已在其他设备重置，当前阅读位置保持不变。请重新打开本章后继续保存。”；重新阅读和完成禁用。A 回看第 1 页再到第 2 页，警告保持；`a-stale-epoch-reading.json` 与 `b-reset.json` 逐字节相同，revision 仍为10，新 epoch 的第 1 页未被旧视图覆盖。 |
| A 再次明确“重新打开本章”                        | 首次显示 `1 / 2` 并确认已保存。`a-reopened-reset.json` 为 revision=11、epoch=1、current/furthest 均为第 1 页，采用了服务端重置后的状态。                                                                                                                                     |
| B 不先刷新，直接正常翻到第 2 页                 | UI 先显示待服务端确认，节流写路径随后进入“此作品已在其他设备更新，请重新打开本章后继续保存。”状态。画面仍为 `2 / 2`，重新阅读和完成禁用；`b-stale-revision.json` 与 `a-reopened-reset.json` 逐字节相同，revision 仍为11，B 的旧视图未覆盖服务端。                            |
| B 明确“重新打开本章”恢复                        | 首次恢复第 1 页真实原图，UI 确认已保存。关闭两页后独立 `b-final-reopened.json` 为 revision=12、epoch=1、current/furthest 均为第 1 页。                                                                                                                                       |

ProtoJSON 省略的零值按协议解码。前两组逐字节比对证明刷新已发现冲突后，旧视图继续翻页没有产生新的业务写入；它们不单独证明旧请求被发送并拒绝。最后一项单独覆盖未先刷新时的正式写路径冲突及权威状态未变；未取得该请求的精确 HTTP 状态码证据，不将 UI 文案写成已观察到 HTTP 409。实际 API 的 CAS、epoch 与幂等事务测试另见[服务端状态记录](server-state.md)。

## 复验与剩余门

启动同一后端的正式 Flutter 模式见[Source 测试服务](../../apps/api/test/source-metadata-probe.md)。使用同一当前 xkcd 构建和明确的 `xkcd.com,imgs.xkcd.com` 测试网络政策，分别打开上述两个 origin。先等待 A 第 1 页的真实图片与保存确认，再由 B 保存第 2 页；A 刷新前后分别记录页码、提示及只读业务状态。刷新后正常翻页不应提升服务端 revision 或覆盖 B 的位置。恢复前台也可能触发刷新，复验时记录实际触发路径，不以手动操作意图代替观察结果。

只读业务 API 同时携带 `X-App-Request: 1` 和与受验签身份匹配的 `X-App-Subject: probe-owner`，通过 library/state 取得作品与章节键；该 header 仅校验会话绑定，不能选择账户。请求缺少或不匹配 subject 时不能作为有效状态证据。

原始状态、网络和临时日志留在忽略的 `.local/sync-conflicts/`，不提交。必要状态比对命令：

```sh
cmp .local/sync-conflicts/b-page-two.json \
  .local/sync-conflicts/a-conflicted-reading.json
cmp .local/sync-conflicts/b-reset.json \
  .local/sync-conflicts/a-stale-epoch-reading.json
cmp .local/sync-conflicts/a-reopened-reset.json \
  .local/sync-conflicts/b-stale-revision.json
```

两页已关闭，测试服务收到中断后退出；独立进程复核未见该测试代理或 workerd，`8897` 无监听。Miniflare 退出后遗留的本轮临时 D1 与静态快照目录已精确删除，必要 API 状态与网络证据保留在上述忽略目录。

本次记录尚未验收：实际前台自动刷新事件、断网/重连、响应丢失、同时到达的写竞争、Native 生命周期、生产 Access 和真机。分类、书签与同步设置继续按[P2](../plan/p2-sync.md)推进，少量 xkcd 分项不提升其它扩展的运行兼容标记。
