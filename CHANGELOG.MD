# Änderungsprotokoll

Dieses Protokoll erfasst Änderungen an svxlink-db9cr ab seiner Einführung.
Vorhandene Versionshinweise des Projekts befinden sich unter `src/doc/`.

## Unveröffentlicht

### Geändert

- Upstream-CodeQL im eigenen Repository deaktiviert: automatische Trigger
  entfernt und Ausführung auf das Upstream-Repository beschränkt.
- Projektregel: In Workflows nur aktuell gepflegte Node.js-Laufzeiten verwenden,
  einschließlich der internen Laufzeit eingebundener Actions.
- CodeQL-Workflow auf Checkout v6 und CodeQL Action v4 mit Node.js 24 umgestellt
  und Berechtigungen zum Hochladen der Analyseergebnisse explizit festgelegt.

### Hinzugefügt

- Täglicher GitHub-Actions-Workflow zum Merge von `sm0svx/svxlink:master` nach
  `master`, mit manuellem Start und automatischer Konfliktauflösung zugunsten
  eigener Änderungen auf `master`.
- Einrichtungs- und Betriebshinweise in `.github/UPSTREAM-SYNC.MD`.
- `TODO.MD` mit einer ersten Aufgabenliste für Dokumentation, Build und Betrieb.
- `AGENT.MD` mit Projektkontext und Hinweisen für die Bearbeitung.
- `CHANGELOG.MD` zur laufenden Dokumentation der Änderungen.
