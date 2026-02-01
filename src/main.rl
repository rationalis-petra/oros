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

    ;; Local modules
    loaders
    (loaders.qoi :only (Pixel)))

   (export main))

(def max-frame-in-flight 2)

(def SyncAcquire Struct
  [.command-buffer hedron.CommandBuffer]
  [.image-available hedron.Semaphore]
  [.in-flight hedron.Fence])

(def SyncSubmit Struct
  [.render-finished hedron.Semaphore])

(def create-sync-acquire proc [pool] struct
  [.command-buffer (hedron.create-command-buffer pool)]
  [.image-available (hedron.create-semaphore)]
  [.in-flight (hedron.create-fence)])

(def destroy-sync-acquire proc [(fdata SyncAcquire)] seq
  (hedron.destroy-semaphore fdata.image-available)
  (hedron.destroy-fence fdata.in-flight))

(def create-acquire-objects proc [pool] 
  (list.list (create-sync-acquire pool) (create-sync-acquire pool)))

(def destroy-sync-submit proc [(sync SyncSubmit)] seq
  (hedron.destroy-semaphore sync.render-finished))

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

(def FontAtlas Struct
  [.image hedron.Image]
  [.image-view hedron.ImageView]
  [.sampler hedron.Sampler])

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
    [.sampler (hedron.create-sampler)]))

(ann destroy-font-atlas Proc [FontAtlas] Unit)
(def destroy-font-atlas proc [font-atlas] seq
  (hedron.destroy-sampler font-atlas.sampler)
  (hedron.destroy-image-view font-atlas.image-view)
  (hedron.destroy-image font-atlas.image))

(def create-texture-layout proc [] seq
  [let! descriptor-bindings (list.list
          (struct hedron.DescriptorBinding
            [.type :combined-image-sampler]
            [.shader-stage :fragment-shader]))]
  [let! descriptor-set (hedron.create-descriptor-set-layout descriptor-bindings)]
  (memory.free descriptor-bindings.data)
  descriptor-set)

(def create-descriptor-pool proc [(number-elements U64)] seq
  [let! elts (narrow number-elements U32)]
  [let! pool-sizes list.list
          (struct hedron.DescriptorPoolSize [.type :combined-image-sampler] [.descriptor-count elts])]
  [let! pool
          (hedron.create-descriptor-pool
            pool-sizes
            elts)]
  (memory.free pool-sizes.data)
  pool)

(def create-descriptor-sets proc [(layouts (list.List hedron.DescriptorSetLayout))
                                  (atlas FontAtlas)
                                  (pool hedron.DescriptorPool)
                                  (num-elements U64)] seq
  [let! descriptor-sets (hedron.alloc-descriptor-sets (narrow num-elements U32) (list.elt 0 layouts) pool)]

  (loop [for i from 0 upto descriptor-sets.len]
    (seq
      [let! copiers (list.list)]
      [let! writers (list.list (struct hedron.DescriptorWrite
        [.info :image-info (struct
           [.sampler atlas.sampler]
           [.image-view atlas.image-view]
           [.image-layout :shader-read-optimal])]
        [.descriptor-type :combined-image-sampler]
        [.descriptor-set (list.elt i descriptor-sets)]))]
      (hedron.update-descriptor-sets writers copiers)
      (memory.free copiers.data)
      (memory.free writers.data)))

  descriptor-sets)

;; -------------------------------------------------------------------
;;
;;             Drawing and related utility functions
;; 
;; -------------------------------------------------------------------

(def Vec2 Struct [.x F32] [.y F32])
(def Vec3 Struct [.x F32] [.y F32] [.z F32])
(def Vertex Struct
  [.pos    Vec2]
  [.colour Vec3]
  [.texture-coord Vec2])

(def DrawData Struct
  [.num-indices U32]
  [.index-buffer hedron.Buffer]
  [.vertex-buffer hedron.Buffer]
  [.pipeline hedron.Pipeline])

(def fdesc proc [enm] match enm [:float-1 "float-1"] [:float-2 "float-2"] [:float-3 "float-3"])



