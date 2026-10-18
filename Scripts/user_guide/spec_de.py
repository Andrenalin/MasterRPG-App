import json

P = []


def page(title, kicker, intro, image, marks, tip=None):
    P.append({"title": title, "kicker": kicker, "intro": intro, "image": image,
              "marks": [{"x": x, "y": y, "text": t} for (x, y, t) in marks], "tip": tip})


P.append({"cover": True, "title": "MasterRPG", "subtitle": "Eine geführte Tour für Spielleiter",
          "text": "Jeder Bildschirm in dieser Anleitung stammt aus dem Tutorial-Abenteuer, das mit der App geliefert wird. Öffne es neben der Anleitung und tippe mit.",
          "image": "22_game_map"})

page("Orientierung", "Los geht's",
     "MasterRPG hält alles für ein Spiel in einer Bibliothek. Jedes Modul hat denselben Aufbau: Die Seitenleiste wählt das Modul, die Liste zeigt seine Einträge, das Detail zeigt den gewählten Eintrag.",
     "01_adventure_list",
     [(240, 299, "Die Seitenleiste gruppiert die Module. Bibliothek: Abenteuer, Charakter, Karte, Wetter. Referenzen: Regeln, Pdf, Tabelle. Material: Musik, Würfel, Foto, 3D Objekt."),
      (500, 200, "Ordner halten lange Listen übersichtlich. Öffne einen mit dem Pfeil; dieselben Ordner gibt es in jedem Modul."),
      (492, 266, "Tippe einen Eintrag an, um ihn zu öffnen. Bild und erste Zeilen der Beschreibung helfen beim Wiederfinden."),
      (506, 108, "Suche nach Text oder tippe @, um nach Tags zu suchen."),
      (424, 54, "Plus legt einen neuen Eintrag an, die drei Punkte öffnen Listenoptionen wie Ordner und Sammlungen.")])

page("Einträge anlegen und bearbeiten", "Los geht's",
     "Jeder Eintrag hat einen Namen, eine Beschreibung und Tags. Tippe oben rechts auf den Stift, um sie zu bearbeiten.",
     "02_edit_item_keyboard",
     [(833, 228, "Der Name erscheint in Listen und als Text eines Links auf diesen Eintrag."),
      (860, 340, "Die Beschreibung erklärt den Eintrag dir und, bei Foto oder Charakter, deinen Spielern."),
      (590, 376, "Diese Schaltflächen fügen einen Link zu einem anderen Modul ein: Abenteuer, Karte, Charakter, PDF, Tabelle oder Wetter. Links verbinden das ganze Spiel.")],
     "Tipp: Tags wie BEISPIEL machen eine Gruppe von Einträgen später leicht auffindbar. Suche nach @BEISPIEL.")

page("Abenteuer: die Geschichte", "Bibliothek",
     "Ein Abenteuer ist die Geschichte. Seine Einträge sind Kapitel oder Szenen, und Links in den Einträgen holen jedes andere Modul dazu.",
     "04_adventure_entries",
     [(664, 144, "Tags helfen beim Finden des Abenteuers. Nutze sie für System, Setting oder Sitzung."),
      (660, 316, "Jeder Eintrag hat eine kurze Überschrift und freien Text. Nutze einen Eintrag pro Szene."),
      (714, 425, "Ein blauer Chip ist ein Link. Tippe einen Würfel-Link zum Würfeln, einen Musik-Link zum Abspielen, einen Karten- oder Foto-Link zum Öffnen."),
      (1093, 54, "Der Stift bearbeitet das Abenteuer. Die Schaltfläche unten rechts fragt den Assistenten auf dem Gerät nach Ideen, wenn dein Gerät das unterstützt.")],
     "Abenteuer können weitere Abenteuer enthalten und in Ordnern gruppiert werden, so kann eine Kampagne viele Szenarien umfassen.")

page("Charaktere", "Bibliothek",
     "Charaktere enthalten Spieler, NSC und Monster. Ordner sortieren sie, und Sammlungen fassen Zusammengehöriges zusammen, etwa alle Monster.",
     "06_character_list",
     [(370, 237, "00 Charakter erklärt jede Art von Wert. Öffne ihn, um den Editor kennenzulernen."),
      (370, 322, "Eine einsatzbereite Heldin. Ihr Porträt wird ihr Marker auf der Karte."),
      (370, 405, "Ein Monster für die Kampfrunde. Kopiere es für jeden Goblin, den du brauchst; jede Kopie behält im Spiel ihre eigenen HP."),
      (320, 509, "Sammlungen listen Charaktere, die zusammengehören, zum Beispiel Monster oder NSC. Eine Sammlung kann denselben Eintrag mehrfach enthalten.")])

