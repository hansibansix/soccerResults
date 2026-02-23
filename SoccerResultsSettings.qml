import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "soccerResults"

    property var detectedBrowsers: []

    Process {
        id: browserDetector
        property string output: ""
        command: ["python3", Qt.resolvedUrl("fetch_kicker.py").toString().replace("file://", ""), "--detect-browsers"]
        running: true
        stdout: SplitParser { onRead: line => { browserDetector.output += line; } }
        onExited: {
            try {
                root.detectedBrowsers = JSON.parse(browserDetector.output);
            } catch (e) {
                root.detectedBrowsers = [];
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Soccer Results"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Live football scores from kicker.de"
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    SelectionSetting {
        settingKey: "league"
        label: "League"
        description: "Which competition to follow"
        options: [
            {label: "Premier League", value: "PL"},
            {label: "La Liga", value: "PD"},
            {label: "Bundesliga", value: "BL1"},
            {label: "2. Bundesliga", value: "BL2"},
            {label: "3. Liga", value: "BL3"},
            {label: "Serie A", value: "SA"},
            {label: "Ligue 1", value: "FL1"},
            {label: "Champions League", value: "CL"}
        ]
        defaultValue: "PL"
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    StyledText {
        width: parent.width
        text: "Favorite Team"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Medium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "When your favorite team has a live match, it will automatically appear in the bar pill (unless a match is manually pinned)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        lineHeight: 1.4
    }

    StringSetting {
        settingKey: "favoriteTeam"
        label: "Team Name"
        description: "As shown on kicker.de (e.g. VfB Stuttgart, Bayern München). All leagues are scanned automatically."
        placeholder: "e.g. VfB Stuttgart"
        defaultValue: ""
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    StringSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval (minutes)"
        description: "Base polling interval — auto-reduces to 1 min during live matches"
        placeholder: "2"
        defaultValue: "2"
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    SelectionSetting {
        settingKey: "cookieBrowser"
        label: "Cookie Browser"
        description: "Browser used for kicker.de authentication. Visit kicker.de once in this browser to generate the cookie."
        options: {
            var opts = [{label: "Auto-detect", value: ""}];
            for (var i = 0; i < root.detectedBrowsers.length; i++) {
                var b = root.detectedBrowsers[i];
                opts.push({label: b.name, value: b.bin});
            }
            return opts;
        }
        defaultValue: ""
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
    }

    StyledRect {
        width: parent.width
        height: infoColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surface

        Column {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DankIcon {
                    name: "info"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "About"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "No API key needed. Data scraped from kicker.de.\n\nSupported leagues:\n\u2022 Premier League (PL)\n\u2022 La Liga (PD)\n\u2022 Bundesliga (BL1)\n\u2022 2. Bundesliga (BL2)\n\u2022 3. Liga (BL3)\n\u2022 Serie A (SA)\n\u2022 Ligue 1 (FL1)\n\u2022 Champions League (CL)"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }
}
