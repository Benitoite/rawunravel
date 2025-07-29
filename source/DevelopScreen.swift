import SwiftUI
import UIKit

struct DevelopScreen: View {
    let fileURL: URL
   
    @State private var currentPP3: String = ""
    
    // Main image and zoom state
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Export/screenshot state
    @State private var showExportSheet = false
    @State private var showExportSuccess = false
    @State private var screenshotForExport: UIImage?
    @State private var showScreenshotExportSheet = false

    // Other UI state
    @State private var isLoading = false
    @State private var showExposurePanel = false
    @State private var exposureCompensation: Float = 0.0
    @State private var blackPoint: Float = 0.0
    @State private var shadows: Float = 0.0
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                ZStack {
                    if let ui = image {
                        ZoomableImageView(
                            image: ui,
                            zoomScale: $zoom,
                            minScale: 1.0,
                            maxScale: 8.0,
                            offset: $offset,
                            lastOffset: $lastOffset
                        )
                    }

                    // Screenshot button (visible crop)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                if let img = image {
                                    // Use the actual geometry size!
                                    let snap = CroppableImage(image: img, zoomScale: zoom, offset: offset)
                                        .snapshot(size: geometry.size)
                                    screenshotForExport = snap
                                }
                            
                            }) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 30))
                                    .padding()
                                    .background(Color.black.opacity(0.13))
                                    .clipShape(Circle())
                                    .shadow(radius: 5)
                            }
                            .padding(.trailing, 26)
                            .padding(.bottom, 88)
                        }
                    }

                    // --- Spinner Overlay ---
                    if isLoading {
                        ZStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(5.0)
                                .offset(x: 2, y: 2)
                                .opacity(0.99)
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .yellow))
                                .scaleEffect(5.0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.01).ignoresSafeArea())
                    }
                }
            }

            // --- Sun + Exposure Panel (top right) ---
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: { withAnimation { showExposurePanel.toggle() } }) {
                        Text("🌞")
                            .font(.title)
                            .padding(8)
                            .background(Color.black.opacity(0.05))
                            .clipShape(Circle())
                    }
                }
                .padding([.top, .trailing])
                if showExposurePanel {
                    SunExposurePanel(
                        exposure: $exposureCompensation,
                        blackPoint: $blackPoint,
                        shadows: $shadows
                    ) { newPP3 in
                        currentPP3 = newPP3
                        processRAW()
                        showExposurePanel = false
                    }
                    .padding()
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(10)
                    .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            // --- EXPORT BUTTON (bottom right) ---
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showExportSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 30, weight: .bold))
                            .padding()
                            .background(Color.black.opacity(0.1))
                            .clipShape(Circle())
                            .shadow(radius: 6)
                    }
                    .padding([.trailing, .bottom], 26)
                }
            }

            // --- EXPORT SUCCESS TOAST ---
            if showExportSuccess {
                Text("Export successful!")
                    .font(.headline)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 32)
                    .background(Color.black.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(radius: 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(999)
                    .padding(.bottom, 64)
            }
        }
        .sheet(isPresented: $showScreenshotExportSheet) {
            if let cropped = screenshotForExport {
                ExportJPGSheet(
                    image: cropped,
                    sourceFileURL: fileURL,
                    currentPP3: currentPP3    // <-- PASS IT HERE TOO
                ) {
                    showScreenshotExportSheet = false
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportJPGSheet(
                image: image ?? UIImage(),
                sourceFileURL: fileURL,
                currentPP3: currentPP3      // <-- THIS IS THE FIX
            ) {
                showExportSheet = false
            }
        }
        .onAppear { initialLoad() }
        .onChange(of: screenshotForExport) { newImage in
            if newImage != nil {
                showScreenshotExportSheet = true
            }
        }
    }

    func processRAW() {
        isLoading = true
        let pp3String = """
        [Exposure]
        Compensation = \(String(format: "%.2f", exposureCompensation))
        Black = \(String(format: "%.3f", blackPoint))
        Shadows = \(String(format: "%.2f", shadows))
        """
        let tempPP3 = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp.pp3")
        try? pp3String.write(to: tempPP3, atomically: true, encoding: .utf8)
        DispatchQueue.global(qos: .userInitiated).async {
            let ui = RTPreviewDecoder.decodeRAWPreview(atPath: fileURL.path, withPP3Path: tempPP3.path)
            DispatchQueue.main.async {
                self.image = ui
                self.isLoading = false
            }
        }
    }

    func initialLoad() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ui = RTPreviewDecoder.decodeRAWPreview(atPath: fileURL.path, withPP3Path: "")
            DispatchQueue.main.async {
                self.image = ui
                self.isLoading = false
            }
        }
    }
}

