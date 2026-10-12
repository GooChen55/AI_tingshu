# 听见 · 智能听书平台

[![CI](https://github.com/GooChen55/AI_tingshu/actions/workflows/ci.yml/badge.svg)](https://github.com/GooChen55/AI_tingshu/actions/workflows/ci.yml)

Java 17 · Spring Boot · Vue 3 / UniApp · FastAPI · RAG · Agent · MySQL / Redis / MongoDB

[快速启动](#快速启动) · [文档目录](docs/README.md) · [开发与贡献](docs/开发与贡献.md) · [来源与授权](docs/来源与第三方说明.md)

听见将音频收听、个人业务助手、知识问答和运营管理放在同一平台中。Java 负责身份、内容、订单与售后事务，Python 负责模型工具编排、检索和受控数据查询，UniApp/Vue 提供用户端，管理台提供审核与模型配置。

## 核心功能

- **收听与账号**：注册登录、分类与书名搜索、专辑详情、分页章节、播放与拖动、进度保存及恢复。本地示例音频支持 HTTP Range。
- **个人助手**：查询会员、进度、订单与售后，会话绑定认证用户并持久化。模型仅选择查询工具，不能提交交易或执行审核。
- **页面内交互**：全局悬浮入口打开听见助手，小窗与全屏共享会话和草稿，跨页面使用时音频继续播放。Enter 发送，Shift+Enter 换行，Esc 退出全屏或关闭小窗。
- **知识问答**：12 份资料、120 个片段，向量与 BM25 检索经 RRF 融合；核验片段 ID 和逐字引用，提供可展开的原文证据。
- **运营问数**：六个聚合视图、指标目录、SQL AST 白名单、数据库只读权限与审计；限制单视图、100 行、3 秒执行时间。
- **订单与售后**：服务端定价、幂等下单、15 分钟超时关闭、支付回调校验、售后草稿确认与审核、持久化退款任务及租约重试。支付和退款使用本地模拟渠道，不涉及真实资金，也不授予付费播放权益。
- **权限与治理**：独立管理会话、Java RBAC、角色撤销立即生效、跨服务请求编号、AI 并发与频率限制、超时取消、带校验和的 SQL 迁移。

## 快速启动

需要 Docker Desktop、JDK 17、Maven、Node.js/npm、Python 3.12+。在项目根目录执行，JavaHome 改为本机的 JDK 17 路径：

```powershell
git clone https://github.com/GooChen55/AI_tingshu.git
cd AI_tingshu
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements/requirements.lock.txt
.\Start.ps1 -JavaHome 'D:\develop\JAVA\jdk\ms-17.0.18' -UseLlm -WithKnowledge -WithOperations
```

首次启动初始化独立数据库卷并构建 Java 与 H5。后续启动可加 `-SkipBuild`；修改源码后先停止，再重新构建和启动。停止保留数据库卷。

仓库当前为私有，需要已获授权的 GitHub 账号。首次演示可以先运行 `.\Start.ps1 -JavaHome '你的 JDK 17 路径'` 使用规则查询，再配置模型并开启完整 AI 服务。

```powershell
.\Stop.ps1
.\Start.ps1 -SkipBuild -UseLlm -WithKnowledge -WithOperations
```

| 入口 | 地址 |
| --- | --- |
| 用户端 | http://127.0.0.1:18083/listen/ |
| 管理台 | http://127.0.0.1:18083/admin |
| 助手工作台 | http://127.0.0.1:18083/ |

可注册普通听友。初始管理员为 `admin`，随机密码保存在 `.runtime/admin-password`；重启不重置已有密码和角色。所有服务仅监听本机回环地址。

## 模型配置

管理员在管理台分别配置对话与向量供应商、API 根地址、模型名称和密钥，先测试，再保存。对话测试检查回答、JSON 和工具调用；向量测试检查实际维度。连接测试产生少量供应商用量，保存不代表测试通过。

支持百炼、DeepSeek 对话、硅基流动、OpenAI 和自定义兼容接口。对话和向量可以使用不同供应商；支持自定义维度的模型开启 `dimensions`，固定维度模型关闭该项并填写真实维度。向量接口、模型或维度变化后构建对应索引。

密钥使用当前 Windows 用户的 DPAPI 加密，保存在 `.runtime/model-settings.json`，不回显、不写入浏览器存储。供应商和地址不变时，留空保留原密钥；切换地址或供应商须提供新密钥。复制到其他机器或 Windows 用户后需重新配置密钥。未保存配置时读取项目 `.env`，参考 `.env.example`。

不传 `-UseLlm` 可使用明确标记的规则查询；不传 `-WithKnowledge` 使用关键词检索。已保存的 DeepSeek `deepseek-flash` 与百炼 `text-embedding-v3`（1024 维）曾通过真实连接及三类业务入口验证，演示前可重新运行兼容检查。

## 工程与服务

| 目录 | 职责 |
| --- | --- |
| backend/java/tingshu-parent | Java 用户、内容与订单服务及公共模块 |
| frontend/uniapp | 用户端 UniApp/Vue 工程 |
| python/assistant、knowledge、operations | 助手、知识检索、运营问数 |
| python/shared | 认证、模型配置、请求追踪与项目路径 |
| scripts/dev、setup、verify | 开发入口、初始化、验收和评测 |
| requirements、data、sql、tests、web、docs | 依赖、资料、迁移、测试、工作台与文档 |

Java 服务端口为 18201/18202/18204，Python 服务为 18083/18084/18085，MySQL/Redis/MongoDB 为 23316/16389/17018。内容服务使用 `local-listening` 构建配置；启动不依赖其他项目目录。

MySQL 默认使用 23316，避开本机 Windows 保留端口范围。需要自选端口时，在同一 PowerShell 会话中先设置 `$env:LISTENING_DB_PORT='端口号'`，再执行启动和验收命令；数据库卷保持不变。

`.runtime` 包含密钥、私有账号、会话和日志，`.venv` 包含本机环境，两者不要提交或公开。迁移文件执行后不得修改；数据库变更应增加新迁移。

## 验证

```powershell
.\scripts\dev\Doctor.ps1
.\scripts\dev\VerifyAll.ps1
.\.venv\Scripts\python.exe scripts\verify\VerifyModelCompatibility.py
```

统一验收执行 Python 与 Java 单测及健康检查。`VerifyAll.ps1 -Live` 还运行真实模型、固定评测与模拟交易重启验收，产生 API 用量并创建标记为测试的业务数据。

已有验收记录：Python 99 项、Java 36 项单测通过；身份/审核/播放实际服务 34 项，本地交易实际服务 30 项；固定真实向量召回 16/16、Agent 契约场景 20/20。固定小样本结果不代表通用准确率或生产性能。报告与复现前提见 [部署与验收](docs/部署与验收.md)。

## 使用范围

目前提供本机 H5 演示，未验证微信小程序或 App 真机发布。真实资金支付退款、云点播、付费播放授权、生产网关与身份治理尚未接入。初始化数据中的大量声音共用一个远程示例地址，不能视为对应的有效音源；当前可靠播放示例为两条本地 MP3，其他内容需要接入有效音频。

进一步阅读：[项目结构](docs/项目结构.md)、[架构与演示](docs/架构与演示.md)、[支付退款设计](docs/支付退款设计与接口.md)、[求职项目提纲](docs/求职项目提纲.md)、[演示视频说明](docs/演示/演示说明.md)、[来源与第三方说明](docs/来源与第三方说明.md)。
