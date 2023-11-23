// Stats for Template Stage

{
	spriteContent: self.getResource().getContent("paletteeditor"),
	animationId: "stage",
	ambientColor: 0x00,
	shadowLayers: [],
	camera: {
		startX : 0,
		startY : 0,
		zoomX : 0,
		zoomY : 0,
		camEaseRate : 1 / 11,
		camZoomRate : 1 / 15,
		minZoomHeight: 360,
		initialHeight: 360,
		initialWidth: 640,
		backgrounds: [{
			spriteContent: self.getResource().getContent("paletteeditor"),
			animationId: "grey_bg",
			mode: ParallaxMode.BOUNDS,
			originalBGWidth: 640,
			originalBGHeight: 360,
			horizontalScroll: true,
			verticalScroll: true,
			loopWidth: 0,
			loopHeight: 0,
			xPanMultiplier: 0.06,
			yPanMultiplier: 0.06,
			scaleMultiplier: 1,
			foreground: false,
			depth: 2000
		}]
	}
}