// --- ZOOMABLE IMAGE VIEW ---

struct ZoomableImageView: View {
    let image: UIImage
    @Binding var zoomScale: CGFloat
    let minScale: CGFloat
    let maxScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    @State private var lastScale: CGFloat = 1.0

    func clampedOffset(for offset: CGSize, imageSize: CGSize, geoSize: CGSize, zoom: CGFloat) -> CGSize {
        let scale = max(imageSize.width / geoSize.width, imageSize.height / geoSize.height)
        let scaledWidth = imageSize.width / scale * zoom
        let scaledHeight = imageSize.height / scale * zoom

        let maxX = max((scaledWidth - geoSize.width) / 2, 0)
        let maxY = max((scaledHeight - geoSize.height) / 2, 0)

        let clampedX = min(max(offset.width, -maxX), maxX)
        let clampedY = min(max(offset.height, -maxY), maxY)
        return CGSize(width: clampedX, height: clampedY)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(zoomScale)
                    .offset(offset)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { val in
                                    let delta = val / lastScale
                                    lastScale = val
                                    let newZoom = (zoomScale * delta).myClamped(to: minScale...maxScale)
                                    let clamped = clampedOffset(for: offset, imageSize: image.size, geoSize: geo.size, zoom: newZoom)
                                    zoomScale = newZoom
                                    offset = clamped
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    if zoomScale <= 1.01 {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                },
                            DragGesture()
                                .onChanged { value in
                                    if zoomScale > 1.01 {
                                        let rawOffset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                        offset = clampedOffset(for: rawOffset, imageSize: image.size, geoSize: geo.size, zoom: zoomScale)
                                    }
                                }
                                .onEnded { _ in
                                    if zoomScale > 1.01 {
                                        lastOffset = offset
                                    } else {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                        )
                    )
                    .animation(.interactiveSpring(), value: offset)
                // ---- Zoom Controls Overlay ----
                let oneToOneScale = max(image.size.width / geo.size.width, image.size.height / geo.size.height)
                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        VStack(spacing: 12) {
                            // Zoom In
                            Button(action: {
                                let newZoom = min(zoomScale * 1.5, maxScale)
                                zoomScale = newZoom
                                offset = clampedOffset(for: offset, imageSize: image.size, geoSize: geo.size, zoom: newZoom)
                                lastOffset = offset
                            }) {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 28))
                                    .frame(width: 44, height: 44)
                                    .foregroundColor(.blue)
                            }
                            // Zoom Out
                            Button(action: {
                                let newZoom = max(zoomScale / 1.5, minScale)
                                zoomScale = newZoom
                                offset = clampedOffset(for: offset, imageSize: image.size, geoSize: geo.size, zoom: newZoom)
                                lastOffset = offset
                            }) {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.system(size: 28))
                                    .frame(width: 44, height: 44)
                                    .foregroundColor(.blue)
                            }
                            // Fit to screen
                            Button(action: {
                                zoomScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }) {
                                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .foregroundColor(.blue)
                            }
                            // 1:1 (pixel crop)
                            Button(action: {
                                let scaleX = image.size.width / geo.size.width
                                let scaleY = image.size.height / geo.size.height
                                let oneToOneScale = max(scaleX, scaleY)
                                zoomScale = oneToOneScale.myClamped(to: minScale...maxScale)
                                let contentWidth = geo.size.width * zoomScale
                                let contentHeight = geo.size.height * zoomScale
                                let dx = (contentWidth - geo.size.width) / 2
                                let dy = (contentHeight - geo.size.height) / 2
                                let desired = CGSize(width: -dx, height: -dy)
                                let clamped = clampedOffset(for: desired, imageSize: image.size, geoSize: geo.size, zoom: zoomScale)
                                offset = clamped
                                lastOffset = clamped
                            }) {
                                Text("1:1")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .frame(width: 44, height: 44)
                                    .foregroundColor(.blue)
                            }
                            // Zoom % Overlay
                            Text("\(Int(round(zoomScale / oneToOneScale * 100)))%")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(.leading, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// --- Utilities ---

extension Comparable {
    func myClamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
extension UIImage {
    func resizedToFit(maxWidth: CGFloat) -> UIImage {
        if size.width <= maxWidth { return self }
        let scale = maxWidth / size.width
        let newSize = CGSize(width: maxWidth, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? self
    }
}


func cropVisibleImage(
    image: UIImage,
    zoomScale: CGFloat,
    offset: CGSize,
    viewportSize: CGSize
) -> UIImage {
    // Step 1: Compute aspect fit rect for image in viewport
    let imageAspect = image.size.width / image.size.height
    let viewportAspect = viewportSize.width / viewportSize.height

    var fittedSize: CGSize
    if imageAspect > viewportAspect {
        fittedSize = CGSize(width: viewportSize.width, height: viewportSize.width / imageAspect)
    } else {
        fittedSize = CGSize(width: viewportSize.height * imageAspect, height: viewportSize.height)
    }
    let fittedOrigin = CGPoint(
        x: (viewportSize.width - fittedSize.width) / 2,
        y: (viewportSize.height - fittedSize.height) / 2
    )

    // Step 2: Compute the center of the displayed image in the viewport
    // In SwiftUI, .offset moves the image relative to center, so positive offset moves the image right/down (which means you see more of the left/top)
    let displayCenter = CGPoint(
        x: viewportSize.width / 2 + offset.width,
        y: viewportSize.height / 2 + offset.height
    )

    // Step 3: The size of the displayed image *after* zoom
    let displayedSize = CGSize(width: fittedSize.width * zoomScale, height: fittedSize.height * zoomScale)

    // Step 4: Where is the *top-left* of the displayed image after pan/zoom?
    let displayedOrigin = CGPoint(
        x: displayCenter.x - displayedSize.width / 2,
        y: displayCenter.y - displayedSize.height / 2
    )

    // Step 5: What part of the image is actually visible in the viewport?
    // The viewport rect in the coordinate space of the displayed image
    let visibleRectInDisplayed = CGRect(
        x: max(0, -displayedOrigin.x),
        y: max(0, -displayedOrigin.y),
        width: min(viewportSize.width, displayedSize.width + min(0, displayedOrigin.x)),
        height: min(viewportSize.height, displayedSize.height + min(0, displayedOrigin.y))
    )

    // Step 6: Map visibleRectInDisplayed to original image coordinates
    let scaleX = image.size.width / displayedSize.width
    let scaleY = image.size.height / displayedSize.height
    let cropRect = CGRect(
        x: visibleRectInDisplayed.origin.x * scaleX,
        y: visibleRectInDisplayed.origin.y * scaleY,
        width: visibleRectInDisplayed.size.width * scaleX,
        height: visibleRectInDisplayed.size.height * scaleY
    ).integral.intersection(CGRect(origin: .zero, size: image.size))

    guard cropRect.width > 1, cropRect.height > 1,
          let cgImage = image.cgImage?.cropping(to: cropRect) else {
        return image
    }
    return UIImage(cgImage: cgImage)
}


struct CroppableImage: View {
    let image: UIImage
    let zoomScale: CGFloat
    let offset: CGSize

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(zoomScale)
            .offset(offset)
            .background(Color.black) // Match your app
    }
}

extension View {
    func snapshot(size: CGSize) -> UIImage {
        let controller = UIHostingController(rootView: self)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
