# Mihon 参考截图状态机

2026-11-14，进行中。用户要求截图触及每个 UI 状态，并同时考虑浅色、深色。此表细化[30 组界面矩阵](../design/mihon-cupertino-fidelity.md)，作为参考采集与后续 Cupertino 对照的工作清单。**目前尚无一组完成包含全部转换与变体的双主题验收；绿色只代表该节点的两张主状态参考图已核对。**

## 记录规则

- 状态由固定 Mihon v0.21.3 的页面、ViewModel 分支和弹层分支确定；不能仅按路由名计数。加载、内容、空结果、失败、选择、输入校验、确认和操作进行中分别记录。取消、返回、重试及成功后的落点也是待核对的转换。
- 每行分别记录浅色与深色截图。`待`表示未采集，文件名表示已核对实际 PNG/XML 的参考画面；只完成一侧仍为待完成。表中省略共同路径 `.local/mihon-reference/` 和后缀 `.png`，对应 XML 同名。原始材料保持在忽略目录。
- 图中节点对应表中 ID；橙色表示主图仍缺一侧或必要信息，未着色表示仍待采集，绿色只用于两种主题均已核对的主状态。**参考截图完成不等于 Karuyomi 像素或交互验收通过。**
- DEFAULT 固定主题，360×800 逻辑视口、720×1600 物理像素、320dpi；系统栏单列。两种主题使用同一数据和同一状态。早期 Monet 图保留为历史，不填入 DEFAULT 栏。键盘、长中文、双倍字号、宽屏/横屏、减少动态另列变体，不用它们替代主状态。
- 同一可见状态只保留一个主 ID，可关联多组页面。Mihon 没有的服务端确认、CAS 冲突、身份失效、部分提交、清理 ACK 等状态列在末节，须由 Karuyomi 实测；不能伪造 Mihon 对应图。用户已列入后续的下载、历史、追踪、备份等独立功能保持原范围，不增加无效入口。
- 当新增源码分支或实际操作发现表外弹层，先补节点及转换，再采集；不把“不易触发”改记为不适用。瞬时状态须实际截到才能填表，未截到继续为待。
- 双主题不是黑白反转：分别核对背景、表面、正文、次级文字、分隔、选中、禁用和错误角色，弹层与阅读黑/白/跟随主题画布也分别核对。主题切换须覆盖已确认浅色↔深色、跟随系统的亮度变化、编辑未保存及保存失败；切换后保留当前页面、选择、输入草稿、滚动锚点和阅读页位。显式浅/深设置不受系统亮度变化覆盖，草稿不提前改变全局主题；只有服务端确认才应用新的设置。

## 01–06：导航、书架、分类

依据：`ui/home/HomeScreen.kt`、`ui/library/LibraryTab.kt`、`presentation/library/LibrarySettingsDialog.kt`、`DeleteLibraryMangaDialog.kt`、`presentation/category/CategoryScreen.kt`、`components/CategoryDialogs.kt`。

```mermaid
stateDiagram-v2
    [*] --> N0
    state "01.01 手机底部导航" as N0
    state "01.02 手机横屏底部导航" as N1
    state "01.03 平板侧栏导航" as N2
    state "02.01 书架为空" as L0
    state "02.02 有作品" as L1
    state "02.03 当前分类为空" as L2
    state "03.01 搜索输入" as L3
    state "03.02 搜索有结果" as L4
    state "03.03 搜索无结果" as L5
    state "03.04 筛选面板" as L6
    state "03.05 排序面板" as L7
    state "03.06 显示面板" as L8
    state "03.07 更多菜单" as L9
    state "04.01 多选" as L10
    state "04.02 移出确认未选择" as L11
    state "04.03 多选更多菜单" as L15
    state "04.04 移出确认可提交" as L16
    state "06.01 无分类提示" as L12
    state "06.02 分类选择" as L13
    state "06.03 混合选择" as L14
    state "06.04 混合项移出草稿" as L17
    state "05.01 分类为空" as C0
    state "05.02 分类列表" as C1
    state "05.03 创建空输入" as C2
    state "05.04 创建可提交" as C3
    state "05.05 创建重名错误" as C4
    state "05.06 重命名未修改" as C5
    state "05.07 重命名可提交" as C6
    state "05.08 删除确认" as C7
    state "05.09 重命名空输入" as C8
    state "05.10 重命名重名错误" as C9
    N0 --> N1: 手机旋转横屏
    N1 --> N0: 恢复竖屏
    N0 --> N2: 平板尺寸且自动平板界面
    N2 --> N0: 恢复手机尺寸
    N0 --> L0: 空书架
    N0 --> L1: 有作品书架
    L0 --> L1: 收藏作品
    L1 --> L2: 切到空分类
    L2 --> L1: 切回
    L1 --> L3: 搜索
    L3 --> L4: 匹配
    L3 --> L5: 不匹配
    L4 --> L1: 清空或返回
    L5 --> L1: 清空或返回
    L1 --> L6: 筛选
    L6 --> L7: 排序页签
    L7 --> L8: 显示页签
    L8 --> L1: 收起
    L1 --> L9: 更多
    L1 --> L10: 长按
    L10 --> L1: 取消选择
    L10 --> L15: 更多
    L15 --> L11: 删除
    L15 --> L10: 返回
    L11 --> L16: 选择影响范围
    L16 --> L11: 全部取消
    L11 --> L15: 取消
    L16 --> L15: 取消
    L16 --> L1: 确认
    L10 --> L12: 设置分类且无分类
    L10 --> L13: 设置分类
    L10 --> L14: 设置分类且多作品分类不同
    L13 --> L10: 确认或取消
    L14 --> L17: 点击混合分类使其未选
    L17 --> L10: 取消并丢弃草稿
    L14 --> L10: 确认或取消
    L17 --> L10: 确认移出分类
    L12 --> C0: 编辑分类
    C0 --> C2: 添加
    C1 --> C2: 添加
    C2 --> C3: 输入新名称
    C3 --> C4: 输入已有名称
    C4 --> C3: 修正
    C3 --> C1: 确认
    C2 --> C0: 取消
    C1 --> C5: 编辑
    C5 --> C6: 修改名称
    C5 --> C8: 清空名称
    C8 --> C6: 输入有效名称
    C6 --> C9: 改为重名
    C9 --> C6: 修正
    C6 --> C1: 确认或取消
    C1 --> C7: 删除
    C7 --> C1: 确认或取消
    C1 --> C0: 删除最后一项
    classDef partial fill:#fff0ce,color:#412e00,stroke:#b07a00
    classDef paired fill:#d9f4de,color:#14351d,stroke:#2b7a3d
    class N0,N1,N2,L0,L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,C0,C1,C2,C3,C4,C5,C6,C7,C8,C9 paired
```

| 状态 ID | 最小必要信息/采集触发                                                                          | 浅色                                                                                                                              | 深色                                                                                                                         |
| ------- | ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| 01.01   | 三入口对应的 Mihon 底部导航：书架/浏览/更多的活动入口、图标、标题及正文边界                    | `s0202-library-content-light`、`s0702-source-list-light`、`s0101-more-light`                                                      | `s0202-library-content-dark`、`s0702-source-list-dark`、`s0101-more-dark`                                                    |
| 01.02   | 手机横屏仍为底部导航，书架/浏览/更多分别采集；800×360dp                                        | `s0102-{library,browse,more}-landscape-light`                                                                                     | `s0102-{library,browse,more}-landscape-dark`                                                                                 |
| 01.03   | 自动平板界面的侧栏、当前入口与正文边界；768×1024dp                                             | `s0103-{library,browse,more}-tablet-light`                                                                                        | `s0103-{library,browse,more}-tablet-dark`                                                                                    |
| 02.01   | 空书架标题、原因、入门指南；移出最后一部测试作品                                               | `s0201-library-empty-light`                                                                                                       | `s0201-library-empty-dark`                                                                                                   |
| 02.02   | 封面、标题、未读标记、续读位置及网格边界                                                       | `s0202-library-content-light`                                                                                                     | `s0202-library-content-dark`                                                                                                 |
| 02.03   | 空分类名、空态及切回入口；切到新建分类                                                         | `s0203-library-category-empty-light`                                                                                              | `s0203-library-category-empty-dark`                                                                                          |
| 03.01   | 已打开的搜索框、查询、清空/退出；点搜索                                                        | `s0301-library-search-light`                                                                                                      | `s0301-library-search-dark`                                                                                                  |
| 03.02   | 查询与匹配作品；输入 `xkcd`                                                                    | `s0302-library-match-light`                                                                                                       | `s0302-library-match-dark`                                                                                                   |
| 03.03   | 查询、无结果说明、清空/退出；输入不会匹配的文本                                                | `s0303-library-no-results-light`                                                                                                  | `s0303-library-no-results-dark`                                                                                              |
| 03.04   | 筛选页签、选项及三态当前值；打开筛选                                                           | `s0304-library-filter-light`                                                                                                      | `s0304-library-filter-dark`                                                                                                  |
| 03.05   | 排序页签、当前排序和方向                                                                       | `s0305-library-sort-light`                                                                                                        | `s0305-library-sort-dark`                                                                                                    |
| 03.06   | 显示页签、当前网格/列表设置                                                                    | `s0306-library-display-light`                                                                                                     | `s0306-library-display-dark`                                                                                                 |
| 03.07   | 可用菜单项及正文锚点；点更多                                                                   | `s0307-library-more-light`                                                                                                        | `s0307-library-more-dark`                                                                                                    |
| 04.01   | 选中数量、选中封面、退出/全选和底部批量操作                                                    | `s0401-library-selection-light`                                                                                                   | `s0401-library-selection-dark`                                                                                               |
| 04.02   | 移出确认初态：影响范围选项均未选、确认禁用、取消                                               | `s0402-library-remove-confirm-light`                                                                                              | `s0402-library-remove-confirm-dark`                                                                                          |
| 04.03   | 多选中的迁移/删除菜单、当前选择上下文及关闭                                                    | `s0403-library-selection-more-light`                                                                                              | `s0403-library-selection-more-dark`                                                                                          |
| 04.04   | 仅选移出书架、确认可用；浅色确认后为空书架；深色取消后返回迁移/删除菜单                        | `s0404-library-remove-enabled-light`                                                                                              | `s0404-library-remove-enabled-dark`、`s0404-library-remove-cancel-dark`                                                      |
| 05.01   | 无分类说明及添加入口                                                                           | `s0501-category-empty-light`                                                                                                      | `category-manager-default-dark`                                                                                              |
| 05.02   | 名称、拖动顺序、编辑和删除入口                                                                 | `s0502-categories-two-light`                                                                                                      | `s0502-categories-two-dark`                                                                                                  |
| 05.03   | 标题、空名称、必填、禁用提交、取消及键盘                                                       | `s0503-category-create-keyboard-light`                                                                                            | `s0503-category-create-empty-dark`                                                                                           |
| 05.04   | 名称、可用提交、取消及键盘                                                                     | `s0504-category-create-keyboard-light`                                                                                            | `s0504-category-create-keyboard-dark`                                                                                        |
| 05.05   | 创建时重复名称、错误说明、禁用添加及键盘                                                       | `s0505-category-create-duplicate-light`                                                                                           | `s0505-category-create-duplicate-dark`                                                                                       |
| 05.06   | 原名称、禁用确认、取消及键盘                                                                   | `s0506-category-rename-second-light`                                                                                              | `s0506-category-rename-second-dark`                                                                                          |
| 05.07   | 修改后名称、可用确认、取消及键盘                                                               | `s0507-category-rename-valid-light`                                                                                               | `s0507-category-rename-valid-dark`                                                                                           |
| 05.08   | 待删分类名、影响、取消和确认                                                                   | `s0508-category-delete-second-light`                                                                                              | `s0508-category-delete-second-dark`                                                                                          |
| 05.09   | 重命名清空名称、必填、禁用确认和键盘                                                           | `s0509-category-rename-empty-light`                                                                                               | `s0509-category-rename-empty-dark`                                                                                           |
| 05.10   | 重命名为另一现有分类、重名错误、禁用确认和键盘                                                 | `s0505-category-rename-duplicate-light`                                                                                           | `s0505-category-rename-duplicate-dark`                                                                                       |
| 06.01   | 无分类说明及编辑分类入口                                                                       | `s0601-no-category-dialog-light`                                                                                                  | `library-categories-default-dark`                                                                                            |
| 06.02   | 分类名、已选项、取消和确认                                                                     | `s0602-library-category-choice-light`                                                                                             | `s0602-library-category-choice-dark`                                                                                         |
| 06.03   | 两部作品跨分类选中，a 部分选中、b 未选；取消后保持多选，重开仍混合；未修改混合项的直接确认仍待 | `s0603-library-categories-current-light`、`s0603-library-categories-cancel-light`、`s0603-library-categories-reopen-light`        | `s0603-library-categories-reopen-dark`、`s0603-library-categories-cancel-dark`                                               |
| 06.04   | 点击混合 a 后变为未选；双主题确认后 a 为空、默认分类含两部作品，随后分别恢复原分类             | `s0604-library-categories-none-current-light`、`s0604-library-categories-applied-light`、`s0604-library-categories-default-light` | `s0604-library-categories-none-draft-dark`、`s0604-library-categories-applied-dark`、`s0604-library-categories-default-dark` |

