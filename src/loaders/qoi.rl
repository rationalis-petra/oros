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


(def load-qoi-image proc [(path String)] :unit)
