//
//  CustomCameraControls.swift
//  ShadowSnap
//
//  Created by Harry He on 28/04/23.
//

import UIKit
import SceneKit

class CustomCameraControls: NSObject, UIGestureRecognizerDelegate {
    private weak var sceneView: SCNView?
    private weak var headNode: SCNNode?
    
    private var panGestureRecognizer: UIPanGestureRecognizer?

    init(sceneView: SCNView, headNode: SCNNode) {
        self.sceneView = sceneView
        self.headNode = headNode
        super.init()
        
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer?.delegate = self
        sceneView.addGestureRecognizer(panGestureRecognizer!)
    }
    
    @objc func handlePanGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let headNode = headNode else { return }

        let translation = gestureRecognizer.translation(in: sceneView)
        let sensitivity: Float = 0.01

        let deltaX = Float(translation.x) * sensitivity
        //let deltaY = Float(translation.y) * sensitivity

        // When swiping right, rotate headNode anti-clockwise on X axis
        // When swiping left, rotate headNode clockwise on X axis
        headNode.eulerAngles.y += deltaX

        // When swiping up, rotate headNode anti-clockwise on Y axis
        // When swiping down, rotate headNode clockwise on Y axis
        //headNode.eulerAngles.x += deltaY

        gestureRecognizer.setTranslation(CGPoint.zero, in: sceneView)
    }


    
    func enable() {
        panGestureRecognizer?.isEnabled = true
    }

    func disable() {
        panGestureRecognizer?.isEnabled = false
    }
}



