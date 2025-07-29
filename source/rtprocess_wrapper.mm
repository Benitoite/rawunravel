#include "rtprocess_wrapper.h"
#include "librtprocess.h"

#include <vector>
#include <functional>
#include <cstring>

struct RPContext {
    int width;
    int height;
    std::vector<std::vector<float>> raw;
    std::vector<std::vector<float>> red, green, blue;
    unsigned cfarray[2][2] = { {0, 1}, {1, 2} }; // RGGB pattern

    RPContext(int w, int h) : width(w), height(h) {
        raw.resize(height, std::vector<float>(width, 0));
        red.resize(height, std::vector<float>(width, 0));
        green.resize(height, std::vector<float>(width, 0));
        blue.resize(height, std::vector<float>(width, 0));
    }

    bool run() {
        const float* rawPtrs[height];
        float* rPtrs[height], *gPtrs[height], *bPtrs[height];

        for (int y = 0; y < height; ++y) {
            rawPtrs[y] = raw[y].data();
            rPtrs[y] = red[y].data();
            gPtrs[y] = green[y].data();
            bPtrs[y] = blue[y].data();
        }

        auto dummyCancel = [](double) { return false; };

        auto err = bayerfast_demosaic(
            width, height, rawPtrs, rPtrs, gPtrs, bPtrs,
            cfarray, dummyCancel, 1.0
        );

        return err == RP_NO_ERROR;
    }
};

extern "C" {

void* rp_create_context(int width, int height) {
    return new RPContext(width, height);
}

void rp_set_raw_pixel(void* ctx, int x, int y, float value) {
    auto* c = static_cast<RPContext*>(ctx);
    if (x < c->width && y < c->height) {
        c->raw[y][x] = value;
    }
}

int rp_run_demosaic(void* ctx) {
    auto* c = static_cast<RPContext*>(ctx);
    return c->run() ? 0 : -1;
}

void rp_get_rgb_pixel(void* ctx, int x, int y, float* r, float* g, float* b) {
    auto* c = static_cast<RPContext*>(ctx);
    if (x < c->width && y < c->height) {
        *r = c->red[y][x];
        *g = c->green[y][x];
        *b = c->blue[y][x];
    }
}

void rp_destroy_context(void* ctx) {
    delete static_cast<RPContext*>(ctx);
}

}
