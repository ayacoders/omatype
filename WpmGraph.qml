import QtQuick
import qs.Commons
import "TypingTestModel.js" as TypingTestModel

// WPM over the course of the run, one point per elapsed second. The same
// samples feed the consistency stat, so a jagged line and a low consistency
// score are two views of one thing — and the average line marks the centre
// that score measures the spread around.
Item {
  id: root

  required property var samples
  property real duration: 0

  property string fontFamily: "monospace"
  property color lineColor: "white"
  property color gridColor: "gray"
  property color mutedText: "gray"

  // One point is a dot, not a line; the run was too short to plot.
  readonly property bool hasData: root.samples && root.samples.length >= 2
  readonly property int maxValue: TypingTestModel.niceMax(root.samples)
  readonly property real average: TypingTestModel.mean(root.samples)

  visible: root.hasData

  // Axis labels sit outside the plot rather than over it.
  readonly property real gutter: Math.max(maxLabel.implicitWidth, zeroLabel.implicitWidth,
    averageLabel.implicitWidth) + Style.spacing.sm
  readonly property real footer: startLabel.implicitHeight + Style.spacing.md
  // Mirrored on the right so the plot sits centred under the stats rather
  // than pushed across by the width of the labels.
  readonly property real plotWidth: Math.max(0, root.width - root.gutter * 2)
  readonly property real plotHeight: Math.max(0, root.height - root.footer)

  function yFor(value) {
    if (root.maxValue <= 0) return root.plotHeight
    return root.plotHeight - (Math.max(0, Math.min(value, root.maxValue)) / root.maxValue) * root.plotHeight
  }

  component AxisLabel: Text {
    color: root.mutedText
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  AxisLabel {
    id: maxLabel
    text: root.maxValue
    x: root.gutter - Style.spacing.sm - implicitWidth
    y: -height / 2
  }

  AxisLabel {
    id: zeroLabel
    text: "0"
    x: root.gutter - Style.spacing.sm - implicitWidth
    y: root.plotHeight - height / 2
  }

  AxisLabel {
    id: averageLabel
    text: "avg " + Math.round(root.average)
    color: root.lineColor
    opacity: 0.7
    x: root.gutter - Style.spacing.sm - implicitWidth
    y: root.yFor(root.average) - height / 2
    // Suppressed near the axis bounds, where it would sit on top of 0 or the
    // ceiling rather than beside its own line.
    visible: root.average > 0
      && Math.abs(y) > height
      && Math.abs(y - (root.plotHeight - height / 2)) > height
  }

  AxisLabel {
    id: startLabel
    text: "0s"
    x: root.gutter
    y: root.plotHeight + Style.spacing.md
  }

  AxisLabel {
    text: Math.round(root.duration) + "s"
    x: root.gutter + root.plotWidth - implicitWidth
    y: root.plotHeight + Style.spacing.md
  }

  Canvas {
    id: canvas
    x: root.gutter
    y: 0
    width: root.plotWidth
    height: root.plotHeight

    // Canvas repaints on resize, but not when the data behind it changes.
    Connections {
      target: root
      function onSamplesChanged() { canvas.requestPaint() }
      function onLineColorChanged() { canvas.requestPaint() }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()

      var points = TypingTestModel.graphPoints(root.samples, width, height, root.maxValue)
      if (points.length < 2) return

      ctx.strokeStyle = root.gridColor
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(0, height - 0.5)
      ctx.lineTo(width, height - 0.5)
      ctx.moveTo(0, 0.5)
      ctx.lineTo(width, 0.5)
      ctx.stroke()

      // Area under the line first, so the stroke sits on top of its own fill.
      ctx.beginPath()
      ctx.moveTo(points[0].x, height)
      for (var i = 0; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y)
      ctx.lineTo(points[points.length - 1].x, height)
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.12)
      ctx.fill()

      if (root.average > 0) {
        var averageY = root.yFor(root.average)
        ctx.save()
        if (ctx.setLineDash) ctx.setLineDash([4, 4])
        ctx.strokeStyle = Qt.rgba(root.lineColor.r, root.lineColor.g, root.lineColor.b, 0.55)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(0, averageY)
        ctx.lineTo(width, averageY)
        ctx.stroke()
        ctx.restore()
      }

      // Straight segments rather than a smoothed spline: the jitter between
      // seconds is the point, and smoothing would flatter it away.
      ctx.beginPath()
      ctx.moveTo(points[0].x, points[0].y)
      for (var j = 1; j < points.length; j++) ctx.lineTo(points[j].x, points[j].y)
      ctx.strokeStyle = root.lineColor
      ctx.lineWidth = Math.max(2, Style.space(2))
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.stroke()
    }
  }
}
