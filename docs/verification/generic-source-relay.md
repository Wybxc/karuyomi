# 通用 Source 中继与 AOT 设置元数据

2026-11-08：移除 Source 网络登记表、路由、发布工具和客户端门槛。此前英文 xkcd 验收只登记 `xkcd.com`、`imgs.xkcd.com`，中文实现使用 `xkcd.tw`；当时的 Worker 把目标拒绝作为外层 403 返回，旧客户端显示账户无权访问。原始登记和实际部署仍按 [v4 记录](v4-production.md)保留。

- 新 Worker 使用 Access JWT 的已签名主体作为账户身份，不复制 Access 的邮箱/主体准入名单。HTTP bridge 不读取 D1、不要求 build 请求头，对所有扩展使用同一公网 fetch 路径。仍检查分帧、请求类型、字节/时间预算和取消；应用 Access 凭据不复制到上游。
- `pnpm check` 通过：官方 Workers 与 Node Vitest 共 516 项，另有协议双向、AOT 组装/增量、依赖与工具检查。Workers 用受控 upstream 确认未登记域名成功、错误签发对象被拒绝、源站响应仍用分帧传递。正式 Vite 装配及真实 D1 用例验证当前 AOT 设置规则随快照投影、同名外仓不能借用官方规则、未知键不能写入。测试中的真实包名只是样本。
- `pnpm flutter:check` 通过 718 项；`pnpm format` 后 `pnpm format:check` 通过。固定 `c04d436` 的 xkcd v6 单包快照通过 `EXTENSION_ASSETS_DIR=/absolute/path/snapshot pnpm acceptance:build`，实际装配 61 个静态文件、1 个扩展。冻结 AOT 输入与产物未修改。
- 以 `pnpm acceptance:serve` 启动本轮官方本地 HTTP harness，应用真实迁移至 `0010`，使用隔离 D1 和测试签名身份。无需环境变量登记域名；已退役网络政策路由返回 404。另直接向二进制中继发起 `https://xkcd.tw/api/strips.json` 的 GET：外层 200、上游 200，收完整 274,851 字节 JSON。
- Codex 内置浏览器打开正式 Web，从空书架进入扩展管理，准备并安装 xkcd 1.6.1，再在运行时的五个 Source 中选 `xkcd · zh`。热门列表正常显示作品 xkcd（兰德尔·门罗），未出现权限提示。独立 GET 读回账户/全局 revision 为 1/1，仅已安装一项，书架仍空。未打开详情或 Reader，未写收藏或进度。

以上覆盖本地 Worker 与中文热门列表；生产 Access、生产部署和 Native 的这次中继变更仍待验收。四个已审核包的设置规则现在只由新版 AOT 写入清单，未用旧冻结清单冒充重编或把设置回归算成新版真实 Source 设置实测。产物状态仍为 `compiled_unverified` / `runtimeReady=false`。本轮本地记录位于忽略目录 `.local/network-registry-*.log`。