page("Werte, Würfel und Links", "Bibliothek",
     "Ein Charakter ist eine Liste von Werten. Ein Wert kann Text, eine Zahl, eine Dezimalzahl oder eine Auswahl sein und einen Würfel und Links tragen.",
     "05_character_values",
     [(688, 268, "Ein Wert hat einen Namen und einen Wert, hier ein freier Text."),
      (600, 340, "Der Wert kann beschreiben, was du brauchst: Regeln, Hinweise, Erinnerungen."),
      (603, 437, "Ein Würfel an einem Wert. Bei einem Zahlenwert nutzt der Würfel ihn als Vergleichswert."),
      (1020, 491, "Namen können Links enthalten, zum Beispiel auf einen Tabelleneintrag. Tippe darauf, um ihn zu lesen oder zu würfeln.")])

page("HP, Initiative und die Kampfrunde", "Bibliothek",
     "Die Kampfrunde liest von jedem Charakter zwei Werte nach Namen: HP und Ini. Beide können eine einfache Zahl oder eine Berechnung sein.",
     "07_character_hp_ini",
     [(622, 385, "Der Eintrag mit dem Namen HP ist die Gesundheit. Die Basis sind 100 Prozent; Schaden und Heilung werden im Spiel als Modifikator verfolgt."),
      (796, 420, "Ein berechneter Wert nutzt Links zu anderen Werten desselben Charakters. Hier ergibt Konstitution mal 2 plus 10 den Wert 34."),
      (620, 466, "Der Eintrag mit dem Namen Ini ist die Initiative."),
      (599, 540, "Der Würfel-Chip wird im Kampf für die Initiative gewürfelt."),
      (1085, 630, "Andere Werte können Text mit Links enthalten, etwa zur Waffentabelle.")],
     "Verwendet dein System andere Namen für HP und Initiative, ändere sie in den Einstellungen der Kampfrunde.")

page("Karten", "Bibliothek",
     "Eine Karte ist ein Foto mit Räumen. Räume verbergen Inhalte vor den Spielern, bis du sie aufdeckst, und jeder Raum kann Charaktere, Würfel, Tabellen, Musik, PDFs und Fotos verknüpfen.",
     "09_map_menu",
     [(790, 314, "Das Kartenfoto. Darunter legen die Einstellungen Abdeckfarbe, Abdeckkachel und Umrandung fest."),
      (1146, 54, "Das Detailmenü öffnet die folgenden Werkzeuge."),
      (962, 114, "Karteneditor: Räume zeichnen und Marker setzen."),
      (962, 152, "Editiere Kachel: die Abdeckkachel der Karte bearbeiten."),
      (962, 190, "Informationen extrahieren aus dem Kartenbild."),
      (962, 59, "Inspektor: Links aus anderen Modulen durchsuchen und ziehen.")])

page("Der Karteneditor", "Bibliothek",
     "Im Editor zeichnest du die Räume und setzt Marker. Die grünen Flächen sind Räume, die Marker sind Charaktere auf der Karte.",
     "10_map_editor",
     [(560, 250, "Ein Raum ist eine Form auf der Karte. Er hat einen Namen, eine Beschreibung und beliebige Links. Eingang und Haupthalle haben hier jeweils einen eigenen Raum."),
      (930, 427, "Ein Marker mit Porträt ist ein Charakter. Elaras Marker gehört einem Spieler."),
      (514, 390, "Ein einfarbiger Marker ist ein Monster. Diese beiden Goblin-Marker sind vor den Spielern verborgen."),
      (260, 778, "Wechsle zwischen den Anzeigemodi, um die Karte so zu sehen, wie die Spieler sie sehen."),
      (320, 778, "Setze Charaktere auf die Karte. Die App bietet einen Marker an, sobald du einen Charakter verknüpfst."),
      (32, 778, "Änderungen übernehmen.")])

page("Tabellen", "Referenzen",
     "Tabellen enthalten alles, was du würfelst oder nachschlägst: Waffen, Beute, Begegnungen, Regeln.",
     "11_table_list",
     [(365, 152, "Ordner organisieren Tabellen."),
      (350, 328, "Eine einfache Liste, etwa eine Waffenliste aus einem Regelbuch."),
      (485, 415, "Eine Würfeltabelle. Der Würfel rechts ist der Würfel, mit dem du auf ihr würfelst."),
      (370, 503, "Eine Sammlung ordnet zusätzliche Listen mit kategorisierten Einträgen.")])

