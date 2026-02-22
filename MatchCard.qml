import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "SoccerApi.js" as Api

StyledRect {
    id: card

    required property var matchData
    property bool pinned: false

    signal pinClicked()

    readonly property bool live: matchData ? Api.isLive(matchData.status) : false
    readonly property bool finished: matchData ? Api.isFinished(matchData.status) : false
    readonly property int crestSize: 32
    readonly property color teamTextColor: finished ? Theme.surfaceVariantText : Theme.surfaceText

    width: parent.width
    implicitHeight: 88
    radius: Theme.cornerRadius
    color: live ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06)
                : Theme.surfaceContainerHigh

    border.color: live ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
    border.width: live ? 1 : 0

    Behavior on color { ColorAnimation { duration: Theme.shortDuration } }

    // Left status strip
    Rectangle {
        width: 3
        height: parent.height - 16
        radius: 1.5
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        color: {
            if (live) return Theme.primary;
            if (finished) return Theme.surfaceVariantText;
            return "transparent";
        }
        opacity: live ? 1.0 : 0.25

        SequentialAnimation on opacity {
            running: live
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutSine }
        }
    }

    // Pin button
    DankIcon {
        id: pinIcon
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 6
        name: "push_pin"
        size: 13
        color: pinned ? Theme.primary : Theme.surfaceVariantText
        opacity: pinned ? 1.0 : (pinArea.containsMouse ? 0.7 : 0)

        Behavior on opacity { NumberAnimation { duration: 150 } }

        MouseArea {
            id: pinArea
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.pinClicked()
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingM + 2
        anchors.rightMargin: Theme.spacingM
        spacing: 0

        // Home team
        TeamDisplay {
            Layout.fillWidth: true
            Layout.fillHeight: true
            teamName: matchData ? matchData.homeTeam : ""
            crestUrl: matchData ? matchData.homeCrest || "" : ""
            crestSize: card.crestSize
            dimmed: finished
            maxNameWidth: card.width / 2 - 72
            nameColor: teamTextColor
        }

        // Score / status center
        Item {
            Layout.preferredWidth: 100
            Layout.fillHeight: true

            // Score pill background
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                width: 80
                height: 52
                radius: 10
                color: {
                    if (live) return Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10);
                    var a = finished ? 0.04 : 0.03;
                    return Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, a);
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -2
                spacing: 3

                StyledText {
                    width: 100
                    text: matchData ? Api.scoreText(matchData) : ""
                    font.pixelSize: live ? 20 : 17
                    font.weight: Font.Bold
                    color: live ? Theme.primary : (finished ? Theme.surfaceVariantText : Theme.surfaceText)
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    width: 100
                    text: {
                        if (!matchData) return "";
                        if (live) {
                            var min = matchData.minute ? matchData.minute + "'" : Api.estimateMinute(matchData);
                            return min || "Live";
                        }
                        return Api.matchStatusLabel(matchData.status);
                    }
                    font.pixelSize: 11
                    font.weight: live ? Font.Bold : Font.Normal
                    color: live ? Theme.primary : Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    opacity: live ? 0.9 : 0.5
                }
            }
        }

        // Away team
        TeamDisplay {
            Layout.fillWidth: true
            Layout.fillHeight: true
            teamName: matchData ? matchData.awayTeam : ""
            crestUrl: matchData ? matchData.awayCrest || "" : ""
            crestSize: card.crestSize
            dimmed: finished
            maxNameWidth: card.width / 2 - 72
            nameColor: teamTextColor
        }
    }
}
