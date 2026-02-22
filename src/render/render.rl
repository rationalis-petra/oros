
(module render
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

    loaders
    (loaders.qoi :only (Pixel)))

   (export
     Renderer
     create-renderer
     destroy-renderer
     draw-text))

;; -----------------------------------------------------------------------------
;;
;;      Private API
;;
;; -----------------------------------------------------------------------------

(def CharCell Struct
  [.x U32]
  [.y U32]
  [.index U32]
  [.pad U32])

(def FontAtlas Struct
  [.image hedron.Image]
  [.image-view hedron.ImageView]
  [.sampler hedron.Sampler])

(def Vec2 Struct [.x F32] [.y F32])
(def Vec3 Struct [.x F32] [.y F32] [.z F32])
(def Vertex Struct
  [.pos    Vec2]
  [.texture-coord Vec2])

(def DrawData Struct
  [.num-indices U32]
  [.index-buffer hedron.Buffer]
  [.instance-buffers (List hedron.Buffer)]
  [.vertex-buffer hedron.Buffer]
  [.pipeline hedron.Pipeline])


(def SyncAcquire Struct
  [.command-buffer hedron.CommandBuffer]
  [.image-available hedron.Semaphore]
  [.in-flight hedron.Fence])

(def SyncSubmit Struct
  [.render-finished hedron.Semaphore])

(def init-char-instances proc [] seq
  ;; For now, fix a grid size of 10x10
  [let! cols 20]
  [let! rows 20]
  [let! instances list.mk-list {CharCell} 400 400]
  (loop [for i from 0 below 400]
    (let [cell struct CharCell
            ;; layout in row-major order.
            [.x narrow (u64.mod i 20) U32]
            [.y narrow (u64./ i 20) U32]
            ;[.index 30]
            [.index narrow (u64.mod i 27) U32]
            [.pad 0]]
       (list.eset i cell instances)))
  instances)

(def max-frame-in-flight 2)

(def create-sync-acquire proc [pool] struct
  [.command-buffer (hedron.create-command-buffer pool)]
  [.image-available (hedron.create-semaphore)]
  [.in-flight (hedron.create-fence)])

(def destroy-sync-acquire proc [(fdata SyncAcquire)] seq
  (hedron.destroy-semaphore fdata.image-available)
  (hedron.destroy-fence fdata.in-flight))

(ann create-acquire-objects Proc [hedron.CommandPool] (List SyncAcquire))
(def create-acquire-objects proc [pool] 
  (list.list (create-sync-acquire pool) (create-sync-acquire pool)))

(def destroy-sync-submit proc [(sync SyncSubmit)] seq
  (hedron.destroy-semaphore sync.render-finished))

(ann create-sync-submit Proc [] SyncSubmit)
(def create-sync-submit proc [] struct
  [.render-finished (hedron.create-semaphore)])

(def create-sync-submit-objects proc [(number-elements U64)] seq
  [let! sync-objects (list.mk-list number-elements number-elements)]
  (loop [for i from 0 below number-elements]
    (list.eset i (create-sync-submit) sync-objects))
  sync-objects)

(def load-shader proc [filename] seq
  [let! file match (filesystem.open-file filename :read)
               [[:ok file] file]
               [[:error errcode] (panic "failed to open shader file")]]
  [let! chunk filesystem.read-chunk file :none]
  [let! module hedron.create-shader-module chunk]

  (list.free-list chunk)
  (filesystem.close-file file)
  module)

(def create-uniform-buffers proc [(number-elements U64)] seq
  [let! uniform-buffers (list.mk-list number-elements number-elements)]
  (loop [for i from 0 below number-elements]
    (list.eset i (hedron.create-buffer :uniform (u64.* 400 (size-of CharCell))) uniform-buffers))
  uniform-buffers)

