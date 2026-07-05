# Play-Store-Eintrag – Texte & Assets

Copy-Paste-Vorlagen für die Google Play Console (Store-Eintrag → Haupt-Store-Eintrag).

## App-Name (max. 30 Zeichen)

```
FlexiPlan – Workout Tracker
```

## Kurzbeschreibung (max. 80 Zeichen)

```
Dein lokales Trainingstagebuch. Workouts als JSON importieren und tracken.
```

## Vollständige Beschreibung (max. 4000 Zeichen)

```
FlexiPlan ist dein minimalistischer Workout-Begleiter und dein digitales Trainingstagebuch – komplett lokal, ohne Cloud, ohne Konto, ohne Werbung.

SO FUNKTIONIERT'S
Importiere deinen Trainingsplan als einfache JSON-Datei – per Datei-Auswahl oder direkt aus der Zwischenablage. FlexiPlan führt dich dann Satz für Satz durch dein Training: mit Belastungs-Timer für zeitbasierte Übungen (z. B. Planks), automatischem Pausen-Timer und großen Touch-Tasten, mit denen du Gewicht und Wiederholungen direkt beim Training anpasst.

DEINE DATEN GEHÖREN DIR
• Keine Internet-Berechtigung – deine Daten können dein Gerät technisch gar nicht verlassen
• Kein Konto, keine Anmeldung, kein Tracking, keine Werbung
• Trainingshistorie mit Gesamtzeit, Sätzen, Wiederholungen und bewegtem Volumen – dauerhaft lokal gespeichert

FLEXIBLE TRAININGSPLÄNE
Trainingspläne sind offene JSON-Dateien. Du kannst sie:
• aus den fertigen Vorlagen im Open-Source-Repository kopieren (Ganzkörper, Push/Pull, Beine, HIIT, Mobility …)
• von deinem Coach im dokumentierten Format bekommen
• dir von einer KI wie ChatGPT, Claude oder Gemini maßschneidern lassen – die Prompt-Vorlage dafür liegt bei

FÜRS ECHTE TRAINING GEMACHT
• Dark-Mode-Design mit hohem Kontrast, ablesbar auch aus Entfernung
• Große Touch-Zonen – bedienbar mit verschwitzten Händen
• Satz überspringen mit Sicherheitsabfrage, vorzeitiges Beenden von Zeit-Übungen
• Pausen-Ansicht zeigt dir, welcher Satz als Nächstes kommt

OPEN SOURCE
Der komplette Quellcode ist öffentlich auf GitHub verfügbar (MIT-Lizenz) – inklusive aller Workout-Vorlagen und der JSON-Format-Dokumentation:
https://github.com/nicolasasauer/FlexiPlan
```

## Assets

| Asset | Anforderung | Status |
|---|---|---|
| App-Icon | 512×512 PNG, max. 1 MB | ✅ [play_store_icon_512.png](play_store_icon_512.png) |
| Feature-Grafik | 1024×500 PNG/JPG | ✅ [feature_graphic_1024x500.png](feature_graphic_1024x500.png) |
| Screenshots Smartphone | mind. 2, 16:9 bis 9:16, je max. 8 MB | ⬜ selbst aufnehmen, siehe unten |
| Datenschutzerklärung-URL | für Produktion Pflicht | ✅ PRIVACY.md im Repo → nach dem Push: `https://github.com/nicolasasauer/FlexiPlan/blob/main/PRIVACY.md` |

### Screenshots aufnehmen

Am einfachsten direkt vom Gerät (Lautstärke-leiser + Power) oder vom Emulator:

```
adb exec-out screencap -p > screenshot_home.png
```

Empfohlene Motive: Home mit aktivem Plan, Import mit validierter Vorschau, Workout-Screen mit +/-Tasten, Rest-Timer, Summary-Screen, Verlauf.

## Sonstige Console-Angaben (Kurzreferenz)

- **Kategorie:** Gesundheit & Fitness
- **Datensicherheit-Formular:** „Es werden keine Nutzerdaten erhoben oder weitergegeben" (App hat keine Internet-Berechtigung)
- **Anzeigen enthalten:** Nein
- **In-App-Käufe:** Nein
