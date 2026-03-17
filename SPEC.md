# SPEC.md: tetris-60.el

## 1. Project Overview
`tetris-60` is a retro game extension package for Emacs. This project aims to create a character-level, pixel-perfect replica of the original 1984 Tetris developed by Alexey Pajitnov on the Soviet Electronika 60 computer. The project strips away all modern graphical glyphs and color elements found in the modern Emacs `tetris.el`, returning to the purest terminal ASCII aesthetic.

## 2. Design Philosophy & Visuals
**Core Principle:** Uncompromising roughness and minimalism.

* **Display Engine:** Fully disable graphical rendering (XPM/PNG icons); strictly pure text character output.
* **Block Composition:** All Tetrominoes are uniformly represented using `[ ]` (left bracket + right bracket), with no color differentiation.
* **Background Pattern:** Use `.` (period) to fill empty grids, or keep it completely black to simulate the scanning texture of early CRT monitors.
* **Color Scheme:**
    * **Foreground:** Phosphor Green (e.g., `#33FF33`) or pure white.
    * **Background:** Pure black (`#000000`).
* **UI Layout:**
    * Discard the modern sidebar scoreboard.
    * Borders are drawn using basic ASCII characters: `+`, `-`, `|`.
    * Game states (Score, Level, Next) are embedded as pure text on the right or bottom of the main grid.

## 3. Architecture
The project is built upon Emacs's built-in `gamegrid.el` library, utilizing a "hard fork" of the native `tetris.el` for deep modification.

* **Namespace:** All functions, variables, and faces must use the `tetris-60-` prefix to avoid conflicts with the built-in version.
* **Dependencies:** Relies solely on Emacs Lisp standard libraries (`cl-lib`, `gamegrid`) to ensure flawless performance in pure terminal environments (`emacs -nw`).
* **Keybindings:**
    * Maintain hacker conventions: `j` (Left), `l` (Right), `i` (Rotate), `k` (Soft Drop), `Space` (Hard Drop).
    * Retain classic arrow key support.

## 4. Functional Specifications
* **Core Gameplay:** Standard 10x20 grid (Since `[ ]` occupies two columns, the actual rendering width is 20 characters).
* **Scoring System:** Adopts the original scoring logic; excludes modern T-Spin rewards or Back-to-Back bonuses.
* **Speed Increment:** The drop delay (Tick rate) decreases non-linearly as the number of cleared lines increases.
* **Ghost Piece:** **Strictly disabled.** The 1984 version had no drop indicator; players must rely on intuition alone.

## 5. Data & Persistence
* **Scoreboard File:** Stored by default at `~/.emacs.d/games/tetris-60-scores`.
* **Data Format:** Uses an easily parsable, structured plain text format (e.g., CSV/TSV style: `Score | Lines | Timestamp`). This clean structure facilitates writing data pipelines or scripts to extract high scores for external display on a GitHub profile or portfolio.

## 6. Packaging & Distribution
* **Package Management:** Follows standard `package.el` formatting with proper File Headers, preparing for future submission to MELPA.
* **Hosting:** Hosted on GitHub, accompanied by a standard open-source license (e.g., GPLv3).

## 7. Easter Eggs & Thematic Enhancements (Optional)
To further enhance the cinematic and retro feel of the project, the following thematic features can be implemented:
* **Boot Sequence Animation:** Simulate a 1984 Soviet computer startup screen with blinking terminal cursors and system initialization text before the game grid renders.
* **Audio/Sound Effects:** Hook into the system's native command (e.g., the `beep` utility in Linux/Fedora) or play low-bitrate 8-bit audio to mimic early PC speaker sounds when lines are cleared.
* **CRT Monitor Simulation:** Utilize Emacs's `line-spacing` property to slightly stretch the vertical distance between rows, simulating the horizontal scan lines and aspect ratio of an old cathode-ray tube display.