page("Auf einer Tabelle würfeln", "Referenzen",
     "Eine Würfeltabelle ordnet Würfelergebnisse Einträgen zu. Die Einträge können Links enthalten, sogar zu anderen Tabellen und Würfeln.",
     "12_table_loot",
     [(560, 144, "Tags gruppieren Tabellen, hier die Kategorie Beute."),
      (594, 199, "Der Würfel der Tabelle. Ändere ihn im Editor."),
      (623, 389, "Der Eintragsname ist das Würfelergebnis. Auch Bereiche wie 1-3 funktionieren."),
      (582, 425, "Der Inhalt kann auf einen anderen Tabelleneintrag verweisen. Tippe auf den Link Axt, um ihn zu lesen oder mit den Spielern zu teilen.")])

page("Würfel", "Material",
     "Das Würfelmodul verwaltet jeden Würfel, den du nutzt: Sets farbiger Würfel, Regeln zur Berechnung eines Ergebnisses und Summenwürfel für Tabellen.",
     "14_dice_editor",
     [(325, 237, "Die Würfel dieses Eintrags. Tippe auf das x, um einen Würfel zu entfernen."),
      (590, 480, "Wähle Würfel in verschiedenen Farben und Formen, vom W3 bis zum W20 und Prozentwürfel."),
      (590, 792, "Einstellungen: Würfel summieren, Modifikator, gegen einen Wert prüfen, Coup- und Patzer-Regeln, Neuwürfe."),
      (352, 144, "Tags gruppieren die Würfel nach Regelsystem.")])

page("Würfelbeutel", "Material",
     "Ein Würfelbeutel sammelt mehrere Würfel. Nutze einen für ein Set, das immer zusammen unterwegs ist, etwa die Schatzwürfel.",
     "13_dice_bag",
     [(300, 112, "Der Name des Beutels. Ein Beutel ist eine Sammlung, derselbe Würfel kann also in mehreren Beuteln liegen."),
      (700, 190, "Jede Zeile zeigt den Würfel und seine Beschreibung. Tippe eine Zeile an, um den Würfel zu öffnen."),
      (812, 54, "Plus fügt dem Beutel einen weiteren Würfel hinzu.")])

page("Wetter", "Bibliothek",
     "Wetter gibt einer Szene Atmosphäre. Du richtest es hier ein und zeigst es den Spielern im Spiel.",
     "15_weather",
     [(730, 360, "Ein Hintergrundfoto hinter dem Wetter. Nicht jedes Foto funktioniert, probiere ein paar aus."),
      (700, 472, "Die Tageszeit. Sterne erscheinen nachts; Mittag entfernt sie."),
      (1090, 508, "Wolkendichte."),
      (1090, 571, "Die Art des Niederschlags (hier Regen). Intensität und Winkel folgen darunter.")])

page("Fotos, Musik, PDFs und 3D", "Material",
     "Diese Module verwalten die Dateien deines Spiels und halten sie in iCloud. Ordner sind hier echte iCloud-Ordner, die Dateien bleiben also auch dort geordnet.",
     "16_photo_folder",
     [(364, 152, "Ein Ordner. Öffne ihn, um seine Fotos zu sehen. Dieselben Ordner gibt es für Musik, Pdf und 3D Objekt."),
      (397, 54, "Plus fügt der Liste einen neuen Eintrag hinzu."),
      (507, 54, "Liste ein- oder ausblenden, um mehr Platz zu haben.")])

page("Das Spiel starten: das Portaltor", "Spielen",
     "Das Portaltor ist der Tab Spiel. Wähle zuerst deine Rolle; die App merkt sich dein letztes Abenteuer und deinen letzten Charakter für die nächste Sitzung.",
     "17_portal_gate",
     [(437, 320, "Spieler: einen Charakter wählen und einem geteilten Spiel beitreten."),
      (729, 320, "Spielleiter: ein Abenteuer wählen und die Sitzung leiten."),
      (1021, 320, "Beitreten: ein Spiel in der Nähe als Beobachter oder Vertreter finden."),
      (729, 516, "Ein Element hier ablegen oder tippen, um es zu wählen."),
      (410, 655, "Spielstatistiken zeigen ein Beispiel-Dashboard deiner Sitzungen.")])

