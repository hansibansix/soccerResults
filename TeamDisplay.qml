import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    required property string teamName
    required property string crestUrl
    property int crestSize: 32
    property bool dimmed: false
    property real maxNameWidth: 100
    property color nameColor: Theme.surfaceText

    Column {
        anchors.centerIn: parent
        spacing: 5

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.crestUrl
            sourceSize.width: root.crestSize
            sourceSize.height: root.crestSize
            width: root.crestSize
            height: root.crestSize
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: root.dimmed ? 0.45 : 1.0
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, root.maxNameWidth)
            text: root.teamName
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            color: root.nameColor
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