(ann create-graphics-pipeline Proc [hedron.Surface (list.List hedron.DescriptorSetLayout)] hedron.Pipeline)
(def create-graphics-pipeline proc [surface layouts] seq
  [let! ;; shaders 
        shaders list.list (load-shader "build/vert.spv") (load-shader "build/frag.spv")]

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
            [.format :float-3]
            [.offset narrow (offset-of colour Vertex) U32])
            (struct hedron.AttributeDescription
            [.binding 0]
            [.location 2]
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
  (hedron.command-draw-indexed command-buffer dd.num-indices 1 0 0 0)
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


(ann new-winsize Proc [(list.List window.Message)] (Maybe (Pair U32 U32)))
(def new-winsize proc [messages] seq
  (if (u64.= 0 messages.len)
      (Maybe (Pair U32 U32)):none
      (match (list.elt (u64.- messages.len 1) messages)
        [[:resize x y]
            (Maybe (Pair U32 U32)):some (struct (Pair U32 U32) [._1 x] [._2 y])])))

(ann main Proc [] Unit)
(def main proc [] seq
  ;; windowing !
  [let! win window.create-window "My Window" 1080 720]
  [let! surface hedron.create-window-surface win]

  [let! dset-layouts (list.list (create-texture-layout))]
  [let! pipeline (create-graphics-pipeline surface dset-layouts)]
  [let! command-pool (hedron.create-command-pool)]
  [let! acquire-objects create-acquire-objects command-pool]
  [let! num-images widen (hedron.num-swapchain-images surface) U64]
  [let! submit-objects create-sync-submit-objects num-images]

  [let! arena (allocators.make-arena (use memory.current-allocator) 16_384)]
  [let! font-atlas
    (bind [memory.temp-allocator (allocators.adapt-arena arena)]
      (create-font-atlas command-pool))]

  ;; descriptor set stuff
  [let! descriptor-pool create-descriptor-pool num-images] 
  [let! descriptor-sets create-descriptor-sets dset-layouts font-atlas descriptor-pool num-images]

  [let! vertices list.list
          (struct Vertex [.pos           (struct Vec2 [.x -0.5] [.y -0.5])]
                         [.colour        (struct Vec3 [.x 1.0]  [.y 0.0] [.z 0.0])]
                         [.texture-coord (struct Vec2 [.x 0.0]  [.y 0.0])])
          (struct Vertex [.pos           (struct Vec2 [.x 0.5]  [.y -0.5])]
                         [.colour        (struct Vec3 [.x 0.0]  [.y 1.0] [.z 0.0])]
                         [.texture-coord (struct Vec2 [.x 1.0]  [.y 0.0])])
          (struct Vertex [.pos           (struct Vec2 [.x 0.5]  [.y 0.5])]
                         [.colour        (struct Vec3 [.x 0.0]  [.y 0.0] [.z 1.0])]
                         [.texture-coord (struct Vec2 [.x 1.0]  [.y 1.0])])
          (struct Vertex [.pos           (struct Vec2 [.x -0.5] [.y 0.5])]
                         [.colour        (struct Vec3 [.x 0.0]  [.y 0.0] [.z 1.0])]
                         [.texture-coord (struct Vec2 [.x 0.0]  [.y 1.0])])]

  [let! indices is (list.list 0 1 2 2 3 0) (list.List U16)]
   
  [let! vertex-buffer hedron.create-buffer :vertex (* (size-of Vertex) vertices.len)]
  [let! index-buffer hedron.create-buffer :index (* (size-of U16) indices.len)]

  [let! draw-data struct DrawData
                     [.num-indices (narrow indices.len U32)]
                     [.index-buffer index-buffer]
                     [.vertex-buffer vertex-buffer]
                     [.pipeline pipeline]]

  (hedron.set-buffer-data vertex-buffer vertices.data)
  (list.free-list vertices)

  (hedron.set-buffer-data index-buffer indices.data)
  (list.free-list indices)

  (bind [memory.temp-allocator (allocators.adapt-arena arena)]
    (loop [while (bool.not (window.should-close win))]
          [for fence-frame = 0 then (u64.mod (u64.+ fence-frame 1) 2)]

      (seq 
        [let! events window.poll-events win]
        [let! winsize new-winsize events]
        (allocators.reset-arena arena)
    
        (draw-frame (list.elt fence-frame acquire-objects) submit-objects draw-data (list.elt 0 descriptor-sets) surface winsize)
        (list.free-list events))))
  (allocators.destroy-arena arena)
  
  (hedron.wait-for-device)

  (list.each destroy-sync-acquire acquire-objects)
  (list.free-list acquire-objects)

  (list.each destroy-sync-submit submit-objects)
  (list.free-list submit-objects)

  (list.each hedron.destroy-descriptor-set-layout dset-layouts)
  (list.free-list dset-layouts)

  (list.free-list descriptor-sets)

  (hedron.destroy-descriptor-pool descriptor-pool)

  (destroy-font-atlas font-atlas)
  (hedron.destroy-buffer vertex-buffer)
  (hedron.destroy-buffer index-buffer)
  (hedron.destroy-command-pool command-pool)
  (hedron.destroy-pipeline pipeline)
  (hedron.destroy-window-surface surface)
  (window.destroy-window win))

