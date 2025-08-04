/*
    RawUnravel - rtprocess_wrapper.mm
    ---------------------------------
    Copyright (C) 2025 Richard Barber

    This file is part of RawUnravel.

    RawUnravel is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    RawUnravel is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with RawUnravel.  If not, see <https://www.gnu.org/licenses/>.
*/

// MARK: - C++ Demosaic Wrapper for librtprocess
//
// This wrapper provides a simple context-based API for Swift/ObjC to call
// Bayer (or X-Trans) demosaicing routines in librtprocess, with efficient
// buffer management and pixel-by-pixel access.

#include "rtprocess_wrapper.h"
#include "librtprocess.h"

#include <vector>
#include <functional>
#include <cstring>

// MARK: - RPContext: Container for per-image buffers and state
//
// This context holds all working image planes (RAW and RGB) for one demosaic run.
struct RPContext {
    int width;   // Image width in pixels
    int height;  // Image height in pixels

    // RAW Bayer input, and demosaiced output planes
    std::vector<std::vector<float>> raw;
    std::vector<std::vector<float>> red, green, blue;

    // Color Filter Array pattern, default RGGB
    unsigned cfarray[2][2] = { {0, 1}, {1, 2} };

    // Construct empty context with all planes zeroed
    RPContext(int w, int h) : width(w), height(h) {
        raw.resize(height, std::vector<float>(width, 0));
        red.resize(height, std::vector<float>(width, 0));
        green.resize(height, std::vector<float>(width, 0));
        blue.resize(height, std::vector<float>(width, 0));
    }

    // Run Bayer demosaic, using librtprocess bayerfast
    bool run() {
        // Prepare C array-of-pointers for each scanline (librtprocess API expects this)
        const float* rawPtrs[height];
        float* rPtrs[height], *gPtrs[height], *bPtrs[height];

        for (int y = 0; y < height; ++y) {
            rawPtrs[y] = raw[y].data();
            rPtrs[y] = red[y].data();
            gPtrs[y] = green[y].data();
            bPtrs[y] = blue[y].data();
        }

        // Dummy cancellation callback (always returns false)
        auto dummyCancel = [](double) { return false; };

        // Call bayerfast_demosaic from librtprocess
        auto err = bayerfast_demosaic(
            width, height, rawPtrs, rPtrs, gPtrs, bPtrs,
            cfarray, dummyCancel, 1.0
        );

        return err == RP_NO_ERROR;
    }
};

// MARK: - C API for Swift/ObjC FFI (extern "C")
//
// These functions create, destroy, and operate on RPContext objects
// from C/ObjC/Swift code. Use void* for context pointer for ABI safety.

extern "C" {

/// Allocate a new RPContext for an image of given width/height.
/// Returns opaque pointer for future calls.
void* rp_create_context(int width, int height) {
    return new RPContext(width, height);
}

/// Set a single RAW Bayer pixel at (x,y).
void rp_set_raw_pixel(void* ctx, int x, int y, float value) {
    auto* c = static_cast<RPContext*>(ctx);
    if (x < c->width && y < c->height) {
        c->raw[y][x] = value;
    }
}

/// Run the demosaic algorithm (returns 0 on success).
int rp_run_demosaic(void* ctx) {
    auto* c = static_cast<RPContext*>(ctx);
    return c->run() ? 0 : -1;
}

/// Get demosaiced RGB pixel at (x,y).
void rp_get_rgb_pixel(void* ctx, int x, int y, float* r, float* g, float* b) {
    auto* c = static_cast<RPContext*>(ctx);
    if (x < c->width && y < c->height) {
        *r = c->red[y][x];
        *g = c->green[y][x];
        *b = c->blue[y][x];
    }
}

/// Free/destroy a context.
void rp_destroy_context(void* ctx) {
    delete static_cast<RPContext*>(ctx);
}

} // extern "C"
