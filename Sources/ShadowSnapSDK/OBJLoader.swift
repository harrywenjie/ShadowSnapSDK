//
//  OBJLoader.swift
//  ShadowSnap
//
//  Created by Harry He on 20/04/23.
//

import Foundation
import SceneKit

struct MeshData {
    var vertices: [SCNVector3] = []
    var originalVertices: [SCNVector3] = []
    var texCoords: [CGPoint] = []
    var indices: [Int32] = []
    var finalTexCoords: [CGPoint] = []
    var normals: [SCNVector3] = []
    var vertexMap: [Int: [Int]] = [:]
}

func parseOBJFile(url: URL) -> MeshData? {
    do {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var meshData = MeshData()

        for line in lines {
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            if components.isEmpty { continue }

            switch components[0] {
            case "v":
                if components.count >= 4,
                   let x = Float(components[1]),
                   let y = Float(components[2]),
                   let z = Float(components[3]) {
                    meshData.vertices.append(SCNVector3(x, y, z))
                    meshData.originalVertices.append(SCNVector3(x, y, z))
                }
            case "vt":
                if components.count >= 3,
                   let u = Float(components[1]),
                   let v = Float(components[2]) {
                    meshData.texCoords.append(CGPoint(x: CGFloat(u), y: CGFloat(1 - v))) // Flip the V coordinate
                }
            case "vn":
                if components.count >= 4,
                   let x = Float(components[1]),
                   let y = Float(components[2]),
                   let z = Float(components[3]) {
                    meshData.normals.append(SCNVector3(x, y, z))
                }
            default:
                continue
            }
        }
        printAndLog("Original vertex count: \(meshData.vertices.count)")
        
        var tempVertices: [SCNVector3] = []
        var tempTexCoords: [CGPoint] = []
        var tempNormals: [SCNVector3] = []
        var inverseVertexMap: [Int: [Int]] = [:]

        for line in lines {
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            if components.isEmpty { continue }

            if components[0] == "f" {
                for i in 1..<components.count {
                    let indices = components[i].components(separatedBy: "/")
                    if indices.count >= 3, let vertexIndex = Int32(indices[0]), let texCoordIndex = Int32(indices[1]), let normalIndex = Int32(indices[2]) {
                        tempVertices.append(meshData.vertices[Int(vertexIndex - 1)])
                        tempTexCoords.append(meshData.texCoords[Int(texCoordIndex - 1)])
                        tempNormals.append(meshData.normals[Int(normalIndex - 1)])
                        let newIndex = tempVertices.count - 1
                        meshData.indices.append(Int32(newIndex))
                        if inverseVertexMap[Int(vertexIndex - 1)] == nil {
                            inverseVertexMap[Int(vertexIndex - 1)] = [newIndex]
                        } else {
                            inverseVertexMap[Int(vertexIndex - 1)]?.append(newIndex)
                        }
                    }
                }
            }
        }

        meshData.vertices = tempVertices
        meshData.finalTexCoords = tempTexCoords
        meshData.normals = tempNormals
        meshData.vertexMap = inverseVertexMap
        


        printAndLog("New vertex count: \(tempVertices.count)")

        return meshData
    } catch {
        printAndLog("Error: Could not read OBJ file: \(error)")
        return nil
    }
}


func createGeometry(meshData: MeshData) -> SCNGeometry {
    let vertexSource = SCNGeometrySource(vertices: meshData.vertices)
    let texCoordSource = SCNGeometrySource(textureCoordinates: meshData.finalTexCoords)
    let normalSource = SCNGeometrySource(normals: meshData.normals) // Use meshData.normals here

    let data = Data(bytes: meshData.indices, count: meshData.indices.count * MemoryLayout<Int32>.size)
    let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: meshData.indices.count / 3, bytesPerIndex: MemoryLayout<Int32>.size)

    let geometry = SCNGeometry(sources: [vertexSource, texCoordSource, normalSource], elements: [element])

    return geometry
}


