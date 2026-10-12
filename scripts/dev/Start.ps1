param(
    [string]$JavaHome = 'D:\develop\JAVA\jdk\ms-17.0.18',
    [string]$PythonExe = 'python',
    [switch]$SkipBuild,
    [switch]$UseLlm,
    [switch]$WithKnowledge,
    [switch]$WithOperations
)
$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (!$env:MAVEN_OPTS) { $env:MAVEN_OPTS = '-Xmx256m -XX:ActiveProcessorCount=2' }
$taskIntegrationRoot = $taskProjectRoot
if (!$PSBoundParameters.ContainsKey('PythonExe') -and (Test-Path -LiteralPath (Join-Path $taskIntegrationRoot '.venv\Scripts\python.exe'))) {
    $PythonExe = Join-Path $taskIntegrationRoot '.venv\Scripts\python.exe'
}
$taskJavaRoot = Join-Path $taskIntegrationRoot 'backend\java\tingshu-parent'
$taskPythonRoot = Join-Path $taskIntegrationRoot 'python\assistant'
$taskFrontendRoot = Join-Path $taskIntegrationRoot 'frontend\uniapp'
$taskRuntimeRoot = Join-Path $taskIntegrationRoot '.runtime'
New-Item -ItemType Directory -Path $taskRuntimeRoot -Force | Out-Null

if (!(Test-Path -LiteralPath (Join-Path $JavaHome 'bin\java.exe'))) { throw '未找到 JDK 17，请传入 -JavaHome' }
$env:JAVA_HOME = $JavaHome
$env:PATH = "$JavaHome\bin;$env:PATH"
$env:LISTENING_DEMO_LOGIN = 'true'
$env:LISTENING_USE_LLM = if ($UseLlm) { 'true' } else { 'false' }
$env:LISTENING_ORDER_URL = 'http://127.0.0.1:18204'
$env:LISTENING_CONTENT_URL = 'http://127.0.0.1:18202'
$env:PYTHONUTF8 = '1'
$taskPythonPaths = @('shared','assistant','knowledge','operations') | ForEach-Object { Join-Path $taskIntegrationRoot "python\$_" }
$env:PYTHONPATH = $taskPythonPaths -join [IO.Path]::PathSeparator
if ($WithKnowledge) { $env:LISTENING_KNOWLEDGE_URL = 'http://127.0.0.1:18084' }
if ($WithOperations) {
    $env:LISTENING_OPERATIONS_URL = 'http://127.0.0.1:18085'
}

Push-Location $taskIntegrationRoot
try {
    docker info --format '{{.ServerVersion}}' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '请先启动 Docker Desktop' }
    docker compose --progress plain up -d --pull missing --wait --wait-timeout 180
    if ($LASTEXITCODE -ne 0) { throw '数据库启动失败，请检查 docker compose logs' }
} finally { Pop-Location }

& $PythonExe (Join-Path $taskIntegrationRoot 'scripts\setup\Provision.py')
if ($LASTEXITCODE -ne 0) { throw '业务表与统计视图初始化失败' }
$env:LISTENING_PAYMENT_CALLBACK_SECRET = (Get-Content -LiteralPath (Join-Path $taskRuntimeRoot 'payment-callback-key') -Raw).Trim()

if (!$SkipBuild) {
    Push-Location $taskJavaRoot
    try {
        mvn -B -ntp -pl 'service/service-user,service/service-order,service/service-album' -am -Plocal-listening '-DskipTests' package
        if ($LASTEXITCODE -ne 0) { throw 'Java 构建失败' }
    } finally { Pop-Location }
}
if (!$SkipBuild -or !(Test-Path -LiteralPath (Join-Path $taskFrontendRoot 'dist\h5\index.html'))) {
    Push-Location $taskFrontendRoot
    try {
        if (Test-Path -LiteralPath 'D:\develop\node\node.exe') { $env:PATH = "D:\develop\node;$env:PATH" }
        if (!(Test-Path -LiteralPath 'node_modules\@dcloudio\vite-plugin-uni\bin\uni.js')) {
            npm.cmd ci --no-audit --no-fund
            if ($LASTEXITCODE -ne 0) { throw '前端依赖安装失败' }
        }
        $env:NODE_OPTIONS = '--max-old-space-size=512'
        npm.cmd run build:h5
        if ($LASTEXITCODE -ne 0) { throw '听见 H5 构建失败' }
    } finally { Pop-Location }
}

