@echo off
REM FlexiPlan – Einmaliges Setup + Build (Windows)
REM Voraussetzung: Flutter SDK ist installiert und im PATH.

echo === 1/5: Plattform-Scaffolding erzeugen (lib/ bleibt unangetastet) ===
call flutter create . --project-name flexiplan --platforms=android,windows
if errorlevel 1 goto :error

echo === 2/5: Abhaengigkeiten laden ===
call flutter pub get
if errorlevel 1 goto :error

echo === 3/5: Statische Analyse ===
call flutter analyze
if errorlevel 1 goto :error

echo === 4/5: Tests ausfuehren ===
call flutter test
if errorlevel 1 goto :error

echo === 5/5: APK bauen ===
call flutter build apk --debug
if errorlevel 1 goto :error

echo.
echo Alles erfolgreich. App starten mit: flutter run
goto :eof

:error
echo.
echo FEHLER: Schritt fehlgeschlagen, siehe Ausgabe oben.
exit /b 1
