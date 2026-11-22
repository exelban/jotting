# Jotting

<p align="center">
  <img src="https://serhiy.s3.eu-central-1.amazonaws.com/github/jotting/icon.png" alt="Jotting app icon" width="128" height="128">
</p>

<picture>
  <source type="image/webp" srcset="https://serhiy.s3.eu-central-1.amazonaws.com/github/jotting/preview.webp">
  <img src="https://serhiy.s3.eu-central-1.amazonaws.com/github/jotting/preview.png" alt="Jotting scratchpad showing a photo walk note with three tabs open">
</picture>

A simple macOS scratchpad for quick plain-text notes.

## Install

Jotting runs on **macOS 14 (Sonoma) or later**. Download `Jotting.dmg` from the [GitHub releases page](https://github.com/exelban/jotting/releases), open the disk image, and drag Jotting into Applications.

## Using the scratchpad

Launch Jotting, then click its menu bar icon or press **Control + comma** to bring the scratchpad forward. Press the same shortcut while the scratchpad is focused to close that window. Start typing in the current tab, or press **⌘T** for a fresh one. Double-click a tab to name it.

Hold **Option** and drag a tab to reorder it. Drop it on another Jotting tab bar to move it there, or release it elsewhere outside the source window to open it in a new window. Press **Esc** to cancel.

| To | Press |
| --- | --- |
| Switch to the next or previous tab | Control + Tab or Control + Shift + Tab |
| Jump to one of the first eight tabs | ⌘1 through ⌘8 |
| Jump to the last tab | ⌘9 |
| Find text in the current tab | ⌘F |
| Hide the scratchpad | ⌘H |

Jotting saves each open tab as you type. Press **⌘S** to save pending edits in Jotting immediately. Use **⌘O** to open an existing note. To write your edits back to that file or save a new `.txt` or `.md` file, choose **File → Save As…** (**⇧⌘S**).

## Settings

Choose **Jotting → Settings…** (**⌘,**) to open the JSON settings in a tab. Edit the global shortcut, theme, font, or line markers, then press **⌘S** to apply your changes. The `application` section contains `launchAtLogin`, `dockIcon`, `menuBar`, and `globalShortcut`. The Dock icon is enabled by default. Set `"dockIcon": false` to hide it. In the `interface` section, set `"lineMarker": "number"` to show line numbers.

In the same section, set `"interfaceStyle": "glass"` to let the colors of windows behind Jotting show faintly through the editor and title bar. The background is blurred and tinted with your theme color. Use `"interfaceStyle": "classic"` for the default opaque background.

## Run from source

Open `Jotting.xcodeproj` in Xcode, select the **Jotting** scheme, and press **⌘R**.

## License

[MIT License](LICENSE)
