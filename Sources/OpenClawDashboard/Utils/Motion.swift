import SwiftUI

enum Motion {
    static func perform(_ reduceMotion: Bool, animation: Animation? = .default, _ body: @escaping () -> Void) {
        if reduceMotion {
            body()
        } else {
            withAnimation(animation, body)
        }
    }
}