01 已实看 `navigation-more-pairs.jpg`、`navigation-landscape-pairs.jpg` 与 `navigation-tablet-pairs.jpg`。手机横屏仍是底部导航，不将可用宽度 800dp 当作自动平板条件；宽屏参考另在同一模拟器设为 1536×2048/320dpi，得到 768×1024dp 的侧栏。平板的三入口布局锚点一致，手机横屏浏览页的列表滚动位置不同，只用于导航分项，排除正文同位置叠图。两种尺寸的“更多”首屏不能展示所有行，完整设置目录仍独立采集。尺寸和旋转已恢复为 720×1600/320dpi 与原 `free`，加速度旋转仍为 1。

06 新图及确认后落点已实看 `categories-transition-pairs-0.jpg` 至 `categories-transition-pairs-2.jpg`。移出草稿确认后退出多选，a 显示真实空态，默认分类包含 One Piece/xkcd；再只选择 One Piece 设回 a，核对默认仅 xkcd、a 仅 One Piece，b 保持空。新的双主题弹层边界一致；早期浅色图的系统底栏边界不同，弹层纵坐标相差 8 物理像素，因此用同轮 `current-light` 与深色主图比较。浅深空态的随机表情不同，不作为字形叠图锚点。先前的取消丢弃草稿证据继续保留，未修改混合值直接确认仍是转换缺口。

## 07–11：漫画源、扩展、仓库与存储

依据：`presentation/browse/SourcesScreen.kt`、`SourcesFilterScreen.kt`、`ExtensionsScreen.kt`、`ExtensionFilterScreen.kt`、`ExtensionDetailsScreen.kt`、`extension/model/InstallStep.kt`、`presentation/more/settings/screen/browse/components/ExtensionStores*.kt`、`SettingsDataScreen.kt`。

```mermaid
stateDiagram-v2
    [*] --> S0
    state "07.01 漫画源加载" as S0
    state "07.02 漫画源列表" as S1
    state "07.03 无可用漫画源" as S2
    state "07.04 置顶与语言分组" as S3
    state "07.05 语言筛选" as S4
    state "07.06 源操作弹层" as S5
    state "08.01 扩展加载" as E0
    state "08.02 扩展空态" as E1
    state "08.03 扩展分组列表" as E2
    state "08.04 搜索无结果" as E3
    state "08.05 扩展语言筛选" as E4
    state "08.06 未信任提示" as E5
    state "08.13 其他未加载原因" as E12
    state "08.14 加载失败诊断" as E13
    state "08.15 安装权限缺失横幅" as E14
    state "08.07 下载等待" as E6
    state "08.08 下载中" as E7
    state "08.09 安装中" as E8
    state "08.10 安装失败重试" as E9
    state "08.11 更多菜单" as E10
    state "08.12 筛选目录为空" as E11
    state "09.01 扩展详情与源开关" as D0
    state "09.02 内容警告" as D1
    state "09.03 卸载确认" as D2
    state "09.04 来源关闭并排至末尾" as D3
    state "10.01 仓库空态" as R0
    state "10.02 地址输入" as R1
    state "10.03 地址错误" as R2
    state "10.04 添加加载" as R3
    state "10.05 仓库列表" as R4
    state "10.06 移除确认" as R5
    state "10.07 仓库操作错误" as R6
    state "11.01 存储摘要" as T0
    state "11.03 清理结果反馈" as T2
    state "11.04 清理失败提示" as T3
    S0 --> S1: 已加载
    S0 --> S2: 无可用源
    S1 --> S3: 置顶或取消置顶
    S1 --> S4: 语言筛选
    S4 --> S1: 修改或返回
    S1 --> S5: 源操作
    S5 --> S1: 取消
    S2 --> E0: 管理扩展
    E0 --> E1: 无扩展
    E0 --> E2: 有扩展
    E2 --> E3: 搜索无匹配
    E3 --> E2: 清空
    E2 --> E4: 筛选
    E4 --> E2: 修改或返回
    E10 --> E11: 无仓库目录时筛选
    E11 --> E2: 返回
    E2 --> E5: 点未信任项目
    E5 --> E2: 信任或返回取消
    E5 --> D2: 卸载
    E2 --> E12: 点其他未加载项目
    E2 --> E13: 点加载失败项目
    E12 --> E2: 关闭
    E13 --> E2: 关闭
    E12 --> D2: 卸载
    E13 --> D2: 卸载
    E2 --> E14: 缺少系统安装权限
    E14 --> E2: 授权后返回（待验）
    E2 --> E6: 安装或更新
    E6 --> E7: 开始下载
    E7 --> E8: 下载完成
    E8 --> E2: 安装完成
    E7 --> E9: 失败
    E8 --> E9: 失败
    E9 --> E6: 重试
    E2 --> E10: 更多
    E2 --> D0: 点已安装项目
    D0 --> D1: 警告说明
    D1 --> D0: 关闭
    D0 --> D3: 关闭来源并重新排序
    D3 --> D0: 重新启用后回启用分组
    D0 --> D2: 卸载
    D2 --> E2: 确认
    D2 --> D0: 取消
    D2 --> E2: 从未加载提示打开后取消
    E10 --> R0: 无仓库
    R0 --> R1: 添加
    R4 --> R1: 添加
    R1 --> R2: 无效输入
    R2 --> R1: 修正
    R1 --> R3: 提交
    R3 --> R4: 成功
    R3 --> R6: 失败
    R6 --> R1: 重试
    R4 --> R5: 移除
    R5 --> R4: 确认或取消
    R5 --> R0: 移除最后一个
    T0 --> T2: 直接清理成功
    T0 --> T3: 直接清理失败
    T2 --> T0: 反馈结束
    T3 --> T0: 反馈结束后可重试
    classDef partial fill:#fff0ce,color:#412e00,stroke:#b07a00
    classDef paired fill:#d9f4de,color:#14351d,stroke:#2b7a3d
    class E2 partial
    class S1,S3,S4,S5,E3,E5,E10,E11,E14,D0,D1,D2,D3,R0,R1,R2,R3,R4,R5,T0,T2 paired
```

| 状态 ID | 最小必要信息/采集触发                                                                            | 浅色                                                                                                       | 深色                                                                                                    |
| ------- | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| 07.01   | 漫画源标题及加载指示；冷启动进入源页                                                             | 待                                                                                                         | 待                                                                                                      |
| 07.02   | 源名、语言、最近使用、可执行尾部操作                                                             | `s0702-source-list-light`                                                                                  | `s0702-source-list-dark`                                                                                |
| 07.03   | 无可用源说明与扩展入口；关闭已安装源                                                             | 待                                                                                                         | 待（Local source 项与真正空态分开）                                                                     |
| 07.04   | Mihon 置顶分组与普通分组、取消置顶入口；对照 Karuyomi 收藏分组                                   | `s0704-source-pinned-light`                                                                                | `s0704-source-pinned-dark`                                                                              |
| 07.05   | 语言列表及当前启用项；两侧只启用多语言/English                                                   | `s0705-source-language-light`（上段）；下段待补                                                            | `s0705-source-language-dark`（上段）；下段待补                                                          |
| 07.06   | 当前源及置顶/隐藏等可用动作                                                                      | `s0706-source-actions-light`                                                                               | `s0706-source-actions-dark`                                                                             |
| 08.01   | 标题、加载状态及禁用刷新；重新读取目录                                                           | 待                                                                                                         | 待                                                                                                      |
| 08.02   | 无扩展原因与仓库入口                                                                             | 待                                                                                                         | 待                                                                                                      |
| 08.03   | 未加载/已安装/可安装/更新分组、名称、语言、版本、主操作；更新仍待                                | `s0803-extensions-installed-light`、`s0803-extension-catalog-light`、`s0803-extensions-untrusted-light`    | `s0803-extensions-installed-dark`、`s0803-extension-catalog-dark`、`s0803-extensions-untrusted-dark`    |
| 08.04   | 查询、无匹配说明、清空/返回；清空后恢复列表                                                      | `s0804-extension-empty-light`；恢复 `s0804-extension-clear-light`                                          | `s0804-extension-empty-dark`；恢复 `s0804-extension-clear-dark`                                         |
| 08.05   | 语言和内容筛选当前值                                                                             | `s0805-extension-filter-light`；启用语言与深色不同，待对齐重拍                                             | `s0805-extension-filter-dark`；待同条件重拍                                                             |
| 08.06   | 未信任风险、信任/卸载与返回取消；取消仍未加载，浅色已确认恢复原信任，深色确认转换待              | `s0806-extension-trust-light`、`s0806-extension-trust-cancel-light`、`s0806-extension-trusted-light`       | `s0806-extension-trust-dark`、`s0806-extension-trust-cancel-dark`                                       |
| 08.07   | 对象、等待标记、取消                                                                             | 待                                                                                                         | 待                                                                                                      |
| 08.08   | 对象、下载标记、进度/取消                                                                        | 待                                                                                                         | 待                                                                                                      |
| 08.09   | 对象、安装中及系统权限/确认（若出现）                                                            | 待                                                                                                         | 待                                                                                                      |
| 08.10   | 对象、失败与重试                                                                                 | 待                                                                                                         | 待                                                                                                      |
| 08.11   | 筛选和仓库入口                                                                                   | `s0811-extension-menu-light`                                                                               | `s0811-extension-menu-dark`                                                                             |
| 08.12   | 筛选页没有仓库语言目录时的独立空态、标题和返回                                                   | `s0812-extension-filter-empty-light`                                                                       | `s0812-extension-filter-empty-dark`                                                                     |
| 08.13   | Filtered / Unsigned / UnsupportedLibVersion / Malformed 的具体原因、关闭与卸载；每种原因分别待采 | 待                                                                                                         | 待                                                                                                      |
| 08.14   | Failed 的具体错误、等宽简要诊断、复制完整堆栈、关闭与卸载                                        | 待                                                                                                         | 待                                                                                                      |
| 08.15   | Android 安装权限缺失横幅及系统授权入口；本轮未改变安装权限                                       | `s0803-extensions-untrusted-light`                                                                         | `s0803-extensions-untrusted-dark`                                                                       |
| 09.01   | 图标、名称、包名、版本/语言/警告、卸载、来源启用/偏好；恢复后 Afrikaans 回首行                   | `s0901-mangadex-details-light`、`s0901-mangadex-restored-light`                                            | `s0901-mangadex-details-dark`、`s0901-mangadex-restored-dark`                                           |
| 09.02   | 内容警告原因和关闭动作                                                                           | `s0902-extension-warning-light`                                                                            | `s0902-extension-warning-dark`                                                                          |
| 09.03   | 同一 MangaDex 的系统卸载确认和取消；浅色从未信任列表发起，深色从详情发起，确认卸载待             | `s0903-extension-uninstall-light`、`s0903-extension-uninstall-cancel-light`                                | `s0903-extension-uninstall-dark`、`s0903-extension-uninstall-return-dark`                               |
| 09.04   | Afrikaans 关闭后移到末尾、关闭开关与独立偏好入口；重新启用恢复首行                               | `s0901-mangadex-disabled-light`                                                                            | `s0901-mangadex-disabled-dark`                                                                          |
| 10.01   | 无仓库说明、返回、刷新和添加                                                                     | `s1001-repository-empty-light`                                                                             | `s1001-repository-empty-dark`                                                                           |
| 10.02   | 地址、必填、提交可用性、取消、键盘                                                               | `s1002-repository-add-empty-light`、`s1002-repository-add-filled-light`                                    | `s1002-repository-add-empty-dark`、`s1002-repository-add-filled-dark`                                   |
| 10.03   | 提交数字 `987654321` 后的实际 scheme 错误、修正/取消                                             | `s1003-repository-invalid-result-light`                                                                    | `s1003-repository-invalid-result-dark`                                                                  |
| 10.04   | 提交正式公开仓库地址后实际可见的“处理中…”                                                        | `s1004-repository-add-processing-light`                                                                    | `s1004-repository-add-processing-dark`                                                                  |
| 10.05   | 仓库名、地址、移除/刷新；使用正式公开仓库                                                        | `s1005-repository-list-light`                                                                              | `s1005-repository-list-dark`                                                                            |
| 10.06   | 待移除仓库、确认/取消；取消保留列表，确认移除最后一项回空态                                      | `s1006-repository-remove-confirm-light`、`s1006-repository-cancel-light`、`s1006-repository-removed-light` | `s1006-repository-remove-confirm-dark`、`s1006-repository-cancel-dark`、`s1006-repository-removed-dark` |
| 10.07   | 失败原因和可用恢复入口；连接失败分支                                                             | 待                                                                                                         | 待                                                                                                      |
| 11.01   | 占用、存储范围及清理入口；两主题清理前均 165 kB，主图上下两段                                    | `s1101-storage-top-light`、`s1101-storage-usage-light`                                                     | `s1101-storage-top-dark`、`s1101-storage-usage-dark`                                                    |
| 11.03   | 清理后占用与实际反馈；两主题稳定状态均 1.37 kB；浅色删除3文件，深色再次清理删除0文件             | `s1103-storage-cleared-light`、`s1103-storage-clear-feedback-light`                                        | `s1103-storage-cleared-dark`、`s1103-storage-clear-feedback-dark`                                       |
| 11.04   | 清理失败 toast 与保留占用，随后可再次点击清理；不能用成功反馈代替                                | 待                                                                                                         | 待                                                                                                      |

