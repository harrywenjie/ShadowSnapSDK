//ARViewController.swift

import ARKit
import SceneKit
import UIKit
import Metal
import ZIPFoundation

/// Size of the generated face texture
private let TextureSize = 2048 //px

/// Should the face mesh be filled in? (i.e. fill in the eye and mouth holes with geometry)
private let fillMesh = true

public class ARViewController: UIViewController, ARSCNViewDelegate{
    
    private var headUvGenerator: HeadTextureGenerator!
    private var scnFaceGeometry: ARSCNFaceGeometry!
    private var scnHeadGeometry: SCNGeometry!
    private var blendTexture: BlendTexture!
    private var faceDistance: Float?
    private var ambientLight: CGFloat = 0.0
    private let lightThreshold: CGFloat = 550.0
    private let minDistance: Float = 34.0
    private let maxDistance: Float = 39.0
    
    /// Primary AR view
    private var sceneView: ARSCNView!
  
    //Model View
    private var capturedFaceView: SCNView!
  
    private var wireframe: Bool!
    
    private var UVchecker: Bool!
    
    //This is to calculate head scale
    private let indicesToCompare: [Int] = [20,39,57,130,131,167,208,211,212,213,295,330,352,376,392,425,462,467,489,579,580,616,659,660,661,730,765,783,807,822,853,888,904,905,906,907,908,909,910,911,912,913,914,915,916,917,918,919,920,921,966,1047,1213,1214,1215,1216]
    
    var meshData: MeshData!
    
    var customCameraControls: CustomCameraControls?
    
    //camera's transform
    var initialCameraTransform: SCNMatrix4?
    
    //closure property
    public var onFaceToCameraDistanceChanged: ((Float?) -> Void)?
    public var onStatusChanged: ((String) -> Void)?
    public var onLightChanged: ((CGFloat) -> Void)?
    
    //monitor user'head
    var timer: Timer?
    var countdown: Int?
    var initialYaw: Float?
    var initialRoll: Float?
    var rotationStep: Int = 0
    public var monitoring: Bool = false
    
    //sound
    var myPlayer: AVAudioPlayer?
    
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        print("viewDidLoad called")
        
        wireframe = false
        UVchecker = false
        
        sceneView = ARSCNView(frame: self.view.bounds, options: nil)
        sceneView.delegate = self
        sceneView.automaticallyUpdatesLighting = false
        sceneView.rendersCameraGrain = true
        //sceneView.scene.background.contents = UIColor.clear
        self.view.addSubview(sceneView)
        
        self.scnFaceGeometry = ARSCNFaceGeometry(device: self.sceneView.device!, fillMesh: fillMesh)
        self.scnHeadGeometry = createARHead()
        
        let bundle = Bundle.module
        let library: MTLLibrary
        do {
            library = try self.sceneView.device!.makeDefaultLibrary(bundle: bundle)
        } catch {
            fatalError("Failed to create Metal library: \(error)")
        }
        
        self.headUvGenerator = HeadTextureGenerator(
            device: self.sceneView.device!,
            library: library,
            viewportSize: self.view.bounds.size,
            head: self.meshData,
            textureSize: TextureSize)

        // Set up the BlendTexture
        self.blendTexture = BlendTexture(device: self.sceneView.device!)
        
