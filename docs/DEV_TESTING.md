# 本地开发验证

普通结构化存储和 OpenAI 兼容请求测试：

```sh
swift test
```

Pi RPC 集成测试需要本机已安装 Pi。用一个只绑定 `127.0.0.1` 的合成流式服务验证请求生命周期，不会连接真实模型或发送真实资料：

```sh
python3 Scripts/mock_openai_sse_server.py
```

在另一个终端执行：

```sh
OPENMUSE_PI_TEST_ENDPOINT=http://127.0.0.1:19876/v1 swift test --filter testPiRPCRuntimeWaitsForSettledAssistantReply
```

测试密钥固定为 `openmuse-test-token`，只用于本地夹具。用户的模型密钥不得写进脚本、测试输出或仓库。

将同一 `OPENMUSE_PI_TEST_ENDPOINT` 设为回环地址后运行完整 `swift test`，Mac Bridge 任务交接测试也会实际启动 Pi CLI：手机侧任务同步到 Mac，Mac 通过 Pi RPC 调用本机合成 SSE 服务，随后把结果与执行权同步回手机侧。测试只接受 `http://127.0.0.1`，不把固定测试密钥发往外部地址；未设置时该桥接测试使用确定性 handler。