page("Ein Spiel leiten", "Spielen",
     "Wähle als Spielleiter das Abenteuer und starte dann. Spieler treten über SharePlay oder dein lokales Netzwerk bei.",
     "19_gm_start_game",
     [(729, 500, "Das Abenteuer, das das Spiel ausführt. Entferne es mit dem Minus, um ein anderes zu wählen."),
      (1093, 546, "Der Beitrittscode. Spieler geben ihn ein, um deinem Spiel beizutreten."),
      (729, 626, "Spiel starten."),
      (1068, 470, "Einen gespeicherten Spielstand importieren, um eine Sitzung fortzusetzen."),
      (1068, 504, "RPG online mit einer entfernten Gruppe spielen.")])

page("Während des Spiels", "Spielen",
     "Der Spielbildschirm hat eine Bühne für Karte, Foto oder Wetter und ein Seitenfeld mit deinem Abenteuer. Die Spieler sehen nur, was du zeigst.",
     "20_game_running",
     [(25, 23, "Das Spiel beenden. Du kannst vorher sichern, um später weiterzumachen."),
      (73, 22, "Den Würfelbeutel aus- oder einblenden."),
      (76, 75, "Würfel vor dem Tisch werfen."),
      (493, 23, "Der Beitrittscode, tippe, um ihn erneut zu sehen."),
      (856, 23, "Das Seitenfeld ein- oder ausblenden."),
      (1030, 300, "Dein Abenteuer. Links darin funktionieren wie im Editor.")])

page("Den Spielern etwas zeigen", "Spielen",
     "Tippe einen Link im Abenteuer an, und er klappt mit Aktionen auf. Du entscheidest, was die Spieler sehen.",
     "21_game_link_actions",
     [(1108, 767, "Der Karten-Link."),
      (994, 793, "Teilen sendet den Inhalt an die Spieler."),
      (1082, 793, "Anzeigen öffnet ihn für dich auf der Bühne."),
      (1030, 810, "Der Inhalt des Links als grüne Vorschau.")])

page("Die Spielkarte", "Spielen",
     "Die Karte ist das Herz einer Sitzung. Räume bleiben verborgen, bis du sie aufdeckst, und die Werkzeugleiste steuert, was die Spieler sehen.",
     "22_game_map",
     [(427, 423, "Ein Raum, der noch vor den Spielern verborgen ist."),
      (776, 427, "Elaras Marker ist für die Spieler sichtbar."),
      (360, 390, "Ein Goblin-Marker, noch verborgen."),
      (141, 778, "Anzeigemodus (hier: Spielleiter)."),
      (196, 778, "Karte teilen: Spieler bekommen nur Aktualisierungen, wenn dies aktiviert ist."),
      (250, 778, "Marker wählen: Charaktere zur Karte hinzufügen."),
      (297, 778, "Zeigemodus."),
      (25, 778, "Den 3D-Tisch zeigen. Auf der Apple Vision Pro ist er ein volumetrischer Tisch, auf anderen Geräten eine Kameraansicht der Karte.")])

page("Charaktere auf der Karte hinzufügen", "Spielen",
     "Füge Marker während einer Sitzung hinzu, ohne das Spiel zu verlassen.",
     "23_game_choose_pins",
     [(338, 330, "Wähle einen oder mehrere Charaktere."),
      (792, 112, "Bestätigen. Die Marker werden mit den Porträts der Charaktere auf der Karte platziert."),
      (845, 506, "Öffne einen Ordner oder eine Sammlung, um darin einen Charakter zu wählen.")])

page("Export, Import und Tipps", "Einstellungen",
     "Deine Abenteuer lassen sich als ein Paket exportieren und auf einem anderen Gerät importieren. Ein Paket enthält alles, was ein Abenteuer verknüpft.",
     "10_settings",
     [(330, 227, "Exportiere die Daten, um sie mit einem anderen Gerät zu teilen oder als Sicherung."),
      (330, 279, "Ein Paket importieren: Prüfe vor dem Übernehmen, was sich ändert."),
      (330, 389, "Ordner validieren: prüft die Ordnerstruktur."),
      (330, 499, "Tipps erneut anzeigen stellt die Hinweise in der App wieder her."),
      (330, 743, "Zurücksetzen der Daten löscht alles. Mit Vorsicht nutzen.")])

json.dump(P, open('spec_de.json', 'w'), indent=1, ensure_ascii=False)
print(len(P), 'pages')
