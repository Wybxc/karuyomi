# TypeScript 源码边界

项目自有 JS/MJS 已迁移为严格 TypeScript，当前维护范围包括：

- `scripts/` 的格式化、Flutter、协议生成与领域操作入口。
- runtime-host 的声明式 Vite 配置、专用资源插件、材料 catalog 与宿主。
- 五个产品运行时桥：crypto、zstd、graphics、cache、file；独立图片 codec 候选。
- 扩展构建、静态快照、完整性与网络政策工具。
- Cloudflare 官方 Workers/Test Harness、Vitest Browser 测试和 Vite fixture 配置。

Node 工具由仓库固定 Node 的原生类型擦除执行；工具配置启用 `erasableSyntaxOnly`，不依赖额外 TS loader。工具共享正式 manifest 类型、HTTP/文件边界类型与真实依赖声明。产品宿主、桥与测试浏览器代码由 Vite CLI 读取配置生成 JavaScript；桥使用独立 WebWorker 类型环境。不存在另一个手写构建器或材料读取时的隐式编译。

```sh
pnpm typecheck
pnpm test
BROWSER=none pnpm test:browser
pnpm test:extension-integrity
pnpm --filter @karuyomi/runtime-host build
```

总类型检查覆盖工作区产品、工具、Vite/测试配置、桥及独立候选 codec。迁移不使用 `any`、`@ts-nocheck` 或关闭严格检查。浏览器测试通过官方 Vite/Vitest 机制处理 TypeScript 和专用 Worker；旧模板式浏览器 runner 与 Source/socket 探针已退役。当前测试覆盖与尚未替代的真实 Source/Native 门见 [Vite 计划](plan/vite-build-and-testing.md)。

Zstd 生成 glue 使用精确锁定 npm 依赖。原型不需要旧版本兼容，已删除冻结 JS 桥副本。生成 JS、依赖、AOT 和临时测试输出保留在忽略目录，不作为自有维护源码。GitHub 语言统计可能晚于提交刷新。

TS 静态类型不能自动保护 Dart 消息边界。当前已采用唯一 `.proto` + Buf，通过 Protobuf-ES / Google Dart 插件生成双端模型和 codec，小控制消息使用标准 ProtoJSON；交换边界仍执行运行时解析、版本/大小、requestId/generation 和业务预算校验。生成一致性由 `pnpm generate:check` 检查，TS↔Dart golden 单独验证；图片/HTTP 正文保持有界二进制通道。选型与当前范围见[跨语言设计](design/cross-language-protocol.md)及[协议计划](plan/cross-language-protocol.md)，工程测试不代替浏览器或 Native 执行验收。
