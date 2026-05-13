# ==============================================================================
# Desarrollado por: Cristian Omar Jiménez Sánchez
# Github: crisomarjs
# Descripción: Auditoría de Windows Update - Consulta de KBs instalados y
#              actualizaciones de seguridad pendientes (solo lectura / no instala)
# Compatibilidad: Windows Server 2012 R2, 2016, 2019, 2022, 2025
# ==============================================================================

#Requires -RunAsAdministrator

[CmdletBinding()]
param (
    [string]$LogDir = "C:\PSWindowsUpdate\Logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==============================================================================
# REGIÓN: Inicialización y estructura de carpetas
# ==============================================================================
#region Init

$BasePath   = "C:\PSWindowsUpdate"
$ScriptPath = "$BasePath\Script"

foreach ($Path in @($BasePath, $LogDir, $ScriptPath)) {
    if (!(Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

# Política de ejecución solo para esta sesión (no modifica el sistema)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Archivo de log con timestamp para no sobreescribir históricos
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = "$LogDir\WU_Audit_$($env:COMPUTERNAME)_$Timestamp.log"

# Detectar versión del SO para ajustar el comportamiento del script
$OS        = Get-CimInstance -ClassName Win32_OperatingSystem
$OSCaption = $OS.Caption
$OSBuild   = $OS.BuildNumber

#endregion

# ==============================================================================
# REGIÓN: Funciones auxiliares
# ==============================================================================
#region Functions

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SECTION")]
        [string]$Level = "INFO"
    )
    $Separator = "=" * 65
    $Line = switch ($Level) {
        "SECTION" { "`n$Separator`n$Message`n$Separator" }
        "WARN"    { "[ADVERTENCIA] $Message" }
        "ERROR"   { "[ERROR]       $Message" }
        default   { "  $Message" }
    }
    $Line | Out-File -FilePath $LogFile -Append -Encoding UTF8
    Write-Host $Line
}

function Get-OSVersion {
    switch ($OSBuild) {
        { $_ -ge 26100 } { return "Windows Server 2025" }
        { $_ -ge 20348 } { return "Windows Server 2022" }
        { $_ -ge 17763 } { return "Windows Server 2019" }
        { $_ -ge 14393 } { return "Windows Server 2016" }
        { $_ -ge 9600  } { return "Windows Server 2012 R2" }
        default           { return "Windows Server (Build $OSBuild)" }
    }
}

function Ensure-PSWindowsUpdate {
    <#
    .SYNOPSIS
        Instala PSWindowsUpdate solo si no está disponible.
        En 2012 R2, garantiza TLS 1.2 antes de descargar desde PSGallery.
    #>

    # En 2012 R2 (Build 9600) PowerShell 5.1 puede no estar presente de fábrica.
    # Verificamos la versión mínima requerida por PSWindowsUpdate.
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log "PowerShell 5.1 es requerido. Versión actual: $($PSVersionTable.PSVersion)" -Level ERROR
        Write-Log "Instale WMF 5.1 desde: https://aka.ms/wmf51download" -Level ERROR
        throw "Versión de PowerShell insuficiente."
    }

    if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Log "Módulo PSWindowsUpdate no encontrado. Instalando..." -Level WARN

        # Forzar TLS 1.2 (requerido por PSGallery, especialmente en 2012 R2)
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

        # Instalar NuGet si no existe
        if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false
        }

        # Registrar PSGallery como fuente confiable si no lo es
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($gallery -and $gallery.InstallationPolicy -ne "Trusted") {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        Install-Module PSWindowsUpdate -Force -Confirm:$false -SkipPublisherCheck -AllowClobber
        Write-Log "Módulo PSWindowsUpdate instalado correctamente."
    }

    Import-Module PSWindowsUpdate -Force
}

#endregion

# ==============================================================================
# REGIÓN: Encabezado del log
# ==============================================================================
#region Header

$OSLabel = Get-OSVersion

@"
=========================================================================
  AUDITORÍA WINDOWS UPDATE - SOLO CONSULTA (NO INSTALA)
=========================================================================
  Servidor   : $($env:COMPUTERNAME)
  SO         : $OSLabel ($OSCaption)
  Build      : $OSBuild
  Fecha/Hora : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Usuario    : $($env:USERNAME)
  Log        : $LogFile
=========================================================================
"@ | Out-File -FilePath $LogFile -Encoding UTF8

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "  AUDITORÍA WINDOWS UPDATE  |  $($env:COMPUTERNAME)  |  $OSLabel"           -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan

