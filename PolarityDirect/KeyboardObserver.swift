import Foundation
import Combine
import UIKit

final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)

        Publishers.Merge3(willShow, willHide, willChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self else { return }

                if note.name == UIResponder.keyboardWillHideNotification {
                    self.height = 0
                    return
                }

                if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    self.height = frame.height
                }
            }
            .store(in: &cancellables)
    }
}
