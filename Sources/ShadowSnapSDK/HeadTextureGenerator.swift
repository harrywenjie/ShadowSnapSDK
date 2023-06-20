//HeadTextureGenerator.swift

import Foundation
import Metal
import UIKit
import ARKit

/// Generates the head texture from AR frames
class HeadTextureGenerator {
    
    private static func renderTargetDescriptor(textureSize: Int) -> MTLTextureDescriptor {
        let renderTargetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: textureSize, height: textureSize, mipmapped: false)
        renderTargetDescriptor.storageMode = .shared
        renderTargetDescriptor.usage = [.shaderWrite, .shaderRead, .renderTarget]
        return renderTargetDescriptor;
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let viewportSize: CGSize
    
    private let textureSize: Int
    
    private let cameraImageTextureCache: CVMetalTextureCache

    private let renderTarget: MTLTexture

    private let renderPipelineState: MTLRenderPipelineState
    private let renderPassDescriptor: MTLRenderPassDescriptor
    
    private let indexCount: Int

    private let indexBuffer: MTLBuffer
    private let positionBuffer: MTLBuffer
    private let normalBuffer: MTLBuffer
    private let uvBuffer: MTLBuffer

    init(device: MTLDevice, library: MTLLibrary, viewportSize: CGSize, head: MeshData, textureSize: Int) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.viewportSize = viewportSize
        self.textureSize = textureSize
        
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        cameraImageTextureCache = textureCache!

        renderTarget = device.makeTexture(descriptor: HeadTextureGenerator.renderTargetDescriptor(textureSize: textureSize))!
        
        renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = renderTarget
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm

        pipelineDescriptor.vertexFunction = library.makeFunction(name: "headTextureVertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "headTextureFragment")

        self.renderPipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        self.indexCount = head.indices.count

        self.indexBuffer = device.makeBuffer(length: MemoryLayout<UInt16>.size * self.indexCount, options: [])!
        let byteSize = head.indices.count * MemoryLayout<UInt16>.size
        let data = Data(bytes: head.indices.map { UInt16($0) }, count: byteSize)
        
        let indexBufferContents = indexBuffer.contents()
        data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) in
            let source = sourcePtr.baseAddress!
            memcpy(indexBufferContents, source, byteSize)
        }
        
        let vertexCount = head.vertices.count
        self.positionBuffer = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * vertexCount, options: [])!
        self.normalBuffer = device.makeBuffer(length: MemoryLayout<SIMD3<Float>>.stride * vertexCount, options: [])!
        self.uvBuffer = device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride * vertexCount, options: [])!
        self.updateGeometry(head: head)
    }
    
    private func updateGeometry(head: MeshData) {
        let vertexCount = head.vertices.count
        let positionBufferSize = MemoryLayout<SIMD3<Float>>.stride * vertexCount
        let normalBufferSize = MemoryLayout<SIMD3<Float>>.stride * vertexCount
        let uvBufferSize = MemoryLayout<SIMD2<Float>>.stride * vertexCount
        
        // Copy the position data
        let positionData = Data(bytes: head.vertices.map { SIMD3<Float>($0) }, count: positionBufferSize)
        positionData.copyBytes(to: UnsafeMutableRawBufferPointer(
                                    start: self.positionBuffer.contents(),
                                    count: positionBufferSize))

        // Copy the normal data
        let normalData = Data(bytes: head.normals.map { SIMD3<Float>($0) }, count: normalBufferSize)
        normalData.copyBytes(to: UnsafeMutableRawBufferPointer(
                                    start: self.normalBuffer.contents(),
                                    count: normalBufferSize))

        // Copy the uv data
        let uvData = Data(bytes: head.finalTexCoords.map { SIMD2<Float>(Float($0.x), Float($0.y)) }, count: uvBufferSize)
        uvData.copyBytes(to: UnsafeMutableRawBufferPointer(
                                    start: self.uvBuffer.contents(),
                                    count: uvBufferSize))
   }

    
    func printBufferData<T>(buffer: MTLBuffer, type: T.Type, count: Int) {
        let dataPointer = buffer.contents().bindMemory(to: type, capacity: count)
        let dataArray = UnsafeBufferPointer(start: dataPointer, count: count)
        for i in 0..<count {
            print("\(i): \(dataArray[i])")
        }
    }
    
    /// Captured head texture for UV map
    public var texture: MTLTexture? {
        renderTarget
    }
    
    /// Update the head texture for the current frame
    public func update(frame: ARFrame, headNode: SCNNode, data: MeshData, cameraNode: SCNNode) {
        struct ShaderState {
            let displayTransform: float4x4
            let modelViewTransform: float4x4
            let projectionTransform: float4x4
        }

        self.updateGeometry(head: data)

        let (capturedImageTextureY, capturedImageTextureCbCr) = getCapturedImageTextures(frame: frame)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Could not create computeCommandBuffer")
        }
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(self.textureSize), height: Double(textureSize), znear: 0, zfar: 1))
        renderEncoder.setRenderPipelineState(self.renderPipelineState)

        // Buffers
        renderEncoder.setVertexBuffer(self.positionBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(self.normalBuffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(self.uvBuffer, offset: 0, index: 2)
        
        // Textures
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureY)!, index: 0)
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr)!, index: 1)
        
        // State
        let affineTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let displayTransform = SCNMatrix4Invert(SCNMatrix4(affineTransform))

        let worldTransform = headNode.worldTransform
        let viewTransform = SCNMatrix4Invert(cameraNode.transform)
        let modelViewTransform = SCNMatrix4Mult(worldTransform, viewTransform)
        let projectionTransform = cameraNode.camera!.projectionTransform
    
        var state = ShaderState(
            displayTransform: simd_float4x4(displayTransform),
            modelViewTransform: simd_float4x4(modelViewTransform),
            projectionTransform: simd_float4x4(projectionTransform))

        renderEncoder.setVertexBytes(&state, length: MemoryLayout<ShaderState>.stride, index: 3)

        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: self.indexCount, indexType: .uint16, indexBuffer: self.indexBuffer, indexBufferOffset: 0)

        renderEncoder.endEncoding()
        
        commandBuffer.commit()
    }
    
    private func getCapturedImageTextures(frame: ARFrame) -> (CVMetalTexture, CVMetalTexture)  {
        let pixelBuffer = frame.capturedImage
        let capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0)!
        let capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1)!
        return (capturedImageTextureY, capturedImageTextureCbCr)
    }
    
    private func getMTLPixelFormat(basedOn pixelBuffer: CVPixelBuffer!) -> MTLPixelFormat {
        let type = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if type == kCVPixelFormatType_DepthFloat32 {
            return .r32Float
        } else if type == kCVPixelFormatType_OneComponent8 {
            return .r8Uint
        } else if type == kCVPixelFormatType_32RGBA {
            return .rgba32Float
        } else {
            fatalError("Unsupported ARDepthData pixel-buffer format.")
        }
    }
    
    private func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, cameraImageTextureCache, pixelBuffer, nil, pixelFormat,
                                                               width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            printAndLog("Error \(status)")
            texture = nil
        }
        
        return texture
    }
}
