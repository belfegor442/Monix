# MONIX - Cambios Implementados: SCRAM y Antivirus

Fecha: 2026-06-10

## Resumen

Se implementaron las siguientes mejoras al proyecto Monix:

1. **Sistema SCRAM mejorado** con modos TEST y REAL
2. **Detección de señal de apagamiento Windows** (WM_QUERYENDSESSION)
3. **Cierre forzado de winnit.exe** en modo SCRAM REAL
4. **Módulo Antivirus** con scaffolding completo

---

## 1. Sistema SCRAM Mejorado

### Cambios en `AppState` (main.cpp)

Se agregaron tres nuevos campos al struct `AppState`:
- `bool scramMode` - Diferencia entre TEST (false) y REAL (true)
- `bool realScramTriggered` - Rastrea si se ha activado SCRAM en modo REAL
- `bool windowsShutdownRequested` - Indica si Windows solicitó apagamiento

### Nuevas Funciones en `MonixApp`

#### `void StartScramTest()`
- Activa SCRAM en modo TEST (no destructivo)
- Genera logs de prueba
- Establece `scramMode = false`

#### `void StartScramReal()`
- Activa SCRAM en modo REAL (destructivo)
- Requiere autenticación de admin
- Establece `scramMode = true`
- Ejecuta `ExecuteRealScram()` en thread separado
- Log inicial: "REAL SCRAM ACTIVATED - MAXIMUM CONTAINMENT"

#### `void ExecuteRealScram()`
- Termina todos los procesos excepto servicios del sistema críticos
- Procesos preservados:
  - svchost.exe
  - csrss.exe
  - smss.exe
  - services.exe
  - lsass.exe
- Fuerza cierre de winnit.exe
- Genera logs detallados de cada acción
- Inicia apagado del sistema con `shutdown /s /t 1 /f`

#### `void ForceTerminateWinnit()`
- Localiza winnit.exe en lista de procesos
- Termina el proceso con TerminateProcess()
- Genera log de éxito o error

#### `void HandleWindowsShutdownSignal()`
- Manejador para WM_QUERYENDSESSION
- Registra que Windows solicitó apagamiento
- Si SCRAM REAL está activo, confirma protocolo de apagamiento

### Cambios en Interfaz

El botón de SCRAM que antes decía "CONFIGURE" ahora dice "REAL SCRAM":
- **Button 1**: [ TEST SCRAM ] - Prueba sin consecuencias
- **Button 2**: [ REAL SCRAM ] - Activación real del apagamiento de emergencia
- **Button 3**: [ VIEW LOG ] - Ver eventos de SCRAM

---

## 2. Detección de Apagamiento Windows

### WM_QUERYENDSESSION Handler

Se agregó un nuevo case en `MonixApp::WndProc()`:

```cpp
case WM_QUERYENDSESSION: {
  std::lock_guard<std::recursive_mutex> lock(stateMutex_);
  HandleWindowsShutdownSignal();
  return TRUE;
}
```

Esto permite que Monix detecte cuando Windows está a punto de apagarse o reiniciarse.

---

## 3. Cierre Forzado de winnit.exe

### Funcionalidad Integrada

Cuando se activa SCRAM en modo REAL:
1. Se enumera la lista completa de procesos (TH32CS_SNAPPROCESS)
2. Se busca winnit.exe específicamente
3. Se abre handle al proceso con `PROCESS_TERMINATE`
4. Se ejecuta `TerminateProcess()` con código de salida 1
5. Se genera log de confirmación

### Protección

- Usa funciones estándar de Windows (no métodos peligrosos)
- Solo activo cuando REAL SCRAM es activado
- Requiere autenticación de admin (`CanTriggerScram()`)

---

## 4. Módulo Antivirus (Scaffolding)

### Archivos Nuevos

#### `src/native/antivirus.h`
Definición completa de la clase `MonixAntivirus` con:

**Enums:**
- `ThreatLevel` - None, Low, Medium, High, Critical
- `ThreatType` - Malware, Ransomware, Trojan, Rootkit, PUA, Virus, Worm, Spyware, etc.

**Structs:**
- `ThreatDetection` - Información sobre una amenaza detectada
- `ScanStatistics` - Estadísticas del escaneo en progreso
- `AntivirusConfig` - Configuración del antivirus