原 11.02“清理确认”是未经调用点核对的假设，现已移除。Mihon 的 `SettingsDataScreen.getDataGroup()` 直接调用 `chapterCache.clear()`，只在完成/失败时显示 toast，没有独立确认框或可见忙碌分支；Karuyomi 的 `ExtensionStoragePage` 同样直接调用 `controller.forget(sha256)`。Karuyomi 的取消 ACK、资源清理失败和身份约束仍须另验，不因此省略。

08.06 仅表示 `Reason.Untrusted` 的风险提示。`Filtered`、`Unsigned`、`UnsupportedLibVersion`、`Malformed` 共用另一种关闭/卸载弹层，`Failed` 还增加等宽错误及复制堆栈，故拆为 08.13/08.14，未采集的原因仍待，不能用信任提示代替。08.15 是 Android 安装权限横幅；本轮未更改该权限，也未完成下载、安装或更新状态。

09.04 的开关关闭后，`ExtensionDetailsViewModel.subscribeToSources()` 按 `!enabled` 排序，将 Afrikaans 移到末尾；两主题都已拍到真正关闭的行，再重新启用回到首行。`s0901-mangadex-disabled-sorted-top-*` 只记录原位置移走，不作为关闭开关主图。09.03 的系统弹层两次均为 Android English 浅色，应用主题不控制其颜色；浅色从未信任列表发起，取消返回列表，深色从详情发起，取消返回详情，底层不同不计同状态像素叠图。`s0903-extension-uninstall-cancel-stale-dark` 的 XML 已返回详情，但 PNG 与确认图完全相同，已排除；另拍并实看稳定 `s0903-extension-uninstall-return-dark`。

11.01 清理前两主题均为 165 kB；浅色清理删除 3 个文件，稳定占用为 1.37 kB，深色再次清理删除 0 个文件，占用保持 1.37 kB。上游明确保留 cache journal，非零值不表示清理失败。反馈图截到 toast 淡入，只用于确认内容，不能作稳定合成色/字形基准；失败反馈仍待。备份/导出等未实现功能只作为本页背景，不扩大本轮产品范围。

## 12–15：源内浏览、筛选、偏好与跨源搜索

依据：`presentation/browse/BrowseSourceScreen.kt` 的 refresh/append Loading/Error/Empty、`ui/browse/source/browse/SourceFilterDialog.kt` 的 typed Filter、`ui/browse/extension/details/SourcePreferencesScreen.kt`、`presentation/browse/GlobalSearchScreen.kt` 的 Loading/Success/Error。

```mermaid
stateDiagram-v2
    [*] --> B0
    state "12.01 首次加载" as B0
    state "12.02 热门作品" as B1
    state "12.03 最新作品" as B2
    state "12.04 搜索输入" as B3
    state "12.05 搜索结果" as B4
    state "12.06 无结果" as B5
    state "12.07 首次失败" as B6
    state "12.08 追加加载" as B7
    state "12.09 追加失败" as B8
    state "13.01 筛选字段" as F0
    state "13.02 已修改草稿" as F1
    state "13.03 排序展开及方向" as F2
    state "13.04 下拉选择展开" as F3
    state "13.05 三态不限制" as F4
    state "13.06 三态包含" as F5
    state "13.07 三态排除" as F6
    state "14.01 偏好列表" as P0
    state "14.02 单项选择" as P1
    state "14.03 多项选择" as P2
    state "14.04 文本编辑" as P3
    state "14.05 多选已修改草稿" as P4
    state "14.06 文本非法" as P5
    state "14.07 文本有效" as P6
    state "15.01 查询及范围" as G0
    state "15.02 各源加载" as G1
    state "15.03 分源成功" as G2
    state "15.04 分源空结果" as G3
    state "15.05 分源失败" as G4
    state "15.06 仅显示有结果" as G5
    B0 --> B1: 成功
    B0 --> B6: 失败
    B6 --> B0: 重试
    B1 --> B2: 最新
    B1 --> B3: 搜索
    B3 --> B0: 提交
    B0 --> B4: 搜索成功
    B0 --> B5: 无结果
    B5 --> B3: 修改查询
    B1 --> B7: 追加
    B4 --> B7: 追加
    B7 --> B1: 成功
    B7 --> B8: 失败
    B8 --> B7: 重试
    B1 --> F0: 筛选
    F0 --> F1: 修改字段
    F1 --> F0: 重置
    F1 --> B0: 应用
    F1 --> B1: 收起不查询并保留草稿
    B1 --> F1: 重开保留的草稿
    F0 --> F2: 展开排序
    F2 --> F2: 同项切换升降序
    F2 --> F1: 选择排序后收起
    F0 --> F3: 打开选择项
    F3 --> F1: 选择新值
    F3 --> F0: 返回不修改
    F0 --> F4: 展开三态组
    F4 --> F5: 包含
    F5 --> F6: 排除
    F6 --> F4: 不限制
    F4 --> F0: 收起组
    F5 --> F1: 收起组
    F6 --> F1: 收起组
    P0 --> P1: 单选
    P0 --> P2: 多选
    P0 --> P3: 编辑文本
    P1 --> P0: 选择或取消
    P2 --> P4: 修改集合
    P2 --> P0: 取消或确认
    P4 --> P0: 确认保存或取消丢弃
    P3 --> P5: 输入非法UUID
    P5 --> P6: 修正
    P6 --> P5: 再次输入非法值
    P6 --> P3: 清空非必填值
    P3 --> P0: 确认空值或取消
    P6 --> P0: 确认保存或取消
    G0 --> G1: 提交查询
    G1 --> G2: 源成功
    G1 --> G3: 源无结果
    G1 --> G4: 源失败
    G4 --> G0: 修改查询或范围
    G2 --> G0: 修改查询或范围
    G2 --> G5: 开启有结果筛选
    G5 --> G2: 关闭有结果筛选
    classDef partial fill:#fff0ce,color:#412e00,stroke:#b07a00
    classDef paired fill:#d9f4de,color:#14351d,stroke:#2b7a3d
    class B0,F0 partial
    class B1,B2,B3,B4,B5,B6,B8,F1,F2,F3,F4,F5,F6,P0,P1,P2,P3,P4,P5,P6,G0,G1,G2,G3,G4,G5 paired
```

