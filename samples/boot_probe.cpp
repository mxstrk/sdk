// boot_probe: minimal "is the board ready to stream" probe over TCP transport.
// Prints millisecond milestones relative to process start; exit 0 only if RX data flowed.
//
//   ./boot_probe <board-ip> [nbufs]        e.g.  ./boot_probe 192.168.1.50
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <vector>
#include <string>
#include <librfnm/device.h>
#include <librfnm/constants.h>

static std::chrono::steady_clock::time_point t0;

static double ms(void) {
	return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
}

int main(int argc, char** argv) {
	if(argc < 2) {
		fprintf(stderr, "usage: boot_probe <ip> [nbufs]\n");
		return 2;
	}
	std::string ip = argv[1];
	int want = argc > 2 ? atoi(argv[2]) : 16;
	t0 = std::chrono::steady_clock::now();

	rfnm::device* dev = nullptr;
	try {
		dev = new rfnm::device(rfnm::TRANSPORT_TCP, ip);
	} catch (const std::exception& e) {
		printf("PROBE open_fail %.1f (%s)\n", ms(), e.what());
		return 1;
	} catch (...) {
		printf("PROBE open_fail %.1f\n", ms());
		return 1;
	}
	printf("PROBE open_ok %.1f\n", ms());
	fflush(stdout);

	rfnm_api_failcode ret = dev->set_samp_rate(61440000);
	printf("PROBE samp_rate ret=%d %.1f\n", (int)ret, ms());
	fflush(stdout);
	if(ret) {
		delete dev;
		return 1;
	}

	rfnm::ch_helper rx_ch = dev->rx_ch_helper(0);
	dev->set_rx_channel_status(rx_ch.id, RFNM_CH_RF_ON, RFNM_CH_STREAM_ON);
	dev->set_rx_channel_freq(rx_ch.id, RFNM_MHZ_TO_HZ(2450));
	dev->set_rx_channel_gain(rx_ch.id, 30);
	dev->set_rx_channel_path(rx_ch.id, RFNM_PATH_SMA_A);
	dev->set_rx_channel_fm_notch(rx_ch.id, RFNM_FM_NOTCH_OFF);
	dev->set_rx_channel_rfic_lpf_bw(rx_ch.id, 61);
	ret = dev->apply(rx_ch.apply);
	printf("PROBE apply ret=%d %.1f\n", (int)ret, ms());
	fflush(stdout);
	if(ret) {
		delete dev;
		return 1;
	}

	size_t bufsize = 0;
	uint8_t bpe = 0;
	dev->set_stream_format(rfnm::STREAM_FORMAT_CS16, &bufsize, &bpe);

	const int NB = 1300;	// must exceed librfnm MIN_RX_BUFCNT (1000) or rx_dqbuf silently starves
	std::vector<rfnm::rx_buf> bufs(NB);
	for(int i = 0; i < NB; i++) {
		bufs[i].buf = (uint8_t*)malloc(bufsize);
		dev->rx_qbuf(&bufs[i], true);
	}
	dev->rx_work_start();
	printf("PROBE work_started %.1f\n", ms());
	fflush(stdout);

	int got = 0;
	double deadline = ms() + 15000.0;
	while(got < want && ms() < deadline) {
		rfnm::rx_buf* rxb;
		if(!dev->rx_dqbuf(&rxb, rx_ch.mask, 100000)) {
			got++;
			dev->rx_qbuf(rxb);
		}
	}
	if(got < want) {
		printf("PROBE stream_timeout got=%d %.1f\n", got, ms());
		fflush(stdout);
		delete dev;
		return 1;
	}
	printf("PROBE stream_ok bufs=%d %.1f\n", got, ms());
	fflush(stdout);
	delete dev;
	printf("PROBE done %.1f\n", ms());
	fflush(stdout);
	return 0;
}
