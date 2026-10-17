import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import shell.services as Ryoku
import "../../"
import "../"
import "glassNesting.js" as Nesting

Item {
    id: root

    property real radius: ThemeBackend.borderRadius
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomLeftRadius: radius
    property real bottomRightRadius: radius
    property real blurStrength: 1.0
    property real tint: 0.0
    property real rim: 0.45
    property bool standalone: false
    property bool surfaceEnabled: true
    property var screenOverride: null
    property bool useSnapshot: false

    readonly property bool liquid: ThemeBackend.liquidGlass
    readonly property bool isGlassBackdrop: true
    property alias texture: glassTexture
    property int consumers: 0
    property int nestLevel: 0
    readonly property real nest: Math.min(1, nestLevel * 0.5)
    property int frame: 0

    readonly property var hostWindow: QsWindow.window
    readonly property var hostScreen: screenOverride ? screenOverride : (hostWindow ? hostWindow.screen : null)
    readonly property string wallpaperPath: Ryoku.Session.wallIsVideo
        ? Ryoku.Session.livePoster : Ryoku.Session.wallpaper
    readonly property string wallpaperUrl: wallpaperPath !== ""
        ? "file://" + wallpaperPath + "?rev=" + revision : ""
    readonly property bool active: surfaceEnabled && ThemeBackend.blurBackground
        && ThemeBackend.elementOpacity < 0.999 && width > 0 && height > 0
        && hostScreen !== null && wallpaperPath !== ""
        && (hostWindow ? hostWindow.visible : true)

    property real imageX: 0
    property real imageY: 0
    property real imageScale: 1
    property real imageRotation: 0
    property int revision: 0

    readonly property real screenWidth: hostScreen ? hostScreen.width : 1
    readonly property real screenHeight: hostScreen ? hostScreen.height : 1
    readonly property size textureSize: Qt.size(
        Math.max(1, Math.round(screenWidth / (liquid ? 2 : 4))),
        Math.max(1, Math.round(screenHeight / (liquid ? 2 : 4))))

    visible: active
    clip: false

    Component.onCompleted: {
        nestLevel = standalone ? 0 : Nesting.nestLevel(root, null, true);
        refreshGeometry();
    }

    function refreshTexture() {
        root.frame++;
        if (root.consumers > 0) glassTexture.scheduleUpdate();
    }

    function refreshGeometry() {
        const w = root.hostWindow;
        const scr = root.hostScreen;
        if (!scr) return;
        let wx = 0;
        let wy = 0;
        if (w && w.anchors && !root.screenOverride) {
            const a = w.anchors;
            const m = w.margins;
            if (a.left) wx = m.left;
            else if (a.right) wx = scr.width - w.width - m.right;
            else wx = (scr.width - w.width) / 2;
            if (a.top) wy = m.top;
            else if (a.bottom) wy = scr.height - w.height - m.bottom;
            else wy = (scr.height - w.height) / 2;
        }
        const p0 = root.mapFromItem(null, -wx, -wy);
        const px = root.mapFromItem(null, 1 - wx, -wy);
        const dx = px.x - p0.x;
        const dy = px.y - p0.y;
        const len = Math.sqrt(dx * dx + dy * dy);
        if (!isFinite(len) || len <= 0) return;
        root.imageX = p0.x;
        root.imageY = p0.y;
        root.imageScale = len;
        root.imageRotation = Math.atan2(dy, dx) * 180 / Math.PI;
        root.refreshTexture();
    }

    onXChanged: refreshGeometry()
    onYChanged: refreshGeometry()
    onWidthChanged: refreshGeometry()
    onHeightChanged: refreshGeometry()
    onHostScreenChanged: refreshGeometry()
    onWallpaperUrlChanged: refreshTexture()
    onConsumersChanged: refreshTexture()
    onLiquidChanged: refreshTexture()
    onTintChanged: refreshTexture()
    onBlurStrengthChanged: refreshTexture()
    onActiveChanged: if (active) refreshGeometry()

    FileView {
        path: root.active ? root.wallpaperPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: root.revision++
    }

    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            bottomRightRadius: root.bottomRightRadius
            color: "black"
        }
    }

    Item {
        id: content
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.mipmap: root.liquid
        layer.smooth: true

        Image {
            x: root.imageX
            y: root.imageY
            width: root.screenWidth
            height: root.screenHeight
            scale: root.imageScale
            transformOrigin: Item.TopLeft
            rotation: root.imageRotation
            source: root.wallpaperUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            sourceSize: root.textureSize
            onStatusChanged: root.refreshTexture()
        }

        Rectangle {
            anchors.fill: parent
            visible: root.tint > 0
            color: Qt.alpha(ThemeBackend.base, root.tint)
        }
    }

    Item {
        id: rendered
        anchors.fill: parent

        MultiEffect {
            anchors.fill: parent
            visible: !root.liquid
            source: content
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: Math.min(1.0, root.blurStrength)
            maskEnabled: true
            maskSource: mask
        }

        LiquidGlass {
            anchors.fill: parent
            visible: root.liquid
            src: content
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            bottomRightRadius: root.bottomRightRadius
            tintColor: ThemeBackend.base
            tintAmount: Math.max(root.tint, 0.12) * (1 - 0.5 * root.nest)
            frost: Math.max(0.5, root.blurStrength * 2.5) * 1.08 * (1 - 0.5 * root.nest)
            rim: root.rim * (1 - 0.35 * root.nest)
            nest: root.nest
            clear: root.nestLevel >= 1 ? 1 : 0
            cursorPos: Qt.point(root.cursorX, root.cursorY)
            hover: root.hoverAmount
        }
    }

    ShaderEffectSource {
        id: glassTexture
        anchors.fill: parent
        sourceItem: rendered
        live: false
        mipmap: true
        visible: false
        smooth: true
        format: ShaderEffectSource.RGBA8
    }

    HoverHandler {
        id: pointer
        enabled: root.liquid
    }

    property real hoverAmount: pointer.hovered ? 1.0 : 0.0
    Behavior on hoverAmount { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    property real cursorX: width / 2
    property real cursorY: height / 2
    Behavior on cursorX { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on cursorY { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Connections {
        target: pointer
        function onPointChanged() {
            if (pointer.hovered) {
                root.cursorX = pointer.point.position.x;
                root.cursorY = pointer.point.position.y;
            }
        }
    }
}
