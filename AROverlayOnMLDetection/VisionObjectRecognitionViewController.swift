/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Contains the object recognition view controller for the Breakfast Finder.
*/

import UIKit
import AVFoundation
import Vision
import ARKit
import SceneKit.ModelIO

let showLayers = true

class VisionObjectRecognitionViewController: ViewController {
    
    @IBOutlet private var sceneView: ARSCNView!
    
    private var detectionOverlay: CALayer! = nil
    
    // Vision parts
    private var requests = [VNRequest]()
    
    var trackingRequest: VNTrackObjectRequest?
    var initialBoundingBox: CGRect?
        
    // Initialize the last observation to nil
    var lastObservation: VNDetectedObjectObservation?
    var node: SCNNode?
    
    var layerScale: CGFloat = 1.0
    
    @discardableResult
    func setupVision() -> NSError? {
        print("setupVision")
        // Setup Vision parts
        let error: NSError! = nil
        
        guard let modelURL = Bundle.main.url(forResource: "ObjectDetector", withExtension: "mlmodelc") else {
            return NSError(domain: "VisionObjectRecognitionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        self.drawVisionRequestResults(results)
                    }
                })
            })
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        return error
    }
    
    func addTopLayer() {
        let totalBox = CGRect(origin: .zero, size: CGSize(width: 1.0, height: 1.0))
        let totalBounds = VNImageRectForNormalizedRect(totalBox, Int(bufferSize.width), Int(bufferSize.height))
        let boxLayer = self.createRoundedRectLayerWithBounds(totalBounds)
        let textLayer = self.createTextSubLayerInBounds(totalBounds,
                                                        identifier: "top",
                                                        confidence: 1.0)
        
        boxLayer.addSublayer(textLayer)
        detectionOverlay.addSublayer(boxLayer)
    }
    
    
    func handleObservation(boundingBox: CGRect,confidence: VNConfidence, identifier: String) {
        var layerBounds = VNImageRectForNormalizedRect(boundingBox, Int(bufferSize.width), Int(bufferSize.height))
        
        var raycastBounds = VNImageRectForNormalizedRect(boundingBox, Int(sceneView.bounds.width), Int(sceneView.bounds.height))
        
        show3DModel(at: CGPoint(x: raycastBounds.midX, y: raycastBounds.midY))
        
        if showLayers {
            let shapeLayer = self.createRoundedRectLayerWithBounds(layerBounds)
            
            let textLayer = self.createTextSubLayerInBounds(layerBounds,
                                                            identifier: identifier,
                                                            confidence: confidence)
            
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
        }
    }
    
    func drawVisionRequestResults(_ results: [Any]) {
//        print ("drawVisionRequestResults")
        if showLayers {
            CATransaction.begin()
            CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
            detectionOverlay.sublayers = nil // remove all the old recognized objects
        }
        
        addTopLayer()
        show3DModel(at: CGPoint(x: 0.5, y: 0.5))
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            if topLabelObservation.confidence < 0.95 {
                continue
            }
            assert(bufferSize.width > 0)
            assert(bufferSize.height > 0)
            
            initialBoundingBox = objectObservation.boundingBox
            
            handleObservation(boundingBox: objectObservation.boundingBox, confidence: objectObservation.confidence, identifier: topLabelObservation.identifier)
            
//            print ("\(topLabelObservation.identifier) \(topLabelObservation.confidence) bounds: \(objectBounds)")
        }
        if showLayers {
            self.updateLayerGeometry()
            CATransaction.commit()
        }
        
        detectionOverlay.setNeedsDisplay()
        rootLayer.setNeedsDisplay()
        previewView.setNeedsDisplay()
    }
    
    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        fatalError("Should not be called")
//        detectImage(in: pixelBuffer)
        
    }
    
    private func detectImage(in ciImage: CIImage) {
        let exifOrientation = exifOrientationFromDeviceOrientation()
        
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, orientation: exifOrientation, options: [:])
//        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    func performObjectTracking(in ciImage: CIImage) {
           // Create a new Vision request handler