| 状态 ID | 最小必要信息/采集触发                                                                          | 浅色                                                                                                                           | 深色                                                                                                                             |
| ------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| 12.01   | 源名、当前模式、加载指示；冷启动、切模式及重试分别记录                                         | `s1203-source-latest-loading-light`（切最新）、`s1201-source-retry-loading-light`（重试）；冷启动图截到路由动画，待补          | `s1201-mangadex-loading-dark`（冷启动）、`s1203-source-latest-loading-dark`（切最新）、`s1201-source-retry-loading-dark`（重试） |
| 12.02   | 源名、热门模式、封面与标题网格                                                                 | `s1202-xkcd-popular-light`、`s1202-mangadex-popular-light`                                                                     | `s1202-xkcd-popular-dark`、`s1202-mangadex-popular-dark`                                                                         |
| 12.03   | 源名、最新模式、作品；真实动态目录内容会变化，不用于同数据叠图                                 | `s1203-source-latest-light`                                                                                                    | `s1203-source-latest-dark`                                                                                                       |
| 12.04   | 空输入和精确查询 `987654321`、键盘、清空和提交                                                 | `s1204-source-search-input-light`、`s1204-source-search-filled-light`                                                          | `s1204-source-search-input-dark`、`s1204-source-search-filled-dark`                                                              |
| 12.05   | 精确查询 `one piece`、匹配作品、清空与返回；键盘已收起                                         | `s1205-mangadex-search-loaded-light`                                                                                           | `s1205-mangadex-search-loaded-dark`                                                                                              |
| 12.06   | 当前查询 `987654321`、无结果说明和恢复动作；主图含键盘                                         | `s1206-source-empty-light`；无键盘/恢复待补                                                                                    | `s1206-source-empty-dark`；无键盘/恢复待补                                                                                       |
| 12.07   | 模拟器断网时首次失败，错误正文、重试/帮助/WebView；离线重试仍失败，联网重试恢复热门            | `s1207-source-network-error-light`、`s1207-source-offline-retry-light`、`s1207-source-recovered-light`                         | `s1207-source-network-error-dark`、`s1207-source-offline-retry-dark`、`s1207-source-recovered-dark`                              |
| 12.08   | 已有作品、追加指示、滚动位置；只有实际可见旋转指示才通过                                       | 待（追加重试帧已为新内容，未截到指示）                                                                                         | 待（慢网/重试帧仍未截到指示）                                                                                                    |
| 12.09   | 追加失败保留已有作品，底部持久错误条、重试；恢复网络后加载更多                                 | `s1209-source-append-error-light`、`s1209-source-append-recovered-light`                                                       | `s1209-source-append-error-dark`、`s1209-source-append-recovered-dark`                                                           |
| 13.01   | text/check/select/tri-state/sort/group 当前值、重置/应用；文本筛选仍需其他真实源               | `s1301-source-filters-light`、`s1301-source-filter-group-light`；text 待                                                       | `s1301-source-filters-dark`、`s1301-source-filter-group-dark`；text 待                                                           |
| 13.02   | group/check/select 草稿，重置、收起重开和实际应用；下述转换另列文件                            | `s1302-source-filter-draft-light`、`s1302-source-filter-reset-light`、`s1304-source-filter-select-draft-light`                 | `s1302-source-filter-draft-dark`、`s1302-source-filter-reset-dark`、`s1304-source-filter-select-draft-dark`                      |
| 13.03   | Sort 展开、默认 Relevance 降序、点同项升序；上下滚动内容                                       | `s1301-source-filter-sort-light`、`s1301-source-filter-sort-lower-light`、`s1303-source-filter-sort-ascending-light`           | `s1301-source-filter-sort-dark`、`s1301-source-filter-sort-lower-dark`、`s1303-source-filter-sort-ascending-dark`                |
| 13.04   | Created within last 下拉展开，Any/Day/Week/Month/Year 和原值                                   | `s1304-source-filter-select-light`                                                                                             | `s1304-source-filter-select-dark`                                                                                                |
| 13.05   | Genre 的 Action 不限制，空框；点击后进入包含                                                   | `s1305-source-filter-tristate-neutral-light`                                                                                   | `s1305-source-filter-tristate-neutral-dark`                                                                                      |
| 13.06   | Action 包含，勾选图形与强调色；点击后进入排除                                                  | `s1305-source-filter-tristate-include-light`                                                                                   | `s1305-source-filter-tristate-include-dark`                                                                                      |
| 13.07   | Action 排除，叉号与强调色；点击后回不限制                                                      | `s1305-source-filter-tristate-exclude-light`、`s1305-source-filter-tristate-reset-light`                                       | `s1305-source-filter-tristate-exclude-dark`、`s1305-source-filter-tristate-reset-dark`                                           |
| 14.01   | MangaDex EN 偏好标题、当前值、说明及开关，上下段均采集                                         | `s1401-source-preferences-light`、`s1401-source-preferences-lower-light`                                                       | `s1401-source-preferences-dark`、`s1401-source-preferences-lower-dark`                                                           |
| 14.02   | Cover quality 字段、Original 当前选中、其他选项、取消；取消后值不变                            | `s1402-source-choice-light`、`s1402-source-choice-cancel-light`                                                                | `s1402-source-choice-dark`、`s1402-source-choice-cancel-dark`                                                                    |
| 14.03   | Filter original languages 多选初态，选项未选、确认/取消                                        | `s1403-source-multiple-light`                                                                                                  | `s1403-source-multiple-dark`                                                                                                     |
| 14.04   | Block groups by UUID 空输入、非必填、确定可用、取消与键盘                                      | `s1404-source-text-empty-light`                                                                                                | `s1404-source-text-empty-dark`                                                                                                   |
| 14.05   | Japanese 已选草稿、确认/取消；取消重开未选，确认重开已选                                       | `s1405-source-multiple-draft-light`、`s1405-source-multiple-cancel-reopen-light`、`s1405-source-multiple-applied-reopen-light` | `s1405-source-multiple-draft-dark`、`s1405-source-multiple-cancel-reopen-dark`、`s1405-source-multiple-applied-reopen-dark`      |
| 14.06   | 文本 `123`，非法 UUID 错误说明、确定禁用、可修正/取消                                          | `s1406-source-text-invalid-light`                                                                                              | `s1406-source-text-invalid-dark`                                                                                                 |
| 14.07   | 有效测试 UUID，错误消失、确定可用；确认后重开仍保留                                            | `s1407-source-text-valid-light`、`s1407-source-text-applied-reopen-light`                                                      | `s1407-source-text-valid-dark`、`s1407-source-text-applied-reopen-dark`                                                          |
| 15.01   | 空输入/查询、已置顶/全部范围、有结果筛选、返回与键盘                                           | `s1501-global-empty-light`、`s1501-global-query-light`                                                                         | `s1501-global-empty-dark`、`s1501-global-query-dark`                                                                             |
| 15.02   | 每源名称与实际旋转指示、总进度；瞬态 PNG 先于 XML，不用后来的 XML 推导该帧位置                 | `s1502-global-naruto-loading-light`                                                                                            | `s1502-global-loading-dark`                                                                                                      |
| 15.03   | 源名/语言与横向封面、封面下三行标题、进入源箭头；深色打开真实 One Piece 详情并返回，浅色转换待 | `s1503-global-top-light`                                                                                                       | `s1503-global-top-dark`、`s1503-global-open-before-dark`、`s1503-global-open-details-dark`、`s1503-global-return-dark`           |
| 15.04   | Local source 无结果；与 MangaDex 成功同屏                                                      | `s1503-global-top-light`                                                                                                       | `s1503-global-top-dark`                                                                                                          |
| 15.05   | 源名/语言、错误图标与说明；无独立重试按钮；混合成功/失败同屏另待                               | `s1505-global-error-light`                                                                                                     | `s1505-global-error-dark`                                                                                                        |
| 15.06   | 有结果筛选选中，只保留 MangaDex 两组；关闭恢复空结果源                                         | `s1503-global-only-results-light`                                                                                              | `s1503-global-only-results-dark`                                                                                                 |

实际转换补充（两种主题均已操作并核对 PNG）：

- MangaDex 筛选勾选 `Has available chapters`，返回收起后热门结果不变，重开仍勾选。证据为 `s1302-source-filter-checkbox-draft-{light,dark}`、`s1302-source-filter-dismissed-{light,dark}`、`s1302-source-filter-dismissed-reopen-{light,dark}`。这是保留未应用草稿，不能写成“取消丢弃”。Karuyomi 的显式取消继续丢弃草稿，作为已确认业务合同的交互差异记录。
- 点击筛选后截到实际加载指示，随后得到 Domino Kick 等真实结果，见 `s1302-source-filter-applying-{light,dark}` 与 `s1302-source-filter-applied-{light,dark}`。浅色瞬态同时截到面板淡出，不能当稳定面板像素基准；两侧等待与结果状态已取得。搜索 `one piece` 的匹配作品在加载完封面、收起键盘后另拍 12.05，不使用早期空封面帧作成对主图。
- 偏好多选的取消/确认后分别重开，检查未选/已选，最后恢复未选。文本编辑用 `00000000-0000-4000-8000-000000000001` 验证，通过确认及重开后清空恢复。完整动作图见同前缀的 `cancel`、`applied`、`reset` 及 `reset-draft` 文件。空值合法且确定可用；错误节点仅由实际非法 UUID 触发。
- 12.07/12.09 仅关闭专用模拟器 Wi-Fi/移动数据触发，真实错误是连接参考代理 `10.0.2.2:7890` 失败。首次失败使用整页错误与三个动作；追加失败保留列表并显示持久错误条，恢复网络重试后继续得到作品。两者均有双主题实际 PNG。错误页表情随机，封面缓存和追加后的滚动位置不同，排除同数据像素叠图；追加加载帧未明确出现旋转指示，12.08 仍待。曾尝试模拟器 2000ms/128kbit/s 网络配置，未据此推断其生效或性能；已恢复 delay none、speed full、Wi-Fi/移动数据启用并暂停模拟器。
- 跨源搜索两主题实际选择“全部”并查询 `one piece`，MangaDex 多语言/English 成功，Local source/xkcd 无结果；有结果筛选开启/关闭已操作。首次进入默认“已置顶”且无可搜源时是空内容区，不误记为加载。浅色真实旋转帧另用 `Naruto` 新查询捕获；`s1502-global-loading-light` 实际无目标、`s1502-global-all-loading-light` 实际为成功布局动画，均排除加载证据。断网后换查询才触发错误，重复提交相同查询没有重发；Mihon 跨源错误没有独立重试按钮，Karuyomi 继续保留单源重试。深色已从全局搜索打开真实 English One Piece 详情，返回后保留查询与结果。成功/失败混合同屏、浅色打开作品、进入源及恢复后再次成功仍是转换缺口。网络已恢复、模拟器已暂停。
- 旧 Android Preference/View 偏好弹层的浅色容器偏蓝，区别于 Mihon Compose 弹层；系统键盘仍按 Android 系统浅色，作为系统变体保留。筛选列表的滚动位置和打开/收起动画存在差异，当前只确认状态覆盖，未计为同位置叠图通过。最新目录两次请求间数据有变化，同样不能用于同数据像素叠图。

## 16–21：作品、章节、封面与迁移

依据：`ui/manga/MangaScreen.kt` 的 Loading/Success/dialog、`presentation/manga/MangaScreen.kt`、`ChapterSettingsDialog.kt`、`components/MangaCoverDialog.kt`、`DuplicateMangaDialog.kt`、`presentation/browse/Migrate*.kt`、`mihon/feature/migration/{config,list,dialog}`。Karuyomi 的只读映射预览是自身状态，不能把 Mihon 迁移选项截图称作映射预览。

```mermaid
stateDiagram-v2
    [*] --> M0
    state "16.01 详情加载" as M0
    state "16.02 未收藏详情" as M1
    state "16.03 已收藏详情" as M2
    state "16.04 简介展开" as M3
    state "16.05 详情或章节加载失败" as M4
    state "16.06 收藏重复提示" as M5
    state "16.07 已有摘要补载详情和章节" as M6
    state "17.01 章节列表" as H0
    state "17.02 无章节" as H1
    state "17.03 章节筛选" as H2
    state "17.04 章节排序" as H3
    state "17.05 章节显示" as H4
    state "17.06 筛选无章节" as H5
    state "17.07 章节选项更多" as H8
    state "18.01 章节多选" as H6
    state "18.02 已读及书签结果" as H7
    state "19.01 封面查看" as V0
    state "19.02 自定义封面操作" as V1
    state "19.03 恢复或替换确认" as V2
    state "20.01 迁移源加载" as Q0
    state "20.02 无待迁移作品" as Q1
    state "20.03 迁移源或作品列表" as Q2
    state "20.04 迁移配置" as Q3
    state "20.05 目标搜索结果" as Q4
    state "20.06 待迁移作品已选" as Q8
    state "20.07 目标源全未选" as Q9
    state "20.08 选源快捷菜单" as Q10
    state "20.09 目标搜索加载" as Q11
    state "20.10 目标搜索无结果" as Q12
    state "20.11 目标搜索失败" as Q13
    state "20.12 目标源内搜索" as Q14
    state "21.01 迁移确认选项" as Q5
    state "21.02 迁移进行中" as Q6
    state "21.03 迁移完成" as Q7
    M0 --> M1: 成功且未收藏
    M0 --> M2: 成功且已收藏
    M0 --> M6: 本地已有摘要且远端未补齐
    M6 --> M1: 补载完成且未收藏
    M6 --> M2: 补载完成且已收藏
    M6 --> M4: 更新失败并保留摘要
    M4 --> M6: 再次刷新并保留摘要
    M1 --> M2: 收藏
    M1 --> M5: 检测到重复
    M1 --> M3: 展开简介
    M2 --> M3: 展开简介
    M3 --> M1: 收起且未收藏
    M3 --> M2: 收起且已收藏
    M5 --> M1: 取消且仍未收藏
    M5 --> Q5: 从重复项发起迁移（待验）
    M1 --> H0: 章节加载成功
    M2 --> H0: 章节加载成功
    M1 --> H1: 没有章节
    H0 --> H2: 筛选
    H2 --> H3: 排序页签
    H3 --> H4: 显示页签
    H4 --> H8: 更多
    H8 --> H4: 返回
    H2 --> H5: 无匹配
    H5 --> H0: 清除筛选
    H0 --> H6: 长按
    H6 --> H7: 已读未读或书签
    H6 --> H0: 取消
    M2 --> V0: 点封面
    V0 --> V1: 自定义操作
    V1 --> V2: 恢复或替换
    V2 --> V0: 确认或取消
    Q0 --> Q1: 无作品
    Q0 --> Q2: 有作品
    Q2 --> Q8: 选择迁移作品
    Q8 --> Q2: 返回并清除选择
    Q8 --> Q3: 继续（转换待验）
    M2 --> Q3: 作品更多菜单迁移
    Q3 --> Q9: 全不选
    Q9 --> Q3: 全选恢复
    Q3 --> Q10: 更多菜单
    Q9 --> Q10: 更多菜单
    Q10 --> Q3: 快捷选择（待验）
    Q10 --> Q9: 返回保留未选
    Q3 --> Q11: 继续并保存选源
    Q9 --> Q11: 继续（待验）
    Q11 --> Q4: 有匹配
    Q11 --> Q12: 无匹配
    Q11 --> Q13: 请求失败
    Q4 --> Q11: 修改查询
    Q12 --> Q11: 修改查询
    Q13 --> Q11: 重新搜索
    Q4 --> Q5: 选择结果
    Q4 --> Q14: 进入单个目标源（待验）
    Q14 --> Q5: 选择结果（待验）
    Q5 --> M1: 显示目标作品
    M1 --> Q4: 从目标作品返回搜索
    Q5 --> Q4: 取消
    Q5 --> Q6: 共存或迁移
    Q6 --> Q7: 完成
    classDef partial fill:#fff0ce,color:#412e00,stroke:#b07a00
    classDef paired fill:#d9f4de,color:#14351d,stroke:#2b7a3d
    class M1,M2,M3,M5,H0,H2,H3,H4,H6,H7,H8,V0,Q2,Q3,Q4,Q5,Q8,Q9,Q10,Q12 paired
```

