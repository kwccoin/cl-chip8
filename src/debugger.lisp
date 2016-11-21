(in-package :chip8.debugger)
(named-readtables:in-readtable :qtools)
(declaim (optimize (debug 3)))


(defparameter *font* (q+:make-qfont "Menlo" 12))
(defparameter *current-instruction-brush*
  (q+:make-qbrush (q+:make-qcolor 216 162 223)))


;;;; Main GUI -----------------------------------------------------------------
(define-widget debugger (QWidget)
  ((model-disassembly :initarg :model-disassembly)
   (model-registers :initarg :model-registers)
   (model-stack :initarg :model-stack)
   (chip-debugger :initarg :chip-debugger)))

(define-initializer (debugger setup)
  (setf (q+:window-title debugger) "Debugger")
  (q+:resize debugger 580 800))


;;;; Utils --------------------------------------------------------------------
(defun model-index (model row col)
  (q+:index model row col (q+:make-qmodelindex)))


;;;; Disassembler -------------------------------------------------------------
;;;; Code
(defun disassemble-address (chip address)
  (-<> chip
    chip8::chip-memory
    (chip8::instruction-information <> address)))


;;;; Model
(define-widget disassembly-model (QAbstractTableModel)
  ((chip :initarg :chip)
   (current-address :initform 0)))

