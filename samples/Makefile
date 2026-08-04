# Cross-build the librfnm samples:   . ../cross/env.sh && make
# lrx_probe runs ON the board (local transport); boot_probe can run anywhere with
# TCP reach (cross-built here — run it on the board or another aarch64 host).
BINS = lrx_probe boot_probe

all: $(BINS)

%: %.cpp
	@test -n "$(RFNM_SYSROOT)" || { echo "error: source ../cross/env.sh first"; exit 1; }
	@echo '$(CXX)' | grep -q aarch64 || { echo "error: CXX is '$(CXX)', not the cross compiler - source ../cross/env.sh in THIS shell first"; exit 1; }
	$(CXX) -O2 -std=c++17 $(ARCHFLAGS) -o $@ $< $(CROSS_LDFLAGS) -lrfnm -lpthread

clean:
	rm -f $(BINS)