(ann create-font-atlas Proc [hedron.CommandPool] FontAtlas)
(def create-font-atlas proc [command-pool] seq
  [let! qoi-image match (loaders.qoi.load-image "resources/fonts/profont-windows.qoi" :rgba)
                [[:ok img] img]
                [[:error code] (panic "failed to load font")]]
  
  [let! staging-buffer hedron.create-buffer :transfer-source (* (size-of Pixel) qoi-image.pixels.len)]
  (hedron.set-buffer-data staging-buffer qoi-image.pixels.data)
  (loaders.qoi.free-image qoi-image)

  [let! hd-image (hedron.create-image qoi-image.width qoi-image.height :r8-g8-b8-a8-srgb)]
  
  ;; Create the command buffer to push data to the image object,
  [let! command-buffer (hedron.create-command-buffer command-pool)]

  (bind [memory.current-allocator (use memory.temp-allocator)]
    seq
    (hedron.command-begin command-buffer :one-time-submit) ;; one-time
    (hedron.command-pipeline-barrier command-buffer :top-of-pipe :transfer
      (list.list) (list.list) 
      (list.list (struct hedron.ImageMemoryBarrier
                   [.old-layout :undefined]
                   [.new-layout :transfer-dest-optimal]
                   [.source-access-mask :none]
                   [.destination-access-mask :transfer-write]
                   [.image hd-image])))
    (hedron.command-copy-buffer-to-image command-buffer staging-buffer hd-image qoi-image.width qoi-image.height)
    (hedron.command-pipeline-barrier command-buffer :transfer :fragment-shader
      (list.list) (list.list)
      (list.list (struct hedron.ImageMemoryBarrier
                   [.old-layout :transfer-dest-optimal]
                   [.new-layout :shader-read-optimal]
                   [.source-access-mask :transfer-write]
                   [.destination-access-mask :shader-read]
                   [.image hd-image])))
    
    (hedron.command-end command-buffer))


  ;; Final bits: submit the command and do cleanup
  (hedron.queue-submit command-buffer :none (list.null-list) (list.null-list))
  (hedron.queue-wait-idle)
  (hedron.free-command-buffer command-pool command-buffer)
  (hedron.destroy-buffer staging-buffer)

  ;; Image View
  [let! hd-image-view (hedron.create-image-view hd-image :r8-g8-b8-a8-srgb)]

  (struct
    [.image hd-image]
    [.image-view hd-image-view]
    [.sampler (hedron.create-sampler :false :nearest :nearest)]))

(ann destroy-font-atlas Proc [FontAtlas] Unit)
(def destroy-font-atlas proc [font-atlas] seq
  (hedron.destroy-sampler font-atlas.sampler)
  (hedron.destroy-image-view font-atlas.image-view)
  (hedron.destroy-image font-atlas.image))

(def create-oros-layouts proc [] seq
  [let! descriptor-bindings (list.list
          (struct hedron.DescriptorBinding
            [.type :combined-image-sampler]
            [.shader-stage :fragment-shader])
          (struct hedron.DescriptorBinding
            [.type :uniform-buffer]
            [.shader-stage :vertex-shader]))]
  [let! descriptor-set-layout (hedron.create-descriptor-set-layout descriptor-bindings)]
  (memory.free descriptor-bindings.data)
  descriptor-set-layout)

(def create-descriptor-pool proc [(number-elements U64)] seq
  [let! elts (narrow number-elements U32)]
  [let! pool-sizes list.list
          (struct hedron.DescriptorPoolSize
            [.type :combined-image-sampler]
            [.descriptor-count elts])
         (struct hedron.DescriptorPoolSize
            [.type :uniform-buffer]
            [.descriptor-count elts])]
  [let! pool
          (hedron.create-descriptor-pool
            pool-sizes
            elts)]
  (memory.free pool-sizes.data)
  pool)

(def create-descriptor-sets proc [(layouts (list.List hedron.DescriptorSetLayout))
                                  (atlas FontAtlas)
                                  (instances (List hedron.Buffer))
                                  (pool hedron.DescriptorPool)
                                  (num-elements U64)] seq
  [let! descriptor-sets (hedron.alloc-descriptor-sets (narrow num-elements U32) (list.elt 0 layouts) pool)]

  (bind [memory.current-allocator (use memory.temp-allocator)]
  (loop [for i from 0 upto descriptor-sets.len]
    (seq
      [let! copiers (list.list)]
      [let! writers (list.list
        (struct hedron.DescriptorWrite
          [.descriptor-type :combined-image-sampler]
          [.descriptor-set (list.elt i descriptor-sets)]
          [.info :image-info
            (list.list
              (struct
               [.sampler atlas.sampler]
               [.image-view atlas.image-view]
               [.image-layout :shader-read-optimal]))])
        (struct hedron.DescriptorWrite
          [.descriptor-type :uniform-buffer]
          [.descriptor-set (list.elt i descriptor-sets)]
          [.info :buffer-info
            (list.list
              (struct
                [.buffer (list.elt i instances)]
                [.offset 0]
                [.range (u32.* 400 (narrow (size-of CharCell) U32))]))]))]

      (hedron.update-descriptor-sets writers copiers))))

  descriptor-sets)