//           let requestHandler = VNImageRequestHandler(ciImage: CIImage(cvPixelBuffer: frame), options: [:])
        
        let exifOrientation = exifOrientationFromDeviceOrientation()
        
        let requestHandler = VNImageRequestHandler(ciImage: ciImage, orientation: exifOrientation, options: [:])
           
           // Initialize the tracking request if it doesn't exist
        if trackingRequest == nil, let initialBoundingBox {
               // Assuming you have an initial bounding box for the object
//               let initialBoundingBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
               
               // Create the initial observation
               let initialObservation = VNDetectedObjectObservation(boundingBox: initialBoundingBox)
               
               // Create the tracking request
               trackingRequest = VNTrackObjectRequest(detectedObjectObservation: initialObservation)
           }
           
           // Perform the tracking request
           do {
               try requestHandler.perform([trackingRequest!])
               
               // Get the tracking results
               guard let results = trackingRequest?.results as? [VNDetectedObjectObservation] else {
                   return
               }
               
               // Update the last observation
               lastObservation = results.first
               
               // Process the tracking results
               if let observation = lastObservation {
                   // Get the normalized bounding box
                   let normalizedBoundingBox = observation.boundingBox
                   
                   // Convert the normalized bounding box to view coordinates if needed
                   handleObservation(boundingBox: observation.boundingBox,confidence: 1.0, identifier: "")
//                   let viewBoundingBox = convertNormalizedBoundingBoxToViewCoordinates(normalizedBoundingBox)
                   
                   // Update the UI or perform any other actions based on the tracking results
                   // ...
               }
           } catch {
               print("Error performing tracking: \(error.localizedDescription)")
           }
       }
    
    
    override func setupAVCapture() {
//        super.setupAVCapture()
        
        // setup Vision parts
        setupLayers()
        updateLayerGeometry()
        setupVision()
        
        // start the capture
//        startCaptureSession()
        
        setupSceneView()
    }
    
    func setupSceneView() {
        
        print(ARWorldTrackingConfiguration.supportedVideoFormats)
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.videoFormat = ARWorldTrackingConfiguration.supportedVideoFormats.first{ $0.imageResolution.width == 1280 && $0.framesPerSecond == 30 }!
        sceneView.session.delegate = self
        sceneView.delegate = self
        sceneView.session.run(configuration)
    }
    
    func setupLayers() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        
//        assert(bufferSize.width > 0)
//        assert(bufferSize.height > 0)
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        print ("detectionOverlay pos: \(detectionOverlay.position), bounds: \(detectionOverlay.bounds)")
        detectionOverlay.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 0.2, 1.0, 0.4])
        let textLayer = self.createTextSubLayerInBounds(detectionOverlay.bounds,
                                                        identifier: "top",
                                                        confidence: 1.0)
        detectionOverlay.addSublayer(textLayer)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = rootLayer.bounds
//        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
//        scale = fmax(xScale, yScale)
//        if scale.isInfinite {
//            scale = 1.0
//        }
        
//        scale = 1.0
//        layerScale = 0.5
        layerScale = 1.0
//        print("layerScale: \(layerScale)")
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
//        detectionOverlay.bounds = rootLayer.bounds
//        detectionOverlay.position = CGPoint(x: 0, y: 0)
        detectionOverlay.zPosition = 100
        
        // rotate the layer into screen orientation and scale and mirror
        let angle = CGFloat(.pi / 2.0)
//        let angle = 0
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: layerScale, y: -layerScale))
//        detectionOverlay.contentsScale = 2.0
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 4.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        let angle = CGFloat(.pi / 2.0)
//        let angle: CGFloat = 0
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
//        print("show rect with bounds: \(bounds), bufferSize: \(bufferSize)")
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }
}

extension VisionObjectRecognitionViewController {
 
    private func show3DModel(at coordinate: CGPoint) {
//        let scale = 2.0
        let scale = 1.0
//        var coordinate = coordinate
//        coordinate.x *= scale
//        coordinate.y *= scale
        
//        let angle = CGFloat(.pi / 2.0)
//        let angle: CGFloat = 0
//        coordinate.setAffineTransform()
        
//        coordinate = coordinate.applying(
//            CGAffineTransform(rotationAngle: angle)
//                .scaledBy(x: 1.0, y: -1.0)
//        )
        
//        print("raycast query at: \(coordinate)")
        
//        let middleCoord = CGPointMake(sceneView.bounds.midX, sceneView.bounds.midY)
        
        /// Create a raycast query using the current frame
        if let raycastQuery: ARRaycastQuery = sceneView.raycastQuery(
//            from: coordinate,
            from: coordinate,
            allowing: .estimatedPlane,
            alignment: .any
        ) {
            // Performing raycast from the clicked location
            let raycastResults: [ARRaycastResult] = sceneView.session.raycast(raycastQuery)
            
//            if !raycastResults.isEmpty {
                print("raycast results: \(raycastResults.debugDescription)")
//            }
            
            // Based on the raycast result, get the closest intersecting point on the plane
            if let closestResult = raycastResults.first {
                /// Get the coordinate of the clicked location
                let transform : matrix_float4x4 = closestResult.worldTransform
                let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                
                /// Load 3D Model into the scene as SCNNode and adding into the scene
                show3DModel(at: worldCoord)
            }
        }
    }
    
