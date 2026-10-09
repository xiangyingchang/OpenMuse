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
