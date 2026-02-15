# SogouBlock

**一键封锁搜狗输入法所有联网行为，保护个人隐私。**

---

## 背景

搜狗输入法（16.1.0.3097）以"输入法"名义安装，实际部署 **41个可执行程序**，包括：

- 截图工具、人脸识别工具
- 后台下载器、云同步上传程序
- 游戏中心、广告推送程序
- 崩溃上报、用户数据反馈上传

安装完成后，在用户**未登录、未主动操作**的情况下，自动连接 20 余个外部服务器 IP，使用 HTTPS 加密传输，内容无法审查。

经实测，该软件在域名被封锁后，会**主动切换为硬编码 IP 直连服务器**，具有明显的反检测行为。

---

## 脚本效果

| 封锁措施 | 说明 |
|---------|------|
| Windows 防火墙规则 | 封锁搜狗所有 exe 的出入站流量 |
| 执行权限禁止 | 危险进程无法启动，即使防火墙失效也无法运行 |
| Hosts 域名拦截 | 13 个搜狗域名重定向至本地 |
| 服务禁用 | 搜狗后台服务设为禁用 |
| 计划任务禁用 | 搜狗定时联网任务全部禁止 |

**保留 `SogouImeBroker.exe`（输入法核心进程），打字功能正常使用。**

---

## 使用方法

### 方法一：右键运行（推荐普通用户）

1. 下载 `SogouBlock.ps1`
2. 右键点击文件
3. 选择 **「以管理员身份运行」**
4. 等待执行完成，看到 `DONE!` 即成功

### 方法二：命令行运行

以**管理员身份**打开 PowerShell，执行：

```powershell
powershell.exe ".\SogouBlock.ps1"
```

---

## 执行结果示例

```
==================================================
  Sogou Input Method Network Block Tool
==================================================

[1/6] Finding Sogou installation path...
  Found: D:\install\recreation\搜狗输入法\SogouInput

[2/6] Enabling Windows Firewall...
  Firewall enabled.

[3/6] Setting firewall rules...
  Firewall: blocked 49 executables.

[4/6] Denying execute permission on dangerous processes...
  Denied execute on 48 processes.

[5/6] Blocking Sogou domains in Hosts file...
  Added 13 domain blocks.

[6/6] Disabling Sogou services and tasks...
  Disabled 1 services, 0 scheduled tasks.

==================================================
  DONE! Sogou is now blocked from the internet.
  Typing function remains working normally.
==================================================

Summary:
  Firewall rules : 98
  Hosts entries  : 13
  Services       : 1 disabled
  Tasks          : 0 disabled
```

---

## 注意事项

- **需要管理员权限**，否则防火墙规则和 Hosts 修改无法生效
- 脚本会**自动搜索**搜狗安装路径，支持任意盘符和自定义安装目录
- 如果使用 **Clash / V2Ray 等代理软件**，需额外在代理配置中添加搜狗域名的 REJECT 规则：
  ```yaml
  # Clash 规则示例
  - DOMAIN-SUFFIX,sogou.com,REJECT
  - DOMAIN-SUFFIX,sogoucdn.com,REJECT
  ```
- 搜狗**更新后**如有新增程序，重新运行脚本即可

---

## 技术细节

脚本依次执行以下操作：

1. 从注册表 `HKLM:\SOFTWARE\WOW6432Node\SogouInput` 读取安装路径，找不到则搜索常见目录，最后全盘扫描
2. 通过注册表强制开启 Windows 防火墙服务（`MpsSvc`）
3. 使用 COM 接口（`HNetCfg.FwPolicy2`）添加防火墙规则，兼容无 `NetSecurity` 模块的精简系统
4. 剥夺危险进程的 `ExecuteFile` 权限（`Everyone: Deny`）
5. 停止 DNS Client 服务后写入 Hosts，避免文件占用冲突
6. 枚举并禁用所有搜狗相关 Windows 服务和计划任务

MIT
