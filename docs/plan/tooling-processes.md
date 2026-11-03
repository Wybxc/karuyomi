# 脚本执行器与公共工具收敛

## 目标与状态

状态：**已验收**。`tools/lib/` 已删除，调用点直接使用成熟库；进程、归档、状态锁与完整工程检查通过，证据见 [VERIFICATION](../VERIFICATION.md#执行器与第三方库直接接入)。项目保留自己的构建、清单、预算和发布语义。入口仍为严格 TypeScript，依赖方向仍是 `scripts → tools/领域 → 第三方库 / Node 标准库`，产品代码不导入工具层。跨语言协议实施与此任务并行，互不增加兼容层。

本计划对应 2026-11-03 用户要求：规划并实施 zx/execa 迁移，同时查找 `tools/lib` 可替代的成熟库。执行契约见 [TOOLING](../TOOLING.md)，工程总计划见[工程与发布](engineering-and-release.md)。

## 选型

| 方案        | 适合的工作                                                    | 在本项目的决定                                                       |
| ----------- | ------------------------------------------------------------- | -------------------------------------------------------------------- |
| execa       | 明确的可执行文件与 argv、类型化输出、流式日志、超时与进程取消 | 作为自有自动化的统一执行器，精确锁定 `10.2.1`                        |
| zx          | 大量 shell 管道、重定向、现有 shell 工作流转成 TS             | 当前没有必须依赖 shell 的调用，不新增 zx；未来出现实际需求时单独评估 |
| Node 标准库 | 文件、流、哈希和少量 OS 测试探针                              | 直接使用，不为简单原语重复增加依赖                                   |

现有 Gradle、Maven、Java、Git、Flutter、Dart、Wrangler 调用均已是 argv 数组，迁移 execa 能删除重复进程事件和错误处理。zx 支持 TypeScript 与参数转义，但其 shell 编排能力当前没有对应收益。[zx 官方说明](https://google.github.io/zx/getting-started)、[execa 执行 API](https://github.com/sindresorhus/execa/blob/v10.2.1/docs/api.md)。

## 分层与调用约定

- 删除 `tools/lib/*.ts` 及只服务于通用包装的测试；各调用点直接导入第三方库。使用上游类型、结果和错误，不再维护通用进程 Promise、配置转发模块或自定义 `CommandError`。
- 普通工具直接用 `execa(file, args, options)`，显式传入 `cwd`。Node 子工具使用当前 `process.execPath`，Java/Flutter 使用已锁定 SDK 路径。默认不启动 shell，不自动改变可执行文件查找顺序。
- 调用点显式选择终端继承、短文本采集或两路输出写同一文件。长构建不缓存日志；短文本必须有 `maxBuffer`。标准输出仍是协议数据，诊断不能混入其中。
- Flutter 开发入口继承终端 stdin，检查/构建默认关闭 stdin；需要同步结果的格式检查、Git 发现可用 `execaSync`，网络、构建与发布使用异步执行。
- 已过滤的子进程环境必须配合 `extendEnv: false`，防止库默认合并重新带入 GitHub/Cloudflare 凭据。部署凭据仍只进入可信部署阶段。
- 保留原始结尾换行和二进制 stdin/stdout；Git `-z`、Dart protoc 插件及跨语言 NDJSON 不依赖自动 trim。需要 trim 的文本由具体调用方显式处理。
- 不加入全局重试或统一短超时；每个操作保留自己的预算。长时 AOT 不能因常规 CLI 默认值被截断或自动重试。

execa 可将输出直接交给终端、文件或流；实现应选对应输出模式，而不是先收集完整字符串再写日志。[官方输出文档](https://github.com/sindresorhus/execa/blob/v10.2.1/docs/output.md)。

## 迁移清单

| 范围                              | 改造                                    | 必须保留的行为                                                 |
| --------------------------------- | --------------------------------------- | -------------------------------------------------------------- |
| `tools/lib/io.ts`                 | 删除模块；TeaVM/扩展直接用 execa        | 日志流式落盘、非零退出/ENOENT、明确 env、采集限额              |
| `scripts/flutter.ts`、`format.ts` | 删除重复 run 封装，直接配置 execa       | SDK 固定、顺序检查、开发终端交互、全部语言格式门               |
| `scripts/check-cloudflare.ts`     | 替换自写捕获/超时/终止                  | 512 KiB 合并输出预算、脱敏、上传完全停止后清理、独立清理预算   |
| `tools/extensions/catalog.ts`     | 用 `execaSync` 查询 Git                 | 同样的固定 checkout、32 MiB 输出上限和 trim 语义               |
| `registration.ts`                 | 用 execa 执行已锁定 Wrangler            | stdout 严格 JSON、stderr 分离、非零退出失败、D1 事务与显式目标 |
| `pipeline.ts`                     | 用 execa 管理 builder 与材料采集        | 有界增量、checkpoint、锁、原子候选和进程树终止顺序             |
| `tools/protocol/`                 | 官方生成器与 golden runner 直接用 execa | protoc 二进制透传、NDJSON 隔离、正常 ESM 编译                  |
| 工具测试启动器                    | 普通命令迁移 execa                      | 真实 OS 后代/信号测试可保留必要的原生探针，并说明用途          |
| API/Source loopback 验证入口      | 直接使用异步 execa                      | D1 迁移顺序、受限输出、JSON/换行和异步失败断言                 |

正式 `workerd-probe.ts` 与 `source-metadata-probe.ts` 的普通子进程同样采用 execa。workerd 的真实 Static Assets/D1 注册、冲突回滚和策略同步回归，以及 Source 入口的隔离 D1 注册、protocol 2 测试 bootstrap 和静态快照启动均已通过；这轮执行器验证使用显式测试 bundle，不作为原 Source 在线或生产 Access 证据。原始报告留在忽略的 `.local/execa-probes/`。

## AOT 取消与状态锁

顶层 supervisor 负责整棵 builder 树，内层 Maven/JVM 不另建隔离进程组。收到 SIGINT/SIGTERM 或丢失锁后，停止派发，终止活动进程树，等待进程与输出关闭，再处理失败记录和锁释放。正常 builder 退出后也必须清理残留后代。execa 的最终 Promise 还会等待管道关闭，因此 supervisor 必须先观察直接子进程的 exit，再清理继承日志管道的后代，最后等待 execa 收尾；不能先等待最终 Promise 才开始清理。execa 的 `killDescendants` 与取消机制作为通用实现基础；`gracefulCancel` 只适用于协作的 Node 子进程，不能直接当作 JVM/Gradle 的优雅停止协议。[官方终止文档](https://github.com/sindresorhus/execa/blob/v10.2.1/docs/termination.md)。

正在运行的 `022d828` 本地全量仍使用冻结目录，不修改其脚本、依赖和 checkpoint。新代码仅用于后续固定输入的运行。工具/锁变化进入新的 host 指纹；不把旧批次结果当作新工具链验证。

## tools/lib 第三方库审查

| 能力                                  | 采用方案                                                              | 保留的项目代码                                             |
| ------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------- |
| 进程执行、输出和取消                  | execa / get-stream                                                    | 输出模式与预算、AOT supervisor 状态/锁顺序                 |
| 确定性 JSON                           | `json-stable-stringify`                                               | 转 UTF-8 Buffer、拒绝无 JSON 表示的根值；删除递归序列化器  |
| 原子 JSON/checkpoint 写入             | `write-file-atomic`                                                   | 建父目录、确定性 JSON 与末尾换行；库负责替换与临时文件清理 |
| 大 SDK ZIP 解包                       | 已安装的 yauzl 3.4 原生 `openPromise/eachEntry/openReadStreamPromise` | 顺序流式解包、去顶层目录、上游可执行权限                   |
| ZIP 成员路径检查                      | yauzl `validateFileName`                                              | 调用点附上项目错误上下文                                   |
| 小 JAR ZIP 读写                       | 已使用 fflate                                                         | 固定压缩参数与时间戳                                       |
| tar 解包                              | 已使用 tar                                                            | 精确 seed 成员集合、重复/链接校验                          |
| 锁和有限并发                          | 已使用 proper-lockfile / p-limit                                      | checkpoint 和包任务调度语义                                |
| 文件读取、SHA-256、目录枚举、记录收窄 | Node 标准库与 is-plain-obj                                            | 元数据大小上限、确定性顺序；无需为一行原语增加库           |

稳定 JSON 采用库的默认 UTF-16 字典序。新 host 输入使用新身份，不保留旧 Unicode 排序兼容实现。不会为了“全部用库”引入第二套 ZIP 实现或取消清单/资源预算校验。[稳定 JSON 库](https://github.com/ljharb/json-stable-stringify)、[原子写入库](https://github.com/npm/write-file-atomic)、[yauzl API](https://github.com/thejoshwolfe/yauzl#openpromisepath-options)。

Wrangler 合并输出用 get-stream 按总字节计 512 KiB；不能将 execa 的 buffer.all 误当作独立的第三路缓存，溢出后必须先停止上传树再清理。

补丁应用直接使用 diff；源码与输出 SHA-256 仍按上游 pin 校验。调用点直接使用库，公共工具模块不迁移到新目录继续维护。

## 提交顺序与验收

1. 删除公共包装并直接使用库，运行真实 argv/Unicode/环境隔离/采集溢出/日志测试和归档、checkpoint 回归。
2. 开发工具与注册命令迁移，验证全量格式、Flutter 检查、生成器一致性和真实本地 D1；不为执行器重构重复操作线上资源。
3. AOT 流水线迁移，真实后代进程分别接受 SIGINT/SIGTERM、忽略 TERM 被强杀、正常父进程退出仍有后代、锁被占用/丢失均应通过；锁释放后不得仍有构建写入。
4. 严格类型检查、dependency-cruiser、项目完整检查和构建通过后，更新本计划与验证记录，及时提交推送；真实 prek hook 必须运行。

完成标准：`tools/lib/` 全部删除，且没有仅换目录的通用包装；正式 scripts/tools 不再自行封装 child_process 事件来完成已有库能力；无 shell 字符串拼接、无无界输出缓存、无凭据继承倒退、无 AOT 后代泄漏；临时证据只进入 ignored 目录。编译和执行器回归不代表真实 Source/Native 图片或生产 Access 已验收。
