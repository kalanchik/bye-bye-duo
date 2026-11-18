import SwiftUI

enum OnboardingIcon: View {
    case logo
    case bolt
    case codex
    case down
    case terminal
    case copy
    case arrow
    case success
    case stageCheck
    case back
    case plane
    case briefcase
    case chat
    case book
    case star
    case plus
    case arrowDisabled
    case grid
    case formatChat
    case formatBook
    case formatTarget
    case clock
    case choiceCheck
    case pencil
    case bell
    case target
    case warningBolt
    case play
    case spinner
    case spinnerDisabled
    case rewardStar
    case codexMenu
    case menuCheck
    case claude
    case gemini
    case cursor
    case info
    case copyCheck
    case error
    case refresh

    var body: some View {
        switch self {
        case .logo: PlanGraphic(.setupLogo, 16.45, 16.181)
        case .bolt: PlanGraphic(.setupBolt, 13.1667, 18.1667)
        case .codex: PlanGraphic(.setupCodex, 22, 22)
        case .down: PlanGraphic(.setupDown, 10.35, 5.85)
        case .terminal: PlanGraphic(.setupTerminal, 13.1667, 9.83333)
        case .copy: PlanGraphic(.setupCopy, 13.35, 13.35)
        case .arrow: PlanGraphic(.setupArrow, 12.6, 10.35)
        case .success: PlanGraphic(.setupSuccess, 13.1667, 9.83333)
        case .stageCheck: PlanGraphic(.setupStageCheck, 10.5333, 7.86667)
        case .back: PlanGraphic(.setupBack, 14, 11.5)
        case .plane: PlanGraphic(.setupPlane, 18.1667, 18.1667)
        case .briefcase: PlanGraphic(.setupCase, 16.5, 16.5)
        case .chat: PlanGraphic(.setupChat, 15.6667, 15.4105)
        case .book: PlanGraphic(.setupBook, 16.5, 15.817)
        case .star: PlanGraphic(.setupStar, 15.8334, 15.25)
        case .plus: PlanGraphic(.setupPlus, 13.1667, 13.1667)
        case .arrowDisabled: PlanGraphic(.setupArrowDisabled, 12.6, 10.35)
        case .grid: PlanGraphic(.setupGrid, 14, 13.1667)
        case .formatChat: PlanGraphic(.setupFormatChat, 15.6667, 15.4105)
        case .formatBook: PlanGraphic(.setupFormatBook, 16.5, 15.817)
        case .formatTarget: PlanGraphic(.setupFormatTarget, 16.5, 16.5)
        case .clock: PlanGraphic(.setupClock, 16.5, 16.5)
        case .choiceCheck: PlanGraphic(.setupChoiceCheck, 9.21667, 6.88333)
        case .pencil: PlanGraphic(.setupPencil, 14.8333, 14.8333)
        case .bell: PlanGraphic(.setupBell, 16.5, 18.1667)
        case .target: PlanGraphic(.setupTarget, 16.5, 16.5)
        case .warningBolt: PlanGraphic(.setupWarningBolt, 13.1667, 18.1667)
        case .play: PlanGraphic(.setupPlay, 10.6667, 13.1667)
        case .spinner: PlanGraphic(.setupSpinner, 14.8333, 14.8333)
        case .spinnerDisabled: PlanGraphic(.setupSpinnerDisabled, 13.35, 13.35)
        case .rewardStar: PlanGraphic(.setupRewardStar, 15.8334, 15.25)
        case .codexMenu: PlanGraphic(.setupCodexMenu, 21, 21)
        case .menuCheck: PlanGraphic(.setupMenuCheck, 11.85, 8.85)
        case .claude: PlanGraphic(.setupClaude, 21, 21)
        case .gemini: PlanGraphic(.setupGemini, 21, 21)
        case .cursor: PlanGraphic(.setupCursor, 21, 21)
        case .info: PlanGraphic(.setupInfo, 16.5, 16.5)
        case .copyCheck: PlanGraphic(.setupCopyCheck, 11.85, 8.85)
        case .error: PlanGraphic(.setupError, 16.5, 16.5)
        case .refresh: PlanGraphic(.setupRefresh, 13.3501, 12.5966)
        }
    }
}
