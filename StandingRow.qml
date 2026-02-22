import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Item {
    id: row

    required property var rowData
    property bool isHeader: false
    property int rowIndex: rowData ? rowData.position - 1 : 0

    readonly property color positionColor: {
        if (!rowData) return "transparent";
        if (rowData.position <= 4) return Theme.primary;
        if (rowData.position >= 18) return Theme.error;
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
            Layout.preferredWidth: 24
            text: isHeader ? "#" : (rowData ? rowData.position : "")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: isHeader ? Font.Bold : Font.Medium
            color: isHeader ? Theme.surfaceVariantText : (positionColor !== "transparent" ? positionColor : Theme.surfaceText)
            horizontalAlignment: Text.AlignHCenter
        }

        // Team name
        StyledText {
            Layout.fillWidth: true
            text: isHeader ? "Team" : (rowData ? rowData.team : "")
            font.pixelSize: Theme.fontSizeSmall
            font.weight: isHeader ? Font.Bold : Font.Normal
            color: isHeader ? Theme.surfaceVariantText : Theme.surfaceText
            elide: Text.ElideRight
            leftPadding: Theme.spacingXS
        }

        StyledText {
            Layout.preferredWidth: 26
            text: isHeader ? "P" : (rowData ? rowData.played : "")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
        }

        StyledText {
            Layout.preferredWidth: 26
            text: isHeader ? "W" : (rowData ? rowData.won : "")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
        }

        StyledText {
            Layout.preferredWidth: 26
            text: isHeader ? "D" : (rowData ? rowData.drawn : "")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
        }

        StyledText {
            Layout.preferredWidth: 26
            text: isHeader ? "L" : (rowData ? rowData.lost : "")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
        }

        StyledText {
            Layout.preferredWidth: 30
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
