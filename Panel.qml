import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "daryn.pipeline-watch"
  ipcTarget: "daryn.pipeline-watch"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color secondaryForeground: Util.alpha(contentForeground, 0.54)

  // Data state
  property int activeCount: 0
  property real totalCpu: 0.0
  property string totalMemory: "0 B"
  property var jobs: []
  property var history: []
  property bool inhibitSleep: false

  property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/daryn.pipeline-watch"

  function refresh() {
    if (!scanProc.running) scanProc.running = true
  }

  function killJob(pid) {
    if (!pid) return
    Quickshell.execDetached([root.pluginDir + "/scanner.py", "--kill", pid.toString()])
    Qt.callLater(root.refresh)
  }

  Process {
    id: scanProc
    command: [root.pluginDir + "/scanner.py"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          root.activeCount = res.activeCount || 0
          root.totalCpu = res.totalCpu || 0.0
          root.totalMemory = res.totalMemory || "0 B"
          root.jobs = res.jobs || []
          root.history = res.history || []
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 2500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  PopupCard {
    id: card
    anchorItem: root.anchorItem
    width: Style.space(480)
    height: Math.min(Style.space(560), parent.height - Style.gapsOut * 2)

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.md

      // --- HEADER ---
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.sm

        Text {
          text: root.activeCount > 0 ? "󰐊" : ""
          color: root.activeCount > 0 ? Color.accent : root.contentForeground
          font.pixelSize: Style.font.heading * 1.2
        }

        ColumnLayout {
          spacing: 2
          Layout.fillWidth: true

          Text {
            text: "Pipeline & Compute Watcher"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            text: root.activeCount > 0 
              ? root.activeCount + " active job" + (root.activeCount > 1 ? "s" : "") + " • CPU: " + root.totalCpu + "% • RAM: " + root.totalMemory
              : "No compute or training jobs active"
            color: root.secondaryForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          height: 24
          width: refText.implicitWidth + 14
          radius: 12
          color: refMouse.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.15) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.07)

          Text {
            id: refText
            anchors.centerIn: parent
            text: "↻ Scan"
            color: root.contentForeground
            font.pixelSize: 11
          }

          MouseArea {
            id: refMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.refresh()
          }
        }
      }

      PanelSeparator { Layout.fillWidth: true }

      // --- ACTIVE JOBS SECTION ---
      PanelSectionHeader {
        text: "ACTIVE PIPELINES & WORKLOADS (" + root.jobs.length + ")"
        Layout.fillWidth: true
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: root.jobs.length > 0 ? Math.min(200, root.jobs.length * 68) : 50

        Text {
          anchors.centerIn: parent
          text: "No active pipelines detected (R, Python, Quarto, DuckDB)"
          color: root.secondaryForeground
          font.italic: true
          font.pixelSize: Style.font.caption
          visible: root.jobs.length === 0
        }

        ListView {
          anchors.fill: parent
          clip: true
          model: root.jobs
          spacing: 6
          visible: root.jobs.length > 0

          delegate: Rectangle {
            width: parent.width
            height: 62
            radius: Style.cornerRadius / 2
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
            border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)
            border.width: 1

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: 8
              spacing: 4

              RowLayout {
                Layout.fillWidth: true
                spacing: 6

                // Type Badge
                Rectangle {
                  height: 18
                  width: typeBadgeText.implicitWidth + 10
                  radius: 9
                  color: modelData.type === "r" ? "#276dc3" : (modelData.type === "python" ? "#ffd343" : (modelData.type === "quarto" ? "#447099" : Color.accent))

                  Text {
                    id: typeBadgeText
                    anchors.centerIn: parent
                    text: (modelData.type || "JOB").toUpperCase()
                    color: modelData.type === "python" ? "#000000" : "#ffffff"
                    font.bold: true
                    font.pixelSize: 9
                  }
                }

                Text {
                  text: modelData.name
                  color: root.contentForeground
                  font.bold: true
                  font.pixelSize: Style.font.body
                  elide: Text.ElideMiddle
                  Layout.fillWidth: true
                }

                Text {
                  text: "⏱ " + modelData.runtime
                  color: root.secondaryForeground
                  font.pixelSize: Style.font.caption
                }

                Text {
                  text: "󰘚 " + modelData.memory
                  color: root.secondaryForeground
                  font.pixelSize: Style.font.caption
                }

                // Kill Button
                Rectangle {
                  width: 20
                  height: 20
                  radius: 10
                  color: killMouse.containsMouse ? Qt.rgba(1, 0, 0, 0.3) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1)

                  Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: root.contentForeground
                    font.pixelSize: 10
                  }

                  MouseArea {
                    id: killMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.killJob(modelData.pid)
                  }
                }
              }

              Text {
                text: "PID " + modelData.pid + " • CPU: " + modelData.cpu + "% • " + modelData.cmd
                color: root.secondaryForeground
                font.family: "monospace"
                font.pixelSize: Style.font.caption * 0.9
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
          }
        }
      }

      PanelSeparator { Layout.fillWidth: true }

      // --- RECENT COMPLETED PIPELINES SECTION ---
      PanelSectionHeader {
        text: "COMPLETED PIPELINES HISTORY"
        Layout.fillWidth: true
      }

      ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: root.history
        spacing: 4

        delegate: Rectangle {
          width: parent.width
          height: 38
          radius: Style.cornerRadius / 2
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.03)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Text {
              text: "✓"
              color: "#2ecc71"
              font.bold: true
              font.pixelSize: 12
            }

            Text {
              text: modelData.name
              color: root.contentForeground
              font.bold: true
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
              Layout.fillWidth: true
            }

            Text {
              text: modelData.duration
              color: root.secondaryForeground
              font.pixelSize: Style.font.caption
            }

            Text {
              text: "Peak: " + modelData.peakMemory
              color: root.secondaryForeground
              font.pixelSize: Style.font.caption
            }

            Text {
              text: modelData.completedAt
              color: root.secondaryForeground
              opacity: 0.7
              font.pixelSize: Style.font.caption * 0.9
            }
          }
        }
      }
    }
  }
}
