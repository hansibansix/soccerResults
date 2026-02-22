import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Item {
    id: row

    required property var rowData
    property bool isHeader: false
    property string leagueCode: ""
    property int totalTeams: 0
    property int rowIndex: rowData ? rowData.position - 1 : 0

    // Zone thresholds per league
    // CL = Champions League, EL = Europa League, ECL = Conference League
    // relPlayoff = relegation playoff, relDirect = direct relegation
    readonly property var _zones: {
        var n = totalTeams;
        if (n <= 0) return { cl: 0, el: 0, ecl: 0, relPlayoff: 0, relDirect: 0 };

        // Bundesliga (18 teams): 1-4 CL, 5 EL, 6 ECL, 16 playoff, 17-18 down
        if (leagueCode === "BL1") return { cl: 4, el: 5, ecl: 6, relPlayoff: 16, relDirect: 17 };
        // 2. Bundesliga (18): 1-2 promotion, 3 playoff, 16 playoff, 17-18 down
        if (leagueCode === "BL2") return { cl: 0, el: 0, ecl: 0, promote: 2, promPlayoff: 3, relPlayoff: 16, relDirect: 17 };
        // 3. Liga (20): 1-2 promotion, 3 playoff, 17-20 down (no playoff)
        if (leagueCode === "BL3") return { cl: 0, el: 0, ecl: 0, promote: 2, promPlayoff: 3, relPlayoff: 0, relDirect: 17 };
        // Premier League (20): 1-4 CL, 5 EL, 18-20 down
        if (leagueCode === "PL") return { cl: 4, el: 5, ecl: 0, relPlayoff: 0, relDirect: 18 };
        // La Liga (20): 1-4 CL, 5 EL, 6 ECL, 18-20 down
        if (leagueCode === "PD") return { cl: 4, el: 5, ecl: 6, relPlayoff: 0, relDirect: 18 };
        // Serie A (20): 1-4 CL, 5 EL, 6 ECL, 18-20 down
        if (leagueCode === "SA") return { cl: 4, el: 5, ecl: 6, relPlayoff: 0, relDirect: 18 };
        // Ligue 1 (18): 1-3 CL, 4 EL, 16 playoff, 17-18 down
        if (leagueCode === "FL1") return { cl: 3, el: 4, ecl: 0, relPlayoff: 16, relDirect: 17 };
        // CL (group/league phase) — no relegation
        if (leagueCode === "CL") return { cl: 8, el: 0, ecl: 0, relPlayoff: 0, relDirect: 0 };

        // Fallback: top 4 CL, bottom 3 relegated
        return { cl: 4, el: 0, ecl: 0, relPlayoff: 0, relDirect: Math.max(n - 2, 1) };
    }

    // Yellow-ish for Europa / promotion playoff
    readonly property color _europaColor: "#E8A317"

    readonly property color positionColor: {
        if (!rowData || !_zones) return "transparent";
        var pos = rowData.position;

        // Promotion (2./3. Bundesliga)
        if (_zones.promote && pos <= _zones.promote) return Theme.primary;
        if (_zones.promPlayoff && pos === _zones.promPlayoff) return _europaColor;

        // Champions League
        if (_zones.cl && pos <= _zones.cl) return Theme.primary;
        // Europa League
        if (_zones.el && pos <= _zones.el) return _europaColor;
        // Conference League
        if (_zones.ecl && pos <= _zones.ecl) return _europaColor;

        // Direct relegation
        if (_zones.relDirect && pos >= _zones.relDirect) return Theme.error;
        // Relegation playoff
        if (_zones.relPlayoff && pos >= _zones.relPlayoff) return _europaColor;

        return "transparent";
    }

    width: parent.width
    implicitHeight: isHeader ? 28 : 34

    // Alternating row background
    Rectangle {
        visible: !isHeader
        anchors.fill: parent
        color: Theme.surfaceText
        opacity: (rowIndex % 2 === 0) ? 0.025 : 0
    }

    // Position indicator bar
    Rectangle {
        visible: !isHeader && rowData
        width: 3
        height: parent.height - 8
        radius: 1.5
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        color: positionColor
        opacity: 0.6
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingS
        spacing: 0

        // Position
        StyledText {
            Layout.preferredWidth: 22
            text: isHeader ? "#" : (rowData ? rowData.position : "")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: isHeader ? Font.Bold : Font.Medium
            color: isHeader ? Theme.surfaceVariantText : (positionColor !== "transparent" ? positionColor : Theme.surfaceText)
            horizontalAlignment: Text.AlignHCenter
        }

        // Trend indicator
        Item {
            Layout.preferredWidth: 14
            Layout.preferredHeight: parent.height
            visible: !isHeader

            // Up arrow
            StyledText {
                visible: rowData && rowData.trend === "up"
                anchors.centerIn: parent
                text: "\u25B2"
                font.pixelSize: 7
                color: Theme.primary
            }
            // Down arrow
            StyledText {
                visible: rowData && rowData.trend === "down"
                anchors.centerIn: parent
                text: "\u25BC"
                font.pixelSize: 7
                color: Theme.error
            }
            // Same (dot)
            Rectangle {
                visible: rowData && rowData.trend === "same"
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: 2
                color: Theme.surfaceVariantText
                opacity: 0.3
            }
        }

        // Header spacer for trend column
        Item {
            Layout.preferredWidth: 14
            visible: isHeader
        }

        // Team crest + name
        Row {
            Layout.fillWidth: true
            spacing: Theme.spacingXS

            Image {
                visible: !isHeader && rowData && (rowData.crest || "") !== ""
                source: (!isHeader && rowData) ? (rowData.crest || "") : ""
                sourceSize.width: 18
                sourceSize.height: 18
                width: 18
                height: 18
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            // Placeholder when no crest
            Item {
                visible: isHeader || !rowData || (rowData.crest || "") === ""
                width: isHeader ? 0 : 18
                height: 18
            }

            StyledText {
                text: isHeader ? "Team" : (rowData ? rowData.team : "")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: isHeader ? Font.Bold : Font.Normal
                color: isHeader ? Theme.surfaceVariantText : Theme.surfaceText
                elide: Text.ElideRight
                width: parent.width - (isHeader ? 0 : 18 + Theme.spacingXS)
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Played
        StyledText {
            Layout.preferredWidth: 22
            text: isHeader ? "P" : (rowData ? rowData.played : "")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
        }

        // W-D-L compact
        StyledText {
            Layout.preferredWidth: 44
            text: {
                if (isHeader) return "W-D-L";
                if (!rowData) return "";
                if (rowData.won === 0 && rowData.drawn === 0 && rowData.lost === 0) return "-";
                return rowData.won + "-" + rowData.drawn + "-" + rowData.lost;
            }
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
        }

        // Goals (GF:GA)
        StyledText {
            Layout.preferredWidth: 42
            text: {
                if (isHeader) return "G";
                if (!rowData) return "";
                if (rowData.gf === 0 && rowData.ga === 0) return "-";
                return rowData.gf + ":" + rowData.ga;
            }
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
        }

        // Goal difference
        StyledText {
            Layout.preferredWidth: 28
            text: isHeader ? "GD" : (rowData ? (rowData.gd > 0 ? "+" + rowData.gd : rowData.gd) : "")
            font.pixelSize: Theme.fontSizeSmall
            color: {
                if (isHeader || !rowData) return Theme.surfaceVariantText;
                if (rowData.gd > 0) return Theme.primary;
                if (rowData.gd < 0) return Theme.error;
                return Theme.surfaceVariantText;
            }
            horizontalAlignment: Text.AlignHCenter
        }

        // Points — highlighted
        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 22
            radius: 6
            color: isHeader ? "transparent" : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)

            StyledText {
                anchors.centerIn: parent
                text: isHeader ? "Pts" : (rowData ? rowData.points : "")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
                color: isHeader ? Theme.surfaceVariantText : Theme.surfaceText
            }
        }
    }

    // Header separator
    Rectangle {
        visible: isHeader
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.outline
        opacity: 0.12
    }
}
