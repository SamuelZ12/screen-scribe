# ScreenScribe

*Capture. Extract. Format.*

<img src="Assets/Icon.png" alt="ScreenScribe Icon" width="64"/>

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-brightgreen)](https://github.com/SamuelZ12/screen-scribe/releases/latest)
[![GitHub all releases](https://img.shields.io/github/downloads/SamuelZ12/screen-scribe/total)](https://github.com/SamuelZ12/screen-scribe/releases)
[![License](https://img.shields.io/github/license/SamuelZ12/screen-scribe)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/SamuelZ12/screen-scribe)](https://github.com/SamuelZ12/screen-scribe/releases/latest)

A macOS menu bar application for capturing screen regions and extracting content using AI-powered prompts. Features built-in support for LaTeX and Markdown extraction, plus the ability to create your own custom prompts.

## Demo

Watch the application in action:

![ScreenScribe Demo GIF](Assets/demo.gif)

### Menu Bar Access
<img src="Assets/Menu_Bar.png" alt="ScreenScribe Menu Bar" width="200"/>

### Settings Panel
<img src="Assets/Settings_Panel.png" alt="ScreenScribe Settings Window" width="400"/>

## Features

* **Menu Bar Convenience:** Lives in your menu bar for quick access.
* **Screen Capture:** Use global keyboard shortcuts or the menu bar to capture any portion of your screen.
* **Text Extraction (Vision OCR):** Uses Apple's built-in Vision framework for fast, offline text recognition.
* **AI-Powered Extraction:** Leverages the Google Gemini API with customizable prompts for intelligent content extraction.
* **Built-in Prompts:**
  * **LaTeX:** Convert mathematical equations and formatted content to LaTeX code.
  * **Markdown:** Extract and convert content to clean Markdown format.
* **Custom Prompts:** Create, edit, and save your own prompts for specialized extraction needs.
* **Per-Prompt Output Format:** Configure how each prompt formats output (line breaks, spaces, or LaTeX newlines).
* **Default Prompt:** Set any prompt as the default for quick keyboard access.
* **Gemini Model Selection:** Choose between different Gemini models to optimize for speed, cost, or accuracy.
* **Clipboard Integration:** Automatically copies extracted content to your clipboard.
* **Customizable Shortcuts:** Set global keyboard shortcuts for text extraction and your default prompt.
* **Recent History:** Access recently captured results directly from the menu bar.
* **API Key Management:** Securely enter and store your Google Gemini API key via the Settings panel.

## Requirements

* **macOS:** Version 14.0 (Sonoma) or later.
* **Google Gemini API Key:** Required for AI-powered extraction (LaTeX, Markdown, and custom prompts). Get a free key from [Google AI Studio](https://makersuite.google.com/app/apikey).
* **Xcode:** Version 16.0 or later (if building from source).

## Gemini API Models and Rate Limits

ScreenScribe allows you to choose between the following Gemini models to optimize for your specific needs:

| Model | Description |
|-------|-------------|
| **Gemini 3.6 Flash** | Best balance of speed, cost, and accuracy |
| **Gemini 3.1 Pro** | Most capable model for complex content |
| **Gemini 3.5 Flash-Lite** | Fastest and most cost-effective option |

> Note: Availability and quotas can change; see Google's current [usage limits](https://ai.google.dev/gemini-api/docs/rate-limits) for details.

## Installation

### Quick Install

1. **Download** the latest `.dmg` from [Releases](https://github.com/SamuelZ12/screen-scribe/releases/latest)
2. **Open** the DMG and drag ScreenScribe to Applications
3. **Right-click** the app and select "Open" (required for first launch)

### Opening for the First Time

Since this app is not notarized with Apple, macOS will show a security warning. Here's how to open it:

> Note: "Not notarized" is separate from "unsigned". Screen Recording permission relies on the app having a stable code signature, even if Gatekeeper still requires the right-click "Open" flow.

**Option 1: Right-click to Open (Recommended)**
1. Open Finder and go to Applications
2. Right-click (or Control-click) on ScreenScribe
3. Select "Open" from the context menu
4. Click "Open" in the dialog that appears

**Option 2: System Settings**
1. Try to open the app normally (it will be blocked)
2. Go to **System Settings > Privacy & Security**
3. Scroll down to find the message about ScreenScribe being blocked
4. Click "Open Anyway"

> This only needs to be done once. After the first successful launch, the app will open normally.

### First Launch

ScreenScribe launches directly in your menu bar.

On the first capture attempt, ScreenScribe will request **Screen Recording** permission.  
If you deny it, you can enable it later in **System Settings > Privacy & Security > Screen Recording**.

Gemini API key setup is optional and is configured from **Settings**.

## Usage

**Capture:**
* Click the menu bar icon and select "Extract Text" for offline OCR, or choose a prompt (LaTeX, Markdown, or custom)
* Use keyboard shortcuts: **Cmd+T** for text, **Cmd+L** for your default AI prompt
* If Screen Recording permission is missing, ScreenScribe asks for it when you trigger capture

**Select Area:** Your cursor will turn into a crosshair. Click and drag to select the screen region.

**Result:**
* A sound plays on successful capture
* Content is automatically copied to your clipboard
* Menu bar icon briefly shows a checkmark

**History:** Access recent captures from the menu bar under "Recent Captures"

**Settings:**
* **API Key:** Enter your Google Gemini API Key for AI-powered extraction
* **Gemini Model:** Select your preferred model (speed vs. accuracy trade-off)
* **Shortcuts:** Customize keyboard shortcuts
* **Prompts:** Create custom prompts, edit copy formats, set your default

## Custom Prompts

Create your own prompts for specialized extraction:

1. Open **Settings** from the menu bar.
2. In the **Prompts** section, click the **+** button.
3. Enter a name and write your prompt instructions.
4. Choose your preferred copy format (line breaks, spaces, or LaTeX newlines).
5. Click **Create** to save.

You can set any prompt as your default by selecting it and clicking **Set as Default**. The default prompt will be triggered by the keyboard shortcut (Cmd+L by default).

**Note:** Built-in prompts (LaTeX and Markdown) cannot be deleted or have their content modified, but you can change their copy format.

## Building from Source

If you prefer to build the application yourself:

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/SamuelZ12/screen-scribe.git
    cd screen-scribe
    ```
2.  **Open in Xcode:**
    ```bash
    open ScreenScribe.xcodeproj
    ```
3.  **Select Scheme:** Ensure the `ScreenScribe` scheme is selected.
4.  **Build/Run:** Press `Cmd+B` to build or `Cmd+R` to run the application directly on your Mac. (Apps you build yourself typically don't trigger the same Gatekeeper warnings on your own machine).
5.  **(Required for AI extraction)** **Configure API Key and Model:** After running the built app, open its Settings panel from the menu bar icon, enter your Google Gemini API key, and select your preferred model.

## Code Structure Overview

* `ScreenScribe/Sources/App.swift`: Main application delegate, menu bar setup, capture initiation, and result handling.
* `ScreenScribe/Sources/Recognizer.swift`: Handles text OCR using Apple's Vision framework.
* `ScreenScribe/Sources/Models/Prompt.swift`: Prompt data model with built-in LaTeX and Markdown prompts.
* `ScreenScribe/Sources/Services/GeminiService.swift`: Manages interaction with the Google Gemini API.
* `ScreenScribe/Sources/Services/PromptManager.swift`: CRUD operations for prompts and persistence.
* `ScreenScribe/Sources/Settings/`: Contains SwiftUI views for settings and prompt management.
* `ScreenScribe/Sources/Extensions/`: Utility extensions for various AppKit/Foundation classes.
* `ScreenScribe/Info.plist`: Application metadata and permission descriptions.
* `ScreenScribe.xcodeproj`: Xcode project file.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built on top of [TextGrabber2](https://github.com/TextGrabber2-app/TextGrabber2) by cyanzhong
