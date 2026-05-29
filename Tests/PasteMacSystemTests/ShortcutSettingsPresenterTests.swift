import PasteCore
@testable import PasteMacSystem
import Testing

@Test func settingsFeedbackAppliedMessageUsesCurrentLanguage() {
    let feedback = SettingsFeedback.appliedShortcut("Cmd+Option+V")

    #expect(feedback.isError == false)
    #expect(feedback.message(language: .english) == "Applied Cmd+Option+V.")
    #expect(feedback.message(language: .simplifiedChinese) == "已应用 Cmd+Option+V。")
}

@Test func settingsFeedbackValidationMessageUsesCurrentLanguage() {
    let feedback = SettingsFeedback.incompleteShortcut

    #expect(feedback.isError == true)
    #expect(feedback.message(language: .english) == "Choose at least one modifier and one key.")
    #expect(feedback.message(language: .simplifiedChinese) == "请至少选择一个修饰键和一个按键。")
}

@Test func settingsFeedbackShortcutFailureUsesCurrentLanguage() {
    let feedback = SettingsFeedback.shortcutFailure(.conflict)

    #expect(feedback.isError == true)
    #expect(feedback.message(language: .english) == "Shortcut is already used by another app.")
    #expect(feedback.message(language: .simplifiedChinese) == "快捷键已被其他应用占用。")
}