(defun disassembly-model-update-current-address (model new-address)
  (let* ((old-address (slot-value model 'current-address))
         (old-row (floor old-address 2))
         (new-row (floor new-address 2)))
    (setf (slot-value model 'current-address) new-address)
    (signal! model (data-changed "QModelIndex" "QModelIndex")
             (model-index model old-row 0)
             (model-index model old-row 3))
    (signal! model (data-changed "QModelIndex" "QModelIndex")
             (model-index model new-row 0)
             (model-index model new-row 3))))

(define-override (disassembly-model column-count) (index)
  (declare (ignore index))
  4)

(define-override (disassembly-model row-count) (index)
  (declare (ignore index))
  (ceiling 4096 2))


(defun disassembly-index-valid-p (index)
  (and (q+:is-valid index)
       (< (q+:row index) (ceiling 4096 2))))

(defun get-disassembly-contents (model row col)
  (let ((data (-<> model
                (slot-value <> 'chip)
                (disassemble-address <> (* 2 row))
                (nth col <>))))
    (ecase col
      (0 (format nil "~3,'0X" data))
      (1 (format nil "~4,'0X" data))
      (2 (if data
           (let ((*print-base* 16))
             (format nil "~A ~{~A~^, ~}" (first data) (rest data)))
           ""))
      (3 data))))

(define-override (disassembly-model data) (index role)
  (let ((row (q+:row index))
        (col (q+:column index)))
    (if (not (disassembly-index-valid-p index))
      (q+:make-qvariant)
      (qtenumcase role
        ((q+:qt.display-role)
         (get-disassembly-contents disassembly-model row col))

        ((q+:qt.font-role) *font*)

        ((q+:qt.background-role)
         (if (= row (floor current-address 2))
           *current-instruction-brush*
           (q+:make-qvariant)))

        ((q+:qt.text-alignment-role) (case col
                                       (0 #x0082)
                                       (1 #x0084)
                                       (2 #x0080)
                                       (3 #x0080)))

        (t (q+:make-qvariant))))))

(define-override (disassembly-model header-data) (section orientation role)
  (case role
    (0 (qtenumcase orientation
         ((q+:qt.vertical) (q+:make-qvariant))
         ((q+:qt.horizontal) (case section
                               (0 "Addr")
                               (1 "Inst")
                               (2 "Disassembly")
                               (3 "Bits")))))
    (t (q+:make-qvariant))))


;;;; Layout
(defun disassembly-update-address (model view address)
  (disassembly-model-update-current-address model address)
  (-<> address
    ;; raw address -> row number
    (floor <> 2)
    ;; Give ourselves a bit of breathing room at the top of the table
    (- <> 4)
    (max <> 0)
    ;; get a QModelIndex, because passing a pair of ints would be too easy
    (model-index model <> 0)
    ;; make the debugger show the current line
    (q+:scroll-to view <> (q+:qabstractitemview.position-at-top))))

(define-subwidget (debugger disassembly-table) (q+:make-qtableview debugger)
  (chip8::debugger-add-callback-arrived
    chip-debugger ; bit of a fustercluck here...
    (curry #'disassembly-update-address model-disassembly disassembly-table))
  (q+:set-model disassembly-table model-disassembly)
  (q+:set-show-grid disassembly-table nil)
  (q+:set-column-width disassembly-table 0 40)
  (q+:set-column-width disassembly-table 1 60)
  (q+:set-column-width disassembly-table 2 200)
  (q+:set-column-width disassembly-table 3 90)
  (let ((vheader (q+:vertical-header disassembly-table)))
    (q+:hide vheader)
    (q+:set-resize-mode vheader (q+:qheaderview.fixed))
    (q+:set-default-section-size vheader 14)))


;;;; Register Viewer ----------------------------------------------------------
;;;; Code
(defun registers-label (row)
  (cond
    ((<= row 15) (format nil "V~X" row))
    ((= row 16) "I")
    ((= row 17) "PC")
    ((= row 18) "DT")
    ((= row 19) "ST")))

(defun registers-value (chip row)
  (cond
    ((<= row 15) (format nil "~2,'0X"
                         (aref (chip8::chip-registers chip) row)))
    ((= row 16) (format nil "~4,'0X" (chip8::chip-index chip)))
    ((= row 17) (format nil "~3,'0X" (chip8::chip-program-counter chip)))
    ((= row 18) (format nil "~2,'0X" (chip8::chip-delay-timer chip)))
    ((= row 19) (format nil "~2,'0X" (chip8::chip-sound-timer chip)))))


;;;; Model
(define-widget registers-model (QAbstractTableModel)
  ((chip :initarg :chip)))


(define-override (registers-model column-count) (index)
  (declare (ignore index))
  2)

(define-override (registers-model row-count) (index)
  (declare (ignore index))
  20)


(defun registers-index-valid-p (index)
  (and (q+:is-valid index)
       (< (q+:row index) 20)))

(define-override (registers-model data) (index role)
  (let ((row (q+:row index))
        (col (q+:column index)))
    (if (not (registers-index-valid-p index))
      (q+:make-qvariant)
      (qtenumcase role
        ((q+:qt.display-role)
         (ecase col
           (0 (registers-label row))
           (1 (registers-value chip row))))
        ((q+:qt.text-alignment-role) #x0082)
        ((q+:qt.font-role) *font*)
        (t (q+:make-qvariant))))))

(define-override (registers-model header-data) (section orientation role)
  (declare (ignore section orientation role))
  (q+:make-qvariant))


;;;; Layout
(defun registers-refresh (model view address)
  (declare (ignore view address))
  (signal! model (data-changed "QModelIndex" "QModelIndex")
           (model-index model 0 1)
           (model-index model 18 1)))

(define-subwidget (debugger registers-table) (q+:make-qtableview debugger)
  (chip8::debugger-add-callback-arrived
    chip-debugger
    (curry #'registers-refresh model-registers registers-table))
  (q+:set-model registers-table model-registers)
  (q+:set-show-grid registers-table nil)
  (q+:set-column-width registers-table 0 30)
  (q+:set-column-width registers-table 1 40)
  (let ((vheader (q+:vertical-header registers-table)))
    (q+:hide vheader)
    (q+:set-resize-mode vheader (q+:qheaderview.fixed))
    (q+:set-default-section-size vheader 14))
  (let ((hheader (q+:horizontal-header registers-table)))
    (q+:hide hheader)))


;;;; Stack Viewer -------------------------------------------------------------
;;;; Code
(defun stack-value (chip index)
  (aref (chip8::chip-stack chip) index))

(defun stack-size (chip)
  (length (chip8::chip-stack chip)))


;;;; Model
(define-widget stack-model (QAbstractListModel)
  ((chip :initarg :chip)))

(define-override (stack-model row-count) (index)
  (declare (ignore index))
  (stack-size chip))


(defun stack-index-valid-p (index chip)
  (and (q+:is-valid index)
       (< (q+:row index) (stack-size chip))))

(defun get-stack-contents (chip row)
  (format nil "~3,'0X" (stack-value chip row)))


(define-override (stack-model data) (index role)
  (let ((row (q+:row index)))
    (if (not (stack-index-valid-p index chip))
      (q+:make-qvariant)
      (qtenumcase role
        ((q+:qt.display-role) (get-stack-contents chip row))
        ((q+:qt.font-role) *font*)
        ; ((q+:qt.text-alignment-role) (case col
        ;                                (0 #x0082)
        ;                                (1 #x0084)
        ;                                (2 #x0080)
        ;                                (3 #x0080)))
        (t (q+:make-qvariant))))))


;;;; Layout
(defun stack-refresh (model view address)
  (declare (ignore view address))
  ;; fuck it just refresh everything
  (signal! model (layout-changed)))

(define-subwidget (debugger stack-list) (q+:make-qlistview debugger)
  (chip8::debugger-add-callback-arrived
    chip-debugger
    (curry #'stack-refresh model-stack stack-list))
  (q+:set-model stack-list model-stack))

(define-subwidget (debugger stack-label)
  (q+:make-qlabel "Stack" debugger))



;;;; Main GUI -----------------------------------------------------------------
(define-subwidget (debugger layout) (q+:make-qhboxlayout debugger)
  (let ((disassembly (q+:make-qvboxlayout)))
    (q+:add-widget disassembly disassembly-table)
    (q+:add-layout layout disassembly))
  (let ((values (q+:make-qvboxlayout)))
    (q+:set-fixed-width registers-table 90)
    (q+:set-fixed-width stack-label 90)
    (q+:set-fixed-width stack-list 90)
    (q+:set-maximum-height stack-list 260)
    (q+:add-widget values registers-table)
    (q+:add-widget values stack-label)
    (q+:add-widget values stack-list)
    (q+:add-layout layout values)))


(defun make-debugger (chip)
  (let ((model-disassembly (make-instance 'disassembly-model :chip chip))
        (model-registers (make-instance 'registers-model :chip chip))
        (model-stack (make-instance 'stack-model :chip chip)))
    (make-instance 'debugger
      :model-disassembly model-disassembly
      :model-registers model-registers
      :model-stack model-stack
      :chip-debugger (chip8::chip-debugger chip))))

(defun run (chip)
  (with-main-window (window (make-debugger chip))))


(defparameter *c* (chip8::make-chip))
(chip8::load-rom *c* "roms/breakout.rom")