        // Initialize the capturedFaceView
        capturedFaceView = SCNView(frame: self.view.bounds)
        capturedFaceView.isHidden = true
        capturedFaceView.backgroundColor = UIColor.clear
        self.view.addSubview(capturedFaceView)
    }

    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        resetTracking()
    }
    
    // MARK: AR
    
    
    private func resetTracking() {
        sceneView.session.run(ARFaceTrackingConfiguration(),
                              options: [.removeExistingAnchors,
                                        .resetTracking,
                                        .resetSceneReconstruction,
                                        .stopTrackedRaycasts])
    }

     
    public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let _ = anchor as? ARFaceAnchor else {
            return
        }
        sceneView.scene.rootNode.name = "Root"
        sceneView.pointOfView?.name = "Camera"
        node.name = "ARFaceAnchorNode"
        let headNode = SCNNode(geometry: scnHeadGeometry)
        headNode.name = "headNode"
        headNode.isHidden = true
        node.addChildNode(headNode)
        scnHeadGeometry.firstMaterial?.isDoubleSided = true
        print("======================")
        print("sceneView Section")
        printAllNodes(sceneView.scene.rootNode)
    }   

    public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else {
            return
        }

        // Get current ARFrame
        guard let frame = sceneView.session.currentFrame else {
            return
        }


        // Update faceDistance here
        faceDistance = distanceInCentimeters(from: faceAnchor, cameraTransform: frame.camera.transform)
        onFaceToCameraDistanceChanged?(faceDistance ?? 0.0)

        // Pass the camera transform to monitorHeadPosition function
        if monitoring {
            monitorHeadPosition(currentFaceAnchor: faceAnchor, cameraTransform: frame.camera.transform, faceDistance: faceDistance)
        }
        
        scnFaceGeometry.update(from: faceAnchor.geometry)
        let sourceVertices = scnFaceGeometry.sources(for: .vertex).first.map { extractVertices(from: $0) } ?? []
        scnHeadGeometry = applyDeformation(to: scnHeadGeometry, with: sourceVertices, meshData: &meshData)

        if let headNode = node.childNodes.first {
            headNode.geometry = scnHeadGeometry
            headUvGenerator.update(frame: frame, headNode: node, data: meshData, cameraNode: sceneView.pointOfView!)
            if !wireframe{
                if UVchecker {
                    scnHeadGeometry.firstMaterial?.diffuse.contents = UIImage(named: "UVChecker")
                    headNode.isHidden = false
                } else {
                    scnHeadGeometry.firstMaterial?.diffuse.contents = headUvGenerator.texture
                    headNode.isHidden = true
                }
            }else{
                scnHeadGeometry.firstMaterial?.diffuse.contents = UIColor.blue
                headNode.isHidden = false
            }

            scnHeadGeometry.firstMaterial?.fillMode = wireframe ? .lines : .fill
            
            //Only check light when we see a face
            if let lightEstimate = frame.lightEstimate {
                ambientLight = lightEstimate.ambientIntensity
                updateLight(ambientLight)
            }
        }
    }

    
    func updateStatus(_ status: String) {
        onStatusChanged?(status)
    }
    
    func updateLight(_ lumen: CGFloat){
        onLightChanged?(lumen)
    }
    
    public func toggleUVChecker(_ show: Bool){
        self.UVchecker = show
        if let capturedHeadNode = capturedFaceView.scene?.rootNode.childNode(withName: "headNode", recursively: true) {
            if UVchecker {
                capturedHeadNode.geometry?.firstMaterial?.diffuse.contents = UIImage(named: "UVChecker")
            } else {
                if let headTexture = headUvGenerator.texture {
                    capturedHeadNode.geometry?.firstMaterial?.diffuse.contents = getBlendedTexture(blendTexture: blendTexture, headTexture: headTexture)
                }
            }
        }
        
    }
    
    public func toggleWireframe(_ show: Bool) {
        self.wireframe = show
        // Update the rendering mode for the captured face view (capturedFaceView)
        if let capturedHeadNode = capturedFaceView.scene?.rootNode.childNode(withName: "headNode", recursively: true) {
            capturedHeadNode.geometry?.firstMaterial?.fillMode = wireframe ? .lines : .fill
            capturedHeadNode.geometry?.subdivisionLevel = wireframe ? 0 : 1
        }
    }

    public func pauseAndRemoveARView() {
        sceneView.session.pause()
        sceneView.removeFromSuperview()
    }
    
    deinit {
        sceneView.session.pause()
    }
    
    func monitorHeadPosition(currentFaceAnchor: ARFaceAnchor, cameraTransform: matrix_float4x4, faceDistance: Float?) {
        // Use faceDistance here for calculation
        guard let faceDistance = faceDistance else {
            return
        }

        // Check light condition first
        if ambientLight < lightThreshold {
            let msg = NSLocalizedString("MOVE_TO_BRIGHT_AREA", comment: "")
            updateStatus(msg)
            //print(msg)
            // Reset the countdown if it's running
            resetCountdown()
            return
        }

        // Check distance condition second
        if faceDistance < minDistance {
            let msg = NSLocalizedString("MOVE_YOUR_FACE_FURTHER", comment: "")
            updateStatus(msg)
            //print(msg)
            // Reset the countdown if it's running
            resetCountdown()
            return
        }
        else if faceDistance > maxDistance {
            let msg = NSLocalizedString("MOVE_YOUR_FACE_CLOSER", comment: "")
            updateStatus(msg)
            //print(msg)
            // Reset the countdown if it's running
            resetCountdown()
            return
        }

       
        //Check face position
        if !isFaceCentered(faceAnchor: currentFaceAnchor, cameraTransform: cameraTransform) {
            let msg = NSLocalizedString("PLACE_YOURSELF_CENTER", comment: "")
            updateStatus(msg)
            //print(msg)
            // Reset the countdown if it's running
            resetCountdown()
            return
        }
        
        // Check face direction condition last
        if !isFacingStraight(faceAnchor: currentFaceAnchor, cameraTransform: cameraTransform) {
            let msg = NSLocalizedString("FACE_DIRECTLY_INTO_CAMERA", comment: "")
            updateStatus(msg)
            //print(msg)
            // Reset the countdown if it's running
            resetCountdown()
            return
        }
        

        // If all conditions are met, start the countdown
        if countdown == nil {
            countdown = 3
            let msg = String(format: NSLocalizedString("PERFECT_STAY_STILL", comment: ""), countdown!)
            updateStatus(msg)
            //print(msg)
            printAndLog("About to start a timer to main thread")
            DispatchQueue.main.async {
                self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.updateCountdown), userInfo: nil, repeats: true)
            }
            printAndLog("Timer started")
        }
    }


    private func resetCountdown() {
        if let _ = countdown {
            printAndLog("resetCountdown called")
            printAndLog("About to reset countdown to nil")
            countdown = nil
            printAndLog("Countdown Set to nil")
            
            printAndLog("About to stop and invalidate timer")
            timer?.invalidate()  // Stop the timer
            printAndLog("About to set timer to nil")
            timer = nil
            printAndLog("Timer set to nil")
            
            printAndLog("About to play the fail sound")
            // Play the fail sound
            playSound(audioPlayer: &myPlayer, soundName: "camera_fail.mp3")
            printAndLog("fail sound played")
        }
    }
    
    public func cancelCapture(){
        monitoring = false
        resetCountdown()
        let msg = "Standby..."
        updateStatus(msg)        
    }
    
    @objc func updateCountdown() {
        printAndLog("updateCountdown called")
        if countdown! > 0 {
            countdown! -= 1
            let msg = String(format: NSLocalizedString("Countdown", comment: ""), "\(countdown!)")
            updateStatus(msg)
            printAndLog(msg)
            // Play the countdown sound
            playSound(audioPlayer: &myPlayer, soundName: "camera_beep.mp3")
        } else {
            printAndLog("About to set monitoring to nil")
            monitoring = false
            printAndLog("monitoring set to nil")
            
            printAndLog("About to invalidate timer")
            timer?.invalidate()  // Stop the timer
            printAndLog("Timer invalidated")
            
            printAndLog("About to set timer to nil")
            timer = nil
            printAndLog("Timer set to nil")
            
            printAndLog("About to set Countdown to nil")
            countdown = nil
            printAndLog("Countdown Set to nil")
            
            printAndLog("About to update msg to UI")
            let msg = "Standby..."
            updateStatus(msg)
            printAndLog("msg updated")
            
            printAndLog("About to play shutter sound")
            playSound(audioPlayer: &myPlayer, soundName: "camera_shutter.mp3")
            printAndLog("Shutter sound played")
            
            printAndLog("About to call showCapturedFace")
            showCapturedFace()
            printAndLog("showCapturedFace called")
        }
    }
 
    private func createARHead() -> SCNGeometry? {
        let bundle = Bundle.module
        guard let objURL = bundle.url(forResource: "ARHead", withExtension: "obj") else {
            printAndLog("Error: Could not find OBJ file in the package bundle")
            return nil
        }
        
        guard let meshData = parseOBJFile(url: objURL) else {
            printAndLog("Error: Could not parse OBJ file")
            return nil
        }
        self.meshData = meshData
        
        printAndLog("======================")
        printAndLog("createARHeadNode section")
        printAndLog("Mesh Data: vertices count: \(meshData.vertices.count), texCoords count: \(meshData.finalTexCoords.count), indices count: \(meshData.indices.count), normals count: \(meshData.normals.count)")
        
        let geometry = createGeometry(meshData: meshData)

        printAndLog("ARHead created successfully")
        return geometry
    }
 
    
    func applyDeformation(to targetGeometry: SCNGeometry, with sourceVertices: [simd_float3], meshData: inout MeshData) -> SCNGeometry? {
        guard let vertexSource = targetGeometry.sources(for: .vertex).first else {
            printAndLog("Error: Could not access targetGeometry or vertex source.")
            return targetGeometry
        }

        // Extract target vertices and make them mutable
        var targetVertices = extractVertices(from: vertexSource)

        // Update the positions of the first 1220 vertices in the target vertices with the source vertices
        for i in 0..<1220 {
            let updatedVertex = SCNVector3(sourceVertices[i].x, sourceVertices[i].y, sourceVertices[i].z)
            if let newIndices = meshData.vertexMap[i] {
                for newIndex in newIndices {
                    meshData.vertices[newIndex] = updatedVertex
                    targetVertices[newIndex] = sourceVertices[i]
                }
            } else {
                printAndLog("Warning: No mapping found for original index \(i)")
            }
        }

        var scalingPercentages: [Float] = []
        for index in indicesToCompare {
            let originalVertex = meshData.originalVertices[index]
            let sourceVertex = sourceVertices[index]
            let originalDistance = distanceBetweenPoints(SIMD3<Float>(originalVertex), SIMD3<Float>(0, 0, 0))
            let sourceDistance = distanceBetweenPoints(sourceVertex, SIMD3<Float>(0, 0, 0))
            let scalingPercentage = sourceDistance / originalDistance
            scalingPercentages.append(scalingPercentage)
        }

        let averageScalingPercentage = scalingPercentages.reduce(0, +) / Float(scalingPercentages.count)
        //print("Average scaling percentage: \(averageScalingPercentage)")

        // Scale the rest of the targetVertices using the vertexMap and averageScalingPercentage
        for originalIndex in 1220..<meshData.originalVertices.count {
            if let newIndices = meshData.vertexMap[originalIndex] {
                let originalVertex = meshData.originalVertices[originalIndex]
                let originalDistance = distanceBetweenPoints(SIMD3<Float>(originalVertex), SIMD3<Float>(0, 0, 0))
                let newDistance = originalDistance * averageScalingPercentage

                let normalizedVertex = simd_normalize(SIMD3<Float>(originalVertex))
                let newVertex = SIMD3<Float>(
                    normalizedVertex.x * newDistance, // Apply scaling to the x-axis
                    normalizedVertex.y * newDistance * 0.97, // Apply scaling to the Y-axis
                    normalizedVertex.z * originalDistance // Keep the original z-axis value
                )
                
                for newIndex in newIndices {
                    targetVertices[newIndex] = newVertex
                    meshData.vertices[newIndex] = SCNVector3(newVertex)
                }
            }
        }

        // Reconstruct the geometry with the updated target vertices
        let updatedGeometry = createUpdatedGeometry(from: targetGeometry, with: targetVertices)

        return updatedGeometry
    }
   
   
    public func showCapturedFace() {
        // Pause the AR session and hide the main AR view
        sceneView.session.pause()
        sceneView.isHidden = true

        // Create a new scene for the capturedFaceView
        let scene = SCNScene()
        capturedFaceView.scene = scene
        
        //Flip the view because using front camera
        capturedFaceView.transform = CGAffineTransform(scaleX: -1, y: 1)

        // Position the camera
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        //camera.wantsHDR = true
        camera.fieldOfView = 60 // adjust the FOV here
        camera.zNear = 0.01 // set the near clipping distance
        camera.zFar = 100 // set the far clipping distance
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 0.5)
        scene.rootNode.addChildNode(cameraNode)

        // Create a node with the current face geometry and texture
        let headNode = SCNNode(geometry: scnHeadGeometry)
        headNode.geometry?.subdivisionLevel = 1

        if let headTexture = headUvGenerator.texture{
            scnHeadGeometry.firstMaterial?.diffuse.contents = getBlendedTexture(blendTexture: blendTexture, headTexture:headTexture)
            printAndLog("Secondary scene setup successfully, blendtexture applied")
        }
        
        
        print("======================")
        print("capturedFaceView Section")
        
        scene.rootNode.addChildNode(headNode)

        // Set the camera to look at the headNode
        let constraint = SCNLookAtConstraint(target: headNode)
        constraint.isGimbalLockEnabled = true
        cameraNode.constraints = [constraint]

        // Store the initial camera's transform
        initialCameraTransform = cameraNode.transform

        customCameraControls = CustomCameraControls(sceneView: capturedFaceView, headNode: headNode)
        customCameraControls?.enable()

        // Show the capturedFaceView
        capturedFaceView.isHidden = false

        scene.rootNode.name = "Root"
        headNode.name = "headNode"
        cameraNode.name = "Camera"

        printAllNodes(scene.rootNode)
    }

   
    public func resetCapturedFace() {
        // Hide the capturedFaceView and remove its content
        capturedFaceView.isHidden = true
        capturedFaceView.scene = nil

        // Show the main AR view and reset tracking
        sceneView.isHidden = false
        resetTracking()
    }
    
    @objc public func generateFaceImages(folderName: String) {
        customCameraControls?.disable()

        // Reset the camera's transform
        if let initialCameraTransform = initialCameraTransform {
            capturedFaceView.pointOfView?.transform = initialCameraTransform
        }

        // Get the head node
        guard let headNode = capturedFaceView.scene?.rootNode.childNode(withName: "headNode", recursively: true) else { return }

        // Reset the head geometry's rotation
        headNode.eulerAngles = SCNVector3Zero

        // Angles to generate images
        let xAngles: [Float] = [30, 0, -30].map { toRadians($0) }
        let yAngles: [Float] = [80, 60, 40, 20, 0, -20, -40, -60, -80].map { toRadians($0) }
        let angles: [SCNVector3] = xAngles.flatMap { x in
            yAngles.map { y in
                SCNVector3(x, y, 0)
            }
        }

        // Create a folder
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        let dateString = dateFormatter.string(from: Date())
        let folderPath = createFolder(named: "\(folderName)_\(dateString)")

        // Generate and save images
        var successCount = 0
        for (index, angle) in angles.enumerated() {
            autoreleasepool {
                headNode.eulerAngles = angle
                let image = takeSceneImage()
                let croppedImage = cropToSquare(image: image)
                let targetSize = CGSize(width: 512, height: 512)
                let resizedImage = resizeImage(croppedImage, to: targetSize)
                guard let unwrappedFolderPath = folderPath else {
                    print("Folder path is nil")
                    return
                }
                let flippedImage = flipImageHorizontally(resizedImage)
                if saveImage(flippedImage, named: "\(index + 1).jpg", inFolder: unwrappedFolderPath) {
                    successCount += 1
                } else {
                    print("Failed to save image at angle \(index + 1)")
                }
            }
        }

        
        // Compress images into a single ZIP file
        if let folderPath = folderPath {
            let zipFilePath = folderPath.deletingLastPathComponent().appendingPathComponent("\(folderName)_\(dateString).zip")
            if let zipURL = compressImagesToZip(folderPath: folderPath, zipFilePath: zipFilePath) {
                print("ZIP archive created at: \(zipURL)")
            } else {
                print("Failed to create ZIP archive")
            }
        }

        // Reset the face geometry's rotation again
        headNode.eulerAngles = SCNVector3Zero
        
        //Enable Camera Control
        customCameraControls?.enable()
        
        // Show success or failure message
        if successCount == angles.count {
            showAlert(title: "Export Successful", message: "Saved \(successCount) images to Files app in the ShadowSnap folder under the name: \(folderName)_\(dateString)", viewController : self)
        } else {
            let failedCount = angles.count - successCount
            showAlert(title: "Partial Export", message: "\(successCount) of \(angles.count) images exported successfully to Files app in the ShadowSnap folder under the name: \(folderName)_\(dateString). \(failedCount) failed.", viewController : self)
        }
    }
    
    func takeSceneImage() -> UIImage {
        return capturedFaceView.snapshot()
    }
    
    public func exportObj(){
        if let headTexture = headUvGenerator.texture{
            exportObjfile(meshData: meshData, blendTexture: blendTexture, viewController: self, headTexture: headTexture)
        }
    }
}
