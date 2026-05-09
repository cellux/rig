BUILD_DIR := build

.PHONY: all configure rig clean

all: rig

configure: $(BUILD_DIR)/CMakeCache.txt

$(BUILD_DIR)/CMakeCache.txt: CMakeLists.txt
	cmake -S . -B $(BUILD_DIR)

rig: $(BUILD_DIR)/CMakeCache.txt
	cmake --build $(BUILD_DIR) --target rig

clean:
	rm -rf $(BUILD_DIR)
