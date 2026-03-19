;;; tetris-60.el --- Retro ASCII Tetris for Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Codex
;; Keywords: games
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.1.0

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `tetris-60' is a terminal-first Tetris variant for Emacs that aims for
;; an uncompromising ASCII look: monochrome screen, dot-matrix empty cells,
;; bracket blocks, and a compact HUD.

;;; Code:

(require 'cl-lib)
(require 'gamegrid)

(defgroup tetris-60 nil
  "Retro ASCII Tetris for Emacs."
  :group 'games
  :prefix "tetris-60-")

(defcustom tetris-60-buffer-name "*Tetris-60*"
  "Name of the `tetris-60' buffer."
  :type 'string)

(defcustom tetris-60-default-tick-period 0.3
  "Fallback delay in seconds between automatic drops."
  :type 'number)

(defcustom tetris-60-update-speed-function
  #'tetris-60-default-update-speed-function
  "Function called after score-relevant state changes.

The function receives two arguments, SHAPES and LINES.  If it returns a
number, the result is used as the timer period."
  :type 'function)

(defcustom tetris-60-score-file
  (locate-user-emacs-file "games/tetris-60-scores")
  "File used to persist `tetris-60' scores in TSV format."
  :type 'file)

(defcustom tetris-60-score-file-length 50
  "Maximum number of score rows to keep in `tetris-60-score-file'."
  :type 'natnum)

(defcustom tetris-60-empty-cell-style 'dot
  "How empty playfield cells are rendered.

The value `dot' renders empty cells as `..'.  The value `blank' renders
them as two spaces."
  :type '(choice (const :tag "Dot matrix" dot)
                 (const :tag "Blank" blank)))

(defcustom tetris-60-foreground-color "#33FF33"
  "Foreground color used when `tetris-60-use-color' is non-nil."
  :type 'color)

(defcustom tetris-60-background-color "#000000"
  "Background color used when `tetris-60-use-color' is non-nil."
  :type 'color)

(defcustom tetris-60-show-controls t
  "Non-nil means display key hints in the HUD."
  :type 'boolean)

(defcustom tetris-60-use-color t
  "Non-nil means use a phosphor-green face remap in the game buffer."
  :type 'boolean)

(defcustom tetris-60-mode-hook nil
  "Hook run after entering `tetris-60-mode'."
  :type 'hook)

(defface tetris-60-screen-face
  '((t :inherit default))
  "Base face used by `tetris-60'."
  :group 'tetris-60)

(defconst tetris-60--board-width 10)
(defconst tetris-60--board-height 20)
(defconst tetris-60--board-x 2)
(defconst tetris-60--board-y 2)
(defconst tetris-60--hud-x 16)
(defconst tetris-60--hud-y 2)
(defconst tetris-60--preview-x tetris-60--hud-x)
(defconst tetris-60--preview-y 4)
(defconst tetris-60--controls-y 12)
(defconst tetris-60--buffer-width 44)
(defconst tetris-60--buffer-height 24)

(defconst tetris-60--cell-empty 128)
(defconst tetris-60--cell-filled 129)
(defconst tetris-60--cell-border-h 130)
(defconst tetris-60--cell-border-v 131)
(defconst tetris-60--cell-corner 132)

(defconst tetris-60--playfield-left (1- tetris-60--board-x))
(defconst tetris-60--playfield-right (+ tetris-60--board-x tetris-60--board-width))
(defconst tetris-60--playfield-top (1- tetris-60--board-y))
(defconst tetris-60--playfield-bottom (+ tetris-60--board-y tetris-60--board-height))

(defconst tetris-60--shapes
  [[[[0  0] [1  0] [0  1] [1  1]]]

   [[[0  0] [1  0] [2  0] [2  1]]
    [[1 -1] [1  0] [1  1] [0  1]]
    [[0 -1] [0  0] [1  0] [2  0]]
    [[1 -1] [2 -1] [1  0] [1  1]]]

   [[[0  0] [1  0] [2  0] [0  1]]
    [[0 -1] [1 -1] [1  0] [1  1]]
    [[2 -1] [0  0] [1  0] [2  0]]
    [[1 -1] [1  0] [1  1] [2  1]]]

   [[[0  0] [1  0] [1  1] [2  1]]
    [[1  0] [0  1] [1  1] [0  2]]]

   [[[1  0] [2  0] [0  1] [1  1]]
    [[0  0] [0  1] [1  1] [1  2]]]

   [[[1  0] [0  1] [1  1] [2  1]]
    [[1  0] [1  1] [2  1] [1  2]]
    [[0  1] [1  1] [2  1] [1  2]]
    [[1  0] [0  1] [1  1] [1  2]]]

   [[[0  0] [1  0] [2  0] [3  0]]
    [[1 -1] [1  0] [1  1] [1  2]]]]
  "Tetromino definitions, borrowed from the canonical Emacs Tetris shape set.")

(defconst tetris-60--shape-scores
  [[6] [6 7 6 7] [6 7 6 7] [6 7] [6 7] [5 5 6 5] [5 8]]
  "Per-shape score increments applied whenever a piece locks.")

(defconst tetris-60--shape-dimensions
  [[2 2] [3 2] [3 2] [3 2] [3 2] [3 2] [4 1]]
  "Bounding box dimensions for spawn placement.")

(defvar-local tetris-60--board nil)
(defvar-local tetris-60--shape 0)
(defvar-local tetris-60--rotation 0)
(defvar-local tetris-60--next-shape 0)
(defvar-local tetris-60--shape-count 0)
(defvar-local tetris-60--line-count 0)
(defvar-local tetris-60--score 0)
(defvar-local tetris-60--pos-x 0)
(defvar-local tetris-60--pos-y 0)
(defvar-local tetris-60--piece-active nil)
(defvar-local tetris-60--paused nil)
(defvar-local tetris-60--score-recorded nil)

(defvar-keymap tetris-60-mode-map
  :doc "Keymap used while a `tetris-60' game is active."
  :name 'tetris-60-mode-map
  "n" #'tetris-60-start-game
  "q" #'tetris-60-end-game
  "p" #'tetris-60-pause-game
  "j" #'tetris-60-move-left
  "l" #'tetris-60-move-right
  "i" #'tetris-60-rotate
  "k" #'tetris-60-move-down
  "SPC" #'tetris-60-hard-drop
  "<left>" #'tetris-60-move-left
  "<right>" #'tetris-60-move-right
  "<up>" #'tetris-60-rotate
  "<down>" #'tetris-60-move-down)

(defvar-keymap tetris-60-null-map
  :doc "Keymap used after a `tetris-60' game ends."
  :name 'tetris-60-null-map
  "n" #'tetris-60-start-game
  "q" #'quit-window)

(defun tetris-60-default-update-speed-function (_shapes lines)
  "Default speed curve for `tetris-60'.

The timer shortens as LINES increases and never drops below 0.05 seconds."
  (max 0.05 (/ 20.0 (+ 50.0 lines))))

(defun tetris-60--display-options ()
  "Return the `gamegrid' display options for `tetris-60'."
  (let ((options (make-vector 256 nil)))
    (dotimes (char 256)
      (aset options char `(((t ,char)) nil nil)))
    options))

(defun tetris-60--empty-cell-glyph ()
  "Return the two-column glyph string for an empty cell."
  (if (eq tetris-60-empty-cell-style 'blank) "  " ".."))

(defun tetris-60--apply-display-table ()
  "Install multi-character glyphs for the playfield cells."
  (aset buffer-display-table tetris-60--cell-empty (vconcat (tetris-60--empty-cell-glyph)))
  (aset buffer-display-table tetris-60--cell-filled (vconcat "[]"))
  (aset buffer-display-table tetris-60--cell-border-h (vconcat "--"))
  (aset buffer-display-table tetris-60--cell-border-v (vconcat "|"))
  (aset buffer-display-table tetris-60--cell-corner (vconcat "+")))

(defun tetris-60--setup-face ()
  "Apply the retro screen colors for the current buffer."
  (setq-local face-remapping-alist
              (when tetris-60-use-color
                `((default (:foreground ,tetris-60-foreground-color
                                        :background ,tetris-60-background-color)))))
  (setq-local cursor-type nil))

(defun tetris-60--init-buffer ()
  "Initialize the game buffer."
  (gamegrid-init-buffer tetris-60--buffer-width
                        tetris-60--buffer-height
                        ?\s)
  (tetris-60--draw-frame)
  (tetris-60--clear-rect tetris-60--hud-x 0
                         (- tetris-60--buffer-width tetris-60--hud-x)
                         tetris-60--buffer-height))

(defun tetris-60--make-empty-row ()
  "Return a fresh empty board row."
  (make-vector tetris-60--board-width 0))

(defun tetris-60--make-empty-board ()
  "Return a fresh empty game board."
  (let ((board (make-vector tetris-60--board-height nil)))
    (dotimes (y tetris-60--board-height)
      (aset board y (tetris-60--make-empty-row)))
    board))

(defun tetris-60--board-cell (x y)
  "Return the board value at X and Y."
  (aref (aref tetris-60--board y) x))

(defun tetris-60--set-board-cell (x y value)
  "Set the board VALUE at X and Y."
  (aset (aref tetris-60--board y) x value))

(defun tetris-60--shape-rotations (&optional shape)
  "Return the number of rotations for SHAPE."
  (length (aref tetris-60--shapes (or shape tetris-60--shape))))

(defun tetris-60--shape-cells (&optional shape rotation)
  "Return the cell coordinates for SHAPE and ROTATION."
  (aref (aref tetris-60--shapes (or shape tetris-60--shape))
        (or rotation tetris-60--rotation)))

(defun tetris-60--shape-width (&optional shape)
  "Return the spawn width for SHAPE."
  (aref (aref tetris-60--shape-dimensions (or shape tetris-60--shape)) 0))

(defun tetris-60--level ()
  "Return the display level derived from cleared lines."
  (1+ (/ tetris-60--line-count 10)))

(defun tetris-60--tick-period ()
  "Return the current timer period."
  (let ((period (funcall tetris-60-update-speed-function
                         tetris-60--shape-count
                         tetris-60--line-count)))
    (if (numberp period)
        period
      tetris-60-default-tick-period)))

(defun tetris-60--buffer-x (x)
  "Translate board X to buffer X."
  (+ tetris-60--board-x x))

(defun tetris-60--buffer-y (y)
  "Translate board Y to buffer Y."
  (+ tetris-60--board-y y))

(defun tetris-60--put-string (x y string &optional width)
  "Write STRING at buffer coordinates X and Y.

If WIDTH is non-nil, clear the remainder of the line segment up to WIDTH."
  (let ((limit (or width (length string))))
    (dotimes (index limit)
      (gamegrid-set-cell (+ x index)
                         y
                         (if (< index (length string))
                             (aref string index)
                           ?\s)))))

(defun tetris-60--clear-rect (x y width height)
  "Fill the rectangle at X, Y, WIDTH, HEIGHT with spaces."
  (dotimes (dy height)
    (dotimes (dx width)
      (gamegrid-set-cell (+ x dx) (+ y dy) ?\s))))

(defun tetris-60--draw-frame ()
  "Draw the static ASCII border around the playfield."
  (dotimes (x tetris-60--board-width)
    (gamegrid-set-cell (+ tetris-60--playfield-left 1 x)
                       tetris-60--playfield-top
                       tetris-60--cell-border-h)
    (gamegrid-set-cell (+ tetris-60--playfield-left 1 x)
                       tetris-60--playfield-bottom
                       tetris-60--cell-border-h))
  (dotimes (y tetris-60--board-height)
    (gamegrid-set-cell tetris-60--playfield-left
                       (+ tetris-60--playfield-top 1 y)
                       tetris-60--cell-border-v)
    (gamegrid-set-cell tetris-60--playfield-right
                       (+ tetris-60--playfield-top 1 y)
                       tetris-60--cell-border-v))
  (gamegrid-set-cell tetris-60--playfield-left tetris-60--playfield-top tetris-60--cell-corner)
  (gamegrid-set-cell tetris-60--playfield-right tetris-60--playfield-top tetris-60--cell-corner)
  (gamegrid-set-cell tetris-60--playfield-left tetris-60--playfield-bottom tetris-60--cell-corner)
  (gamegrid-set-cell tetris-60--playfield-right tetris-60--playfield-bottom tetris-60--cell-corner))

(defun tetris-60--render-board ()
  "Render the static board contents and the active piece."
  (dotimes (y tetris-60--board-height)
    (dotimes (x tetris-60--board-width)
      (gamegrid-set-cell (tetris-60--buffer-x x)
                         (tetris-60--buffer-y y)
                         (if (= (tetris-60--board-cell x y) 1)
                             tetris-60--cell-filled
                           tetris-60--cell-empty))))
  (when tetris-60--piece-active
    (dolist (cell (append (tetris-60--current-piece-cells) nil))
      (pcase-let ((`(,x ,y) cell))
        (when (and (>= y 0) (< y tetris-60--board-height))
          (gamegrid-set-cell (tetris-60--buffer-x x)
                             (tetris-60--buffer-y y)
                             tetris-60--cell-filled))))))

(defun tetris-60--render-preview ()
  "Render the next piece preview."
  (dotimes (row 4)
    (dotimes (col 4)
      (gamegrid-set-cell (+ tetris-60--preview-x col)
                         (+ tetris-60--preview-y row)
                         tetris-60--cell-empty)))
  (dolist (cell (append (tetris-60--shape-cells tetris-60--next-shape 0) nil))
    (let ((x (aref cell 0))
          (y (aref cell 1)))
      (when (and (<= 0 x 3) (<= 0 y 3))
        (gamegrid-set-cell (+ tetris-60--preview-x x)
                           (+ tetris-60--preview-y y)
                           tetris-60--cell-filled)))))

(defun tetris-60--render-status ()
  "Render the HUD."
  (tetris-60--put-string tetris-60--hud-x tetris-60--hud-y "NEXT" 20)
  (tetris-60--put-string tetris-60--hud-x 9 (format "SCORE %05d" tetris-60--score) 20)
  (tetris-60--put-string tetris-60--hud-x 10 (format "LINES %05d" tetris-60--line-count) 20)
  (tetris-60--put-string tetris-60--hud-x 11 (format "LEVEL %02d" (tetris-60--level)) 20)
  (if tetris-60-show-controls
      (progn
        (tetris-60--put-string tetris-60--hud-x tetris-60--controls-y "j LEFT   l RIGHT" 24)
        (tetris-60--put-string tetris-60--hud-x (1+ tetris-60--controls-y) "i ROTATE k DROP" 24)
        (tetris-60--put-string tetris-60--hud-x (+ tetris-60--controls-y 2) "SPC HARD DROP" 24)
        (tetris-60--put-string tetris-60--hud-x (+ tetris-60--controls-y 3) "p PAUSE  n NEW" 24)
        (tetris-60--put-string tetris-60--hud-x (+ tetris-60--controls-y 4) "q END GAME" 24))
    (tetris-60--clear-rect tetris-60--hud-x tetris-60--controls-y 24 5))
  (when tetris-60--paused
    (tetris-60--put-string tetris-60--hud-x 18 "PAUSED" 20))
  (unless tetris-60--paused
    (tetris-60--put-string tetris-60--hud-x 18 "" 20)))

(defun tetris-60--render-game-over ()
  "Render the game-over banner."
  (tetris-60--put-string tetris-60--hud-x 19 "GAME OVER" 20)
  (tetris-60--put-string tetris-60--hud-x 20 "n NEW GAME" 20))

(defun tetris-60--render ()
  "Render the full game state."
  (tetris-60--draw-frame)
  (tetris-60--render-board)
  (tetris-60--render-preview)
  (tetris-60--render-status))

(defun tetris-60--random-shape ()
  "Return a random shape index."
  (random (length tetris-60--shapes)))

(defun tetris-60--current-piece-cells (&optional pos-x pos-y rotation)
  "Return current-piece cells translated to POS-X, POS-Y and ROTATION."
  (let ((base-x (or pos-x tetris-60--pos-x))
        (base-y (or pos-y tetris-60--pos-y)))
    (mapcar (lambda (cell)
              (list (+ base-x (aref cell 0))
                    (+ base-y (aref cell 1))))
            (append (tetris-60--shape-cells nil rotation) nil))))

(defun tetris-60--collision-p (&optional pos-x pos-y rotation)
  "Return non-nil if the current piece collides at POS-X, POS-Y and ROTATION."
  (cl-some
   (lambda (cell)
     (pcase-let ((`(,x ,y) cell))
       (or (< x 0)
           (>= x tetris-60--board-width)
           (>= y tetris-60--board-height)
           (and (>= y 0)
                (= (tetris-60--board-cell x y) 1)))))
   (tetris-60--current-piece-cells pos-x pos-y rotation)))

(defun tetris-60--merge-piece ()
  "Merge the active piece into the board."
  (dolist (cell (append (tetris-60--current-piece-cells) nil))
    (pcase-let ((`(,x ,y) cell))
      (when (>= y 0)
        (tetris-60--set-board-cell x y 1)))))

(defun tetris-60--full-row-p (row)
  "Return non-nil if ROW is full."
  (cl-loop for cell across row always (= cell 1)))

(defun tetris-60--clear-full-rows ()
  "Remove all full rows and return the number of cleared rows."
  (let ((rows '())
        (cleared 0))
    (dotimes (y tetris-60--board-height)
      (let ((row (copy-sequence (aref tetris-60--board y))))
        (if (tetris-60--full-row-p row)
            (cl-incf cleared)
          (push row rows))))
    (setq rows (nreverse rows))
    (setq tetris-60--board (make-vector tetris-60--board-height nil))
    (dotimes (index tetris-60--board-height)
      (aset tetris-60--board index
            (if (< index cleared)
                (tetris-60--make-empty-row)
              (copy-sequence (nth (- index cleared) rows)))))
    cleared))

(defun tetris-60--update-timer ()
  "Apply the current speed function to the active timer."
  (when gamegrid-timer
    (gamegrid-set-timer (tetris-60--tick-period))))

(defun tetris-60--shape-score ()
  "Return the score value for the current shape and rotation."
  (aref (aref tetris-60--shape-scores tetris-60--shape) tetris-60--rotation))

(defun tetris-60--spawn-piece ()
  "Activate the next piece and queue another next piece."
  (setq tetris-60--shape tetris-60--next-shape
        tetris-60--rotation 0
        tetris-60--next-shape (tetris-60--random-shape)
        tetris-60--pos-x (/ (- tetris-60--board-width
                               (tetris-60--shape-width))
                            2)
        tetris-60--pos-y 0
        tetris-60--piece-active t)
  (if (tetris-60--collision-p)
      (progn
        (setq tetris-60--piece-active nil)
        (tetris-60-end-game))
    (tetris-60--render)))

(defun tetris-60--lock-piece ()
  "Lock the active piece, update counters, and spawn the next one."
  (tetris-60--merge-piece)
  (cl-incf tetris-60--shape-count)
  (cl-incf tetris-60--score (tetris-60--shape-score))
  (cl-incf tetris-60--line-count (tetris-60--clear-full-rows))
  (tetris-60--update-timer)
  (tetris-60--spawn-piece))

(defun tetris-60--move-piece (dx dy &optional lock-on-hit)
  "Move the active piece by DX and DY.

If LOCK-ON-HIT is non-nil, locking is triggered after a blocked move."
  (let ((new-x (+ tetris-60--pos-x dx))
        (new-y (+ tetris-60--pos-y dy)))
    (if (tetris-60--collision-p new-x new-y)
        (when lock-on-hit
          (tetris-60--lock-piece)
          t)
      (setq tetris-60--pos-x new-x
            tetris-60--pos-y new-y)
      (tetris-60--render)
      t)))

(defun tetris-60--rotate-piece ()
  "Rotate the active piece clockwise."
  (let ((next-rotation (% (1+ tetris-60--rotation)
                          (tetris-60--shape-rotations))))
    (unless (tetris-60--collision-p tetris-60--pos-x tetris-60--pos-y next-rotation)
      (setq tetris-60--rotation next-rotation)
      (tetris-60--render)
      t)))

(defun tetris-60--reset-state ()
  "Reset all game state for a fresh game."
  (setq tetris-60--board (tetris-60--make-empty-board)
        tetris-60--shape 0
        tetris-60--rotation 0
        tetris-60--next-shape (tetris-60--random-shape)
        tetris-60--shape-count 0
        tetris-60--line-count 0
        tetris-60--score 0
        tetris-60--pos-x 0
        tetris-60--pos-y 0
        tetris-60--piece-active nil
        tetris-60--paused nil
        tetris-60--score-recorded nil)
  (tetris-60--render)
  (tetris-60--spawn-piece))

(defun tetris-60--timestamp ()
  "Return the current local timestamp in ISO 8601 format."
  (format-time-string "%Y-%m-%dT%H:%M:%S%:z"))

(defun tetris-60--parse-score-line (line)
  "Parse one score LINE from the score file."
  (pcase-let ((`(,score ,lines ,timestamp)
               (split-string line "\t")))
    (and score lines timestamp
         (list :score (string-to-number score)
               :lines (string-to-number lines)
               :timestamp timestamp))))

(defun tetris-60--format-score-entry (entry)
  "Return a TSV string for score ENTRY."
  (format "%d\t%d\t%s"
          (plist-get entry :score)
          (plist-get entry :lines)
          (plist-get entry :timestamp)))

(defun tetris-60--sort-score-entries (entries)
  "Sort score ENTRIES by score descending."
  (sort entries
        (lambda (left right)
          (or (> (plist-get left :score) (plist-get right :score))
              (and (= (plist-get left :score) (plist-get right :score))
                   (> (plist-get left :lines) (plist-get right :lines)))
              (and (= (plist-get left :score) (plist-get right :score))
                   (= (plist-get left :lines) (plist-get right :lines))
                   (string> (plist-get left :timestamp)
                            (plist-get right :timestamp)))))))

(defun tetris-60--read-score-file (file)
  "Read score entries from FILE."
  (if (not (file-exists-p file))
      nil
    (with-temp-buffer
      (insert-file-contents file)
      (cl-loop for line in (split-string (buffer-string) "\n" t)
               for entry = (tetris-60--parse-score-line line)
               when entry collect entry))))

(defun tetris-60--write-score-file (file entries)
  "Write ENTRIES to FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (dolist (entry entries)
      (insert (tetris-60--format-score-entry entry))
      (insert "\n"))))

(defun tetris-60--record-score ()
  "Persist the current score to `tetris-60-score-file'."
  (unless tetris-60--score-recorded
    (let* ((entry (list :score tetris-60--score
                        :lines tetris-60--line-count
                        :timestamp (tetris-60--timestamp)))
           (entries (tetris-60--sort-score-entries
                     (cons entry (tetris-60--read-score-file tetris-60-score-file)))))
      (setq entries (cl-subseq entries 0 (min (length entries) tetris-60-score-file-length)))
      (tetris-60--write-score-file tetris-60-score-file entries)
      (setq tetris-60--score-recorded t))))

(defun tetris-60--tick (buffer)
  "Advance the game in BUFFER by one tick."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and (not tetris-60--paused)
                 (tetris-60-active-p))
        (tetris-60--move-piece 0 1 t)))))

(defun tetris-60-active-p ()
  "Return non-nil if a `tetris-60' game is active."
  (eq (current-local-map) tetris-60-mode-map))

(defun tetris-60-start-game ()
  "Start a new `tetris-60' game."
  (interactive nil tetris-60-mode)
  (gamegrid-kill-timer)
  (tetris-60--apply-display-table)
  (tetris-60--setup-face)
  (tetris-60--init-buffer)
  (use-local-map tetris-60-mode-map)
  (tetris-60--reset-state)
  (gamegrid-start-timer (tetris-60--tick-period) #'tetris-60--tick))

(defun tetris-60-end-game ()
  "End the current `tetris-60' game."
  (interactive nil tetris-60-mode)
  (gamegrid-kill-timer)
  (use-local-map tetris-60-null-map)
  (tetris-60--record-score)
  (tetris-60--render)
  (tetris-60--render-game-over))

(defun tetris-60-pause-game ()
  "Toggle pause state."
  (interactive nil tetris-60-mode)
  (when (tetris-60-active-p)
    (setq tetris-60--paused (not tetris-60--paused))
    (tetris-60--render)
    (message (if tetris-60--paused
                 "Tetris-60 paused"
               "Tetris-60 resumed"))))

(defun tetris-60-move-left ()
  "Move the active piece one cell left."
  (interactive nil tetris-60-mode)
  (unless tetris-60--paused
    (tetris-60--move-piece -1 0)))

(defun tetris-60-move-right ()
  "Move the active piece one cell right."
  (interactive nil tetris-60-mode)
  (unless tetris-60--paused
    (tetris-60--move-piece 1 0)))

(defun tetris-60-move-down ()
  "Soft-drop the active piece by one row."
  (interactive nil tetris-60-mode)
  (unless tetris-60--paused
    (tetris-60--move-piece 0 1)))

(defun tetris-60-rotate ()
  "Rotate the active piece clockwise."
  (interactive nil tetris-60-mode)
  (unless tetris-60--paused
    (tetris-60--rotate-piece)))

(defun tetris-60-hard-drop ()
  "Drop the active piece to the bottom and lock it."
  (interactive nil tetris-60-mode)
  (unless tetris-60--paused
    (while (tetris-60--move-piece 0 1))
    (tetris-60--lock-piece)))

(put 'tetris-60-mode 'mode-class 'special)

(define-derived-mode tetris-60-mode nil "Tetris-60"
  "Major mode for the `tetris-60' game."
  :interactive nil
  (add-hook 'kill-buffer-hook #'gamegrid-kill-timer nil t)
  (use-local-map tetris-60-null-map)
  (setq-local show-trailing-whitespace nil)
  (setq-local gamegrid-use-glyphs nil)
  (setq-local gamegrid-use-color nil)
  (gamegrid-init (tetris-60--display-options))
  (tetris-60--apply-display-table)
  (tetris-60--setup-face)
  (tetris-60--init-buffer))

;;;###autoload
(defun tetris-60 ()
  "Start playing `tetris-60'."
  (interactive)
  (select-window (or (get-buffer-window tetris-60-buffer-name)
                     (selected-window)))
  (switch-to-buffer tetris-60-buffer-name)
  (gamegrid-kill-timer)
  (tetris-60-mode)
  (tetris-60-start-game))

(provide 'tetris-60)

;;; tetris-60.el ends here
