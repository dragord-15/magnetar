CC=gcc
CFLAGS=-Wall -Wextra -std=gnu11 -O2 -I./src
LDFLAGS=-lm

# Frontend source files
FRONTEND_SRC = src/main.c \
      src/lexer/lexer.c \
      src/parser/parser.c \
      src/semantic/symbols.c \
      src/semantic/types.c \
      src/ir/ir.c \
      src/ir/ir_builder.c \
      src/ir/ir_optimizer.c \
      src/utils/arena.c \
      src/utils/hashmap.c \
      src/utils/job_scheduler.c \
      src/utils/diagnostics.c \
      src/runtime/gc.c \
      src/runtime/memory.c

# Backend source files
BACKEND_SRC = src/backend/backend.c \
      src/backend/elf_writer.c \
      src/backend/pe_writer.c \
      src/backend/asm_writer.c \
      src/backend/bin_writer.c \
      src/backend/x86_64/backend.c \
      src/backend/x86_64/codegen.c \
      src/backend/x86_64/encoder.c \
      src/backend/arm64/backend.c \
      src/backend/arm64/codegen.c \
      src/backend/arm64/encoder.c \
      src/backend/arm64/stubs.c \
      src/backend/arm64/a64.c \
      src/backend/riscv/backend.c

# All source files for magc
SRC = $(FRONTEND_SRC) $(BACKEND_SRC)

# Convert .c to .o
OBJS = $(SRC:.c=.o)
TARGET = magc

# ── Main target ──
all: clean $(TARGET) mag
	@echo "✅ Magnetar Compiler & Linker built successfully!"
	@echo "Run: ./magc <source.mg> [-c] [-o output] [--target arch]"
	@echo "Run: ./mag <obj1.o> <obj2.o> ... -o <output> [--target arch]"
	@echo "Targets: native default (arm64 on ARM, x86_64 otherwise), arm64, x86_64, riscv (placeholder)"

# ── Link compiler ──
$(TARGET): $(OBJS)
	@echo "🔗 Linking magnetar compiler..."
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS)
	@echo "✅ Done!"

# Objects the mag linker needs from the frontend (codegen references semantic symbols)
MAG_FRONTEND_OBJS = src/lexer/lexer.o src/parser/parser.o src/semantic/symbols.o \
      src/semantic/types.o src/ir/ir.o src/ir/ir_builder.o src/ir/ir_optimizer.o \
      src/utils/arena.o src/utils/hashmap.o src/utils/diagnostics.o \
      src/runtime/gc.o src/runtime/memory.o

# ── Link custom linker ──
MAG_BACKEND_OBJS = src/backend/backend.o src/backend/elf_writer.o src/backend/pe_writer.o \
      src/backend/x86_64/backend.o src/backend/x86_64/codegen.o src/backend/x86_64/encoder.o \
      src/backend/arm64/backend.o src/backend/arm64/codegen.o \
      src/backend/arm64/encoder.o src/backend/arm64/stubs.o src/backend/arm64/a64.o src/backend/riscv/backend.o
mag: src/mag.o $(MAG_BACKEND_OBJS) $(MAG_FRONTEND_OBJS)
	@echo "🔗 Linking custom linker mag..."
	$(CC) $(CFLAGS) -o $@ src/mag.o $(MAG_BACKEND_OBJS) $(MAG_FRONTEND_OBJS) $(LDFLAGS)
	@echo "✅ Done!"

# ── Compile each .c to .o ──
src/%.o: src/%.c
	@echo "🔨 Compiling $<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/lexer/%.o: src/lexer/%.c
	@echo "🔨 Compiling lexer/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/parser/%.o: src/parser/%.c
	@echo "🔨 Compiling parser/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/semantic/%.o: src/semantic/%.c
	@echo "🔨 Compiling semantic/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/ir/%.o: src/ir/%.c
	@echo "🔨 Compiling ir/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/utils/%.o: src/utils/%.c
	@echo "🔨 Compiling utils/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/codegen/%.o: src/codegen/%.c
	@echo "🔨 Compiling codegen/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/runtime/%.o: src/runtime/%.c
	@echo "🔨 Compiling runtime/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/backend/%.o: src/backend/%.c
	@echo "🔨 Compiling backend/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/backend/x86_64/%.o: src/backend/x86_64/%.c
	@echo "🔨 Compiling backend/x86_64/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/backend/arm64/%.o: src/backend/arm64/%.c
	@echo "🔨 Compiling backend/arm64/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

