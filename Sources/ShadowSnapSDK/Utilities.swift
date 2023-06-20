//
//  Utilities.swift
//  ShadowSnap
//
//  Created by Harry He on 28/04/23.
//

import ARKit
import SceneKit
import simd


func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1  // ensure 1x scale factor
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let resizedImage = renderer.image { (context) in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
    return resizedImage
}

func saveImage(_ image: UIImage, named imageName: String, inFolder folderURL: URL) -> Bool {
    let imageURL = folderURL.appendingPathComponent(imageName)

    guard let imageData = image.jpegData(compressionQuality: 0.7) else {
        printAndLog("Error converting UIImage to JPEG data")
        return false
    }
    
    do {
        try imageData.write(to: imageURL)
        print("Image saved at: \(imageURL)")
        return true
    } catch {
        print("Error saving image: \(error)")
        return false
    }
}


func compressImagesToZip(folderPath: URL, zipFilePath: URL) -> URL? {
    let fileManager = FileManager.default

    do {
        try fileManager.zipItem(at: folderPath, to: zipFilePath, shouldKeepParent: false, compressionMethod: .deflate)
    } catch {
        print("Error creating ZIP archive: \(error)")
        return nil
    }

    return zipFilePath
}

func cropToSquare(image: UIImage) -> UIImage {
    let originalWidth  = image.size.width
    let originalHeight = image.size.height

    let cropWidth = min(originalWidth, originalHeight)
    let cropHeight = cropWidth

    let x = (originalWidth - cropWidth) / 2.0
    let y = (originalHeight - cropHeight) / 2.0

    let cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
    let imageRef = image.cgImage!.cropping(to: cropRect)

    return UIImage(cgImage: imageRef!, scale: image.scale, orientation: image.imageOrientation)
}


func toRadians(_ degrees: Float) -> Float {
    return degrees * .pi / 180
}

func toDegrees(_ radians: Float) -> Float {
    return radians * 180.0 / .pi
}

func createFolder(named folderName: String) -> URL? {
    let fileManager = FileManager.default
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let folderURL = documentsURL.appendingPathComponent(folderName)

    do {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        print("Folder created at: \(folderURL)")
        return folderURL
    } catch {
        print("Error creating folder: \(error)")
        return nil
    }
}


func createUpdatedGeometry(from originalGeometry: SCNGeometry, with updatedVertices: [simd_float3]) -> SCNGeometry {
    let vertexData = Data(bytes: updatedVertices, count: updatedVertices.count * MemoryLayout<simd_float3>.size)
    let vertexSource = SCNGeometrySource(data: vertexData,
                                         semantic: .vertex,
                                         vectorCount: updatedVertices.count,
                                         usesFloatComponents: true,
                                         componentsPerVector: 3,
                                         bytesPerComponent: MemoryLayout<Float>.size,
                                         dataOffset: 0,
                                         dataStride: MemoryLayout<simd_float3>.size)

    let otherSources = originalGeometry.sources.filter { $0.semantic != .vertex }
    let updatedSources = [vertexSource] + otherSources
    let updatedGeometry = SCNGeometry(sources: updatedSources, elements: originalGeometry.elements)

    return updatedGeometry
}


func distanceBetweenPoints(_ pointA: SIMD3<Float>, _ pointB: SIMD3<Float>) -> Float {
    let diff = pointA - pointB
    return sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)
}

func printAllNodes(_ node: SCNNode, level: Int = 0) {
    print(String(repeating: "  ", count: level) + "\(node.name ?? "unnamed")")
    for child in node.childNodes {
        printAllNodes(child, level: level + 1)
    }
}

func extractVertices(from source: SCNGeometrySource) -> [SIMD3<Float>] {
    let vertexCount = source.vectorCount
    let stride = source.dataStride
    let offset = source.dataOffset
    let buffer = source.data
    
    var vertices = [SIMD3<Float>](repeating: SIMD3<Float>(), count: vertexCount)
    
    for i in 0..<vertexCount {
        let vertexPointer = buffer.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) -> UnsafePointer<Float32> in
            let pointer = bufferPointer.baseAddress! + offset + i * stride
            return pointer.assumingMemoryBound(to: Float32.self)
        }
        vertices[i] = SIMD3<Float>(x: vertexPointer.pointee, y: vertexPointer.advanced(by: 1).pointee, z: vertexPointer.advanced(by: 2).pointee)
    }
    
    return vertices
}


func matrix_float3x3(_ matrix4x4: float4x4) -> float3x3 {
    let matrix = float3x3([
        SIMD3<Float>(matrix4x4.columns.0.x, matrix4x4.columns.0.y, matrix4x4.columns.0.z),
        SIMD3<Float>(matrix4x4.columns.1.x, matrix4x4.columns.1.y, matrix4x4.columns.1.z),
        SIMD3<Float>(matrix4x4.columns.2.x, matrix4x4.columns.2.y, matrix4x4.columns.2.z)
    ])
    return matrix
}

