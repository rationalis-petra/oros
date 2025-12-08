(module element
  (import
    (core :all)
    (extra :all)
    (meta.gen :all)
    (platform :all)  ;; TODO: when support non-all imports, update to platform.memory

    (data :all)
    (data.string :all)
    (data.list :all))

  (export :all))

(def Colour Struct [.r U8] [.g U8] [.b U8] [.a U8])

(def Sizing Enum [:fixed U32] :grow :fit)

(def Size Struct [.x Sizing] [.y Sizing])

(def Style Struct
  [.size Size]
  [.colour Colour])

(def Element Named Element Enum
  [:container Style U32 U32])

;; Ideal layout look:
;; (layout
;;   (text "click me!")
;;   (container style
;;     (loop [for blah in blah])
;;     elt-1
;;     elt-2))
;; 


;; Sample UI Layout - desirable code

;; (def build-layout macro proc [(syntax (list.List Syntax)]
  
;; )
;; (def )

(def Layout (List Element))

(def current-layout dynamic struct Layout
  [.data (num-to-address 0)]
  [.len 0]
  [.capacity 0]
  [.gpa (use memory.current-allocator)])

;(def container-stack dynamic (mk-list {U64} 0 0))

;; (ann begin-box Proc [Style] Unit)
;; (def begin-box proc [style] seq
;;   [let! elt-id ]
;;   (push (:container style 0 0) container-stack)
;;   )

;(ann end-box Proc [Style] Unit)
