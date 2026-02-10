;; ---------------------------------------------------
;; 
;;          Oros.
;; 
;; ---------------------------------------------------

(module oros
  (import
    ;; Base modules
    (core :all)
    (extra :all)
    (num :all)
    (abs.numeric :all)
    (abs.show :all)

    (platform :all)
    (data :all)
    (data.pointer :all)

    (render :all))

   (export main))

(ann new-winsize Proc [(list.List window.Message)] (Maybe (Pair U32 U32)))
(def new-winsize proc [messages] seq
  (if (u64.= 0 messages.len)
      (Maybe (Pair U32 U32)):none
      (match (list.elt (u64.- messages.len 1) messages)
        [[:resize x y]
          ((Maybe (Pair U32 U32)):some (struct (Pair U32 U32) [._1 x] [._2 y]))]
            ;; TODO: add '_' pattern
        [[:key-event a b c]
          (Maybe (Pair U32 U32)):none])))


(ann process-events Proc [(list.List window.Message)] Unit)
(def process-events proc [messages] loop
  [for i from 0 below messages.len]
    (match (list.elt i messages)
      [[:resize x y] :unit]
      [[:key-event key u pressed] :unit]))

;; (def process-events proc [messages] loop
;;   [for i from 0 below messages.len]
;;     (match (list.elt i messages)
;;       [[:resize x y] :unit]
;;       [[:key-event key u pressed] when pressed
;;           (match key
;;             [:backspace seq
;;               (set app.col (- (get app.col) 1))
;;               [let! idx (widen (+ (* (get app.row) 20) (get app.col)) U64)]
;;               (list.eset idx (struct CharCell [.x (get app.col)] [.y (get app.row)] [.index (key-translate :space)] [.pad 0]) app.chars)]
;;             [_ seq
;;               [let! x (get app.col)]
;;               [let! y (get app.row)]
;;               [let! idx (widen (+ (* y 20) x) U64)]
;;                 (list.eset idx (struct CharCell [.x x] [.y y] [.index (key-translate key)] [.pad 0]) app.chars)
;;               (if (u32.= x 19)
;;                 (seq (set app.col 0) (set app.row (+ 1 y)))
;;                 (set app.col (+ 1 x)))])]))


(ann main Proc [] Unit)
(def main proc [] seq
  [let! win window.create-window "Oros" 1080 720]
  [let! renderer (create-renderer win)]

  [let! arena (allocators.make-arena (use memory.current-allocator) 16_384)]
  (bind [memory.temp-allocator (allocators.adapt-arena arena)]
    seq
    
    (loop [while (bool.not (window.should-close win))]
          [for fence-frame = 0 then (u64.mod (u64.+ fence-frame 1) 2)]
    
      (seq 
        (thread.sleep-for (name thread.Seconds 0.03))
        [let! events window.poll-events win]
        [let! winsize new-winsize events]
        (process-events events)
        (hedron.set-buffer-data (list.elt fence-frame renderer.instance-buffers) renderer.instances.data)
        (allocators.reset-arena arena)
    
        (draw-text "this is a very very large test string which keeps going on and on" fence-frame winsize renderer)
        (list.free-list events))))

  (allocators.destroy-arena arena)
  (destroy-renderer renderer)
  (window.destroy-window win))