src/backend/riscv/%.o: src/backend/riscv/%.c
	@echo "🔨 Compiling backend/riscv/$<..."
	$(CC) $(CFLAGS) -c $< -o $@

# ── Clean ──
clean:
	@echo "🧹 Cleaning..."
	@rm -f src/main.o src/mag.o
	@rm -f src/lexer/*.o
	@rm -f src/parser/*.o
	@rm -f src/semantic/*.o
	@rm -f src/ir/*.o
	@rm -f src/utils/*.o
	@rm -f src/codegen/*.o
	@rm -f src/runtime/*.o
	@rm -f src/backend/*.o
	@rm -f src/backend/x86_64/*.o
	@rm -f src/backend/arm64/*.o
	@rm -f src/backend/riscv/*.o
	@rm -f $(TARGET) mag
	@echo "✅ Clean!"

# ── تثبيت ──
install: $(TARGET) mag
	@echo "📦 Remove last version..."
	@sudo rm -f /usr/local/bin/magc /usr/local/bin/mag
	@sudo rm -f /bin/magc /bin/mag
	@echo "📦 Installing magnetar..."
	@sudo install -m 755 $(TARGET) /usr/local/bin/
	@sudo install -m 755 mag /usr/local/bin/
	@sudo install -m 755 $(TARGET) /bin/
	@sudo install -m 755 mag /bin/
	@echo "📦 Installing magnetar lib..."
	@sudo mkdir -p /usr/local/lib/magnetar/lib
	@sudo mkdir -p /usr/lib/magnetar/lib
	@sudo cp lib/*.mg /usr/local/lib/magnetar/lib/ 2>/dev/null || true
	@sudo cp lib/*.mg /usr/lib/magnetar/lib/ 2>/dev/null || true
	@echo "✅ Magnetar installed! Use 'magc' and 'mag' anywhere."

# ── إزالة التثبيت ──
uninstall:
	@echo "🗑️  Uninstalling magnetar..."
	@sudo rm -f /usr/local/bin/magc /usr/local/bin/mag
	@sudo rm -f /usr/bin/magc /usr/bin/mag
	@echo "🗑️  Uninstalling magnetar lib..."
	@sudo rm -rf /usr/lib/magnetar
	@sudo rm -rf /usr/local/lib/magnetar
	@sudo rm -f /usr/local/share/man/man1/magnetar.1 2>/dev/null || true
	@sudo rm -f /usr/share/bash-completion/completions/magnetar 2>/dev/null || true
	@echo "✅ Magnetar uninstalled!"

# ── اختبار ──

# ── معلومات ──
info:
	@echo "⚡ Magnetar Compiler"
	@echo "  Version:    $(shell ./magc --version 2>/dev/null || echo 'not built')"
	@echo "  Binary:     $(shell which magc 2>/dev/null || echo 'not installed')"
	@echo "  Libraries:  $(shell ls /usr/local/lib/magnetar/lib/ 2>/dev/null || echo 'none')"

# ── مساعدة ──
help:
	@echo "⚡ magnetar Compiler Build System"
	@echo ""
	@echo "  make          - Build Magnetar"
	@echo "  make clean    - Clean build files"
	@echo "  make install  - Install to /usr/local/bin"
	@echo "  make uninstall- Remove from system"
	@echo "  make test     - Run test with hello.mg"
	@echo "  make info     - Show installation info"
	@echo "  make help     - Show this message"

.PHONY: all clean install uninstall test info help
