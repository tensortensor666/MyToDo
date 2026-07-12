# 原型 vs Flutter 差距修复 TODO

对比来源
- 原型：`C:\Users\tensor\AppData\Roaming\Open Design\namespaces\release-stable-win\data\projects\0ead1f80-3c76-4f93-acf9-0548c81082d6`（`desktop.html` / `android.html` / `styles.css` / `critique.json`）
- Flutter 工程：`e:\code\MyTodo`（`lib/main.dart` + `lib/src/ui/nav_views.dart` + `lib/src/data/*`）
- 本轮新增原型反馈：`critique.json` 强调普通 todo 不再显示或操作进度，存钱清单进度继续保留为核心信息。

工作流约定（按 memory）：**做一项 → 编 exe + apk + 截图 → 等用户确认再做下一项**。本文件按完成顺序勾选。

---

## [1] 侧栏导航顺序：存钱清单归入「清单」段

- **现状**：`buildNavEntries`（nav_views.dart:61）把存钱放在列表最后；`_DesktopSidebar`（main.dart:1151）按 `isVirtual` 分组，存钱因 `isVirtual=true` 落入「智能视图」段尾部（已计划 之后）。
- **原型**：「存钱清单」位于「清单」段内（收件箱 / 工作 / 生活 之后、系统段之前），侧栏计数显示计划总数（原型 demo 为 3）。
- **改动点**：
  - `nav_views.dart`：给 `TodoNavEntry` 增加定位标记或调整构建顺序，使存钱能在清单段尾部渲染；存钱计数 = `store.savings.length`。
  - `main.dart` `_DesktopSidebar`：把存钱从 `smartEntries` 挑出，放到「清单」段末尾渲染（用户清单之后）。
  - `_CompactNavigationDrawer`：同步分组。
- **验证目标**：存钱出现在「清单」段、计数为计划数；智能视图段只剩 我的一天 / 重要 / 已计划。

状态：✅ 代码已完成，待 Windows / Android 截图确认

改动已完成：
- `nav_views.dart`：`TodoNavEntry` 新增 `isSavingsView` 标记，存钱条目置为 true。
- `main.dart` `_DesktopSidebar`：从 smartEntries 剔除存钱，新增 `savingsEntry` 在「清单」段末尾（用户清单之后）渲染，计数改用 `controller.store.savings.length`。
- `main.dart` `_CompactNavigationDrawer`：存钱计数同样用 `store.savings.length`。
- `flutter analyze` 通过（No issues found）。

待办：运行 Windows / Android 实机对比侧栏顺序，等用户确认。

---

## [2] 普通任务移除进度 UI，进度只保留给存钱清单

- **原型**：`critique.json` 说明普通 todo 不再显示或操作进度；普通任务卡只保留完成状态、标题、meta、重要/删除等动作，存钱清单继续显示整体/单计划进度。
- **Flutter 原状**：`_TodoTile` 渲染 `_TodoProgressBar`，任务编辑器 `_TodoEditorContent` 也有「进度」Slider。
- **改动点**：
  - `main.dart`：移除普通任务卡里的 `_TodoProgressBar` 渲染。
  - `main.dart`：删除 `_TodoProgressBar` 组件。
  - `main.dart`：任务编辑器不再展示/提交普通 todo 的进度字段。
  - `todo_models.dart` / `todo_store.dart`：保留底层 `progress` 字段和同步兼容逻辑，避免历史数据和远程事件结构破坏。
- **验证目标**：普通任务行无进度条/百分比/滑杆；编辑任务无「进度」字段；存钱清单仍显示整体进度和计划进度。

状态：✅ 代码已完成，待截图确认

---

## [3] 桌面窗口关闭态 `window-closed-state`

- 原型 `desktop.html:423` `.window-closed-state`：窗口关闭后整页「MyTodo 已关闭」+ 重新打开按钮。
- Flutter 当前无对应态。需评估：Flutter 关窗 = 进程退出，"重新打开"在桌面单实例语义下是否成立。可能以托盘恢复窗口实现。

状态：⬜ 未开始

---

## [4] 设置抽屉视觉对齐原型

- 原型 `desktop.html` / `android.html` 已更新为「设置与同步」：第一张卡为 Supabase 空间配置，第二张卡为软件更新，底部为构建信息。
- Flutter 原状仍显示「关于 MyTodo」，并把 Supabase 配置放在独立弹窗里，卡片顺序和原型不一致。

状态：✅ 代码已完成，待视觉截图确认

改动已完成：
- `main.dart`：桌面右侧抽屉和 Android sheet 标题统一为「设置与同步」。
- `main.dart`：`_SettingsSurface` 改为原型顺序「远程同步 / Supabase 空间」→「软件更新」→ footer。
- `main.dart`：Supabase 项目 URL、Anon Key、设备名称、最近同步直接在设置卡内展示和编辑。
- `main.dart`：保存配置、测试连接、立即同步、断开按钮放在同一卡内。
- `todo_store.dart`：新增 `updateDeviceName`，设置页设备名称可持久化。

待办：截图确认输入框网格、switch pill、按钮换行和原型一致。

---

## [5] 版本号标签同步

