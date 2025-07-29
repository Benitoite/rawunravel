#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void* rp_create_context(int width, int height);
void rp_set_raw_pixel(void* ctx, int x, int y, float value);
int rp_run_demosaic(void* ctx);
void rp_get_rgb_pixel(void* ctx, int x, int y, float* r, float* g, float* b);
void rp_destroy_context(void* ctx);

#ifdef __cplusplus
}
#endif
