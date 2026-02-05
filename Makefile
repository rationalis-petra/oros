
.SILENT:

BUILD_DIR := ./build
SHADER_DIR := ./build/shaders

.PHOHY: shaders

./build/shaders/text/vert.spv: resources/shaders/text/text.vert
	mkdir -p $(BUILD_DIR)
	mkdir -p $(SHADER_DIR)
	mkdir -p ./build/shaders/text
	glslc ./resources/shaders/text/text.vert -o ./build/shaders/text/vert.spv

./build/shaders/text/frag.spv: resources/shaders/text/text.frag
	mkdir -p $(BUILD_DIR)
	mkdir -p $(SHADER_DIR)
	mkdir -p ./build/shaders/text
	glslc ./resources/shaders/text/text.frag -o ./build/shaders/text/frag.spv

./build/shaders/vert.spv: resources/shaders/shader.vert
	mkdir -p $(BUILD_DIR)
	mkdir -p $(SHADER_DIR)
	glslc ./resources/shaders/shader.vert -o ./build/shaders/vert.spv

./build/shaders/frag.spv: resources/shaders/shader.frag
	mkdir -p $(BUILD_DIR)
	mkdir -p $(SHADER_DIR)
	glslc ./resources/shaders/shader.frag -o ./build/shaders/frag.spv

shaders: ./build/shaders/frag.spv ./build/shaders/vert.spv ./build/shaders/text/vert.spv ./build/shaders/text/frag.spv

.PHONY: run

run: shaders
	relic atlas run oros

