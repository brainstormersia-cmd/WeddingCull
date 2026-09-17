import Foundation

public enum AccessibilityIdentifiers {
    // Start screen
    public static let importButton = "start_import_button"
    public static let openSessionButton = "start_open_session_button"
    public static let startTitle = "start_title"

    // Analysis screen
    public static let analysisProgressIndicator = "analysis_progress_indicator"
    public static let analysisPhaseLabel = "analysis_phase_label"
    public static let analysisCancelButton = "analysis_cancel_button"
    public static let analysisPauseButton = "analysis_pause_button"
    public static let analysisResumeButton = "analysis_resume_button"

    // Main Review Screen
    public static let sidebarList = "sidebar_list"
    public static let photoGrid = "photo_grid"
    public static let inspectorPanel = "inspector_panel"
    public static let burstCompareModal = "burst_compare_modal"
    public static let exportButton = "main_export_button"
    public static let targetCountInput = "target_count_input"
    public static let targetCountSlider = "target_count_slider"
    public static let recalculateButton = "recalculate_selection_button"

    // Selection buttons
    public static let selectButton = "action_select_button"
    public static let alternativeButton = "action_alternative_button"
    public static let rejectButton = "action_reject_button"

    // Burst Compare
    public static let burstFramePrefix = "burst_frame_"
    public static let setWinnerButton = "set_burst_winner_button"
    public static let closeBurstCompareButton = "close_burst_compare_button"

    // Export Dialog
    public static let exportDestinationFolder = "export_destination_folder"
    public static let exportConfirmButton = "export_confirm_button"
    public static let exportCancelButton = "export_cancel_button"
    public static let exportResultSummary = "export_result_summary"

    // Real Photo Display & Loupe
    public static let photoThumbnailLoaded = "photo_thumbnail_loaded"
    public static let photoThumbnailPlaceholder = "photo_thumbnail_placeholder"
    public static let photoPreviewLoaded = "photo_preview_loaded"
    public static let photoPreviewPlaceholder = "photo_preview_placeholder"
    public static let burstLoupeView = "burst_loupe_view"
    public static let burstFaceFocusButton = "burst_face_focus_button"
    public static let burstZoomLoupeButton = "burst_zoom_loupe_button"
}