function Test-TaskEndpoint([string]$Url) {
    try { Invoke-RestMethod -Uri $Url -TimeoutSec 3 | Out-Null; return $true } catch { return $false }
}
$taskPids = @{}
$taskPidFile = Join-Path $taskRuntimeRoot 'processes.json'
if (Test-Path -LiteralPath $taskPidFile) {
    $taskPrevious = Get-Content -LiteralPath $taskPidFile -Raw | ConvertFrom-Json
    foreach ($taskProperty in $taskPrevious.PSObject.Properties) { $taskPids[$taskProperty.Name] = $taskProperty.Value }
}
$taskReadyUrls = @('http://127.0.0.1:18201/v3/api-docs', 'http://127.0.0.1:18202/v3/api-docs', 'http://127.0.0.1:18204/v3/api-docs', 'http://127.0.0.1:18083/health')
foreach ($taskAux in @(
    @{ Enabled=$WithKnowledge; Name='knowledge'; Port=18084; Module='app.listening.service:app'; Folder='python\knowledge' },
    @{ Enabled=$WithOperations; Name='operations'; Port=18085; Module='listening.service:app'; Folder='python\operations' }
)) {
    if ($taskAux.Enabled) {
        $taskAuxUrl = "http://127.0.0.1:$($taskAux.Port)/health"
        $taskReadyUrls += $taskAuxUrl
        if (!(Test-TaskEndpoint $taskAuxUrl)) {
            $taskAuxProcess = Start-Process -FilePath $PythonExe -ArgumentList @('-m','uvicorn',$taskAux.Module,'--host','127.0.0.1','--port',([string]$taskAux.Port)) -WorkingDirectory (Join-Path $taskIntegrationRoot $taskAux.Folder) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRuntimeRoot "$($taskAux.Name).log") -RedirectStandardError (Join-Path $taskRuntimeRoot "$($taskAux.Name)-error.log")
            $taskPids[$taskAux.Name] = $taskAuxProcess.Id
        }
    }
}
if (!(Test-TaskEndpoint 'http://127.0.0.1:18201/v3/api-docs')) {
    $taskJar = Join-Path $taskJavaRoot 'service\service-user\target\service-user.jar'
    $taskJava = Start-Process -FilePath (Join-Path $JavaHome 'bin\java.exe') -ArgumentList @(
        '-Xms32m','-Xmx192m','-Xss512k','-XX:ActiveProcessorCount=2','-XX:MaxMetaspaceSize=160m','-XX:TieredStopAtLevel=1','-XX:ReservedCodeCacheSize=48m','-Dfile.encoding=UTF-8', '-jar', ('"' + $taskJar + '"'),
        '--spring.profiles.active=local', '--spring.cloud.bootstrap.enabled=false',
        '--spring.cloud.nacos.config.enabled=false', '--spring.cloud.nacos.discovery.enabled=false', '--spring.cloud.bus.enabled=false'
    ) -WorkingDirectory $taskJavaRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRuntimeRoot 'user.log') -RedirectStandardError (Join-Path $taskRuntimeRoot 'user-error.log')
    $taskPids['java'] = $taskJava.Id
}
if (!(Test-TaskEndpoint 'http://127.0.0.1:18202/v3/api-docs')) {
    $taskContentJar = Join-Path $taskJavaRoot 'service\service-album\target\service-album.jar'
    $taskContent = Start-Process -FilePath (Join-Path $JavaHome 'bin\java.exe') -ArgumentList @(
        '-Xms32m','-Xmx192m','-Xss512k','-XX:ActiveProcessorCount=2','-XX:MaxMetaspaceSize=160m','-XX:TieredStopAtLevel=1','-XX:ReservedCodeCacheSize=48m','-Dfile.encoding=UTF-8', '-jar', ('"' + $taskContentJar + '"'),
        '--spring.profiles.active=local', '--spring.cloud.bootstrap.enabled=false',
        '--spring.cloud.nacos.config.enabled=false', '--spring.cloud.nacos.discovery.enabled=false', '--spring.cloud.bus.enabled=false'
    ) -WorkingDirectory $taskJavaRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRuntimeRoot 'content.log') -RedirectStandardError (Join-Path $taskRuntimeRoot 'content-error.log')
    $taskPids['content'] = $taskContent.Id
}
if (!(Test-TaskEndpoint 'http://127.0.0.1:18083/health')) {
    $taskPython = Start-Process -FilePath $PythonExe -ArgumentList @('-m','uvicorn','atguigu.listening.app:app','--host','127.0.0.1','--port','18083') -WorkingDirectory $taskPythonRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRuntimeRoot 'assistant.log') -RedirectStandardError (Join-Path $taskRuntimeRoot 'assistant-error.log')
    $taskPids['python'] = $taskPython.Id
}
if (!(Test-TaskEndpoint 'http://127.0.0.1:18204/v3/api-docs')) {
    $taskOrderJar = Join-Path $taskJavaRoot 'service\service-order\target\service-order.jar'
    $taskOrder = Start-Process -FilePath (Join-Path $JavaHome 'bin\java.exe') -ArgumentList @(
        '-Xms32m','-Xmx192m','-Xss512k','-XX:ActiveProcessorCount=2','-XX:MaxMetaspaceSize=160m','-XX:TieredStopAtLevel=1','-XX:ReservedCodeCacheSize=48m','-Dfile.encoding=UTF-8', '-jar', ('"' + $taskOrderJar + '"'),
        '--spring.profiles.active=local', '--spring.cloud.bootstrap.enabled=false',
        '--spring.cloud.nacos.config.enabled=false', '--spring.cloud.nacos.discovery.enabled=false', '--spring.cloud.bus.enabled=false'
    ) -WorkingDirectory $taskJavaRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRuntimeRoot 'order.log') -RedirectStandardError (Join-Path $taskRuntimeRoot 'order-error.log')
    $taskPids['order'] = $taskOrder.Id
}
$taskPids | ConvertTo-Json | Set-Content -LiteralPath $taskPidFile -Encoding utf8
foreach ($taskUrl in $taskReadyUrls) {
    $taskReady = $false
    for ($taskAttempt = 0; $taskAttempt -lt 60; $taskAttempt++) {
        if (Test-TaskEndpoint $taskUrl) { $taskReady = $true; break }
        Start-Sleep -Seconds 1
    }
    if (!$taskReady) { throw "服务未就绪：$taskUrl，请检查 .runtime 日志" }
}
$taskHealth = Invoke-RestMethod -Uri 'http://127.0.0.1:18083/health' -TimeoutSec 3
if ($taskHealth.llm -ne [bool]$UseLlm) { Write-Warning '已运行服务的模型模式不同。要切换模式，请先运行 Stop.ps1，再启动。' }
# Windows venv 的 python.exe 可能是启动器；记录实际监听进程，保证停止脚本不会遗留子进程。
foreach ($taskService in @(
    @{Name='python';Port=18083;Pattern='atguigu\.listening\.app:app'},
    @{Name='knowledge';Port=18084;Pattern='app\.listening\.service:app'},
    @{Name='operations';Port=18085;Pattern='uvicorn listening\.service:app'}
)) {
    if ($taskPids.ContainsKey($taskService.Name)) {
        $taskListener = Get-NetTCPConnection -State Listen -LocalAddress '127.0.0.1' -LocalPort $taskService.Port -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($taskListener) {
            $taskListeningProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$($taskListener.OwningProcess)"
            if ($taskListeningProcess.CommandLine -notmatch $taskService.Pattern) { throw '端口进程身份不匹配，未接管' }
            if ($taskPids[$taskService.Name] -ne $taskListener.OwningProcess) {
                $taskLauncher = Get-CimInstance Win32_Process -Filter "ProcessId=$($taskPids[$taskService.Name])"
                if ($taskLauncher -and $taskLauncher.CommandLine -match $taskService.Pattern) {
                    $taskPids[$taskService.Name + 'Launcher'] = $taskLauncher.ProcessId
                }
            }
            $taskPids[$taskService.Name] = $taskListener.OwningProcess
        }
    }
}
$taskPids | ConvertTo-Json | Set-Content -LiteralPath $taskPidFile -Encoding utf8
Write-Output '服务已启动，日志位于 .runtime。浏览器打开 http://127.0.0.1:18083'
