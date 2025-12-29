(module qoi
  (import
    (core :all)
    (extra :all)
    (meta.gen :all)
    (platform :all)  ;; TODO: when support non-all imports, update to platform.memory
    (num :all)
    (num.bool :all)

    (data :all)
    (data.result :all)
    (data.list   :only (List))
    (data.string :only (String))

    (abs.numeric :all)
    (abs.order :all)
    (abs.show :all))

  (export
    ImageFormat
    Image
    QoiError
    LoaderError
    Pixel
    load-image))


(def ImageFormat Named ImageFormat Enum
  :rgba)

(def Pixel Struct
  [.r U8]
  [.g U8]
  [.b U8]
  [.a U8])

(def Image Named Image Struct
  [.pixels (List Pixel)]
  [.width  U32]
  [.height U32]
  [.format ImageFormat])

(def QoiError Named QoiError Enum
  :invalid-header)

(def LoaderError Named LoaderError Enum 
  [:file-error filesystem.FileError])

(def QoiHeader Struct packed
  ;; TODO: add support for inline arrays, then change this to
  ;; .mag [Array 8 U8] (different type for static vs dynamic?)
  [.mag1 U8]
  [.mag2 U8]
  [.mag3 U8]
  [.mag4 U8]

  [.width  U32]
  [.height U32]
  [.channels     U8]
  [.colour-space U8])


(ann rgb Proc [U8 U8 U8] Pixel)
(def rgb proc [r b g] (struct Pixel [.r r] [.g g] [.b b] [.a 0]))

(ann load-image Proc [String ImageFormat] (Result Image LoaderError))
(def load-image proc [path format] match (filesystem.open-file path :read)
  [[:ok file] seq
    ;; QOI has a 14-byte header, so try load 14 bytes from the file as a new chunk
    [let! header-bytes (filesystem.read-chunk file (:some 14))]
    ;; TODO: report 'nicely'
    (when (!= header-bytes.len 14) (panic "Unable to load qoi header!"))
    [let! qoi-header (load {QoiHeader} header-bytes.data)]
    (list.free-list header-bytes)
    (when (not (-> (= qoi-header.mag1 (narrow #q U8))
                 (and (= qoi-header.mag2 (narrow #o U8)))
                 (and (= qoi-header.mag3 (narrow #i U8)))
                 (and (= qoi-header.mag4 (narrow #f U8)))))
      (panic "QOI header lacks magic bytes 'qoif'"))

    [let! raw-pixel-data (filesystem.read-chunk file :none)]
    ;; TODO: replace 'byte-swap' with 'to-platform-endianness'
    [let! width (u32.byte-swap qoi-header.width)]
    [let! height (u32.byte-swap qoi-header.height)]

    [let! num-pixels (widen (* width height) U64)]

    [let! pixels (list.mk-list {Pixel} num-pixels num-pixels)]

    (loop [for i from 0 below num-pixels]
      (list.eset i (rgb 100 100 100) pixels))

    (list.free-list raw-pixel-data)
    (filesystem.close-file file)

    (:ok (struct Image
      [.pixels pixels]
      [.width width]
      [.height height]
      [.format :rgba]))]
  [[:error code] (:error (:file-error code))])
  

(ann free-image Proc [Image] Unit)
(def free-image proc [image] (list.free-list image.pixels))
