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

$BasePath   = "C:\PSWindowsUpdate"
$ScriptPath = "$BasePath\Script"

foreach ($Path in @($BasePath, $LogDir, $ScriptPath)) {
    if (!(Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = "$LogDir\WU_Audit_$($env:COMPUTERNAME)_$Timestamp.log"

$OS        = Get-CimInstance -ClassName Win32_OperatingSystem
$OSCaption = $OS.Caption
$OSBuild   = $OS.BuildNumber

# ==============================================================================
# Funciones
# ==============================================================================

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
    # Requiere PowerShell 5.1 minimo. En 2012 R2 instalar WMF 5.1: https://aka.ms/wmf51download
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log "PowerShell 5.1 es requerido. Version actual: $($PSVersionTable.PSVersion)" -Level ERROR
        throw "Version de PowerShell insuficiente."
    }

    if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Log "Modulo PSWindowsUpdate no encontrado. Instalando..." -Level WARN

        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

        if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false
        }

        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($gallery -and $gallery.InstallationPolicy -ne "Trusted") {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }

        Install-Module PSWindowsUpdate -Force -Confirm:$false -SkipPublisherCheck -AllowClobber
        Write-Log "Modulo PSWindowsUpdate instalado correctamente."
    }

    Import-Module PSWindowsUpdate -Force
}

function Get-PendingRebootStatus {
    <#
        Revisa todas las ubicaciones del registro donde Windows indica
        que hay un reinicio pendiente por actualizaciones u otros cambios.
    #>
    $Motivos   = [System.Collections.Generic.List[string]]::new()
    $Pendiente = $false

    # 1. Component Based Servicing - Windows Update aplico cambios que requieren reinicio
    $CBS = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"
    if (Test-Path "$CBS\RebootPending") {
        $Motivos.Add("Windows Update - Component Based Servicing (RebootPending)")
        $Pendiente = $true
    }

    # 2. Windows Update registro reinicio requerido explicitamente
    $WU = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"
    if (Test-Path "$WU\RebootRequired") {
        $Motivos.Add("Windows Update - Auto Update (RebootRequired)")
        $Pendiente = $true
    }

    # 3. Archivos en uso que seran reemplazados al reiniciar
    $PFR    = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $PFRVal = Get-ItemProperty -Path $PFR -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($PFRVal -and $PFRVal.PendingFileRenameOperations) {
        $Motivos.Add("Archivos pendientes de reemplazar al reiniciar (PendingFileRenameOperations)")
        $Pendiente = $true
    }

    # 4. Instalacion de software (MSI) dejo reinicio pendiente
    $SW = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress"
    if (Test-Path $SW) {
        $Motivos.Add("Instalacion de software en progreso (MSI InProgress)")
        $Pendiente = $true
    }

    # 5. Servicios de Windows Update pendientes de registrar
    $SvcPending = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending"
    if (Test-Path $SvcPending) {
        $Motivos.Add("Servicios de Windows Update pendientes de registrar")
        $Pendiente = $true
    }

    # 6. SCCM / ConfigMgr requiere reinicio
    $SCCM = "HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData"
    if (Test-Path $SCCM) {
        $Motivos.Add("SCCM / Configuration Manager requiere reinicio")
        $Pendiente = $true
    }

    return [PSCustomObject]@{
        Pendiente = $Pendiente
        Motivos   = $Motivos
    }
}

# ==============================================================================
# Encabezado
# ==============================================================================

$OSLabel = Get-OSVersion

@"
=========================================================================
  AUDITORIA WINDOWS UPDATE - SOLO CONSULTA (NO INSTALA)
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
Write-Host "  AUDITORIA WINDOWS UPDATE  |  $($env:COMPUTERNAME)  |  $OSLabel" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan

# ==============================================================================
# Ultimo KB instalado
# ==============================================================================

Write-Log "ULTIMO PARCHE (KB) INSTALADO" -Level SECTION

try {
    $AllHotfixes = Get-HotFix | Where-Object { $_.InstalledOn -ne $null } |
                   Sort-Object InstalledOn -Descending

    if ($AllHotfixes) {
        $Last = $AllHotfixes | Select-Object -First 1
        $Report = @"

  KB           : $($Last.HotFixID)
  Tipo         : $($Last.Description)
  Instalado    : $($Last.InstalledOn.ToString("yyyy-MM-dd"))
  Instalado por: $($Last.InstalledBy)
"@
        Write-Log $Report
        Write-Log "`n  Ultimos 5 parches instalados:" -Level INFO
        $AllHotfixes | Select-Object -First 5 |
            Select-Object HotFixID, Description,
                @{N="InstalledOn";E={$_.InstalledOn.ToString("yyyy-MM-dd")}},
                InstalledBy |
            Format-Table -AutoSize |
            Out-String |
            Out-File -FilePath $LogFile -Append -Encoding UTF8
    }
    else {
        Write-Log "No se encontraron parches registrados." -Level WARN
    }
}
catch {
    Write-Log "Error al obtener historial de HotFix: $($_.Exception.Message)" -Level ERROR
}

