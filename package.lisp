(defpackage :chip8
  (:use
    :cl
    :losh
    :iterate
    :cl-arrows
    :chip8.quickutils)
  (:export))


(defpackage :chip8.gui
  (:use :cl+qt :iterate :losh
    :chip8.quickutils))
