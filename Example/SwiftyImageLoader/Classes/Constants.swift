//
//  Created by Kiavash Faisali on 10/2/16.
//
//

import Foundation
import UIKit

public enum ImageLoadingError: Error {
    case improperUrl
    case downloadError
}
public typealias ImageCompletion = (_ finished: Bool, _ error: Error?) -> ()
// MARK: - CompletionHolder Class
//final internal class CompletionHolder {
//    var completion: (Completion)?
//    
//    init(completion: Completion?) {
//        self.completion = completion
//    }
//}

// MARK: - ControlStateHolder Class
//final internal class ControlStateHolder {
//    var controlState: UIControlState
//    
//    init(state: UIControlState) {
//        self.controlState = state
//    }
//}