(ann create-graphics-pipeline Proc [hedron.Surface (list.List hedron.DescriptorSetLayout)] hedron.Pipeline)
(def create-graphics-pipeline proc [surface layouts] seq
  [let! ;; shaders 
        shaders list.list (load-shader "build/shaders/text/vert.spv") (load-shader "build/shaders/text/frag.spv")]

  [let! vertex-binding-descriptions list.list
          (struct hedron.BindingDescription
            [.binding 0]
            [.stride narrow (size-of Vertex) U32]
            [.input-rate :vertex])]

  [let! vertex-attribute-descriptions list.list
          (struct hedron.AttributeDescription
            [.binding 0]
            [.location 0]
            [.format :float-2]
            [.offset narrow (offset-of pos Vertex) U32])
          (struct hedron.AttributeDescription
            [.binding 0]
            [.location 1]
            [.format :float-2]
            [.offset narrow (offset-of texture-coord Vertex) U32])]

  [let! pipeline
    hedron.create-pipeline
      layouts
      vertex-binding-descriptions
      vertex-attribute-descriptions
      shaders
      surface]

  (list.each hedron.destroy-shader-module shaders)
  (list.free-list vertex-binding-descriptions)
  (list.free-list vertex-attribute-descriptions)
  (list.free-list shaders)
  pipeline)

(ann record-command Proc [hedron.CommandBuffer DrawData hedron.DescriptorSet hedron.Surface U32] Unit)
(def record-command proc [command-buffer dd descriptor-set surface next-image] seq
  (hedron.command-begin command-buffer :none)
  (hedron.command-begin-renderpass command-buffer surface next-image)
  (hedron.command-bind-pipeline command-buffer dd.pipeline)
  (hedron.command-set-surface command-buffer surface)
  (hedron.command-bind-vertex-buffer command-buffer dd.vertex-buffer)
  (hedron.command-bind-index-buffer command-buffer dd.index-buffer :u16)
  (hedron.command-bind-descriptor-set command-buffer dd.pipeline descriptor-set)

  (hedron.command-draw-indexed command-buffer dd.num-indices 400 0 0 0)
  (hedron.command-end-renderpass command-buffer)
  (hedron.command-end command-buffer))

(ann draw-frame Proc [SyncAcquire (list.List SyncSubmit) DrawData hedron.DescriptorSet hedron.Surface (Maybe (Pair U32 U32))] Unit)
(def draw-frame proc [acquire submit draw-data descriptor-set surface (resize (Maybe (Pair U32 U32)))] seq
  (hedron.wait-for-fence acquire.in-flight)

  (match resize
    [[:some extent] seq
      (hedron.resize-window-surface surface extent)]
    [:none seq
      [let! imres (hedron.acquire-next-image surface acquire.image-available)]

      (match imres
        [[:image next-image] seq
          [let! syn (list.elt (widen next-image U64) submit)] ;; bug here??
          
          (hedron.reset-fence acquire.in-flight)
          (hedron.reset-command-buffer acquire.command-buffer)
            
          ;; The actual drawing
          (record-command acquire.command-buffer draw-data descriptor-set surface next-image)
            
          (bind [memory.current-allocator (use memory.temp-allocator)]
            (hedron.queue-submit
              acquire.command-buffer
              (:some acquire.in-flight)
              (list.list (pair.pair acquire.image-available :colour-attachment))
              (list.list syn.render-finished)))

          (hedron.queue-present surface syn.render-finished next-image)]
        [:resized :unit])]))


;; -----------------------------------------------------------------------------
;;
;;      Public API
;;
;; -----------------------------------------------------------------------------

(def Renderer Opaque Struct
  [.surface hedron.Surface]
  [.dset-layouts List hedron.DescriptorSetLayout]
  [.pipeline hedron.Pipeline]
  [.command-pool hedron.CommandPool]
  [.acquire-objects List SyncAcquire]
  [.num-images U64]
  [.submit-objects List SyncSubmit]
  [.font-atlas FontAtlas]
  [.vertex-buffer hedron.Buffer]
  [.index-buffer hedron.Buffer]
  [.instance-buffers List hedron.Buffer]
  [.descriptor-pool hedron.DescriptorPool]
  [.descriptor-sets List hedron.DescriptorSet]
  [.draw-data DrawData]
  [.instances List CharCell])