# ==============================================================================
# Estado de reinicio pendiente
# ==============================================================================

Write-Log "ESTADO DE REINICIO PENDIENTE" -Level SECTION

try {
    $RebootStatus = Get-PendingRebootStatus

    if ($RebootStatus.Pendiente) {
        Write-Log "  REINICIO PENDIENTE: SI" -Level WARN
        Write-Log "  Motivo(s) detectado(s):" -Level WARN
        foreach ($Motivo in $RebootStatus.Motivos) {
            Write-Log "    - $Motivo" -Level WARN
        }
        Write-Log "  Al reiniciar el servidor se aplicaran los cambios pendientes." -Level WARN
        Write-Host ""
        Write-Host "  *** ESTE SERVIDOR REQUIERE REINICIO ***" -ForegroundColor Red
    }
    else {
        Write-Log "  REINICIO PENDIENTE: NO" -Level INFO
        Write-Log "  El servidor no requiere reinicio en este momento." -Level INFO
        Write-Host ""
        Write-Host "  Sin reinicio pendiente." -ForegroundColor Green
    }
}
catch {
    Write-Log "Error al verificar estado de reinicio: $($_.Exception.Message)" -Level ERROR
}

# ==============================================================================
# Actualizaciones de seguridad pendientes
# ==============================================================================

Write-Log "ACTUALIZACIONES PENDIENTES (SOLO LECTURA)" -Level SECTION

try {
    Ensure-PSWindowsUpdate

    Write-Log "  Consultando Windows Update... (puede tardar varios minutos)" -Level INFO

    $AllUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop

    if ($AllUpdates) {
        # @() garantiza array aunque Where-Object no encuentre coincidencias
        $SecurityUpdates = @($AllUpdates | Where-Object {
            $_.Title      -match "Security|Cumulative|Rollup" -or
            $_.Categories -match "Security Updates"
        })

        Write-Log "`n  Total de actualizaciones disponibles: $($AllUpdates.Count)" -Level INFO
        $AllUpdates |
            Select-Object KB, Size,
                @{N="Titulo";E={$_.Title.Substring(0, [Math]::Min(70, $_.Title.Length))}} |
            Format-Table -AutoSize -Wrap |
            Out-String |
            Out-File -FilePath $LogFile -Append -Encoding UTF8

        Write-Log "`n  Actualizaciones de SEGURIDAD pendientes: $($SecurityUpdates.Count)" -Level INFO

        if ($SecurityUpdates.Count -gt 0) {
            $SecurityUpdates |
                Select-Object KB, Size,
                    @{N="Titulo";E={$_.Title.Substring(0, [Math]::Min(70, $_.Title.Length))}} |
                Format-Table -AutoSize -Wrap |
                Out-String |
                Out-File -FilePath $LogFile -Append -Encoding UTF8

            Write-Host ""
            Write-Host "  HAY $($SecurityUpdates.Count) ACTUALIZACION(ES) DE SEGURIDAD PENDIENTE(S)" `
                -ForegroundColor Yellow
        }
        else {
            Write-Log "  No hay actualizaciones de seguridad pendientes." -Level INFO
            Write-Host "  Sin actualizaciones de seguridad pendientes." -ForegroundColor Green
        }
    }
    else {
        Write-Log "  El servidor esta al dia. No hay actualizaciones disponibles." -Level INFO
        Write-Host "  Servidor al dia." -ForegroundColor Green
    }
}
catch {
    Write-Log "Error al consultar Windows Update: $($_.Exception.Message)" -Level ERROR
    Write-Log "Verifique conectividad con WSUS o Internet." -Level WARN
}

# ==============================================================================
# Fin
# ==============================================================================

@"

=========================================================================
  Script finalizado: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
=========================================================================
"@ | Out-File -FilePath $LogFile -Append -Encoding UTF8

Write-Host ""
Write-Host "  Log guardado en:" -ForegroundColor Cyan
Write-Host "  $LogFile" -ForegroundColor Green
Write-Host ""