- 原型 `v1.4.2` 占位；Flutter `_appVersionLabel = 'v1.4.8'`、`_appBuildLabel = '构建 2026.07.09'`。
- 确认工程真实版本（pubspec.yaml version），把侧栏设置入口尾部 + 设置卡 + Android 关于卡统一到真实版本。

状态：✅ 代码已完成，待截图确认

改动已完成：
- `pubspec.yaml` 当前真实版本为 `1.4.9+26`。
- `main.dart`：`_appVersionLabel` 更新为 `v1.4.9`。
- 侧栏设置入口、设置更新卡、Android 设置 sheet 共用该常量。

---

## [6] Android appbar 与原型对齐

- 原型 `android.html` appbar：左侧 menu + MyTodo，右侧 搜索 / 同步；设置入口移入 `mobile-sidebar` 的「系统 / 设置与同步」。
- 原型主屏：只显示当前清单标题、`当前 / 逾期 / 完成` tabs 和匹配任务；不再显示移动端摘要卡或底部导航。
- 原型 `mobile-sidebar`：按「智能视图 / 清单 / 系统」分组，点击导航项后收起侧栏并切换范围，底部显示远程同步卡。

状态：✅ 代码已同步，待 Android 截图确认

已完成：
- `main.dart` `_MobileNavigationBar`：左侧 menu + `MyTodo`，右侧保留 搜索 / 同步，移除设置按钮。
- `main.dart` `_CompactNavigationDrawer`：重排为「智能视图 / 清单 / 系统」分组，新增「设置与同步」和底部远程同步卡。
- `main.dart` `_TodoContentPage`：移动端主内容改为当前清单标题 + 状态 tabs + 任务列表，移除摘要卡。
- `main.dart`：移除移动端底部导航，FAB 下移到右下角 24px。

保留差异：
- Flutter 在「清单」分组中保留「存钱清单」入口，避免 Android 端失去已有功能入口。

---

## [7] 存钱流水行 is-in / is-out 着色核对

- 原型 `savings-ledger-row.is-in` 绿、`.is-out` 红（styles.css:2409-2410）。
- Flutter `_SavingsDetail` ledger 行需确认存入/取出金额着色一致。

状态：✅ 代码已核对，待截图确认

核对结果：
- `_SavingsDetail`：`entry.amount >= 0` 使用 `_appSuccess`，负数使用 `_appDanger`。
- 金额显示为 `+¥...` / `−¥...`，与原型 `is-in` / `is-out` 语义一致。

---

## [8] 存钱计划新建/编辑抽屉对齐原型

- **原型**：`desktop.html` 的 `savings-plan-drawer` 使用右侧抽屉，宽度 `min(460px, 100vw - 24px)`，三段式结构：标题栏 / 可滚动表单 / footer 按钮栏。
- **Flutter 原状**：`_showSavingsPlanEditor` 使用居中的 `AlertDialog`，配色继承默认 Material，对比原型不一致。
- **改动点**：
  - `main.dart`：`_showSavingsPlanEditor` 改为 `showGeneralDialog` 右侧滑入抽屉。
  - `main.dart`：面板背景、边框、圆角、遮罩、按钮高度和输入框配色对齐原型 token。
  - `main.dart`：新建时保留「首笔存入（可选）」双列布局；编辑时不显示首笔存入，避免误追加流水。
  - `main.dart`：表单校验改为原型式字段下方错误文案。
- **验证目标**：点击「新建计划」/ 编辑存钱计划时从右侧弹出抽屉；不再出现居中弹窗；输入框为暖白 surface、橙色 focus、红色错误提示。

状态：✅ 代码已完成，待截图确认

---

## [9] 原型 demo 数据填充

- **原型**：桌面和 Android 原型包含固定演示数据：工作/生活清单、4 条任务、3 个存钱计划及流水。
- **Flutter 原状**：新安装数据库只有系统清单，无原型 demo 数据；视觉对比时页面内容和计数不一致。
- **改动点**：
  - `todo_store.dart`：正式 `TodoStore.open()` 在空库首次启动时调用 `seedPrototypeDataIfEmpty()`。
  - `todo_store.dart`：种子数据包含原型任务「整理周末采购清单 / 同步 Windows 和 Android 设备 / 处理过期发票 / 检查应用内更新页面」。
  - `todo_store.dart`：种子数据包含原型存钱计划「应急备用金 / 旅行基金 / 新设备款」及对应流水。
  - `todo_store.dart`：只在无任务、无自定义清单、无模板、无存钱计划时填充，避免覆盖用户已有数据。
  - `todo_store_test.dart`：新增空库只填充一次的回归测试。
- **验证目标**：清空数据或新安装后，任务、清单、存钱计划和计数接近原型；已有用户数据启动后不会被追加 demo 数据。

状态：✅ 代码已完成，待截图确认

---

## [10] 任务行 meta 行语义图标核对

- 原型每条任务 meta 带 创建(note) / 截止(calendar) / 提醒(bell) / 清单(inbox/briefcase) 多图标。
- Flutter `_TodoTile` 元信息图标需核对齐全度与样式（逾期用 due-danger 红）。

状态：⬜ 未开始

---

## [11] 入口页 launcher（可选）

- 原型 `index.html` 双卡入口 + 入场动效。
- Flutter 直接按宽度切换桌面/移动布局，无独立 launcher。功能型应用可不做。

状态：⬜ 未开始（评估是否需要）
