# Edit Site Time Zone 布局崩溃修复

## 问题现象

点击 Sites 列表中的 Edit Site 后，`/sitespace/retrieve/siteprops` 请求成功，但页面在 `SiteEditViewController.setupTimeZoneSection()` 加载期间抛出 `NSGenericException`：两个 UILabel 的横向约束无法激活，因为约束两端没有共同祖先视图。

服务器回复中的空 timezone 符合未配置语义，不是本次崩溃原因。

## 根因

新增 Time Zone UI 有两处相同的视图层级顺序错误：

- Edit Site 中，`timeZoneNameLabel` 建立到 `timeZoneOffsetLabel` 的约束时，后者尚未加入 `timeZoneContainer`。
- Time Zone 选择列表 cell 中，`ianaIdLabel` 建立到 `utcOffsetLabel` 的约束时，后者尚未加入 `cardView`。

SnapKit 会在 `makeConstraints` 阶段立即激活约束。约束引用的 sibling 必须先进入同一个父视图，否则 UIKit 会抛出异常。

## 修复

- 在 Edit Site 中，先将两个 timezone UILabel 都加入 `timeZoneContainer`，再激活二者之间的横向约束。
- 在 Time Zone cell 中，先将 IANA 和 UTC offset UILabel 都加入 `cardView`，再激活二者之间的横向约束。
- 未改变 UI 尺寸、颜色、文案、时区数据、retrieve/update 接口或同步流程。

## 回归保护

`SiteTimeZoneUIContractTests` 新增两项视图层级顺序检查，分别覆盖 Edit Site timezone 行和 Time Zone 列表 cell。

TDD 过程：

- 修复前，测试分别以 Edit Site 和 Time Zone cell 的 sibling 尚未共享父视图为原因失败。
- 修复后，完整 UI 路由契约测试通过。

## 验证结果

重新编译并运行的 7 项时区测试全部通过：

- SiteTimeZoneValueTests
- SiteTimeZoneCatalogTests
- SitePropsEditPolicyTests
- SiteTimeZonePersistenceContractTests
- SitePropsAPIContractTests
- SiteTimeZoneUIContractTests：完整 UI 路由
- SiteTimeZoneUIContractTests：本地化、资源和 target 归属

以下四个 scheme 均使用 Debug、generic iPhoneOS、关闭签名构建通过，退出码为 0：

- SunSmart
- Archipelago
- SLG Sync Plus
- SylSmart

仍需在真机重新点击 Edit Site，并继续进入 Time Zone 选择列表，完成原始崩溃路径的运行时验收。

本次未创建 Git commit。
