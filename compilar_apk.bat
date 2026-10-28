@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
echo === Compilando Noche de juegos ===

where flutter >nul 2>nul
if errorlevel 1 (
  echo.
  echo [ERROR] No se encontro Flutter. Instala Flutter y Android Studio primero:
  echo   https://docs.flutter.dev/install/manual
  echo Luego cierra y abre esta ventana y ejecuta de nuevo este archivo.
  pause
  exit /b 1
)

if not exist android (
  echo Generando proyecto Android...
  call flutter create --org com.cesar.juegos --project-name pareme_la_mano --platforms=android _gen
  xcopy /E /I /Y _gen\android android >nul
  rmdir /S /Q _gen
  rem Firebase exige minSdk 23 y se bloquea la pantalla dividida
  powershell -NoProfile -Command "Get-ChildItem android\app -Include build.gradle,build.gradle.kts | ForEach-Object { (Get-Content $_.FullName) -replace 'minSdk\s*=\s*flutter\.minSdkVersion','minSdk = 23' -replace 'minSdkVersion\s+flutter\.minSdkVersion','minSdkVersion 23' | Set-Content $_.FullName }"
  powershell -NoProfile -Command "$f='android\app\src\main\AndroidManifest.xml'; (Get-Content $f) -replace '<activity','<activity android:resizeableActivity=\"false\"' | Set-Content $f"
)

call flutter pub get
if errorlevel 1 goto fallo
call flutter build apk --release
if errorlevel 1 goto fallo

echo.
echo LISTO. El APK esta en:
echo   %cd%\build\app\outputs\flutter-apk\app-release.apk
explorer build\app\outputs\flutter-apk
pause
exit /b 0

:fallo
echo.
echo [ERROR] La compilacion fallo. Copia el mensaje de arriba y pegalo en el chat con Claude.
pause
exit /b 1
