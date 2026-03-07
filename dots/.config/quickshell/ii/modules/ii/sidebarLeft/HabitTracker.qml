import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property real padding: 10
    property string currentTask: ""
    property string currentDuration: ""
    property bool isIdle: true
    property var todayEntries: []

    Component.onCompleted: {
        refreshStatus.running = true;
        refreshToday.running = true;
    }

    Process {
        id: statusProc
        command: ["python3", Quickshell.env("HOME") + "/.config/habits/habit-clock.py", "status"]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { statusProc.buffer += data; }
        }
        onExited: (exitCode, exitStatus) => {
            let output = statusProc.buffer.trim();
            statusProc.buffer = "";
            if (output === "idle" || output === "") {
                root.isIdle = true;
                root.currentTask = "";
                root.currentDuration = "";
            } else {
                root.isIdle = false;
                let parts = output.split(" | ");
                root.currentTask = parts[0] || "";
                root.currentDuration = parts[1] || "0:00";
            }
        }
    }

    Process {
        id: todayProc
        command: ["python3", Quickshell.env("HOME") + "/.config/habits/habit-clock.py", "today"]
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { todayProc.buffer += data + "\n"; }
        }
        onExited: (exitCode, exitStatus) => {
            let output = todayProc.buffer.trim();
            todayProc.buffer = "";
            let entries = [];
            if (output && output !== "No entries today") {
                let lines = output.split("\n");
                for (let line of lines) {
                    let trimmed = line.trim();
                    if (trimmed.length > 0) {
                        let colonIdx = trimmed.lastIndexOf(":");
                        if (colonIdx > 0) {
                            entries.push({
                                "task": trimmed.substring(0, colonIdx).trim(),
                                "time": trimmed.substring(colonIdx + 1).trim()
                            });
                        }
                    }
                }
            }
            root.todayEntries = entries;
        }
    }

    Timer {
        id: refreshStatus
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statusProc.buffer = "";
            statusProc.running = true;
        }
    }

    Timer {
        id: refreshToday
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            todayProc.buffer = "";
            todayProc.running = true;
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 12

        // Current status card
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: statusColumn.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: root.isIdle ? Appearance.colors.colLayer2 : Appearance.colors.colSecondaryContainer

            ColumnLayout {
                id: statusColumn
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 4

                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: root.isIdle ? "pause_circle" : "timer"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: root.isIdle ? Appearance.colors.colSubtext : Appearance.m3colors.m3onSecondaryContainer
                    }
                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            text: root.isIdle ? "Idle" : root.currentTask
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.bold: true
                            color: root.isIdle ? Appearance.colors.colSubtext : Appearance.m3colors.m3onSecondaryContainer
                        }
                        StyledText {
                            visible: !root.isIdle
                            text: root.currentDuration
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: root.isIdle ? Appearance.colors.colSubtext : Appearance.m3colors.m3onSecondaryContainer
                            opacity: 0.7
                        }
                    }
                }
            }
        }

        // Section header
        StyledText {
            text: "Today"
            font.pixelSize: Appearance.font.pixelSize.large
            font.bold: true
            color: Appearance.colors.colOnLayer1
            Layout.topMargin: 4
        }

        // Today's entries
        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: todayColumn.implicitHeight

            ColumnLayout {
                id: todayColumn
                anchors {
                    left: parent.left
                    right: parent.right
                }
                spacing: 6

                Repeater {
                    model: root.todayEntries

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: entryRow.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            id: entryRow
                            anchors {
                                fill: parent
                                margins: 8
                            }
                            spacing: 8

                            MaterialSymbol {
                                text: "schedule"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer2
                                opacity: 0.6
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.task
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                            StyledText {
                                text: modelData.time
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                                opacity: 0.7
                            }
                        }
                    }
                }

                // Empty state
                Item {
                    visible: root.todayEntries.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60

                    StyledText {
                        anchors.centerIn: parent
                        text: "No entries today"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
            }
        }

        // Refresh button
        RippleButton {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 32
            implicitWidth: refreshRow.implicitWidth + 20
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover

            onClicked: {
                statusProc.buffer = "";
                statusProc.running = true;
                todayProc.buffer = "";
                todayProc.running = true;
            }

            contentItem: RowLayout {
                id: refreshRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    text: "Refresh"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }
}