(ann create-renderer Proc [window.Window] Renderer)
(def create-renderer proc [win] seq
  [let! arena (allocators.make-arena (use memory.current-allocator) 16_384)]
  [let! renderer
    (bind [memory.temp-allocator (allocators.adapt-arena arena)]
      seq
      [let! surface hedron.create-window-surface win]
      
      [let! dset-layouts (list.list (create-oros-layouts))]
      [let! pipeline (create-graphics-pipeline surface dset-layouts)]
      [let! command-pool (hedron.create-command-pool)]
      [let! acquire-objects create-acquire-objects command-pool]
      [let! num-images widen (hedron.num-swapchain-images surface) U64]
      [let! submit-objects create-sync-submit-objects num-images]
      
      [let! font-atlas (create-font-atlas command-pool)]
      
      ;; Square!
      [let! vertices list.list
              (struct Vertex [.pos           (struct Vec2 [.x -1.0] [.y -1.0])]
                             [.texture-coord (struct Vec2 [.x 0.0]  [.y 0.0])])
              (struct Vertex [.pos           (struct Vec2 [.x 1.0]  [.y -1.0])]
                             [.texture-coord (struct Vec2 [.x 1.0]  [.y 0.0])])
              (struct Vertex [.pos           (struct Vec2 [.x 1.0]  [.y 1.0])]
                             [.texture-coord (struct Vec2 [.x 1.0]  [.y 1.0])])
              (struct Vertex [.pos           (struct Vec2 [.x -1.0] [.y 1.0])]
                             [.texture-coord (struct Vec2 [.x 0.0]  [.y 1.0])])]
      
      [let! indices is (list.list 0 1 2 2 3 0) (list.List U16)]
       
      [let! vertex-buffer hedron.create-buffer :vertex (* (size-of Vertex) vertices.len)]
      [let! instance-buffers create-uniform-buffers num-images]
      [let! index-buffer hedron.create-buffer :index (* (size-of U16) indices.len)]

      [let! instances (init-char-instances)]
      (loop [for i from 0 below instance-buffers.len]
       (hedron.set-buffer-data (list.elt i instance-buffers) instances.data))
      
      ;; descriptor set stuff
      [let! descriptor-pool create-descriptor-pool num-images] 
      [let! descriptor-sets create-descriptor-sets dset-layouts font-atlas instance-buffers descriptor-pool num-images]
      
      [let! draw-data struct DrawData
                         [.num-indices (narrow indices.len U32)]
                         [.index-buffer index-buffer]
                         [.instance-buffers instance-buffers]
                         [.vertex-buffer vertex-buffer]
                         [.pipeline pipeline]]
      
      (hedron.set-buffer-data vertex-buffer vertices.data)
      (list.free-list vertices)
      
      (hedron.set-buffer-data index-buffer indices.data)
      (list.free-list indices)

      (struct Renderer 
        [.surface surface]
        [.dset-layouts dset-layouts]
        [.pipeline pipeline]
        [.command-pool command-pool]
        [.acquire-objects acquire-objects]
        [.num-images num-images]
        [.submit-objects submit-objects]
        [.font-atlas font-atlas]
        [.vertex-buffer vertex-buffer]
        [.index-buffer index-buffer]
        [.instance-buffers instance-buffers]
        [.descriptor-pool descriptor-pool]
        [.descriptor-sets descriptor-sets]
        [.draw-data draw-data]
        [.instances instances]))]

  (allocators.destroy-arena arena)

  renderer)

(ann destroy-renderer Proc [Renderer] Unit)
(def destroy-renderer proc [state] seq
  (hedron.wait-for-device)

  (list.free-list state.instances)
  
  (list.each destroy-sync-acquire state.acquire-objects)
  (list.free-list state.acquire-objects)
  
  (list.each destroy-sync-submit state.submit-objects)
  (list.free-list state.submit-objects)
  
  (list.each hedron.destroy-descriptor-set-layout state.dset-layouts)
  (list.free-list state.dset-layouts)
  
  (list.free-list state.descriptor-sets)
  
  (hedron.destroy-descriptor-pool state.descriptor-pool)
  
  (list.each hedron.destroy-buffer state.instance-buffers)
  (list.free-list state.instance-buffers)
  (destroy-font-atlas state.font-atlas)

  (hedron.destroy-buffer state.vertex-buffer)
  (hedron.destroy-buffer state.index-buffer)
  (hedron.destroy-command-pool state.command-pool)
  (hedron.destroy-pipeline state.pipeline)
  (hedron.destroy-window-surface state.surface))

;; (ann ascii-table List U32)
;; (def ascii-table
;;   ;;(bind [memory.current-allocator (use memory.comptime-allocator)]
;;   (list.list ))
;;   ;)

