# Karuyomi 开发指引

## 项目与计划

- 当前是项目原型阶段。所有修改均无需向后兼容；直接维护当前代码、协议、清单和资源，不为旧版本增加兼容分支、回退或迁移层。必要时可以重建本地数据和产物。
- 多端同步是首要设计目标。书架、分类、阅读进度、书签和非敏感设置以 Worker API + D1 为唯一业务权威；客户端保存当前会话内存状态和可丢弃的缓存，收到服务端确认才标记已保存。先完成同一身份在 Web/iOS/Android 间的在线读写与一致性闭环，再扩展外围功能；不先扩展独立本地业务数据库、持久 outbox 或离线合并，再把同步作为后补模块。已加载阅读可在断网时继续，未确认草稿须明确提示，不承诺关闭后恢复。
- P0 优先采用最简单直接、能完成真实端到端流程的实现路径。先验证可用性并取得实测数据，再针对已确认的瓶颈考虑优化；不为假设的性能需求提前引入分片、LOD、多级缓存或额外抽象。必要的限额、取消、生命周期和类型检查仍需落实，不能以“简单”为由省略。
- 在 `docs/plan/` 维护系列计划，以 `docs/plan/README.md` 为统一目录和状态索引；每份计划记录目标、当前状态、待办与验收条件。按索引推进，阶段完成后更新对应计划和目录。`docs/PLAN.md` 是简洁总览，避免在多处复制同一份详细状态。
- 架构依据在持续维护的 `docs/design/`，已有证据和未通过门槛在 `docs/VERIFICATION.md`。设计决策变化时更新设计文档，实现变化时同步计划和证据，不把计划或机制探针写成已完成能力。
- 客户端采用 Flutter/Dart，Source 执行采用 TeaVM JavaScript backend；不重复选型。API 和 Worker 宿主使用 TypeScript。
- 沟通和进度说明使用中文；说明实际完成、验证结果与剩余限制。
- 交互式浏览器操作使用 Codex 内置浏览器，不操作 Safari。内置浏览器不可用时如实报告，不擅自改用其它桌面浏览器；已有验证记录必须保留真实执行环境。
- 可用性的优先级高于安全性，但有两项例外：网络安全在信任普遍安全基础设施的前提下是必要的；不要尝试破坏或绕过类型检查。不要因假设所有基础设施都不可信而添加妨碍可用性的防护，类型错误应通过修正代码或设计解决。

## 安装、构建与检查

- 使用仓库固定的 Node、pnpm、Flutter/Dart 版本：`.node-version`、`package.json`、`.fvmrc` 是版本依据。安装依赖运行 `pnpm install --frozen-lockfile`。
- 安装提交检查：`pnpm hooks:install`；全库手动检查：`pnpm hooks:check`。
- 通用检查：`pnpm check`；Dart/Flutter 检查：`pnpm flutter:check`；完整客户端与 API 构建：`pnpm build`。
- Web/Worker/运行时 JS 构建使用声明式 Vite 配置与官方 CLI；依赖顺序写在包 scripts，项目特有资源合同放在 Vite 插件 hook。不恢复调用 `build()` / `createBuilder()` 的自有构建器或独立资源组装脚本。Flutter 与 Java/TeaVM 工具链继续使用各自正式工具。
- Workers 集成测试使用 Cloudflare 官方 Vitest 插件，生成配置与 Static Assets 使用官方 Wrangler harness；浏览器测试使用官方 Vitest Browser，由 Vite 处理 TS/Worker 入口，不维护手工服务器或浏览器 runner。交互验收使用内置浏览器，preview 配置固定 `BROWSER=none`，防止自动打开默认浏览器。
- TeaVM 工具链、原始 JAR 与 seed 按锁文件准备，入口见 `runtime/teavm/README.md`。准备后运行 `pnpm teavm:check` 验证 Java DTO 与有界 HTTP body。
- `FLUTTER_ROOT` 可指定 Flutter SDK；原生构建和完整原生格式检查需要 macOS/Xcode。

## 代码与格式

