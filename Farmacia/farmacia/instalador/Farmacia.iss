; =============================================================
; Farmacia.iss — instalador de Farmacia para Windows
;
; NO compiles este archivo a mano: ejecuta preparar.ps1
; (genera config.iss y staging\servidor\ antes de esto).
;
; Que instala en la PC destino:
;   1. PostgreSQL 17 en silencio + BD "farmacia"
;   2. Ollama en silencio
;   3. Reglas de firewall para 8080 (API) y 8081 (web/QR)
;   4. El servidor (farmacia_server.exe), la web y la app de
;      escritorio, con acceso directo "Farmacia"
; =============================================================

#include "config.iss"

[Setup]
AppId={{5B1E0C64-4E33-4A7E-9C4F-2D8A17B90F11}
AppName=Farmacia
AppVersion={#AppVersion}
AppPublisher=Farmacia
DefaultDirName={autopf}\Farmacia
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=salida
OutputBaseFilename=Farmacia-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\app\farmacia.exe

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
; Servidor + web + .env + contexto + iniciar.bat + crear_bd.ps1
Source: "staging\servidor\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
; App de escritorio (flutter build windows --release)
Source: "..\frontend\build\windows\x64\runner\Release\*"; DestDir: "{app}\app"; Flags: recursesubdirs ignoreversion
; Instaladores de PostgreSQL y Ollama (se descargan en preparar.ps1)
Source: "deps\{#PgInstalador}"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "deps\OllamaSetup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
; Modelo de Ollama para instalar sin internet (lo copia preparar.ps1)
#if DirExists('staging\ollama-modelos')
Source: "staging\ollama-modelos\*"; DestDir: "{tmp}\ollama-modelos"; Flags: recursesubdirs deleteafterinstall
#endif

[Dirs]
; El sistema escribe aqui en tiempo de ejecución (modelo IA, imágenes,
; respaldos, logs) con usuario normal, sin privilegios de administrador
Name: "{app}\models"; Permissions: users-modify
Name: "{app}\uploads"; Permissions: users-modify
Name: "{app}\backups"; Permissions: users-modify
Name: "{app}\logs"; Permissions: users-modify

[Icons]
Name: "{autoprograms}\Farmacia"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\iniciar.ps1"""; WorkingDir: "{app}"; Comment: "Inicia el servidor oculto y abre la app"; IconFilename: "{app}\app\farmacia.exe"; IconIndex: 0
Name: "{autoprograms}\Farmacia - App de escritorio"; Filename: "{app}\app\farmacia.exe"; WorkingDir: "{app}\app"
Name: "{autodesktop}\Farmacia"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\iniciar.ps1"""; WorkingDir: "{app}"; Tasks: desktopicon; IconFilename: "{app}\app\farmacia.exe"; IconIndex: 0

[Run]
; 1) PostgreSQL en silencio (crea servicio, usuario postgres con la clave)
Filename: "{tmp}\{#PgInstalador}"; \
    Parameters: "--mode unattended --unattendedmodeui none --superpassword {#ClaveDB} --serverport 5432"; \
    StatusMsg: "Instalando PostgreSQL (puede tardar varios minutos)..."; \
    Flags: waituntilterminated

; 2) BD farmacia (reintenta mientras PostgreSQL termina de arrancar)
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\crear_bd.ps1"" -Clave ""{#ClaveDB}"""; \
    StatusMsg: "Creando la base de datos farmacia..."; \
    Flags: waituntilterminated

; 3) Ollama en silencio (para el asistente IA)
Filename: "{tmp}\OllamaSetup.exe"; Parameters: "/S"; \
    StatusMsg: "Instalando Ollama (asistente IA)..."; \
    Flags: waituntilterminated

; 3b) Modelo de IA ya listo, sin internet (ubicacion por defecto de Ollama)
#if DirExists('staging\ollama-modelos')
Filename: "cmd.exe"; \
    Parameters: "/C xcopy /E /I /Y ""{tmp}\ollama-modelos\*.*"" ""%USERPROFILE%\.ollama\models"""; \
    StatusMsg: "Instalando el modelo de IA (1 GB)..."; \
    Flags: waituntilterminated
#endif

; 4) Firewall: que el celular pueda escanear el QR y entrar a la web
Filename: "netsh.exe"; \
    Parameters: "advfirewall firewall add rule name=""Farmacia - Servidor (TCP 8080)"" dir=in action=allow protocol=TCP localport=8080"; \
    Flags: waituntilterminated
Filename: "netsh.exe"; \
    Parameters: "advfirewall firewall add rule name=""Farmacia - Web (TCP 8081)"" dir=in action=allow protocol=TCP localport=8081"; \
    Flags: waituntilterminated

; 5) Arrancar todo (oculto: solo se ve la app de escritorio)
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\iniciar.ps1"""; \
    WorkingDir: "{app}"; \
    Description: "Iniciar Farmacia ahora"; \
    Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Datos que crea el sistema en caliente (los respaldos/imagenes
; se conservan a proposito: son datos del cliente)
Type: files; Name: "{app}\models\Modelfile"
