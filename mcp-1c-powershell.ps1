# MCP Server ��� 1� �� PowerShell
# ������������ MCP ������� � ����������� �� � HTTP ������� � 1�

param(
    [string]$BaseUrl = "",
    [string]$Method = "",
    [string]$Arguments = "",
    [switch]$Initialize,
    [switch]$ListTools,
    [switch]$Help
)

# ��������� ��������� ��� ���������� ������ � �������� ���������
$OutputEncoding          = [Text.Encoding]::UTF8
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding= [Text.Encoding]::UTF8   # ������� ��� �������

# �������������� ��������� ��� Windows PowerShell
if ($PSVersionTable.PSVersion.Major -lt 6) {
    $PSDefaultParameterValues['*:Encoding'] = 'utf8'
}

# ������������
$Global:MCPConfig = @{
    BaseUrl = $BaseUrl
    ServerInfo = @{
        name = "1C-MCP-Server-PowerShell"
        version = "1.0.0"
    }
    Tools = @()
}

# ���� ��� ����������� ������ ������ (��������� ������ vs stdio)
$Global:IsStdioMode = $false

# ������� ��� ����������� (� stderr ���� stdio �����)
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    if ($Global:IsStdioMode) {
        # � stdio ������ ��� ���� ���������� � stderr � ���������� ����������
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("[$Level] $Message`n")
        [Console]::OpenStandardError().Write($bytes, 0, $bytes.Length)
    } else {
        # � ��������� ������ ����� ������������ ������� �����
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

# ������� ��� HTTP �������� � 1�
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
            # ���� ��������� ContentType ��� ���������� UTF-8 ��������� ���� ������� � ������ ������� PowerShell
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

# ������������� - ��������� ������ ������������ �� 1�
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

# ��������� ������ ������������
function Get-MCPTools {
    if ($Global:MCPConfig.Tools.Count -eq 0) {
        Initialize-MCPServer | Out-Null
    }
    
    return @{ tools = $Global:MCPConfig.Tools }
}

# ����� ����������� 1�
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

# ��������� MCP JSON-RPC �������
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

# ��������� ��������� ������
function Handle-CommandLine {
    if ($Help) {
        Write-Host @"
MCP Server ��� 1� �� PowerShell

�������������:
  .\mcp-1c-powershell.ps1 -Initialize
  .\mcp-1c-powershell.ps1 -ListTools
  .\mcp-1c-powershell.ps1 -Method "get_metadata_structure" -Arguments '{"object_type":"�����������"}'
  
���������:
  -BaseUrl       URL ���� 1�
  -Initialize    ������������� �������
  -ListTools     �������� ������ ��������� ������������
  -Method        ��� ������ ��� ������
  -Arguments     ��������� � JSON �������
  -Help          �������� ��� �������
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

# �������� �������
function Main {
    # ���� ���� ��������� ��������� ������, ������������ ��
    if ($Initialize -or $ListTools -or $Method -or $Help) {
        Handle-CommandLine
        return
    }
    
    # ����� JSON-RPC ����� stdin/stdout
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

# ������
Main 