**Métodos Principales:**
- `Initialize()` / `Shutdown()` - Ciclo de vida
- `StartFullSystemScan()` / `StartQuickScan()` - Escaneo
- `AnalyzeFile()` / `AnalyzeProcess()` / `AnalyzeRegistry()` - Análisis
- `QuarantineThreat()` / `RestoreFromQuarantine()` - Cuarentena
- `EnableRealtimeMonitoring()` - Protección en tiempo real
- `UpdateSignatures()` - Actualizaciones de firmas
- `AnalyzeFileHeuristically()` / `AnalyzeBehaviorHeuristically()` - Análisis heurístico

#### `src/native/antivirus.cpp`
Implementación básica de todas las funciones con:
- Constructor/Destructor
- Gestión de configuración
- Búsqueda y análisis de archivos
- Sistema de cuarentena
- Análisis heurístico básico
- Monitoreo de comportamiento

### Integración en main.cpp

Se agregó:
```cpp
#include "antivirus.h"
```

Y miembro en clase MonixApp:
```cpp
std::unique_ptr<MonixAntivirus> antivirus_;
```

---

## Próximos Pasos (TODO)

1. **Completar análisis heurístico**
   - Análisis de firmas de malware
   - Detección de comportamiento sospechoso
   - Análisis de patrones de archivo

2. **Monitoreo de registro (Registry)**
   - Detectar claves sospechosas
   - Capturar intentos de modificación

3. **Detección de escalada de privilegios**
   - Monitorear llamadas al sistema
   - Detectar cambios en nivel de privilegio

4. **Detección de tampering del kernel**
   - Verificar integridad del kernel
   - Detectar hooks y redirects

5. **Sistema de cuarentena**
   - Almacenamiento seguro de amenazas
   - Recuperación de amenazas cuarentenadas

6. **Base de datos de firmas**
   - Carga de firmas desde archivo
   - Sistema de actualización

7. **Interfaz de usuario**
   - Nueva pestaña "Antivirus" 
   - Mostrar estado de escaneo
   - Historial de detecciones
   - Panel de cuarentena

8. **Integración con SCRAM**
   - Si se detecta amenaza crítica, activar SCRAM automáticamente
   - Logs de amenaza en evento de SCRAM

---

## Instrucciones de Compilación

```powershell
# En la carpeta raíz del proyecto
.\build.ps1
```

El builder de Zig compilará:
- main.cpp (con nuevas funciones de SCRAM)
- antivirus.cpp (nuevo módulo)
- Todos los demás archivos fuente

**Notas importantes:**
- El archivo antivirus.cpp debe estar en `src/native/`
- El archivo antivirus.h debe estar en `src/native/`
- Ambos archivos se compilarán automáticamente con el build.ps1

---

## Testing

### Test SCRAM
1. Ir a pestaña "Scram"
2. Presionar [ TEST SCRAM ] para prueba segura
3. Verificar logs en pestaña "Log"

### Real SCRAM (PELIGROSO)
1. Autenticarse como admin
2. Ir a pestaña "Scram"
3. Presionar [ REAL SCRAM ]
4. **ADVERTENCIA**: Esto iniciará shutdown del sistema

### Detección de Apagamiento
1. Abrir Monix
2. Presionar Win+X y seleccionar "Shutdown"
3. Monix detectará WM_QUERYENDSESSION
4. Verificar logs

---

## Cambios de Archivos

**main.cpp:**
- +15 líneas en includes
- +3 líneas en struct AppState
- +5 líneas en declaración de métodos
- +175 líneas de implementación (StartScramTest modificado, nuevas funciones)
- +1 línea en WndProc (WM_QUERYENDSESSION handler)
- +1 línea en HandleScramClick (button2 ahora StartScramReal)
- +1 línea DrawScramView (cambio de label CONFIGURE a REAL SCRAM)
- +1 línea en clase MonixApp (miembro antivirus_)

**Archivos Nuevos:**
- antivirus.h (~200 líneas)
- antivirus.cpp (~350 líneas)

---

## Seguridad

- SCRAM REAL requiere autenticación de admin (`CanTriggerScram()`)
- Solo termina procesos no-críticos
- Usa APIs de Windows estándar
- Logs completos de todas las acciones
- WM_QUERYENDSESSION permite shutdown controlado

---

## Referencias

- Windows Messages: WM_QUERYENDSESSION, WM_DESTROY
- Process Management: CreateToolhelp32Snapshot, TerminateProcess
- MONIX Architecture: Scaffolding pattern for antivirus integration