func meshDataToObjString(meshData: MeshData) -> String {
    var objString = ""

    // Write vertices (v)
    for vertex in meshData.vertices {
        objString += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
    }

    // Write texture coordinates (vt)
    for texCoord in meshData.finalTexCoords {
        objString += "vt \(texCoord.x) \(texCoord.y)\n"
    }

    // Write normals (vn)
    for normal in meshData.normals {
        objString += "vn \(normal.x) \(normal.y) \(normal.z)\n"
    }

    // Write faces (f)
    let faceCount = meshData.indices.count / 3
    for i in 0..<faceCount {
        let faceIndex = i * 3
        let vi1 = meshData.indices[faceIndex] + 1
        let vi2 = meshData.indices[faceIndex + 1] + 1
        let vi3 = meshData.indices[faceIndex + 2] + 1
        objString += "f \(vi1)/\(vi1)/\(vi1) \(vi2)/\(vi2)/\(vi2) \(vi3)/\(vi3)/\(vi3)\n"
    }

    return objString
}

func distanceInCentimeters(from faceAnchor: ARFaceAnchor, cameraTransform: matrix_float4x4) -> Float {
    // Compute the relative transform from the camera to the face
    let faceTransform = faceAnchor.transform
    let relativeTransform = simd_mul(cameraTransform.inverse, faceTransform)
    
    // Extract the Z component of the relative transform's translation
    let distanceMeters = -relativeTransform.columns.3.z
    
    // Convert the distance to centimeters and return it
    return distanceMeters * 100.0
}


func isFacingStraight(faceAnchor: ARFaceAnchor, cameraTransform: matrix_float4x4, toleranceDegrees: Float = 5.0) -> Bool {
    // Compute the relative transform from the camera to the face
    let faceTransform = faceAnchor.transform
    let relativeTransform = simd_mul(cameraTransform.inverse, faceTransform)

    // Convert 4x4 transform to quaternion
    let relativeQuaternion = simd_quatf(relativeTransform)

    // Convert quaternion to Euler angles
    let relativeEulerAngles = toEulerAngles(quat: relativeQuaternion)

    // Convert Euler angles from radians to degrees
    let yawDegrees = toDegrees(relativeEulerAngles.yaw)
    let rollDegrees = toDegrees(relativeEulerAngles.roll) - 90.0 // Offset for the roll
    let pitchDegrees = toDegrees(relativeEulerAngles.pitch)

    //print("Relative Yaw: \(yawDegrees), Roll: \(rollDegrees), Pitch: \(pitchDegrees)")

    // Convert tolerance to radians
    let tolerance = toleranceDegrees

    // Check if the face's orientation is within the defined tolerance of straight ahead
    return abs(yawDegrees) < tolerance && abs(rollDegrees) < tolerance && abs(pitchDegrees) < tolerance
}


func isFaceCentered(faceAnchor: ARFaceAnchor, cameraTransform: matrix_float4x4, xTolerance: Float = 0.02, yTolerance: Float = 0.05, yOffset: Float = 0.04) -> Bool {
    let relativeTransform = matrix_multiply(cameraTransform.inverse, faceAnchor.transform)
    
    let faceX = relativeTransform.columns.3.y
    let faceY = relativeTransform.columns.3.x - yOffset

    //print("Relative Face Position: \(faceX), \(faceY)")

    // Check if the face's X and Y positions are within the defined tolerance of the center (0)
    return abs(faceX) < xTolerance && abs(faceY) < yTolerance
}

func toEulerAngles(quat: simd_quatf) -> (pitch: Float, yaw: Float, roll: Float) {
    let ysqr = quat.vector.y * quat.vector.y

    // pitch (x-axis rotation)
    let t0 = +2.0 * (quat.real * quat.vector.x + quat.vector.y * quat.vector.z)
    let t1 = +1.0 - 2.0 * (quat.vector.x * quat.vector.x + ysqr)
    let pitch = atan2(t0, t1)

    // yaw (y-axis rotation)
    let t2 = +2.0 * (quat.real * quat.vector.y - quat.vector.z * quat.vector.x)
    let t3 = min(max(t2, -1.0), 1.0) // clamp t2 to the range [-1, 1]
    let yaw = asin(t3)

    // roll (z-axis rotation)
    let t4 = +2.0 * (quat.real * quat.vector.z + quat.vector.x * quat.vector.y)
    let t5 = +1.0 - 2.0 * (ysqr + quat.vector.z * quat.vector.z)
    let roll = atan2(t4, t5)

    return (pitch, yaw, roll)
}

func playSound(audioPlayer: inout AVAudioPlayer?, soundName: String) {
    let bundle = Bundle.module
    if let url = bundle.url(forResource: soundName, withExtension: nil) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Couldn't load file")
        }
    }
}

func showAlert(title: String, message: String, viewController: UIViewController) {
    DispatchQueue.main.async {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))

        if let presentedAlert = viewController.presentedViewController as? UIAlertController {
            presentedAlert.dismiss(animated: true) {
                viewController.present(alert, animated: true)
            }
        } else {
            viewController.present(alert, animated: true)
        }
    }
}

func getBlendedTexture(blendTexture: BlendTexture, headTexture:MTLTexture) -> MTLTexture? {
    print("getBlendedTexture called")
    return blendTexture.blend(headTexture: headTexture)
}