| 状态 ID | 最小必要信息/采集触发                                                                          | 浅色                                                                                                                           | 深色                                                                                                                       |
| ------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| 16.01   | 本地读取前的全屏加载指示；源码此分支没有独立标题或返回按钮，系统返回另验                       | 待                                                                                                                             | 待                                                                                                                         |
| 16.02   | One Piece / MangaDex ALL 的完整未收藏详情、作者、状态、摘要和添加入口                          | `s1602-one-piece-ready-light`                                                                                                  | `s1602-one-piece-ready-dark`                                                                                               |
| 16.03   | 已在书架状态、分类/续读入口及同一元数据                                                        | `s1603-details-light`                                                                                                          | `s1603-details-dark`                                                                                                       |
| 16.04   | 同一 One Piece 的长简介、完整标签及收起；分首屏与末段，并核对收起后回原详情                    | `s1604-one-piece-expanded-{top,tail}-light`、`s1602-one-piece-ready-light`                                                     | `s1604-one-piece-expanded-{top,tail}-dark`、`s1602-one-piece-ready-dark`                                                   |
| 16.05   | 加载失败保留资料、具体错误与再次刷新入口；元数据/章节失败分别采集                              | 待                                                                                                                             | 待                                                                                                                         |
| 16.06   | 重复作品名称、封面、来源、章节数、仍然添加与取消；两侧取消后目标仍未收藏，查看/迁移/添加转换待 | `s1606-one-piece-duplicate-light`、`s1606-duplicate-cancel-light`                                                              | `s1606-one-piece-duplicate-dark`、`s1606-duplicate-cancel-dark`                                                            |
| 16.07   | 已有摘要时补载元数据/章节，保留摘要并显示更新反馈；早期 XML 的 0 章不能证明稍后 PNG 的加载态   | 待                                                                                                                             | 待                                                                                                                         |
| 17.01   | 同一 xkcd 的章节数量、名称、日期、已读/未读和下载操作；Dragonfly 已读，其余首屏章节未读        | `s1701-chapter-list-light`                                                                                                     | `s1701-chapter-list-dark`                                                                                                  |
| 17.02   | 空章节说明和重新读取入口                                                                       | 待                                                                                                                             | 待                                                                                                                         |
| 17.03   | 筛选页签、未读/书签等三态、翻译组入口                                                          | `s1703-chapter-filter-light`                                                                                                   | `s1703-chapter-filter-dark`                                                                                                |
| 17.04   | 当前排序字段/方向                                                                              | `s1704-chapter-sort-light`                                                                                                     | `s1704-chapter-sort-dark`                                                                                                  |
| 17.05   | 当前显示方式                                                                                   | `s1705-chapter-display-light`                                                                                                  | `s1705-chapter-display-dark`                                                                                               |
| 17.06   | 生效条件、无章节及清除/返回                                                                    | 待                                                                                                                             | 待                                                                                                                         |
| 17.07   | 默认设置/重置菜单及底层上下文；参考附加分支，不据此扩展本轮产品功能                            | `s1707-chapter-options-more-light`                                                                                             | `s1707-chapter-options-more-dark`                                                                                          |
| 18.01   | 选中数量、选中行、退出/全选和底部动作                                                          | `s1801-chapter-selection-light`                                                                                                | `s1801-chapter-selection-dark`                                                                                             |
| 18.02   | 已读/未读/书签三类结果各自可见，不能只凭点击记录                                               | `s1802-chapter-read-light`、`s1802-chapter-unread-light`、`s1802-chapter-bookmarked-light`、`s1802-chapter-unbookmarked-light` | `s1802-chapter-read-dark`、`s1802-chapter-unread-dark`、`s1802-chapter-bookmarked-dark`、`s1802-chapter-unbookmarked-dark` |
| 19.01   | 实际大封面、关闭和操作；旧 `cover-view-default-dark` 不符合                                    | `s1901-cover-light`                                                                                                            | `s1901-cover-dark`                                                                                                         |
| 19.02   | 当前封面、可用自定义/重置动作                                                                  | 待                                                                                                                             | 待                                                                                                                         |
| 19.03   | 替换或恢复对象、影响、确认/取消；系统文件选择单列                                              | 待                                                                                                                             | 待                                                                                                                         |
| 20.01   | 迁移标题和加载指示                                                                             | 待                                                                                                                             | 待                                                                                                                         |
| 20.02   | 无作品说明及返回                                                                               | 待                                                                                                                             | 待                                                                                                                         |
| 20.03   | 源名、语言、书架数量、排序入口及源内未选择作品列表；排序变更与空书架待                         | `s2003-migration-{sources,titles}-light`                                                                                       | `s2003-migration-{sources,titles}-dark`                                                                                    |
| 20.04   | 目标源已选分组、名称/语言、排序把手、全选/全不选与继续；更多菜单入口                           | `s2004-migration-config-light`、`migration-config-restored-light`                                                              | `s2004-migration-config-dark`、`migration-config-restored-dark`                                                            |
| 20.05   | 实际迁移查询 one piece、分源结果与原源标记；主图带键盘，选首个结果后进入21.01                  | `s2005-migration-one-piece-light`                                                                                              | `s2005-migration-one-piece-dark`                                                                                           |
| 20.06   | 待迁移作品的选中行、源名、继续与返回清除选择；继续转换待验                                     | `s2006-migration-selected-light`                                                                                               | `s2006-migration-selected-dark`                                                                                            |
| 20.07   | 全不选后仅显示可选源、无排序把手；参考继续按钮仍可见，全选恢复；未选时继续待验                 | `s2004-migration-none-light`                                                                                                   | `s2004-migration-none-dark`                                                                                                |
| 20.08   | 选择已启用/已置顶源的快捷菜单；返回后保持原选择，快捷选择执行待验                              | `s2004-migration-options-light`                                                                                                | `s2004-migration-options-dark`                                                                                             |
| 20.09   | 实际迁移查询、分源旋转指示、已返回项与搜索进度；不得以15的图替代                               | 待                                                                                                                             | 待                                                                                                                         |
| 20.10   | 实际迁移查询 xkcd、各源无结果及原源标记；改为 one piece 后恢复结果                             | `s2005-migration-search-light`                                                                                                 | `s2005-migration-search-dark`                                                                                              |
| 20.11   | 实际迁移查询、失败源和具体错误、重新搜索；混合成功/失败另列变体                                | 待                                                                                                                             | 待                                                                                                                         |
| 20.12   | 单个目标源内的迁移搜索、查询与原作品上下文；加载/成功/空/失败均待                              | 待                                                                                                                             | 待                                                                                                                         |
| 21.01   | 参考弹层为章节/分类选项及显示作品/共存/迁移；显示作品后实际打开目标并返回；改选、取消和提交待  | `s2101-migration-confirm-light`、`s1602-one-piece-ready-light`                                                                 | `s2101-migration-confirm-dark`、`s1602-one-piece-ready-dark`                                                               |
| 21.02   | 原/目标上下文和进行中反馈、操作禁用                                                            | 待                                                                                                                             | 待                                                                                                                         |
| 21.03   | 目标作品落点、原书架关系及完成后可用操作                                                       | 待                                                                                                                             | 待                                                                                                                         |

16–21 已实看 `migration-reference-pairs-0.jpg` 至 `migration-reference-pairs-3.jpg`、`migration-reference-selected-pairs.jpg`，以及 `manga-reference-pairs-0.jpg` 至 `manga-reference-pairs-2.jpg`。原作品为 xkcd，目标源保持最初三个已选项；先全不选、查看菜单、返回并全选恢复，再继续搜索。xkcd 查询真实返回三源无结果；输入 one piece 得到 MangaDex ALL/EN 的真实作品，选择 ALL 第一项进入数据选择。此操作只查看目标作品，未执行共存或迁移。One Piece ALL 与书架已有 EN 版本触发真实重复提示，两主题均取消，目标保持未收藏。返回书架后原 xkcd/One Piece EN 关系保持；模拟器已暂停。

长简介展开首屏和末段已成对，完整显示正文与标签，再收起回原详情。首个目标详情的 XML 曾为未知作者/0章，而随后同前缀 PNG 已完成元数据和章节加载；该帧不能作为16.01/16.07或17.02的图片证据。早期输入丢字产生的 o ie 查询只留在忽略目录，不填入同条件主图。20.06 的正式成对图包含选中背景与继续按钮；未实际点击此入口进入配置，不能用作品更多菜单的成功转换替代。空书架迁移、冷加载、迁移失败、共存/迁移后的落点和所有修改/取消变体仍待。

以下为两主题稳定 XML 相同的主要矩形，均为720×1600/320dpi的物理像素；仅建立参考锚点，尚未与 Karuyomi 迁移页叠图：

| 元素             | 矩形 (left, top, right, bottom) |
| ---------------- | ------------------------------- |
| One Piece 封面   | (32,296,232,596)                |
| One Piece 标题   | (264,346,460,442)               |
| 未收藏详情章节数 | (32,1060,170,1108)              |
| 迁移数据选择标题 | (88,617,520,687)                |
| 迁移章节选项文字 | (152,747,210,787)               |
| 迁移显示作品动作 | (112,987,226,1027)              |
| 重复作品提示标题 | (48,278,440,360)                |
| 重复作品取消文字 | (327,1408,393,1456)             |

## 22–25：阅读器与图片

