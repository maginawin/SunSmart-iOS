# Site 入口同步弹窗 Figma 对齐设计

## 目标

将 `SiteEntryTimeZoneSyncOverlay` 的检查态和结果态分别对齐 Figma 节点 `399:11418` 与 `399:11390`，只调整视觉实现，不改变已确认的时区仲裁、1 秒最短展示、30 秒超时、返回拦截和 `GOT IT` 关闭逻辑。

## Figma 规格

### Checking sync status

- 卡片固定尺寸：302 × 188 pt。
- 圆角：20 pt。
- 阴影：Y 轴 5 pt、模糊 8 pt、黑色 10%。
- Loading 容器：56 × 56 pt，顶部 18 pt；内部图形为 Figma 导出的 39 × 39 pt 资源。
- 标题：18 pt Regular、`#1E2329`、高度 26 pt。
- 描述：15 pt Light、`#64748B`、两行居中、高度 44 pt。
- Loading、标题、描述之间均为 10 pt。

### Sync status

- 卡片固定尺寸：343 × 296 pt。
- 圆角：24 pt。
- 阴影：Figma 双层阴影，UIKit 使用等效组合阴影表达。
- 内容区左右各 24 pt、顶部 24 pt。
- 标题：16 pt Regular、`#1E2329`、高度 25 pt。
- 第一状态卡距标题 16 pt；第二状态卡距第一卡 8 pt。
- 两张状态卡均为 313 × 64 pt、16 pt 圆角、背景 `#F6F8FF`。
- 状态卡左侧 32 × 32 pt 淡绿色圆形底，内部使用 Figma 导出的 16 × 16 pt成功图标。
- 主文字：14 pt Light、`#1E2329`；状态文字：12 pt Light、成功色 `#007A55`。
- `GOT IT` 区域固定在底部，高 60 pt；顶部 1 pt 分隔线；透明背景；15 pt Light 主题色文字 `#6667AB`。

## 数据与交互保持

- Site 行继续展示动态 UTC offset 和实际上传结果。
- Gateway 行继续展示当前阶段已确认的状态文案。
- 失败状态保留红色状态文字，但卡片结构仍与 Figma 一致。
- 检查态不可关闭；结果态只能点击 `GOT IT` 关闭。
- 新增图形资源放入共用 Asset Catalog，使四个品牌 target 共同使用，不增加 target 专属资源。

## 验证

- 先扩充现有 Overlay 契约测试，使旧布局因尺寸、结构和资源不匹配而失败。
- 修改 Overlay 和资源后使契约测试通过。
- 回归全部 Site 入口时区同步聚焦测试。
- 使用 generic iPhoneOS 分别构建 SunSmart、Archipelago、SLG Sync Plus、SylSmart。
- 真机视觉验收仍需对照 Figma 检查屏幕缩放、Dynamic Type 和动画。
