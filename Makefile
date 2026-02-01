
.SILENT:

BUILD_DIR := ./build

.PHOHY: shaders

frag.spv: resources/shaders/shader.frag
	mkdir -p $(BUILD_DIR)
	glslc ./resources/shaders/shader.frag -o ./build/frag.spv

vert.spv: resources/shaders/shader.vert
	mkdir -p $(BUILD_DIR)
	glslc ./resources/shaders/shader.vert -o ./build/vert.spv

shaders: frag.spv vert.spv

.PHONY: run

run: shaders
	relic atlas run oros

