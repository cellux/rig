BUILD_DIR := build

.PHONY: all configure rig test clean

all: rig

configure: $(BUILD_DIR)/CMakeCache.txt

$(BUILD_DIR)/CMakeCache.txt: CMakeLists.txt
	cmake -S . -B $(BUILD_DIR)

rig: $(BUILD_DIR)/CMakeCache.txt
	cmake --build $(BUILD_DIR) --target rig

test: rig
	ctest --test-dir $(BUILD_DIR) --output-on-failure --verbose

clean:
	rm -rf $(BUILD_DIR)
