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
    (data.pointer :all)

    (math :all))

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

(def TextBufferData Struct
    [.allocator  Allocator]
    [.cursor-pos U64]
    [.gap-begin  U64]
    [.gap-end    U64]
    [.bytes (Ptr (List U8))])

(def TextBuffer Opaque Named TextBuffer Ptr TextBufferData)

(ann make-textbuffer Proc [Allocator] TextBuffer)
(def make-textbuffer proc [alloc] seq
  (bind [memory.current-allocator alloc]
    (into TextBuffer (name TextBuffer
      (new (struct TextBufferData
        [.allocator  alloc]
        [.cursor-pos 0]
        [.gap-begin  0]
        [.gap-end    0]
        [.bytes      (new (list.mk-list 1024 1024))]))))))

(ann insert-char Proc [U32 TextBuffer] Unit)
(def insert-char proc [codepoint bptr] seq
  ;; Step 1: check gap size
  [let! buffer (get (unname (out-of TextBuffer bptr)))]
  [let! gap-size (- buffer.gap-end buffer.gap-begin)]
  (if (u64.> gap-size 4)
    :unit
    :unit))

    ;; if (codepoint < 128) {
    ;;     dest[0] = (uint8_t)codepoint; // downcast is safe, as codepoint < 128
    ;;     *size = 1;
    ;; }
    ;; // Encode with 2 bytes (11 bits)
    ;; // encoded as 110xxxxx 10xxxxxx
    ;; else if (codepoint < 2048) {
    ;;     dest[0] = ((0x7c0 & codepoint) >> 6) | 0xc0;
    ;;     dest[1] = (0x3f & codepoint) | 0x80;
    ;;     *size = 2;
    ;; }
    ;; // Encode with 3 bytes (16 bits)
    ;; // encoded as 1110xxxx 10xxxxxx 10xxxxxx
    ;; else if (codepoint < 65536) {
    ;;     dest[0] = ((0xf000 & codepoint) >> 12) | 0xe0; 
    ;;     dest[1] = ((0xfc0 & codepoint) >> 6) | 0x80;
    ;;     dest[2] = (0x3f & codepoint) | 0x80;
    ;;     *size = 3;
    ;; }
    ;; // Encode with 4 bytes (21 bits)
    ;; // encoded as 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    ;; else {
    ;;     dest[0] = ((0x1c0000 & codepoint) >> 18) | 0xf0;
    ;;     dest[1] = ((0x3f000 & codepoint) >> 12) | 0x80;
    ;;     dest[2] = ((0xfc0 & codepoint) >> 6) | 0x80;
    ;;     dest[3] = (0x3f & codepoint) | 0x80;
    ;;     *size = 4;
    ;; }


(ann insert-string Proc [String TextBuffer] Unit)

(ann move Proc [TextBuffer (Vec2 U64)] Unit)