- 如果某个功能有成熟的第三方库可用，就直接引入，不要自行实现。固定依赖版本并使用现有包管理方式；直接在调用点导入库，不另建只转发同一功能的通用包装层；`tools/lib/` 已移除，不以换目录的方式恢复。自行编写的代码集中在项目特有的业务逻辑和集成上。
- 所有项目自有代码提交前必须先运行 `pnpm format`，再运行 `pnpm format:check`。范围包括 Java、Dart、TypeScript、JavaScript、Kotlin/Gradle Kotlin DSL、Swift、Objective-C、Ruby、SQL 和结构化配置；现有代码同样适用。
- 使用 pnpm 精确锁定的 prek 管理标准 pre-commit hook，不维护手写 Git hook。检查不自动暂存，部分暂存的工作区处理交给 prek。
- 当前格式工具要求完整 JDK 21+、Flutter 3.47.5 / Dart 3.13.4、Xcode 27.2 的 swift-format 6.4.4 与 clang-format 21.0.0；其余 formatter 的版本和校验固定在 `scripts/format.ts`。首次下载公开 formatter 不需要私有 JVM seed。
- `pnpm check` 在跨平台 CI 使用显式 portable 格式检查；提交前仍须在 macOS 通过完整检查。不要以跳过 hook 或缩小格式范围解决失败。
- 项目自有自动化脚本统一使用 TypeScript；Java 编译器适配/JVM oracle 和平台要求的构建文件保留各自语言。`scripts/` 是调用入口，依赖 `tools/` 领域模块及第三方库，工具不得反向导入入口；TeaVM 工具不得依赖扩展发布编排。依赖层级和验证入口见 `docs/TOOLING.md`，提交必须通过 `pnpm check:dependencies`。
- 自有、可维护的 JS/Node 脚本和运行时桥使用 TypeScript，并纳入严格类型检查。不能只改后缀，也不能用 `any`、`@ts-nocheck` 或宽泛断言掩盖迁移问题；产品桥和宿主实际执行的 JS 由构建生成。测试工具内嵌的浏览器脚本模板必须保持合法 JavaScript，不能直接加入 TS 语法。
- 上游 submodule、生成产物、锁文件和精确上游上下文补丁不作为普通源码重新排版。更新它们时使用对应生成器、包管理器或上游补丁流程。设计文档参与普通 Markdown 格式检查。

## 来源、目录与文档

- 真正的第三方上游通过 Git submodule 固定提交引入，包括 Keiyoushi 扩展源码仓库。研究交付中的项目实现应内化为正式项目源码；不得把研究材料目录伪装成上游仓库。
- 构建依赖通过锁定的包管理器或校验过的工具链获取，不复制依赖缓存或生成的上游代码到维护源码中。
- `tools/ios-resource-probe` 一类临时工程、研究探针、下载、原始 JAR、seed、构建缓存与大产物放在忽略的本地目录，不提交到源码仓库。可复用的正式测试可以内化，但不要整套搬入临时工程。
- 清理散落的 JSON 时，只保留后续开发有用的事实并整理到文档；无用记录删除或忽略。构建输入、协议 schema、锁文件等确属源码的 JSON 保留在相应位置。
- 文档保留可复验命令、必要结论和限制；详细临时日志留在忽略目录，避免将大量机器输出复制入库。
- `docs/design/` 不再冻结；它记录当前设计与决策依据，随用户决策和架构变化更新。保留聊天来源与初次导入记录作为溯源，历史评估要标明背景，不作为禁止修改当前设计的约束。实施状态维护在 `docs/plan/`，实际验证维护在 `docs/VERIFICATION.md`。
- 不修改官方扩展的业务源码或原始 JAR 来掩盖运行问题；适配代码放在项目自有宿主。构建失败按包隔离并记录，不阻断其余包，也不把失败标为可运行。

## 运行时、资源与类型边界