依据：`presentation/reader/appbars/ReaderAppBars.kt`、`ReadingModeSelectDialog.kt`、`settings/ReaderSettingsDialog.kt` 的阅读模式/常规/滤镜页签、`ReaderPageActionsDialog.kt`、`ui/reader/ReaderActivity.kt`、`loader/ChapterLoader.kt`、`viewer/pager/{PagerPageHolder,PagerTransitionHolder}.kt` 及 webtoon holder。错误、空章节、首末页和章节间过渡均须实拍；首次章节失败的返回反馈与画布内图片失败不能合并。

```mermaid
stateDiagram-v2
    [*] --> A19
    state "22.01 已知页位的图片加载" as A0
    state "22.02 工具隐藏" as A1
    state "22.03 工具显示" as A2
    state "22.04 图片失败" as A3
    state "22.05 空页面反馈并返回" as A4
    state "22.06 页码跳转" as A5
    state "22.07 有相邻章的过渡" as A6
    state "22.08 首次章失败并返回作品" as A20
    state "22.09 首次阅读载入" as A19
    state "22.10 章节过渡加载" as A21
    state "22.11 章节过渡失败" as A22
    state "22.12 无上一章" as A23
    state "22.13 无下一章" as A24
    state "22.14 工具切章等待弹层" as A25
    state "23.01 阅读模式选择" as A7
    state "23.02 更多操作" as A8
    state "23.03 书签结果" as A9
    state "24.01 阅读模式设置" as A10
    state "24.02 常规设置" as A11
    state "24.03 滤镜设置" as A12
    state "24.04 覆盖与继承结果" as A13
    state "24.05 自定义亮度启用" as A17
    state "24.06 色彩滤镜启用" as A18
    state "25.01 图片操作面板" as A14
    state "25.02 设置封面确认" as A15
    state "25.03 图片缩放或查看" as A16
    A19 --> A1: 首张图片可见
    A19 --> A20: 初始化章节失败并退出阅读器
    A19 --> A4: 页列表为空并退出阅读器
    A20 --> A19: 返回原作品重新点同章
    A4 --> A19: 返回原作品重开章节
    A0 --> A1: 图片可见
    A0 --> A3: 失败
    A3 --> A0: 重试
    A1 --> A2: 中央点击
    A2 --> A1: 中央点击
    A2 --> A5: 拖动页码
    A5 --> A1: 跳转完成
    A1 --> A6: 读至相邻章过渡
    A6 --> A0: 下一章
    A6 --> A21: 相邻章页列表加载
    A21 --> A0: 加载完成
    A21 --> A22: 加载失败
    A22 --> A21: 重试
    A1 --> A23: 已到全书开头
    A1 --> A24: 已到全书末尾
    A2 --> A25: 工具栏切换章节
    A25 --> A1: 载入完成
    A25 --> A2: 失败后回原章（待实测）
    A2 --> A7: 阅读模式
    A2 --> A8: 更多
    A2 --> A9: 书签
    A9 --> A2: 切换完成
    A2 --> A10: 设置
    A10 --> A11: 常规页签
    A11 --> A12: 滤镜页签
    A12 --> A17: 启用自定义亮度
    A17 --> A12: 关闭自定义亮度
    A17 --> A18: 启用色彩滤镜
    A18 --> A17: 关闭色彩滤镜
    A10 --> A13: 修改覆盖或继承
    A13 --> A2: 返回阅读
    A1 --> A14: 长按图片
    A14 --> A15: 设置封面
    A15 --> A14: 取消（已观察返回图片操作）
    A15 --> A1: 确认（落点待实测）
    A1 --> A16: 缩放
    A16 --> A1: 复位或关闭
    classDef partial fill:#fff0ce,color:#412e00,stroke:#b07a00
    classDef paired fill:#d9f4de,color:#14351d,stroke:#2b7a3d
    class A1,A2,A5,A7,A8,A9,A10,A11,A12,A14,A15,A16,A17,A18,A19,A20 paired
```

| 状态 ID | 最小必要信息/采集触发                                                          | 浅色                                                                                                     | 深色                                                                                                  |
| ------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| 22.01   | 已知页位时的图片加载指示与章节/页位上下文；不将首次章载入或无图片的空黑帧替代  | 待                                                                                                       | 待（`reader-loading-default-dark` 实际为 Android 首次全屏提示）                                       |
| 22.02   | 实际图片与页码，工具隐藏                                                       | `s2202-reader-canvas-light`                                                                              | `s2202-reader-canvas-dark`                                                                            |
| 22.03   | 返回、作品/章节、书签/更多、页码与底部工具                                     | `s2203-reader-tools-light`                                                                               | `s2203-reader-tools-dark`                                                                             |
| 22.04   | 失败页、错误和重试；不要把外层全屏提示当图片失败                               | 待                                                                                                       | 待                                                                                                    |
| 22.05   | 初始空页列表错误 toast 并返回作品；不是独立空画布，消息须真实触发              | 待                                                                                                       | 待                                                                                                    |
| 22.06   | 3322 Dragonfly 的当前/总页数、滑杆落点；1→2 的实际第二页图片及返回 1           | `s2206-reader-jump-{before,result,restored}-light`                                                       | `s2206-reader-jump-{before,result,restored}-dark`                                                     |
| 22.07   | 当前章/相邻章、方向和可继续过渡；不含加载/失败及无相邻章分支                   | 待                                                                                                       | 待                                                                                                    |
| 22.08   | 初始章节请求失败，退出阅读器回原作品并显示真实错误；恢复网络后重开同章成功     | `s2208-reader-initial-failure-light-5`、`s2209-reader-retry-light-settled`                               | `s2208-reader-initial-failure-dark-5`、`s2209-reader-retry-dark-settled`                              |
| 22.09   | 首次进入的黑色阅读画布、实际旋转指示；尚无页位工具，读取阶段不由瞬态图推断     | `s2209-reader-retry-light-5`                                                                             | `s2209-reader-retry-dark-5`                                                                           |
| 22.10   | 相邻章过渡保留原/目标章，显示页列表加载指示与说明                              | 待                                                                                                       | 待                                                                                                    |
| 22.11   | 相邻章过渡的实际错误、原/目标章和重试                                          | 待                                                                                                       | 待                                                                                                    |
| 22.12   | 无上一章的边界说明与当前章；不能用普通首页代替                                 | 待                                                                                                       | 待                                                                                                    |
| 22.13   | 无下一章的边界说明与当前章；不能用普通末页代替                                 | 待                                                                                                       | 待                                                                                                    |
| 22.14   | 工具栏切章的不可取消等待弹层、加载指示与说明，和画布内过渡加载区分             | 待                                                                                                       | 待                                                                                                    |
| 23.01   | 当前模式、可选模式、应用及关闭                                                 | `s2301-reader-mode-light`                                                                                | `s2301-reader-mode-dark`                                                                              |
| 23.02   | 当前章节可用操作与关闭                                                         | `s2302-reader-more-light`                                                                                | `s2302-reader-more-dark`                                                                              |
| 23.03   | 已加与已移除两种书签状态、可用反向动作                                         | `s2303-reader-bookmarked-light`、`s2303-reader-unbookmarked-light`                                       | `s2303-reader-bookmarked-dark`、`s2303-reader-unbookmarked-dark`                                      |
| 24.01   | 本作品范围、阅读模式、默认/显式值、输入选项；完整滚动段分项                    | `s2401-reader-settings-light`、`s2401-reader-settings-lower-light`、`s2401-reader-settings-bottom-light` | `s2401-reader-settings-dark`、`s2401-reader-settings-lower-dark`、`s2401-reader-settings-bottom-dark` |
| 24.02   | 常规页签、当前图像适配/显示选项；完整滚动段分项                                | `s2402-reader-settings-light`、`s2402-reader-settings-lower-light`                                       | `s2402-reader-settings-dark`、`s2402-reader-settings-lower-dark`                                      |
| 24.03   | 滤镜页签、亮度/色彩/灰度/反色关闭状态                                          | `s2403-reader-settings-light`                                                                            | `s2403-reader-settings-dark`                                                                          |
| 24.04   | 切换继承/显式设置后实际阅读呈现；两种各一图                                    | 待                                                                                                       | 待                                                                                                    |
| 24.05   | 亮度开关启用、当前数值和滑杆；参考附加分支                                     | `s2405-reader-brightness-enabled-light`                                                                  | `s2405-reader-brightness-enabled-dark`                                                                |
| 24.06   | 色彩开关、RGBA当前值、混合模式、灰度/反色；参考附加分支，RGB等未实现功能列后续 | `s2406-reader-color-filter-enabled-light`、`s2406-reader-color-filter-lower-light`                       | `s2406-reader-color-filter-enabled-dark`、`s2406-reader-color-filter-lower-dark`                      |
| 25.01   | 当前图片上下文、设置封面/保存等真实动作                                        | `s2501-reader-image-actions-light`                                                                       | `s2501-reader-image-actions-dark`                                                                     |
| 25.02   | 设置封面影响、确认/取消；取消返回图片操作面板，确认落点待验                    | `s2502-reader-cover-confirm-light`；取消图 `s2502-reader-cover-cancel-light`                             | `s2502-reader-cover-confirm-dark`                                                                     |
| 25.03   | 双击放大的实际 Dragonfly 图片及再次双击复位；Karuyomi 独立图片页另验           | `s2503-reader-zoom-confirmed-light`、`s2503-reader-zoom-reset-light`                                     | `s2503-reader-zoom-confirmed-dark`、`s2503-reader-zoom-reset-dark`                                    |

阅读新图已实看 `reader-initial-burst-{light,dark}.jpg`、`reader-retry-burst-{light,dark}.jpg`、`reader-jump-pairs.jpg` 和四张 `s2503-reader-zoom-{confirmed,reset}-{light,dark}.png`。同一 xkcd 3322 在专用模拟器断网时实际返回 `Failed to connect to /10.0.2.2:7890`，退出阅读器并由系统显示 toast；恢复网络后重开同章得到真实图片。进入时的旋转指示与阅读模式 toast 同屏，不能把模式提示当作错误。采样帧为先截图的短时连续 PNG，时间记录在同前缀 `.timing.json`，没有同帧 XML；随后 `settled.xml` 只代表稍后的页面。首次章与图片加载复用指示组件，仅凭黑底旋转帧不能证明内部所处阶段，已知页位的 22.01 继续待采。

页码滑杆从 1 拖至 2 后菜单自动隐藏，重开工具后显示页码 2 及真实第二页，再拖回 1；操作前后的稳定主图成对，拖动中的浮动反馈帧仍待。第二页是 Source 提供的文字图片，按原比例显示可能横向裁切，不当作缩放证据。早期无明确双击间隔的 `doubletap` / `zoomed-picture` 图仅切换了工具，均排除；正式 25.03 使用两次触点间 100ms，取得约两倍放大的实际第一张图片及复位。深色主图有完整页码，浅色放大图的页码未显示，工具/计时变体继续单列。两主题沿用黑色阅读背景，图片本身未染色；已读标记因实际阅读改变，失败前的读状态不同不作同数据叠图。未触发空页、单张图片失败或章节过渡分支。Wi-Fi/移动数据已恢复为原启用值，模拟器暂停。

## 26–30：设置、选择与通用弹层

依据：`presentation/more/settings/screen/SettingsMainScreen.kt`、`SettingsAppearanceScreen.kt`、`SettingsReaderScreen.kt`、`SettingsAdvancedScreen.kt`、`debug/DebugInfoScreen.kt`、`WorkerInfoScreen.kt`，以及官方 Preference 对应选择/编辑对话框。通用弹层复用前面已定义状态，不用另一个页面的常态代替。