(ann char-translate Proc [U8] U32)
(def char-translate proc [char] ;; (list.elt (widen char U64) ascii-table))
  cond 

    [(u8.= 33 char)  76] ;; !
    [(u8.= 40 char)  74] ;; (
    [(u8.= 41 char)  80] ;; )
    [(u8.= 44 char)  72] ;; ,
    [(u8.= 45 char)  87] ;; -
    [(u8.= 46 char)  70] ;; .

    ;; numbers 0-0
    [(u8.= 48 char)  60]
    [(u8.= 49 char)  61]
    [(u8.= 50 char)  62]
    [(u8.= 51 char)  63]
    [(u8.= 52 char)  64]
    [(u8.= 53 char)  65]
    [(u8.= 54 char)  66]
    [(u8.= 55 char)  67]
    [(u8.= 56 char)  68]
    [(u8.= 57 char)  69]

    [(u8.= 59 char)  73] ;; semicolon
    [(u8.= 63 char)  75] ;; ?

    ;; Capitals
    [(u8.= 65 char) 30]
    [(u8.= 66 char) 31]
    [(u8.= 67 char) 32]
    [(u8.= 68 char) 33]
    [(u8.= 69 char) 34]
    [(u8.= 70 char) 35]
    [(u8.= 71 char) 36]
    [(u8.= 72 char) 37]
    [(u8.= 73 char) 38]
    [(u8.= 74 char) 39]
    [(u8.= 75 char) 40]
    [(u8.= 76 char) 41]
    [(u8.= 77 char) 42]
    [(u8.= 78 char) 43]
    [(u8.= 79 char) 44]
    [(u8.= 80 char) 45]
    [(u8.= 81 char) 46]
    [(u8.= 82 char) 47]
    [(u8.= 83 char) 48]
    [(u8.= 84 char) 49]
    [(u8.= 85 char) 50]
    [(u8.= 86 char) 51]
    [(u8.= 87 char) 52]
    [(u8.= 88 char) 53]
    [(u8.= 89 char) 54]
    [(u8.= 90 char) 55]

    ;; lowercase
    [(u8.=  97 char)  0]
    [(u8.=  98 char)  1]
    [(u8.=  99 char)  2]
    [(u8.= 100 char)  3]
    [(u8.= 101 char)  4]
    [(u8.= 102 char)  5]
    [(u8.= 103 char)  6]
    [(u8.= 104 char)  7]
    [(u8.= 105 char)  8]
    [(u8.= 106 char)  9]
    [(u8.= 107 char) 10]
    [(u8.= 108 char) 11]
    [(u8.= 109 char) 12]
    [(u8.= 110 char) 13]
    [(u8.= 111 char) 14]
    [(u8.= 112 char) 15]
    [(u8.= 113 char) 16]
    [(u8.= 114 char) 17]
    [(u8.= 115 char) 18]
    [(u8.= 116 char) 19]
    [(u8.= 117 char) 20]
    [(u8.= 118 char) 21]
    [(u8.= 119 char) 22]
    [(u8.= 120 char) 23]
    [(u8.= 121 char) 24]
    [(u8.= 122 char) 25]
    [:true 27])

(ann set-char-instances Proc [(List (List U8)) (List CharCell)] Unit)
(def set-char-instances proc [text instances] seq
  ;; For now, fix a grid size of 10x10
  [let! cols 20]
  [let! rows 20]
  (loop [for i from 0 below 400]
     
    (let [inner-list (list.elt (u64./ i 20) text)]
         [cell struct CharCell
            ;; layout in row-major order.
            [.x narrow (u64.mod i 20) U32]
            [.y narrow (u64./ i 20) U32]

            ;; translate text if there's more string...
            [.index (char-translate (list.elt (u64.mod i 20) inner-list))]
            [.pad 0]]
       (list.eset i cell instances))))

(def write-char-instances proc [(instances (List CharCell))] seq
  ;; For now, fix a grid size of 10x10
  (loop [for i from 0 below 400]
    (seq 
      [let! cell (list.elt i instances)]
      (terminal.write-string "cell: ")
      (terminal.write-string (to-string cell.x))
      (terminal.write-string ",")
      (terminal.write-string (to-string cell.y))
      (terminal.write-string " - ")
      (terminal.write-string (to-string cell.index))
      (terminal.write-string "\n"))))

(ann draw-text Proc [(List (List U8)) U64 (Maybe (Pair U32 U32)) Renderer] Unit)
(def draw-text proc [text fence-frame winsize state] 
  (bind [memory.current-allocator (use memory.temp-allocator)] seq
    (set-char-instances text state.instances)
    ;; (terminal.write-string "\n\n --------------------------------------------- \n")
    ;; (write-char-instances state.instances)
    ;; (terminal.write-string "\n\n --------------------------------------------- \n")
    (hedron.set-buffer-data (list.elt fence-frame state.instance-buffers) state.instances.data)
    (draw-frame (list.elt fence-frame state.acquire-objects)
                state.submit-objects
                state.draw-data
                (list.elt 0 state.descriptor-sets)
                state.surface
                winsize)))