#endregion

# ==============================================================================
# REGIÓN: Último KB instalado
# ==============================================================================
#region LastPatch

Write-Log "ÚLTIMO PARCHE (KB) INSTALADO" -Level SECTION

try {
    $AllHotfixes = Get-HotFix | Where-Object { $_.InstalledOn -ne $null } |
                   Sort-Object InstalledOn -Descending

    if ($AllHotfixes) {
        $Last = $AllHotfixes | Select-Object -First 1
        $Report = @"

  KB          : $($Last.HotFixID)
  Tipo        : $($Last.Description)
  Instalado   : $($Last.InstalledOn.ToString("yyyy-MM-dd"))
  Instalado por: $($Last.InstalledBy)
"@
        Write-Log $Report

        # Mostrar los últimos 5 como referencia
        Write-Log "`n  Últimos 5 parches instalados:" -Level INFO
        $AllHotfixes | Select-Object -First 5 |
            Select-Object HotFixID, Description,
                @{N="InstalledOn";E={$_.InstalledOn.ToString("yyyy-MM-dd")}},
                InstalledBy |
            Format-Table -AutoSize |
            Out-String |
            Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
    else {
        Write-Log "No se encontraron parches registrados en Win32_QuickFixEngineering." -Level WARN
    }
}
catch {
    Write-Log "Error al obtener historial de HotFix: $($_.Exception.Message)" -Level ERROR
}

#endregion

# ==============================================================================
# REGIÓN: KBs pendientes de seguridad (requiere PSWindowsUpdate)
# ==============================================================================
#region PendingUpdates

Write-Log "ACTUALIZACIONES PENDIENTES (SOLO LECTURA)" -Level SECTION

try {
    Ensure-PSWindowsUpdate

    Write-Log "  Consultando Windows Update... (puede tardar varios minutos)" -Level INFO

    $AllUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop

    if ($AllUpdates) {
        # Filtrar actualizaciones de seguridad, acumulativas y rollups
        $SecurityUpdates = @($AllUpdates | Where-Object {
            $_.Title      -match "Security|Cumulative|Rollup" -or
            $_.Categories -match "Security Updates"
        })

        # Todas las actualizaciones disponibles
        Write-Log "`n  Total de actualizaciones disponibles: $($AllUpdates.Count)" -Level INFO
        $AllUpdates |
            Select-Object KB, Size,
                @{N="Título";E={$_.Title.Substring(0, [Math]::Min(70, $_.Title.Length))}} |
            Format-Table -AutoSize -Wrap |
            Out-String |
            Out-File -FilePath $LogFile -Append -Encoding UTF8

        # Solo las de seguridad
        Write-Log "`n  Actualizaciones de SEGURIDAD pendientes: $($SecurityUpdates.Count)" -Level INFO

        if ($SecurityUpdates) {
            $SecurityUpdates |
                Select-Object KB, Size,
                    @{N="Título";E={$_.Title.Substring(0, [Math]::Min(70, $_.Title.Length))}} |
                Format-Table -AutoSize -Wrap |
                Out-String |
                Out-File -FilePath $LogFile -Append -Encoding UTF8

            Write-Host ""
            Write-Host "  HAY $($SecurityUpdates.Count) ACTUALIZACIÓN(ES) DE SEGURIDAD PENDIENTE(S)" `
                -ForegroundColor Yellow
        }
        else {
            Write-Log "  No hay actualizaciones de seguridad pendientes." -Level INFO
            Write-Host "  Sin actualizaciones de seguridad pendientes." -ForegroundColor Green
        }
    }
    else {
        Write-Log "  El servidor está al día. No hay actualizaciones disponibles." -Level INFO
        Write-Host "  Servidor al día." -ForegroundColor Green
    }
}
catch {
    Write-Log "Error al consultar Windows Update: $($_.Exception.Message)" -Level ERROR
    Write-Log "Sugerencia: Verifique conectividad con el servidor WSUS o con Internet." -Level WARN
}

#endregion

# ==============================================================================
# REGIÓN: Pie del log
# ==============================================================================
#region Footer

@"

=========================================================================
  Script finalizado: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
=========================================================================
"@ | Out-File -FilePath $LogFile -Append -Encoding UTF8

Write-Host ""
Write-Host "  Log guardado en:" -ForegroundColor Cyan
Write-Host "  $LogFile" -ForegroundColor Green
Write-Host ""

#endregion