- 共享 runtime materials 作为 Web 静态资源交付，或打包进 Native 应用；不要把共享材料按扩展重复发布，也不要让 Native 通过网络回退读取这些内置资源。
- Static Assets 是所有客户端扩展分发的最终权威来源。每个扩展只部署最新可用构建，由客户端或 Service Worker 检查索引、更新及清理旧缓存；不经 R2 或入口 Worker 转发正文，不在入口 Worker 脚本中内嵌。公开扩展下载不携带 GitHub 凭据或应用 Access 凭据。
- 共享桥、WASM 等构建资源属于 Web Static Assets；Native 按已确定的方案内置。Source 原有请求头、Cookie、拦截器和图片处理语义必须通过正式运行时链路，不能用原图 URL 绕过插件处理。
- 阅读图片交付边界只传插件处理后的不透明编码字节与资源身份（`resourceId/generation/byteLength/url`）。Source 宿主不检查图片 MIME、尺寸或方向，不预解码，也不决定完整图、分片或 LOD；图片识别、解码、尺寸学习、解码预算、缓存与分片由 UI 客户端负责。宿主仍校验传输字节/资源限额、generation 和生命周期；插件原业务主动执行的图片处理继续保留。当前默认使用 Flutter/UI 直接解码；未被产品采用且缺少性能依据的自研分片候选源码和专属工具已删除。先建立真实 UI 基线，针对实测瓶颈优先评估成熟平台或第三方方案；取得同条件目标设备的首屏、跳转、滚动、CPU、RSS/GPU 对照证据后再决定优化，不能以机制可行性代替性能结论。
- Worker TypeScript 与 Dart 的静态类型不能保证跨语言消息安全。交换边界需要统一协议、运行时解析、版本和大小校验，以及 requestId/generation 约束。
- 跨语言协议已选定 Protobuf `.proto` + Buf，使用 Protobuf-ES / Google Dart 插件生成模型和 codec，小控制消息先采用标准 ProtoJSON；具体比较见 `docs/design/cross-language-protocol.md`，实施状态见 `docs/plan/cross-language-protocol.md`。IDL 位于 `protocol/`，双端生成并接入正式控制边界；生成一致性用 `pnpm generate:check` 检查。实际浏览器/原生运行证据须另外验收。业务预算、generation 与资源生命周期仍须校验；图片/HTTP 大正文保持独立二进制通道。Pigeon 适用于 Dart 与原生平台，不代替 TS Worker 协议。
- 大正文与图片使用有界二进制通道，控制消息保持小；落实背压、限额、超时、取消、迟到结果丢弃和资源释放。

## AOT、静态分发与 CI

- 构建扩展 AOT 前先分析包大小优化方案；方案确定后推进实际发布，不让可选研究无限阻塞交付。结论见 `docs/AOT-SIZE.md`。
- 扩展不再发布到 GitHub Release；构建后更新 Static Assets 的当前索引、清单和产物。客户端只以静态索引为准，远端不维护历史扩展版本或回滚目录。运行时 seed 等独立构建依赖不受此规则影响。
- CI 构建状态与客户端索引分开维护，记录上游提交、源码依赖闭包、host/输入指纹及构建结果。只构建输入变化的包；失败保留上次成功版本，同一失败输入不反复重试。缓存仅加速构建，不能代替持久的增量状态和首次 baseline 保护。
- 扩展产物哈希在上传/下载的传输边界验证一次；后续本地处理复用已验证结果，不反复读取并计算同一份字节。增量构建的源码/工具链指纹与传输完整性校验区别对待。
- 初次全量 AOT 只在本地运行，不消耗 CI 构建时长。使用固定提交的独立构建目录和可恢复 checkpoint；开发时不要改变正在运行的构建输入，也不要启动两个发布器并写同一 state。
- CI 跟随上游版本做有界增量更新，缺少已完成本地 baseline 时不得退化为初次全量。通用项目 CI 仅响应分支 push 和 PR，所有 Release tag 均不触发；分支与 PR 检查保持正常。
- 发布和恢复命令以 `docs/EXTENSIONS.md` 为准。格式化、工具链或 host 变更应正确进入新的构建输入身份。

## 提交与验证

- 推进过程中及时按可审阅里程碑提交并推送，不把全部工作积压到最后。提交只包含对应任务变更，不夹带临时输出。
- 按改动运行有意义的类型检查、测试和构建；格式化通过不等于语义正确。移动源码或修改入口后核对所有调用路径与 CI。
- 编译成功、完整性校验、模拟 supplier、浏览器初始化、Source 在线行为、真实 Access 登录、图片阅读和真机性能是不同验证层级。只能报告实际通过的层级。
- 未实测的扩展保持 `compiled_unverified` / `runtimeReady=false`；不能把 AOT 成功当成运行兼容或完整阅读验收。

本文按 [AGENTS.md 开放约定](https://agents.md/) 维护。子目录若有更具体指引，按其范围执行；用户后续明确指示优先于本文。
