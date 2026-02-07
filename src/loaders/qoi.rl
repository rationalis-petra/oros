(module qoi

  (import
    (core :all)
    (extra :all)
    (meta.gen :all)
    (platform :all)  ;; TODO: when support non-all imports, update to platform.memory
    (num :all)
    (num.bool :all)
    dev
    debug

    (data :all)
    (data.pointer :all)
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
(def rgb proc [r b g] (struct Pixel [.r r] [.g g] [.b b] [.a 255]))

(def mk-initial-list proc [] seq
  [let! pixels (list.mk-list {Pixel} 64 64)]
  (loop [for i from 0 below 64]
    (list.eset i (struct Pixel [.r 0] [.g 0] [.b 0] [.a 0]) pixels))
  pixels)

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

    ;; See https://qoiformat.org/qoi-specification.pdf
    ;;  for details of the qoi format.

    [let! running (mk-initial-list)]
    [let! prev-pixel (new {Pixel} (rgb 0 0 0))]

    [let! src-pos (new {U64} 0)]
    [let! runleft (new {U8} 0)]

    (loop [for i from 0 below num-pixels]
      (seq
        [let! loc (get src-pos)]
        [let! tag (list.elt loc raw-pixel-data)]

        (cond
          [(u8.> (get runleft) 0) seq
           (list.eset i (get prev-pixel) pixels)
           (set runleft (- (get runleft) 1))]
          ;; Alpha remains unchanged, all new r,g,b values
          [(= tag #b_11111110) seq
            [let! old-pixel (get prev-pixel)]
            [let! new-pixel (struct (get prev-pixel)
              [.r (list.elt (+ loc 1) raw-pixel-data)]
              [.g (list.elt (+ loc 2) raw-pixel-data)]
              [.b (list.elt (+ loc 3) raw-pixel-data)]
              [.a old-pixel.a])]
            (list.eset i new-pixel pixels)
            (set prev-pixel new-pixel)
            (set src-pos (+ loc 4))]
          ;; All values are changed
          [(= tag #b_11111111) seq
            [let! new-pixel (struct Pixel
              [.r (list.elt (+ loc 1) raw-pixel-data)]
              [.g (list.elt (+ loc 2) raw-pixel-data)]
              [.b (list.elt (+ loc 3) raw-pixel-data)]
              [.a (list.elt (+ loc 4) raw-pixel-data)])]
            (list.eset i new-pixel pixels)
            (set prev-pixel new-pixel)
            (set src-pos (+ loc 5))]
          ;; lower 6 bits are an index into the running array
          [(= (u8.shr 6 tag) #b_00) seq
            ;; We know the lower 6 bits are an index into the running array, AND
            ;; that the upper 2 bits are 0, so can just use the value!
            [let! new-pixel (list.elt (widen tag U64) running)]
            (list.eset i new-pixel pixels)
            (set prev-pixel new-pixel)
            (set src-pos (+ loc 1))]
          ;; rgb diff
          ;;[(seq (debug.debug-break) (= (u8.shr 6 tag) #b_01)) seq
          [(= (u8.shr 6 tag) #b_01) seq
            [let! old-pixel (get prev-pixel)]
            [let! new-pixel struct
                [.r (+ old-pixel.r (- (u8.and #b_11 tag) 2))]
                [.g (+ old-pixel.g (- (u8.shr 2 (u8.and #b_1100 tag)) 2))]
                [.b (+ old-pixel.b (- (u8.shr 4 (u8.and #b_110000 tag)) 2))]
                [.a old-pixel.a]]
            (list.eset i new-pixel pixels)
            (set prev-pixel new-pixel)
            (set src-pos (+ loc 1))]
          ;; luma diff
          [(= (u8.shr 6 tag) #b_10) seq
            [let! b2 list.elt (u64.+ 1 loc) raw-pixel-data]
            [let! old-pixel (get prev-pixel)]

            [let! vg (- (u8.and tag #b_111111) 32)]

            [let! new-pixel struct
                [.r (+ old-pixel.r (u8.+ (u8.- vg 8) (u8.and (u8.shr 4 b2) #b_1111)))]
                [.g (+ old-pixel.g vg)]
                [.b (+ old-pixel.b (u8.+ (u8.- vg 8) (u8.and b2 #b_1111)))]
                [.a old-pixel.a]]
            (list.eset i new-pixel pixels)
            (set prev-pixel new-pixel)
            (set src-pos (+ loc 2))
            ;(debug.debug-break)
            ]
          ;; encoded as a run
          [:true seq
            (set runleft (u8.and tag #b_111111))
            (set src-pos (+ loc 1))
            (list.eset i (get prev-pixel) pixels)]) ;* #b_00

        [let! pxl (get prev-pixel)]

        ;; index_position = (r * 3 + g * 5 + b * 7 + a * 11) % 64
        [let! index-pos (u8.mod (u8.+ (u8.* 3 pxl.r) (u8.+ (u8.* 5 pxl.g) (u8.+ (u8.* 7 pxl.b) (u8.* 11 pxl.a)))) 64)]
        (list.eset (u64.mod (widen index-pos U64) 64) pxl running)))

    (terminal.write-string "\n")
    (delete runleft)
    (delete src-pos)
    (delete prev-pixel)
    (list.free-list running)
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