```mermaid
stateDiagram-v2
    [*] --> U0
    state "26.01 设置目录" as U0
    state "26.02 外观设置" as U1
    state "26.03 全局阅读设置" as U2
    state "26.04 平板设置双栏" as U14
    state "28.01 高级与诊断入口" as U3
    state "28.02 应用与设备诊断" as U4
    state "28.03 Android后台任务诊断" as U12
    state "28.04 系统复制反馈" as U13
    state "29.01 少量单选" as U5
    state "29.02 长列表或搜索选择" as U6
    state "29.03 无匹配选项" as U7
    state "30.01 编辑空输入" as U8
    state "30.02 编辑可提交" as U9
    state "30.03 编辑校验错误" as U10
    state "30.04 确认与取消" as U11
    U0 --> U1: 外观
    U0 --> U14: 平板宽度
    U14 --> U0: 恢复手机宽度
    U14 --> U14: 左侧切换设置分类
    U0 --> U2: 阅读
    U0 --> U3: 高级
    U3 --> U4: 诊断明细
    U4 --> U12: Worker info
    U12 --> U12: 横向滚动正文
    U12 --> U13: 复制
    U13 --> U12: 系统反馈收起
    U12 --> U4: 返回
    U4 --> U3: 返回
    U1 --> U5: 选择
    U2 --> U5: 选择
    U0 --> U6: 长选项
    U6 --> U7: 搜索无匹配
    U7 --> U6: 清空
    U5 --> U2: 取消默认阅读模式且保留原值
    U5 --> U1: 外观调用点返回（待验）
    U6 --> U0: 选择或取消返回原页
    U0 --> U8: 编辑
    U8 --> U9: 有效输入
    U9 --> U10: 无效输入
    U10 --> U9: 修正
    U9 --> U11: 提交确认
    U11 --> U0: 确认或取消
    classDef partial fill:#fff0ce,color:#412e00,stroke:#b07a00
    classDef paired fill:#d9f4de,color:#14351d,stroke:#2b7a3d
    class U13 partial
    class U0,U1,U2,U3,U4,U5,U12,U14 paired
```

| 状态 ID | 最小必要信息/采集触发                                                             | 浅色                                                               | 深色                                                                 |
| ------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------- |
| 26.01   | 设置分类、标题/说明和返回；旧 `settings-main-default-dark` 实际为“更多”           | `s2601-settings-light`                                             | `s2601-settings-dark`                                                |
| 26.02   | 当前浅深模式、DEFAULT 卡、主题选中、显示偏好                                      | `s2602-appearance-light`                                           | `s2602-appearance-dark`                                              |
| 26.03   | 阅读显示/输入分组、当前值和说明；六段滚动主图，详见下文                           | `s2603-reader-preferences-*-light`                                 | `s2603-reader-preferences-*-dark`                                    |
| 26.04   | 平板设置目录/当前分类与外观同屏、当前主题、分栏边界；768×1024dp                   | `nav-settings-tablet-light`                                        | `s2604-settings-tablet-dark`                                         |
| 28.01   | 高级设置首屏、数据/网络、书架和阅读/扩展末段；中段有滚动偏差，未操作维护/网络选项 | `s2801-advanced-{top,network,library,extensions}-light`            | `s2801-advanced-{top,network,library,extensions}-dark`               |
| 28.02   | 调试信息的版本、构建、安装测试ID、编译状态、WebView与设备；上下两段               | `s2802-debug-info-top-light`、`s2802-debug-info-device-light`      | `s2802-debug-info-top-dark`、`s2802-debug-info-device-dark`          |
| 28.03   | Worker info 的 Enqueued/Finished/Running、等宽正文、复制和返回；横向变体          | `s2803-worker-info-light`、`s2804-worker-horizontal-light`         | `s2803-worker-info-dark`、`s2804-worker-horizontal-dark`             |
| 28.04   | 系统复制预览；只能确认已显示的内容，不能由点击推断完整剪贴板校验                  | 待（`s2803-worker-copy-light` 只有空容器，排除）                   | `s2803-worker-copy-dark`（含测试任务ID开头的系统预览；完整内容待验） |
| 29.01   | 默认阅读模式标题、五个选项、当前右到左、取消；取消后原值不变                      | `s2901-reader-mode-choice-light`、`s2901-reader-mode-cancel-light` | `s2901-reader-mode-choice-dark`、`s2901-reader-mode-cancel-dark`     |
| 29.02   | 当前项、可搜索的长选项、搜索/取消和键盘                                           | 待                                                                 | 待（先核对 Mihon 是否采用同样搜索结构）                              |
| 29.03   | 查询、无匹配、清空/取消                                                           | 待                                                                 | 待（若 Mihon 无此界面，记为 Karuyomi 独有并保留源码依据）            |
| 30.01   | 标题、必填/禁用提交、取消、键盘；关联05.03/10.02/14.04                            | 待                                                                 | `category-create-default-dark`（分类分项）                           |
| 30.02   | 当前草稿、可用提交和取消；关联05.04/05.07/14.04                                   | 待                                                                 | `category-ime-default-dark`（分类分项）                              |
| 30.03   | 原输入、具体校验错误、修正/取消；关联05.05/10.03                                  | 待                                                                 | 待                                                                   |
| 30.04   | 对象、影响、确认/取消；逐操作关联04.02/05.08/09.03/10.06/19.03/21.01/25.02        | 待                                                                 | 待                                                                   |

26.03 的 `*` 依次为 `top`、`display`、`paged`、`webtoon`、`navigation`、`actions`，已实看 `settings-reference-pairs-0.jpg` 至 `settings-reference-pairs-2.jpg`。首屏与末段两主题的应用 XML 边界一致；中间四段有约 3–15 物理像素的滚动差，部分首尾文字受裁切，只计状态覆盖，不能用于同位置叠图。六段覆盖默认模式/提示、显示/E-Ink、章节跳过、单页/条漫、输入和操作菜单；未实现的 Android 专属设置及 E-Ink 只作参考，不增加无效产品入口。

26.04 已实看 `settings-tablet-pairs.jpg`：两栏各 384dp，左侧保留完整目录、当前“外观”高亮，右侧展示外观字段。深色多出“纯黑深色模式”一行，后续字段自然下移；不能把整张图强行套成相同纵坐标。恢复手机尺寸后返回独立页面。其它设置分类在双栏中的切换、输入与返回仍待，不能用外观主图代替。

28 和 29 已实看 `settings-reference-pairs-3.jpg` 至 `settings-reference-pairs-5.jpg`，并单独核对 Worker info 横向滚动及深色复制图。28.03 是 Mihon 的 Android WorkManager 诊断，与 Cloudflare Worker 无关；当时仅有一项 Enqueued，Finished/Running 为 `-`，其它运行状态仍待。横向滚动会移动整块正文，标题栏保持位置。28.04 属于独立 Android 系统反馈，不将系统容器配色纳入 Mihon 应用角色；未验证完整复制内容。29.01 本轮只取消，没有改动默认阅读模式；选中其他模式并返回仍待。

28.01 后续补齐 `network`、`library`、`extensions` 三段，已实看 `extension-storage-pairs-5.jpg` / `extension-storage-pairs-6.jpg`。网络/书架中段约有 14 物理像素滚动差，上边缘个别文字受裁切；末段布局一致。未修改 DoH、User Agent、日志保护、数据库清理或文件名设置。仅通过正式“撤销已信任的未知插件”触发参考扩展未加载，完成两主题提示与取消后，已恢复原 MangaDex / xkcd 信任及 Afrikaans 启用。模拟器暂停在深色 MangaDex 详情。

## Karuyomi 独有状态与转换

这些节点没有 Mihon 的业务等价物，不能用参考应用图证明通过。应用同一套主题和页面骨架，并在目标 Web 产物中逐状态采集浅/深图；原生现场验收仍停止。

```mermaid
stateDiagram-v2
    [*] --> K0
    state "27.K1 未连接" as K0
    state "27.K2 正在连接" as K1
    state "27.K3 登录失效" as K2
    state "27.K4 无权限" as K3
    state "27.K5 身份已确认" as K4
    state "30.K1 已确认快照" as K5
    state "30.K2 未保存草稿" as K6
    state "30.K3 等待确认" as K7
    state "30.K4 结果未知" as K8
    state "30.K5 CAS冲突" as K9
    state "30.K6 部分提交" as K10
    state "30.K7 身份或Source退役" as K11
    state "28.K1 资源释放中" as K12
    state "28.K2 释放失败" as K13
    K0 --> K1: 连接
    K1 --> K2: 需要登录
    K1 --> K3: 拒绝访问
    K1 --> K4: 确认身份
    K2 --> K1: 显式登录
    K3 --> K1: 切换账号
    K4 --> K5: 读取快照
    K5 --> K6: 编辑
    K6 --> K7: 保存原命令
    K7 --> K5: 服务端确认
    K7 --> K8: 响应丢失
    K8 --> K7: 原命令幂等重试
    K7 --> K9: revision不匹配
    K9 --> K5: 显式只读重取
    K7 --> K10: 批量部分成功
    K10 --> K8: 有不确定项
    K10 --> K6: 明确提交剩余项
    K6 --> K11: 身份或Source变化
    K7 --> K11: 身份或Source变化
    K11 --> K12: 关闭旧资源并丢弃迟到结果
    K12 --> K13: ACK失败
    K13 --> K12: 重试同一资源清理
    K12 --> K4: 清理确认后继续
```

| 状态 ID | 最小必要信息与操作边界                                       | 浅色 | 深色 |
| ------- | ------------------------------------------------------------ | ---- | ---- |
| 27.K1   | 当前服务地址、尚未连接、连接入口；地址非法时给出可修正原因   | 待   | 待   |
| 27.K2   | 正在连接的服务、进度及当前可用操作；不显示旧身份的已保存状态 | 待   | 待   |
| 27.K3   | 登录已失效、受影响操作、显式登录/重试入口及未确认草稿提示    | 待   | 待   |
| 27.K4   | 当前服务、拒绝访问原因和切换账号/连接入口                    | 待   | 待   |
| 27.K5   | 已确认的服务与身份、连接状态和后续可用入口                   | 待   | 待   |
| 30.K1   | 当前对象、服务端已确认值及适用的保存反馈                     | 待   | 待   |
| 30.K2   | 当前对象与草稿、尚未保存提示、可提交/校验原因及取消          | 待   | 待   |
| 30.K3   | 保存中、操作对象和提交范围；禁止重复提交并保留草稿           | 待   | 待   |
| 30.K4   | 结果尚未确认、保留的原操作及同一操作重试；不误报成功或失败   | 待   | 待   |
| 30.K5   | 服务端值已变化、受影响草稿与显式重新读取入口                 | 待   | 待   |
| 30.K6   | 已确认/失败/未知的对象及数量、剩余操作和精确重试             | 待   | 待   |
| 30.K7   | 原身份或来源已失效、受影响草稿、旧操作不可继续及恢复入口     | 待   | 待   |
| 28.K1   | 正在关闭的页面/资源、等待确认及受阻操作                      | 待   | 待   |
| 28.K2   | 尚未释放的资源、失败原因和同一清理重试入口                   | 待   | 待   |

各业务页需要分别覆盖：书架/分类与批量（02–06）、账户扩展/仓库（08–11）、Source偏好（14）、停止/取消/分页/资源清理（12/15）、作品元数据/章节读态/书签/封面（16–19）、只读迁移映射与提交（20–21）、阅读进度/Access恢复/设置覆盖（22–24）、全局设置和连接/诊断（26–28）。共享状态机仅归纳语义，表中目标画面仍分别待验，不能用一张设置错误截图代替全部业务上下文。

### 15：Karuyomi 跨源搜索的目标状态

这张图跟踪产品自身的明确选源、独立重试与停止确认，不填入 Mihon 的参考画面。下表记录真实 CI Web 产物 `b826249` 与错误修复 `07342fb` 的隔离内置浏览器证据；已有截图不代表全部变体或最终配色验收完成。浏览器截图实际编码为 JPEG，不用于精确颜色采样。

