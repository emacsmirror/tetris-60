;;; tetris-60-test.el --- Tests for tetris-60 -*- lexical-binding: t; -*-

(require 'ert)

(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name)))))

(require 'tetris-60)

(defmacro tetris-60-test--with-game (&rest body)
  "Create an isolated `tetris-60' buffer and run BODY inside it."
  `(with-temp-buffer
     (tetris-60-mode)
     (setq tetris-60--board (tetris-60--make-empty-board)
           tetris-60--shape 0
           tetris-60--rotation 0
           tetris-60--next-shape 1
           tetris-60--shape-count 0
           tetris-60--line-count 0
           tetris-60--score 0
           tetris-60--pos-x 4
           tetris-60--pos-y 0
           tetris-60--piece-active t
           tetris-60--paused nil
           tetris-60--score-recorded nil)
     ,@body))

(ert-deftest tetris-60-collision-detects-boundaries-and-blocks ()
  (tetris-60-test--with-game
   (should-not (tetris-60--collision-p))
   (should (tetris-60--collision-p -1 0))
   (tetris-60--set-board-cell 4 0 1)
   (should (tetris-60--collision-p))))

(ert-deftest tetris-60-clear-full-rows-shifts-board-down ()
  (tetris-60-test--with-game
   (dotimes (x tetris-60--board-width)
     (tetris-60--set-board-cell x (1- tetris-60--board-height) 1))
   (tetris-60--set-board-cell 0 (- tetris-60--board-height 2) 1)
   (should (= (tetris-60--clear-full-rows) 1))
   (should (= (tetris-60--board-cell 0 (1- tetris-60--board-height)) 1))
   (should (= (tetris-60--board-cell 1 (1- tetris-60--board-height)) 0))
   (should (= (tetris-60--board-cell 0 0) 0))))

(ert-deftest tetris-60-lock-piece-updates-score-and-spawns-next-piece ()
  (tetris-60-test--with-game
   (setq tetris-60--shape 0
         tetris-60--rotation 0
         tetris-60--next-shape 2
         tetris-60--pos-x 4
         tetris-60--pos-y 18)
   (tetris-60--lock-piece)
   (should (= tetris-60--shape-count 1))
   (should (= tetris-60--score 6))
   (should (= (tetris-60--board-cell 4 18) 1))
   (should (= (tetris-60--board-cell 5 19) 1))
   (should (= tetris-60--shape 2))
   (should tetris-60--piece-active)))

(ert-deftest tetris-60-score-file-is-tsv-and-sorted ()
  (let ((score-file (make-temp-file "tetris-60-score"))
        (tetris-60-score-file-length 2))
    (unwind-protect
        (tetris-60-test--with-game
         (tetris-60--write-score-file
          score-file
          (list (list :score 10 :lines 1 :timestamp "2026-03-17T10:00:00+08:00")
                (list :score 50 :lines 3 :timestamp "2026-03-17T10:05:00+08:00")))
         (setq tetris-60-score-file score-file
               tetris-60--score 30
               tetris-60--line-count 2)
         (cl-letf (((symbol-function 'tetris-60--timestamp)
                    (lambda () "2026-03-17T10:10:00+08:00")))
           (tetris-60--record-score))
         (with-temp-buffer
           (insert-file-contents score-file)
           (should (equal (split-string (buffer-string) "\n" t)
                          '("50\t3\t2026-03-17T10:05:00+08:00"
                            "30\t2\t2026-03-17T10:10:00+08:00")))))
      (delete-file score-file))))

(ert-deftest tetris-60-empty-cell-style-affects-display-table ()
  (let ((tetris-60-empty-cell-style 'blank))
    (with-temp-buffer
      (tetris-60-mode)
      (should (equal (aref buffer-display-table tetris-60--cell-empty)
                     (vconcat "  "))))))

(ert-deftest tetris-60-tick-period-respects-custom-speed-function ()
  (let ((tetris-60-update-speed-function (lambda (_shapes lines)
                                           (/ 1.0 (1+ lines)))))
    (tetris-60-test--with-game
     (setq tetris-60--line-count 3)
     (should (= (tetris-60--tick-period) 0.25)))))

;;; tetris-60-test.el ends here
