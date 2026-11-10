# 全应用主题系统

主题统一管理颜色、组件、排版、页面渲染与装饰。首页、编辑器、日历、AI、设置和浮层共用主题状态，切换时保留当前业务数据与页面状态。视觉要求见[设计规范](../DESIGN.md#视觉语言与全局主题)。

## 架构边界

```text
AppThemeCatalog（身份、文案、能力、稳定存储 ID）
        │
        ├── AppPalette（语义颜色与页面渐变）
        ├── AppComponentTheme（圆角、排版、组件与布局语义）
        ├── AppThemeAtmosphere（导航栈和浮层之上的全局装饰）
        └── experience/*（需要完全不同结构时的主题页面渲染器）
                         │
                    共用页面状态与业务回调
```

- `lib/theme/app_theme_catalog.dart` 是可选主题的唯一目录。持久化只保存 `storageId`，不能保存枚举下标。
- `AppThemeCatalog.defaultStyle` 定义首次启动和配置失效时使用的主题，当前为「纸短情长」。明暗选项由各主题的 `supportsDark` 决定。
- `lib/theme/app_theme.dart` 负责 Material 基础主题和 `AppPalette`。功能页面只读取 `context.appColors` 等语义颜色。
- `lib/theme/app_component_theme.dart` 负责非颜色决策，包括字号、字体、圆角、阴影和首页、日历、设置、AI、编辑器的展示语义。页面按这些语义渲染，不能判断具体主题名。
- `AppThemeAtmosphere` 安装在 `MaterialApp.builder`，使路由、弹窗、底部弹层和应用锁共享同一种全局质感。
- 首页等结构差异很大的体验放入 `lib/experience/<experience>/`。渲染器只接收已整理的状态与回调，不读取仓储、不保存设置，也不复制搜索、选择、隐私空间等业务逻辑。
- 弹窗、菜单和反馈统一经过 `AppOverlay`、`AppAnchoredMenuButton`、`AppFeedback` 等入口，避免浮层脱离当前主题。
- 纸张主题的实心按钮与首页选中标签共用 `AppPalette.primaryFill` / `primaryGradient`，避免实色按钮比纸面控件显得更沉；小字、图标仍使用 `accent`，浅色选区文字使用 `onAccentSoft`，不借用按下态颜色。禁用和自定义危险色按钮保留各自状态色。文件管理器与首页共用 `AppThemeCanvas` 背景。

`test/theme_architecture_test.dart` 会阻止 `lib/pages`、`lib/widgets` 和 `lib/experience` 直接使用 `AppThemeStyle.*`。需要新增视觉能力时，应扩展语义配置，而不是在功能页面写 `if (当前主题 == ...)`。

## 新增主题流程

1. 在中英文 ARB 中加入主题名称、说明和明暗限制文案，重新生成本地化代码。
2. 在 `AppThemeStyle` 和 `AppThemeCatalog.definitions` 注册主题；选择新的、稳定且永不复用的 `storageId`。
3. 新增版本化设计 Token，并在 `AppPalette` 中完成浅色、深色（如支持）及可读性颜色映射。
4. 配置 `AppComponentTheme`。能复用现有组件语言时复用 profile；确有新的排版或组件行为时，先增加语义枚举或字段，再由页面消费该语义。
5. 若页面结构完全不同，在 `lib/experience` 新建纯渲染 surface，由现有页面注入状态和操作。不要分叉控制器、数据库或导航规则。
6. 检查首页、编辑器、日历、AI、设置、应用锁、菜单、对话框、底部弹层、错误反馈及安全区域，保证主题从背景到最小控件连续一致。
7. 添加颜色对比度、组件 profile、持久化、窄屏、大字号和关键页面 widget 测试；页面结构变化通过布局尺寸、溢出与交互断言验证。

## 验收标准

- 切换主题后当前路由立即更新，输入、滚动、搜索、选择和编辑草稿不丢失。
- 所有文字和交互色满足现有对比度测试；大字号与窄屏没有溢出。
- 主题不改变笔记、隐私、AI、同步或备份的业务规则。
- 新主题可以改变组件和页面结构，但主题专属代码被限制在主题定义与体验渲染层。
- `flutter analyze`、全量 `flutter test`和主题架构测试均通过。