```mermaid
stateDiagram-v2
    [*] --> Q0
    state "15.K1 查询与明确选源" as Q0
    state "15.K2 没有可选源" as Q1
    state "15.K3 查询或选择无效" as Q2
    state "15.K4 等待执行" as Q3
    state "15.K5 单源加载" as Q4
    state "15.K6 单源有结果" as Q5
    state "15.K7 单源无结果" as Q6
    state "15.K8 单源失败" as Q7
    state "15.K9 完整错误诊断" as Q8
    state "15.K10 正在停止" as Q9
    state "15.K11 停止已确认" as Q10
    state "15.K12 停止未确认" as Q11
    state "15.K13 页面资源清理失败" as Q12
    state "15.K14 正在打开作品" as Q13
    state "15.K15 精确作品详情" as Q14
    Q0 --> Q1: 无可用源
    Q1 --> Q0: 安装后刷新范围
    Q0 --> Q2: 空词/过长/未选源
    Q2 --> Q0: 修正
    Q0 --> Q3: 冻结查询和来源
    Q3 --> Q4: 获得执行位置
    Q4 --> Q5: 有结果
    Q4 --> Q6: 无结果
    Q4 --> Q7: 失败
    Q7 --> Q8: 查看错误详情
    Q8 --> Q7: 关闭且不发请求
    Q7 --> Q3: 只重试此源原查询/页
    Q5 --> Q3: 此源下一页且保留已有结果
    Q3 --> Q9: 停止此源
    Q4 --> Q9: 停止此源
    Q9 --> Q10: ACK确认
    Q9 --> Q11: 确认失败
    Q11 --> Q9: 重试同一停止
    Q10 --> Q3: 显式重试
    Q5 --> Q13: 打开精确作品并停止旧任务
    Q13 --> Q14: 详情就绪
    Q14 --> Q5: 返回原查询与结果
    Q0 --> Q12: 退出时清理失败
    Q12 --> Q0: 重试清理确认后返回
    classDef paired fill:#d9f4de,color:#14351d,stroke:#2b7a3d
    class Q0,Q4,Q5,Q6,Q7,Q8,Q10,Q14 paired
```

| 状态 ID | 最小必要信息与实际边界                                                    | 浅色                                                                               | 深色                                                                             |
| ------- | ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| 15.K1   | 查询、源数/上限、语言及明确选择、刷新和开始；主图为未选源                 | `karuyomi-b826249-cross-scope-light.jpg`                                           | `karuyomi-b826249-cross-scope-dark.jpg`                                          |
| 15.K2   | 无可选源原因及安装/刷新入口                                               | 待                                                                                 | 待                                                                               |
| 15.K3   | 原输入与校验原因、可修正入口，不创建搜索任务                              | 待                                                                                 | 待                                                                               |
| 15.K4   | 源身份、等待执行及停止入口；同包排队要真实截到                            | 待                                                                                 | 待                                                                               |
| 15.K5   | 源名、语言、真实旋转指示、停止此源/全部和总进度；独立重试保留 xkcd 空结果 | `karuyomi-07342fb-cross-start-light.jpg`、`karuyomi-07342fb-cross-retry-light.jpg` | `karuyomi-07342fb-cross-start-dark.jpg`、`karuyomi-07342fb-cross-retry-dark.jpg` |
| 15.K6   | Komiic 备用镜像的三项真实结果；标题在封面下，普通封面仍占位               | `karuyomi-b826249-cross-results-light.jpg`                                         | `karuyomi-b826249-cross-results-dark.jpg`                                        |
| 15.K7   | xkcd 返回零项、源状态及空结果说明；与成功源同屏                           | `karuyomi-b826249-cross-results-light.jpg`                                         | `karuyomi-b826249-cross-results-dark.jpg`                                        |
| 15.K8   | 默认镜像真实 HTTP 500；短说明、错误详情与重试独立命名，重试在首屏         | `karuyomi-07342fb-cross-error-light.jpg`                                           | `karuyomi-07342fb-cross-error-dark.jpg`                                          |
| 15.K9   | 源名、完整原始诊断和关闭；关闭后仍停在原失败，超长滚动浏览器变体待补      | `karuyomi-07342fb-cross-diagnostic-light.jpg`                                      | `karuyomi-07342fb-cross-diagnostic-dark.jpg`                                     |
| 15.K10  | 正在停止、当前源及禁止重复开始；不能用加载图代替                          | 待                                                                                 | 待                                                                               |
| 15.K11  | 两源均已停止、原查询与显式重试；本轮为零结果，非空保留/旧停止失败恢复待补 | `karuyomi-07342fb-cross-stopped-light.jpg`                                         | `karuyomi-07342fb-cross-stopped-dark.jpg`                                        |
| 15.K12  | 未确认的停止、同一停止重试、继续搜索受阻                                  | 待                                                                                 | 待                                                                               |
| 15.K13  | 页面资源尚未释放、精确清理重试、退出受阻                                  | 待                                                                                 | 待                                                                               |
| 15.K14  | 正在打开、原分源结果与冻结操作；实际过渡图仍待                            | 待                                                                                 | 待                                                                               |
| 15.K15  | 《ONE PIECE航海王》、尾田榮一郎、238 章；返回保留原查询与三项结果         | `karuyomi-b826249-cross-open-light.jpg`、`karuyomi-b826249-cross-return-light.jpg` | `karuyomi-b826249-cross-open-dark.jpg`、`karuyomi-b826249-cross-return-dark.jpg` |

`07342fb` 的三张 `cross-{start,errors,operations}-pairs.jpg` 联系表已实看，浅深均为 360×800、同样的 xkcd en / Komiic 和查询 `航海王`。两主题重试按钮 DOM 均为 `x=8,y=588,width=106.359375,height=57`，名称仅为“重试此源”。独立重试帧的 Komiic 旋转指示和 xkcd 已返回空态同时存在；深色 DOM 在截图后已回到失败，不用后续 DOM 冒充截图瞬间。错误详情为完整 HTTP 500 和原始 JS/Java 堆栈，关闭后仍为原失败。超长诊断的实际滚动、无请求的独立网络审计及取消 ACK 失败等仍待浏览器分项；100 行诊断/关闭不请求/取消失败恢复另有 29 项组件与控制器回归，不能互相替代。验收采用临时 D1、`acceptance-owner`、无 fixture；视口已恢复且 harness 已停止。

## 已核对的成对参考与差异

2026-11-14 已实看 `category-theme-pairs.jpg`、`library-theme-pairs-0.jpg` 与 `library-theme-pairs-1.jpg` 的 PNG 联系表，并与同名 XML 对照。首批覆盖书架有内容/空分类/搜索、选项三页签、多选/更多/移出初态、分类列表/输入/校验/删除及设置目录/外观。排序重新统一为“检查更新时间”降序，深色面板从普通书架打开，不沿用搜索条仍开着的旧图。

- 创建和重命名的重名错误为独立节点；移出确认的初始禁用态与选择范围后可提交态也分别记录。实际取消删除确认返回底层“迁移/删除”菜单，不能画作直接回书架。
- 固定 DEFAULT 的空书架与移出确认可提交态新增成对联系表 `library-empty-removal-pairs.jpg`。浅色确认移出唯一测试 xkcd 后显示空书架，切深色保留空态；随后从同一真实源详情重新添加 xkcd。深色取消可提交确认返回底层菜单，作品仍保留，确认成功转换仍待深色重放。未删除下载或进度；模拟器已暂停在 xkcd 多选态。空态颜文字不同，排除该字形的同内容叠图。
- 参考应用的空态颜文字每次随机变化，属于同一空态；保留实际生成结果，不为叠图修改上游。
- Gboard 是独立系统界面：本次应用切深色时键盘仍跟随 Android 系统浅色，需单独核对键盘占位及操作可达，不将键盘颜色作为 Mihon 配色角色。
- 外观深色新增“纯黑深色模式”一行，导致下方显示组位移；该开关本次关闭。列表、弹层和背景分别取色，不用单一黑白反转代替深色。
- 搜索无结果的主图含键盘，后续仍需无键盘及双倍字号变体；未覆盖的变体不因主状态成对而清零。
- 已实看 `chapter-results-reviewed-0.jpg`、`chapter-results-reviewed-1.jpg`、`image-actions-matched-reviewed.jpg` 和 `reader-settings-lower-reviewed.jpg`。章节多选、已读/未读、书签添加/删除均有成对主图；图片操作与封面确认已统一为同一页且底层工具隐藏，取消实际返回图片操作面板。确认封面后的落点仍待验。阅读设置的模式/常规滚动末端已成对；模式中段约有 7 个物理像素的滚动偏差，只作为覆盖证据，后续逐元素叠图须先对齐滚动锚点。
- `source-pairs-reviewed-0.jpg` 至 `source-pairs-reviewed-3.jpg` 已实看源列表/置顶/语言上段/源操作、xkcd 热门/搜索无结果、已安装扩展/目录/搜索清空、更多菜单及筛选独立空态的成对主图。源列表的语言条件统一为多语言/English。08.03 的未加载和更新、07.05 的下段、12.06 的无键盘及恢复仍待补；08.05 两侧启用语言不同，不能按同条件完成。Mihon 的“置顶”用于分组布局对照，不将其解释为 Karuyomi 的账户服务端收藏能力。
- `repository-pairs-reviewed-0.jpg` 至 `repository-pairs-reviewed-2.jpg` 已实看仓库空态、输入空/有效值、实际校验错误、处理中、成功列表和移除确认/取消/完成。仓库地址为 `https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json`；处理中浅色采用先截图后 XML，PNG 确实包含加载文字。深色空输入/错误图使用拼音键盘、有效地址和处理中已切 English；键盘作为独立系统变体保留，仍需同键盘条件对照。未将提交前的 `s1003-repository-invalid-dark` 误记为错误结果。
- 新节点 08.12 对应 `ExtensionFilterScreen.kt` 的 `state.isEmpty` 分支：无仓库语言目录时筛选页自身为空，区别于有值的语言筛选 08.05。xkcd 不支持最新，搜索实现返回空；搜索成功、最新与分页必须另用真实支持的 Source 采集，不以空结果覆盖。
- 后续 `extension-storage-pairs-0.jpg` 至 `extension-storage-pairs-6.jpg` 已实看；第 2 张取消深色图曾为旧帧，已替换为重新采集并实看的稳定返回图。未加载/信任/取消、来源关闭/恢复、存储首屏/占用/清理后、系统卸载确认及高级完整滚动段均新增双主题主图；未加载其它原因、更新/下载/安装、确认卸载与清理失败仍待。系统弹层和中段滚动限制见对应表，不将新增主图计为整组完成。

## 当前采集顺序与变体门槛

1. 书架/分类已完成首批成对核对，空书架、空分类管理、移出可提交及混合分类主态已补；继续补混合项修改/确认、深色移出成功及全部转换。流程图绿色只代表所标具体状态，不能代表该组全部状态已完成。
2. 继续源/扩展/仓库、浏览/筛选/偏好/跨源搜索、详情/章节/封面/迁移、阅读器、设置/诊断。每组采用双主题成对采集；网络错误只作用于参考模拟器并及时恢复。
3. 对所有已记录状态核对主要元素边界与颜色角色，再使用对应数据验证 Karuyomi 的 Cupertino 呈现；源码数值或参考图不能替代目标产物。
4. 完成每组的360px、宽屏/横屏、长中文、双倍文字、键盘/滚动末端和减少动态；键盘必须同时显示输入及可达的提交/取消。主题切换不能丢失选择或草稿。

已排除的误计：`reader-loading-default-dark` 是 Android 全屏引导；`cover-view-default-dark` 仍为详情；`extension-details-selected-default-dark` 仍为扩展列表；`settings-main-default-dark` 是更多页；`category-create-filled-default-dark` 输入仍为空。它们均不填入所命名的目标状态。
