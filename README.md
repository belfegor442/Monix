# Monix

Monix es una app nativa de observabilidad para Windows con una sola ventana, telemetria local y una superficie visual estilo CRT.

## Build

El build usa Zig como compilador C++ local. En esta copia de trabajo esta en `tools/zig-dist/`, pero esa carpeta no se sube al repo porque pesa demasiado. Si clonas el proyecto desde GitHub, instala Zig o coloca `zig.exe` en:

```text
tools\zig-dist\zig-x86_64-windows-0.16.0\zig.exe
```

Construir la app y el instalador:

```powershell
.\build.ps1
```

Crear paquetes listos para subir:

```powershell
.\build.ps1 -Package
```

Tambien puedes usar:

```powershell
.\package.ps1
```

## Salidas

- `build\Monix.exe`: app principal.
- `build\MonixInstaller.exe`: instalador Windows con apariencia Monix, sin shaders.
- `dist\Monix-Windows.zip`: paquete Windows listo para subir.
- `dist\Monix-Linux.zip`: paquete Linux de compatibilidad con Wine.

## Instalacion en Windows

Descomprime `Monix-Windows.zip` y ejecuta `MonixInstaller.exe`.

El instalador copia `Monix.exe`, configuracion, shader, fuentes, sonidos y archivos de runtime. Si se abre como administrador instala en Program Files; si no, instala para el usuario actual en Local AppData.

## Instalacion en Linux

Descomprime `Monix-Linux.zip` y ejecuta:

```bash
bash install-monix.sh
```

El paquete Linux instala Wine si puede, copia Monix a `~/.local/opt/monix`, crea el comando `monix` y un lanzador de escritorio.

Nota: Monix usa APIs de Windows para su telemetria. El paquete Linux es una capa de compatibilidad para ejecutar el build Windows, no un port nativo del colector.
