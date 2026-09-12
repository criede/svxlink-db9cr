# Hinweise für Agenten

## Projekt

svxlink-db9cr basiert auf SvxLink, einem modularen Sprachdienstsystem für den
Amateurfunk. Das Projekt enthält C/C++-Quellcode, Tcl-Skripte und einen
CMake-basierten Build. Ziel und Umfang lokaler DB9CR-Anpassungen sind noch
zu dokumentieren.

## Orientierung

- `README.adoc`: Projektüberblick.
- `INSTALL.adoc`: Installations- und Build-Hinweise.
- `src/CMakeLists.txt`: Einstieg in den CMake-Build.
- `src/svxlink/`: Server, Module, Skripte und weitere Funkkomponenten.
- `src/async/`: Bibliotheken für asynchrone Verarbeitung und Audio.
- `src/qtel/`: Grafischer EchoLink-Client.
- `src/doc/`: Dokumentation und Versionshinweise.
- `TODO.MD`: Offene Aufgaben.
- `CHANGELOG.MD`: Protokoll lokaler Änderungen.

## Arbeitsweise

- Vor Änderungen vorhandenen Code, Dokumentation und Git-Status prüfen.
- Vorhandene Änderungen des Nutzers erhalten.
- Änderungen auf die jeweilige Aufgabe begrenzen und den bestehenden Stil nutzen.
- Zugangsdaten und andere vertrauliche Konfigurationswerte nicht einchecken.
- Funktionsänderungen mit passenden Builds oder gezielten Tests prüfen;
  Voraussetzungen dazu in `INSTALL.adoc` nachlesen.
- Tatsächlich ausgeführte Prüfungen und verbleibende Einschränkungen benennen.
- Aufgabenliste und Änderungsprotokoll bei relevanten Änderungen aktualisieren.
- In Workflows immer eine aktuell gepflegte Node.js-Version verwenden,
  vorzugsweise eine unterstützte LTS-Version. Das gilt auch für die interne
  Node.js-Laufzeit verwendeter Actions: passende, gepflegte Action-Versionen
  auswählen und deren `runs.using` prüfen. `actions/setup-node` allein ändert
  die interne Laufzeit anderer Actions nicht. Keine EOL-Versionen oder
  Umgehungen zur Weiterverwendung abgekündigter Laufzeiten einsetzen.

## Upstream-Workflows

- Vom Upstream übernommene Actions in `criede/svxlink-db9cr` deaktiviert halten.
- Der eigene Workflow `Sync upstream` bleibt aktiviert.

## Dateiname

Diese Datei heißt wie angefordert `AGENT.MD`. Werkzeuge, die Anweisungen aus
`AGENTS.md` laden, erkennen sie unter diesem Namen möglicherweise nicht automatisch.
