# TypeScript 源码边界

项目原有的 18 份自有 JS/MJS 入口已迁移为 TypeScript：

- scripts 下的格式化、Flutter、协议常量生成与静态资源组装。
- runtime-host 的构建、材料 catalog 与命令入口。
- 五个项目运行时桥：crypto、zstd、graphics、cache、file。
- 扩展完整性与浏览器验证工具，以及 Source / workerd 集成测试入口。

Node 工具由固定 Node 24.15.0 的原生类型擦除直接执行；工具配置启用 erasableSyntaxOnly，不依赖额外 TS loader。工具共享正式 manifest 类型、HTTP/文件边界类型与真实依赖的声明。产品宿主和桥由 esbuild 编译成浏览器 JavaScript，桥单独使用 WebWorker 类型环境。

```sh
pnpm typecheck
pnpm test:extension-integrity
pnpm --filter @karuyomi/runtime-host build
```

总类型检查包含工作区产品源码、tsconfig.tools.json、runtime/teavm/bridge/tsconfig.json 和真实浏览器回归的专用配置。迁移不使用 any、ts-nocheck 或关闭严格检查；浏览器测试模板仍输出合法 JavaScript。

Zstd 的生成 glue 改为锁定的 npm 依赖；原型无需旧版本兼容，已删除冻结 JS 桥副本。当前仓库不维护独立 JS 源文件；生成的 JS 资源、依赖、AOT 和临时测试输出留在忽略目录。GitHub 的语言统计可能晚于提交刷新。

TS 的静态类型不会自动保护 Dart 消息边界。当前仍由 TS Zod schema、Dart 解析及协议常量提供分项保护；跨语言单一 schema/IDL 和 Protobuf 双端生成尚属讨论方向，并未在这次语言迁移中实施。
