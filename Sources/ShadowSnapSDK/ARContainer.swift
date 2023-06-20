//ARContainer.swift

import Foundation
import SwiftUI

public struct ARContainer : UIViewControllerRepresentable {
    
    public typealias UIViewControllerType = ARViewController
    
    let ref: (ARViewController) -> Void
    
    public init(ref: @escaping (ARViewController) -> Void) {
            self.ref = ref
    }

    public func makeUIViewController(context: UIViewControllerRepresentableContext<ARContainer>) -> ARViewController {
        let controller = ARViewController()
        ref(controller)
        return controller
    }
    
    public func updateUIViewController(_ view: ARViewController, context: Context) {
        // noop
    }
}
