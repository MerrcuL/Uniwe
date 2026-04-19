<div align="center">
  <img src="assets/icons/icon_foreground.png" alt="Uniwe Logo" width="150"/>

  <h1>Uniwe App</h1>
  
  [**🇺🇸 English**](README.md) | [**🇩🇪 Deutsch**](README.de.md)
  
  <br>

  [![Download from latest release](https://img.shields.io/badge/Download-Release-blue?style=for-the-badge&logo=github)](https://github.com/MerrcuL/Uniwe/releases/latest)
</div>

*Wenn du nicht weißt, welche Version du herunterladen sollst:*
* **arm64-v8a:** Fast sicher diese Version
* **universal:** Wenn die erste nicht funktioniert
---

### Aber warum?

Als ich mich im Oktober 2025 einschrieb, war ich überrascht, dass eine so große Hochschule wie die HTW Berlin **keine eigene mobile App hatte**. Ich habe nicht die Absicht, **Studo** zu nutzen, das nicht nur voller Schnickschnack ist (Authentifikator, Jobsuche, Feed … im Ernst??), sondern auch seine grundlegenden Funktionen hinter einem „Pro“-Abonnement versteckt. Außerdem hat sich die Benutzeroberfläche sowohl von Studo als auch von LSF seit 2010 nicht verändert (und das ist nicht einmal übertrieben), also beschloss ich, eine anständige App für mich (und für euch) zu entwickeln – eine, die **schön, modern, völlig kostenlos und Open Source** ist.

Übersetzt mit DeepL.com (kostenlose Version)

### Kernfunktionen
- **Stundenplan:** Automatisch aus LSF importiert und ordentlich dargestellt.
- **Webmail-Integration:** Schnelle Überprüfung im Hintergrund und lokale Benachrichtigungen für das HTW-Postfach.
- **Mensa-Speiseplan:** Tägliches Essensangebot der HTW-Mensen.
- **Verkehr:** Live-Abfahrten von Trams an den Campussen.
- **Sicher & Privat:** Anmeldedaten werden sicher und lokal auf deinem Gerät gespeichert.

### Tipp für die Ansicht von E-Mails
- Gehe zu „Einstellungen“ → „Mail“
- Ändere die Ansicht auf „Liste ohne E-Mail-Vorschau“
> Auf diese Weise kannst du deine E-Mails genauso anzeigen, wie du es von Gmail gewohnt bist.

### Verwendete Technologien
Folgende Technologien und Bibliotheken machen Uniwe möglich:

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat-square&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=flat-square&logo=dart&logoColor=white) 

`http` `provider` `dynamic_color` `flutter_secure_storage` `enough_mail` `webview_flutter`

---

### Datenschutz and Sicherheit

Uniwe wurde mit besonderem Augenmerk auf Datenschutz und Sicherheit entwickelt.

- **Nur lokale Speicherung:** Deine LSF- und HTW-Anmeldedaten werden sicher verschlüsselt und **ausschließlich** lokal auf deinem Gerät im sicheren Speicher des Systems (Keystore/Keychain) abgelegt (über `flutter_secure_storage`). Deine Passwörter werden niemals an eigene Server gesendet – es gibt keinen zentralisierten Uniwe-Server.
- **Direkte Verbindungen:** Die App stellt sämtliche Verbindungen zu den HTW LSF- und Webmail-Servern direkt von deinem Gerät aus her.
- **Open-Source-Transparenz:** Der gesamte Code ist hier öffentlich zugänglich. Du kannst genau überprüfen, wie deine Daten verarbeitet werden, wodurch ausgeschlossen ist, dass verdeckt Daten im Hintergrund gesammelt werden.

---

## 🛠 Mitwirken & Kompilieren

Diese App ist sehr modular aufgebaut und wir freuen uns über Beiträge von jedem! Teile die App gerne mit deinen Kommilitonen, melde Fehler oder erstelle einen Pull Request.

**Wie man die App baut (Kompiliert):**
1. Klonen des Repositories: `git clone https://github.com/MerrcuL/Uniwe.git`
2. [Flutter](https://flutter.dev/docs/get-started/install) installieren (SDK >=3.2.0).
3. `flutter pub get` ausführen, um Abhängigkeiten herunterzuladen.
4. `flutter build apk` ausführen, um das Android-Paket zu erstellen.

**Struktur:**
- `/lib/models/`: Datenstrukturen
- `/lib/screens/`: Benutzeroberfläche (UI)
- `/lib/services/`: Logik (Netzwerk, Authentifizierung, LSF Scraping)

---

## 📜 Lizenzen & APIs
Uniwe verwendet folgende externe APIs und Open-Source-Pakete:
- **[OpenMensa](https://openmensa.org):** Mensa-API.
- **[BVG Transport Rest](https://v6.bvg.transport.rest):** VBB/BVG Abfahrtzeiten. 
- Alle externen Abhängigkeiten unterliegen ihren jeweiligen Open-Source-Lizenzen.
