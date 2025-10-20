CXX := g++
CXXFLAGS := -Wall -Wextra -Wstrict-overflow -Wshadow -Wdouble-promotion -Wundef -Wpointer-arith -Wcast-align -Wcast-qual -Wuninitialized -Wimplicit-fallthrough -pedantic -std=c++11 -O2

TARGET := build/squelch
SRC := src/squelch.cc

# Default target
all: $(TARGET)

# How to build the program
$(TARGET): $(SRC)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $^

.PHONY: ubsan
ubsan: CXXFLAGS += $(UBSAN_FLAGS)
ubsan: LDFLAGS += $(UBSAN_FLAGS)
ubsan: clean $(TARGET)
	@echo "Built with UBSan."

.PHONY: test
test: $(TARGET)
	cd test && perl test.pl

.PHONY: clean
clean:
	rm -rf build