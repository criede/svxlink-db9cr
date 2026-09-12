# Tägliche Upstream-Synchronisierung

Der Workflow `Sync upstream` übernimmt täglich um 02:17 UTC alle neuen Commits
aus `sm0svx/svxlink`, Branch `master`, in `criede/svxlink-db9cr`, Branch `master`.
Das entspricht 03:17 Uhr im Winter und 04:17 Uhr im Sommer in Deutschland.
Andere Branches, Tags und GitHub-Releases werden nicht synchronisiert.

Auch `.github/workflows/` ist vollständig von der Übernahme ausgeschlossen:
Vor dem Merge-Commit wird dieser Ordner auf den eigenen Stand vor dem Merge
zurückgesetzt. Dadurch werden weder neue Upstream-Workflows hinzugefügt noch
eigene Workflows geändert oder gelöscht. Dies gilt auch bei einem ansonsten
möglichen Fast-Forward. Der eigene Sync und die CodeQL-Deaktivierung bleiben erhalten.

Eigene Commits bleiben durch einen Git-Merge erhalten. Bei inhaltlichen Konflikten
hat die Version unseres `master` Vorrang (`git merge -X ours`). Konfliktfreie
Upstream-Änderungen werden auch innerhalb derselben Datei übernommen. Verbleibende
Dateikonflikte, etwa Ändern/Löschen, werden mit dem Dateistand unseres `master`
aufgelöst; eigene Löschungen bleiben dabei erhalten. Anschließend wird der Merge
abgeschlossen und gepusht. Konfliktbehaftete Upstream-Anteile werden dadurch
bewusst verworfen und bei späteren Läufen nicht erneut angeboten.

Mit eigenen Änderungen sind die auf GitHub in `master` eingecheckten Änderungen
gemeint. Nicht gepushte Änderungen auf einem lokalen Rechner kennt der Workflow
nicht. Technische Fehler brechen den Lauf weiterhin ab. Bei zwischenzeitlichen
Änderungen am Zielbranch wird kein Force-Push ausgeführt; der Workflow kann
anschließend erneut starten.

## Einrichtung

1. Den Workflow auf den Standardbranch des GitHub-Repositories pushen.
2. GitHub Actions im Repository aktivieren, falls noch nicht geschehen.
3. Unter **Actions → Sync upstream → Run workflow** einen ersten Lauf starten.

Standardmäßig nutzt der Workflow den automatisch bereitgestellten `GITHUB_TOKEN`
mit `contents: write`. Branch-Regeln müssen diesen direkten Push erlauben.
Pushes mit diesem Token lösen keine weiteren Push-Workflows aus.

Damit auch Änderungen an `.github/workflows/` übernommen werden können, bei
Bedarf ein Repository-Secret **UPSTREAM_SYNC_TOKEN** hinterlegen: ein auf dieses
Repository beschränktes Fine-grained Personal Access Token mit **Contents: Read
and write** und **Workflows: Read and write**. Der Workflow verwendet dieses
Secret bevorzugt. Ohne ausreichende Berechtigung kann GitHub den Push mit
Workflow-Änderungen ablehnen. Ein PAT kann auch nachfolgende Push-Workflows auslösen.
Tokenwerte ausschließlich in GitHub Secrets speichern.

GitHub kann geplante Läufe verzögern und deaktiviert geplante Workflows in
öffentlichen Repositories nach 60 Tagen ohne Repository-Aktivität. Bei Forks
können geplante Workflows zunächst deaktiviert sein. Bei Bedarf unter **Actions**
wieder aktivieren. Der Zeitplan setzt voraus, dass die Datei auf dem Standardbranch
liegt.

## Quellen

- [GitHub: Workflow-Ereignisse und Zeitpläne](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GitHub: GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)
- [GitHub: Berechtigungen für Workflow-Änderungen](https://github.github.com/gh-aw/reference/safe-outputs-pull-requests/)
