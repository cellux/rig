BUILD_DIR := build
TARGET := rig

.PHONY: all configure clean

all: $(TARGET)

configure: $(BUILD_DIR)/CMakeCache.txt

$(BUILD_DIR)/CMakeCache.txt: CMakeLists.txt
	cmake -S . -B $(BUILD_DIR)

$(TARGET): $(BUILD_DIR)/CMakeCache.txt
	cmake --build $(BUILD_DIR) --target $(TARGET)

clean:
	rm -rf $(BUILD_DIR)
