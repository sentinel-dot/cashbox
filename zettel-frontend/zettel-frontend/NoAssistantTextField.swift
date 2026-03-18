// NoAssistantTextField.swift
// cashbox — UIViewRepresentable-Wrapper der die iPad InputAssistantBar deaktiviert.
//
// Hintergrund: SwiftUI's TextField nutzt intern einen eigenen InputAccessoryGenerator,
// dessen Constraints mit UIKit's SystemInputAssistantView kollidieren ("Unable to
// simultaneously satisfy constraints"). UITextField.appearance() greift nicht, da
// SwiftUI's interne Implementierung UIAppearance-Proxies ignoriert.
// Lösung: UIViewRepresentable mit direktem Zugriff auf inputAssistantItem.
// Deckt sowohl normale Texteingabe als auch SecureEntry (Passwort) ab.

import SwiftUI

struct NoAssistantTextField: UIViewRepresentable {
    let placeholder:          String
    @Binding var text:        String
    var keyboardType:         UIKeyboardType                  = .default
    var uiFont:               UIFont                          = UIFont.systemFont(ofSize: 14)
    var uiTextColor:          UIColor                         = UIColor.label
    var textAlignment:        NSTextAlignment                 = .natural
    var isSecure:             Bool                            = false
    var textContentType:      UITextContentType?              = nil
    var autocapitalizationType: UITextAutocapitalizationType  = .sentences
    var autocorrectionType:   UITextAutocorrectionType        = .default
    @Binding var isFocused:   Bool

    init(
        placeholder:            String,
        text:                   Binding<String>,
        keyboardType:           UIKeyboardType                  = .default,
        uiFont:                 UIFont                          = UIFont.systemFont(ofSize: 14),
        uiTextColor:            UIColor                         = UIColor.label,
        textAlignment:          NSTextAlignment                 = .natural,
        isSecure:               Bool                            = false,
        textContentType:        UITextContentType?              = nil,
        autocapitalizationType: UITextAutocapitalizationType    = .sentences,
        autocorrectionType:     UITextAutocorrectionType        = .default,
        isFocused:              Binding<Bool>                   = .constant(false)
    ) {
        self.placeholder            = placeholder
        self._text                  = text
        self.keyboardType           = keyboardType
        self.uiFont                 = uiFont
        self.uiTextColor            = uiTextColor
        self.textAlignment          = textAlignment
        self.isSecure               = isSecure
        self.textContentType        = textContentType
        self.autocapitalizationType = autocapitalizationType
        self.autocorrectionType     = autocorrectionType
        self._isFocused             = isFocused
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder                = placeholder
        tf.keyboardType               = keyboardType
        tf.font                       = uiFont
        tf.textColor                  = uiTextColor
        tf.textAlignment              = textAlignment
        tf.isSecureTextEntry          = isSecure
        tf.textContentType            = textContentType
        tf.autocapitalizationType     = autocapitalizationType
        tf.autocorrectionType         = autocorrectionType
        tf.borderStyle                = .none
        tf.backgroundColor            = .clear

        // Entfernt SystemInputAssistantView (QuickType/Undo-Bar auf iPad).
        // Das ist der direkte Fix für die AutoLayout-Constraint-Konflikte.
        tf.inputAssistantItem.leadingBarButtonGroups  = []
        tf.inputAssistantItem.trailingBarButtonGroups = []

        tf.addTarget(context.coordinator,
                     action: #selector(Coordinator.textChanged(_:)),
                     for: .editingChanged)
        tf.delegate = context.coordinator
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text        { uiView.text = text }
        if uiView.font != uiFont      { uiView.font = uiFont }
        uiView.textColor              = uiTextColor
        uiView.isSecureTextEntry      = isSecure

        // Fokus im nächsten Run-Loop-Zyklus setzen, um Layout-Rekursion zu vermeiden.
        let shouldFocus = isFocused
        guard shouldFocus != uiView.isFirstResponder else { return }
        DispatchQueue.main.async {
            if shouldFocus {
                uiView.becomeFirstResponder()
            } else {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NoAssistantTextField
        init(_ parent: NoAssistantTextField) { self.parent = parent }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }
    }
}
