//
//  BlendTexture.swift
//  ShadowSnap
//
//  Created by Harry He on 29/04/23.
//

import Metal
import MetalKit
import UIKit

class BlendTexture {
    private let device: MTLDevice
    private var computePipelineState: MTLComputePipelineState!
    private var blendPipelineState: MTLComputePipelineState!
    private var maskTexture: MTLTexture!
    private var skinTexture: MTLTexture!
    private var sampleMask: MTLTexture!
    private let commandQueue: MTLCommandQueue
    private let threadGroupCount: MTLSize
    
    // Define a serial dispatch queue for synchronization
    private let commandQueueDispatchQueue = DispatchQueue(label: "com.blendtexture.commandqueue")
    
    init?(device: MTLDevice) {
        self.device = device

        // Add this line to initialize the command queue
        guard let commandQueue = device.makeCommandQueue() else {
            printAndLog("Failed to create command queue")
            return nil
        }
        self.commandQueue = commandQueue
            
        // Load the textures
        let textureLoader = MTKTextureLoader(device: device)
        let bundle = Bundle.module
        do {
            if let url = bundle.url(forResource: "headMask", withExtension: "png") {
                maskTexture = try textureLoader.newTexture(URL: url, options: [.origin: MTKTextureLoader.Origin.topLeft])
                printAndLog("Mask texture loaded")
            }
            if let url = bundle.url(forResource: "sampleMask", withExtension: "png") {
                sampleMask = try textureLoader.newTexture(URL: url, options: [.origin: MTKTextureLoader.Origin.topLeft])
                printAndLog("sampleMask loaded")
            }
        } catch let error {
            printAndLog("Failed to load textures: \(error.localizedDescription)")
            return nil
        }

        // Create the compute pipeline state
        guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
            printAndLog("Failed to create default library")
            return nil
        }
        
        // Compute Pipeline for computeMeanColor
        do {
            if let computeFunction = library.makeFunction(name: "computeMeanColor") {
                let computePipelineState = try device.makeComputePipelineState(function: computeFunction)
                self.computePipelineState = computePipelineState
            }
        } catch let error {
            printAndLog("Failed to create compute pipeline state: \(error.localizedDescription)")
            return nil
        }


        // Compute Pipeline for blendWithMeanColorAndMask
        do {
            if let blendFunction = library.makeFunction(name: "blendWithMeanColor") {
                let blendPipelineState = try device.makeComputePipelineState(function: blendFunction)
                self.blendPipelineState = blendPipelineState
            }
        } catch let error {
            printAndLog("Failed to create blend pipeline state: \(error.localizedDescription)")
            return nil
        }
        
        // Add this line to calculate threadGroupCount
        let maxThreadsCompute = computePipelineState.maxTotalThreadsPerThreadgroup
        let maxThreadsBlend = blendPipelineState.maxTotalThreadsPerThreadgroup
        let threads = Int(sqrt(Double(min(maxThreadsCompute, maxThreadsBlend))))
        self.threadGroupCount = MTLSize(width: threads, height: threads, depth: 1)
    }

 
    //Compute mean color from texture
    func computeMeanColor(headTexture: MTLTexture) -> SIMD4<Float> {
        // Create buffers to store the results
        let bufferLength = MemoryLayout<Float>.size
        let colorSumX = device.makeBuffer(length: bufferLength, options: [])
        let colorSumY = device.makeBuffer(length: bufferLength, options: [])
        let colorSumZ = device.makeBuffer(length: bufferLength, options: [])
        let colorSumW = device.makeBuffer(length: bufferLength, options: [])
        let count = device.makeBuffer(length: bufferLength, options: [])
        
        var meanColor: SIMD4<Float>!
        commandQueueDispatchQueue.sync {
            let commandBuffer = commandQueue.makeCommandBuffer()
            let computeEncoder = commandBuffer?.makeComputeCommandEncoder()
            computeEncoder?.setComputePipelineState(computePipelineState)
            computeEncoder?.setTexture(headTexture, index: 0)
            computeEncoder?.setTexture(sampleMask, index: 1)
            computeEncoder?.setBuffer(colorSumX, offset: 0, index: 0)
            computeEncoder?.setBuffer(colorSumY, offset: 0, index: 1)
            computeEncoder?.setBuffer(colorSumZ, offset: 0, index: 2)
            computeEncoder?.setBuffer(colorSumW, offset: 0, index: 3)
            computeEncoder?.setBuffer(count, offset: 0, index: 4)

            let threadGroups = MTLSizeMake((headTexture.width + threadGroupCount.width - 1) / threadGroupCount.width,
                                           (headTexture.height + threadGroupCount.height - 1) / threadGroupCount.height,
                                           1)
            computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            computeEncoder?.endEncoding()
            commandBuffer?.commit()
            commandBuffer?.waitUntilCompleted()
            
            // Read the results
            let colorSumXValue = Float(colorSumX!.contents().load(as: UInt32.self)) / 255.0
            let colorSumYValue = Float(colorSumY!.contents().load(as: UInt32.self)) / 255.0
            let colorSumZValue = Float(colorSumZ!.contents().load(as: UInt32.self)) / 255.0
            let colorSumWValue = Float(colorSumW!.contents().load(as: UInt32.self)) / 255.0
            let countValue = Float(count!.contents().load(as: UInt32.self))

            // Calculate the mean color
            meanColor = SIMD4<Float>(colorSumXValue, colorSumYValue, colorSumZValue, colorSumWValue) / countValue
        }
        
        return meanColor
    }

    // Function to perform the blending operation
    func blend(headTexture: MTLTexture) -> MTLTexture? {
        let width = headTexture.width
        let height = headTexture.height

        // Compute the mean color
        var meanColor = computeMeanColor(headTexture: headTexture)

        let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        guard let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor) else {
            fatalError("Failed to create output texture.")
        }

        commandQueueDispatchQueue.sync {
            let commandBuffer = commandQueue.makeCommandBuffer()
            let computeEncoder = commandBuffer?.makeComputeCommandEncoder()

            // Use pre-initialized blendPipelineState
            computeEncoder?.setComputePipelineState(blendPipelineState)

            computeEncoder?.setTexture(headTexture, index: 0)
            computeEncoder?.setTexture(maskTexture, index: 1)
            let meanColorBuffer = device.makeBuffer(bytes: &meanColor, length: MemoryLayout<SIMD4<Float>>.size, options: [])
            computeEncoder?.setBuffer(meanColorBuffer, offset: 0, index: 0)
            computeEncoder?.setTexture(outputTexture, index: 2)

            let threadGroups = MTLSizeMake((headTexture.width + threadGroupCount.width - 1) / threadGroupCount.width,
                                           (headTexture.height + threadGroupCount.height - 1) / threadGroupCount.height,
                                           1)
            computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
            computeEncoder?.endEncoding()
            commandBuffer?.commit()
            commandBuffer?.waitUntilCompleted()
        }

        return outputTexture
    }
}

