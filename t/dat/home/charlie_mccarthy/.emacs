;; This is a template for a special .emacs file that only sets the load-path
;; Some other code will read this in and substitute actual locations for
;; the strings /home/doom/End/Cave/EmacsPerl/Wall/Emacs-Run/t/dat/usr/lib-load-path-munge and /home/doom/End/Cave/EmacsPerl/Wall/Emacs-Run/t/dat/usr/lib-target, and write the new value out to a mock home location.

;; Begin with a fairly minimal load path
(setq load-path (list "/tmp" "/home/doom/End/Cave/EmacsPerl/Wall/Emacs-Run/t/dat/usr/lib-load-path-munge"))

(defvar emacs-run-testorama-unused-lib-1 "/home/doom/End/Cave/EmacsPerl/Wall/Emacs-Run/t/dat/usr/lib-target")