    func show3DModel(at worldCoord: SCNVector3 ) {
        print("show 3d model at \(worldCoord)")
//        guard let node : SCNNode = loadNode() else {return}
        if node == nil {
            node = createARNodeWith(image: UIImage(named: "eye")!, size: CGSizeMake(0.1, 0.1))
            sceneView.scene.rootNode.addChildNode(node!)
        }
        
        node!.position = worldCoord
        
//        if sceneView.scene.rootNode.childNodes.count > 1 {
//            sceneView.scene.rootNode.childNodes.first?.removeFromParentNode()
//        }
    }

    func loadNode() -> SCNNode? {
        guard let urlPath = Bundle.main.url(forResource: "traffic_light", withExtension: "usdz") else {
            return nil
        }
        let mdlAsset = MDLAsset(url: urlPath)
        mdlAsset.loadTextures()
        
        let asset = mdlAsset.object(at: 0) // extract first object
        let assetNode = SCNNode(mdlObject: asset)
        assetNode.scale = SCNVector3(0.001, 0.001, 0.001)
        
        return assetNode
    }
    
    func createARNodeWith(image: UIImage, size: CGSize) -> SCNNode? {
        
        // Create a SceneKit plane geometry matching the size of the detected image
//        let planeGeometry = SCNPlane(width: imageAnchor.referenceImage.physicalSize.width,
//                                     height: imageAnchor.referenceImage.physicalSize.height)
        
        let planeGeometry = SCNPlane(width: size.width,
                                     height: size.height)
        
        // Create a SceneKit material with the desired image
        let material = SCNMaterial()
        material.diffuse.contents = image
        
        // Assign the material to the plane geometry
        planeGeometry.materials = [material]
        
        // Create a SceneKit node with the plane geometry
        let planeNode = SCNNode(geometry: planeGeometry)
        
        // Rotate the plane to be parallel to the detected image
        planeNode.eulerAngles.x = -.pi / 2
        
        return planeNode
        // Add the plane node as a child of the anchor node
//        node.addChildNode(planeNode)
    }
}



extension VisionObjectRecognitionViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {

//        print("arFrame: \(frame.camera.imageResolution)")
        
//        bufferSize.width = rootLayer.frame.width //frame.camera.imageResolution.width
//        bufferSize.height = rootLayer.frame.height //frame.camera.imageResolution.height
        
//        bufferSize.width = frame.camera.imageResolution.width
//        bufferSize.height = frame.camera.imageResolution.height
        
        
        
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let scale = UIScreen.main.scale
//        print( "scale: \(scale)")
        let uiImage = UIImage(ciImage: image, scale: scale, orientation: .right)
        bufferSize.width = image.extent.width / 2
        bufferSize.height = image.extent.height / 2
//        print("bufferSize: \(bufferSize)")
        
        detectionOverlay.bounds = CGRectMake(0, 0, bufferSize.width, bufferSize.height)
        previewView.image = uiImage
        detectImage(in: image)
//        detectImage(in: frame.capturedImage)
//        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        
//        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil)
//        let features = detector!.features(in: image)
//
//        for feature in features as! [CIQRCodeFeature] {
//            if !discoveredQRCodes.contains(feature.messageString!) {
//                discoveredQRCodes.append(feature.messageString!)
//                let url = URL(string: feature.messageString!)
//                let position = SCNVector3(frame.camera.transform.columns.3.x,
//                                          frame.camera.transform.columns.3.y,
//                                          frame.camera.transform.columns.3.z)
//            }
//         }
    }
}

extension VisionObjectRecognitionViewController: ARSCNViewDelegate {
    
    /// - Tag: ImageWasRecognized
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
//        alteredImage?.add(anchor, node: node)
//        setMessageHidden(true)
    }

    /// - Tag: DidUpdateAnchor
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
//        alteredImage?.update(anchor)
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard let arError = error as? ARError else { return }
        
        if arError.code == .invalidReferenceImage {
            // Restart the experience, as otherwise the AR session remains stopped.
            // There's no benefit in surfacing this error to the user.
            print("Error: The detected rectangle cannot be tracked.")
//            searchForNewImageToTrack()
            return
        }
        
        let errorWithInfo = arError as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Use `compactMap(_:)` to remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            
            // Present an alert informing about the error that just occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
//                self.searchForNewImageToTrack()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
}
