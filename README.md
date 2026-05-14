# 🛡️ Get-WindowsUpdateAudit

Script de PowerShell para auditoría de Windows Update en servidores Windows. Consulta el último KB instalado, detecta actualizaciones de seguridad pendientes y verifica si el servidor requiere reinicio — **sin instalar nada**.

---

## ✨ Características

- ✅ Muestra el último parche (KB) instalado y los 5 más recientes
- ✅ Lista todas las actualizaciones disponibles en Windows Update
- ✅ Filtra y alerta sobre actualizaciones de **seguridad pendientes**
- ✅ Detecta si el servidor tiene un **reinicio pendiente** por actualizaciones
- ✅ Genera un log con timestamp por cada ejecución
- ✅ Solo lectura — **no instala ni modifica nada**

---

## 🖥️ Compatibilidad

| Sistema Operativo       | Soportado |
|-------------------------|-----------|
| Windows Server 2012 R2  | ✅        |
| Windows Server 2016     | ✅        |
| Windows Server 2019     | ✅        |
| Windows Server 2022     | ✅        |
| Windows Server 2025     | ✅        |

---

## 🚀 Uso

### Ejecución local (en el servidor)

Abre PowerShell **como Administrador** y ejecuta:

```powershell
.\Get-WindowsUpdateAudit.ps1
```

### Ejecución con ruta de log personalizada

```powershell
.\Get-WindowsUpdateAudit.ps1 -LogDir "D:\Logs\WindowsUpdate"
```

### Ejecución remota desde otra máquina

```powershell
Invoke-Command -ComputerName "192.168.1.100" `
               -FilePath ".\Get-WindowsUpdateAudit.ps1" `
               -Credential (Get-Credential) `
               -Authentication Basic
```

---

## 📁 Estructura generada

```
C:\PSWindowsUpdate\
├── Logs\
│   ├── WU_Audit_SERVIDOR01_20260513_100057.log
│   ├── WU_Audit_SERVIDOR01_20260514_090012.log
│   └── ...
└── Script\
    └── Get-WindowsUpdateAudit.ps1
```

Cada ejecución genera un log independiente con el nombre del servidor y timestamp.

---

## 📋 Ejemplo de salida

```
==========================================================================
  AUDITORÍA WINDOWS UPDATE  |  SERVIDOR01  |  Windows Server 2022
==========================================================================

=================================================================
ÚLTIMO PARCHE (KB) INSTALADO
=================================================================
  KB           : KB5066139
  Tipo         : Security Update
  Instalado    : 2025-12-12
  Instalado por: NT AUTHORITY\SYSTEM

=================================================================
ESTADO DE REINICIO PENDIENTE
=================================================================
[ADVERTENCIA] REINICIO PENDIENTE: SI
[ADVERTENCIA]   - Windows Update - Auto Update (RebootRequired)
*** ESTE SERVIDOR REQUIERE REINICIO ***

=================================================================
ACTUALIZACIONES PENDIENTES (SOLO LECTURA)
=================================================================
  Total de actualizaciones disponibles: 4
  Actualizaciones de SEGURIDAD pendientes: 2

  HAY 2 ACTUALIZACIÓN(ES) DE SEGURIDAD PENDIENTE(S)
```

---

## 🔍 Detección de reinicio pendiente

El script verifica **6 ubicaciones del registro** de Windows:

| # | Ubicación | Qué indica |
|---|-----------|------------|
| 1 | `CBS\RebootPending` | Windows Update aplicó cambios que requieren reinicio |
| 2 | `Auto Update\RebootRequired` | Reinicio requerido explícitamente por Windows Update |
| 3 | `PendingFileRenameOperations` | Archivos en uso que serán reemplazados al reiniciar |
| 4 | `Installer\InProgress` | Instalación MSI pendiente de completar |
| 5 | `WU Services\Pending` | Servicios de Windows Update por registrar |
| 6 | `SCCM RebootData` | SCCM / Configuration Manager requiere reinicio |

---

## ⚙️ Requisitos

- PowerShell 5.1+
- Ejecutar como **Administrador**
- Acceso a Internet o WSUS para consultar actualizaciones disponibles
- Módulo `PSWindowsUpdate` (se instala automáticamente si no está presente)

---

## 📦 Módulo PSWindowsUpdate

Si el módulo no está instalado, el script lo descarga automáticamente desde PowerShell Gallery. Requiere:

- NuGet como proveedor de paquetes
- TLS 1.2 habilitado (se configura automáticamente)
- Acceso a `https://www.powershellgallery.com`

---

## 📝 Parámetros

| Parámetro | Tipo   | Default                   | Descripción                        |
|-----------|--------|---------------------------|------------------------------------|
| `-LogDir` | String | `C:\PSWindowsUpdate\Logs` | Ruta donde se guardan los logs     |

---

## ⚠️ Notas de seguridad

Este script es de **solo lectura**. No instala, no modifica configuraciones del sistema ni reinicia servidores. Está diseñado para auditoría e inventario de parches.

Para ejecución remota en entornos de producción se recomienda usar **WinRM con HTTPS** (puerto 5986) en lugar de HTTP plano.

---

## 👨‍💻 Autor

**Cristian Omar Jiménez Sánchez**  
GitHub: [@crisomarjs](https://github.com/crisomarjs)

---
