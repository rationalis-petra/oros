(module tbuf
  (import
    ;; Base modules
    (core :all)
    (extra :all)
    (num :all)
    (abs.numeric :all)
    (abs.show :all)

    (platform :all)
    (data :all)
    (data.string :only (String))
    (data.pointer :all))

  (export
    TextBuffer))

;; -----------------------------------------------------------------------------
;; Text Buffer
;; -----------------------------------------------------------------------------
;;  Plan:
;; ---------
;; Start with a gap buffer: fastest for smaller buffers, easy
;; to implement.
;; Later, switch to a piece tree or rope, for
;;   - better average costs, as gap buffer can be 'spiky'
;;   - snapshotting/concurrent access (when backed by immutable structures)
;; 
;;  Current Implementation
;; -----------------------------------------------------------------------------
;; The gap buffer is implemented as a singular array of unsigned 8-bit integers,
;;  with a 'gap', e.g. indices 0-4 may contain 'Hello', then indices 4-10 could
;;  be 'blank' or 'gap' space, which is ignored, e.g. when rendering, and finally
;;  indices 11-15 could be 'World'. To delete the letter 'o', at the end of
;;  'Hello', the 'gap' would simply grow to be indices 3-10. To replace this
;;  deleted 'o' with 'ey', the gap would be 'shrunk to take indices 5-10, with 
;;  bytes inserted at appropriate locations in the array.
;;  
;; To move the gap, bytes are simply copied from the end to the beginning (or vice-versa).
;;   This does slow traversal for large files, but should not be an issue for us
;;   for some time

(def TextBuffer Struct
  [])

(def Pos Struct [.row U64] [.col U64])

(ann insert-char Proc [U32 TextBuffer] Unit)
(ann insert-string Proc [String TextBuffer] Unit)
(ann move Proc [TextBuffer Move])
