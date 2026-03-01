(module math
  (import
    ;; Base modules
    (core :all)
    (extra :all)
    (num :all)
    (abs.numeric :all)
    (abs.show :all)

    (data :all))

  (export
    TextBuffer))


(def Vec2 Family [A] Struct [.x A] [.y A])
