# 章节书签验证

2026-11-06，章节书签从 `business.proto`、D1 到正式 Flutter 详情和阅读页面接入。本文分别记录工程/组件证据与真实客户端门，不把模拟 supplier、编译或单进程组件当成独立客户端同步验收。

## 已实现行为

- 章节列表标记/移除、仅书签筛选，以及阅读当前章的同一控制；Source 章节身份保持现有稳定键，不用标题或旧序号匹配。
- 独立 64 项分页集合与当前章布尔读取；D1 复用作品 CAS、账户 revision 和原子幂等 batch。未收藏作品也可标记，取消收藏与重置阅读保留书签。
- 只在服务端 ACK 后更新图标；未确认操作固定 UUID/正文/CAS，仅显式重试。完整只读刷新不会重发旧操作；冲突后重新读取，旧幂等 ACK 不覆盖当前撤销结果。
- 阅读进度造成的本会话已确认 revision 变化可安全采用；远端变化仍冲突。身份变化、页面关闭和迟到结果与新页面隔离。

## 可复验入口与证据范围

```sh
pnpm generate:check
pnpm check
pnpm flutter:check
pnpm build
```

官方 workerd/D1 状态测试新增书签的保留语义、并发 CAS、旧 ACK、身份隔离、分页与 batch 回滚。Dart 数据测试和正式页面组件测试使用真实业务 client/repository 加受控 API supplier，检查确认、重试、冲突、身份及详情/阅读入口；该 supplier 不是在线 Source 或生产 Access。

## 本轮检查结果

完整 `pnpm check` 通过：365 项 Vitest、协议 golden 和工具回归全部通过，154 个模块 / 498 条依赖无违规。官方 workerd/D1 状态测试共 19 项通过，contracts 5 项通过；它们包含在上述工程检查中，不重复累加为额外在线证据。

`pnpm flutter:check` 三项目静态分析通过，测试分别为 21 / 42 / 269 项；新增 11 项书签数据回归和 11 项控制器/控件/正式导航回归。正式导航覆盖详情标记→仅书签筛选→进入阅读→移除当前章书签→返回详情自动刷新为空。该用例由官方 Flutter widget 测试和受控 Source/API supplier 驱动，不是独立客户端或真实 Source 验收。

全库 `pnpm format`、`pnpm format:check` 和最终 `pnpm build` 通过；正式输出包含宿主、Native 内置材料、Flutter Web release 与 API。运行日志留在忽略的 `.local/bookmarks/`，不提交临时服务或机器输出。

## 尚待验收

- 两个独立客户端的标记→第二端读回→第二端移除→第一端重新读取，以及重启、自动前台刷新和真实丢响应恢复。
- Web/iOS/Android 的实际平台组合、Source 在线阅读期间的书签，以及生产 Access、真机与触控。

实现与边界见[章节书签设计](../design/bookmarks.md)，当前交付顺序见 [P2](../plan/p2-sync.md)。
