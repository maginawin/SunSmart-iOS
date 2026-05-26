# HTTP 请求日志与创建 Space 失败分析

## 背景

当前问题是在 Site 中创建 Space 失败，界面只弹出同步失败或未知错误，控制台缺少足够 HTTP 日志，难以判断是请求未发出、服务端拒绝、响应解析失败，还是业务错误码未覆盖。

## 当前请求日志现状

- 项目网络层使用 `MoyaProvider<NetowrkReqeustApi>`，并挂载了自定义 `NetworkLoggerPlugin`。
- `NetworkLoggerPlugin.willSend` 中请求 URL、headers、body 的打印全部被注释。
- `NetworkLoggerPlugin.didReceive` 中成功响应的 URL、status code、response data 打印也全部被注释。
- 当前唯一有效的日志是 Moya 传输失败时打印 `Request failed with error`。
- 如果服务端返回 HTTP 成功但业务 `code != 200`，`NetworkRequest` 只把 code 映射成 `NetworkApiError`，不会打印原始 code、message、响应体或目标接口。
- 未被枚举覆盖的服务端错误码会统一变成 `.unknown`，最终 UI 只显示 `unknown_error`。

结论：当前项目名义上有 HTTP log 插件，但实际只能看到底层传输失败；业务失败、响应解析失败、HTTP 状态码异常、请求体异常都缺少可用日志。

## 创建 Space 调用链

入口在 `SiteViewController.addSpace()`：

1. 用户输入完成后先调用 `site.addSpace(name:imageId:)`，本地创建 `SpaceData`。
2. 如果 site 已上传云端，创建 `CloudSynchronizationManager` 任务：`.addSpaces(site: site, spaces: [space])`。
3. `.addSpaces` 在 `SyncOperation.getNetworkApi()` 中转换成 `.siteUpload(siteData:)`。
4. `.siteUpload` 的接口路径是 `/sitespace/sync/siteprops`。
5. 同步任务失败时只保存 `space.syncCloudError = error`，UI 再通过错误图标或弹窗显示本地化错误文案。

因此，“创建 Space 失败”并不是添加按钮直接调用独立 add-space API，而是通过同步整个 site/指定 spaces 的方式上传。

## 可疑点

`NetowrkReqeustApi.headers` 对 `.siteUpload` 和 `.spaceUpload` 设置了：

- `Content-Encoding: gzip`
- `Accept-Encoding: gzip`

但实际 `task` 使用的是普通 `JSONEncoding.default`，原本的 gzip body 逻辑已经被注释。也就是说请求头声明 body 是 gzip，实际 body 却是未压缩 JSON。

如果服务端严格按 `Content-Encoding: gzip` 解码请求体，`.siteUpload` 可能会失败；创建 Space 正好走 `.siteUpload`，所以这是当前问题的一个高优先级排查点。

## 建议

1. 先补全 DEBUG 下的网络诊断日志，至少包含 target、method、URL、headers、请求 body 摘要、HTTP status、业务 code/message、响应 body、Moya/AFError code。
2. 对 `siteUpload`/`spaceUpload` 单独打印 body 是否实际 gzip，避免日志误导。
3. 修正 gzip 策略二选一：
   - 如果不压缩 body，就不要发送 `Content-Encoding: gzip`。
   - 如果服务端要求 gzip，就恢复 `.requestCompositeData(bodyData:gzipData,urlParameters:)` 或在 requestClosure 中实际压缩 body。
4. 扩展 `NetworkApiError` 或保留 unknown 的原始 code/message，否则 UI 和日志都会丢失服务端具体错误。
5. 创建 Space 失败时建议记录一次同步上下文：operation 类型、siteId、spaceId、spaceName、接口 path、错误 code。

