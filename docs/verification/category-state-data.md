# 分类协议与服务端数据层

2026-11-05，本地 macOS、Node 24.15.0、Flutter 3.47.5 / Dart 3.13.4。本记录证明分类协议、D1 API 与 Dart 数据层；分类管理 UI 和实际双客户端分类验收尚未完成。

## 已通过

- `pnpm test:protocol`：10 项通过，新增目录 mutation、目录响应及关联消息参加 TS→Dart→TS / Dart→TS→Dart codec 检查。
- `apps/api/test/state-workerd.test.ts`：真实 workerd/D1 共 15 项通过。新增分类用例覆盖目录 CAS、改名/排序、漫画双 CAS、目录顺序投影、跨 mutation kind 的 UUID 冲突、删除与关联/进度交错、失败回滚、身份隔离及分页版本失效。迁移由固定 Drizzle Kit 生成。
- Flutter `test/data`：47 项通过，其中新增分类测试覆盖精确 mutation/body 重试、独立队列、旧 ACK 后读回、删除不复活、关联双 CAS、目录与书架一致快照、分页和身份结束。数据层静态分析通过。

目录最多 64 项，分类 ID 为 UUIDv4，名称按 Unicode/UTF-8 预算校验并允许同名。漫画关系仅在 D1 关系表保存；删除在同一事务内提升实时受影响漫画的列与 JSON revision，保留收藏、阅读位置及进度 epoch。取消收藏保留分类关联。

## 未完成

下一步接入管理分类、排序、全部/未分类/分类筛选及漫画多选关联界面。界面必须保留对话框打开时的目录/漫画 revision，冲突后不能自动提高 CAS 并覆盖另一端修改。随后使用两个实际客户端验收双向读回；组件客户端和 D1 并发测试不能代替这一步。
