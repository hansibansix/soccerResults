import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "soccerResults"

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
        height: leagueColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: leagueColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "League"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
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
        }
    }

    StyledRect {
        width: parent.width
        height: refreshColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: refreshColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Refresh"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StringSetting {
                settingKey: "refreshInterval"
                label: "Refresh Interval (minutes)"
                description: "Base polling interval — auto-reduces to 1 min during live matches"
                placeholder: "2"
                defaultValue: "2"
            }
        }
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
