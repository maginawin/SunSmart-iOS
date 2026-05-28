# Space Share Flow Analysis

## 结论

- 入口：`SunSmart/Main/Site/Controller/SiteViewController.swift` 的 `spaceMenu(space:point:)`，当 `space.spaceOperates` 包含 `.shareEditor` 或 `.shareVisitor` 时显示 Share 菜单项，点击后调用 `shareSpace(space)`。
- 主流程：`shareSpace(_:)` 会先检查网络、密码验证、云同步状态、是否有未上传数据。只有通过这些前置检查后才会进入分享请求。
- 请求策略：
  - 如果 `space.shareCode` 已存在，调用 `.shareInfo(shareId:)` 拉取既有分享数据。
  - 如果 `space.shareCode` 不存在，必要时生成 `editorPassword`，再调用 `.spaceShare(space:)` 创建分享 token。
- HTTP 方法：`NetowrkReqeustApi.method` 当前统一 `return .post`，所以 `.shareInfo` 与 `.spaceShare` 都会以 POST 发送。

## 关键定位

- Share 菜单入口：`SunSmart/Main/Site/Controller/SiteViewController.swift:1565`
- 点击调用：`SunSmart/Main/Site/Controller/SiteViewController.swift:1567`
- Share 主流程：`SunSmart/Main/Site/Controller/SiteViewController.swift:1188`
- 未同步数据拦截：`SunSmart/Main/Site/Controller/SiteViewController.swift:1219`
- 已有 shareCode 时选择 `.shareInfo`：`SunSmart/Main/Site/Controller/SiteViewController.swift:1235`
- 无 shareCode 时选择 `.spaceShare`：`SunSmart/Main/Site/Controller/SiteViewController.swift:1242`
- 发起请求：`SunSmart/Main/Site/Controller/SiteViewController.swift:1246`
- `.spaceShare` path：`SunSmart/Common/Network/NetowrkReqeustApi.swift:276`
- `.shareInfo` path：`SunSmart/Common/Network/NetowrkReqeustApi.swift:286`
- 统一 POST：`SunSmart/Common/Network/NetowrkReqeustApi.swift:327`
- `.spaceShare` 参数：`SunSmart/Common/Network/NetowrkReqeustApi.swift:402`
- `.shareInfo` 参数：`SunSmart/Common/Network/NetowrkReqeustApi.swift:429`
- Moya 实际 request：`SunSmart/Common/Network/NetworkRequest.swift:85`

## 是否每次都会发命令给服务器

不是每次点击都一定马上发分享接口：

- 无网络直接提示并返回。
- 非 owner 且需要密码验证时，会先验证密码，验证通过后递归重新进入分享流程。
- 当前 space 云同步排队或进行中时，只提示或提升同步优先级，不发分享接口。
- `space.needUploadCloud == true` 时，先加入云同步任务并返回，不发分享接口。

通过前置检查后，会发一次网络请求：

- 已有 `space.shareCode`：发 `.shareInfo`，POST `/sitespace/share/info`。
- 没有 `space.shareCode`：发 `.spaceShare`，POST `/sitespace/space/singleshare`。
