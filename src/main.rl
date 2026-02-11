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

(def AppState Struct
  [.x (Ptr U64)]
  [.y (Ptr U64)]
  [.text Ptr (List (List U8))])

(ann create-app Proc [] AppState)
(def create-app proc [] seq
  [let! text new (list.mk-list {(List U8)} 20 20)]
  (loop [for i from 0 below 20]
    (seq
      [let! inner-list (list.mk-list {U8} 20 20)]
      (loop [for j from 0 below 20]
        (list.eset j 0 inner-list))
      (list.eset i inner-list (get text))))
  (struct
    [.x (new 0)]
    [.y (new 0)]
    [.text text]))

;; TODO: If adding a second annotation, which is different, seems to cause
;;       memory leak in language?
;; (ann create-app Proc [AppState] Unit)

(ann destroy-app Proc [AppState] Unit)
(def destroy-app proc [(app AppState)] seq
  ;; TODO: add ability to create local closure around A, 
  ;; converting free-list from  All [A] Proc [(List A)] Unit to Proc [List U8] Unit
  ;; (list.each list.free-list (get app.text))
  ;; TODO: uncomment out the above to get memory leak :(
  [let! text (get app.text)]

  (loop [for i from 0 below text.len]
    (list.free-list (list.elt i text)))
  (list.free-list (get app.text))
  (delete app.text)
  (delete app.x)
  (delete app.y))

(ann key-to-ascii Proc [window.Key] U8)
(def key-to-ascii proc [key] match key
    [:a 97]
    [:b 98]
    [:c 99]
    [:d 100]
    [:e 101]
    [:f 102]
    [:g 103]
    [:h 104] 
    [:i 105] 
    [:j 106] 
    [:k 107] 
    [:l 108] 
    [:m 109] 
    [:n 110] 
    [:o 111] 
    [:p 112] 
    [:q 113] 
    [:r 114] 
    [:s 115] 
    [:t 116] 
    [:u 117] 
    [:v 118] 
    [:w 119] 
    [:x 120] 
    [:y 121] 
    [:z 122] 

    [:one   49]
    [:two   50]
    [:three 51]
    [:four  52]
    [:five  53]
    [:six   54]
    [:seven 55]
    [:eight 56]
    [:nine  57]
    [:zero  48]

    [:exclamation 33]
    [:at          64]
    [:hash        23]
    [:dollar      36]
    [:percent     37]
    [:caret       94]
    [:ampersand   38]
    [:asterisk    42]
    [:lparen      40] 
    [:rparen      41]
    [:minus       35]
    [:plus        43]

    [:lbrace    91]
    [:rbrace    93]
    [:colon     58]
    [:semicolon 59]
    [:comma     44]
    [:dot       46]
    [:query     63]

    [:space 32]

    ;; Control characters...
    [_ 0])



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




(ann process-events Proc [(list.List window.Message) AppState] Unit)
(def process-events proc [messages (app AppState)] loop
  [for i from 0 below messages.len]
    (match (list.elt i messages)
      [[:resize x y] :unit]
      [[:key-event key u pressed] when pressed
          (match key
            [:enter seq
              (set app.y (+ (get app.y) 1))
              (set app.x 0)]
            [:backspace seq
              (set app.x (- (get app.x) 1))
              [let! inner-list (list.elt (get app.y) (get app.text))]
              (list.eset (get app.x) (key-to-ascii :space) inner-list)]
            [_ seq
              [let! x (get app.x)]
              [let! y (get app.y)]
              [let! inner-list (list.elt y (get app.text))]
              (list.eset x (key-to-ascii key) inner-list)
              (if (u64.= x 19)
                (seq (set app.x 0) (set app.y (+ 1 y)))
                (set app.x (+ 1 x)))])]))


(ann main Proc [] Unit)
(def main proc [] seq
  [let! win window.create-window "Oros" 1080 720]
  [let! renderer (create-renderer win)]

  [let! arena (allocators.make-arena (use memory.current-allocator) 16_384)]
  [let! app (create-app)]
  (bind [memory.temp-allocator (allocators.adapt-arena arena)] seq
    
    (loop [while (bool.not (window.should-close win))]
          [for fence-frame = 0 then (u64.mod (u64.+ fence-frame 1) 2)]
    
      (seq 
        (thread.sleep-for (name thread.Seconds 0.03))
        [let! events window.poll-events win]
        [let! winsize new-winsize events]
        (process-events events app)
        (hedron.set-buffer-data (list.elt fence-frame renderer.instance-buffers) renderer.instances.data)
        (allocators.reset-arena arena)
    
        (draw-text (get app.text) fence-frame winsize renderer)
        (list.free-list events))))

  (destroy-app app)
  (allocators.destroy-arena arena)
  (destroy-renderer renderer)
  (window.destroy-window win))

