# MCP Server для 1С на PowerShell
# Обрабатывает MCP команды и преобразует их в HTTP запросы к 1С

param(
    [string]$BaseUrl = "",
    [string]$Method = "",
    [string]$Arguments = "",
    [switch]$Initialize,
    [switch]$ListTools,
    [switch]$Help
)

# Настройка кодировки для правильной работы с русскими символами
$OutputEncoding          = [Text.Encoding]::UTF8
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding= [Text.Encoding]::UTF8   # полезно для отладки

# Дополнительная настройка для Windows PowerShell
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $PSDefaultParameterValues['*:Encoding'] = 'utf8'
}

# Конфигурация
$Global:MCPConfig = @{
    BaseUrl = $BaseUrl
    ServerInfo = @{
        name = "1C-MCP-Server-PowerShell"
        version = "1.0.0"
    }
    Tools = @()
}

# Флаг для определения режима работы (командная строка vs stdio)
$Global:IsStdioMode = $false

# Функция для логирования (в stderr если stdio режим)
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    if ($Global:IsStdioMode) {
        # В stdio режиме все логи направляем в stderr с правильной кодировкой
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("[$Level] $Message`n")
        [Console]::OpenStandardError().Write($bytes, 0, $bytes.Length)
    } else {
        # В командной строке можем использовать цветной вывод
        $color = switch ($Level) {
            "Error" { "Red" }
            "Warning" { "Yellow" }
            "Success" { "Green" }
            "Info" { "Gray" }
            "Debug" { "Cyan" }
            default { "White" }
        }
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

# Функция для HTTP запросов к 1С
function Invoke-1CRequest {
    param(
        [string]$Url,
        [string]$Method = "GET",
        [hashtable]$Body = $null
    )
    
    try {
        $headers = @{
            "Accept" = "application/json; charset=utf-8"
        }
        
        if ($Method -eq "POST" -and $Body) {
            $jsonBody = ($Body | ConvertTo-Json -Depth 10)
            # Явно указываем ContentType для правильной UTF-8 кодировки тела запроса в старых версиях PowerShell
            $response = Invoke-RestMethod -Uri $Url -Method POST -Body $jsonBody -Headers $headers -ContentType "application/json; charset=utf-8"
        } else {
            $response = Invoke-RestMethod -Uri $Url -Method GET -Headers $headers
        }
        
        return $response
    }
    catch {
        throw "HTTP request failed: $($_.Exception.Message)"
    }
}

# Инициализация - получение списка инструментов от 1С
function Initialize-MCPServer {
    try {
        $toolsUrl = "$($Global:MCPConfig.BaseUrl)/tools"
        $response = Invoke-1CRequest -Url $toolsUrl -Method "GET"
        
        if ($response -and $response.tools) {
            $Global:MCPConfig.Tools = $response.tools
        }
        
        return @{
            protocolVersion = "2024-11-05"
            capabilities = @{
                tools = @{ listChanged = $false }
                resources = @{ subscribe = $false; listChanged = $false }
            }
            serverInfo = $Global:MCPConfig.ServerInfo
        }
    }
    catch {
        throw "Failed to initialize MCP server: $($_.Exception.Message)"
    }
}

# Получение списка инструментов
function Get-MCPTools {
    if ($Global:MCPConfig.Tools.Count -eq 0) {
        Initialize-MCPServer | Out-Null
    }
    
    return @{ tools = $Global:MCPConfig.Tools }
}

# Вызов инструмента 1С
function Invoke-MCPTool {
    param(
        [string]$ToolName,
        $ToolArguments = $null
    )
    
    try {
        $callUrl = "$($Global:MCPConfig.BaseUrl)/call"
        $requestBody = @{
            name = $ToolName
            arguments = if ($ToolArguments) { $ToolArguments } else { @{} }
        }
        
        $response = Invoke-1CRequest -Url $callUrl -Method "POST" -Body $requestBody
        
        return @{
            content = @(
                @{
                    type = "text"
                    text = ($response | ConvertTo-Json -Depth 10)
                }
            )
        }
    }
    catch {
        throw "Tool call failed: $($_.Exception.Message)"
    }
}

# Обработка MCP JSON-RPC запроса
function Handle-MCPRequest {
    param($Request)
    
    switch ($Request.method) {
        "initialize" { return Initialize-MCPServer }
        "tools/list" { return Get-MCPTools }
        "tools/call" { return Invoke-MCPTool -ToolName $Request.params.name -ToolArguments $Request.params.arguments }
        "resources/list" { return @{ resources = @() } }
        default { throw "Unknown method: $($Request.method)" }
    }
}

# Обработка командной строки
function Handle-CommandLine {
    if ($Help) {
        Write-Host @"
MCP Server для 1С на PowerShell

Использование:
  .\mcp-1c-powershell.ps1 -Initialize
  .\mcp-1c-powershell.ps1 -ListTools
  .\mcp-1c-powershell.ps1 -Method "get_metadata_structure" -Arguments '{"object_type":"Справочники"}'
  
Параметры:
  -BaseUrl       URL базы 1С
  -Initialize    Инициализация сервера
  -ListTools     Показать список доступных инструментов
  -Method        Имя метода для вызова
  -Arguments     Аргументы в JSON формате
  -Help          Показать эту справку
"@
        return
    }
    
    if ($Initialize) {
        $result = Initialize-MCPServer
        Write-Host ($result | ConvertTo-Json -Depth 10)
        return
    }
    
    if ($ListTools) {
        $result = Get-MCPTools
        Write-Host ($result | ConvertTo-Json -Depth 10)
        return
    }
    
    if ($Method) {
        $args = @{}
        if ($Arguments) {
            $args = $Arguments | ConvertFrom-Json
        }
        
        $result = Invoke-MCPTool -ToolName $Method -ToolArguments $args
        Write-Host ($result | ConvertTo-Json -Depth 10)
        return
    }
}

# Основная функция
function Main {
    # Если есть параметры командной строки, обрабатываем их
    if ($Initialize -or $ListTools -or $Method -or $Help) {
        Handle-CommandLine
        return
    }
    
    # Режим JSON-RPC через stdin/stdout
    while ($true) {
        try {
            $line = Read-Host
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            $request = $line | ConvertFrom-Json
            $result = Handle-MCPRequest -Request $request
            
            $response = @{
                jsonrpc = "2.0"
                id = $request.id
                result = $result
            }
            
            Write-Output ($response | ConvertTo-Json -Depth 10 -Compress)
        }
        catch {
            $errorResponse = @{
                jsonrpc = "2.0"
                id = if ($request -and $request.id) { $request.id } else { $null }
                error = @{
                    code = -32603
                    message = $_.Exception.Message
                }
            }
            
            Write-Output ($errorResponse | ConvertTo-Json -Depth 10 -Compress)
        }
    }
}

# Запуск
Main 