func writeToLog(_ message: String) {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let logURL = paths[0].appendingPathComponent("app_log.txt")

    do {
        let fileHandle: FileHandle
        if FileManager.default.fileExists(atPath: logURL.path) {
            fileHandle = try FileHandle(forWritingTo: logURL)
        } else {
            FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: nil)
            fileHandle = try FileHandle(forWritingTo: logURL)
        }

        fileHandle.seekToEndOfFile()
        fileHandle.write("\(Date()): \(message)\n".data(using: .utf8)!)
        fileHandle.closeFile()
    } catch {
        print("Error writing to log: \(error)")
    }
}

func printAndLog(_ message: String) {
    print(message)
    //writeToLog(message)
}

func exportObjfile(meshData: MeshData, blendTexture: BlendTexture, viewController: UIViewController, headTexture: MTLTexture) {
    // Generate a timestamped folder name
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
    let dateString = dateFormatter.string(from: Date())
    let folderName = "Model_\(dateString)"

    // Create a folder with the timestamped name
    guard let folderURL = createFolder(named: folderName) else {
        print("Error creating folder")
        return
    }

    // Update the file names
    let objFileName = "Model.obj"
    let textureFileName = "Model.png"

    // Create the full file URLs
    let objFileURL = folderURL.appendingPathComponent(objFileName)
    let textureFileURL = folderURL.appendingPathComponent(textureFileName)

    var objExportSuccess = false
    var textureExportSuccess = false

    // Write MeshData to the OBJ file
    do {
        let objString = meshDataToObjString(meshData: meshData)
        try objString.write(to: objFileURL, atomically: true, encoding: .utf8)
        print("OBJ file successfully exported to: \(objFileURL.path)")
        objExportSuccess = true
    } catch {
        print("Error exporting OBJ file: \(error.localizedDescription)")
    }

    // Save the texture as a PNG file
    if let blendedTexture = getBlendedTexture(blendTexture:blendTexture, headTexture:headTexture), let uiImage = textureToImage(blendedTexture){
        if let imageData = uiImage.pngData() {
            do {
                try imageData.write(to: textureFileURL)
                print("Texture file successfully exported to: \(textureFileURL.path)")
                textureExportSuccess = true
            } catch {
                print("Error exporting texture file: \(error.localizedDescription)")
            }
        }
    }

    // Show a single alert for both the OBJ and texture exports
    if objExportSuccess && textureExportSuccess {
        showAlert(title: "Success", message: "OBJ and texture files saved successfully in folder \(folderName).", viewController : viewController)
    } else {
        var errorMessage = "Failed to save the following files:\n"
        if !objExportSuccess {
            errorMessage += "- OBJ file\n"
        }
        if !textureExportSuccess {
            errorMessage += "- Texture file"
        }
        showAlert(title: "Error", message: errorMessage, viewController : viewController)
    }
}

func flipImageHorizontally(_ originalImage: UIImage) -> UIImage {
    UIGraphicsBeginImageContext(originalImage.size)
    let context = UIGraphicsGetCurrentContext()!

    // Flip context
    context.translateBy(x: originalImage.size.width / 2, y: originalImage.size.height / 2)
    context.scaleBy(x: -1.0, y: 1.0)
    context.translateBy(x: -originalImage.size.width / 2, y: -originalImage.size.height / 2)

    // Draw original image in the context
    originalImage.draw(at: .zero)

    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return newImage ?? originalImage
}

extension float3x3 {
    func eulerAngles() -> (pitch: Float, yaw: Float, roll: Float) {
        let sy = sqrt(self[0][0] * self[0][0] + self[1][0] * self[1][0])
        let singular = sy < 1e-6
        var x, y, z: Float

        if !singular {
            x = atan2(self[2][1], self[2][2])
            y = atan2(-self[2][0], sy)
            z = atan2(self[1][0], self[0][0])
        } else {
            x = atan2(-self[1][2], self[1][1])
            y = atan2(-self[2][0], sy)
            z = 0
        }

        return (pitch: x, yaw: y, roll: z)
    }
}

extension SCNMatrix4 {
    /**
     Create a 4x4 matrix from CGAffineTransform, which represents a 3x3 matrix
     but stores only the 6 elements needed for 2D affine transformations.
     
     [ a  b  0 ]     [ a  b  0  0 ]
     [ c  d  0 ]  -> [ c  d  0  0 ]
     [ tx ty 1 ]     [ 0  0  1  0 ]
     .               [ tx ty 0  1 ]
     
     Used for transforming texture coordinates in the shader modifier.
     (Needs to be SCNMatrix4, not SIMD float4x4, for passing to shader modifier via KVC.)
     */
    init(_ affineTransform: CGAffineTransform) {
        self.init()
        m11 = Float(affineTransform.a)
        m12 = Float(affineTransform.b)
        m21 = Float(affineTransform.c)
        m22 = Float(affineTransform.d)
        m41 = Float(affineTransform.tx)
        m42 = Float(affineTransform.ty)
        m33 = 1
        m44 = 1
    }
}
